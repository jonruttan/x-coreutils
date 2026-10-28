; # x-coreutils -- the small tools, as applets
;
; ## cu/etherwake.x -- ether-wake: a Wake-On-LAN magic packet sent
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's ether-wake (networking/ether-wake.c).  MAC is sent a magic
; packet out of -i's interface, eth0 unless named, over a raw packet
; socket: MAC as the destination, or the broadcast address with -b; the
; interface's own address as the source; the type 0x0842; six bytes of
; 0xff, then MAC sixteen times.  -p appends a password, four to six bytes
; as hex pairs joined by colons, or four as a dotted quad.
;
; MAC is read as the C library's ether_aton_r reads it; musl's, which
; busybox is built on, finds no hostname in /etc/ethers, so a MAC not read
; is the usage.  -p's password is read as sscanf's %2x and %u read it; one
; not read is said and left out.  AF_PACKET is Linux's; elsewhere the
; socket is refused as Linux refuses an unknown family.

(module cu/etherwake)

(import cu/cli cu-opts cu-usage)
(import cu/inet inet-set! inet-zeros)
(import cu/inetd in-call)
(import cu/ping pn-byte pn-setopt pn-sol-socket)
(import cu/prims byte-at byte-len cu-err-label cu-libc-sym cu-ptr-call
  cu-ptr-ref cu-str->ptr file-write length libc-strerror reverse string-append
  string-concat)

(def %ew-say (fn (_ msg) (file-write 2 (string-concat (list "ether-wake: " msg "\n")))))
(def %ew-die (fn (_ msg) (do (%ew-say msg) (Err raise (lit ether-wake) msg ()))))
(def %ew-errno-die (fn (_ what r) (%ew-die (string-concat (list what ": " (libc-strerror (Err errno-of r)))))))
(def %ew-usage (fn (_) (Err raise (lit ether-wake-usage) "usage" ())))
(def %ew-fd -1)

; --- reading the words -----------------------------------------------------------------

(def %ew-space? (fn (_ c) (if (= c 32) #t (if (>= c 9) (<= c 13) #f))))
(def %ew-at (fn (_ s i) (if (< i (byte-len s)) (byte-at s i) -1)))
(def %ew-hex
  (fn (_ c)
    (match ((if (>= c 48) (<= c 57) #f) (- c 48))
           ((if (>= c 97) (<= c 102) #f) (- c 87))
           ((if (>= c 65) (<= c 70) #f) (- c 55))
           (#t -1))))
(def %ew-dec (fn (_ c) (if (if (>= c 48) (<= c 57) #f) (- c 48) -1)))

; strtoul in BASE from I: (VALUE . END), END I where no digit is read, VALUE
; held at 4096 past the byte's range; a sign, and 0x in base 16, read as
; strtoul reads them
(def %ew-strtoul
  (fn (_ s i digit base)
    (def j (let skip ((w i)) (if (%ew-space? (%ew-at s w)) (skip (+ w 1)) w)))
    (def sign (%ew-at s j))
    (def k (if (if (= sign 43) #t (= sign 45)) (+ j 1) j))
    (def from (if (if (= base 16) (if (= (%ew-at s k) 48) (if (= (| (%ew-at s (+ k 1)) 32) 120)
                                                              (>= (digit (%ew-at s (+ k 2))) 0) #f) #f) #f)
                (+ k 2) k))
    (let go ((at from) (n 0))
      (let ((d (digit (%ew-at s at))))
        (match ((>= d 0) (go (+ at 1) (if (> n 4095) n (+ (* n base) d))))
               ((= at from) (pair 0 i))
               ((= sign 45) (pair (if (= n 0) 0 4096) at))
               (#t (pair n at)))))))

; ether_aton_r: the six bytes, or nil
(def %ew-aton
  (fn (_ s)
    (let go ((ii 0) (at 0) (out ()))
      (match ((= ii 6) (if (= at (byte-len s)) (reverse out) ()))
             ((if (> ii 0) (not (= (%ew-at s at) 58)) #f) ())
             (#t (let ((r (%ew-strtoul s (if (> ii 0) (+ at 1) at) %ew-hex 16)))
                   (if (> (first r) 255) () (go (+ ii 1) (rest r) (pair (first r) out)))))))))

; one sscanf conversion at I, WIDTH bytes at most past the blanks, -1 for
; none: (VALUE . END), VALUE the low byte, or nil where it fails
(def %ew-scan
  (fn (_ s i width digit base)
    (def j (let skip ((w i)) (if (%ew-space? (%ew-at s w)) (skip (+ w 1)) w)))
    (def stop (if (< width 0) (byte-len s) (+ j width)))
    (def ch (fn (_ k) (if (< k stop) (%ew-at s k) -1)))
    (def neg (= (ch j) 45))
    (def from (if (if neg #t (= (ch j) 43)) (+ j 1) j))
    (let go ((at from) (n 0))
      (let ((d (digit (ch at))))
        (match ((>= d 0) (go (+ at 1) (% (+ (* n base) d) 256)))
               ((= at from) ())
               (neg (pair (% (- 256 n) 256) at))
               (#t (pair n at)))))))

; the conversions of FORMAT's N fields joined by SEP: the values read
; before the first that fails, nil where the word ends before the first
(def %ew-sscanf
  (fn (_ s n sep width digit base)
    (let go ((k 0) (at 0) (out ()))
      (if (= k n) (reverse out)
        (let ((at (if (= k 0) at (if (= (%ew-at s at) sep) (+ at 1) -1))))
          (if (< at 0) (reverse out)
            (let ((r (%ew-scan s at width digit base)))
              (if (null? r) (reverse out) (go (+ k 1) (rest r) (pair (first r) out))))))))))

; get_wol_pw: the password's bytes, nil said where fewer than four are read
(def %ew-password
  (fn (_ s)
    (def mac (%ew-sscanf s 6 58 2 %ew-hex 16))
    (def pw (if (< (List length mac) 4) (%ew-sscanf s 4 46 -1 %ew-dec 10) mac))
    (if (< (List length pw) 4) (do (%ew-say "can't read Wake-On-LAN pass") ()) pw)))

; --- the packet ------------------------------------------------------------------------

(def %ew-put!
  (fn (_ b at bytes)
    (let go ((i at) (l bytes)) (unless (null? l) (do (inet-set! b i (first l) 1) (go (+ i 1) (rest l)))))))

; ioctl on the packet socket with an ifreq naming DEVICE; the result, the
; ifreq after it
(def %ew-ifreq
  (fn (_ device req)
    (let ((ifr (inet-zeros 40)))
      (do (let copy ((i 0)) (when (if (< i (byte-len device)) (< i 15) #f)
                              (do (inet-set! ifr i (byte-at device i) 1) (copy (+ i 1)))))
          (pair (in-call (cu-ptr-call (cu-libc-sym "ioctl") %ew-fd req (cu-str->ptr ifr))) ifr)))))

(def %ew-main
  (fn (_ argv)
    (def o (cu-opts "ether-wake" argv))
    (def ops (Opts operands o))
    (unless (if (pair? ops) (null? (rest ops)) #f) (%ew-usage))
    (def device (let ((v (Opts value o "-i"))) (if (null? v) "eth0" v)))
    (def bcast (Opts on? o "-b"))
    (def pw (let ((p (Opts value o "-p"))) (if (null? p) () (%ew-password p))))
    (set! %ew-fd
      (if os-darwin? (%ew-die (string-append "socket(AF_PACKET,3,0): " (libc-strerror 47)))
        (let ((fd (in-call (cu-ptr-call (cu-libc-sym "socket") 17 3 0))))
          (if (< fd 0) (%ew-errno-die "socket(AF_PACKET,3,0)" fd) fd))))
    (def mac (%ew-aton (first ops)))
    (when (null? mac) (%ew-usage))
    (def n (+ 116 (List length pw)))
    (def pkt (inet-zeros 128))
    (%ew-put! pkt 0 (if bcast (list 255 255 255 255 255 255) mac))
    (%ew-put! pkt 12 (list 8 66 255 255 255 255 255 255))
    (let go ((k 0)) (when (< k 16) (do (%ew-put! pkt (+ 20 (* k 6)) mac) (go (+ k 1)))))
    (let ((hw (%ew-ifreq device 35111)))
      (do (when (< (first hw) 0)
            (%ew-errno-die (string-concat (list "SIOCGIFHWADDR on " device " failed")) (first hw)))
          (let go ((k 0)) (when (< k 6) (do (inet-set! pkt (+ 6 k) (pn-byte (cu-str->ptr (rest hw)) (+ 18 k)) 1) (go (+ k 1)))))))
    (%ew-put! pkt 116 pw)
    (when bcast
      (let ((r (pn-setopt %ew-fd pn-sol-socket 6 1)))
        (when (< r 0) (%ew-say (string-append "SO_BROADCAST: " (libc-strerror (Err errno-of r)))))))
    (def idx (%ew-ifreq device 35123))
    (when (< (first idx) 0) (%ew-errno-die "ioctl 0x8933 failed" (first idx)))
    (def to (inet-zeros 20))
    (inet-set! to 0 17 2)
    (inet-set! to 4 (cu-ptr-ref (cu-str->ptr (rest idx)) 16 4) 4)
    (inet-set! to 11 6 1)
    (let go ((k 0)) (when (< k 6) (do (inet-set! to (+ 12 k) (pn-byte (cu-str->ptr pkt) k) 1) (go (+ k 1)))))
    (let ((r (in-call (cu-ptr-call (cu-libc-sym "sendto") %ew-fd (cu-str->ptr pkt) n 0 (cu-str->ptr to) 20))))
      (when (< r 0) (%ew-errno-die "sendto" r)))
    0))

(def cu-ether-wake
  (fn (_ argv stdin-thunk)
    (set! %ew-fd -1)
    (def status
      (guard (e (match ((eq? (cu-err-label e) (lit ether-wake-usage)) (cu-usage "ether-wake"))
                       ((eq? (cu-err-label e) (lit ether-wake)) 1)
                       (#t (do (unless (< %ew-fd 0) (cu-ptr-call (cu-libc-sym "close") %ew-fd)) (error e)))))
        (%ew-main argv)))
    (unless (< %ew-fd 0) (cu-ptr-call (cu-libc-sym "close") %ew-fd))
    (set! %ew-fd -1)
    status))

(provide cu/etherwake cu-ether-wake)

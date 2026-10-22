; # x-coreutils -- the small tools, as applets
;
; ## cu/inet.x -- what route, arp and the other network tables share
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's libbb/inet_common.c and what networking/interface.c's tables read
; with: the kernel's addresses (an IPv4 one held as the u32 its bytes make,
; its first byte the lowest, as /proc/net prints it), INET_resolve and
; INET_rresolve over the C library's inet_aton, gethostbyname and
; gethostbyaddr, inet_ntop for IPv6, the fields /proc/net's tables print,
; and the buffers and the datagram socket the ioctls take.  A call that
; fails ends the run through the applet's own DIE.

; the value of the hex digits of S
(module cu/inet)

(import cu/prims byte-at byte-len char->integer cu-int->ptr cu-int->str
  cu-ptr->str cu-ptr-call cu-ptr-ref cu-ptr-set! cu-ptr-word cu-str->ptr
  cu-string-type cvt filter libc-strerror map str-make-raw string-append
  string-concat string=? substring)
(import cu/text cu-pad-right cu-pad-zero)

(def inet-hex
  (fn (_ s)
    (let go ((i 0) (n 0))
      (if (>= i (byte-len s)) n
        (let ((c (char->integer (byte-at s i))))
          (go (+ i 1) (+ (* n 16) (match ((<= c 57) (- c 48)) ((<= c 70) (- c 55)) (#t (- c 87))))))))))

; the decimal value of S, a minus sign allowed, as %d reads it
(def inet-dec
  (fn (_ s)
    (if (if (> (byte-len s) 0) (= (byte-at s 0) #\-) #f)
      (- 0 (inet-dec (substring s 1 (byte-len s))))
      (let go ((i 0) (n 0))
        (if (if (< i (byte-len s)) (if (>= (byte-at s i) #\0) (<= (byte-at s i) #\9) #f) #f)
          (go (+ i 1) (+ (* n 10) (- (char->integer (byte-at s i)) 48)))
          n)))))

; N, a 32-bit field, as %d prints it: signed
(def inet-int32 (fn (_ n) (if (>= n 2147483648) (- n 4294967296) n)))

; N, an address as the kernel's tables hold it (its first byte the lowest), dotted
(def inet-dotted
  (fn (_ n)
    (Str8 join "." (map (fn (_ k) (cu-int->str (& (>> n (* 8 k)) 255))) (list 0 1 2 3)))))

; a line's words, split at spaces and tabs
(def inet-words
  (fn (_ line)
    (filter (fn (_ w) (> (byte-len w) 0))
            (Str8 split " " (Str8 replace "\t" " " line)))))

; S padded with spaces to W, cut to P where P is given: %-W.Ps
(def inet-left
  (fn (_ s w . p)
    (cu-pad-right (if (if (null? p) #f (> (byte-len s) (first p))) (substring s 0 (first p)) s) w)))

; four bytes at P as the address they hold, first byte lowest
(def %inet-peek4
  (fn (_ p) (cu-ptr-ref p 0 4)))

; inet_aton: S's address, or nil where S is not one
(def inet-aton
  (fn (_ s)
    (def buf (str-make-raw 4))
    (if (= (in-call (cu-ptr-call (in-c "inet_aton") s (cu-str->ptr buf))) 0) ()
      (%inet-peek4 (cu-str->ptr buf)))))

; gethostbyname: the first address NAME has, or nil
(def inet-host-addr
  (fn (_ name)
    (let ((h (cu-ptr-call (in-c "gethostbyname") name)))
      (if (= h 0) ()
        ; h_addr_list, after h_name, h_aliases, h_addrtype and h_length
        (let ((list (cu-ptr-word (cu-int->ptr h) 24)))
          (%inet-peek4 (cu-int->ptr (cu-ptr-word (cu-int->ptr list) 0))))))))

; gethostbyaddr: the name of address N, or nil
(def inet-addr-host
  (fn (_ n)
    (def buf (str-make-raw 4))
    (cu-ptr-set! (cu-str->ptr buf) 0 n 4)
    (let ((h (cu-ptr-call (in-c "gethostbyaddr") (cu-str->ptr buf) 4 2)))
      (if (= h 0) () (cu-ptr->str (cu-int->ptr (cu-ptr-word (cu-int->ptr h) 0)))))))

; INET_resolve: NAME as (ISNET . ADDRESS) -- isnet 1 for default, 0 for an
; address or a host -- or nil where it resolves to nothing
(def inet-resolve
  (fn (_ name)
    (match
      ((string=? name "default") (pair 1 0))
      ((not (null? (inet-aton name))) (pair 0 (inet-aton name)))
      (#t (let ((a (inet-host-addr name))) (if (null? a) () (pair 0 a)))))))

; INET_rresolve: address N under mask M as a name -- "default" or "*" for
; 0.0.0.0 as WILD says, a host's name where it has one, else dotted
(def inet-rresolve
  (fn (_ n m numeric? wild host?)
    (match
      (numeric? (inet-dotted n))
      ((= n 0) wild)
      ((if host? #t (not (= (& n (^ m 4294967295)) 0)))
        (let ((name (inet-addr-host n))) (if (null? name) (inet-dotted n) name)))
      (#t (inet-dotted n)))))

; 32 hex digits as inet_ntop writes the address they spell
(def inet-ntop6
  (fn (_ hex)
    (def buf (str-make-raw 16))
    (map (fn (_ k) (cu-ptr-set! (cu-str->ptr buf) k (inet-hex (substring hex (* 2 k) (+ (* 2 k) 2))) 1))
         (List range 0 16))
    (inet-ntop6-bytes buf)))

; inet_ntop: the 16 bytes of BUF as an IPv6 address
(def inet-ntop6-bytes
  (fn (_ buf)
    (def out (str-make-raw 64))
    (cu-ptr-call (in-c "inet_ntop") 10 (cu-str->ptr buf) (cu-str->ptr out) 64)
    (cu-ptr->str (cu-str->ptr out))))

; gethostbyaddr: the name of the IPv6 address in the 16 bytes of BUF, or nil
(def inet-addr-host6
  (fn (_ buf)
    (let ((h (cu-ptr-call (in-c "gethostbyaddr") (cu-str->ptr buf) 16 10)))
      (if (= h 0) () (cu-ptr->str (cu-int->ptr (cu-ptr-word (cu-int->ptr h) 0)))))))

; getservbyport: the name of PORT for PROTO, from /etc/services, or nil
(def inet-service
  (fn (_ port proto)
    (let ((s (cu-ptr-call (in-c "getservbyport") (| (<< (& port 255) 8) (& (>> port 8) 255)) proto)))
      (if (= s 0) () (cu-ptr->str (cu-int->ptr (cu-ptr-word (cu-int->ptr s) 0)))))))

; an AF_INET datagram socket, or the run ended as xsocket ends it
(def inet-socket
  (fn (_ family die)
    (let ((fd (in-call (cu-ptr-call (in-c "socket") family 2 0))))
      (if (< fd 0) (die (string-append "socket: " (libc-strerror (Err errno-of fd)))) fd))))

; xioctl: REQ on FD with the buffer, the run ended as busybox's ends it where it
; fails, "ioctl 0x890b failed: REASON"
(def inet-ioctl
  (fn (_ fd req buf die)
    (let ((r (in-call (cu-ptr-call (in-c "ioctl") fd req (cu-str->ptr buf)))))
      (do (cu-ptr-call (in-c "close") fd)
          (when (< r 0) (die (string-concat (list "ioctl 0x" (cvt req cu-string-type 16) " failed: " (libc-strerror (Err errno-of r))))))))))

; a zeroed buffer of N bytes
(def inet-zeros
  (fn (_ n)
    (let ((b (str-make-raw n)))
      (do (map (fn (_ k) (cu-ptr-set! (cu-str->ptr b) k 0 1)) (List range 0 n)) b))))

(def inet-set! (fn (_ buf at v n) (cu-ptr-set! (cu-str->ptr buf) at v n)))

; a sockaddr_in for address N at AT
(def inet-sin!
  (fn (_ buf at n) (do (inet-set! buf at 2 2) (inet-set! buf (+ at 4) n 4))))

; N's four bytes in the other order
(def inet-swap
  (fn (_ n) (| (| (<< (& n 255) 24) (<< (& (>> n 8) 255) 16)) (| (<< (& (>> n 16) 255) 8) (& (>> n 24) 255)))))

; N as eight lowercase hex digits, %.8x
(def inet-hex8 (fn (_ n) (cu-pad-zero (cvt n cu-string-type 16) 8)))

; inet_pton: NAME's IPv6 address written at AT; #f where it is not one
(def inet-pton6!
  (fn (_ buf at name)
    (let ((tmp (str-make-raw 16)))
      (if (= (in-call (cu-ptr-call (in-c "inet_pton") 10 name (cu-str->ptr tmp))) 1)
        (do (map (fn (_ k) (inet-set! buf (+ at k) (cu-ptr-ref (cu-str->ptr tmp) k 1) 1)) (List range 0 16)) #t)
        #f))))

(provide cu/inet inet-addr-host inet-addr-host6 inet-aton inet-dec inet-dotted
  inet-hex inet-hex8 inet-host-addr inet-int32 inet-ioctl inet-left inet-ntop6
  inet-ntop6-bytes inet-pton6! inet-resolve inet-rresolve inet-service
  inet-set! inet-sin! inet-socket inet-swap inet-words inet-zeros)

; # x-coreutils -- the small tools, as applets
;
; ## cu/arp.x -- arp: the kernel's ARP cache, shown and edited
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's arp (networking/arp.c).  With no -s or -d, the entries of
; /proc/net/arp, each `NAME (IP) at HWADDR [TYPE] FLAGS on DEVICE`, those of
; one host, one hardware type (-H) or one device (-i) where asked; -n leaves
; the names out.  -s sets an entry, its hardware address given or (-D) read
; from a device; -d deletes one, the private entry and then the published.
; Both hand the kernel an arpreq through SIOCSARP and SIOCDARP.  -v is
; accepted and, as busybox builds it, says nothing more.

(module cu/arp)

(import cu/cli cu-opts cu-usage)
(import cu/inet inet-dotted inet-hex inet-ioctl inet-resolve inet-rresolve
  inet-set! inet-sin! inet-socket inet-words inet-zeros)
(import cu/inetd in-call)
(import cu/prims byte-at byte-len char->integer cu-err-label cu-int->ptr
  cu-int->str cu-libc-sym cu-lines cu-ptr->str cu-ptr-call cu-ptr-ref
  cu-str->ptr file-or-err file-read-unsized file-write filter length
  libc-strerror map reverse set-first! string-append string-concat string=?
  substring)

(def %ar-say (fn (_ msg) (file-write 2 (string-append "arp: " msg "\n"))))
(def %ar-die (fn (_ msg) (do (%ar-say msg) (Err raise (lit arp) msg ()))))
(def %ar-usage (fn (_) (Err raise (lit arp-usage) "usage" ())))

; the ATF flags arpreq carries
(def %ar-com 2)
(def %ar-perm 4)
(def %ar-publ 8)
(def %ar-trail 16)
(def %ar-netmask 32)

; the hardware types interface.c knows: (NAME ARPHRD ADDRESS-LENGTH)
(def %ar-hwtypes
  (list (list "loop" 772 0) (list "ether" 1 6) (list "ppp" 512 0) (list "unspec" -1 0) (list "sit" 776 0)))

(def %ar-hwtype (fn (_ name) (List find (fn (_ h) (string=? (first h) name)) %ar-hwtypes)))
(def %ar-hwntype (fn (_ type) (List find (fn (_ h) (= (List ref 1 h) type)) %ar-hwtypes)))

; herror's words for the lookup that just failed: the C library's
(def %ar-herror
  (fn (_ name)
    (let ((err (cu-ptr-ref (cu-int->ptr (cu-ptr-call (cu-libc-sym "__h_errno_location"))) 0 4)))
      (%ar-die (string-concat (list name ": " (cu-ptr->str (cu-int->ptr (cu-ptr-call (cu-libc-sym "hstrerror") err)))))))))

; INET_input: NAME's address, the run ended with herror's words where it has none
(def %ar-input
  (fn (_ name) (let ((r (inet-resolve name))) (if (null? r) (%ar-herror name) (rest r)))))

; in_ether: "XX[:]XX[:]...": six bytes, a byte of one digit where a colon
; follows; nil where it is not one
(def ar-ether
  (fn (_ s)
    (def end (byte-len s))
    (def hex (fn (_ i) (if (< i end) (let ((c (| (char->integer (byte-at s i)) 0)))
                                       (match ((if (>= c 48) (<= c 57) #f) (- c 48))
                                              ((if (>= (| c 32) 97) (<= (| c 32) 102) #f) (- (| c 32) 87))
                                              (#t ()))) ())))
    (let go ((i 0) (k 0) (acc ()))
      (if (= k 6) (if (= i end) (reverse acc) ())
        (let ((i0 (if (if (> k 0) (if (< i end) (= (byte-at s i) #\:) #f) #f) (+ i 1) i)))
          (let ((a (hex i0)))
            (if (null? a) ()
              (let ((b (hex (+ i0 1))))
                (if (null? b)
                  ; one digit, a colon or the end after it
                  (if (if (>= (+ i0 1) end) #t (= (byte-at s (+ i0 1)) #\:)) (go (+ i0 1) (+ k 1) (pair a acc)) ())
                  (go (+ i0 2) (+ k 1) (pair (+ (* a 16) b) acc)))))))))))

; --- showing ----------------------------------------------------------------------

; arp_disp: one entry
(def %ar-line
  (fn (_ name ip type flags hwa mask dev)
    (def hw (let ((h (%ar-hwntype type))) (if (null? h) (%ar-hwtype "ether") h)))
    (def labels (filter (fn (_ l) (> (byte-len l) 0))
                        (list (if (= (& flags %ar-perm) 0) "" "PERM") (if (= (& flags %ar-publ) 0) "" "PUP")
                              (if (= (& flags %ar-trail) 0) "" "TRAIL"))))
    (string-concat
      (list name " (" ip ") at "
            (match ((not (= (& flags %ar-com) 0)) (string-concat (list hwa " [" (first hw) "] ")))
                   ((not (= (& flags %ar-publ) 0)) "* ")
                   (#t "<incomplete> "))
            (if (= (& flags %ar-netmask) 0) "" (string-concat (list "netmask " mask " ")))
            (Str8 join " " labels) " on " dev "\n"))))

; arp_show: the cache's entries, those of HOST (an address), HW's type and
; DEVICE where they are given
(def %ar-show
  (fn (_ o host hw device)
    (def text (let ((t (file-or-err (fn (_) (file-read-unsized "/proc/net/arp"))))) (if (Err err? t) "" t)))
    (def rows (filter (fn (_ w) (>= (length w) 4)) (map inet-words (rest (cu-lines text)))))
    ; an entry of another hardware type, another host or another device is
    ; passed over
    (def wanted?
      (fn (_ w)
        (match
          ((if (null? hw) #f (not (= (inet-hex (substring (List ref 1 w) 2 (byte-len (List ref 1 w)))) (List ref 1 hw)))) #f)
          ((if (null? host) #f (not (string=? (first w) host))) #f)
          ((= (byte-len device) 0) #t)
          (#t (string=? (if (>= (length w) 6) (List ref 5 w) "-") device)))))
    (def shown (filter wanted? rows))
    (map (fn (_ w)
           (let ((ip (first w)))
             (file-write 1
               (%ar-line (if (Opts on? o "-n") "?"
                           (let ((a (inet-resolve ip)))
                             (let ((name (if (null? a) ip (inet-rresolve (rest a) 4294967040 #f "default" #f))))
                               (if (string=? name ip) "?" name))))
                         ip (inet-hex (substring (List ref 1 w) 2 (byte-len (List ref 1 w))))
                         (inet-hex (substring (List ref 2 w) 2 (byte-len (List ref 2 w))))
                         (List ref 3 w) (if (>= (length w) 5) (List ref 4 w) "-") (if (>= (length w) 6) (List ref 5 w) "-")))))
         shown)
    (when (if (null? shown) (if (null? hw) (if (null? host) (> (byte-len device) 0) #t) #t) #f)
      (file-write 1 (string-concat (list "No match found in " (cu-int->str (length rows)) " entries\n"))))
    0))

; --- setting and deleting ---------------------------------------------------------

; an arpreq for HOST's address, its device DEV
(def %ar-req
  (fn (_ addr)
    (let ((req (inet-zeros 68))) (do (inet-sin! req 0 addr) req))))

(def %ar-dev! (fn (_ req dev) (map (fn (_ k) (inet-set! req (+ 52 k) (char->integer (byte-at dev k)) 1))
                                    (List range 0 (if (> (byte-len dev) 15) 15 (byte-len dev))))))

; the modifiers after the host and address, as both -s and -d read them:
; (FLAGS-CHANGES DEVICE), each word acting on the request through ON
(def %ar-modifiers
  (fn (self ws req dev on)
    (if (null? ws) dev
      (let ((w (first ws)))
        (match
          ((string=? w "dev") (if (null? (rest ws)) (%ar-usage) (self (rest (rest ws)) req (first (rest ws)) on)))
          ((string=? w "netmask")
            (if (null? (rest ws)) (%ar-usage)
              (do (unless (string=? (first (rest ws)) "255.255.255.255")
                    (do (inet-sin! req 36 (%ar-input (first (rest ws)))) (on "netmask")))
                  (self (rest (rest ws)) req dev on))))
          ((string=? w "dontpub") (do (%ar-say "feature ATF_DONTPUB is not supported") (self (rest ws) req dev on)))
          ((string=? w "auto") (do (%ar-say "feature ATF_MAGIC is not supported") (self (rest ws) req dev on)))
          ((List find (fn (_ k) (string=? k w)) (list "pub" "priv" "temp" "trail"))
            (do (on w) (self (rest ws) req dev on)))
          (#t (%ar-usage)))))))

; arp_set: HOST's entry, at the hardware address the next word gives
(def %ar-set
  (fn (_ o args hw device)
    (def req (%ar-req (%ar-input (first args))))
    (when (null? (rest args)) (%ar-die "need hardware address"))
    (if (Opts on? o "-D") (%ar-devhw! req (first (rest args)) hw)
      (let ((bytes (ar-ether (first (rest args)))))
        (do (when (null? bytes) (%ar-die "invalid hardware address"))
            (inet-set! req 16 1 2)
            (let go ((k 0) (bs bytes)) (unless (null? bs) (do (inet-set! req (+ 18 k) (first bs) 1) (go (+ k 1) (rest bs))))))))
    (def flags (list (| %ar-perm %ar-com)))
    (def on (fn (_ what)
              (set-first! flags
                (match ((string=? what "pub") (| (first flags) %ar-publ)) ((string=? what "priv") (& (first flags) (^ %ar-publ -1)))
                       ((string=? what "temp") (& (first flags) (^ %ar-perm -1))) ((string=? what "trail") (| (first flags) %ar-trail))
                       (#t (| (first flags) %ar-netmask))))))
    (def dev (%ar-modifiers (rest (rest args)) req device on))
    (inet-set! req 32 (first flags) 4)
    (%ar-dev! req dev)
    (inet-ioctl (inet-socket 2 %ar-die) 35157 req %ar-die)
    0))

; arp_getdevhw: IFNAME's hardware address into the request
(def %ar-devhw!
  (fn (_ req ifname hw)
    (def ifr (inet-zeros 40))
    (map (fn (_ k) (inet-set! ifr k (char->integer (byte-at ifname k)) 1)) (List range 0 (if (> (byte-len ifname) 15) 15 (byte-len ifname))))
    (def fd (inet-socket 2 %ar-die))
    (def r (in-call (cu-ptr-call (cu-libc-sym "ioctl") fd 35111 (cu-str->ptr ifr))))
    (cu-ptr-call (cu-libc-sym "close") fd)
    (when (< r 0) (%ar-die (string-concat (list "can't get HW-Address for '" ifname "': " (libc-strerror (Err errno-of r))))))
    (when (if (null? hw) #f (not (= (cu-ptr-ref (cu-str->ptr ifr) 16 2) (List ref 1 hw)))) (%ar-die "protocol type mismatch"))
    (map (fn (_ k) (inet-set! req (+ 16 k) (cu-ptr-ref (cu-str->ptr ifr) (+ 16 k) 1) 1)) (List range 0 16))))

; arp_del: HOST's entry, the private one and then, where asked or that is
; not there, the published
(def %ar-del
  (fn (_ o args hw device)
    (def host (first args))
    (def req (%ar-req (%ar-input host)))
    (unless (null? hw) (inet-set! req 16 (& (List ref 1 hw) 65535) 2))
    (def kind (list 0 %ar-perm))
    (def on (fn (_ what)
              (match ((string=? what "pub") (set-first! kind (| (first kind) 1)))
                     ((string=? what "priv") (set-first! kind (| (first kind) 2)))
                     ((string=? what "temp") (set-first! (rest kind) (& (first (rest kind)) (^ %ar-perm -1))))
                     ((string=? what "trail") (set-first! (rest kind) (| (first (rest kind)) %ar-trail)))
                     (#t (set-first! (rest kind) (| (first (rest kind)) %ar-netmask))))))
    (def dev (%ar-modifiers (rest args) req device on))
    (def which (if (= (first kind) 0) 3 (first kind)))
    (%ar-dev! req dev)
    (def try (fn (_ flags)
               (do (inet-set! req 32 flags 4)
                   (let ((fd (inet-socket 2 %ar-die)))
                     (let ((r (in-call (cu-ptr-call (cu-libc-sym "ioctl") fd 35155 (cu-str->ptr req)))))
                       (do (cu-ptr-call (cu-libc-sym "close") fd)
                           (if (< r 0) (Err errno-of r) 0)))))))
    (def none (fn (_) (do (file-write 1 (string-concat (list "No ARP entry for " host "\n"))) 255)))
    (def flags (first (rest kind)))
    (def priv (if (= (& which 2) 0) () (try flags)))
    (match
      ((if (null? priv) #f (= priv 0)) 0)
      ((if (null? priv) #f (not (= priv 6))) (%ar-die (string-append "SIOCDARP(priv): " (libc-strerror priv))))
      ((if (null? priv) #f (= (& which 1) 0)) (none))
      (#t (let ((pub (try (| flags %ar-publ))))
            (match ((= pub 0) 0) ((= pub 6) (none)) (#t (%ar-die (string-append "SIOCDARP(pub): " (libc-strerror pub))))))))))

(def cu-arp
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "arp" argv))
    (def ops (Opts operands o))
    (def af (let ((a (Opts value o "-A"))) (if (null? a) (Opts value o "-p") a)))
    (def hwname (let ((h (Opts value o "-H"))) (if (null? h) (Opts value o "-t") h)))
    (def device (let ((i (Opts value o "-i"))) (if (null? i) "" i)))
    (guard (e (match ((eq? (cu-err-label e) (lit arp-usage)) (cu-usage "arp"))
                     ((eq? (cu-err-label e) (lit arp)) 1)
                     (#t (error e))))
      (do (unless (if (null? af) #t (List find (fn (_ a) (string=? a af)) (list "inet" "inet6" "unspec")))
            (%ar-die (string-append af ": unknown address family")))
          (def hw (if (null? hwname) () (let ((h (%ar-hwtype hwname))) (if (null? h) (%ar-die (string-append hwname ": unknown hardware type")) h))))
          (unless (if (null? af) #t (string=? af "inet")) (%ar-die (string-append af ": kernel only supports 'inet'")))
          (unless (if (null? hw) #t (> (List ref 2 hw) 0)) (%ar-die (string-append hwname ": hardware type without ARP support")))
          (match
            ((if (Opts on? o "-d") #t (Opts on? o "-s"))
              (if (null? ops) (%ar-die "need host name")
                (if (Opts on? o "-s") (%ar-set o ops hw device) (%ar-del o ops hw device))))
            (#t (%ar-show o (if (null? ops) () (inet-dotted (%ar-input (first ops)))) hw device)))))))

(provide cu/arp ar-ether cu-arp)

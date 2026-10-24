; # x-coreutils -- the small tools, as applets
;
; ## cu/route.x -- route: the kernel's routing tables, shown and edited
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's route (networking/route.c).  With no verb, the IPv4 table from
; /proc/net/route, or with -A inet6 the IPv6 one from /proc/net/ipv6_route;
; -n leaves the addresses as numbers, -e shows MSS, window and irtt in place
; of metric, ref and use.  `add` and `del` (or `delete`) hand the kernel an
; rtentry, or for inet6 an in6_rtmsg, through the SIOCADDRT and SIOCDELRT
; ioctls on a datagram socket.  Names are the C library's: inet_aton,
; gethostbyname and gethostbyaddr, through the FFI, as busybox calls them.

(module cu/route)

(import cu/cli cu-opts cu-usage)
(import cu/dump dp-find)
(import cu/inet inet-dec inet-dotted inet-hex inet-hex8 inet-int32 inet-ioctl
  inet-left inet-ntop6 inet-pton6! inet-resolve inet-rresolve inet-set!
  inet-sin! inet-socket inet-swap inet-words inet-zeros)
(import cu/inetd in-c in-call)
(import cu/prims byte-at byte-len char->integer cu-err-label cu-int->str
  cu-lines cu-ptr-call cu-ptr-ref cu-ptr-set! cu-str->ptr file-or-err
  file-read-unsized file-write length libc-strerror map string-append
  string-concat string=? substring)
(import cu/strings cu-range-number)
(import cu/telnetd td-ptr->int)
(import cu/text cu-pad-left)

(def %rt-say (fn (_ msg) (file-write 2 (string-append "route: " msg "\n"))))

; an error that ends the run, as bb_error_msg_and_die
(def %rt-die (fn (_ msg) (do (%rt-say msg) (Err raise (lit route) msg ()))))

; --- display ----------------------------------------------------------------------

; set_flags: the letters of FLAGS, in busybox's order
(def %rt-flagchars
  (list (pair 1 "U") (pair 2 "G") (pair 4 "H") (pair 8 "R") (pair 16 "D") (pair 32 "M")
        (pair 65536 "D") (pair 262144 "A") (pair 16777216 "C") (pair 512 "!") (pair 2097152 "n")))

(def %rt-flags
  (fn (_ flags)
    (string-concat (map (fn (_ fc) (if (= (& flags (first fc)) 0) "" (rest fc))) %rt-flagchars))))

; bb_displayroutes: the IPv4 table, -e's columns where EXTRA?
(def rt-show4
  (fn (_ numeric? extra?)
    (def text (file-or-err (fn (_) (file-read-unsized "/proc/net/route"))))
    (file-write 1 (string-append "Kernel IP routing table\nDestination     Gateway         Genmask         Flags "
                                 (if extra? "  MSS Window  irtt" "Metric Ref    Use") " Iface\n"))
    (unless (Err err? text)
      (map (fn (_ line)
             (let ((w (inet-words line)))
               (when (= (length w) 11)
                 (let ((d (inet-hex (List ref 1 w))) (g (inet-hex (List ref 2 w)))
                       (fl (inet-hex (List ref 3 w))) (m (inet-hex (List ref 7 w))))
                   (unless (= (& fl 1) 0)
                     (let ((letters (%rt-flags (& fl 63))))
                       (file-write 1
                         (string-concat
                           (list (inet-left (inet-rresolve d m numeric? "default" #f) 15 15) " "
                                 (inet-left (inet-rresolve g m numeric? "*" #t) 15 15) " "
                                 (inet-left (inet-dotted m) 16)
                                 (inet-left (if (= (& fl 512) 0) letters
                                             (string-append "!" (substring letters 1 (byte-len letters))))
                                           6)
                                 (if extra?
                                   (string-concat
                                     (list (cu-pad-left (List ref 8 w) 5) " " (inet-left (List ref 9 w) 5) " "
                                           (cu-pad-left (List ref 10 w) 6)))
                                   (string-concat
                                     (list (inet-left (cu-int->str (inet-dec (List ref 6 w))) 6) " "
                                           (inet-left (cu-int->str (inet-dec (List ref 4 w))) 2) " "
                                           (cu-pad-left (cu-int->str (inet-dec (List ref 5 w))) 7))))
                                 " " (List ref 0 w) "\n")))))))))
           (rest (cu-lines text))))
    0))

; INET6_displayroutes: every route of /proc/net/ipv6_route, up or not
(def %rt-show6
  (fn (_)
    (def text (file-or-err (fn (_) (file-read-unsized "/proc/net/ipv6_route"))))
    (file-write 1 (string-concat (list "Kernel IPv6 routing table\n" (inet-left "Destination" 44) (inet-left "Next Hop" 40)
                                       "Flags Metric Ref    Use Iface\n")))
    (unless (Err err? text)
      (map (fn (_ line)
             (let ((w (inet-words line)))
               (when (= (length w) 10)
                 (file-write 1
                   (string-concat
                     (list (inet-left (string-concat (list (inet-ntop6 (List ref 0 w)) "/" (cu-int->str (inet-hex (List ref 1 w))))) 43) " "
                           (inet-left (inet-ntop6 (List ref 4 w)) 39) " "
                           (inet-left (%rt-flags (& (inet-hex (List ref 8 w)) 19202567)) 5) " "
                           (inet-left (cu-int->str (inet-int32 (inet-hex (List ref 5 w)))) 6) " "
                           (inet-left (cu-int->str (inet-int32 (inet-hex (List ref 6 w)))) 2) " "
                           (cu-pad-left (cu-int->str (inet-int32 (inet-hex (List ref 7 w)))) 7) " "
                           (inet-left (List ref 9 w) 8) "\n"))))))
           (cu-lines text)))
    0))

; --- the ioctls --------------------------------------------------------------------

; kw_lookup: the keywords of route's tables, each (WORD CODE TAKES-ARG?)
(def %rt-keywords
  (list (list "metric" (lit metric) #t) (list "netmask" (lit netmask) #t) (list "gw" (lit gw) #t)
        (list "gateway" (lit gw) #t) (list "mss" (lit mss) #t) (list "window" (lit window) #t)
        (list "irtt" (lit irtt) #t) (list "dev" (lit dev) #t) (list "device" (lit dev) #t)
        (list "reject" (lit reject) #f) (list "mod" (lit mod) #f) (list "dyn" (lit dyn) #f)
        (list "reinstate" (lit reinstate) #f)))

(def %rt-keyword
  (fn (_ w) (List find (fn (_ k) (string=? (first k) w)) %rt-keywords)))

; a number for KEYWORD's argument, the run ended as busybox ends it where it is
; not one or not in LO..HI
(def %rt-number
  (fn (_ s lo hi)
    (let ((n (cu-range-number "route" s lo hi)))
      (if (null? n) (Err raise (lit route) "number" ()) n))))

; the usage, the run ended with status 1
(def %rt-usage (fn (_) (Err raise (lit route-usage) "usage" ())))

; INET_setroute: ADD? or delete, from the words ARGS
(def %rt-set4
  (fn (_ add? args)
    (def xflag (match ((string=? (first args) "-net") 1) ((string=? (first args) "-host") 2) (#t 0)))
    (def args1 (if (= xflag 0) args (rest args)))
    (when (null? args1) (%rt-usage))
    (def rt (inet-zeros 120))
    (def target (first args1))
    (def slash (dp-find target 0 #\/))
    (def mask (if (< slash 0) () (let ((n (%rt-number (substring target (+ slash 1) (byte-len target)) 0 32)))
                                   (& (<< (- 4294967296 1) (- 32 n)) 4294967295))))
    (def host (if (< slash 0) target (substring target 0 slash)))
    (def resolved (%rt-resolve! host))
    (def dst (rest resolved))
    (inet-sin! rt 8 dst)
    ; a prefix's mask, network order, its first byte the highest
    (def mask-ne (if (null? mask) () (inet-swap mask)))
    (unless (null? mask-ne) (inet-sin! rt 40 mask-ne))
    (def isnet (if (= xflag 0) (first resolved) (& xflag 1)))
    ; the state each word leaves: (FLAGS MASK NETMASK-WORD DEVICE)
    (let go ((ws (rest args1)) (st (list (if (= isnet 0) 5 1) mask-ne (if (null? mask) "default" ()) ())))
      (if (null? ws)
        (let ((flags (List ref 0 st)) (dev (List ref 3 st)))
          (%rt-finish4 add? rt dst (if (if (= (& flags 512) 0) #t (not (null? dev))) dev "lo")
                       flags (List ref 1 st) (List ref 2 st)))
        (let ((r (%rt-word4 rt ws st))) (go (first r) (rest r)))))))

; NAME's address, or the run ended with "resolving NAME"
(def %rt-resolve!
  (fn (_ name)
    (let ((r (inet-resolve name))) (if (null? r) (%rt-die (string-append "resolving " name)) r))))

; the flag a keyword that takes no argument sets
(def %rt-flag-of
  (fn (_ code) (match ((eq? code (lit reject)) 512) ((eq? code (lit mod)) 32) ((eq? code (lit dyn)) 16) (#t 8))))

; the words WS read from the first, into RT: (WORDS-LEFT . STATE), as
; INET_setroute's loop reads them
(def %rt-word4
  (fn (_ rt ws st)
    (def flags (List ref 0 st))
    (def m (List ref 1 st))
    (def nm (List ref 2 st))
    (def dev (List ref 3 st))
    (def k (%rt-keyword (first ws)))
    (def code (if (null? k) () (List ref 1 k)))
    (def arg (if (null? (rest ws)) () (first (rest ws))))
    (def next (fn (_ fl m2 nm2 dev2) (pair (rest (rest ws)) (list fl m2 nm2 dev2))))
    (match
      ((if (null? k) #f (not (List ref 2 k))) (pair (rest ws) (list (| flags (%rt-flag-of code)) m nm dev)))
      ((if (null? k) #f (null? arg)) (%rt-usage))
      ((eq? code (lit metric))
        (do (inet-set! rt 80 (+ (%rt-number arg 0 4294967295) 1) 2) (next flags m nm dev)))
      ((eq? code (lit netmask))
        (do (unless (null? m) (%rt-usage))
            (let ((r (%rt-resolve! arg))) (do (inet-sin! rt 40 (rest r)) (next flags (rest r) arg dev)))))
      ((eq? code (lit gw))
        (do (unless (= (& flags 2) 0) (%rt-usage))
            (let ((r (%rt-resolve! arg)))
              (do (unless (= (first r) 0) (%rt-die (string-concat (list "gateway " arg " is a NETWORK"))))
                  (inet-sin! rt 24 (rest r))
                  (next (| flags 2) m nm dev)))))
      ((eq? code (lit mss)) (do (inet-set! rt 96 (%rt-number arg 64 32768) 8) (next (| flags 64) m nm dev)))
      ((eq? code (lit window)) (do (inet-set! rt 104 (%rt-number arg 128 2147483647) 8) (next (| flags 128) m nm dev)))
      ((eq? code (lit irtt)) (do (inet-set! rt 112 (%rt-number arg 0 4294967295) 2) (next (| flags 256) m nm dev)))
      ; a device: after dev, or the last word when it is no keyword
      ((if (null? dev) (if (null? k) (null? (rest ws)) (eq? code (lit dev))) #f)
        (if (null? k) (pair (rest ws) (list flags m nm (first ws))) (next flags m nm arg)))
      (#t (%rt-usage)))))

; the checks after the words, the host route's mask, and the ioctl
(def %rt-finish4
  (fn (_ add? rt dst dev flags m nm)
    (do (unless (null? m)
          (let ((mask (^ (inet-swap m) 4294967295)))
            (do (when (if (= (& flags 4) 0) #f (not (= mask 4294967295)))
                  (%rt-die (string-concat (list "netmask " (inet-hex8 mask) " and host route conflict"))))
                (unless (= (& mask (+ mask 1)) 0) (%rt-die (string-append "bogus netmask " (if (null? nm) "(null)" nm))))
                (unless (= (& dst (^ m 4294967295)) 0) (%rt-die "netmask and route address conflict")))))
        (when (if add? (not (= (& flags 4) 0)) #f) (inet-sin! rt 40 4294967295))
        (inet-set! rt 56 flags 2)
        (def devbuf (if (null? dev) () (string-append dev "")))
        (unless (null? devbuf) (cu-ptr-set! (cu-str->ptr rt) 88 (td-ptr->int (cu-str->ptr devbuf)) 8))
        (inet-ioctl (inet-socket 2 %rt-die) (if add? 35083 35084) rt %rt-die)
        0)))

; INET6_setroute: ADD? or delete, from the words ARGS
(def %rt-set6
  (fn (_ add? args)
    (def rt (inet-zeros 80))
    (def target (first args))
    (def slash (dp-find target 0 #\/))
    (def plen (match ((string=? target "default") 0) ((< slash 0) 128)
                     (#t (%rt-number (substring target (+ slash 1) (byte-len target)) 0 128))))
    (def host (if (< slash 0) target (substring target 0 slash)))
    (unless (string=? target "default")
      (unless (inet-pton6! rt 0 host) (%rt-die (string-append "resolving " host))))
    (inet-set! rt 52 plen 2)
    (inet-set! rt 56 1 4)
    (let go ((ws (rest args)) (flags (if (= plen 128) 5 1)) (dev ()))
      (if (null? ws)
        (do (inet-set! rt 72 flags 4)
            (def fd (inet-socket 10 %rt-die))
            (unless (null? dev)
              (let ((ifr (inet-zeros 40)))
                (do (map (fn (_ k) (inet-set! ifr k (char->integer (byte-at dev k)) 1)) (List range 0 (if (> (byte-len dev) 15) 15 (byte-len dev))))
                    (let ((r (in-call (cu-ptr-call (in-c "ioctl") fd 35123 (cu-str->ptr ifr)))))
                      (when (< r 0) (%rt-die (string-concat (list "ioctl 0x8933 failed: " (libc-strerror (Err errno-of r)))))))
                    (inet-set! rt 76 (cu-ptr-ref (cu-str->ptr ifr) 16 4) 4))))
            (inet-ioctl fd (if add? 35083 35084) rt %rt-die)
            0)
        (let ((k (%rt-keyword (first ws))))
          (match
            ((if (null? k) #f (if (eq? (List ref 1 k) (lit mod)) #t (eq? (List ref 1 k) (lit dyn))))
              (go (rest ws) (| flags (if (eq? (List ref 1 k) (lit mod)) 32 16)) dev))
            ((if (null? k) #f (if (List ref 2 k) (null? (rest ws)) #f)) (%rt-usage))
            ((if (null? k) #f (eq? (List ref 1 k) (lit metric)))
              (do (inet-set! rt 56 (%rt-number (first (rest ws)) 0 4294967295) 4) (go (rest (rest ws)) flags dev)))
            ((if (null? k) #f (eq? (List ref 1 k) (lit gw)))
              (do (unless (= (& flags 2) 0) (%rt-usage))
                  (unless (inet-pton6! rt 32 (first (rest ws))) (%rt-die (string-append "resolving " (first (rest ws)))))
                  (go (rest (rest ws)) (| flags 2) dev)))
            ((if (null? dev) (if (null? k) (null? (rest ws)) (eq? (List ref 1 k) (lit dev))) #f)
              (if (null? k) (go (rest ws) flags (first ws)) (go (rest (rest ws)) flags (first (rest ws)))))
            (#t (%rt-usage))))))))

(def cu-route
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "route" argv))
    (def family (Opts value o "-A"))
    (def ops (Opts operands o))
    (def six? (if (null? family) #f (string=? family "inet6")))
    (match
      ((if (null? family) #f (if (string=? family "inet") #f (not six?))) (cu-usage "route"))
      ((null? ops) (if six? (%rt-show6) (rt-show4 (Opts on? o "-n") (Opts on? o "-e"))))
      (#t
        (let ((verb (first ops)))
          (if (if (if (string=? verb "add") #f (if (string=? verb "del") #f (not (string=? verb "delete")))) #t (null? (rest ops)))
            (cu-usage "route")
            (guard (e (if (eq? (cu-err-label e) (lit route-usage)) (cu-usage "route")
                        (if (eq? (cu-err-label e) (lit route)) 1 (error e))))
              (if six? (%rt-set6 (string=? verb "add") (rest ops)) (%rt-set4 (string=? verb "add") (rest ops))))))))))

(provide cu/route cu-route rt-show4)

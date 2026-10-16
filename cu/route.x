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

(def %rt-say (fn (_ msg) (file-write 2 (string-append "route: " msg "\n"))))

; an error that ends the run, as bb_error_msg_and_die
(def %rt-die (fn (_ msg) (do (%rt-say msg) (Err raise (lit route) msg ()))))

; the value of the hex digits of S
(def %rt-hex
  (fn (_ s)
    (let go ((i 0) (n 0))
      (if (>= i (byte-len s)) n
        (let ((c (char->integer (byte-at s i))))
          (go (+ i 1) (+ (* n 16) (match ((<= c 57) (- c 48)) ((<= c 70) (- c 55)) (#t (- c 87))))))))))

; the decimal value of S, a minus sign allowed, as %d reads it
(def %rt-dec
  (fn (_ s)
    (if (if (> (byte-len s) 0) (= (byte-at s 0) #\-) #f)
      (- 0 (%rt-dec (substring s 1 (byte-len s))))
      (let go ((i 0) (n 0))
        (if (if (< i (byte-len s)) (if (>= (byte-at s i) #\0) (<= (byte-at s i) #\9) #f) #f)
          (go (+ i 1) (+ (* n 10) (- (char->integer (byte-at s i)) 48)))
          n)))))

; N, a 32-bit field, as %d prints it: signed
(def %rt-int32 (fn (_ n) (if (>= n 2147483648) (- n 4294967296) n)))

; N, an address as the kernel's tables hold it (its first byte the lowest), dotted
(def %rt-dotted
  (fn (_ n)
    (Str8 join "." (map (fn (_ k) (%cu-int->str (& (>> n (* 8 k)) 255))) (list 0 1 2 3)))))

; a line's words, split at spaces and tabs
(def %rt-words
  (fn (_ line)
    (filter (fn (_ w) (> (byte-len w) 0))
            (Str8 split " " (Str8 replace "\t" " " line)))))

; S padded with spaces to W, cut to P where P is given: %-W.Ps
(def %rt-left
  (fn (_ s w . p)
    (%cu-pad-right (if (if (null? p) #f (> (byte-len s) (first p))) (substring s 0 (first p)) s) w)))

; --- the C library ----------------------------------------------------------------

; four bytes at P as the address they hold, first byte lowest
(def %rt-peek4
  (fn (_ p) (%cu-ptr-ref p 0 4)))

; inet_aton: S's address, or nil where S is not one
(def %rt-aton
  (fn (_ s)
    (def buf (%str-make-raw 4))
    (if (= (%in-call (%cu-ptr-call (%in-c "inet_aton") s (%cu-str->ptr buf))) 0) ()
      (%rt-peek4 (%cu-str->ptr buf)))))

; gethostbyname: the first address NAME has, or nil
(def %rt-host-addr
  (fn (_ name)
    (let ((h (%cu-ptr-call (%in-c "gethostbyname") name)))
      (if (= h 0) ()
        ; h_addr_list, after h_name, h_aliases, h_addrtype and h_length
        (let ((list (%cu-ptr-word (%cu-int->ptr h) 24)))
          (%rt-peek4 (%cu-int->ptr (%cu-ptr-word (%cu-int->ptr list) 0))))))))

; gethostbyaddr: the name of address N, or nil
(def %rt-addr-host
  (fn (_ n)
    (def buf (%str-make-raw 4))
    (%cu-ptr-set! (%cu-str->ptr buf) 0 n 4)
    (let ((h (%cu-ptr-call (%in-c "gethostbyaddr") (%cu-str->ptr buf) 4 2)))
      (if (= h 0) () (%cu-ptr->str (%cu-int->ptr (%cu-ptr-word (%cu-int->ptr h) 0)))))))

; INET_resolve: NAME as (ISNET . ADDRESS) -- isnet 1 for default, 0 for an
; address or a host -- or nil where it resolves to nothing
(def %rt-resolve
  (fn (_ name)
    (match
      ((string=? name "default") (pair 1 0))
      ((not (null? (%rt-aton name))) (pair 0 (%rt-aton name)))
      (#t (let ((a (%rt-host-addr name))) (if (null? a) () (pair 0 a)))))))

; INET_rresolve: address N under mask M as a name -- "default" or "*" for
; 0.0.0.0 as WILD says, a host's name where it has one, else dotted
(def %rt-rresolve
  (fn (_ n m numeric? wild host?)
    (match
      (numeric? (%rt-dotted n))
      ((= n 0) wild)
      ((if host? #t (not (= (& n (^ m 4294967295)) 0)))
        (let ((name (%rt-addr-host n))) (if (null? name) (%rt-dotted n) name)))
      (#t (%rt-dotted n)))))

; --- display ----------------------------------------------------------------------

; set_flags: the letters of FLAGS, in busybox's order
(def %rt-flagchars
  (list (pair 1 "U") (pair 2 "G") (pair 4 "H") (pair 8 "R") (pair 16 "D") (pair 32 "M")
        (pair 65536 "D") (pair 262144 "A") (pair 16777216 "C") (pair 512 "!") (pair 2097152 "n")))

(def %rt-flags
  (fn (_ flags)
    (string-concat (map (fn (_ fc) (if (= (& flags (first fc)) 0) "" (rest fc))) %rt-flagchars))))

; bb_displayroutes: the IPv4 table, -e's columns where EXTRA?
(def %rt-show4
  (fn (_ numeric? extra?)
    (def text (file-or-err (fn (_) (file-read-unsized "/proc/net/route"))))
    (file-write 1 (string-append "Kernel IP routing table\nDestination     Gateway         Genmask         Flags "
                                 (if extra? "  MSS Window  irtt" "Metric Ref    Use") " Iface\n"))
    (unless (Err err? text)
      (map (fn (_ line)
             (let ((w (%rt-words line)))
               (when (= (length w) 11)
                 (let ((d (%rt-hex (List ref 1 w))) (g (%rt-hex (List ref 2 w)))
                       (fl (%rt-hex (List ref 3 w))) (m (%rt-hex (List ref 7 w))))
                   (unless (= (& fl 1) 0)
                     (let ((letters (%rt-flags (& fl 63))))
                       (file-write 1
                         (string-concat
                           (list (%rt-left (%rt-rresolve d m numeric? "default" #f) 15 15) " "
                                 (%rt-left (%rt-rresolve g m numeric? "*" #t) 15 15) " "
                                 (%rt-left (%rt-dotted m) 16)
                                 (%rt-left (if (= (& fl 512) 0) letters
                                             (string-append "!" (substring letters 1 (byte-len letters))))
                                           6)
                                 (if extra?
                                   (string-concat
                                     (list (%cu-pad-left (List ref 8 w) 5) " " (%rt-left (List ref 9 w) 5) " "
                                           (%cu-pad-left (List ref 10 w) 6)))
                                   (string-concat
                                     (list (%rt-left (%cu-int->str (%rt-dec (List ref 6 w))) 6) " "
                                           (%rt-left (%cu-int->str (%rt-dec (List ref 4 w))) 2) " "
                                           (%cu-pad-left (%cu-int->str (%rt-dec (List ref 5 w))) 7))))
                                 " " (List ref 0 w) "\n")))))))))
           (rest (%cu-lines text))))
    0))

; 32 hex digits as inet_ntop writes the address they spell
(def %rt-ntop6
  (fn (_ hex)
    (def buf (%str-make-raw 16))
    (map (fn (_ k) (%cu-ptr-set! (%cu-str->ptr buf) k (%rt-hex (substring hex (* 2 k) (+ (* 2 k) 2))) 1))
         (List range 0 16))
    (def out (%str-make-raw 64))
    (%cu-ptr-call (%in-c "inet_ntop") 10 (%cu-str->ptr buf) (%cu-str->ptr out) 64)
    (%cu-ptr->str (%cu-str->ptr out))))

; INET6_displayroutes: every route of /proc/net/ipv6_route, up or not
(def %rt-show6
  (fn (_)
    (def text (file-or-err (fn (_) (file-read-unsized "/proc/net/ipv6_route"))))
    (file-write 1 (string-concat (list "Kernel IPv6 routing table\n" (%rt-left "Destination" 44) (%rt-left "Next Hop" 40)
                                       "Flags Metric Ref    Use Iface\n")))
    (unless (Err err? text)
      (map (fn (_ line)
             (let ((w (%rt-words line)))
               (when (= (length w) 10)
                 (file-write 1
                   (string-concat
                     (list (%rt-left (string-concat (list (%rt-ntop6 (List ref 0 w)) "/" (%cu-int->str (%rt-hex (List ref 1 w))))) 43) " "
                           (%rt-left (%rt-ntop6 (List ref 4 w)) 39) " "
                           (%rt-left (%rt-flags (& (%rt-hex (List ref 8 w)) 19202567)) 5) " "
                           (%rt-left (%cu-int->str (%rt-int32 (%rt-hex (List ref 5 w)))) 6) " "
                           (%rt-left (%cu-int->str (%rt-int32 (%rt-hex (List ref 6 w)))) 2) " "
                           (%cu-pad-left (%cu-int->str (%rt-int32 (%rt-hex (List ref 7 w)))) 7) " "
                           (%rt-left (List ref 9 w) 8) "\n"))))))
           (%cu-lines text)))
    0))

; --- the ioctls --------------------------------------------------------------------

; an AF_INET datagram socket, or the run ended as xsocket ends it
(def %rt-socket
  (fn (_ family)
    (let ((fd (%in-call (%cu-ptr-call (%in-c "socket") family 2 0))))
      (if (< fd 0) (%rt-die (string-append "socket: " (libc-strerror (Err errno-of fd)))) fd))))

; xioctl: REQ on FD with the buffer, the run ended as busybox's ends it where it
; fails, "ioctl 0x890b failed: REASON"
(def %rt-ioctl
  (fn (_ fd req buf)
    (let ((r (%in-call (%cu-ptr-call (%in-c "ioctl") fd req (%cu-str->ptr buf)))))
      (do (%cu-ptr-call (%in-c "close") fd)
          (when (< r 0) (%rt-die (string-concat (list "ioctl 0x" (%cvt req %cu-string-type 16) " failed: " (libc-strerror (Err errno-of r))))))))))

; a zeroed buffer of N bytes
(def %rt-zeros
  (fn (_ n)
    (let ((b (%str-make-raw n)))
      (do (map (fn (_ k) (%cu-ptr-set! (%cu-str->ptr b) k 0 1)) (List range 0 n)) b))))

(def %rt-set! (fn (_ buf at v n) (%cu-ptr-set! (%cu-str->ptr buf) at v n)))

; a sockaddr_in for address N at AT
(def %rt-sin!
  (fn (_ buf at n) (do (%rt-set! buf at 2 2) (%rt-set! buf (+ at 4) n 4))))

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
    (let ((n (%cu-range-number "route" s lo hi)))
      (if (null? n) (Err raise (lit route) "number" ()) n))))

; the usage, the run ended with status 1
(def %rt-usage (fn (_) (Err raise (lit route-usage) "usage" ())))

; INET_setroute: ADD? or delete, from the words ARGS
(def %rt-set4
  (fn (_ add? args)
    (def xflag (match ((string=? (first args) "-net") 1) ((string=? (first args) "-host") 2) (#t 0)))
    (def args1 (if (= xflag 0) args (rest args)))
    (when (null? args1) (%rt-usage))
    (def rt (%rt-zeros 120))
    (def target (first args1))
    (def slash (%dp-find target 0 #\/))
    (def mask (if (< slash 0) () (let ((n (%rt-number (substring target (+ slash 1) (byte-len target)) 0 32)))
                                   (& (<< (- 4294967296 1) (- 32 n)) 4294967295))))
    (def host (if (< slash 0) target (substring target 0 slash)))
    (def resolved (%rt-resolve! host))
    (def dst (rest resolved))
    (%rt-sin! rt 8 dst)
    ; a prefix's mask, network order, its first byte the highest
    (def mask-ne (if (null? mask) () (%rt-swap mask)))
    (unless (null? mask-ne) (%rt-sin! rt 40 mask-ne))
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
    (let ((r (%rt-resolve name))) (if (null? r) (%rt-die (string-append "resolving " name)) r))))

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
        (do (%rt-set! rt 80 (+ (%rt-number arg 0 4294967295) 1) 2) (next flags m nm dev)))
      ((eq? code (lit netmask))
        (do (unless (null? m) (%rt-usage))
            (let ((r (%rt-resolve! arg))) (do (%rt-sin! rt 40 (rest r)) (next flags (rest r) arg dev)))))
      ((eq? code (lit gw))
        (do (unless (= (& flags 2) 0) (%rt-usage))
            (let ((r (%rt-resolve! arg)))
              (do (unless (= (first r) 0) (%rt-die (string-concat (list "gateway " arg " is a NETWORK"))))
                  (%rt-sin! rt 24 (rest r))
                  (next (| flags 2) m nm dev)))))
      ((eq? code (lit mss)) (do (%rt-set! rt 96 (%rt-number arg 64 32768) 8) (next (| flags 64) m nm dev)))
      ((eq? code (lit window)) (do (%rt-set! rt 104 (%rt-number arg 128 2147483647) 8) (next (| flags 128) m nm dev)))
      ((eq? code (lit irtt)) (do (%rt-set! rt 112 (%rt-number arg 0 4294967295) 2) (next (| flags 256) m nm dev)))
      ; a device: after dev, or the last word when it is no keyword
      ((if (null? dev) (if (null? k) (null? (rest ws)) (eq? code (lit dev))) #f)
        (if (null? k) (pair (rest ws) (list flags m nm (first ws))) (next flags m nm arg)))
      (#t (%rt-usage)))))

; N's four bytes in the other order
(def %rt-swap
  (fn (_ n) (| (| (<< (& n 255) 24) (<< (& (>> n 8) 255) 16)) (| (<< (& (>> n 16) 255) 8) (& (>> n 24) 255)))))

; the checks after the words, the host route's mask, and the ioctl
(def %rt-finish4
  (fn (_ add? rt dst dev flags m nm)
    (do (unless (null? m)
          (let ((mask (^ (%rt-swap m) 4294967295)))
            (do (when (if (= (& flags 4) 0) #f (not (= mask 4294967295)))
                  (%rt-die (string-concat (list "netmask " (%rt-hex8 mask) " and host route conflict"))))
                (unless (= (& mask (+ mask 1)) 0) (%rt-die (string-append "bogus netmask " (if (null? nm) "(null)" nm))))
                (unless (= (& dst (^ m 4294967295)) 0) (%rt-die "netmask and route address conflict")))))
        (when (if add? (not (= (& flags 4) 0)) #f) (%rt-sin! rt 40 4294967295))
        (%rt-set! rt 56 flags 2)
        (def devbuf (if (null? dev) () (string-append dev "")))
        (unless (null? devbuf) (%cu-ptr-set! (%cu-str->ptr rt) 88 (%td-ptr->int (%cu-str->ptr devbuf)) 8))
        (%rt-ioctl (%rt-socket 2) (if add? 35083 35084) rt)
        0)))

; N as eight lowercase hex digits, %.8x
(def %rt-hex8 (fn (_ n) (%cu-pad-zero (%cvt n %cu-string-type 16) 8)))

; INET6_setroute: ADD? or delete, from the words ARGS
(def %rt-set6
  (fn (_ add? args)
    (def rt (%rt-zeros 80))
    (def target (first args))
    (def slash (%dp-find target 0 #\/))
    (def plen (match ((string=? target "default") 0) ((< slash 0) 128)
                     (#t (%rt-number (substring target (+ slash 1) (byte-len target)) 0 128))))
    (def host (if (< slash 0) target (substring target 0 slash)))
    (unless (string=? target "default")
      (unless (%rt-pton6! rt 0 host) (%rt-die (string-append "resolving " host))))
    (%rt-set! rt 52 plen 2)
    (%rt-set! rt 56 1 4)
    (let go ((ws (rest args)) (flags (if (= plen 128) 5 1)) (dev ()))
      (if (null? ws)
        (do (%rt-set! rt 72 flags 4)
            (def fd (%rt-socket 10))
            (unless (null? dev)
              (let ((ifr (%rt-zeros 40)))
                (do (map (fn (_ k) (%rt-set! ifr k (char->integer (byte-at dev k)) 1)) (List range 0 (if (> (byte-len dev) 15) 15 (byte-len dev))))
                    (let ((r (%in-call (%cu-ptr-call (%in-c "ioctl") fd 35123 (%cu-str->ptr ifr)))))
                      (when (< r 0) (%rt-die (string-concat (list "ioctl 0x8933 failed: " (libc-strerror (Err errno-of r)))))))
                    (%rt-set! rt 76 (%cu-ptr-ref (%cu-str->ptr ifr) 16 4) 4))))
            (%rt-ioctl fd (if add? 35083 35084) rt)
            0)
        (let ((k (%rt-keyword (first ws))))
          (match
            ((if (null? k) #f (if (eq? (List ref 1 k) (lit mod)) #t (eq? (List ref 1 k) (lit dyn))))
              (go (rest ws) (| flags (if (eq? (List ref 1 k) (lit mod)) 32 16)) dev))
            ((if (null? k) #f (if (List ref 2 k) (null? (rest ws)) #f)) (%rt-usage))
            ((if (null? k) #f (eq? (List ref 1 k) (lit metric)))
              (do (%rt-set! rt 56 (%rt-number (first (rest ws)) 0 4294967295) 4) (go (rest (rest ws)) flags dev)))
            ((if (null? k) #f (eq? (List ref 1 k) (lit gw)))
              (do (unless (= (& flags 2) 0) (%rt-usage))
                  (unless (%rt-pton6! rt 32 (first (rest ws))) (%rt-die (string-append "resolving " (first (rest ws)))))
                  (go (rest (rest ws)) (| flags 2) dev)))
            ((if (null? dev) (if (null? k) (null? (rest ws)) (eq? (List ref 1 k) (lit dev))) #f)
              (if (null? k) (go (rest ws) flags (first ws)) (go (rest (rest ws)) flags (first (rest ws)))))
            (#t (%rt-usage))))))))

; inet_pton: NAME's IPv6 address written at AT; #f where it is not one
(def %rt-pton6!
  (fn (_ buf at name)
    (let ((tmp (%str-make-raw 16)))
      (if (= (%in-call (%cu-ptr-call (%in-c "inet_pton") 10 name (%cu-str->ptr tmp))) 1)
        (do (map (fn (_ k) (%rt-set! buf (+ at k) (%cu-ptr-ref (%cu-str->ptr tmp) k 1) 1)) (List range 0 16)) #t)
        #f))))

(def %cu-route
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "route" argv))
    (def family (Opts value o "-A"))
    (def ops (Opts operands o))
    (def six? (if (null? family) #f (string=? family "inet6")))
    (match
      ((if (null? family) #f (if (string=? family "inet") #f (not six?))) (%cu-usage "route"))
      ((null? ops) (if six? (%rt-show6) (%rt-show4 (Opts on? o "-n") (Opts on? o "-e"))))
      (#t
        (let ((verb (first ops)))
          (if (if (if (string=? verb "add") #f (if (string=? verb "del") #f (not (string=? verb "delete")))) #t (null? (rest ops)))
            (%cu-usage "route")
            (guard (e (if (eq? (%cu-err-label e) (lit route-usage)) (%cu-usage "route")
                        (if (eq? (%cu-err-label e) (lit route)) 1 (error e))))
              (if six? (%rt-set6 (string=? verb "add") (rest ops)) (%rt-set4 (string=? verb "add") (rest ops))))))))))

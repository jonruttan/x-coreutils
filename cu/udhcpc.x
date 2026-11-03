; # x-coreutils -- the small tools, as applets
;
; ## cu/udhcpc.x -- udhcpc: busybox's DHCP client
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox 1.36.1's udhcpc (networking/udhcp/dhcpc.c), as its defconfig
; builds it: -a and -b on, hostnames sanitised, no -P.
;
; The client broadcasts DISCOVER -t times -T seconds apart, then REQUESTs
; the first OFFER; an ACK binds the lease, with -a once an ARP probe finds
; nobody holding the address -- one who does gets a DECLINE.  Half way
; through the lease it renews from the server, then broadcasts as the end
; nears, then starts over.  Each event runs -s's program with the event's
; name and the lease in the environment: deconfig, bound, renew, nak,
; leasefail.  Without -f the run goes to the background once it has a
; lease; -b goes there when it has none, -n ends there, -q ends at the lease.
; SIGUSR1 renews, SIGUSR2 releases, SIGTERM ends the run, releasing with -R.
;
; Replies are read through a packet socket while there is no address, and
; through UDP on port 68 while renewing.  busybox's "started, v" line, and
; the vendor class sent by default, give the version x-coreutils was
; installed as.

(module cu/udhcpc)

(import cu/cli cu-declaration cu-optional cu-usage)
(import cu/inet inet-set!)
(import cu/inetd in-call)
(import cu/nc nc-count)
(import cu/ping pn-be16 pn-div pn-now pn-setopt)
(import cu/prims append byte-at byte-len cu-err-label cu-hexs cu-int->str
  cu-libc-sym cu-nth cu-ptr-call cu-ptr-ref cu-str->ptr file-close
  integer->char length libc-strerror list->string map reverse string-append
  string=? substring sys-exit sys-usleep)
(import cu/telnetd td-ptr->int)
(import cu/udhcp ud-6rd ud-ack ud-add-option! ud-add-simple! ud-arpping
  ud-be16! ud-be32 ud-be32! ud-byte ud-bytes ud-bytes-be ud-catch! ud-chaddr
  ud-child? ud-ciaddr ud-cksum ud-daemonize! ud-decline ud-die ud-discover
  ud-dns-string ud-dotted ud-dump ud-end ud-end-option ud-errno ud-error
  ud-file ud-find-option ud-flags ud-get-option ud-get-option32 ud-giaddr
  ud-hex2 ud-hlen ud-info ud-insert ud-ip ud-ip-pair ud-listen ud-log1 ud-log2
  ud-logging! ud-ms ud-nak ud-offer ud-optflag-named ud-optflag-of ud-optflags
  ud-options ud-packet ud-packet-size ud-process-reset! ud-put!
  ud-read-interface ud-recv-kernel ud-release ud-remove-pidfile ud-req
  ud-request ud-s32 ud-same? ud-scan-overload ud-secs ud-send-kernel
  ud-send-raw ud-set! ud-siaddr ud-sip-servers ud-sname ud-spawn
  ud-static-routes ud-status ud-str-bytes ud-str2optset ud-string
  ud-string-host ud-strtou ud-taken ud-type-length ud-u16 ud-u32 ud-u8
  ud-verbose ud-write-pidfile ud-xid ud-yiaddr ud-zeros)
(import cu/vi vi-bundle-version)

; --- the run's settings and state -------------------------------------------------------

(def %uc-iface "eth0")
(def %uc-script "/usr/share/udhcpc/default.script")
(def %uc-pidfile ())
(def %uc-ifindex 0)
(def %uc-mac (list 0 0 0 0 0 0))
(def %uc-options ())             ; what is sent: -x, -V, -F, the client ID
(def %uc-clientid #f)            ; the client ID is ours, the MAC in it
(def %uc-mask ())                ; the codes asked for, ascending
(def %uc-broadcast #f)

(def %uc-discover-timeout 3)
(def %uc-discover-retries 3)
(def %uc-tryagain 20)
(def %uc-arp ())                 ; -a's milliseconds, nil without it
(def %uc-background #f)          ; -b
(def %uc-now #f)                 ; -n
(def %uc-foreground #f)          ; -f
(def %uc-quit #f)                ; -q
(def %uc-release #f)             ; -R

; the states
(def %uc-init 0)
(def %uc-requesting 1)
(def %uc-bound 2)
(def %uc-renewing 3)
(def %uc-rebinding 4)
(def %uc-renew-requested 5)
(def %uc-released 6)

(def %uc-state 0)
(def %uc-xid 0)
(def %uc-first-secs 0)
(def %uc-sock -1)
(def %uc-listen 0)               ; 0 none, 1 kernel, 2 raw
(def %uc-timeout 0)
(def %uc-lease 0)
(def %uc-packet-num 0)
(def %uc-server 0)
(def %uc-requested 0)

(def %uc-sec (fn (_) (pn-div (pn-now) 1000000)))
(def %uc-xid! (fn (_) (set! %uc-xid (in-call (cu-ptr-call (cu-libc-sym "rand"))))))

; --- the script --------------------------------------------------------------------------

; mton: the mask's width, counted to its last set bit
(def %uc-mton
  (fn (_ m) (let go ((m m) (i 0)) (if (= m 0) i (go (& (<< m 1) 4294967295) (+ i 1))))))

(def %uc-text (fn (_ l) (list->string (map integer->char l))))
(def %uc-upto-nul
  (fn (_ l) (let go ((left l) (acc ())) (if (if (null? left) #t (= (first left) 0)) (reverse acc) (go (rest left) (pair (first left) acc))))))

; good_hostname
(def %uc-good-name?
  (fn (_ l)
    (def ok? (fn (_ c) (match ((if (>= c #\0) (<= c #\9) #f) #t)
                              ((if (>= (| c 32) #\a) (<= (| c 32) #\z) #f) #t)
                              (#t (if (= c #\-) #t (if (= c #\_) #t (= c #\.)))))))
    (if (if (null? l) #f (= (first l) #\-)) #f
      (null? (List find (fn (_ c) (not (ok? c))) l)))))

(def %uc-hex4 (fn (_ l) (%str-concat (map ud-hex2 l))))

; sprint_nip6
(def %uc-nip6
  (fn (_ l)
    (Str8 join ":" (let go ((left l) (acc ())) (if (null? left) (reverse acc) (go (List drop 2 left) (pair (%uc-hex4 (List take 2 left)) acc)))))))

; dname_dec: the names in L, a space between, after PRE; nil where L
; holds no label or is not one
(def %uc-dname
  (fn (_ l pre)
    (def n (length l))
    (def at (fn (_ i) (cu-nth i l)))
    (let go ((pos 0) (ret 0) (depth 0) (out (reverse (ud-str-bytes pre))) (len (byte-len pre)) (labels #f))
      (if (>= pos n)
        (if labels (%uc-text (reverse (rest out))) ())
        (let ((c (at pos)))
          (def next
            (match
              ((= (& c 192) 192)
               (if (> (+ pos 2) n) ()
                 (list (& (+ (* c 256) (at (+ pos 1))) 16383) (if (= ret 0) (+ pos 2) ret) (+ depth 1) out len labels)))
              ((not (= c 0))
               (if (> (+ pos c 1) n) ()
                 (list (+ pos c 1) ret depth
                       (pair #\. (append (reverse (List take c (List drop (+ pos 1) l))) out))
                       (+ len c 1) #t)))
              (#t (list (if (= ret 0) (+ pos 1) ret) (if (= ret 0) ret 0) (if (= ret 0) depth 0)
                        (if (= len 0) out (pair #\space (rest out))) len labels))))
          (if (if (null? next) #t (if (> (cu-nth 2 next) 6) #t (> (cu-nth 4 next) 6150))) ()
            (go (first next) (cu-nth 1 next) (cu-nth 2 next) (cu-nth 3 next) (cu-nth 4 next) (cu-nth 5 next))))))))

; xmalloc_optname_optval: NAME=, then DATA as FLAGS' type says; a name
; decoded is the whole of it, NAME= included, as dname_dec writes it
(def %uc-optval
  (fn (_ flags data name)
    (def pre (string-append name "="))
    (def r (%uc-items (& flags 15) (ud-type-length flags) data pre))
    (if (pair? r) (rest r) (string-append pre r))))

(def %uc-items
  (fn (self type size l pre)
    (def nip (fn (_ b) (ud-dotted (ud-bytes-be (List take 4 b)))))
    ; an item said, then the rest in its type, a space between
    (def more (fn (_ text) (let ((left (List drop size l))) (if (< (length left) size) text (%str-concat (list text " " (self type size left pre)))))))
    (if (< (length l) size) ""
      (match
        ((= type ud-ip) (more (nip l)))
        ((= type ud-ip-pair) (more (%str-concat (list (nip l) "/" (nip (List drop 4 l))))))
        ((= type ud-u8) (more (cu-int->str (first l))))
        ((= type ud-u16) (more (cu-int->str (ud-bytes-be (List take 2 l)))))
        ((if (= type ud-u32) #t (= type ud-s32)) (more (cu-int->str (ud-bytes-be (List take 4 l)))))
        ((if (= type ud-string) #t (= type ud-string-host))
         (let ((s (%uc-upto-nul l)))
           (if (if (= type ud-string-host) (not (%uc-good-name? s)) #f)
             (substring "bad" 0 (if (< (length l) 4) (- (length l) 1) 3))
             (%uc-text s))))
        ((= type ud-static-routes) (%uc-routes l ""))
        ((= type ud-6rd)
         (if (if (>= (length l) 22) (if (<= (first l) 32) (<= (- (+ (cu-nth 1 l) 32) (first l)) 128) #f) #f)
           (%str-concat (list (cu-int->str (first l)) " " (cu-int->str (cu-nth 1 l)) " "
                              (%uc-nip6 (List take 16 (List drop 2 l))) " "
                              (self ud-ip 4 (List drop 18 l) pre)))
           ""))
        ((= type ud-dns-string)
         (let ((d (%uc-dname l pre))) (if (null? d) "" (pair (lit whole) d))))
        ((= type ud-sip-servers)
         (match ((= (first l) 1) (self ud-ip 4 (rest l) pre))
                ((= (first l) 0) (let ((d (%uc-dname (rest l) pre))) (if (null? d) "" (pair (lit whole) d))))
                (#t "")))
        (#t "")))))

; the static routes: "IP/MASK ROUTER", a space between
(def %uc-routes
  (fn (self l pfx)
    (if (< (length l) 5) ""
      (let ((mask (first l)))
        (def n (>> (+ mask 7) 3))
        (if (if (> mask 32) #t (< (length l) (+ 1 n 4))) ""
          (let ((ip (append (List take n (rest l)) (List take (- 4 n) (list 0 0 0 0))))
                (l (List drop (+ 1 n) l)))
            (%str-concat (list pfx (ud-dotted (ud-bytes-be ip)) "/" (cu-int->str mask) " "
                               (ud-dotted (ud-bytes-be (List take 4 l)))
                               (self (List drop 4 l) " ")))))))))

; fill_envp: the variables, each "NAME=VALUE", for P, or for no packet
(def %uc-env
  (fn (_ p)
    (def say (fn (_ s) (do (ud-log2 (string-append " " s)) s)))
    (def head (list (say (string-append "interface=" %uc-iface))))
    (if (null? p) head
      (let ((scan (ud-scan-overload p)))
        (def items
          ; (CODE BYTES TEXT) in the order seen, a repeated code's bytes
          ; joined to the first's; the mask's entries go along as code -1
          (let go ((l (rest scan)) (acc ()))
            (if (if (null? l) #t (eq? (first l) (lit malformed))) (reverse acc)
              (let ((code (first (first l))) (data (ud-bytes p (cu-nth 1 (first l)) (cu-nth 2 (first l)))))
                (def old (List find (fn (_ i) (= (first i) code)) acc))
                (def bytes (if (null? old) data (append (cu-nth 1 old) data)))
                (def f (ud-optflag-of code))
                (def mask (if (if (= code 1) (= (length bytes) 4) #f)
                            (list (list -1 () (say (string-append "mask=" (cu-int->str (%uc-mton (ud-bytes-be bytes)))))))
                            ()))
                (def text (say (if (if (null? f) #t (null? (cu-nth 2 f)))
                                 (%str-concat (list "opt" (cu-int->str code) "=" (%uc-hex4 bytes)))
                                 (%uc-optval (first f) bytes (cu-nth 2 f)))))
                (def item (list code bytes text))
                (go (rest l) (append mask (if (null? old) (pair item acc) (map (fn (_ i) (if (eq? i old) item i)) acc))))))))
        (def field (fn (_ at n) (%uc-text (%uc-upto-nul (ud-bytes p at n)))))
        (append head (map (fn (_ i) (cu-nth 2 i)) items)
          (list (say (string-append "ip=" (ud-dotted (ud-be32 p ud-yiaddr)))))
          (if (= (ud-be32 p ud-siaddr) 0) () (list (say (string-append "siaddr=" (ud-dotted (ud-be32 p ud-siaddr))))))
          (if (= (ud-be32 p ud-giaddr) 0) () (list (say (string-append "giaddr=" (ud-dotted (ud-be32 p ud-giaddr))))))
          (if (if (= (& (first scan) 1) 0) (not (= (ud-byte p ud-file) 0)) #f)
            (list (say (string-append "boot_file=" (field ud-file 128)))) ())
          (if (if (= (& (first scan) 2) 0) (not (= (ud-byte p ud-sname) 0)) #f)
            (list (say (string-append "sname=" (field ud-sname 64)))) ()))))))

; d4_run_script
(def %uc-script-run
  (fn (_ p event)
    (def env (%uc-env p))
    (ud-log1 (%str-concat (list "executing " %uc-script " " event)))
    (ud-spawn (list %uc-script event)
              (List fold (fn (_ acc s)
                           (let ((eq (let go ((i 0)) (match ((>= i (byte-len s)) ()) ((= (byte-at s i) #\=) i) (#t (go (+ i 1)))))))
                             (if (null? eq) acc (append acc (list (pair (substring s 0 eq) (substring s (+ eq 1) (byte-len s))))))))
                         () env))))

(def %uc-deconfig (fn (_) (%uc-script-run () "deconfig")))

; --- the packets -------------------------------------------------------------------------

; init_packet
(def %uc-packet
  (fn (_ type)
    (def p (ud-packet type))
    (inet-set! p ud-xid %uc-xid 4)
    (def now (%uc-sec))
    (when (= %uc-first-secs 0) (set! %uc-first-secs now))
    (let ((secs (- now %uc-first-secs))) (ud-be16! p ud-secs (if (< secs 65535) secs 65535)))
    (ud-put! p ud-chaddr %uc-mac)
    p))

; add_client_options: the size, the codes asked for, -B, what is sent
(def %uc-client-options
  (fn (_ p)
    (ud-add-simple! p 57 576)
    (unless (null? %uc-mask)
      (ud-put! p (+ ud-options (ud-end-option p)) (append (pair 55 (pair (length %uc-mask) %uc-mask)) (list 255))))
    (when (if %uc-broadcast (= (ud-be32 p ud-ciaddr) 0) #f) (ud-set! p ud-flags 128))
    (map (fn (_ o) (ud-add-option! p o)) %uc-options)))

(def %uc-ids
  (fn (_ p server)
    (ud-add-simple! p 54 server)
    (let ((ci (ud-find-option %uc-options 61))) (unless (null? ci) (ud-add-option! p ci)))))

(def %uc-bcast
  (fn (_ p src) (ud-send-raw p src 68 4294967295 67 (list 255 255 255 255 255 255) %uc-ifindex)))
(def %uc-bcast-or-ucast
  (fn (_ p ciaddr server)
    (if (= server 0) (%uc-bcast p ciaddr) (ud-send-kernel p ciaddr 68 server 67 %uc-iface))))

(def %uc-send-discover
  (fn (_ requested)
    (def p (%uc-packet ud-discover))
    (unless (= requested 0) (ud-add-simple! p 50 requested))
    (%uc-client-options p)
    (ud-info "broadcasting discover")
    (%uc-bcast p 0)))

(def %uc-send-select
  (fn (_ server requested)
    (def p (%uc-packet ud-request))
    (ud-add-simple! p 50 requested)
    (ud-add-simple! p 54 server)
    (%uc-client-options p)
    (ud-info (%str-concat (list "broadcasting select for " (ud-dotted requested) ", server " (ud-dotted server))))
    (%uc-bcast p 0)))

(def %uc-send-renew
  (fn (_ server ciaddr)
    (def p (%uc-packet ud-request))
    (ud-be32! p ud-ciaddr ciaddr)
    (%uc-client-options p)
    (ud-info (if (= server 0) "broadcasting renew" (string-append "sending renew to server " (ud-dotted server))))
    (%uc-bcast-or-ucast p ciaddr server)))

(def %uc-send-decline
  (fn (_ server requested)
    (def p (%uc-packet ud-decline))
    (ud-add-simple! p 50 requested)
    (%uc-ids p server)
    (ud-info "broadcasting decline")
    (%uc-bcast p 0)))

(def %uc-send-release
  (fn (_ server ciaddr)
    (def p (%uc-packet ud-release))
    (ud-be32! p ud-ciaddr ciaddr)
    (%uc-ids p server)
    (ud-info "sending release")
    (%uc-bcast-or-ucast p ciaddr server)))

; d4_recv_raw_packet: the DHCP packet in what the packet socket FD read,
; or -1 where the read failed, -2 where it is not one for us
(def %uc-recv-raw
  (fn (_ fd)
    (def b (ud-zeros 656))
    (def ctl (ud-zeros 40))
    (def iov (ud-zeros 16))
    (def msg (ud-zeros 56))
    (inet-set! iov 0 (td-ptr->int (cu-str->ptr b)) 8)
    (inet-set! iov 8 656 8)
    (inet-set! msg 16 (td-ptr->int (cu-str->ptr iov)) 8)
    (inet-set! msg 24 1 8)
    (inet-set! msg 32 (td-ptr->int (cu-str->ptr ctl)) 8)
    (inet-set! msg 40 36 8)
    (def n (let go () (let ((r (in-call (cu-ptr-call (cu-libc-sym "recvmsg") fd (cu-str->ptr msg) 0))))
                        (if (if (< r 0) (= (Err errno-of r) 4) #f) (go) r))))
    (def be16 (fn (_ i) (pn-be16 (cu-str->ptr b) i)))
    (def ignore (fn (_ why) (do (ud-log1 why) -2)))
    (if (< n 0) (do (ud-log1 "packet read error, ignoring") n)
      (match
        ((< n 28) (ignore "packet is too short, ignoring"))
        ((< n (be16 2)) (ignore "oversized packet, ignoring"))
        (#t (%uc-check b (be16 2) ctl msg))))))

(def %uc-check
  (fn (_ b bytes ctl msg)
    (def be16 (fn (_ i) (pn-be16 (cu-str->ptr b) i)))
    (def ignore (fn (_ why) (do (ud-log1 why) -2)))
    (def ip-sum (be16 10))
    (match
      ((match ((not (= (ud-byte b 9) 17)) #t)
              ((not (= (ud-byte b 0) 69)) #t)
              ((not (= (be16 22) 68)) #t)
              (#t (not (= (be16 24) (- bytes 20)))))
       (ignore "unrelated/bogus packet, ignoring"))
      ((not (= ip-sum (do (ud-be16! b 10 0) (ud-cksum b 0 20)))) (ignore "bad IP header checksum, ignoring"))
      (#t
       (let ((unready (if (>= (cu-ptr-ref (cu-str->ptr msg) 40 8) 16)
                        (if (= (cu-ptr-ref (cu-str->ptr ctl) 8 4) 263)
                          (if (= (cu-ptr-ref (cu-str->ptr ctl) 12 4) 8) (not (= (& (cu-ptr-ref (cu-str->ptr ctl) 16 4) 8) 0)) #f) #f) #f))
             (udp-sum (be16 26)))
         (do (ud-put! b 0 (list 0 0 0 0 0 0 0 0 0))
             (ud-be16! b 2 (be16 24))
             (ud-be16! b 26 0)
             (match
               ((if unready #f (if (= udp-sum 0) #f (not (= udp-sum (ud-cksum b 0 bytes)))))
                (ignore "packet with bad UDP checksum received, ignoring"))
               ((not (= (ud-be32 b 264) 1669485411)) (ignore "packet with bad magic, ignoring"))
               (#t
                (let ((p (ud-zeros ud-packet-size)))
                  (cu-ptr-call (cu-libc-sym "memcpy") (cu-str->ptr p) (+ (td-ptr->int (cu-str->ptr b)) 28) (- bytes 28))
                  (ud-log2 "received a packet")
                  (ud-dump p)
                  p)))))))))

; --- listening ---------------------------------------------------------------------------

; udhcp_raw_socket
(def %uc-raw-socket
  (fn (_ ifindex)
    (ud-log2 (string-append "opening raw socket on ifindex " (cu-int->str ifindex)))
    (def fd (in-call (cu-ptr-call (cu-libc-sym "socket") 17 2 8)))
    (when (< fd 0) (ud-die (string-append "socket: " (libc-strerror (ud-errno fd)))))
    (def sll (ud-zeros 20))
    (inet-set! sll 0 17 2)
    (ud-be16! sll 2 2048)
    (inet-set! sll 4 ifindex 4)
    (let ((r (in-call (cu-ptr-call (cu-libc-sym "bind") fd (cu-str->ptr sll) 20))))
      (when (< r 0) (ud-die (string-append "bind: " (libc-strerror (ud-errno r))))))
    (when (< (pn-setopt fd 263 8 1) 0)
      (unless (= (Err errno-of -1) 92) (ud-log1 "can't set PACKET_AUXDATA on raw socket")))
    fd))

; change_listen_mode
(def %uc-listen!
  (fn (_ mode)
    (ud-log1 (string-append "entering listen mode: " (match ((= mode 0) "none") ((= mode 1) "kernel") (#t "raw"))))
    (set! %uc-listen mode)
    (when (>= %uc-sock 0) (do (file-close %uc-sock) (set! %uc-sock -1)))
    (match ((= mode 1) (set! %uc-sock (ud-listen 68 %uc-iface)))
           ((= mode 2) (set! %uc-sock (%uc-raw-socket %uc-ifindex)))
           (#t ()))))

; perform_release
(def %uc-perform-release
  (fn (_)
    (%uc-listen! 0)
    (when (match ((= %uc-state %uc-bound) #t) ((= %uc-state %uc-renewing) #t)
                 ((= %uc-state %uc-rebinding) #t) (#t (= %uc-state %uc-renew-requested)))
      (do (ud-info (%str-concat (list "unicasting a release of " (ud-dotted %uc-requested) " to " (ud-dotted %uc-server))))
          (%uc-xid!)
          (%uc-send-release %uc-server %uc-requested)))
    (ud-info "entering released state")
    (%uc-deconfig)
    (set! %uc-state %uc-released)))

; client_background
(def %uc-background!
  (fn (_)
    (ud-daemonize!)
    (ud-logging! "udhcpc" (ud-verbose) #f %uc-syslog)
    (ud-write-pidfile %uc-pidfile)))
(def %uc-syslog #f)

; --- the options ----------------------------------------------------------------------

; xatoi_positive and xatou
(def %uc-number
  (fn (_ s max)
    (let ((r (ud-strtou s 10)))
      (match ((not (rest r)) (ud-die (%str-concat (list "invalid number '" s "'"))))
             ((> (first r) max) (ud-die (%str-concat (list "number " s " is not in 0.." (cu-int->str max) " range"))))
             (#t (first r))))))

(def %uc-ask!
  (fn (_ code)
    (unless (List find (fn (_ c) (= c code)) %uc-mask)
      (set! %uc-mask (let go ((l %uc-mask)) (if (if (null? l) #t (> (first l) code)) (pair code l) (pair (first l) (go (rest l)))))))))

(def %uc-setup
  (fn (_ o msec)
    (set! %uc-iface (Opts value o "-i" "eth0"))
    (set! %uc-script (Opts value o "-s" "/usr/share/udhcpc/default.script"))
    (set! %uc-pidfile (Opts value o "-p"))
    (set! %uc-options ())
    (set! %uc-mask ())
    (set! %uc-broadcast (Opts on? o "-B"))
    (set! %uc-background (Opts on? o "-b"))
    (set! %uc-now (Opts on? o "-n"))
    (set! %uc-foreground (Opts on? o "-f"))
    (set! %uc-quit (Opts on? o "-q"))
    (set! %uc-release (Opts on? o "-R"))
    (set! %uc-discover-timeout (%uc-number (Opts value o "-T" "3") 2147483647))
    (set! %uc-discover-retries (%uc-number (Opts value o "-t" "3") 2147483647))
    (set! %uc-tryagain (%uc-number (Opts value o "-A" "20") 2147483647))
    (let ((f (Opts value o "-F")))
      (unless (null? f)
        (set! %uc-options (ud-insert %uc-options (pair 81 (pair (+ (byte-len f) 3) (append (list 1 0 0) (ud-str-bytes f))))))))
    (set! %uc-requested 0)
    (let ((r (Opts value o "-r")))
      (unless (null? r)
        (let ((n (%uc-aton r)))
          (if (null? n) (do (cu-usage "udhcpc") (ud-end 1)) (set! %uc-requested n)))))
    (set! %uc-arp (if (Opts on? o "-a") (%uc-number (if (null? msec) "2000" msec) 4294967295) ()))
    (map (fn (_ s)
           (let ((r (ud-strtou s 0)))
             (%uc-ask! (if (if (rest r) (<= (first r) 254) #f) (first r) (first (rest (ud-optflag-named s)))))))
         (Opts values o "-O"))
    (unless (Opts on? o "-o")
      (map (fn (_ f) (unless (= (& (first f) ud-req) 0) (%uc-ask! (first (rest f))))) ud-optflags))
    (map (fn (_ x) (set! %uc-options (rest (ud-str2optset x %uc-options)))) (Opts values o "-x"))
    (let ((v (Opts value o "-V" (string-append "udhcp " (vi-bundle-version)))))
      (unless (= (byte-len v) 0)
        (let ((b (ud-str-bytes (if (> (byte-len v) 254) (substring v 0 254) v))))
          (set! %uc-options (ud-insert %uc-options (pair 60 (pair (length b) b)))))))
    (set! %uc-clientid (if (Opts on? o "-C") #f (null? (ud-find-option %uc-options 61))))
    (when %uc-clientid (set! %uc-options (ud-insert %uc-options (list 61 7 1 0 0 0 0 0 0))))))

; inet_aton, the number in host order
(def %uc-aton
  (fn (_ s)
    (let ((buf (ud-zeros 4)))
      (if (= (in-call (cu-ptr-call (cu-libc-sym "inet_aton") s (cu-str->ptr buf))) 0) () (ud-be32 buf 0)))))

; udhcp_read_interface, the client ID given the MAC read
(def %uc-interface!
  (fn (_)
    (let ((r (ud-read-interface %uc-iface #f)))
      (if (null? r) #f
        (do (set! %uc-ifindex (first r))
            (set! %uc-mac (cu-nth 2 r))
            (when %uc-clientid
              (set! %uc-options (map (fn (_ o) (if (= (first o) 61) (append (list 61 7 1) %uc-mac) o)) %uc-options)))
            #t)))))

; --- the run ----------------------------------------------------------------------------

(def %uc-main
  (fn (_ argv)
    (def cut (cu-optional "udhcpc" argv))
    ; parsed against the declaration, a long spelling reads as its letter
    (def o (Opts parse (cu-declaration "udhcpc") (first cut)))
    (set! %uc-syslog (Opts on? o "-S"))
    (ud-logging! "udhcpc" (nc-count o "-v") #t #f)
    (ud-catch!)
    (%uc-setup o (rest cut))
    (if (not (%uc-interface!)) 1
      (do (when %uc-syslog (do (cu-ptr-call (cu-libc-sym "openlog") "udhcpc" 1 24)
                               (ud-logging! "udhcpc" (ud-verbose) #t #t)))
          (ud-write-pidfile %uc-pidfile)
          (ud-info (string-append "started, v" (vi-bundle-version)))
          (cu-ptr-call (cu-libc-sym "srand") (& (pn-now) 4294967295))
          (set! %uc-state %uc-init)
          (set! %uc-sock -1)
          (set! %uc-listen 0)
          (set! %uc-first-secs 0)
          (set! %uc-server 0)
          (%uc-deconfig)
          (set! %uc-packet-num 0)
          (set! %uc-timeout 0)
          (set! %uc-lease 0)
          (let ((status (%uc-loop)))
            (do (ud-remove-pidfile %uc-pidfile) status))))))

; the run ends with STATUS; anything else a pass answers goes on
(def %uc-end (fn (_ status) (list (lit end) status)))
(def %uc-end? (fn (_ r) (if (pair? r) (eq? (first r) (lit end)) #f)))

; the run's way out: 0, released first with -R
(def %uc-ret0
  (fn (_) (do (when %uc-release (%uc-perform-release)) (%uc-end 0))))

; the main loop; each pass answers a timeout, a signal or a packet
(def %uc-loop
  (fn (self)
    (Heap collect)
    (def event (if (> %uc-timeout 0) (%uc-wait) (lit timeout)))
    (def r
      (match ((eq? event (lit timeout)) (%uc-timed-out))
             ((eq? event (lit packet)) (%uc-packet-in))
             (#t (%uc-signal event))))
    (if (%uc-end? r) (first (rest r)) (self))))

; the poll: half a second at a time, the signals looked at between;
; timeout, packet, or the signal's number
(def %uc-wait
  (fn (_)
    (when (> %uc-timeout 2147483) (set! %uc-timeout 2147483))
    (ud-log1 (%str-concat (list "waiting " (cu-int->str %uc-timeout) " seconds")))
    (def before (%uc-sec))
    (def end (+ (ud-ms) (* %uc-timeout 1000)))
    (def event
      (let go ()
        (let ((sig (ud-taken)) (left (- end (ud-ms))))
          (match ((not (null? sig)) sig)
                 ((<= left 0) (lit timeout))
                 (#t (let ((slice (if (> left 500) 500 left)))
                       (if (< %uc-sock 0) (do (sys-usleep (* slice 1000)) (go))
                         (if (null? (Sys poll (list (pair %uc-sock (list (lit in)))) slice)) (go) (lit packet)))))))))
    (def diff (- (%uc-sec) before))
    (set! %uc-lease (if (< (- %uc-lease diff) 0) 0 (- %uc-lease diff)))
    (set! %uc-timeout (if (< (- %uc-timeout diff) 0) 0 (- %uc-timeout diff)))
    event))

; the timeout's work, by state; a number ends the run
(def %uc-timed-out
  (fn (_)
    (if (not (%uc-interface!)) (%uc-ret0)
      (match
        ((= %uc-state %uc-init) (%uc-selecting))
        ((= %uc-state %uc-requesting)
         (if (< %uc-packet-num 3)
           (do (%uc-send-select %uc-server %uc-requested)
               (set! %uc-timeout %uc-discover-timeout)
               (set! %uc-packet-num (+ %uc-packet-num 1))
               ())
           (do (set! %uc-state %uc-init) (%uc-leasefail))))
        ((= %uc-state %uc-bound)
         (do (set! %uc-state %uc-renewing) (set! %uc-first-secs 0) (%uc-enter-renew)))
        ((if (= %uc-state %uc-renewing) #t (= %uc-state %uc-renew-requested)) (%uc-renew))
        ((= %uc-state %uc-rebinding) (%uc-rebind))
        (#t (do (set! %uc-timeout 2147483) ()))))))

(def %uc-selecting
  (fn (_)
    (if (if (= %uc-discover-retries 0) #t (< %uc-packet-num %uc-discover-retries))
      (do (when (= %uc-packet-num 0) (do (%uc-listen! 2) (%uc-xid!)))
          (%uc-send-discover %uc-requested)
          (set! %uc-timeout %uc-discover-timeout)
          (set! %uc-packet-num (+ %uc-packet-num 1))
          ())
      (%uc-leasefail))))

(def %uc-leasefail
  (fn (_)
    (%uc-listen! 0)
    (%uc-script-run () "leasefail")
    (match
      (%uc-background
       (do (ud-info "no lease, forking to background")
           (%uc-background!)
           (set! %uc-background #f) (set! %uc-now #f) (set! %uc-foreground #t)
           (%uc-try-again)))
      (%uc-now (do (ud-info "no lease, failing") (%uc-end 1)))
      (#t (%uc-try-again)))))

(def %uc-try-again
  (fn (_) (do (set! %uc-timeout %uc-tryagain) (set! %uc-packet-num 0) ())))

; got_SIGUSR1: into the renew
(def %uc-enter-renew
  (fn (_) (do (ud-log1 "entering renew state") (%uc-listen! 1) (%uc-renew))))

(def %uc-renew
  (fn (_)
    (if (if (= %uc-packet-num 0) (>= (%uc-send-renew %uc-server %uc-requested) 0) #f)
      (do (set! %uc-timeout %uc-discover-timeout) (set! %uc-packet-num (+ %uc-packet-num 1)) ())
      (do (ud-log1 "no response to renew")
          (if (> %uc-lease 30)
            (do (%uc-listen! 0) (%uc-half-lease))
            (do (set! %uc-state %uc-rebinding)
                (ud-log1 "entering rebinding state")
                (%uc-listen! 2)
                (set! %uc-packet-num 0)
                (%uc-rebind)))))))

(def %uc-rebind
  (fn (_)
    (if (if (> %uc-lease 0) (< %uc-packet-num 3) #f)
      (do (%uc-send-renew 0 %uc-requested)
          (set! %uc-timeout %uc-discover-timeout)
          (set! %uc-packet-num (+ %uc-packet-num 1))
          ())
      (do (%uc-listen! 0)
          (ud-info "lease lost, entering init state")
          (%uc-deconfig)
          (set! %uc-state %uc-init)
          (%uc-start-over 0)))))

(def %uc-start-over
  (fn (_ timeout)
    (do (set! %uc-first-secs 0) (set! %uc-timeout timeout) (set! %uc-packet-num 0) ())))

; BOUND_for_half_lease
(def %uc-half-lease
  (fn (_)
    (do (set! %uc-timeout (>> %uc-lease 1)) (set! %uc-state %uc-bound) (set! %uc-packet-num 0) ())))

(def %uc-signal
  (fn (_ sig)
    (match
      ((= sig 10)
       (if (if (<= %uc-state %uc-requesting) #t (= %uc-state %uc-rebinding)) ()
         (do (when (> %uc-lease 30) (set! %uc-lease 30))
             (set! %uc-first-secs 0)
             (set! %uc-packet-num 0)
             (if (if (= %uc-state %uc-bound) #t (= %uc-state %uc-renewing))
               (do (set! %uc-state %uc-renew-requested) (%uc-enter-renew))
               (do (when (= %uc-state %uc-renew-requested) (do (%uc-listen! 0) (%uc-deconfig)))
                   (%uc-listen! 0)
                   (set! %uc-state %uc-init)
                   (set! %uc-timeout 0)
                   ())))))
      ((= sig 12) (do (%uc-perform-release) (set! %uc-timeout 2147483) ()))
      (#t (do (ud-info "received SIGTERM") (%uc-ret0))))))

(def %uc-packet-in
  (fn (_)
    (def p (if (= %uc-listen 1) (ud-recv-kernel %uc-sock) (%uc-recv-raw %uc-sock)))
    (match
      ((number? p)
       (do (when (= p -1)
             (do (ud-error (%str-concat (list "read error: " (libc-strerror (Err errno-of -1)) ", reopening socket")))
                 (sys-usleep (* %uc-discover-timeout 1000000))
                 (%uc-listen! %uc-listen)))
           ()))
      ((not (= (cu-ptr-ref (cu-str->ptr p) ud-xid 4) %uc-xid))
       (ud-log1 (%str-concat (list "xid " (cu-hexs (cu-ptr-ref (cu-str->ptr p) ud-xid 4)) " (our is " (cu-hexs %uc-xid) "), ignoring packet"))))
      ((if (= (ud-byte p ud-hlen) 6) (not (ud-same? (ud-bytes p ud-chaddr 6) %uc-mac)) #t)
       (ud-log1 "chaddr does not match, ignoring packet"))
      (#t
       (let ((m (ud-get-option p 53)))
         (if (null? m) (ud-log1 "no message type option, ignoring packet")
           (%uc-message p (ud-byte p (first m)))))))))

(def %uc-message
  (fn (_ p type)
    (match
      ((= %uc-state %uc-init)
       (when (= type ud-offer)
         (let ((id (ud-get-option32 p 54)))
           (do (when (null? id) (ud-info "no server ID, using 0.0.0.0"))
               (set! %uc-server (if (null? id) 0 id))
               (set! %uc-requested (ud-be32 p ud-yiaddr))
               (ud-log1 (string-append "received offer of " (ud-dotted %uc-requested)))
               (set! %uc-state %uc-requesting)
               (set! %uc-timeout 0)
               (set! %uc-packet-num 0)
               ()))))
      ((if (= %uc-state %uc-bound) #t (= %uc-state %uc-released)) ())
      ((= type ud-ack) (%uc-ack p))
      ((= type ud-nak) (%uc-nak p))
      (#t ()))))

(def %uc-ack
  (fn (_ p)
    (%uc-listen! 0)
    (def yiaddr (ud-be32 p ud-yiaddr))
    (def given (ud-get-option32 p 51))
    (def lease (if (null? given) 3600 given))
    (ud-info (%str-concat (list "lease of " (ud-dotted yiaddr) " obtained from " (ud-dotted %uc-server)
                                ", lease time " (cu-int->str lease) (if (null? given) " (default)" ""))))
    (set! %uc-lease (match ((>= lease 2147483648) 2147483647) ((< lease 30) 30) (#t lease)))
    (set! %uc-requested yiaddr)
    (if (if (null? %uc-arp) #f (= (ud-arpping yiaddr () 0 %uc-mac %uc-iface %uc-arp) 0))
      (do (ud-info "offered address is in use (got ARP reply), declining")
          (%uc-xid!)
          (%uc-send-decline %uc-server yiaddr)
          (unless (= %uc-state %uc-requesting) (%uc-deconfig))
          (set! %uc-state %uc-init)
          (set! %uc-requested 0)
          (%uc-start-over %uc-tryagain))
      (let ((start (%uc-sec)))
        (%uc-script-run p (if (= %uc-state %uc-requesting) "bound" "renew"))
        (set! %uc-lease (let ((l (- %uc-lease (- (%uc-sec) start)))) (if (< l 0) 0 l)))
        (if %uc-quit (%uc-ret0)
          (do (set! %uc-now #f)
              (unless %uc-foreground
                (do (%uc-background!) (set! %uc-background #f) (set! %uc-foreground #t)))
              (%uc-half-lease)))))))

(def %uc-nak
  (fn (_ p)
    (def id (ud-get-option32 p 54))
    (if (not (= (if (null? id) 0 id) %uc-server))
      (ud-log1 "received DHCP NAK with wrong server ID, ignoring packet")
      (do (%uc-listen! 0)
          (ud-info "received DHCP NAK")
          (%uc-script-run p "nak")
          (unless (= %uc-state %uc-requesting) (%uc-deconfig))
          (sys-usleep 3000000)
          (set! %uc-state %uc-init)
          (set! %uc-requested 0)
          (%uc-start-over 0)))))

(def cu-udhcpc
  (fn (_ argv stdin-thunk)
    (ud-process-reset!)
    (def status
      (guard (e (match ((eq? (cu-err-label e) (lit udhcp)) (ud-status))
                       (#t (do (when (ud-child?) (sys-exit 1)) (error e)))))
        (%uc-main argv)))
    (when (ud-child?) (sys-exit status))
    status))

(provide cu/udhcpc cu-udhcpc)

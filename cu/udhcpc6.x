; # x-coreutils -- the small tools, as applets
;
; ## cu/udhcpc6.x -- udhcpc6: busybox's DHCPv6 client
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox 1.36.1's udhcpc6 (networking/udhcp/d6_dhcpc.c, d6_packet.c and
; d6_socket.c), as its defconfig builds it: the RFC 3646, 4704, 4833 and
; 5970 options on, -b on, no -P.
;
; The client multicasts SOLICIT -t times -T seconds apart from its
; link-local address, then REQUESTs from the first ADVERTISE; a REPLY binds
; the lease: the address from its IA_NA, with -d the prefix from its IA_PD,
; with -l neither, an INFORMATION-REQUEST sent in place of each SOLICIT and
; RENEW.  Half way through the lease it renews from the server, then
; multicasts as the end nears, then starts over.  Each event runs -s's
; program with the event's name and the reply's options in the environment:
; deconfig, bound, renew, nak, leasefail.  Without -f the run goes to the
; background once it has a lease; -b goes there when it has none, -n ends
; there, -q ends at the lease.  SIGUSR1 renews, SIGUSR2 releases, SIGTERM
; ends the run, releasing with -R.
;
; Replies are read through a packet socket while there is no lease, and
; through UDP on port 546 while renewing.  The transaction ID and the IAIDs
; are written as busybox writes them, in this machine's byte order.
; busybox's "started, v" line gives the version x-coreutils was installed
; as.

(module cu/udhcpc6)

(import cu/cli cu-opts)
(import cu/inet inet-set!)
(import cu/inetd in-call)
(import cu/nc nc-count)
(import cu/ping pn-af6 pn-byte pn-div pn-now pn-setopt pn-sol-socket)
(import cu/prims append byte-at byte-len cu-err-label cu-hexs cu-int->ptr
  cu-int->str cu-libc-sym cu-nth cu-ptr->str cu-ptr-call cu-ptr-ref
  cu-ptr-word cu-str->ptr file-close length libc-strerror map reverse
  string-append string=? substring sys-exit sys-usleep)
(import cu/udhcp ud-6rd ud-be16! ud-bytes ud-bytes-be ud-catch! ud-child?
  ud-cksum ud-daemonize! ud-die ud-dname-dec ud-dns-string ud-errno
  ud-error ud-find-option ud-info ud-list ud-listen6 ud-log1 ud-log2
  ud-logging! ud-mac-text ud-ms ud-nip6 ud-optflag-named ud-perror
  ud-process-reset! ud-put! ud-remove-pidfile ud-req ud-set! ud-sin6 ud-spawn
  ud-status ud-str2optset ud-string ud-strtou ud-taken ud-text ud-verbose
  ud-write-pidfile ud-zeros)
(import cu/vi vi-bundle-version)

; --- the run's settings and state -------------------------------------------------------

; d6_optflags and d6_option_strings: (FLAGS CODE NAME)
(def %u6-optflags
  (list (list (+ ud-6rd ud-list ud-req) 23 "dns") (list (+ ud-dns-string ud-list ud-req) 24 "search")
        (list ud-dns-string 39 "fqdn") (list ud-string 41 "tz") (list ud-string 42 "timezone")
        (list ud-string 59 "bootfile_url") (list ud-string 60 "bootfile_param")
        (list ud-string 209 "pxeconffile") (list ud-string 210 "pxepathprefix")))

(def %u6-zero16 (list 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0))
(def %u6-all-servers (list 255 2 0 0 0 0 0 0 0 0 0 0 0 1 0 2))   ; ff02::1:2
(def %u6-all-servers-mac (list 51 51 0 1 0 2))

(def %u6-iface "eth0")
(def %u6-script "/usr/share/udhcpc/default6.script")
(def %u6-pidfile ())
(def %u6-ifindex 0)
(def %u6-mac (list 0 0 0 0 0 0))
(def %u6-ll %u6-zero16)          ; the link-local address
(def %u6-options ())             ; what is sent: -x, the client ID
(def %u6-clientid #f)            ; the client ID is ours, the MAC in it
(def %u6-mask ())                ; the codes asked for, ascending

(def %u6-discover-timeout 3)
(def %u6-discover-retries 3)
(def %u6-tryagain 20)
(def %u6-background #f)          ; -b
(def %u6-now #f)                 ; -n
(def %u6-foreground #f)          ; -f
(def %u6-quit #f)                ; -q
(def %u6-release #f)             ; -R
(def %u6-stateless #f)           ; -l
(def %u6-want-addr #t)           ; an address asked for: not -l, not -r no
(def %u6-prefix #f)              ; -d
(def %u6-syslog #f)

; the states
(def %u6-init 0)
(def %u6-requesting 1)
(def %u6-bound 2)
(def %u6-renewing 3)
(def %u6-rebinding 4)
(def %u6-renew-requested 5)
(def %u6-released 6)

(def %u6-state 0)
(def %u6-xid 0)
(def %u6-first-secs 0)
(def %u6-sock -1)
(def %u6-listen 0)               ; 0 none, 1 kernel, 2 raw
(def %u6-timeout 0)
(def %u6-lease 0)
(def %u6-packet-num 0)
(def %u6-server-id ())           ; the options as sent: code, length, data
(def %u6-ia-na ())
(def %u6-ia-pd ())
(def %u6-srv6 %u6-zero16)        ; where the last raw packet came from
(def %u6-requested ())           ; the address asked for, or nil
(def %u6-leased #f)              ; it is the one the last REPLY gave

(def %u6-sec (fn (_) (pn-div (pn-now) 1000000)))
(def %u6-rand (fn (_) (in-call (cu-ptr-call (cu-libc-sym "rand")))))
; random_xid: three random bytes after the one the type takes
(def %u6-xid! (fn (_) (set! %u6-xid (& (%u6-rand) 4294967040))))

; --- bytes --------------------------------------------------------------------------------

(def %u6-host32 (fn (_ n) (list (& n 255) (& (>> n 8) 255) (& (>> n 16) 255) (& (>> n 24) 255))))
(def %u6-be16 (fn (_ n) (list (& (>> n 8) 255) (& n 255))))
(def %u6-opt (fn (_ code data) (append (%u6-be16 code) (%u6-be16 (length data)) data)))

; the N bytes of L from I, zeros past its end
(def %u6-at
  (fn (_ l i n)
    (let go ((k (- n 1)) (acc ()))
      (if (< k 0) acc
        (go (- k 1) (pair (let ((t (List drop (+ i k) l))) (if (null? t) 0 (first t))) acc))))))
(def %u6-be32-at (fn (_ l i) (ud-bytes-be (%u6-at l i 4))))
; d6_xid32, as this machine reads it
(def %u6-xid-of (fn (_ p) (ud-bytes-be (reverse (%u6-at p 0 4)))))

(def %u6-upto-nul
  (fn (_ l) (let go ((left l) (acc ())) (if (if (null? left) #t (= (first left) 0)) (reverse acc) (go (rest left) (pair (first left) acc))))))

(def %u6-buffer (fn (_ l) (let ((b (ud-zeros (length l)))) (do (ud-put! b 0 l) b))))

; d6_find_option: the option of CODE among the options L, L from it on; nil
; where none is, or one before it runs past L or has a code or length over
; 255
(def %u6-find
  (fn (_ l code)
    (let go ((l l) (left (- (length l) 4)))
      (match ((< left 0) ())
             ((> (cu-nth 3 l) left) ())
             ((if (= (first l) 0) (not (= (cu-nth 2 l) 0)) #t) ())
             ((= (cu-nth 1 l) code) l)
             (#t (let ((k (+ (cu-nth 3 l) 4))) (go (List drop k l) (- left k))))))))

; d6_copy_option: the option alone
(def %u6-copy
  (fn (_ l code) (let ((o (%u6-find l code))) (if (null? o) () (List take (+ (cu-nth 3 o) 4) o)))))

; --- the script --------------------------------------------------------------------------

; option_to_env: the variables the options L give, in their order
(def %u6-option-env
  (fn (self l)
    (let go ((l l) (left (- (length l) 4)) (acc ()))
      (if (match ((< left 0) #t) ((not (= (first l) 0)) #t) ((not (= (cu-nth 2 l) 0)) #t) (#t (> (cu-nth 3 l) left)))
        (reverse acc)
        (let ((code (cu-nth 1 l)) (len (cu-nth 3 l)))
          (def data (List take len (List drop 4 l)))
          (def text (fn (_ name) (string-append name (ud-text (%u6-upto-nul data)))))
          (def items
            (match
              ((if (= code 3) #t (= code 25)) (self (List drop 12 data)))
              ((= code 5)
               (if (< len 24) ()
                 (list (string-append "ipv6=" (ud-nip6 (List take 16 data)))
                       (string-append "lease=" (cu-int->str (%u6-be32-at data 20))))))
              ((= code 26)
               (let ((at (List drop 4 l)))
                 (list (string-append "ipv6prefix_lease=" (cu-int->str (%u6-be32-at at 4)))
                       (%str-concat (list "ipv6prefix=" (ud-nip6 (%u6-at at 9 16)) "/" (cu-int->str (first (%u6-at at 8 1))))))))
              ((= code 23)
               (if (not (= (& len 15) 0)) ()
                 (list (string-append "dns="
                         (Str8 join " " (let addrs ((d data) (out ()))
                                          (if (null? d) (reverse out) (addrs (List drop 16 d) (pair (ud-nip6 (List take 16 d)) out)))))))))
              ((= code 24) (let ((d (ud-dname-dec data "search="))) (if (null? d) () (list d))))
              ((= code 39)
               (match ((= len 0) ())
                      ((not (= (& (first data) 248) 0)) (list (text "fqdn=")))
                      (#t (let ((d (ud-dname-dec (rest data) "fqdn="))) (if (null? d) () (list d))))))
              ((= code 41) (list (text "tz=")))
              ((= code 42) (list (text "tz_name=")))
              ((List find (fn (_ c) (= c code)) (list 59 60 209 210))
               (let ((f (List find (fn (_ f) (= (cu-nth 1 f) code)) %u6-optflags)))
                 (list (text (string-append (cu-nth 2 f) "=")))))
              (#t ())))
          (go (List drop (+ 4 len) l) (- left (+ 4 len)) (append (reverse items) acc)))))))

; d6_run_script: OPTIONS' variables, nil for none, then EVENT's run
(def %u6-script-run
  (fn (_ options event)
    (def env (pair (string-append "interface=" %u6-iface) (%u6-option-env options)))
    (ud-log1 (%str-concat (list "executing " %u6-script " " event)))
    (ud-spawn (list %u6-script event)
              (map (fn (_ s)
                     (let ((eq (let go ((i 0)) (if (= (byte-at s i) #\=) i (go (+ i 1))))))
                       (pair (substring s 0 eq) (substring s (+ eq 1) (byte-len s)))))
                   env))
    (map (fn (_ s) (ud-log2 (string-append " " s))) env)))

(def %u6-deconfig (fn (_) (%u6-script-run () "deconfig")))

; --- sending ------------------------------------------------------------------------------

(def %u6-dump
  (fn (_ p) (ud-log2 (string-append " xid " (cu-hexs (%u6-xid-of p))))))

; init_d6_packet: type, transaction ID, ELAPSED_TIME
(def %u6-packet
  (fn (_ type)
    (def now (%u6-sec))
    (when (= %u6-first-secs 0) (set! %u6-first-secs now))
    (def secs (- now %u6-first-secs))
    (append (pair type (rest (%u6-host32 %u6-xid)))
            (list 0 8 0 2) (%u6-be16 (if (< secs 65535) secs 65535)))))

; add_d6_client_options: the codes asked for, the FQDN asked for, what is sent
(def %u6-client-options
  (fn (_)
    (append (if (null? %u6-mask) () (%u6-opt 6 (List fold (fn (_ acc c) (append acc (list 0 c))) () %u6-mask)))
            (list 0 39 0 2 0 0)
            (List fold (fn (_ acc o) (append acc (%u6-be16 (first o)) (%u6-be16 (cu-nth 1 o)) (rest (rest o))))
                       () %u6-options))))

(def %u6-ias (fn (_) (append %u6-server-id %u6-ia-na %u6-ia-pd)))

; d6_send_raw_packet: P in IPv6 and UDP headers of our own, from SRC:SPORT
; to DST:DPORT at hardware address DMAC; the hop limit 1
(def %u6-send-raw
  (fn (_ p src sport dst dport dmac)
    (def fd (in-call (cu-ptr-call (cu-libc-sym "socket") 17 2 56710)))
    (if (< fd 0) (do (ud-perror "socket(PACKET)" (ud-errno fd)) -1)
      (let ((sll (ud-zeros 20)) (size (length p)))
        (inet-set! sll 0 17 2)
        (ud-be16! sll 2 34525)
        (inet-set! sll 4 %u6-ifindex 4)
        (ud-set! sll 11 6)
        (ud-put! sll 12 dmac)
        (if (< (in-call (cu-ptr-call (cu-libc-sym "bind") fd (cu-str->ptr sll) 20)) 0)
          (let ((e (Err errno-of -1))) (do (file-close fd) (ud-perror "bind(PACKET)" e) -1))
          (let ((b (ud-zeros (+ 48 size))))
            (ud-set! b 0 96)
            (ud-be16! b 4 (+ 8 size))
            (ud-put! b 8 src)
            (ud-put! b 24 dst)
            (ud-be16! b 40 sport)
            (ud-be16! b 42 dport)
            (ud-be16! b 44 (+ 8 size))
            (ud-put! b 48 p)
            ; the sum skips the header's first four bytes and takes the
            ; next header one byte to its right
            (ud-set! b 7 17)
            (ud-be16! b 46 (ud-cksum b 4 (+ 48 size)))
            (ud-set! b 7 1)
            (ud-set! b 6 17)
            (%u6-dump p)
            (let ((r (in-call (cu-ptr-call (cu-libc-sym "sendto") fd (cu-str->ptr b) (+ 48 size) 0 (cu-str->ptr sll) 20))))
              (let ((e (Err errno-of r)))
                (do (file-close fd)
                    (when (< r 0) (ud-perror "sendto" e))
                    r)))))))))

; d6_send_kernel_packet: P through the kernel's UDP, from SRC:546 to
; DST:547 on the interface
(def %u6-send-kernel
  (fn (_ p src dst)
    (def fd (in-call (cu-ptr-call (cu-libc-sym "socket") pn-af6 2 17)))
    (def fail
      (fn (_ what r)
        (let ((e (Err errno-of r))) (do (file-close fd) (ud-perror what e) -1))))
    (if (< fd 0) (do (ud-perror "socket(UDP)" (ud-errno fd)) -1)
      (do (pn-setopt fd pn-sol-socket 2 1)
          (let ((rb (in-call (cu-ptr-call (cu-libc-sym "bind") fd (cu-str->ptr (ud-sin6 src 546 0)) 28))))
            (if (< rb 0) (fail "bind(UDP)" rb)
              (let ((rc (in-call (cu-ptr-call (cu-libc-sym "connect") fd (cu-str->ptr (ud-sin6 dst 547 %u6-ifindex)) 28))))
                (if (< rc 0) (fail "connect" rc)
                  (do (%u6-dump p)
                      (let ((rw (in-call (cu-ptr-call (cu-libc-sym "write") fd (cu-str->ptr (%u6-buffer p)) (length p)))))
                        (if (< rw 0) (fail "write" rw)
                          (do (file-close fd) rw))))))))))))

(def %u6-mcast
  (fn (_ p) (%u6-send-raw p %u6-ll 546 %u6-all-servers 547 %u6-all-servers-mac)))

(def %u6-send-info
  (fn (_)
    (def p (append (%u6-packet 11) (%u6-client-options)))
    (ud-error "sending info request")
    (%u6-mcast p)))

; the IA_NA asked for, an IAADDR in it for REQUESTED; the IA_PD with -d.
; An address a REPLY gave is read by busybox from the IA_NA it frees for
; the new one, which takes its place zeroed, so the IAADDR's is zeros
(def %u6-send-discover
  (fn (_ asked)
    (def requested (if (if %u6-leased (not (null? asked)) #f) %u6-zero16 asked))
    (when %u6-leased (set! %u6-requested requested))
    (def head (%u6-packet 1))
    (set! %u6-ia-na
      (if (not %u6-want-addr) ()
        (%u6-opt 3 (append (%u6-host32 (%u6-rand)) (list 0 0 0 0 0 0 0 0)
                           (if (null? requested) () (%u6-opt 5 (append requested (list 0 0 0 0 0 0 0 0))))))))
    (set! %u6-ia-pd
      (if (not %u6-prefix) () (%u6-opt 25 (append (%u6-host32 (%u6-rand)) (list 0 0 0 0 0 0 0 0)))))
    (def p (append head %u6-ia-na %u6-ia-pd (%u6-client-options)))
    (ud-info "sending discover")
    (%u6-mcast p)))

(def %u6-send-select
  (fn (_)
    (def p (append (%u6-packet 3) (%u6-ias) (%u6-client-options)))
    (ud-info "sending select")
    (%u6-mcast p)))

; SERVER nil multicasts it
(def %u6-send-renew
  (fn (_ server ours)
    (def p (append (%u6-packet 5) (%u6-ias) (%u6-client-options)))
    (ud-info "sending renew")
    (if (null? server) (%u6-mcast p)
      (%u6-send-kernel p (if (null? ours) %u6-zero16 ours) server))))

; the client ID, its first 14 bytes, where it leads what is sent
(def %u6-send-release
  (fn (_ server ours)
    (def ci (ud-find-option %u6-options 1))
    (def p (append (%u6-packet 8) (%u6-ias)
                   (if (null? ci) () (%u6-at (append (%u6-be16 (first ci)) (%u6-be16 (cu-nth 1 ci)) (rest (rest ci))) 0 14))))
    (ud-info "sending release")
    (%u6-send-kernel p (if (null? ours) %u6-zero16 ours) server)))

; --- receiving ----------------------------------------------------------------------------

; d6_recv_raw_packet: the DHCPv6 packet in what the packet socket FD read,
; its sender kept; -1 where the read failed, -2 where it is not one for us
(def %u6-recv-raw
  (fn (_ fd)
    (def b (ud-zeros 656))
    (def n (let go () (let ((r (in-call (cu-ptr-call (cu-libc-sym "read") fd (cu-str->ptr b) 656))))
                        (if (if (< r 0) (= (Err errno-of r) 4) #f) (go) r))))
    (def be16 (fn (_ i) (+ (* (pn-byte (cu-str->ptr b) i) 256) (pn-byte (cu-str->ptr b) (+ i 1)))))
    (def ignore (fn (_ why) (do (ud-log1 why) -2)))
    (match
      ((< n 0) (do (ud-log1 "packet read error, ignoring") n))
      ((< n 48) (ignore "packet is too short, ignoring"))
      ((< n (+ 40 (be16 4))) (ignore "oversized packet, ignoring"))
      ((match ((not (= (pn-byte (cu-str->ptr b) 6) 17)) #t)
              ((not (= (>> (pn-byte (cu-str->ptr b) 0) 4) 6)) #t)
              ((not (= (be16 42) 546)) #t)
              (#t (not (= (be16 44) (be16 4)))))
       (ignore "unrelated/bogus packet, ignoring"))
      (#t
       (do (set! %u6-srv6 (ud-bytes b 8 16))
           (ud-log2 "received a packet")
           (let ((p (ud-bytes b 48 (if (< (be16 4) 8) 0 (- (be16 4) 8)))))
             (do (%u6-dump p) p)))))))

; d6_recv_kernel_packet
(def %u6-recv-kernel
  (fn (_ fd)
    (def b (ud-zeros 608))
    (def n (let go () (let ((r (in-call (cu-ptr-call (cu-libc-sym "read") fd (cu-str->ptr b) 608))))
                        (if (if (< r 0) (= (Err errno-of r) 4) #f) (go) r))))
    (match ((< n 0) (do (ud-log1 "packet read error, ignoring") n))
           ((< n 4) (do (ud-info "packet with bad magic, ignoring") -2))
           (#t (let ((p (ud-bytes b 0 n))) (do (ud-log2 "received a packet") (%u6-dump p) p))))))

; --- the interface and listening ------------------------------------------------------------

(def %u6-family
  (fn (_ sa) (if os-darwin? (pn-byte sa 1) (cu-ptr-ref sa 0 2))))

; d6_read_interface: the MAC and ifindex from the interface's packet
; address, its last link-local address; #f where either is not had, said.
; An interface with no MAC has one made up, once.
(def %u6-interface!
  (fn (_)
    (def pp (ud-zeros 8))
    (cu-ptr-call (cu-libc-sym "getifaddrs") (cu-str->ptr pp))
    (def head (cu-ptr-word (cu-str->ptr pp) 0))
    (def got
      (let go ((a head) (mac #f) (ll #f))
        (if (= a 0) (pair mac ll)
          (let ((p (cu-int->ptr a)))
            (def next (cu-ptr-word p 0))
            (def addr (cu-ptr-word p 24))
            (if (if (= addr 0) #t (not (string=? (cu-ptr->str (cu-int->ptr (cu-ptr-word p 8))) %u6-iface)))
              (go next mac ll)
              (let ((sa (cu-int->ptr addr)))
                (def fam (%u6-family sa))
                (def is-mac (= fam 17))
                (when is-mac
                  (do (set! %u6-mac (map (fn (_ i) (pn-byte sa (+ 12 i))) (list 0 1 2 3 4 5)))
                      (ud-log2 (string-append "MAC " (ud-mac-text %u6-mac)))
                      (set! %u6-ifindex (cu-ptr-ref sa 4 4))
                      (ud-log2 (string-append "ifindex " (cu-int->str %u6-ifindex)))))
                (def is-ll (if (= fam pn-af6) (if (= (pn-byte sa 8) 254) (= (& (pn-byte sa 9) 192) 128) #f) #f))
                (when is-ll
                  (do (set! %u6-ll (map (fn (_ i) (pn-byte sa (+ 8 i))) (List range 0 16)))
                      (ud-log1 (string-append "IPv6 " (ud-nip6 %u6-ll)))))
                (go next (if is-mac #t mac) (if is-ll #t ll))))))))
    (unless (= head 0) (cu-ptr-call (cu-libc-sym "freeifaddrs") head))
    (def mac (if (first got) #t (%u6-made-mac)))
    (unless mac (ud-error "can't get MAC"))
    (unless (rest got) (ud-error "can't get link-local IPv6 address"))
    (if mac (rest got) #f)))

; no packet address: the ifindex asked of the kernel, a MAC made up
(def %u6-made-mac
  (fn (_)
    (def fd (in-call (cu-ptr-call (cu-libc-sym "socket") pn-af6 3 255)))
    (when (< fd 0) (ud-die (string-append "socket: " (libc-strerror (ud-errno fd)))))
    (def ifr (ud-zeros 40))
    (cu-ptr-call (cu-libc-sym "memcpy") (cu-str->ptr ifr) %u6-iface (if (> (byte-len %u6-iface) 15) 15 (byte-len %u6-iface)))
    (def ok (= (in-call (cu-ptr-call (cu-libc-sym "ioctl") fd 35123 (cu-str->ptr ifr))) 0))
    (when ok
      (do (set! %u6-ifindex (cu-ptr-ref (cu-str->ptr ifr) 16 4))
          (ud-log2 (string-append "ifindex " (cu-int->str %u6-ifindex)))
          (when (= (ud-bytes-be (List take 4 %u6-mac)) 0)
            (let ((m (append (%u6-host32 (%u6-rand)) (List take 2 (%u6-host32 (%u6-rand))))))
              (set! %u6-mac (pair (& (first m) 252) (rest m)))))))
    (file-close fd)
    ok))

; d6_raw_socket
(def %u6-raw-socket
  (fn (_ ifindex)
    (ud-log2 (string-append "opening raw socket on ifindex " (cu-int->str ifindex)))
    (def fd (in-call (cu-ptr-call (cu-libc-sym "socket") 17 2 56710)))
    (when (< fd 0) (ud-die (string-append "socket: " (libc-strerror (ud-errno fd)))))
    (def sll (ud-zeros 20))
    (inet-set! sll 0 17 2)
    (ud-be16! sll 2 34525)
    (inet-set! sll 4 ifindex 4)
    (let ((r (in-call (cu-ptr-call (cu-libc-sym "bind") fd (cu-str->ptr sll) 20))))
      (when (< r 0) (ud-die (string-append "bind: " (libc-strerror (ud-errno r))))))
    fd))

; change_listen_mode
(def %u6-listen!
  (fn (_ mode)
    (ud-log1 (string-append "entering listen mode: " (match ((= mode 0) "none") ((= mode 1) "kernel") (#t "raw"))))
    (set! %u6-listen mode)
    (when (>= %u6-sock 0) (do (file-close %u6-sock) (set! %u6-sock -1)))
    (match ((= mode 1) (set! %u6-sock (ud-listen6 546 %u6-iface)))
           ((= mode 2) (set! %u6-sock (%u6-raw-socket %u6-ifindex)))
           (#t ()))))

; perform_d6_release
(def %u6-perform-release
  (fn (_)
    (%u6-listen! 0)
    (when (match ((= %u6-state %u6-bound) #t) ((= %u6-state %u6-renewing) #t)
                 ((= %u6-state %u6-rebinding) #t) (#t (= %u6-state %u6-renew-requested)))
      (do (ud-info "unicasting a release")
          (%u6-xid!)
          (%u6-send-release %u6-srv6 %u6-requested)))
    (ud-info "entering released state")
    (%u6-deconfig)
    (set! %u6-state %u6-released)))

; client_background
(def %u6-background!
  (fn (_)
    (ud-daemonize!)
    (ud-logging! "udhcpc6" (ud-verbose) #f %u6-syslog)
    (ud-write-pidfile %u6-pidfile)))

; --- the options ----------------------------------------------------------------------

; xatoi_positive
(def %u6-number
  (fn (_ s)
    (let ((r (ud-strtou s 10)))
      (match ((not (rest r)) (ud-die (%str-concat (list "invalid number '" s "'"))))
             ((> (first r) 2147483647) (ud-die (%str-concat (list "number " s " is not in 0..2147483647 range"))))
             (#t (first r))))))

(def %u6-ask!
  (fn (_ code)
    (unless (List find (fn (_ c) (= c code)) %u6-mask)
      (set! %u6-mask (let go ((l %u6-mask)) (if (if (null? l) #t (> (first l) code)) (pair code l) (pair (first l) (go (rest l)))))))))

; inet_pton: the 16 bytes S names, or nil
(def %u6-pton
  (fn (_ s)
    (let ((b (ud-zeros 16)))
      (if (= (in-call (cu-ptr-call (cu-libc-sym "inet_pton") pn-af6 s (cu-str->ptr b))) 1) (ud-bytes b 0 16) ()))))

(def %u6-setup
  (fn (_ o)
    (set! %u6-iface (Opts value o "-i" "eth0"))
    (set! %u6-script (Opts value o "-s" "/usr/share/udhcpc/default6.script"))
    (set! %u6-pidfile (Opts value o "-p"))
    (set! %u6-options ())
    (set! %u6-mask ())
    (set! %u6-mac (list 0 0 0 0 0 0))
    (set! %u6-ll %u6-zero16)
    (set! %u6-ifindex 0)
    (set! %u6-background (Opts on? o "-b"))
    (set! %u6-now (Opts on? o "-n"))
    (set! %u6-foreground (Opts on? o "-f"))
    (set! %u6-quit (Opts on? o "-q"))
    (set! %u6-release (Opts on? o "-R"))
    (set! %u6-stateless (Opts on? o "-l"))
    (set! %u6-prefix (Opts on? o "-d"))
    (set! %u6-discover-timeout (%u6-number (Opts value o "-T" "3")))
    (set! %u6-discover-retries (%u6-number (Opts value o "-t" "3")))
    (set! %u6-tryagain (%u6-number (Opts value o "-A" "20")))
    (set! %u6-requested ())
    (set! %u6-leased #f)
    (set! %u6-want-addr (not %u6-stateless))
    (let ((r (Opts value o "-r")))
      (unless (if %u6-stateless #t (null? r))
        (if (string=? r "no") (set! %u6-want-addr #f)
          (let ((a (%u6-pton r)))
            (if (null? a) (ud-die (%str-concat (list "bad IPv6 address '" r "'"))) (set! %u6-requested a))))))
    (map (fn (_ s)
           (let ((r (ud-strtou s 0)))
             (%u6-ask! (if (if (rest r) (<= (first r) 254) #f) (first r) (cu-nth 1 (ud-optflag-named s %u6-optflags))))))
         (Opts values o "-O"))
    (unless (Opts on? o "-o")
      (map (fn (_ f) (unless (= (& (first f) ud-req) 0) (%u6-ask! (cu-nth 1 f)))) %u6-optflags))
    (map (fn (_ x) (set! %u6-options (rest (ud-str2optset x %u6-options %u6-optflags #t)))) (Opts values o "-x"))
    (set! %u6-clientid (null? (ud-find-option %u6-options 1)))
    (when %u6-clientid
      (do (ud-log2 "attaching option 01 to list")
          (set! %u6-options (append %u6-options (list (list 1 10 0 3 0 1 0 0 0 0 0 0))))))))

; the client ID made here, the MAC read last in it
(def %u6-clientid!
  (fn (_)
    (when %u6-clientid
      (set! %u6-options (append (List take (- (length %u6-options) 1) %u6-options)
                                (list (append (list 1 10 0 3 0 1) %u6-mac)))))))

; --- the run ----------------------------------------------------------------------------

(def %u6-main
  (fn (_ argv)
    (def o (cu-opts "udhcpc6" argv))
    (set! %u6-syslog (Opts on? o "-S"))
    (ud-logging! "udhcpc6" (nc-count o "-v") #t #f)
    (ud-catch!)
    (%u6-setup o)
    (if (not (%u6-interface!)) 1
      (do (when %u6-syslog (do (cu-ptr-call (cu-libc-sym "openlog") "udhcpc6" 1 24)
                               (ud-logging! "udhcpc6" (ud-verbose) #t #t)))
          (ud-write-pidfile %u6-pidfile)
          (ud-info (string-append "started, v" (vi-bundle-version)))
          (cu-ptr-call (cu-libc-sym "srand") (& (pn-now) 4294967295))
          (set! %u6-state %u6-init)
          (set! %u6-sock -1)
          (set! %u6-listen 0)
          (set! %u6-first-secs 0)
          (set! %u6-server-id ())
          (set! %u6-ia-na ())
          (set! %u6-ia-pd ())
          (set! %u6-srv6 %u6-zero16)
          (%u6-deconfig)
          (set! %u6-packet-num 0)
          (set! %u6-timeout 0)
          (set! %u6-lease 0)
          (let ((status (%u6-loop)))
            (do (ud-remove-pidfile %u6-pidfile) status))))))

; the run ends with STATUS; anything else a pass answers goes on
(def %u6-end (fn (_ status) (list (lit end) status)))
(def %u6-end? (fn (_ r) (if (pair? r) (eq? (first r) (lit end)) #f)))

; the run's way out: 0, released first with -R
(def %u6-ret0
  (fn (_) (do (when %u6-release (%u6-perform-release)) (%u6-end 0))))

; the main loop; each pass answers a timeout, a signal or a packet
(def %u6-loop
  (fn (self)
    (Heap collect)
    (def event (if (> %u6-timeout 0) (%u6-wait) (lit timeout)))
    (def r
      (match ((eq? event (lit timeout)) (%u6-timed-out))
             ((eq? event (lit packet)) (%u6-packet-in))
             (#t (%u6-signal event))))
    (if (%u6-end? r) (first (rest r)) (self))))

; the poll: half a second at a time, the signals looked at between;
; timeout, packet, or the signal's number
(def %u6-wait
  (fn (_)
    (when (> %u6-timeout 2147483) (set! %u6-timeout 2147483))
    (ud-log1 (%str-concat (list "waiting " (cu-int->str %u6-timeout) " seconds")))
    (def before (%u6-sec))
    (def end (+ (ud-ms) (* %u6-timeout 1000)))
    (def event
      (let go ()
        (let ((sig (ud-taken)) (left (- end (ud-ms))))
          (match ((not (null? sig)) sig)
                 ((<= left 0) (lit timeout))
                 (#t (let ((slice (if (> left 500) 500 left)))
                       (if (< %u6-sock 0) (do (sys-usleep (* slice 1000)) (go))
                         (if (null? (Sys poll (list (pair %u6-sock (list (lit in)))) slice)) (go) (lit packet)))))))))
    (def diff (- (%u6-sec) before))
    (set! %u6-lease (if (< (- %u6-lease diff) 0) 0 (- %u6-lease diff)))
    (set! %u6-timeout (if (< (- %u6-timeout diff) 0) 0 (- %u6-timeout diff)))
    event))

(def %u6-tries-left?
  (fn (_) (if (= %u6-discover-retries 0) #t (< %u6-packet-num %u6-discover-retries))))
(def %u6-sent
  (fn (_) (do (set! %u6-timeout %u6-discover-timeout) (set! %u6-packet-num (+ %u6-packet-num 1)) ())))

; the timeout's work, by state; a number ends the run
(def %u6-timed-out
  (fn (_)
    (if (not (%u6-interface!)) (%u6-ret0)
      (do (%u6-clientid!)
          (match
            ((= %u6-state %u6-init) (%u6-selecting))
            ((= %u6-state %u6-requesting)
             (if (%u6-tries-left?)
               (do (%u6-send-select) (%u6-sent))
               (do (set! %u6-state %u6-init) (%u6-leasefail))))
            ((= %u6-state %u6-bound)
             (do (set! %u6-state %u6-renewing) (set! %u6-first-secs 0) (%u6-enter-renew)))
            ((if (= %u6-state %u6-renewing) #t (= %u6-state %u6-renew-requested)) (%u6-renew))
            ((= %u6-state %u6-rebinding) (%u6-rebind))
            (#t (do (set! %u6-timeout 2147483) ())))))))

(def %u6-selecting
  (fn (_)
    (if (%u6-tries-left?)
      (do (when (= %u6-packet-num 0) (do (%u6-listen! 2) (%u6-xid!)))
          (if %u6-stateless (%u6-send-info) (%u6-send-discover %u6-requested))
          (%u6-sent))
      (%u6-leasefail))))

(def %u6-leasefail
  (fn (_)
    (%u6-listen! 0)
    (%u6-script-run () "leasefail")
    (match
      (%u6-background
       (do (ud-info "no lease, forking to background")
           (%u6-background!)
           (set! %u6-background #f) (set! %u6-now #f) (set! %u6-foreground #t)
           (%u6-try-again)))
      (%u6-now (do (ud-info "no lease, failing") (%u6-end 1)))
      (#t (%u6-try-again)))))

(def %u6-try-again
  (fn (_) (do (set! %u6-timeout %u6-tryagain) (set! %u6-packet-num 0) ())))

; got_SIGUSR1: into the renew
(def %u6-enter-renew
  (fn (_) (do (ud-log1 "entering renew state") (%u6-listen! 1) (%u6-renew))))

(def %u6-renew
  (fn (_)
    (if (= %u6-packet-num 0)
      (do (if %u6-stateless (%u6-send-info) (%u6-send-renew %u6-srv6 %u6-requested))
          (%u6-sent))
      (do (ud-log1 "no response to renew")
          (if (> %u6-lease 30)
            (do (%u6-listen! 0) (%u6-half-lease))
            (do (set! %u6-state %u6-rebinding)
                (ud-log1 "entering rebinding state")
                (%u6-listen! 2)
                (set! %u6-packet-num 0)
                (%u6-rebind)))))))

(def %u6-rebind
  (fn (_)
    (if (if (> %u6-lease 0) (< %u6-packet-num 3) #f)
      (do (if %u6-stateless (%u6-send-info) (%u6-send-renew () %u6-requested))
          (%u6-sent))
      (do (%u6-listen! 0)
          (ud-info "lease lost, entering init state")
          (%u6-deconfig)
          (set! %u6-state %u6-init)
          (%u6-start-over)))))

(def %u6-start-over
  (fn (_) (do (set! %u6-first-secs 0) (set! %u6-timeout 0) (set! %u6-packet-num 0) ())))

; BOUND_for_half_lease
(def %u6-half-lease
  (fn (_)
    (do (set! %u6-timeout (>> %u6-lease 1)) (set! %u6-state %u6-bound) (set! %u6-packet-num 0) ())))

(def %u6-signal
  (fn (_ sig)
    (match
      ((= sig 10)
       (if (if (<= %u6-state %u6-requesting) #t (= %u6-state %u6-rebinding)) ()
         (do (when (> %u6-lease 30) (set! %u6-lease 30))
             (set! %u6-first-secs 0)
             (set! %u6-packet-num 0)
             (if (if (= %u6-state %u6-bound) #t (= %u6-state %u6-renewing))
               (do (%u6-listen! 1) (set! %u6-state %u6-renew-requested) (%u6-enter-renew))
               (do (when (= %u6-state %u6-renew-requested) (do (%u6-listen! 0) (%u6-deconfig)))
                   (%u6-listen! 0)
                   (set! %u6-state %u6-init)
                   (set! %u6-timeout 0)
                   ())))))
      ((= sig 12) (do (%u6-perform-release) (set! %u6-timeout 2147483) ()))
      (#t (do (ud-info "received SIGTERM") (%u6-ret0))))))

(def %u6-packet-in
  (fn (_)
    (def p (if (= %u6-listen 1) (%u6-recv-kernel %u6-sock) (%u6-recv-raw %u6-sock)))
    (match
      ((number? p)
       (do (when (= p -1)
             (do (ud-error (%str-concat (list "read error: " (libc-strerror (Err errno-of -1)) ", reopening socket")))
                 (sys-usleep (* %u6-discover-timeout 1000000))
                 (%u6-listen! %u6-listen)))
           ()))
      ((not (= (& (%u6-xid-of p) 4294967040) %u6-xid))
       (ud-log1 (%str-concat (list "xid " (cu-hexs (& (%u6-xid-of p) 4294967040)) " (our is " (cu-hexs %u6-xid) "), ignoring packet"))))
      (#t (%u6-message (first (%u6-at p 0 1)) (List drop 4 p))))))

; TYPE and the OPTIONS of a packet that is ours: an ADVERTISE while
; selecting, a REPLY while asking
(def %u6-message
  (fn (_ type options)
    (match
      ((= %u6-state %u6-init) (when (if (= type 2) #t (= type 7)) (%u6-type-ok type options)))
      ((match ((= %u6-state %u6-requesting) #t) ((= %u6-state %u6-renewing) #t)
              ((= %u6-state %u6-renew-requested) #t) (#t (= %u6-state %u6-rebinding)))
       (when (= type 7) (%u6-type-ok type options)))
      (#t ()))))

(def %u6-type-ok
  (fn (_ type options)
    (%u6-listen! 0)
    (def status (%u6-find options 13))
    (if (if (null? status) #f (not (= (ud-bytes-be (%u6-at status 4 2)) 0)))
      (do (ud-info (%str-concat (list "received DHCP NAK (" (cu-int->str (first (%u6-at status 8 1))) ")")))
          (%u6-script-run options "nak")
          (unless (= %u6-state %u6-requesting) (%u6-deconfig))
          (sys-usleep 3000000)
          (set! %u6-state %u6-init)
          (set! %u6-requested ())
          (set! %u6-leased #f)
          (%u6-start-over))
      (let ((sid (%u6-copy options 2)))
        (match
          ((null? sid) (do (ud-info "no server ID, ignoring packet") ()))
          ((= type 2)
           (do (set! %u6-server-id sid)
               (%u6-listen! 2)
               (set! %u6-state %u6-requesting)
               (set! %u6-timeout 0)
               (set! %u6-packet-num 0)
               ()))
          (#t (do (set! %u6-server-id sid) (%u6-reply options))))))))

; the lease's seconds from IA_NA's IAADDR, or ignore where it has none
(def %u6-take-na
  (fn (_ options)
    (set! %u6-ia-na (%u6-copy options 3))
    (def say (fn (_ msg) (do (ud-info msg) (lit ignore))))
    (match
      ((null? %u6-ia-na) (say "no IA_NA option, ignoring packet"))
      ((< (cu-nth 3 %u6-ia-na) 40) (say (%str-concat (list "IA_NA option is too short:" (cu-int->str (cu-nth 3 %u6-ia-na)) " bytes"))))
      (#t
       (let ((a (%u6-find (List drop 16 %u6-ia-na) 5)))
         (match
           ((null? a) (say "no IAADDR option, ignoring packet"))
           ((< (cu-nth 3 a) 24) (say (%str-concat (list "IAADDR option is too short:" (cu-int->str (cu-nth 3 a)) " bytes"))))
           (#t
            (let ((lease (%u6-be32-at a 24)))
              (do (set! %u6-requested (List take 16 (List drop 4 a)))
                  (set! %u6-leased #t)
                  (ud-info (string-append "IPv6 obtained, lease time " (cu-int->str lease)))
                  lease)))))))))

; the lease's seconds from IA_PD's IAPREFIX, or ignore where it has none
(def %u6-take-pd
  (fn (_ options)
    (set! %u6-ia-pd (%u6-copy options 25))
    (def say (fn (_ msg) (do (ud-info msg) (lit ignore))))
    (match
      ((null? %u6-ia-pd) (say "no IA_PD option, ignoring packet"))
      ((< (cu-nth 3 %u6-ia-pd) 37) (say (%str-concat (list "IA_PD option is too short:" (cu-int->str (cu-nth 3 %u6-ia-pd)) " bytes"))))
      (#t
       (let ((a (%u6-find (List drop 16 %u6-ia-pd) 26)))
         (match
           ((null? a) (say "no IAPREFIX option, ignoring packet"))
           ((< (cu-nth 3 a) 25) (say (%str-concat (list "IAPREFIX option is too short:" (cu-int->str (cu-nth 3 a)) " bytes"))))
           (#t
            (let ((lease (%u6-be32-at a 8)))
              (do (ud-info (string-append "prefix obtained, lease time " (cu-int->str lease)))
                  lease)))))))))

(def %u6-reply
  (fn (_ options)
    (def address (if %u6-want-addr (%u6-take-na options) 0))
    (if (eq? address (lit ignore)) ()
      (let ((prefix (if %u6-prefix (%u6-take-pd options) 0)))
        (if (eq? prefix (lit ignore)) ()
          (%u6-bind options address prefix))))))

; the lease the shorter of the two, a day with -l, at least 30 seconds
(def %u6-bind
  (fn (_ options address prefix)
    (def a (if (= address 0) prefix address))
    (def p (if (= prefix 0) a prefix))
    (def shorter (if (< p a) p a))
    (set! %u6-lease (match (%u6-stateless 86400)
                           ((>= shorter 2147483648) 2147483647)
                           ((< shorter 30) 30)
                           (#t shorter)))
    (let ((start (%u6-sec)))
      (%u6-script-run options (if (= %u6-state %u6-requesting) "bound" "renew"))
      (set! %u6-lease (let ((l (- %u6-lease (- (%u6-sec) start)))) (if (< l 0) 0 l)))
      (if %u6-quit (%u6-ret0)
        (do (set! %u6-now #f)
            (unless %u6-foreground
              (do (%u6-background!) (set! %u6-background #f) (set! %u6-foreground #t)))
            (%u6-half-lease))))))

(def cu-udhcpc6
  (fn (_ argv stdin-thunk)
    (ud-process-reset!)
    (def status
      (guard (e (match ((eq? (cu-err-label e) (lit udhcp)) (ud-status))
                       (#t (do (when (ud-child?) (sys-exit 1)) (error e)))))
        (%u6-main argv)))
    (when (ud-child?) (sys-exit status))
    status))

(provide cu/udhcpc6 cu-udhcpc6)

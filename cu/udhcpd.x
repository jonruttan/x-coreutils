; # x-coreutils -- the small tools, as applets
;
; ## cu/udhcpd.x -- udhcpd: busybox's DHCP server
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox 1.36.1's udhcpd (networking/udhcp/dhcpd.c), as its defconfig
; builds it: the lease file rewritten at every ACK, addresses tried from
; the start of the range, no -P.  CONFFILE, else /etc/udhcpd.conf, is read
; as config_read reads it, each keyword's default where the file does not
; name it; a file that cannot be read leaves every one at its default.
;
; DISCOVER is answered with an OFFER: the client's static lease, else its
; lease, else the address it asks for where that is free in the range,
; else the first address in the range nobody holds -- an ARP probe of
; -a's milliseconds asks -- or the oldest expired lease.  REQUEST is
; ACKed where it names the client's lease, else NAKed where it chose a
; server or an address; DECLINE holds the address for decline_time;
; RELEASE ends the lease; INFORM gets the options.  Replies go out through
; a packet socket of their own, to the broadcast address unless the client
; has one; a relay's go through the kernel to the relay.
;
; The leases are written to lease_file every auto_time seconds, at every
; ACK, on SIGUSR1 and on SIGTERM, which ends the run; notify_file is run
; after each write with the file's name.  Without -f the run goes to the
; background and says nothing but, with -S, to syslog; busybox's
; "started, v" line gives the version x-coreutils was installed as.

(module cu/udhcpd)

(import cu/cli cu-opts)
(import cu/inetd in-lines in-tokens-max)
(import cu/nc nc-count)
(import cu/prims append byte-at byte-len cu-err-label cu-hexs cu-int->str
  cu-libc-sym cu-nth cu-ptr-call file-close file-open-read file-read-all
  filter length libc-strerror map reverse string-append string=? substring
  sys-exit vec-make vec-ref vec-set!)
(import cu/udhcp ud-ack ud-add-option! ud-add-simple! ud-arpping ud-be32
  ud-be32! ud-byte ud-bytes ud-catch! ud-chaddr ud-child? ud-ciaddr
  ud-daemonize! ud-decline ud-die ud-discover ud-dotted ud-end ud-error
  ud-file ud-find-option ud-flags ud-get-option ud-get-option32 ud-giaddr
  ud-hlen ud-info ud-inform ud-listen ud-log1 ud-log2 ud-logging! ud-mac-text
  ud-nak ud-now ud-offer ud-op ud-packet ud-perror ud-process-reset! ud-put!
  ud-read-interface ud-recv-kernel ud-release ud-remove-pidfile ud-request
  ud-same? ud-send-kernel ud-send-raw ud-siaddr ud-sname ud-spawn ud-status
  ud-str-bytes ud-str2nip ud-str2optset ud-strtou ud-taken ud-write-pidfile
  ud-xid ud-yiaddr ud-zeros)
(import cu/vi vi-bundle-version)

; --- the configuration ------------------------------------------------------------------

(def %dd-start 0)
(def %dd-end 0)
(def %dd-interface "")
(def %dd-max-leases 0)
(def %dd-auto-time 0)
(def %dd-decline-time 0)
(def %dd-conflict-time 0)
(def %dd-offer-time 0)
(def %dd-min-lease 0)
(def %dd-lease-file "")
(def %dd-pidfile "")
(def %dd-siaddr 0)
(def %dd-options ())
(def %dd-notify ())
(def %dd-sname ())
(def %dd-boot-file ())
(def %dd-statics ())             ; (MAC ADDRESS HOSTNAME-OPTION), in the file's order

(def %dd-server 0)               ; our address
(def %dd-ifindex 0)
(def %dd-mac ())
(def %dd-max-lease-sec 0)
(def %dd-arp-ms 2000)

; read_staticlease: MAC, address, an optional host name
(def %dd-static
  (fn (_ line)
    (def words (filter (fn (_ w) (> (byte-len w) 0)) (%dd-split line)))
    (if (if (null? words) #t (null? (rest words))) #f
      (let ((mac (%dd-ether-aton (first words))))
        (if (null? mac) #f
          (let ((nip (ud-str2nip (first (rest words)))))
            (if (null? nip) #f
              (do (set! %dd-statics
                    (append %dd-statics
                            (list (list mac nip
                                        (if (null? (rest (rest words))) ()
                                          (let ((h (ud-str-bytes (first (rest (rest words))))))
                                            (let ((h (if (> (length h) 120) (List take 120 h) h)))
                                              (pair 12 (pair (length h) h)))))))))
                  (ud-log2 (%str-concat (list "static lease: mac:" (ud-mac-text mac)
                                                " nip:" (cu-hexs (%dd-swap nip)))))
                  #t))))))))

(def %dd-split
  (fn (_ s)
    (let go ((i 0) (from 0) (acc ()))
      (match ((>= i (byte-len s)) (reverse (pair (substring s from i) acc)))
             ((if (= (byte-at s i) #\space) #t (= (byte-at s i) #\tab)) (go (+ i 1) (+ i 1) (pair (substring s from i) acc)))
             (#t (go (+ i 1) from acc))))))

; ether_aton_r: six hex bytes, one or two digits each, colons between
(def %dd-ether-aton
  (fn (_ s)
    (def hex (fn (_ c) (match ((if (>= c #\0) (<= c #\9) #f) (- c #\0))
                              ((if (>= (| c 32) #\a) (<= (| c 32) #\f) #f) (+ (- (| c 32) #\a) 10))
                              (#t -1))))
    (def n (byte-len s))
    (def at (fn (_ i) (if (< i n) (byte-at s i) 0)))
    (let go ((i 0) (k 0) (acc ()))
      (if (= k 6) (if (= i n) (reverse acc) ())
        (let ((a (hex (at i))))
          (if (< a 0) ()
            (let ((b (hex (at (+ i 1)))))
              (let ((v (if (< b 0) a (+ (* a 16) b))) (j (if (< b 0) (+ i 1) (+ i 2))))
                (match ((= k 5) (go j 6 (pair v acc)))
                       ((= (at j) #\:) (go (+ j 1) (+ k 1) (pair v acc)))
                       (#t ()))))))))))

(def %dd-optset
  (fn (_ v) (let ((r (ud-str2optset v %dd-options))) (do (set! %dd-options (rest r)) (first r)))))

; the keywords: (NAME SETTER DEFAULT), the ones with a default first
(def %dd-keywords
  (list
    (list "start" (fn (_ v) (let ((n (ud-str2nip v))) (if (null? n) #f (do (set! %dd-start n) #t)))) "192.168.0.20")
    (list "end" (fn (_ v) (let ((n (ud-str2nip v))) (if (null? n) #f (do (set! %dd-end n) #t)))) "192.168.0.254")
    (list "interface" (fn (_ v) (do (set! %dd-interface v) #t)) "eth0")
    (list "max_leases" (fn (_ v) (%dd-set-u32 v (fn (_ n) (set! %dd-max-leases n)))) "235")
    (list "auto_time" (fn (_ v) (%dd-set-u32 v (fn (_ n) (set! %dd-auto-time n)))) "7200")
    (list "decline_time" (fn (_ v) (%dd-set-u32 v (fn (_ n) (set! %dd-decline-time n)))) "3600")
    (list "conflict_time" (fn (_ v) (%dd-set-u32 v (fn (_ n) (set! %dd-conflict-time n)))) "3600")
    (list "offer_time" (fn (_ v) (%dd-set-u32 v (fn (_ n) (set! %dd-offer-time n)))) "60")
    (list "min_lease" (fn (_ v) (%dd-set-u32 v (fn (_ n) (set! %dd-min-lease n)))) "60")
    (list "lease_file" (fn (_ v) (do (set! %dd-lease-file v) #t)) "/var/lib/misc/udhcpd.leases")
    (list "pidfile" (fn (_ v) (do (set! %dd-pidfile v) #t)) "/var/run/udhcpd.pid")
    (list "siaddr" (fn (_ v) (let ((n (ud-str2nip v))) (if (null? n) #f (do (set! %dd-siaddr n) #t)))) "0.0.0.0")
    (list "option" %dd-optset "")
    (list "opt" %dd-optset "")
    (list "notify_file" (fn (_ v) (do (set! %dd-notify v) #t)) ())
    (list "sname" (fn (_ v) (do (set! %dd-sname v) #t)) ())
    (list "boot_file" (fn (_ v) (do (set! %dd-boot-file v) #t)) ())
    (list "static_lease" %dd-static "")))

; read_u32 sets the number whether or not it was read whole
(def %dd-set-u32
  (fn (_ v set)
    (let ((r (ud-strtou v 10))) (do (set (& (first r) 4294967295)) (rest r)))))

; read_config
(def %dd-read-config
  (fn (_ file)
    (map (fn (_ k) ((first (rest k)) (cu-nth 2 k))) (List take 12 %dd-keywords))
    (def fd (file-open-read file))
    (if (< fd 0)
      (ud-perror file (Err errno-of fd))
      (do (file-close fd)
          (map (fn (_ line)
                 (let ((ts (in-tokens-max (rest line) 2)))
                   (match ((null? ts) ())
                          ((null? (rest ts))
                           (ud-error (%str-concat (list "bad line " (cu-int->str (first line)) ": 1 tokens found, 2 needed"))))
                          (#t (let ((k (List find (fn (_ k) (string=? (first k) (Str8 downcase (first ts)))) %dd-keywords)))
                                (unless (null? k)
                                  (unless ((first (rest k)) (first (rest ts)))
                                    (do (ud-error (%str-concat (list "can't parse line " (cu-int->str (first line)) " in " file)))
                                        (unless (null? (cu-nth 2 k)) ((first (rest k)) (cu-nth 2 k)))))))))))
               (in-lines (file-read-all file)))))
    (when (> %dd-start %dd-end) (ud-die (string-append "bad start/end IP range in " file)))))

; --- the leases -------------------------------------------------------------------------

; a lease: (EXPIRES ADDRESS MAC HOSTNAME), the name 20 bytes NUL-padded
(def %dd-nuls (fn (_ n) (let go ((k 0) (acc ())) (if (= k n) acc (go (+ k 1) (pair 0 acc))))))
(def %dd-empty (list 0 0 (list 0 0 0 0 0 0) (%dd-nuls 20)))
(def %dd-leases ())

(def %dd-lease (fn (_ i) (vec-ref %dd-leases i)))
(def %dd-expires (fn (_ l) (first l)))
(def %dd-nip (fn (_ l) (first (rest l))))
(def %dd-lmac (fn (_ l) (cu-nth 2 l)))
(def %dd-host (fn (_ l) (cu-nth 3 l)))
(def %dd-index-where
  (fn (_ pred) (let go ((i 0)) (match ((>= i %dd-max-leases) ()) ((pred (%dd-lease i)) i) (#t (go (+ i 1)))))))

; oldest_expired_lease: an empty slot, the last of them, else the expired
; lease that ends first
(def %dd-oldest-expired
  (fn (_)
    (let go ((i 0) (oldest-time (ud-now)) (oldest ()))
      (if (>= i %dd-max-leases) oldest
        (let ((e (%dd-expires (%dd-lease i))))
          (if (if (= e 0) #t (< e oldest-time)) (go (+ i 1) e i) (go (+ i 1) oldest-time oldest)))))))

; clear_leases
(def %dd-clear!
  (fn (_ mac nip)
    (let go ((i 0))
      (when (< i %dd-max-leases)
        (do (let ((l (%dd-lease i)))
              (when (if (if (null? mac) #f (ud-same? (%dd-lmac l) mac)) #t (if (= nip 0) #f (= (%dd-nip l) nip)))
                (vec-set! %dd-leases i %dd-empty)))
            (go (+ i 1)))))))

; add_lease: the slot it took, or nil; HOST the bytes of a name, nil for none
(def %dd-add-lease!
  (fn (_ mac nip secs host)
    (%dd-clear! mac nip)
    (def i (%dd-oldest-expired))
    (unless (null? i)
      (vec-set! %dd-leases i
        (list (& (+ (ud-now) secs) 4294967295) nip (if (null? mac) (list 0 0 0 0 0 0) mac)
              (if (null? host) (%dd-nuls 20) (%dd-clean-name host)))))
    i))

; the name up to its NUL, at most 19 bytes, a - leading it and each byte
; but a letter, digit, - or _ made a dot
(def %dd-clean-name
  (fn (_ host)
    (def kept (let go ((l host) (k 0) (acc ())) (if (if (null? l) #t (if (= k 19) #t (= (first l) 0))) (reverse acc) (go (rest l) (+ k 1) (pair (first l) acc)))))
    (def ok? (fn (_ c) (match ((if (>= c #\0) (<= c #\9) #f) #t)
                              ((if (>= (| c 32) #\a) (<= (| c 32) #\z) #f) #t)
                              (#t (if (= c #\-) #t (= c #\_))))))
    (def cleaned (if (null? kept) ()
                   (pair (if (= (first kept) #\-) #\. (if (ok? (first kept)) (first kept) #\.))
                         (map (fn (_ c) (if (ok? c) c #\.)) (rest kept)))))
    (append cleaned (%dd-nuls (- 20 (length cleaned))))))

(def %dd-expired? (fn (_ l) (< (%dd-expires l) (ud-now))))
(def %dd-by-mac (fn (_ mac) (%dd-index-where (fn (_ l) (ud-same? (%dd-lmac l) mac)))))
(def %dd-by-nip (fn (_ nip) (%dd-index-where (fn (_ l) (= (%dd-nip l) nip)))))

(def %dd-static-of (fn (_ mac) (let ((s (List find (fn (_ s) (ud-same? (first s) mac)) %dd-statics))) (if (null? s) 0 (first (rest s))))))
(def %dd-static-nip? (fn (_ nip) (not (null? (List find (fn (_ s) (= (first (rest s)) nip)) %dd-statics)))))

; nobody_responds_to_arp: a holder found is given a conflict lease
(def %dd-nobody-holds?
  (fn (_ nip safe)
    (let ((r (ud-arpping nip safe %dd-server %dd-mac %dd-interface %dd-arp-ms)))
      (if (not (= r 0)) #t
        (do (ud-info (%str-concat (list (ud-dotted nip) " belongs to someone, reserving it for "
                                          (cu-int->str %dd-conflict-time) " seconds")))
            (%dd-add-lease! () nip %dd-conflict-time ())
            #f)))))

; find_free_or_expired_nip: 0 where none is free
(def %dd-find-free
  (fn (_ safe)
    (let go ((addr %dd-start) (oldest ()))
      (if (= addr (+ %dd-end 1))
        (if (if (null? oldest) #f (if (%dd-expired? (%dd-lease oldest)) (%dd-nobody-holds? (%dd-nip (%dd-lease oldest)) safe) #f))
          (%dd-nip (%dd-lease oldest)) 0)
        (if (if (= addr %dd-server) #t (%dd-static-nip? addr)) (go (+ addr 1) oldest)
          (let ((i (%dd-by-nip addr)))
            (if (null? i)
              (if (%dd-nobody-holds? addr safe) addr (go (+ addr 1) oldest))
              (go (+ addr 1) (if (if (null? oldest) #t (< (%dd-expires (%dd-lease i)) (%dd-expires (%dd-lease oldest)))) i oldest)))))))))

; write_leases
(def %dd-write-leases
  (fn (_)
    (def fd (File open %dd-lease-file (list (lit wronly) (lit creat) (lit trunc)) 438))
    (if (< fd 0) (ud-perror (%str-concat (list "can't open '" %dd-lease-file "'")) (Err errno-of fd))
      (let ((curr (ud-now)))
        (def used (let go ((i (- %dd-max-leases 1)) (acc ()))
                    (if (< i 0) acc
                      (go (- i 1) (if (= (%dd-nip (%dd-lease i)) 0) acc (pair (%dd-lease i) acc))))))
        (def b (ud-zeros (+ 8 (* 36 (length used)))))
        (ud-be32! b 0 (>> curr 32))
        (ud-be32! b 4 (& curr 4294967295))
        (let go ((l used) (at 8))
          (unless (null? l)
            (let ((left (- (%dd-expires (first l)) curr)))
              (do (ud-be32! b at (if (< left 0) 0 left))
                  (ud-be32! b (+ at 4) (%dd-nip (first l)))
                  (ud-put! b (+ at 8) (%dd-lmac (first l)))
                  (ud-put! b (+ at 14) (%dd-host (first l)))
                  (go (rest l) (+ at 36))))))
        (File write fd b (+ 8 (* 36 (length used))))
        (file-close fd)
        (unless (null? %dd-notify) (ud-spawn (list %dd-notify %dd-lease-file) ()))))))

; read_leases: those written in the last twelve hours, in the range and
; not another's static address
(def %dd-read-leases
  (fn (_ file)
    (def fd (file-open-read file))
    (if (< fd 0) (ud-perror (%str-concat (list "can't open '" file "'")) (Err errno-of fd))
      (let ((head (ud-zeros 8)))
        (if (not (= (File read fd head 8) 8))
          (file-close fd)
          (let ((passed (- (ud-now) (+ (* (ud-be32 head 0) 4294967296) (ud-be32 head 4)))))
            (if (if (< passed 0) #t (> passed 43200)) (file-close fd)
              (do (%dd-read-lease-loop fd passed 0)
                  (file-close fd)))))))))

(def %dd-read-lease-loop
  (fn (self fd passed n)
    (def b (ud-zeros 36))
    (if (not (= (File read fd b 36) 36))
      (ud-log1 (%str-concat (list "read " (cu-int->str n) " leases")))
      (let ((nip (ud-be32 b 4)) (mac (ud-bytes b 8 6)))
        (if (if (< nip %dd-start) #t (> nip %dd-end)) (self fd passed n)
          (let ((left (let ((e (- (%dd-signed (ud-be32 b 0)) passed))) (if (<= e 0) 0 e))))
            (if (if (not (= (%dd-static-of mac) 0)) #t (%dd-static-nip? nip)) (self fd passed n)
              (if (null? (%dd-add-lease! mac nip left (ud-bytes b 14 20)))
                (ud-error (%str-concat (list "too many leases while loading " %dd-lease-file)))
                (self fd passed (+ n 1))))))))))

(def %dd-signed (fn (_ n) (if (>= n 2147483648) (- n 4294967296) n)))

; --- the replies ------------------------------------------------------------------------

; send_packet_to_client, or to the relay where the request came through one
(def %dd-send
  (fn (_ p broadcast)
    (def giaddr (ud-be32 p ud-giaddr))
    (if (not (= giaddr 0))
      (do (ud-log1 "forwarding packet to relay")
          (ud-send-kernel p %dd-server 67 giaddr 67 %dd-interface))
      (let ((ciaddr (ud-be32 p ud-ciaddr)))
        (if (if broadcast #t (if (not (= (& (ud-byte p ud-flags) 128) 0)) #t (= ciaddr 0)))
          (do (ud-log1 "broadcasting packet to client")
              (ud-send-raw p %dd-server 67 4294967295 68 (list 255 255 255 255 255 255) %dd-ifindex))
          (do (ud-log1 "unicasting packet to client ciaddr")
              (ud-send-raw p %dd-server 67 ciaddr 68 (ud-bytes p ud-chaddr 6) %dd-ifindex)))))))

(def %dd-send-verbose
  (fn (_ p fmt)
    (do (ud-info (string-append fmt (ud-dotted (ud-be32 p ud-yiaddr))))
        (%dd-send p #f))))

; init_packet: a reply of TYPE to OLD, our address as the server's
(def %dd-reply
  (fn (_ old type)
    (def p (ud-packet type))
    (ud-put! p ud-xid (ud-bytes old ud-xid 4))
    (ud-put! p ud-chaddr (ud-bytes old ud-chaddr 16))
    (ud-put! p ud-flags (ud-bytes old ud-flags 2))
    (ud-put! p ud-giaddr (ud-bytes old ud-giaddr 4))
    (ud-put! p ud-ciaddr (ud-bytes old ud-ciaddr 4))
    (ud-add-simple! p 54 %dd-server)
    p))

; add_server_options: the configured options but the lease time, the
; static lease's host name before a configured one, siaddr, sname, file
(def %dd-server-options
  (fn (_ p)
    (def yiaddr (ud-be32 p ud-yiaddr))
    (def st (if (= yiaddr 0) () (List find (fn (_ s) (= (first (rest s)) yiaddr)) %dd-statics)))
    (def hostname (if (null? st) () (cu-nth 2 st)))
    (map (fn (_ o) (unless (if (= (first o) 51) #t (if (= (first o) 12) (not (null? hostname)) #f))
                     (ud-add-option! p o)))
         %dd-options)
    (unless (null? hostname) (ud-add-option! p hostname))
    (ud-be32! p ud-siaddr %dd-siaddr)
    (unless (null? %dd-sname) (ud-put! p ud-sname (%dd-upto (ud-str-bytes %dd-sname) 63)))
    (unless (null? %dd-boot-file) (ud-put! p ud-file (%dd-upto (ud-str-bytes %dd-boot-file) 127)))))

(def %dd-upto (fn (_ l n) (if (> (length l) n) (List take n l) l)))

; select_lease_time
(def %dd-lease-time
  (fn (_ p)
    (let ((t (ud-get-option32 p 51)))
      (match ((null? t) %dd-max-lease-sec)
             ((> t %dd-max-lease-sec) %dd-max-lease-sec)
             ((< t %dd-min-lease) %dd-min-lease)
             (#t t)))))

; the host name the client gave, as bytes, or nil
(def %dd-client-name
  (fn (_ p) (let ((o (ud-get-option p 12))) (if (null? o) () (ud-bytes p (first o) (rest o))))))

; send_offer
(def %dd-offer
  (fn (_ old static lease requested)
    (def p (%dd-reply old ud-offer))
    (def mac (ud-bytes old ud-chaddr 6))
    (def taken (fn (_ nip) (let ((i (%dd-by-nip nip))) (if (null? i) #f (not (%dd-expired? (%dd-lease i)))))))
    (def yiaddr
      (match ((not (= static 0)) static)
             ((not (null? lease)) (%dd-nip (%dd-lease lease)))
             ((if (= requested 0) #f (if (>= requested %dd-start) (if (<= requested %dd-end) (not (taken requested)) #f) #f)) requested)
             (#t (%dd-find-free mac))))
    (ud-be32! p ud-yiaddr yiaddr)
    (match ((= yiaddr 0) (ud-error "no free IP addresses. OFFER abandoned"))
           ((if (= static 0) (null? (%dd-add-lease! (ud-bytes p ud-chaddr 6) yiaddr %dd-offer-time (%dd-client-name old))) #f)
            (ud-error "no free IP addresses. OFFER abandoned"))
           (#t (do (ud-add-simple! p 51 (%dd-lease-time old))
                   (%dd-server-options p)
                   (%dd-send-verbose p "sending OFFER to "))))))

(def %dd-nak
  (fn (_ old)
    (do (ud-log1 "sending NAK")
        (%dd-send (%dd-reply old ud-nak) #t))))

(def %dd-ack
  (fn (_ old yiaddr)
    (def p (%dd-reply old ud-ack))
    (ud-be32! p ud-yiaddr yiaddr)
    (def secs (%dd-lease-time old))
    (ud-add-simple! p 51 secs)
    (%dd-server-options p)
    (%dd-send-verbose p "sending ACK to ")
    (%dd-add-lease! (ud-bytes p ud-chaddr 6) yiaddr secs (%dd-client-name old))
    (%dd-write-leases)))

(def %dd-inform
  (fn (_ old)
    (let ((p (%dd-reply old ud-ack)))
      (do (%dd-server-options p) (%dd-send p #f)))))

; --- a request --------------------------------------------------------------------------

(def %dd-handle
  (fn (_ p)
    (def type (let ((o (ud-get-option p 53))) (if (null? o) 0 (ud-byte p (first o)))))
    (def server-id (ud-get-option32 p 54))
    (match
      ((not (= (ud-byte p ud-hlen) 6)) (ud-info "MAC length != 6, ignoring packet"))
      ((not (= (ud-byte p ud-op) 1)) (ud-info "not a REQUEST, ignoring packet"))
      ((if (< type 1) #t (> type 8)) (ud-info "no or bad message type option, ignoring packet"))
      ((if (null? server-id) #f (not (= server-id %dd-server))) (ud-log1 "server ID doesn't match, ignoring packet"))
      (#t (%dd-handle-type p type server-id)))))

(def %dd-handle-type
  (fn (_ p type server-id)
    (def mac (ud-bytes p ud-chaddr 6))
    (def static (%dd-static-of mac))
    (when (not (= static 0)) (ud-info (string-append "found static lease: " (cu-hexs (%dd-swap static)))))
    ; the static lease is a lease of its own, never in the table
    (def lease (if (= static 0) (%dd-by-mac mac) (lit static)))
    (def lease-nip (match ((eq? lease (lit static)) static) ((null? lease) ()) (#t (%dd-nip (%dd-lease lease)))))
    (def req-opt (ud-get-option32 p 50))
    (def requested (if (null? req-opt) 0 req-opt))
    (match
      ((= type ud-discover)
       (do (ud-log1 "received DISCOVER")
           (%dd-offer p static (if (eq? lease (lit static)) () lease) requested)))
      ((= type ud-request)
       (do (ud-log1 "received REQUEST")
           (let ((want (if (null? req-opt) (ud-be32 p ud-ciaddr) requested)))
             (match ((if (null? req-opt) (= want 0) #f) (ud-log1 "no requested IP and no ciaddr, ignoring packet"))
                    ((if (null? lease-nip) #f (= want lease-nip)) (%dd-ack p lease-nip))
                    ((if (null? server-id) (not (null? req-opt)) #t) (%dd-nak p))
                    (#t ())))))
      ((= type ud-decline)
       (do (ud-log1 "received DECLINE")
           (when (match ((null? server-id) #f) ((null? req-opt) #f) ((null? lease-nip) #f) (#t (= requested lease-nip)))
             (unless (eq? lease (lit static))
               (vec-set! %dd-leases lease
                 (list (& (+ (ud-now) %dd-decline-time) 4294967295) lease-nip (list 0 0 0 0 0 0) (%dd-host (%dd-lease lease))))))))
      ((= type ud-release)
       (do (ud-log1 "received RELEASE")
           (when (if (null? server-id) #f (if (null? lease-nip) #f (= (ud-be32 p ud-ciaddr) lease-nip)))
             (unless (eq? lease (lit static))
               (let ((l (%dd-lease lease)))
                 (vec-set! %dd-leases lease (list (ud-now) (%dd-nip l) (%dd-lmac l) (%dd-host l))))))))
      ((= type ud-inform) (do (ud-log1 "received INFORM") (%dd-inform p)))
      (#t ()))))

; the number as busybox's %x prints a network-order address
(def %dd-swap
  (fn (_ n) (+ (<< (& n 255) 24) (<< (& (>> n 8) 255) 16) (<< (& (>> n 16) 255) 8) (& (>> n 24) 255))))

; --- the run ----------------------------------------------------------------------------

(def %dd-main
  (fn (_ argv)
    (def o (cu-opts "udhcpd" argv))
    (def verbose (nc-count o "-v"))
    (def fg (Opts on? o "-f"))
    (unless fg (ud-daemonize!))
    (def syslog (Opts on? o "-S"))
    (when syslog (cu-ptr-call (cu-libc-sym "openlog") "udhcpd" 1 24))
    (ud-logging! "udhcpd" verbose fg syslog)
    (set! %dd-server 0)
    (let ((i (Opts value o "-I")))
      (unless (null? i)
        (let ((n (ud-str2nip i))) (if (null? n) (ud-end 1) (set! %dd-server n)))))
    (let ((a (Opts value o "-a" "2000")))
      (let ((r (ud-strtou a 10)))
        (if (rest r) (set! %dd-arp-ms (first r)) (ud-die (%str-concat (list "invalid number '" a "'"))))))
    (set! %dd-options ())
    (set! %dd-statics ())
    (set! %dd-notify ())
    (set! %dd-sname ())
    (set! %dd-boot-file ())
    (%dd-read-config (let ((ops (Opts operands o))) (if (null? ops) "/etc/udhcpd.conf" (first ops))))
    (when (> %dd-auto-time 2147483) (set! %dd-auto-time 2147483))
    (ud-write-pidfile %dd-pidfile)
    (ud-info (string-append "started, v" (vi-bundle-version)))
    (set! %dd-max-lease-sec
      (let ((l (ud-find-option %dd-options 51)))
        (if (null? l) 864000 (%dd-bytes-be (rest (rest l))))))
    (let ((n (+ (- %dd-end %dd-start) 1)))
      (when (> %dd-max-leases n)
        (do (ud-error (%str-concat (list "max_leases=" (cu-int->str %dd-max-leases) " is too big, setting to " (cu-int->str n))))
            (set! %dd-max-leases n))))
    (set! %dd-leases (vec-make %dd-max-leases %dd-empty))
    (%dd-read-leases %dd-lease-file)
    (def status
      (let ((r (ud-read-interface %dd-interface (= %dd-server 0))))
        (if (null? r) 1
          (do (set! %dd-ifindex (first r))
              (when (= %dd-server 0) (set! %dd-server (first (rest r))))
              (set! %dd-mac (cu-nth 2 r))
              (ud-catch!)
              (%dd-loop -1 (+ (ud-now) %dd-auto-time))))))
    ; remove_pidfile, on the two ways out that are not a death
    (ud-remove-pidfile %dd-pidfile)
    status))

(def %dd-bytes-be (fn (_ l) (List fold (fn (_ acc x) (+ (* acc 256) x)) 0 (if (> (length l) 4) (List take 4 l) l))))

; the poll is taken half a second at a time, the signals looked at between
(def %dd-loop
  (fn (self sock deadline)
    (def fd (if (< sock 0) (ud-listen 67 %dd-interface) sock))
    (Heap collect)
    (def sig (ud-taken))
    (match
      ((= sig 10)
       (do (ud-info "received SIGUSR1") (%dd-write-leases) (self fd (+ (ud-now) %dd-auto-time))))
      ((= sig 15)
       (do (ud-info "received SIGTERM") (%dd-write-leases) (file-close fd) 0))
      ((if (> %dd-auto-time 0) (<= (- deadline (ud-now)) 0) #f)
       (do (%dd-write-leases) (self fd (+ (ud-now) %dd-auto-time))))
      (#t
       (let ((r (Sys poll (list (pair fd (list (lit in)))) 500)))
         (if (null? r) (self fd deadline)
           (let ((p (ud-recv-kernel fd)))
             (match ((not (number? p)) (do (%dd-handle p) (self fd deadline)))
                    ((= p -1)
                     (do (ud-log1 (%str-concat (list "read error: " (libc-strerror (Err errno-of -1)) ", reopening socket")))
                         (file-close fd)
                         (self -1 deadline)))
                    (#t (self fd deadline))))))))))

(def cu-udhcpd
  (fn (_ argv stdin-thunk)
    (ud-process-reset!)
    (def status
      (guard (e (match ((eq? (cu-err-label e) (lit udhcp)) (ud-status))
                       (#t (do (when (ud-child?) (sys-exit 1)) (error e)))))
        (%dd-main argv)))
    (when (ud-child?) (sys-exit status))
    status))

(provide cu/udhcpd cu-udhcpd)

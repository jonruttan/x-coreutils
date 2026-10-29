; # x-coreutils -- the small tools, as applets
;
; ## cu/udhcp.x -- what busybox's DHCP server and client share
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox 1.36.1's networking/udhcp: common.c, packet.c, socket.c,
; arpping.c and domain_codec.c's encoder, built as its defconfig builds
; them -- RFC 3397 and 802.1Q options on, no -P.
;
; Addresses are kept as numbers in host order, the first byte highest.
; An option is a list of bytes: its code, its length, then its data; a set
; of options is a list of them, sorted by code.  A packet is a buffer the
; size of busybox's struct dhcp_packet, its 80 bytes of slack for servers
; that send more options than fit included.
;
; Messages go to stderr and, with syslog on, to syslog, each led by the
; applet's name; -v and -vv add the messages busybox logs at levels 1 and 2.

(module cu/udhcp)

(import cu/inet inet-host-addr inet-set!)
(import cu/inetd in-c in-call in-percent)
(import cu/ping pn-be16 pn-byte pn-div pn-fold pn-now pn-setopt pn-sol-socket
  pn-sum)
(import cu/prims append byte-at byte-len cu-hexs cu-int->str cu-nth
  cu-ptr-call cu-ptr-ref cu-str->ptr file-write filter hx-strtoul length
  libc-strerror map reverse str-make-raw string-append string-concat string=?
  substring)
(import cu/telnetd td-ptr->int)
(import cu/text cu-pad-zero)

; --- saying ----------------------------------------------------------------------------

(def %ud-name "udhcp")
(def %ud-verbose 0)
(def %ud-stdio #t)
(def %ud-syslog #f)

; who says it, how much, and where
(def ud-logging!
  (fn (_ name verbose stdio syslog)
    (do (set! %ud-name name) (set! %ud-verbose verbose) (set! %ud-stdio stdio) (set! %ud-syslog syslog))))
(def ud-verbose (fn (_) %ud-verbose))

(def ud-log!
  (fn (_ level msg)
    (do (when %ud-stdio (file-write 2 (string-concat (list %ud-name ": " msg "\n"))))
        (when %ud-syslog (cu-ptr-call (in-c "syslog") level (in-percent msg))))))
(def ud-info (fn (_ msg) (ud-log! 6 msg)))
(def ud-error (fn (_ msg) (ud-log! 3 msg)))
(def ud-perror (fn (_ msg err) (ud-error (string-concat (list msg ": " (libc-strerror err))))))
(def ud-log1 (fn (_ msg) (when (>= %ud-verbose 1) (ud-info msg))))
(def ud-log2 (fn (_ msg) (when (>= %ud-verbose 2) (ud-info msg))))

; the run ends with STATUS, its message said
(def %ud-status 0)
(def ud-end (fn (_ status) (do (set! %ud-status status) (Err raise (lit udhcp) "end" ()))))
(def ud-status (fn (_) %ud-status))
(def ud-die (fn (_ msg) (do (ud-error msg) (ud-end 1))))
(def ud-errno (fn (_ r) (Err errno-of r)))

; --- numbers and bytes ------------------------------------------------------------------

(def ud-now (fn (_) (first (Sys time-of-day))))
(def ud-ms (fn (_) (pn-div (pn-now) 1000)))

(def ud-zeros
  (fn (_ n)
    (let ((b (str-make-raw n)))
      (do (cu-ptr-call (in-c "memset") (cu-str->ptr b) 0 n) b))))
(def ud-byte (fn (_ b i) (pn-byte (cu-str->ptr b) i)))
(def ud-set! (fn (_ b i v) (inet-set! b i (& v 255) 1)))
(def ud-be32
  (fn (_ b i)
    (+ (* (ud-byte b i) 16777216) (* (ud-byte b (+ i 1)) 65536) (* (ud-byte b (+ i 2)) 256) (ud-byte b (+ i 3)))))
(def ud-be32!
  (fn (_ b i n)
    (do (ud-set! b i (>> n 24)) (ud-set! b (+ i 1) (>> n 16))
        (ud-set! b (+ i 2) (>> n 8)) (ud-set! b (+ i 3) n))))
(def ud-be16! (fn (_ b i n) (do (ud-set! b i (>> n 8)) (ud-set! b (+ i 1) n))))
(def ud-bytes (fn (_ b i n) (let go ((k (- n 1)) (acc ())) (if (< k 0) acc (go (- k 1) (pair (ud-byte b (+ i k)) acc))))))
(def ud-put!
  (fn (_ b i l) (let go ((k i) (l l)) (unless (null? l) (do (ud-set! b k (first l)) (go (+ k 1) (rest l)))))))
(def ud-be32-bytes (fn (_ n) (list (& (>> n 24) 255) (& (>> n 16) 255) (& (>> n 8) 255) (& n 255))))
(def ud-bytes-be (fn (_ l) (List fold (fn (_ acc x) (+ (* acc 256) x)) 0 l)))
(def ud-str-bytes (fn (_ s) (ud-bytes s 0 (byte-len s))))
(def ud-same?
  (fn (_ a b) (match ((null? a) (null? b)) ((null? b) #f) ((= (first a) (first b)) (ud-same? (rest a) (rest b))) (#t #f))))

; inet_ntoa
(def ud-dotted
  (fn (_ n)
    (string-concat (list (cu-int->str (& (>> n 24) 255)) "." (cu-int->str (& (>> n 16) 255)) "."
                         (cu-int->str (& (>> n 8) 255)) "." (cu-int->str (& n 255))))))

(def ud-hex2 (fn (_ b) (cu-pad-zero (cu-hexs b) 2)))
(def ud-mac-text (fn (_ l) (Str8 join ":" (map ud-hex2 l))))

; host_and_af2sockaddr for AF_INET: S's address, a dotted one or a name
; looked up, a :PORT after it passed over; nil where it is not one, said
(def ud-str2nip
  (fn (_ s)
    (def bad (fn (_ what w) (do (ud-error (string-concat (list "bad " what " '" w "'"))) ())))
    (def colon (fn (_ from) (let go ((i (- (byte-len s) 1))) (match ((< i from) ()) ((= (byte-at s i) #\:) i) (#t (go (- i 1)))))))
    (def bracket (if (> (byte-len s) 0) (= (byte-at s 0) #\[) #f))
    (def close (if bracket (let go ((i 1)) (match ((>= i (byte-len s)) ()) ((= (byte-at s i) #\]) i) (#t (go (+ i 1))))) ()))
    (def last (colon 0))
    (def cut (match ((if bracket (null? close) #f) (lit bad))
                    ((if bracket (= (+ close 1) (byte-len s)) #f) ())
                    (bracket (if (= (byte-at s (+ close 1)) #\:) (+ close 1) (lit bad)))
                    ((null? last) ())
                    ((= (colon 0) (let go ((i 0)) (if (= (byte-at s i) #\:) i (go (+ i 1))))) last)
                    (#t ())))
    (if (eq? cut (lit bad)) (bad "address" s)
      (let ((host (match (bracket (substring s 1 (if (null? close) (byte-len s) close)))
                         ((null? cut) s)
                         (#t (substring s 0 cut))))
            (port (if (null? cut) () (substring s (+ cut 1) (byte-len s)))))
        (def p (if (null? port) (pair 0 #t) (ud-strtou port 10)))
        (if (if (rest p) (> (first p) 65535) #t) (bad "port" port)
          (let ((a (%ud-aton host)))
            (if (null? a)
              (let ((h (inet-host-addr host))) (if (null? h) (bad "address" s) (%ud-swap h)))
              a)))))))

(def %ud-swap
  (fn (_ n)
    (+ (<< (& n 255) 24) (<< (& (>> n 8) 255) 16) (<< (& (>> n 16) 255) 8) (& (>> n 24) 255))))
(def %ud-aton
  (fn (_ s)
    (let ((buf (ud-zeros 4)))
      (if (= (in-call (cu-ptr-call (in-c "inet_aton") s (cu-str->ptr buf))) 0) ()
        (ud-be32 buf 0)))))

; bb_strtou32 and bb_strtoi32 from BASE: (VALUE . OK), not OK where S does
; not begin with a letter or digit (a sign, for the signed), has more after
; its digits, or is out of range
(def ud-strtou
  (fn (_ s base)
    (if (if (= (byte-len s) 0) #t (not (%ud-alnum? (byte-at s 0)))) (pair 0 #f)
      (let ((r (hx-strtoul s 0 base 4294967295)))
        (if (null? (first r)) (pair 4294967295 #f)
          (pair (first r) (= (rest r) (byte-len s))))))))
(def ud-strtoi
  (fn (_ s base)
    (def neg (if (> (byte-len s) 0) (= (byte-at s 0) #\-) #f))
    (def r (ud-strtou (if neg (substring s 1 (byte-len s)) s) base))
    (def v (if neg (- 0 (first r)) (first r)))
    (pair v (if (rest r) (if neg (<= v 2147483648) (<= v 2147483647)) #f))))
(def %ud-alnum?
  (fn (_ c) (if (if (>= c #\0) (<= c #\9) #f) #t (if (>= (| c 32) #\a) (<= (| c 32) #\z) #f))))

; strtok_r: the token of S at or after I, the delimiters DELIMS passed over
; first; (TOKEN . NEXT), or nil where none is left.  DELIMS "" takes the rest.
(def ud-strtok
  (fn (_ s i delims)
    (def n (byte-len s))
    (def delim? (fn (_ c) (let go ((k 0)) (if (>= k (byte-len delims)) #f (if (= (byte-at delims k) c) #t (go (+ k 1)))))))
    (def from (let go ((k i)) (if (if (< k n) (delim? (byte-at s k)) #f) (go (+ k 1)) k)))
    (if (>= from n) ()
      (let ((to (let go ((k from)) (if (if (< k n) (not (delim? (byte-at s k))) #f) (go (+ k 1)) k))))
        (pair (substring s from to) (if (< to n) (+ to 1) n))))))

; --- the options ----------------------------------------------------------------------

; the types, and the bits beside them
(def ud-ip 0)
(def ud-ip-pair 1)
(def ud-string 2)
(def ud-string-host 3)
(def ud-u8 4)
(def ud-u16 5)
(def ud-u32 6)
(def ud-s32 7)
(def ud-bin 8)
(def ud-static-routes 9)
(def ud-6rd 10)
(def ud-dns-string 11)
(def ud-sip-servers 12)
(def ud-req 16)
(def ud-list 32)

; dhcp_optflags and dhcp_option_strings: (FLAGS CODE NAME); the last three
; are encoded only, and have no name
(def ud-optflags
  (list (list (+ 0 16) 1 "subnet") (list 7 2 "timezone") (list (+ 0 32 16) 3 "router")
        (list (+ 0 32 16) 6 "dns") (list (+ 0 32) 9 "lprsrv") (list (+ 3 16) 12 "hostname")
        (list 5 13 "bootsize") (list (+ 3 16) 15 "domain") (list 0 16 "swapsrv")
        (list 2 17 "rootpath") (list 4 23 "ipttl") (list 5 26 "mtu")
        (list (+ 0 16) 28 "broadcast") (list (+ 1 32) 33 "routes") (list 3 40 "nisdomain")
        (list (+ 0 32) 41 "nissrv") (list (+ 0 32 16) 42 "ntpsrv") (list (+ 0 32) 44 "wins")
        (list 6 51 "lease") (list 0 54 "serverid") (list 2 56 "message") (list 2 60 "vendor")
        (list 3 66 "tftp") (list 2 67 "bootfile") (list 2 100 "tzstr") (list 2 101 "tzdbstr")
        (list (+ 11 32) 119 "search") (list 12 120 "sipsrv") (list (+ 9 32) 121 "staticroutes")
        (list 5 132 "vlanid") (list 4 133 "vlanpriority") (list 2 209 "pxeconffile")
        (list 2 210 "pxepathprefix") (list 6 211 "reboottime") (list 10 212 "ip6rd")
        (list (+ 9 32) 249 "msstaticroutes") (list 2 252 "wpad")
        (list 0 50 ()) (list 4 53 ()) (list 5 57 ())))

; dhcp_option_lengths, by type
(def ud-type-lengths (list 4 8 1 1 1 2 4 4 0 5 12 1 1))
(def ud-type-length (fn (_ flags) (cu-nth (& flags 15) ud-type-lengths)))
(def %ud-name-of (fn (_ f) (cu-nth 2 f)))

(def ud-optflag-of (fn (_ code) (List find (fn (_ f) (= (first (rest f)) code)) ud-optflags)))

; udhcp_option_idx: NAME's entry, else the run ends naming every one known
(def ud-optflag-named
  (fn (_ name)
    (def named (filter (fn (_ f) (not (null? (%ud-name-of f)))) ud-optflags))
    (def f (List find (fn (_ f) (string=? (%ud-name-of f) name)) named))
    (if (null? f)
      (ud-die (string-concat (list "unknown option '" name "', known options: "
                                   (Str8 join " " (map %ud-name-of named)))))
      f)))

; udhcp_find_option: the option of CODE in SET, or nil
(def ud-find-option
  (fn (_ set code)
    (match ((null? set) ())
           ((= (first (first set)) code) (first set))
           ((> (first (first set)) code) ())
           (#t (ud-find-option (rest set) code)))))

; udhcp_insert_new_option: SET with OPT placed before the first of a code
; not lower
(def %ud-insert
  (fn (_ set opt)
    (if (if (null? set) #t (>= (first (first set)) (first opt))) (pair opt set)
      (pair (first set) (%ud-insert (rest set) opt)))))

(def %ud-replace
  (fn (_ set old new) (map (fn (_ o) (if (eq? o old) new o)) set)))

; hex2bin: the bytes of S, two hex digits each, a colon between allowed and
; one digit before a colon or the end taken alone; nil where S is not one
(def %ud-hex2bin
  (fn (_ s)
    (def n (byte-len s))
    (def hex (fn (_ c) (match ((if (>= c #\0) (<= c #\9) #f) (- c #\0))
                              ((if (>= (| c 32) #\a) (<= (| c 32) #\f) #f) (+ (- (| c 32) #\a) 10))
                              (#t -1))))
    (let go ((i 0) (count 255) (acc ()))
      (if (if (>= i n) #t (= count 0))
        (if (< i n) () (reverse acc))
        (let ((hi (hex (byte-at s i))))
          (if (< hi 0) ()
            (let ((c (if (< (+ i 1) n) (byte-at s (+ i 1)) 0)))
              (let ((lo (hex c)))
                (match ((>= lo 0)
                        (let ((j (+ i 2))) (go (if (if (< j n) (= (byte-at s j) #\:) #f) (+ j 1) j) (- count 1) (pair (+ (* hi 16) lo) acc))))
                       ((= c #\:) (go (+ i 2) (- count 1) (pair hi acc)))
                       ((= c 0) (go (+ i 1) (- count 1) (pair hi acc)))
                       (#t ()))))))))))

; convert_dname: NAME as DNS labels, lower case, nil where a label is empty
; or longer than 63 or the whole longer than 255
(def %ud-dname
  (fn (_ name)
    (def labels (let go ((i 0) (from 0) (acc ()))
                  (match ((>= i (byte-len name)) (reverse (pair (substring name from i) acc)))
                         ((= (byte-at name i) #\.)
                          (if (= (+ i 1) (byte-len name)) (reverse (pair (substring name from i) acc))
                            (go (+ i 1) (+ i 1) (pair (substring name from i) acc))))
                         (#t (go (+ i 1) from acc)))))
    (def bad (List find (fn (_ l) (if (= (byte-len l) 0) #t (> (byte-len l) 63))) labels))
    (def out (append (List fold (fn (_ acc l) (append acc (pair (byte-len l) (map (fn (_ c) (if (if (>= c #\A) (<= c #\Z) #f) (+ c 32) c)) (ud-str-bytes l)))))
                                () labels)
                     (list 0)))
    (if (if (null? bad) (<= (length out) 255) #f) out ())))

; attach_option: SET with VALUE's bytes for FLAG's code, a list option's
; bytes added to the one there while it stays under 255
(def %ud-attach
  (fn (_ set flag value)
    (def type (& (first flag) 15))
    (def bytes (match ((= type ud-bin)
                       (let ((b (%ud-hex2bin value)))
                         (if (null? b) (ud-die (string-concat (list "malformed hex string '" value "'"))) b)))
                      ((= type ud-dns-string) (%ud-dname value))
                      (#t value)))
    (def code (first (rest flag)))
    (def existing (ud-find-option set code))
    (match ((null? existing) (%ud-insert set (pair code (pair (length bytes) bytes))))
           ((= (& (first flag) ud-list) 0) set)
           ((< (+ (first (rest existing)) (length bytes)) 255)
            (%ud-replace set existing (pair code (pair (+ (first (rest existing)) (length bytes)) (append (rest (rest existing)) bytes)))))
           (#t set))))

; udhcp_str2optset: LINE, "NAME VALUE..." or "CODE VALUE", added to SET;
; (OK . SET), the values read before one not read kept
(def ud-str2optset
  (fn (_ line set)
    (def name (ud-strtok line 0 " \t=:"))
    (if (null? name) (pair #f set)
      (let ((num (ud-strtou (first name) 0)))
        (def flag (if (if (rest num) (< (first num) 255) #f)
                    (list ud-bin (first num) ())
                    (ud-optflag-named (first name))))
        (%ud-values line (rest name) flag set #f)))))

; OK: whether a value was read before this one; a list ends at its last
(def %ud-values
  (fn (self line at flag set ok)
    (def type (& (first flag) 15))
    (def tok (if (= type ud-bin)
               (let ((t (ud-strtok line at ""))) (if (null? t) () (pair (%ud-trim (first t)) (rest t))))
               (ud-strtok line at ", \t")))
    (if (null? tok) (pair ok set)
      (let ((r (%ud-value line (first tok) (rest tok) flag)))
        ; r: (BYTES-OR-NIL NEXT FLAG)
        (if (null? (first r)) (pair #f set)
          (let ((set (%ud-attach set (cu-nth 2 r) (first r))))
            (if (= (& (first flag) ud-list) 0) (pair #t set)
              (self line (first (rest r)) flag set #t))))))))

(def %ud-trim
  (fn (_ s)
    (def ws? (fn (_ c) (if (= c #\space) #t (if (>= c #\tab) (<= c 13) #f))))
    (def a (let go ((i 0)) (if (if (< i (byte-len s)) (ws? (byte-at s i)) #f) (go (+ i 1)) i)))
    (def b (let go ((i (byte-len s))) (if (if (> i a) (ws? (byte-at s (- i 1))) #f) (go (- i 1)) i)))
    (substring s a b)))

; one value VAL of FLAG's type, the line read on from AT: (BYTES NEXT FLAG),
; BYTES nil where it is not one -- for a raw code's hex bytes, VAL itself
(def %ud-value
  (fn (_ line val at flag)
    (def type (& (first flag) 15))
    (def ip (fn (_ s) (let ((n (ud-str2nip s))) (if (null? n) () (ud-be32-bytes n)))))
    (def num (fn (_ r size) (if (rest r) (List drop (- 4 size) (ud-be32-bytes (& (first r) 4294967295))) ())))
    (def string (fn (_ s) (if (= (byte-len s) 0) () (ud-str-bytes (if (> (byte-len s) 254) (substring s 0 254) s)))))
    (match
      ((= type ud-ip) (list (ip val) at flag))
      ((= type ud-ip-pair)
       (let ((a (ip val)) (t (ud-strtok line at ", \t/-")))
         (if (if (null? a) #t (null? t)) (list () at flag)
           (let ((b (ip (first t)))) (list (if (null? b) () (append a b)) (rest t) flag)))))
      ((if (= type ud-string) #t (if (= type ud-string-host) #t (= type ud-dns-string)))
       (let ((b (string val)))
         (list (if (null? b) () (if (= type ud-dns-string) (substring val 0 (length b)) b)) at flag)))
      ((= type ud-u8) (list (let ((r (ud-strtou val 0))) (if (rest r) (list (& (first r) 255)) ())) at flag))
      ((= type ud-u16) (list (num (ud-strtou val 0) 2) at flag))
      ((= type ud-u32) (list (num (ud-strtou val 0) 4) at flag))
      ((= type ud-s32) (list (num (ud-strtoi val 0) 4) at flag))
      ((= type ud-static-routes) (%ud-route line val at flag))
      ((= type ud-bin)
       (let ((q (if (> (byte-len val) 0) (byte-at val 0) 0)))
         (if (if (if (= q #\") #t (= q #\')) (if (> (byte-len val) 1) (= (byte-at val (- (byte-len val) 1)) q) #f) #f)
           (let ((b (string (substring val 1 (- (byte-len val) 1)))))
             (list b at (list ud-string (first (rest flag)) ())))
           (list val at flag))))
      (#t (list () at flag)))))

; "a.b.c.d/m" then a router: the mask's width, the prefix's bytes, the router
(def %ud-route
  (fn (_ line val at flag)
    (def slash (let go ((i 0)) (if (>= i (byte-len val)) () (if (= (byte-at val i) #\/) i (go (+ i 1))))))
    (if (null? slash) (list () at flag)
      (let ((net (ud-str2nip (substring val 0 slash)))
            (m (ud-strtou (substring val (+ slash 1) (byte-len val)) 10))
            (t (ud-strtok line at ", \t/-")))
        (if (match ((null? net) #t) ((null? t) #t) ((> (first m) 32) #t) (#t (not (rest m))))
          (list () (if (null? t) at (rest t)) flag)
          (let ((gw (ud-str2nip (first t))))
            (if (null? gw) (list () (rest t) flag)
              (list (append (pair (first m) (List take (>> (+ (first m) 7) 3) (ud-be32-bytes net))) (ud-be32-bytes gw))
                    (rest t) flag))))))))

; --- the packet -----------------------------------------------------------------------

; struct dhcp_packet's fields
(def ud-op 0)
(def ud-htype 1)
(def ud-hlen 2)
(def ud-xid 4)
(def ud-secs 8)
(def ud-flags 10)
(def ud-ciaddr 12)
(def ud-yiaddr 16)
(def ud-siaddr 20)
(def ud-giaddr 24)
(def ud-chaddr 28)
(def ud-sname 44)
(def ud-file 108)
(def ud-cookie 236)
(def ud-options 240)
(def ud-packet-size 628)          ; with the slack
(def ud-dhcp-size 548)            ; without it
(def ud-options-size 308)

; the message types
(def ud-discover 1)
(def ud-offer 2)
(def ud-request 3)
(def ud-decline 4)
(def ud-ack 5)
(def ud-nak 6)
(def ud-release 7)
(def ud-inform 8)

; udhcp_init_header: a packet of TYPE, a reply's op where a server sends it
(def ud-packet
  (fn (_ type)
    (def p (ud-zeros ud-packet-size))
    (ud-set! p ud-op (if (if (= type ud-offer) #t (if (= type ud-ack) #t (= type ud-nak))) 2 1))
    (ud-set! p ud-htype 1)
    (ud-set! p ud-hlen 6)
    (ud-be32! p ud-cookie 1669485411)
    (ud-set! p ud-options 255)
    (ud-add-simple! p 53 type)
    p))

; udhcp_end_option: where the end option is, from the options' start
(def ud-end-option
  (fn (_ p)
    (let go ((i 0))
      (let ((c (ud-byte p (+ ud-options i))))
        (match ((= c 255) i)
               ((= c 0) (go (+ i 1)))
               (#t (go (+ i (ud-byte p (+ ud-options i 1)) 2))))))))

; udhcp_add_binary_option
(def ud-add-option!
  (fn (_ p opt)
    (def end (ud-end-option p))
    (def len (+ 2 (first (rest opt))))
    (if (>= (+ end len 1) ud-options-size)
      (ud-error (string-concat (list "option 0x" (ud-hex2 (first opt)) " did not fit into the packet")))
      (do (ud-log2 (string-concat (list "adding option: 0x" (ud-hex2 (first opt)) " " (%ud-hex-text (rest (rest opt))))))
          (ud-put! p (+ ud-options end) opt)
          (ud-set! p (+ ud-options end len) 255)))))

(def %ud-hex-text (fn (_ l) (string-concat (map ud-hex2 l))))

; udhcp_add_simple_option: CODE's value N, as many bytes as its type has
(def ud-add-simple!
  (fn (_ p code n)
    (def f (ud-optflag-of code))
    (if (null? f) (ud-error (string-concat (list "can't add option 0x" (ud-hex2 code))))
      (let ((len (ud-type-length (first f))))
        (ud-add-option! p (pair code (pair len (List drop (- 4 len) (ud-be32-bytes n)))))))))

; udhcp_scan_options, all of them: each option's (CODE START LEN), START
; where its data begins; nil past a malformed one, said
(def ud-scan
  (fn (_ p)
    (let go ((at ud-options) (rem (- ud-packet-size ud-options)) (overload 0) (acc ()))
      (if (<= rem 0) (%ud-malformed acc)
        (let ((c (ud-byte p at)))
          (match
            ((= c 0) (go (+ at 1) (- rem 1) overload acc))
            ((= c 255)
             (match ((= (& overload 257) 1) (go ud-file 128 (| overload 257) acc))
                    ((= (& overload 514) 2) (go ud-sname 64 (| overload 514) acc))
                    (#t (reverse acc))))
            ((<= rem 1) (%ud-malformed acc))
            (#t
             (let ((len (ud-byte p (+ at 1))))
               (match ((= len 0) (go (+ at 2) (- rem 2) overload acc))
                      ((< (- rem (+ len 2)) 0) (%ud-malformed acc))
                      ((= c 52) (go (+ at len 2) (- rem (+ len 2)) (| overload (ud-byte p (+ at 2))) acc))
                      (#t (go (+ at len 2) (- rem (+ len 2)) overload (pair (list c (+ at 2) len) acc))))))))))))

(def %ud-malformed
  (fn (_ acc) (do (ud-error "bad packet, malformed option field") (reverse (pair (lit malformed) acc)))))

; udhcp_get_option: (START . LEN) of CODE's data, or nil
(def ud-get-option
  (fn (_ p code)
    (let go ((l (ud-scan p)))
      (match ((null? l) ())
             ((eq? (first l) (lit malformed)) ())
             ((= (first (first l)) code)
              (let ((at (cu-nth 1 (first l))) (len (cu-nth 2 (first l))))
                (do (ud-log2 (string-concat (list "option found: 0x" (ud-hex2 code) " " (%ud-hex-text (ud-bytes p at len)))))
                    (pair at len))))
             (#t (go (rest l)))))))

; udhcp_get_option32: its four bytes as a number, or nil
(def ud-get-option32
  (fn (_ p code)
    (let ((o (ud-get-option p code)))
      (if (if (null? o) #t (not (= (rest o) 4))) () (ud-be32 p (first o))))))

; udhcp_dump_packet, at -vv
(def ud-dump
  (fn (_ p)
    (when (>= %ud-verbose 2)
      (do (ud-info (string-concat (list " op " (cu-hexs (ud-byte p ud-op)) " htype " (cu-hexs (ud-byte p ud-htype))
                                        " hlen " (cu-hexs (ud-byte p ud-hlen)) " hops " (cu-hexs (ud-byte p 3))
                                        " xid " (cu-hexs (%ud-le32 p ud-xid))
                                        " secs " (cu-hexs (pn-be16 (cu-str->ptr p) ud-secs))
                                        " flags " (cu-hexs (pn-be16 (cu-str->ptr p) ud-flags))
                                        " ciaddr " (cu-hexs (%ud-le32 p ud-ciaddr)) " yiaddr " (cu-hexs (%ud-le32 p ud-yiaddr))
                                        " siaddr " (cu-hexs (%ud-le32 p ud-siaddr)) " giaddr " (cu-hexs (%ud-le32 p ud-giaddr)))))
          (ud-info (string-concat (list " chaddr " (%ud-hex-text (ud-bytes p ud-chaddr 16)))))))))

; a field as this machine's memory holds it, which is how busybox prints it
(def %ud-le32 (fn (_ p i) (cu-ptr-ref (cu-str->ptr p) i 4)))

; udhcp_recv_kernel_packet: a packet read from FD, or a number below 0
(def ud-recv-kernel
  (fn (_ fd)
    (def p (ud-zeros ud-packet-size))
    (def n (in-call (cu-ptr-call (in-c "read") fd (cu-str->ptr p) ud-packet-size)))
    (match ((< n 0) (do (ud-log1 "packet read error, ignoring") n))
           ((if (< n ud-options) #t (not (= (ud-be32 p ud-cookie) 1669485411)))
            (do (ud-info "packet with bad magic, ignoring") -2))
           (#t (do (ud-log2 "received a packet") (ud-dump p) p)))))

; how much of the options' room is left unsent: what follows the end
; option, at most enough to leave 300 bytes of packet
(def %ud-padding
  (fn (_ p) (let ((pad (- ud-options-size 1 (ud-end-option p)))) (if (> pad 248) 248 pad))))

; udhcp_send_raw_packet: P in IP and UDP headers of our own, from SRC:SPORT
; to DST:DPORT at hardware address DMAC, through IFINDEX
(def ud-send-raw
  (fn (_ p src sport dst dport dmac ifindex)
    (def fd (in-call (cu-ptr-call (in-c "socket") 17 2 8)))
    (if (< fd 0) (do (ud-perror "socket(PACKET)" (ud-errno fd)) -1)
      (let ((sll (ud-zeros 20)))
        (inet-set! sll 0 17 2)
        (ud-be16! sll 2 2048)
        (inet-set! sll 4 ifindex 4)
        (ud-set! sll 11 6)
        (ud-put! sll 12 dmac)
        (if (< (in-call (cu-ptr-call (in-c "bind") fd (cu-str->ptr sll) 20)) 0)
          (let ((e (Err errno-of -1))) (do (cu-ptr-call (in-c "close") fd) (ud-perror "bind(PACKET)" e) -1))
          (let ((pad (%ud-padding p)))
            (def size (- (+ 28 ud-dhcp-size) pad))
            (def b (ud-zeros (+ 28 ud-packet-size)))
            (cu-ptr-call (in-c "memcpy") (+ (td-ptr->int (cu-str->ptr b)) 28) (cu-str->ptr p) ud-dhcp-size)
            (ud-set! b 9 17)
            (ud-be32! b 12 src)
            (ud-be32! b 16 dst)
            (ud-be16! b 20 sport)
            (ud-be16! b 22 dport)
            (ud-be16! b 24 (- size 20))
            (ud-be16! b 2 (- size 20))
            (ud-be16! b 26 (%ud-cksum b 0 size))
            (ud-be16! b 2 size)
            (ud-set! b 0 69)
            (ud-set! b 8 64)
            (ud-be16! b 10 (%ud-cksum b 0 20))
            (ud-dump p)
            (let ((r (in-call (cu-ptr-call (in-c "sendto") fd (cu-str->ptr b) size 0 (cu-str->ptr sll) 20))))
              (let ((e (Err errno-of r)))
                (do (cu-ptr-call (in-c "close") fd)
                    (when (< r 0) (ud-perror "sendto" e))
                    r)))))))))

; inet_cksum: pn-fold answers the complement
(def %ud-cksum
  (fn (_ b from end) (pn-fold (pn-sum (cu-str->ptr b) from end))))

; udhcp_send_kernel_packet: P through the kernel's UDP, from SRC:SPORT to
; DST:DPORT, bound to IFNAME
(def ud-send-kernel
  (fn (_ p src sport dst dport ifname)
    (def fd (in-call (cu-ptr-call (in-c "socket") 2 2 17)))
    (def fail
      (fn (_ what r)
        (let ((e (Err errno-of r))) (do (cu-ptr-call (in-c "close") fd) (ud-perror what e) -1))))
    (if (< fd 0) (do (ud-perror "socket(UDP)" (ud-errno fd)) -1)
      (do (pn-setopt fd pn-sol-socket 2 1)
          (let ((r (ud-bind-device fd ifname)))
            (if (< r 0) (fail "bindtodevice" r)
              (let ((rb (in-call (cu-ptr-call (in-c "bind") fd (cu-str->ptr (ud-sin src sport)) 16))))
                (if (< rb 0) (fail "bind(UDP)" rb)
                  (let ((rc (in-call (cu-ptr-call (in-c "connect") fd (cu-str->ptr (ud-sin dst dport)) 16))))
                    (if (< rc 0) (fail "connect" rc)
                      (do (ud-dump p)
                          (let ((rw (in-call (cu-ptr-call (in-c "write") fd (cu-str->ptr p) (- ud-dhcp-size (%ud-padding p))))))
                            (if (< rw 0) (fail "write" rw)
                              (do (cu-ptr-call (in-c "close") fd) rw))))))))))))))

; a sockaddr_in for N and PORT
(def ud-sin
  (fn (_ n port)
    (let ((b (ud-zeros 16)))
      (do (inet-set! b 0 2 2) (ud-be16! b 2 port) (ud-be32! b 4 n) b))))

; SO_BINDTODEVICE
(def ud-bind-device
  (fn (_ fd name)
    (let ((b (ud-zeros 16)))
      (do (cu-ptr-call (in-c "memcpy") (cu-str->ptr b) name (if (> (byte-len name) 15) 15 (byte-len name)))
          (in-call (cu-ptr-call (in-c "setsockopt") fd pn-sol-socket 25 (cu-str->ptr b) 16))))))

; udhcp_listen_socket: UDP on PORT, broadcasts let in, bound to INF -- an
; alias's colon and what follows dropped
(def ud-listen
  (fn (_ port inf)
    (ud-log2 (string-concat (list "opening listen socket on *:" (cu-int->str port) " " inf)))
    (def fd (in-call (cu-ptr-call (in-c "socket") 2 2 17)))
    (when (< fd 0) (ud-die (string-append "socket: " (libc-strerror (ud-errno fd)))))
    (pn-setopt fd pn-sol-socket 2 1)
    (when (< (pn-setopt fd pn-sol-socket 6 1) 0) (ud-die (string-append "SO_BROADCAST: " (libc-strerror (Err errno-of -1)))))
    (def dev (let go ((i (- (byte-len inf) 1))) (match ((< i 0) inf) ((= (byte-at inf i) #\:) (substring inf 0 i)) (#t (go (- i 1))))))
    (let ((r (ud-bind-device fd dev)))
      (when (< r 0) (ud-die (string-concat (list "can't bind to interface " dev ": " (libc-strerror (ud-errno r)))))))
    (let ((r (in-call (cu-ptr-call (in-c "bind") fd (cu-str->ptr (ud-sin 0 port)) 16))))
      (when (< r 0) (ud-die (string-append "bind: " (libc-strerror (ud-errno r))))))
    fd))

; udhcp_read_interface: (IFINDEX ADDRESS MAC) of NAME, ADDRESS asked only
; where WANT-ADDR; nil where an ioctl fails, said
(def ud-read-interface
  (fn (_ name want-addr)
    (def fd (in-call (cu-ptr-call (in-c "socket") 2 3 255)))
    (when (< fd 0) (ud-die (string-append "socket: " (libc-strerror (ud-errno fd)))))
    (def ifr (ud-zeros 40))
    (inet-set! ifr 16 2 2)
    (cu-ptr-call (in-c "memcpy") (cu-str->ptr ifr) name (if (> (byte-len name) 15) 15 (byte-len name)))
    (def ioctl (fn (_ req) (in-call (cu-ptr-call (in-c "ioctl") fd req (cu-str->ptr ifr)))))
    (def fail (fn (_ msg r) (let ((e (ud-errno r))) (do (cu-ptr-call (in-c "close") fd) (ud-perror msg e) ()))))
    (def addr
      (if (not want-addr) 0
        (let ((r (ioctl 35093)))
          (if (< r 0) (lit failed) (ud-be32 ifr 20)))))
    (if (eq? addr (lit failed)) (fail (string-concat (list "is interface " name " up and configured?")) -1)
      (do (when want-addr (ud-log1 (string-append "IP " (ud-dotted addr))))
          (let ((r (ioctl 35123)))
            (if (< r 0) (fail "ioctl 0x8933 failed" r)
              (let ((index (cu-ptr-ref (cu-str->ptr ifr) 16 4)))
                (ud-log2 (string-append "ifindex " (cu-int->str index)))
                (let ((rh (ioctl 35111)))
                  (if (< rh 0) (fail "ioctl 0x8927 failed" rh)
                    (let ((mac (ud-bytes ifr 18 6)))
                      (ud-log2 (string-append "MAC " (ud-mac-text mac)))
                      (cu-ptr-call (in-c "close") fd)
                      (list index addr mac)))))))))))

; arpping: 1 where no host answers for TEST within MS milliseconds, 0 where
; one does whose hardware address is not SAFE, -1 where the probe could not
; be sent
(def ud-arpping
  (fn (_ test safe from from-mac ifname ms)
    (if (= ms 0) 1
      (let ((s (in-call (cu-ptr-call (in-c "socket") 17 10 1544))))
        (if (< s 0) (do (ud-perror "can't create raw socket" (ud-errno s)) -1)
          (let ((rv (%ud-arp s test safe from from-mac ifname ms)))
            (do (cu-ptr-call (in-c "close") s)
                (ud-log1 (if (= rv 0) "ARP reply received for this address" "no ARP reply received for this address"))
                rv)))))))

(def %ud-arp
  (fn (_ s test safe from from-mac ifname ms)
    (if (< (pn-setopt s pn-sol-socket 6 1) 0)
      (do (ud-perror "can't enable bcast on ARP socket" (Err errno-of -1)) 1)
      (let ((a (ud-zeros 60)) (addr (ud-zeros 16)))
        (ud-put! a 0 (list 255 255 255 255 255 255))
        (ud-put! a 6 from-mac)
        (ud-be16! a 12 2054)
        (ud-be16! a 14 1)
        (ud-be16! a 16 2048)
        (ud-set! a 18 6)
        (ud-set! a 19 4)
        (ud-be16! a 20 1)
        (ud-put! a 22 from-mac)
        (ud-be32! a 28 from)
        (ud-be32! a 38 test)
        (cu-ptr-call (in-c "memcpy") (+ (td-ptr->int (cu-str->ptr addr)) 2) ifname (if (> (byte-len ifname) 13) 13 (byte-len ifname)))
        (if (< (in-call (cu-ptr-call (in-c "sendto") s (cu-str->ptr a) 60 0 (cu-str->ptr addr) 16)) 0) 1
          (%ud-arp-wait s test safe ms ms))))))

(def %ud-arp-wait
  (fn (self s test safe left timeo)
    (def before (ud-ms))
    (def r (Sys poll (list (pair s (list (lit in)))) left))
    (def got
      (if (null? r) ()
        (let ((b (ud-zeros 60)))
          (let ((n (in-call (cu-ptr-call (in-c "read") s (cu-str->ptr b) 60))))
            (if (< n 0) (lit stop) (pair n b))))))
    (match ((eq? got (lit stop)) 1)
           ((if (pair? got)
              (if (>= (first got) 42) (if (= (pn-be16 (cu-str->ptr (rest got)) 20) 2) (= (ud-be32 (rest got) 28) test) #f) #f) #f)
            (if (if (null? safe) #f (ud-same? safe (ud-bytes (rest got) 22 6))) 1 0))
           (#t (let ((left (- left (+ (- (ud-ms) before) 1))))
                 (if (if (>= left 0) (<= left timeo) #f) (self s test safe left timeo) 1))))))

; --- signals --------------------------------------------------------------------------

; udhcp_sp_setup's signals, caught and taken between polls
(def ud-signals (list 10 12 15))
(def ud-catch! (fn (_) (map (fn (_ n) (Sys catch-signal n)) ud-signals)))
(def ud-taken (fn (_) (List find (fn (_ n) (Sys take-signal n)) ud-signals)))

(provide cu/udhcp ud-ack ud-add-option! ud-add-simple! ud-arpping ud-be32
  ud-be32! ud-byte ud-bytes ud-catch! ud-chaddr ud-ciaddr ud-decline ud-die
  ud-discover ud-dotted ud-end ud-error ud-file ud-find-option ud-flags
  ud-get-option ud-get-option32 ud-giaddr ud-hex2 ud-hlen ud-info ud-inform
  ud-listen ud-log1 ud-log2 ud-logging! ud-mac-text ud-nak ud-now ud-offer
  ud-op ud-packet ud-perror ud-put! ud-read-interface ud-recv-kernel
  ud-release ud-request ud-same? ud-send-kernel ud-send-raw ud-set! ud-siaddr
  ud-sname ud-status ud-str-bytes ud-str2nip ud-str2optset ud-strtou ud-taken
  ud-xid ud-yiaddr ud-zeros)

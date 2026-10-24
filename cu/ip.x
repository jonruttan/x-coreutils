; # x-coreutils -- the small tools, as applets
;
; ## cu/ip.x -- ip, ipaddr and iplink: the kernel's interfaces and addresses, over netlink
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's ip (networking/ip.c) and its libiproute: the options before the
; words (-oneline, -family inet|inet6|link, -4, -6, -0), the keywords each
; matched by a unique prefix, and `ip addr show` and `ip link show` as
; ipaddr_list_or_flush makes them.  A NETLINK_ROUTE socket dumps the links
; (RTM_GETLINK) and the addresses (RTM_GETADDR) for the family asked; each
; link prints its index, name, flags, MTU, qdisc, master, state and queue
; length (SIOCGIFTXQLEN), then its link-layer line, then the addresses the
; filter keeps -- dev, up, scope, to PREFIX and label PATTERN (fnmatch).
; The verbs that change the kernel's state are in cu/ipset.x, ip route in
; cu/iproute.x; ip neigh, rule and tunnel come later.

; --- the run ----------------------------------------------------------------------

; F, the run's state, is an alist: name (the applet's), oneline, preferred
; (the family the options asked for), family (the one the filter keeps),
; words, and for a listing up, label, dev, scope, scopemask, pfx and links
(module cu/ip)

(import cu/cli cu-usage)
(import cu/dump dp-find)
(import cu/ifconfig if-ref if-req)
(import cu/inet inet-int32 inet-ntop6-bytes inet-pton6! inet-set! inet-words
  inet-zeros)
(import cu/inetd in-c in-call)
(import cu/prims append byte-at byte-len char->integer cu-err-label
  cu-int->ptr cu-int->str cu-lines cu-nth cu-ptr-call cu-ptr-ref cu-str->ptr
  cu-string-type cvt file-or-err file-read-unsized file-write filter length
  libc-strerror map reverse str-make-raw string-append string-concat string=?
  substring)
(import cu/telnetd td-ptr->int)
(import cu/text cu-pad-zero)

(def ip-get (fn (_ f k) (rest (Assoc entry k f))))
(def ip-put (fn (_ f k v) (pair (pair k v) f)))

(def ip-say (fn (_ f msg) (file-write 2 (string-concat (list (ip-get f (lit name)) ": " msg "\n")))))

; an error that ends the run, as bb_error_msg_and_die
(def ip-die (fn (_ f msg) (do (ip-say f msg) (Err raise (lit ip) msg ()))))
(def ip-die-usage (fn (_) (Err raise (lit ip-usage) "usage" ())))

(def ip-invarg
  (fn (_ f arg opt) (ip-die f (string-concat (list "invalid argument '" arg "' to '" opt "'")))))

; the words after the first of WS, or the run ended as NEXT_ARG ends it
(def ip-next
  (fn (_ f ws)
    (if (null? (rest ws)) (ip-die f "command line is not complete, try \"help\"") (rest ws))))

; index_in_substrings: the index of the one word of WORDS KEY begins, the
; word KEY is where it is one, -1 where none or more than one
(def ip-keyword
  (fn (_ words key)
    (def n (byte-len key))
    (if (= n 0) -1
      (let go ((ws words) (i 0) (found -1))
        (match
          ((null? ws) found)
          ((not (if (>= (byte-len (first ws)) n) (string=? (substring (first ws) 0 n) key) #f)) (go (rest ws) (+ i 1) found))
          ((= (byte-len (first ws)) n) i)
          ((>= found 0) -1)
          (#t (go (rest ws) (+ i 1) i)))))))

; --- numbers ----------------------------------------------------------------------

(def %ip-alnum?
  (fn (_ c)
    (match ((if (>= c #\0) (<= c #\9) #f) #t)
           ((if (>= c #\a) (<= c #\z) #f) #t)
           (#t (if (>= c #\A) (<= c #\Z) #f)))))

(def ip-digit
  (fn (_ c base)
    (def v (match ((if (>= c #\0) (<= c #\9) #f) (- (char->integer c) 48))
                  ((if (>= c #\a) (<= c #\z) #f) (- (char->integer c) 87))
                  ((if (>= c #\A) (<= c #\Z) #f) (- (char->integer c) 55))
                  (#t 99)))
    (if (< v base) v -1)))

; bb_strtou with base 0: (VALUE . CLEAN?), CLEAN? #f where a stray
; character that is not a letter or digit ends it, or nil where it is no
; number -- it starts with neither, a letter or digit ends it, or it passes 32 bits
(def %ip-strtou
  (fn (_ s)
    (def n (byte-len s))
    (def hex? (if (> n 2) (if (= (byte-at s 0) #\0) (if (= (byte-at s 1) #\x) #t (= (byte-at s 1) #\X)) #f) #f))
    (def base (match (hex? 16) ((if (> n 1) (= (byte-at s 0) #\0) #f) 8) (#t 10)))
    (if (if (= n 0) #t (not (%ip-alnum? (byte-at s 0)))) ()
      (let go ((i (if hex? 2 0)) (v 0))
        (let ((d (if (< i n) (ip-digit (byte-at s i) base) -1)))
          (match
            ((>= d 0) (go (+ i 1) (+ (* v base) d)))
            ((> v 4294967295) ())
            ((= i n) (pair v #t))
            ((%ip-alnum? (byte-at s i)) ())
            (#t (pair v #f))))))))

(def %ip-hex2 (fn (_ b) (cu-pad-zero (cvt b cu-string-type 16) 2)))

; the little-endian number BYTES make
(def ip-num
  (fn (_ bytes) (let go ((bs (reverse bytes)) (n 0)) (if (null? bs) n (go (rest bs) (+ (* n 256) (first bs)))))))

; the string BYTES hold, up to a NUL
(def %ip-cstr
  (fn (_ bytes)
    (let go ((bs bytes) (acc ()))
      (if (if (null? bs) #t (= (first bs) 0)) (bytes->str (reverse acc)) (go (rest bs) (pair (first bs) acc))))))

; BYTES padded with zeros to 16
(def ip-pad16
  (fn (_ bytes) (append bytes (map (fn (_ k) 0) (List range (length bytes) 16)))))

; --- names ------------------------------------------------------------------------

; ll_type_n2a: the link types busybox names, as ARPHRD numbers
(def %ip-link-types
  (list (pair 0 "generic") (pair 772 "loopback") (pair 1 "ether") (pair 32 "infiniband")
        (pair 6 "ieee802") (pair 800 "tr") (pair 801 "ieee802.11") (pair 24 "ieee1394")
        (pair 783 "irda") (pair 256 "slip") (pair 257 "cslip") (pair 258 "slip6") (pair 259 "cslip6")
        (pair 512 "ppp") (pair 768 "ipip") (pair 769 "tunnel6") (pair 776 "sit") (pair 778 "gre")
        (pair 65535 "void")))

(def %ip-link-type
  (fn (_ type)
    (let ((e (List find (fn (_ e) (= (first e) type)) %ip-link-types)))
      (if (null? e) (string-concat (list "[" (cu-int->str type) "]")) (rest e)))))

; ll_addr_n2a: a link-layer address, hex pairs, or dotted for a tunnel's four bytes
(def %ip-ll-addr
  (fn (_ bytes type)
    (if (if (= (length bytes) 4) (if (= type 768) #t (if (= type 776) #t (= type 778))) #f)
      (Str8 join "." (map cu-int->str bytes))
      (Str8 join ":" (map %ip-hex2 bytes)))))

; rt_addr_n2a: an address of FAMILY, as inet_ntop writes it
(def ip-ntoa
  (fn (_ family bytes)
    (match
      ((= family 2) (Str8 join "." (map cu-int->str (List take 4 (ip-pad16 bytes)))))
      ((= family 10)
        (let ((buf (str-make-raw 16)))
          (do (map (fn (_ e) (inet-set! buf (first e) (rest e) 1)) (ip-indexed (ip-pad16 bytes)))
              (inet-ntop6-bytes buf))))
      (#t "???"))))

(def ip-indexed
  (fn (_ l) (let go ((l l) (i 0) (acc ())) (if (null? l) (reverse acc) (go (rest l) (+ i 1) (pair (pair i (first l)) acc))))))

; rtnl_tab_initialize: the names of a table -- scopes, protos, tables --
; /etc/iproute2/rt_FILE over busybox's OWN, as ((ID . NAME) ...), a later
; line over an earlier one
(def ip-names
  (fn (_ f file own)
    (def text (file-or-err (fn (_) (file-read-unsized (string-append "/etc/iproute2/rt_" file)))))
    (if (Err err? text) own
      (let go ((lines (cu-lines text)) (no 1) (acc own))
        (if (null? lines) acc
          (let ((ws (inet-words (first (Str8 split "#" (first lines))))))
            (if (null? (if (null? ws) () (rest ws))) (go (rest lines) (+ no 1) acc)
              (let ((id (%ip-strtou (first ws))))
                (if (if (null? id) #t (> (first id) 1023))
                  (do (ip-say f (string-concat (list "database " file " is corrupted at line " (cu-int->str no)))) acc)
                  (go (rest lines) (+ no 1) (pair (pair (first id) (first (rest ws))) acc)))))))))))

; rtnl_*_n2a: ID's name in TAB, else its number
(def ip-name
  (fn (_ tab id)
    (let ((e (List find (fn (_ e) (= (first e) id)) tab)))
      (if (null? e) (cu-int->str id) (rest e)))))

; rtnl_a2n: the lowest id TAB names NAME, else NAME's number up to 1023 (RT_TABLE_MAX), else nil
(def ip-id
  (fn (_ tab name)
    (def named (filter (fn (_ e) (if (string=? (rest e) name) (eq? (List find (fn (_ x) (= (first x) (first e))) tab) e) #f)) tab))
    (if (null? named)
      (let ((n (%ip-strtou name))) (if (if (null? n) #t (> (first n) 1023)) () (first n)))
      (List fold (fn (_ m e) (if (< (first e) m) (first e) m)) 1024 named))))

(def ip-scopes
  (fn (_ f) (ip-names f "scopes" (list (pair 0 "global") (pair 255 "nowhere") (pair 254 "host") (pair 253 "link") (pair 200 "site")))))
(def ip-scope-name (fn (_ f id) (ip-name (ip-get f (lit scopes)) id)))
(def ip-scope-id (fn (_ f name) (ip-id (ip-get f (lit scopes)) name)))

; --- prefixes ---------------------------------------------------------------------

(def %ip-any? (fn (_ s) (if (string=? s "default") #t (if (string=? s "all") #t (string=? s "any")))))

; get_addr_1's dotted quad: the bytes as far as it reads them and whether it read them all
(def %ip-quad
  (fn (_ s)
    (let go ((k 0) (i 0) (n 0) (bytes (list 0 0 0 0)))
      (let ((c (if (< k (byte-len s)) (byte-at s k) ())))
        (match
          ((null? c) (pair #t bytes))
          ((if (>= c #\0) (<= c #\9) #f)
            (let ((v (+ (* n 10) (- (char->integer c) 48))))
              (if (>= v 256) (pair #f bytes) (go (+ k 1) i v (%ip-set-nth bytes i v)))))
          ((if (= c #\.) (< i 3) #f) (go (+ k 1) (+ i 1) 0 bytes))
          (#t (pair #f bytes)))))))

(def %ip-set-nth
  (fn (_ l i v) (map (fn (_ e) (if (= (first e) i) v (rest e))) (ip-indexed l))))

; get_addr_1: NAME as an address of FAMILY (0 for either), (OK? FAMILY BYTES
; BYTELEN), FAMILY and BYTES as far as it got where it is not one
(def ip-addr1
  (fn (_ name family)
    (def zero (ip-pad16 ()))
    (match
      ((%ip-any? name) (list #t family zero (if (= family 10) 16 4)))
      ((>= (dp-find name 0 #\:) 0)
        (let ((buf (inet-zeros 16)))
          (if (if (if (= family 0) #t (= family 10)) (inet-pton6! buf 0 name) #f)
            (list #t 10 (ip-bytes (cu-str->ptr buf) 0 16) 16)
            (list #f 10 zero 0))))
      ((not (if (= family 0) #t (= family 2))) (list #f 0 zero 0))
      (#t (let ((q (%ip-quad name))) (list (first q) 2 (ip-pad16 (rest q)) (if (first q) 4 0)))))))

(def %ip-ones
  (fn (_ n) (let go ((n n) (c 0)) (if (= n 0) c (go (>> n 1) (+ c (& n 1)))))))

; get_prefix_1: ARG as (FAMILY BYTES BITS BYTELEN), or the run ended
(def ip-prefix
  (fn (_ f arg family)
    (def slash (dp-find arg 0 #\/))
    (def a (ip-addr1 (if (< slash 0) arg (substring arg 0 slash)) family))
    (def full (if (= (List ref 1 a) 10) 128 32))
    (match
      ((%ip-any? arg) (list family (ip-pad16 ()) 0 0))
      ((not (first a)) (list (List ref 1 a) (List ref 2 a) 0 0))
      ((< slash 0) (list (List ref 1 a) (List ref 2 a) full (List ref 3 a)))
      (#t (list (List ref 1 a) (List ref 2 a) (%ip-plen f arg (substring arg (+ slash 1) (byte-len arg)) family full) (List ref 3 a))))))

; the length after a prefix's slash: a number up to BITS, or a netmask
(def %ip-plen
  (fn (_ f arg s family bits)
    (def n (%ip-strtou s))
    ; busybox has cut ARG at its slash by then
    (def bad (fn (_) (ip-die f (string-concat (list "an inet prefix is expected rather than \"" (substring arg 0 (dp-find arg 0 #\/)) "\"")))))
    (if (if (null? n) #f (if (rest n) (<= (first n) bits) #f)) (first n)
      (let ((m (ip-addr1 s family)))
        (match
          ((not (first m)) (bad))
          ((= (List ref 1 m) 2)
            (let ((mask (ip-num (reverse (List take 4 (List ref 2 m))))))
              (let ((inv (^ mask 4294967295)))
                (if (if (= (& inv (+ inv 1)) 0) (<= (%ip-ones mask) bits) #f) (%ip-ones mask) (bad)))))
          (#t (if (null? n) 4294967295 (first n))))))))

; inet_addr_match: whether BYTES and the prefix's agree in its first BITS bits
(def ip-match?
  (fn (_ bytes pbytes bits)
    (let go ((a bytes) (b pbytes) (left bits))
      (match
        ((if (<= left 0) #t (null? a)) #t)
        ((>= left 8) (if (= (first a) (first b)) (go (rest a) (rest b) (- left 8)) #f))
        (#t (= (& (^ (first a) (first b)) (& (<< 255 (- 8 left)) 255)) 0))))))

; --- netlink ----------------------------------------------------------------------

(def ip-off (fn (_ p o) (cu-int->ptr (+ (td-ptr->int p) o))))
(def ip-bytes (fn (_ p at n) (map (fn (_ k) (cu-ptr-ref p (+ at k) 1)) (List range 0 n))))
(def ip-align (fn (_ n) (& (+ n 3) (^ 3 4294967295))))

; the attribute TYPE of ATTRS: (TYPE . BYTES), or nil
(def ip-attr (fn (_ attrs type) (List find (fn (_ e) (= (first e) type)) attrs)))

; parse_rtattr: the attributes from AT to END at P whose types are among
; WANT, ((TYPE . BYTES) ...), the last of a type first
(def ip-attrs
  (fn (_ p at end want)
    (let go ((a at) (acc ()))
      (if (> (+ a 4) end) acc
        (let ((len (cu-ptr-ref p a 2)) (type (cu-ptr-ref p (+ a 2) 2)))
          (if (if (< len 4) #t (> (+ a len) end)) acc
            (go (+ a (ip-align len))
                (if (null? (List find (fn (_ t) (= t type)) want)) acc
                  (pair (pair type (ip-bytes p (+ a 4) (- len 4))) acc)))))))))

; IFLA_ADDRESS BROADCAST IFNAME MTU LINK QDISC MASTER OPERSTATE
(def %ip-link-want (list 1 2 3 4 5 6 10 16))
; IFA_ADDRESS LOCAL LABEL BROADCAST ANYCAST CACHEINFO FLAGS
(def %ip-addr-want (list 1 2 3 4 5 6 8))

; a link's message at P of LEN bytes: (KIND INDEX TYPE FLAGS ATTRS), or nil
(def ip-link-of
  (fn (_ p len kind)
    (if (if (if (= kind 16) #t (= kind 17)) (>= len 32) #f)
      (list kind (inet-int32 (cu-ptr-ref p 20 4)) (cu-ptr-ref p 18 2) (cu-ptr-ref p 24 4)
            (ip-attrs p 32 len %ip-link-want))
      ())))

; an address's message: (KIND FAMILY PREFIXLEN FLAGS SCOPE INDEX ATTRS), or nil
(def ip-addr-of
  (fn (_ p len kind)
    (if (if (if (= kind 20) #t (= kind 21)) (>= len 24) #f)
      (list kind (cu-ptr-ref p 16 1) (cu-ptr-ref p 17 1) (cu-ptr-ref p 18 1) (cu-ptr-ref p 19 1)
            (cu-ptr-ref p 20 4) (ip-attrs p 24 len %ip-addr-want))
      ())))

; xrtnl_open: a NETLINK_ROUTE socket, bound
(def ip-open
  (fn (_ f)
    (def fd (in-call (cu-ptr-call (in-c "socket") 16 3 0)))
    (when (< fd 0) (ip-die f (string-append "socket: " (libc-strerror (Err errno-of fd)))))
    (def sa (inet-zeros 12))
    (inet-set! sa 0 16 2)
    (let ((r (in-call (cu-ptr-call (in-c "bind") fd (cu-str->ptr sa) 12))))
      (if (< r 0) (ip-die f (string-append "bind: " (libc-strerror (Err errno-of r)))) fd))))

; xrtnl_wilddump_request then xrtnl_dump_filter: the kernel's KIND messages
; for FAMILY, each as OF reads it, in its order
(def ip-dump
  (fn (_ f fd kind family seq of)
    (def req (inet-zeros 20))
    (inet-set! req 0 20 4)
    (inet-set! req 4 kind 2)
    (inet-set! req 6 769 2)
    (inet-set! req 8 seq 4)
    (inet-set! req 16 family 1)
    (let ((r (in-call (cu-ptr-call (in-c "write") fd (cu-str->ptr req) 20))))
      (when (< r 0) (ip-die f (string-append "write error: " (libc-strerror (Err errno-of r))))))
    (ip-dump-read f fd seq of)))

; xrtnl_dump_filter: the messages to SEQ up to NLMSG_DONE, each as OF reads it
(def ip-dump-read
  (fn (_ f fd seq of)
    (def buf (str-make-raw 32768))
    (let go ((acc ()))
      (let ((n (in-call (cu-ptr-call (in-c "recv") fd (cu-str->ptr buf) 32768 0))))
        (match
          ((< n 0) (do (ip-say f (string-append "OVERRUN: " (libc-strerror (Err errno-of n)))) (go acc)))
          ((= n 0) (do (ip-say f "EOF on netlink") (ip-die f "dump terminated")))
          (#t (let ((r (%ip-take f (cu-str->ptr buf) n seq of acc)))
                (if (first r) (reverse (rest r)) (go (rest r))))))))))

; the messages of the N bytes at P that answer SEQ: (DONE? . ACC)
(def %ip-take
  (fn (_ f p n seq of acc)
    (let go ((o 0) (acc acc))
      (let ((len (if (> (+ o 16) n) 0 (cu-ptr-ref p o 4))))
        (match
          ((if (< len 16) #t (> (+ o len) n)) (pair #f acc))
          ((not (= (cu-ptr-ref p (+ o 8) 4) seq)) (go (+ o (ip-align len)) acc))
          ((= (cu-ptr-ref p (+ o 4) 2) 3) (pair #t acc))
          ((= (cu-ptr-ref p (+ o 4) 2) 2) (%ip-nl-error f p o len))
          (#t (let ((m (of (ip-off p o) len (cu-ptr-ref p (+ o 4) 2))))
                (go (+ o (ip-align len)) (if (null? m) acc (pair m acc))))))))))

; NLMSG_ERROR in a dump
(def %ip-nl-error
  (fn (_ f p o len)
    (if (< len 36) (ip-say f "ERROR truncated")
      (ip-say f (string-append "RTNETLINK answers: " (libc-strerror (- 0 (inet-int32 (cu-ptr-ref p (+ o 16) 4)))))))
    (ip-die f "dump terminated")))

; --- the links --------------------------------------------------------------------

(def %ip-l-index (fn (_ l) (cu-nth 1 l)))
(def %ip-l-flags (fn (_ l) (cu-nth 3 l)))
(def %ip-l-name
  (fn (_ l) (let ((e (ip-attr (cu-nth 4 l) 3))) (if (null? e) () (%ip-cstr (rest e))))))

(def %ip-link-at (fn (_ f idx) (List find (fn (_ l) (= (%ip-l-index l) idx)) (ip-get f (lit links)))))

; ll_index_to_name
(def ip-index-name
  (fn (_ f idx)
    (let ((l (%ip-link-at f idx)))
      (match ((= idx 0) "*")
             ((if (null? l) #t (null? (%ip-l-name l))) (string-append "if" (cu-int->str idx)))
             (#t (%ip-l-name l))))))

; ll_index_to_flags
(def %ip-index-flags
  (fn (_ f idx) (let ((l (%ip-link-at f idx))) (if (if (= idx 0) #t (null? l)) 0 (%ip-l-flags l)))))

; xll_name_to_index: if_nametoindex, or the run ended
(def ip-dev-index
  (fn (_ f name)
    (let ((i (in-call (cu-ptr-call (in-c "if_nametoindex") name))))
      (if (<= i 0) (ip-die f (string-concat (list "can't find device '" name "'"))) i))))

(def ip-sl (fn (_ f) (if (ip-get f (lit oneline)) "\\" "\n")))

; print_link_flags
(def %ip-flag-labels
  (list (pair 8 "LOOPBACK") (pair 2 "BROADCAST") (pair 16 "POINTOPOINT") (pair 4096 "MULTICAST")
        (pair 128 "NOARP") (pair 1 "UP") (pair 65536 "LOWER_UP")))

(def %ip-link-flags
  (fn (_ flags mdown)
    (def f (& flags (^ 64 4294967295)))
    (def on (filter (fn (_ e) (not (= (& f (first e)) 0))) %ip-flag-labels))
    (def left (List fold (fn (_ n e) (& n (^ (first e) 4294967295))) f on))
    (string-concat
      (list "<" (if (if (= (& flags 1) 0) #f (= (& flags 64) 0)) "NO-CARRIER," "")
            (Str8 join "," (map rest on)) (if (= left 0) "" (cvt left cu-string-type 16))
            (if mdown ",M-DOWN" "") "> "))))

(def %ip-operstates (list "UNKNOWN" "NOTPRESENT" "DOWN" "LOWERLAYERDOWN" "TESTING" "DORMANT" "UP"))

; print_queuelen: SIOCGIFTXQLEN on a stream socket, "qlen N" where it is not 0
(def %ip-qlen
  (fn (_ f name)
    (def fd (in-call (cu-ptr-call (in-c "socket") 2 1 0)))
    (if (< fd 0) ""
      (let ((r (if-req name)))
        (let ((n (in-call (cu-ptr-call (in-c "ioctl") fd 35138 (cu-str->ptr r)))))
          (cu-ptr-call (in-c "close") fd)
          (match
            ((< n 0) (do (ip-say f (string-append "ioctl 0x8942 failed: " (libc-strerror (Err errno-of n)))) ""))
            ((= (if-ref r 16 4) 0) "")
            (#t (string-append "qlen " (cu-int->str (inet-int32 (if-ref r 16 4)))))))))))

; "@LINK: " for a link that has one, and M-DOWN where that one is down
(def %ip-iflink
  (fn (_ f attrs)
    (let ((e (ip-attr attrs 5)))
      (match
        ((null? e) (pair ": " #f))
        ((= (ip-num (rest e)) 0) (pair "@NONE: " #f))
        (#t (let ((i (inet-int32 (ip-num (rest e)))))
              (pair (string-concat (list "@" (ip-index-name f i) ": ")) (= (& (%ip-index-flags f i) 1) 0))))))))

; what an attribute adds to a line where the link has it
(def ip-some
  (fn (_ attrs type show) (let ((e (ip-attr attrs type))) (if (null? e) "" (show (rest e))))))

; the link-layer line: "    link/TYPE ADDR brd|peer ADDR"
(def %ip-ll-line
  (fn (_ f l)
    (def attrs (cu-nth 4 l))
    (def type (cu-nth 2 l))
    (string-concat
      (list (ip-sl f) "    link/" (%ip-link-type type) " "
            (ip-some attrs 1 (fn (_ b) (%ip-ll-addr b type)))
            (ip-some attrs 2 (fn (_ b) (string-append (if (= (& (%ip-l-flags l) 16) 0) " brd " " peer ") (%ip-ll-addr b type))))))))

; print_linkinfo's line for L
(def %ip-link-text
  (fn (_ f l)
    (def attrs (cu-nth 4 l))
    (def at (%ip-iflink f attrs))
    (def family (ip-get f (lit family)))
    (string-concat
      (list (if (= (first l) 17) "Deleted " "") (cu-int->str (%ip-l-index l)) ": " (%ip-l-name l) (first at)
            (%ip-link-flags (%ip-l-flags l) (rest at))
            (ip-some attrs 4 (fn (_ b) (string-concat (list "mtu " (cu-int->str (ip-num b)) " "))))
            (ip-some attrs 6 (fn (_ b) (string-concat (list "qdisc " (%ip-cstr b) " "))))
            (ip-some attrs 10 (fn (_ b) (string-concat (list "master " (ip-index-name f (inet-int32 (ip-num b))) " "))))
            (ip-some attrs 16 (fn (_ b) (string-concat (list "state " (if (< (first b) 7) (cu-nth (first b) %ip-operstates) "") " "))))
            (%ip-qlen f (%ip-l-name l))
            (if (if (= family 0) #t (= family 17)) (%ip-ll-line f l) "")
            "\n"))))

; print_linkinfo: 0 where it printed L or its filter passed it over, -1 where L has no name
(def %ip-print-link
  (fn (_ f l)
    (def ifindex (ip-get f (lit ifindex)))
    (def label (ip-get f (lit label)))
    (def family (ip-get f (lit family)))
    (match
      ((if (= ifindex 0) #f (not (= ifindex (%ip-l-index l)))) 0)
      ((if (ip-get f (lit up)) (= (& (%ip-l-flags l) 1) 0) #f) 0)
      ((null? (%ip-l-name l)) (do (ip-say f "nil ifname") -1))
      ((if (null? label) #f (if (if (= family 0) #t (= family 17)) (not (%ip-fnmatch? label (%ip-l-name l))) #f)) 0)
      (#t (do (file-write 1 (%ip-link-text f l)) 0)))))

(def %ip-fnmatch?
  (fn (_ pattern s) (= (in-call (cu-ptr-call (in-c "fnmatch") pattern s 0)) 0)))

; --- the addresses ----------------------------------------------------------------

(def %ip-a-family (fn (_ a) (cu-nth 1 a)))
(def %ip-a-scope (fn (_ a) (cu-nth 4 a)))
(def %ip-a-index (fn (_ a) (cu-nth 5 a)))
(def %ip-a-attrs (fn (_ a) (cu-nth 6 a)))

; the attribute TYPE of A's, else OTHER's
(def %ip-a-either
  (fn (_ a type other)
    (let ((e (ip-attr (%ip-a-attrs a) type))) (if (null? e) (ip-attr (%ip-a-attrs a) other) e))))

; the label an address is matched by: its own, else its link's name
(def %ip-a-label
  (fn (_ f a)
    (let ((e (ip-attr (%ip-a-attrs a) 3))) (if (null? e) (ip-index-name f (%ip-a-index a)) (%ip-cstr (rest e))))))

(def %ip-scope-ok?
  (fn (_ f a) (= (& (^ (ip-get f (lit scope)) (%ip-a-scope a)) (ip-get f (lit scopemask))) 0)))

; the prefix filter: whether LOCAL, an address's (TYPE . BYTES) or nil, passes it
(def %ip-pfx-ok?
  (fn (_ f local)
    (def pfx (ip-get f (lit pfx)))
    (if (if (= (first pfx) 0) #t (null? local)) #t
      (ip-match? (ip-pad16 (rest local)) (List ref 1 pfx) (List ref 2 pfx)))))

; print_addrinfo's filter
(def ip-addr-shown?
  (fn (_ f a)
    (def ifindex (ip-get f (lit ifindex)))
    (def label (ip-get f (lit label)))
    (match
      ((if (= ifindex 0) #f (not (= ifindex (%ip-a-index a)))) #f)
      ((not (%ip-scope-ok? f a)) #f)
      ((if (null? label) #f (not (%ip-fnmatch? label (%ip-a-label f a)))) #f)
      (#t (%ip-pfx-ok? f (%ip-a-either a 2 1))))))

; the flags print_addrinfo names, each with its space
(def %ip-addr-flags
  (fn (_ flags)
    (def named (filter (fn (_ e) (not (= (& flags (first e)) 0)))
                       (list (pair 1 "secondary ") (pair 64 "tentative ") (pair 8 "dadfailed ") (pair 32 "deprecated "))))
    (def left (& flags (^ 745 4294967295)))
    (string-concat
      (list (string-concat (map rest named))
            (if (= (& flags 128) 0) "dynamic " "")
            (if (= (& flags 512) 0) "" "noprefixroute ")
            (if (= left 0) "" (string-concat (list "flags " (%ip-hex2 left) " ")))))))

(def %ip-lft
  (fn (_ word n) (string-append word (if (= n 4294967295) " forever" (string-concat (list " " (cu-int->str (inet-int32 n)) "sec"))))))

; whether two addresses' first four bytes are the same, as busybox's memcmp asks
(def %ip-same4?
  (fn (_ a b)
    (let go ((a (List take 4 (ip-pad16 a))) (b (List take 4 (ip-pad16 b))))
      (if (null? a) #t (if (= (first a) (first b)) (go (rest a) (rest b)) #f)))))

; "ADDR/LEN " or "ADDR peer PEER/LEN ", as far as the first four bytes tell them apart
(def %ip-addr-local
  (fn (_ a local peer)
    (def family (%ip-a-family a))
    (def len (string-append "/" (cu-int->str (cu-nth 2 a))))
    (string-concat
      (list (ip-ntoa family (rest local))
            (if (if (null? peer) #t (%ip-same4? (rest peer) (rest local)))
              (string-append len " ")
              (string-concat (list " peer " (ip-ntoa family (rest peer)) len " ")))))))

; print_addrinfo's line for A
(def %ip-addr-text
  (fn (_ f a)
    (def attrs (%ip-a-attrs a))
    (def family (%ip-a-family a))
    (def local (%ip-a-either a 2 1))
    (def fl (ip-attr attrs 8))
    (string-concat
      (list (if (= (first a) 21) "Deleted " "")
            (if (ip-get f (lit oneline)) (string-concat (list (cu-int->str (%ip-a-index a)) ": " (ip-index-name f (%ip-a-index a)))) "")
            (match ((= family 2) "    inet ") ((= family 10) "    inet6 ") (#t (string-concat (list "    family " (cu-int->str family) " "))))
            (if (null? local) "" (%ip-addr-local a local (%ip-a-either a 1 2)))
            (ip-some attrs 4 (fn (_ b) (string-concat (list "brd " (ip-ntoa family b) " "))))
            (ip-some attrs 5 (fn (_ b) (string-concat (list "any " (ip-ntoa family b) " "))))
            "scope " (ip-scope-name f (%ip-a-scope a)) " "
            (%ip-addr-flags (if (null? fl) (cu-nth 3 a) (ip-num (rest fl))))
            (ip-some attrs 3 %ip-cstr)
            (ip-some attrs 6 (fn (_ b) (string-concat (list (ip-sl f) "       " (%ip-lft "valid_lft" (ip-num (List take 4 (List drop 4 b))))
                                                            " " (%ip-lft "preferred_lft" (ip-num (List take 4 b)))))))
            "\n"))))

; print_selected_addrinfo: the addresses of link IDX the family keeps
(def %ip-print-addrs
  (fn (_ f idx addrs)
    (def family (ip-get f (lit family)))
    (map (fn (_ a)
           (when (if (= (first a) 20) (if (= (%ip-a-index a) idx) (if (= family 0) #t (= family (%ip-a-family a))) #f) #f)
             (when (ip-addr-shown? f a) (file-write 1 (%ip-addr-text f a)))))
         addrs)))

; whether link L has an address the filter keeps, as the family's listing asks
(def %ip-has-addr?
  (fn (_ f l addrs)
    (def family (ip-get f (lit family)))
    (def label (ip-get f (lit label)))
    (not (null? (List find
                  (fn (_ a)
                    (match
                      ((not (= (%ip-a-index a) (%ip-l-index l))) #f)
                      ((not (= family (%ip-a-family a))) #f)
                      ((not (%ip-scope-ok? f a)) #f)
                      ((not (%ip-pfx-ok? f (%ip-a-either a 2 1))) #f)
                      (#t (if (null? label) #t (%ip-fnmatch? label (%ip-a-label f a))))))
                  addrs)))))

; --- the listing ------------------------------------------------------------------

; one of the listing's words at the front of WS: (F . WORDS-LEFT)
(def %ip-list-word
  (fn (_ f ws)
    (def w (first ws))
    (match
      ((string=? w "to") (let ((a (ip-next f ws))) (pair (%ip-to f (first a)) (rest a))))
      ((string=? w "scope") (let ((a (ip-next f ws))) (pair (%ip-scope-filter f (first a)) (rest a))))
      ((string=? w "up") (pair (ip-put f (lit up) #t) (rest ws)))
      ((string=? w "label") (let ((a (ip-next f ws))) (pair (ip-put f (lit label) (first a)) (rest a))))
      (#t (let ((a (if (string=? w "dev") (ip-next f ws) ws)))
            (if (null? (ip-get f (lit dev)))
              (pair (ip-put f (lit dev) (first a)) (rest a))
              (ip-die f (string-concat (list "either \"dev\" is duplicate, or \"" (first a) "\" is garbage")))))))))

(def %ip-to
  (fn (_ f arg)
    (def family (ip-get f (lit family)))
    (when (= family 17)
      (ip-die f (string-concat (list "\"" arg "\" may be inet prefix, but it is not allowed in this context"))))
    (let ((p (ip-prefix f arg family)))
      (ip-put (ip-put f (lit pfx) p) (lit family) (if (= family 0) (first p) family)))))

(def %ip-scope-filter
  (fn (_ f arg)
    (let ((id (ip-scope-id f arg)))
      (match
        ((not (null? id)) (ip-put (ip-put f (lit scope) id) (lit scopemask) 4294967295))
        ((string=? arg "all") (ip-put (ip-put f (lit scope) 255) (lit scopemask) 0))
        (#t (ip-invarg f arg "scope"))))))

; ipaddr_list_or_flush up to its addresses: the words read into the filter,
; the socket open (fd), the links dumped (links) and dev's index (ifindex)
(def ip-filter
  (fn (_ f0 ws)
    (def f1 (List fold (fn (_ f kv) (ip-put f (first kv) (rest kv))) f0
                  (list (pair (lit family) (ip-get f0 (lit preferred))) (pair (lit up) #f) (pair (lit label) ())
                        (pair (lit dev) ()) (pair (lit scope) 0) (pair (lit scopemask) 0)
                        (pair (lit pfx) (list 0 () 0 0)) (pair (lit links) ()) (pair (lit ifindex) 0))))
    (def f2 (ip-put f1 (lit scopes) (ip-scopes f1)))
    (def f3 (let go ((f f2) (ws ws)) (if (null? ws) f (let ((r (%ip-list-word f ws))) (go (first r) (rest r))))))
    (def fd (ip-open f3))
    (def links (ip-dump f3 fd 18 (ip-get f3 (lit preferred)) 1 ip-link-of))
    (def dev (ip-get f3 (lit dev)))
    (List fold (fn (_ f kv) (ip-put f (first kv) (rest kv))) f3
               (list (pair (lit fd) fd) (pair (lit links) links)
                     (pair (lit ifindex) (if (null? dev) 0 (ip-dev-index f3 dev)))))))

; ipaddr_list_or_flush's listing: the links, each with its addresses
(def ip-list
  (fn (_ f0 ws)
    (def f (ip-filter f0 ws))
    (def family (ip-get f (lit family)))
    (def links (ip-get f (lit links)))
    (def addrs (if (= family 17) () (ip-dump f (ip-get f (lit fd)) 22 family 2 ip-addr-of)))
    (cu-ptr-call (in-c "close") (ip-get f (lit fd)))
    (map (fn (_ l)
           (when (if (if (ip-get f (lit oneline)) (not (= family 17)) #f) #t (= (%ip-print-link f l) 0))
             (unless (= family 17) (%ip-print-addrs f (%ip-l-index l) addrs))))
         (if (if (= family 0) #t (= family 17)) links (filter (fn (_ l) (%ip-has-addr? f l addrs)) links)))
    0))

; --- the commands -----------------------------------------------------------------

; ip_parse_common_args: the options before the words, onto F
(def %ip-common
  (fn (_ f argv)
    (def w (if (null? argv) "" (first argv)))
    (def opt (if (if (> (byte-len w) 1) (= (byte-at w 1) #\-) #f) (substring w 2 (byte-len w)) (if (> (byte-len w) 0) (substring w 1 (byte-len w)) "")))
    (match
      ((if (null? argv) #t (not (= (byte-at w 0) #\-))) (ip-put f (lit words) argv))
      ((string=? w "--") (ip-put f (lit words) (rest argv)))
      (#t (%ip-common-opt f argv (ip-keyword (list "oneline" "family" "4" "6" "0") opt))))))

(def %ip-common-opt
  (fn (_ f argv k)
    (match
      ((< k 0) (ip-die-usage))
      ((= k 0) (%ip-common (ip-put f (lit oneline) #t) (rest argv)))
      ((= k 1)
        (if (null? (rest argv)) (ip-die-usage)
          (let ((fam (List find (fn (_ e) (string=? (first e) (first (rest argv)))) (list (pair "inet" 2) (pair "inet6" 10) (pair "link" 17)))))
            (if (null? fam) (ip-invarg f (first (rest argv)) "family")
              (%ip-common (ip-put f (lit preferred) (rest fam)) (rest (rest argv)))))))
      (#t (%ip-common (ip-put f (lit preferred) (cu-nth (- k 2) (list 2 10 17))) (rest argv))))))

(def ip-run
  (fn (_ name argv go)
    (guard (e (match ((eq? (cu-err-label e) (lit ip-usage)) (cu-usage name))
                     ((eq? (cu-err-label e) (lit ip)) 1)
                     (#t (error e))))
      (let ((f (%ip-common (list (pair (lit name) name) (pair (lit oneline) #f) (pair (lit preferred) 0)) argv)))
        (go f (ip-get f (lit words)))))))

(provide cu/ip ip-addr-of ip-addr-shown? ip-addr1 ip-align ip-attr ip-attrs
  ip-bytes ip-dev-index ip-die ip-die-usage ip-digit ip-dump ip-dump-read
  ip-filter ip-get ip-id ip-index-name ip-indexed ip-invarg ip-keyword
  ip-link-of ip-list ip-match? ip-name ip-names ip-next ip-ntoa ip-num ip-off
  ip-open ip-pad16 ip-prefix ip-put ip-run ip-say ip-scope-id ip-scope-name
  ip-scopes ip-sl ip-some)

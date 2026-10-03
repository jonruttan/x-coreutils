; # x-coreutils -- the small tools, as applets
;
; ## cu/dns.x -- nslookup
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's nslookup (FEATURE_NSLOOKUP_BIG): the queries built as its
; res_mkquery builds them, sent over a UDP socket connected to each server in
; turn, every unanswered one again after timeout/retry seconds, and each reply
; printed as its parse_reply prints it.  With no -type, HOST is a reverse
; lookup when it reads as an address and an A and an AAAA query otherwise.
; With no DNS_SERVER, /etc/resolv.conf names the servers (127.0.0.1 when it
; names none) and the search domains a dotless HOST is tried under.
;
; Packets are runs, read and written as the socket's file descriptor, so
; their NUL bytes cross.

; --- the command line ------------------------------------------------------------

(def %ns-port 53)
(def %ns-retry 2)
(def %ns-timeout 5)
(def %ns-debug #f)
(def %ns-exit 0)

; busybox's qtypes table, in its order: (NAME . NUMBER)
(def %ns-types
  (list (pair "SOA" 6) (pair "NS" 2) (pair "A" 1) (pair "AAAA" 28) (pair "CNAME" 5)
        (pair "MX" 15) (pair "TXT" 16) (pair "SRV" 33) (pair "PTR" 12) (pair "ANY" 255)))

(def %ns-rcodes
  (list "NOERROR" "FORMERR" "SERVFAIL" "NXDOMAIN" "NOTIMP" "REFUSED" "YXDOMAIN"
        "YXRRSET" "NXRRSET" "NOTAUTH" "NOTZONE" "11" "12" "13" "14" "15"))

; busybox's usage text, less the banner naming its binary; status 1
(def %ns-usage
  (fn (_)
    (do (file-write 2
          (string-concat
            (list "Usage: nslookup [-type=QUERY_TYPE] [-debug] HOST [DNS_SERVER]\n\n"
                  "Query DNS about HOST\n\n"
                  "QUERY_TYPE: soa,ns,a,aaaa,cname,mx,txt,ptr,srv,any\n")))
        1)))

; busybox's xatou_range: VAL's digits within LO..HI, or the run ends
(def %ns-number
  (fn (_ val lo hi)
    (def n (%wget-digits val))
    (match
      ((null? n) (%net-die (string-concat (list "invalid number '" val "'"))))
      ((if (< n lo) #t (> n hi))
        (%net-die (string-concat (list "number " val " is not in "
          (%cu-int->str lo) ".." (%cu-int->str hi) " range"))))
      (#t n))))

; the qtype number for NAME, any case, or the run ends
(def %ns-type
  (fn (_ val)
    (def up (%ns-upper val))
    (let go ((ts %ns-types))
      (match
        ((null? ts) (%net-die (string-concat (list "invalid query type \"" val "\""))))
        ((string=? (first (first ts)) up) (rest (first ts)))
        (#t (go (rest ts)))))))

(def %ns-upper
  (fn (_ s)
    (bytes->str
      (let go ((i (- (byte-len s) 1)) (acc ()))
        (if (< i 0) acc
          (go (- i 1)
              (pair (let ((c (byte-at s i)))
                      (if (if (>= c #\a) (<= c #\z) #f) (- c 32) (& c 255)))
                    acc)))))))

; the options in front of the operands, each -NAME or -NAME=VALUE: answers
; the qtypes asked for, in busybox's table order, or nil for none; nil
; overall stands for "show the usage"
(def %ns-options
  (fn (self argv types)
    (match
      ((null? argv) (lit usage))
      ((not (= (byte-at (first argv) 0) #\-)) (pair (reverse types) argv))
      (#t
        (let ((arg (substring (first argv) 1 (byte-len (first argv)))))
          (let ((eq (%wget-index arg #\= 0)))
            (let ((name (if (null? eq) arg (substring arg 0 eq)))
                  (val (if (null? eq) "" (substring arg (+ eq 1) (byte-len arg)))))
              (match
                ((%cu-member-s? name (list "type" "querytype"))
                  (self (rest argv) (%ns-add-type types (%ns-type val))))
                ((string=? name "port")
                  (do (set! %ns-port (%ns-number val 1 65535)) (self (rest argv) types)))
                ((string=? name "retry")
                  (do (set! %ns-retry (%ns-number val 1 2147483647)) (self (rest argv) types)))
                ((string=? name "debug") (do (set! %ns-debug #t) (self (rest argv) types)))
                ((%cu-member-s? name (list "t" "timeout"))
                  (do (set! %ns-timeout (%ns-number val 1 2147483)) (self (rest argv) types)))
                (#t (lit usage))))))))))

; TYPES with T added once
(def %ns-add-type
  (fn (_ types t) (if (%wget-memv t types) types (pair t types))))

; --- names and queries -------------------------------------------------------------

; S's labels as a byte list in wire form, a length before each and a 0 after,
; or nil for a name res_mkquery refuses: over 253 bytes, a label over 63, or
; two dots at its end
(def %ns-wire-name
  (fn (_ s)
    (def l0 (byte-len s))
    (def l1 (if (if (> l0 0) (= (byte-at s (- l0 1)) #\.) #f) (- l0 1) l0))
    (def name (substring s 0 l1))
    (match
      ((if (> l1 0) (= (byte-at name (- l1 1)) #\.) #f) ())
      ((> l1 253) ())
      ((= l1 0) (list 0))
      (#t
        (let go ((i 0) (start 0) (acc ()))
          (match
            ((if (= i l1) #t (= (byte-at name i) #\.))
              (let ((n (- i start)))
                (if (> (- n 1) 61) ()
                  (let ((acc2 (append (reverse (%ns-bytes name start i)) (pair n acc))))
                    (if (= i l1) (reverse (pair 0 acc2)) (go (+ i 1) (+ i 1) acc2))))))
            (#t (go (+ i 1) start acc))))))))

; S's bytes from A to B, as a list
(def %ns-bytes
  (fn (_ s a b)
    (let go ((i (- b 1)) (acc ()))
      (if (< i a) acc (go (- i 1) (pair (& (byte-at s i) 255) acc))))))

; a query: (NAME BYTES . DONE?), BYTES res_mkquery's packet with an id of 0, or
; nil when the name is refused
(def %ns-query
  (fn (_ name type)
    (def wire (%ns-wire-name name))
    (list name
          (if (null? wire) ()
            (append (list 0 0 1 32 0 1 0 0 0 0 0 0)
                    (append wire (list (%wget-div type 256) (% type 256) 0 1))))
          #f)))

; the dotted quad S's four numbers, or nil
(def %ns-ipv4
  (fn (_ s)
    (def parts (%ns-split s #\.))
    (if (= (length parts) 4)
      (let ((ns (map (fn (_ p) (if (> (byte-len p) 3) () (%wget-digits p))) parts)))
        (if (null? (filter (fn (_ n) (if (null? n) #t (> n 255))) ns)) ns ()))
      ())))

; S cut at each C
(def %ns-split
  (fn (_ s c)
    (let go ((i 0) (start 0) (acc ()))
      (match
        ((= i (byte-len s)) (reverse (pair (substring s start i) acc)))
        ((= (byte-at s i) c) (go (+ i 1) (+ i 1) (pair (substring s start i) acc)))
        (#t (go (+ i 1) start acc))))))

; S's eight 16-bit groups when it reads as an IPv6 address, or nil
(def %ns-ipv6
  (fn (_ s)
    (def dc (%wget-find s "::"))
    (def group (fn (_ g)
      (if (if (> (byte-len g) 0) (<= (byte-len g) 4) #f)
        (let go ((i 0) (v 0))
          (if (= i (byte-len g)) v
            (let ((h (%ns-hex (byte-at g i)))) (if (< h 0) () (go (+ i 1) (+ (* v 16) h))))))
        ())))
    (def groups (fn (_ part) (if (= (byte-len part) 0) () (map group (%ns-split part #\:)))))
    (def all
      (if (null? dc) (groups s)
        (let ((left (groups (substring s 0 dc)))
              (right (groups (substring s (+ dc 2) (byte-len s)))))
          (if (> (+ (length left) (length right)) 7) (list ())
            (append left (append (%ns-zeros (- 8 (+ (length left) (length right)))) right))))))
    (if (if (= (length all) 8) (null? (filter null? all)) #f) all ())))

(def %ns-zeros (fn (self n) (if (<= n 0) () (pair 0 (self (- n 1))))))

(def %ns-hex
  (fn (_ c)
    (match
      ((if (>= c #\0) (<= c #\9) #f) (- c #\0))
      ((if (>= c #\a) (<= c #\f) #f) (- c 87))
      ((if (>= c #\A) (<= c #\F) #f) (- c 55))
      (#t -1))))

; busybox's make_ptr: the reverse name for an address, or nil
(def %ns-make-ptr
  (fn (_ s)
    (def v6 (%ns-ipv6 s))
    (def v4 (%ns-ipv4 s))
    (def join (fn (_ ns) (string-concat (map (fn (_ n) (string-append (%cu-int->str n) ".")) ns))))
    (match
      ((not (null? v6))
        (if (if (= (first v6) 0) (if (= (first (rest v6)) 0) (if (= (first (rest (rest v6))) 0)
              (if (= (first (rest (rest (rest v6)))) 0)
                (if (= (first (rest (rest (rest (rest v6))))) 0)
                  (= (first (rest (rest (rest (rest (rest v6)))))) 65535) #f) #f) #f) #f) #f)
          ; a v4-mapped address reverses as its IPv4
          (let ((a (first (rest (rest (rest (rest (rest (rest v6))))))))
                (b (first (rest (rest (rest (rest (rest (rest (rest v6))))))))))
            (string-append (join (list (% b 256) (%wget-div b 256) (% a 256) (%wget-div a 256)))
                           "in-addr.arpa"))
          (string-append
            (string-concat
              (map (fn (_ n) (list->string (list (%ns-hexch (% n 16)) #\. (%ns-hexch (%wget-div n 16)) #\.)))
                   (reverse (%ns-nibbles v6))))
            "ip6.arpa")))
      ((not (null? v4)) (string-append (join (reverse v4)) "in-addr.arpa"))
      (#t ()))))

; the address's sixteen bytes
(def %ns-nibbles
  (fn (_ groups)
    (let go ((gs groups) (acc ()))
      (if (null? gs) (reverse acc)
        (go (rest gs) (pair (% (first gs) 256) (pair (%wget-div (first gs) 256) acc)))))))

(def %ns-hexch (fn (_ n) (integer->char (if (< n 10) (+ n #\0) (+ n 87)))))

; HOST's queries of TYPE: one under each search domain for a dotless name,
; else the name itself, as busybox's add_query_with_search
(def %ns-with-search
  (fn (_ type host search)
    (if (if (= type 12) #t (if (null? search) #t (not (null? (%wget-index host #\. 0)))))
      (list (%ns-query host type))
      (map (fn (_ d) (%ns-query (string-append host (string-append "." d)) type))
           (filter (fn (_ d) (> (byte-len d) 0)) (%ns-split-blanks search))))))

(def %ns-split-blanks
  (fn (_ s)
    (filter (fn (_ w) (> (byte-len w) 0))
      (%ns-split (Str8 replace "\t" " " s) #\space))))

; --- servers ---------------------------------------------------------------------

; /etc/resolv.conf's (SERVERS . SEARCH): its nameserver lines in order and its
; search line, else its domain line, else the hostname's domain part; "." is
; no search at all
(def %ns-resolv-conf
  (fn (_)
    (def text (if (file-exists? "/etc/resolv.conf") (file-read-all "/etc/resolv.conf") ""))
    (def st
      (let go ((ls (%ns-split text #\newline)) (servers ()) (search ()) (has-search #f))
        (if (null? ls) (list (reverse servers) search)
          (let ((words (%ns-split-blanks (first ls))))
            (if (if (null? words) #t (null? (rest words)))
              (go (rest ls) servers search has-search)
              (let ((key (first words))
                    (arg (%whois-trim (substring (first ls)
                            (+ (%wget-find (first ls) (first words)) (byte-len (first words)))
                            (byte-len (first ls))))))
                (match
                  ((string=? key "nameserver") (go (rest ls) (pair (first (rest words)) servers) search has-search))
                  ((string=? key "search") (go (rest ls) servers arg #t))
                  ((if (string=? key "domain") (not has-search) #f) (go (rest ls) servers arg has-search))
                  (#t (go (rest ls) servers search has-search)))))))))
    (def search0
      (if (null? (first (rest st)))
        (let ((h (Assoc get (lit nodename) (sys-uname))))
          (let ((d (%wget-index h #\. 0))) (if (null? d) () (substring h (+ d 1) (byte-len h)))))
        (first (rest st))))
    (pair (first st) (if (if (null? search0) #f (string=? search0 ".")) () search0))))

; a server's (NAME IP PORT): NAME's own ":PORT" overrides -port
(def %ns-server
  (fn (_ name)
    (def colon (%wget-last-index name #\:))
    (def port (if (null? colon) () (%wget-digits (substring name (+ colon 1) (byte-len name)))))
    (def host (if (null? port) name (substring name 0 colon)))
    (def ip (guard (_ ()) (net-resolve host)))
    (when (null? ip) (%net-die (string-concat (list "bad address '" name "'"))))
    (list name ip (if (null? port) %ns-port port))))

; --- the exchange: busybox's send_queries ---------------------------------------------

; the run of a query's bytes
(def %ns-run (fn (_ bs) (pair (bytes->str bs) (length bs))))

; send every unanswered query to SERVER; #t, or #f when a write failed
(def %ns-send-all
  (fn (_ fd server queries)
    (let go ((qs queries))
      (match
        ((null? qs) #t)
        ((first (rest (rest (first qs)))) (go (rest qs)))
        (#t
          (let ((r (file-write-run fd (%ns-run (first (rest (first qs)))))))
            (if (< r 0)
              (do (file-write 2 (string-concat (list "nslookup: write to '" (first server) "': "
                    (file-err-text (file-open-err r (first server))) "\n")))
                  #f)
              (go (rest qs)))))))))

; ask SERVER every query; answers how many replies came, -1 after a failed write
(def %ns-send-queries
  (fn (_ server queries)
    (def fd (net-udp-connect (first (rest server)) (first (rest (rest server)))))
    (def timeout (* %ns-timeout 1000))
    (def interval (%wget-div timeout %ns-retry))
    (def tstart (sys-time-ms))
    (def r (%ns-loop fd server queries timeout interval tstart tstart #t 0 (* 2 (length queries)) #f))
    (net-close fd)
    r))

; the wait for replies: a resend each INTERVAL, until TIMEOUT has passed or
; every query has its answer
(def %ns-loop
  (fn (self fd server queries timeout interval tstart tsent send? replies servfail printed?)
    (def now (sys-time-ms))
    (match
      ((>= (- now tstart) timeout) replies)
      ((if send? #t (>= (- now tsent) interval))
        (if (%ns-send-all fd server queries)
          (self fd server queries timeout interval tstart (sys-time-ms) #f replies
                (* 2 (length queries)) printed?)
          -1))
      (#t
        (let ((ready (sys-poll (list (pair fd (list (lit in)))) (- interval (- now tsent)))))
          (if (null? ready)
            (self fd server queries timeout interval tstart tsent #f replies servfail printed?)
            (%ns-on-reply self fd server queries timeout interval tstart tsent replies servfail
                          printed? (file-read-run fd 512))))))))

; one datagram read: print the server's lines on the first, match it to its
; query by id, and print what it says
(def %ns-on-reply
  (fn (_ loop fd server queries timeout interval tstart tsent replies servfail printed? r)
    (unless printed?
      (file-write 1 (string-concat
        (list "Server:\t\t" (first server) "\nAddress:\t" (first (rest server)) ":"
              (%cu-int->str (first (rest (rest server)))) "\n\n"))))
    (def bs (%ns-bytes (first r) 0 (rest r)))
    (def q (if (< (length bs) 4) () (%ns-match queries (first bs) (first (rest bs)))))
    (def rcode (if (null? q) 0 (& (first (rest (rest (rest bs)))) 15)))
    (match
      ((null? q) (loop fd server queries timeout interval tstart tsent #f replies servfail #t))
      ((first (rest (rest q)))
        (loop fd server queries timeout interval tstart tsent #f replies servfail #t))
      ((if (= rcode 2) (> servfail 0) #f)
        (do (file-write-run fd (%ns-run (first (rest q))))
            (loop fd server queries timeout interval tstart tsent #f replies (- servfail 1) #t)))
      (#t
        (do (set-first! (rest (rest q)) #t)
            (when %ns-debug
              (file-write 1 (string-concat
                (list "Query #" (%cu-int->str (%ns-index queries q 0)) " completed in "
                      (%cu-int->str (- (sys-time-ms) tstart)) "ms:\n"))))
            (if (= rcode 0)
              (when (< (%ns-print-reply bs) 0)
                (do (file-write 1 (string-concat (list "*** Can't find " (first q) ": Parse error\n")))
                    (set! %ns-exit 1)))
              (do (file-write 1 (string-concat (list "** server can't find " (first q) ": "
                    (%cu-nth rcode %ns-rcodes) "\n")))
                  (set! %ns-exit 1)))
            (file-write 1 "\n")
            (if (>= (+ replies 1) (length queries)) (+ replies 1)
              (loop fd server queries timeout interval tstart tsent #f (+ replies 1) servfail #t)))))))

(def %ns-match
  (fn (self qs a b)
    (match
      ((null? qs) ())
      ((if (= (first (first (rest (first qs)))) a) (= (first (rest (first (rest (first qs))))) b) #f)
        (first qs))
      (#t (self (rest qs) a b)))))

(def %ns-index
  (fn (self qs q i) (if (eq? (first qs) q) i (self (rest qs) q (+ i 1)))))

; --- the reply: busybox's parse_reply ---------------------------------------------------

; byte I of the list BS, as a vector would answer it
(def %ns-at (fn (_ v i) (vec-ref v i)))
(def %ns-u16 (fn (_ v i) (+ (* 256 (vec-ref v i)) (vec-ref v (+ i 1)))))
(def %ns-u32 (fn (_ v i) (+ (* 65536 (%ns-u16 v i)) (%ns-u16 v (+ i 2)))))

; dn_expand: the name at I as dotted text, and how many bytes it takes there
; -- (TEXT . LENGTH), or nil for a name that runs off the end or loops
(def %ns-name
  (fn (_ v n i)
    (let go ((j i) (parts ()) (len ()) (hops 0))
      (match
        ((>= j n) ())
        ((> hops n) ())
        ((= (vec-ref v j) 0)
          (pair (%ns-join (reverse parts)) (if (null? len) (+ (- j i) 1) len)))
        ((= (& (vec-ref v j) 192) 192)
          (if (>= (+ j 1) n) ()
            (go (+ (* 256 (& (vec-ref v j) 63)) (vec-ref v (+ j 1))) parts
                (if (null? len) (+ (- j i) 2) len) (+ hops 2))))
        (#t
          (let ((k (vec-ref v j)))
            (if (> (+ (+ j k) 1) n) ()
              (go (+ (+ j k) 1)
                  (pair (bytes->str (let take ((m (+ j k)) (acc ())) (if (<= m j) acc (take (- m 1) (pair (vec-ref v m) acc))))) parts)
                  len hops))))))))

(def %ns-join
  (fn (_ parts)
    (if (null? parts) ""
      (string-concat (pair (first parts) (map (fn (_ p) (string-append "." p)) (rest parts)))))))

; the record parse: print each answer as busybox's parse_reply does; answers
; how many, or -1 for a reply it cannot read
(def %ns-print-reply
  (fn (_ bs)
    (def n (length bs))
    (def v (vec-build n (let ((l bs)) (fn (_ i) (let ((b (first l))) (do (set! l (rest l)) b))))))
    (%ns-print-aa v)
    (if (< n 12) -1
      (let ((after-q (%ns-skip-questions v n 12 (%ns-u16 v 4))))
        (if (null? after-q) -1
          (%ns-answers v n after-q 0 (%ns-u16 v 6)))))))

(def %ns-print-aa
  (fn (_ v)
    (match
      ((= (& (vec-ref v 2) 4) 0) (file-write 1 "Non-authoritative answer:\n"))
      (%ns-debug (file-write 1 "authoritative answer:\n"))
      (#t ()))))

(def %ns-skip-questions
  (fn (self v n i k)
    (if (= k 0) i
      (let ((nm (%ns-name v n i)))
        (if (if (null? nm) #t (> (+ (+ i (rest nm)) 4) n)) ()
          (self v n (+ (+ i (rest nm)) 4) (- k 1)))))))

; the answers from I, the Kth of COUNT
(def %ns-answers
  (fn (self v n i k count)
    (if (= k count) k
      (let ((nm (%ns-name v n i)))
        (if (if (null? nm) #t (> (+ (+ i (rest nm)) 10) n)) -1
          (let ((at (+ i (rest nm))))
            (let ((type (%ns-u16 v at)) (rdlen (%ns-u16 v (+ at 8))) (rd (+ at 10)))
              (if (> (+ rd rdlen) n) -1
                (if (< (%ns-print-rr v n (first nm) type rd rdlen) 0) -1
                  (self v n (+ rd rdlen) (+ k 1) count))))))))))

; one record, as busybox prints it; -1 for one it cannot read
(def %ns-print-rr
  (fn (_ v n name type rd rdlen)
    (def say (fn (_ parts) (do (file-write 1 (string-concat parts)) 0)))
    (def named (fn (_ fmt-mid at)
      (let ((d (%ns-name v n at)))
        (if (null? d) -1 (say (list name fmt-mid (first d) "\n"))))))
    (match
      ((= type 1)
        (if (= rdlen 4)
          (say (list "Name:\t" name "\nAddress: "
                     (%ns-join (map %cu-int->str (list (vec-ref v rd) (vec-ref v (+ rd 1)) (vec-ref v (+ rd 2)) (vec-ref v (+ rd 3))))) "\n"))
          -1))
      ((= type 28)
        (if (= rdlen 16)
          (say (list "Name:\t" name "\nAddress: " (%ns-ntop6 v rd) "\n"))
          -1))
      ((= type 2) (named "\tnameserver = " rd))
      ((= type 5) (named "\tcanonical name = " rd))
      ((= type 12) (named "\tname = " rd))
      ((= type 15)
        (if (< rdlen 2) (do (file-write 1 "MX record too short\n") -1)
          (let ((d (%ns-name v n (+ rd 2))))
            (if (null? d) -1
              (say (list name "\tmail exchanger = " (%cu-int->str (%ns-u16 v rd)) " " (first d) "\n"))))))
      ((= type 16)
        (if (< rdlen 1) -1
          (let ((k (vec-ref v rd)))
            (if (= k 0) 0
              (say (list name "\ttext = \""
                         (bytes->str (let take ((m (+ rd k)) (acc ()))
                                       (if (<= m rd) acc
                                         (take (- m 1) (if (= (vec-ref v m) 0) () (pair (vec-ref v m) acc))))))
                         "\"\n"))))))
      ((= type 33)
        (if (< rdlen 6) -1
          (let ((d (%ns-name v n (+ rd 6))))
            (if (null? d) -1
              (say (list name "\tservice = " (%cu-int->str (%ns-u16 v rd)) " "
                         (%cu-int->str (%ns-u16 v (+ rd 2))) " " (%cu-int->str (%ns-u16 v (+ rd 4)))
                         " " (first d) "\n"))))))
      ((= type 6) (%ns-print-soa v n name rd rdlen))
      (#t 0))))

(def %ns-print-soa
  (fn (_ v n name rd rdlen)
    (def origin (if (< rdlen 20) () (%ns-name v n rd)))
    (def mail (if (null? origin) () (%ns-name v n (+ rd (rest origin)))))
    (if (null? mail) -1
      (let ((at (+ (+ rd (rest origin)) (rest mail))))
        (do (file-write 1 (string-concat
              (list name "\n\torigin = " (first origin) "\n\tmail addr = " (first mail)
                    "\n\tserial = " (%cu-int->str (%ns-u32 v at))
                    "\n\trefresh = " (%cu-int->str (%ns-u32 v (+ at 4)))
                    "\n\tretry = " (%cu-int->str (%ns-u32 v (+ at 8)))
                    "\n\texpire = " (%cu-int->str (%ns-u32 v (+ at 12)))
                    "\n\tminimum = " (%cu-int->str (%ns-u32 v (+ at 16))) "\n")))
            0)))))

; inet_ntop for 16 bytes at I: lowercase groups without leading zeros, the
; longest run of two or more zero groups as ::
(def %ns-ntop6
  (fn (_ v i)
    (def groups (let go ((k 7) (acc ())) (if (< k 0) acc (go (- k 1) (pair (%ns-u16 v (+ i (* 2 k))) acc)))))
    (def best (%ns-zero-run groups 0 -1 0 -1 0))
    (def hex (fn (_ g) (%ns-hex-group g)))
    (def bs (first best))
    (def bl (rest best))
    (if (< bl 2)
      (%ns-join-colon (map hex groups))
      (string-concat
        (list (%ns-join-colon (map hex (%ns-take bs groups))) "::"
              (%ns-join-colon (map hex (%ns-drop (+ bs bl) groups))))))))

; the longest run of zeros in GS: (START . LENGTH), the first of the longest
(def %ns-zero-run
  (fn (self gs i cur-start cur-len best-start best-len)
    (match
      ((null? gs) (if (> cur-len best-len) (pair cur-start cur-len) (pair best-start best-len)))
      ((= (first gs) 0)
        (self (rest gs) (+ i 1) (if (< cur-start 0) i cur-start) (+ cur-len 1) best-start best-len))
      ((> cur-len best-len) (self (rest gs) (+ i 1) -1 0 cur-start cur-len))
      (#t (self (rest gs) (+ i 1) -1 0 best-start best-len)))))

(def %ns-take (fn (self n l) (if (<= n 0) () (pair (first l) (self (- n 1) (rest l))))))
(def %ns-drop (fn (self n l) (if (<= n 0) l (self (- n 1) (rest l)))))
(def %ns-join-colon
  (fn (_ ss) (if (null? ss) "" (string-concat (pair (first ss) (map (fn (_ s) (string-append ":" s)) (rest ss)))))))
(def %ns-hex-group
  (fn (_ g)
    (if (= g 0) "0"
      (list->string (let go ((v g) (acc ())) (if (= v 0) acc (go (%wget-div v 16) (pair (%ns-hexch (% v 16)) acc))))))))

; --- the applet ------------------------------------------------------------------

(def %cu-nslookup
  (fn (_ argv stdin-thunk)
    (set! %ns-port 53) (set! %ns-retry 2) (set! %ns-timeout 5)
    (set! %ns-debug #f) (set! %ns-exit 0)
    (guard (e (if (eq? (Err label e) (lit net))
                (do (file-write 2 (string-concat (list "nslookup: " (e msg) "\n"))) 1)
                (error e)))
      (%ns-run-applet argv))))

(def %ns-run-applet
  (fn (_ argv)
    (def parsed (%ns-options argv ()))
    (match
      ((eq? parsed (lit usage)) (%ns-usage))
      ((null? (rest parsed)) (%ns-usage))
      ((if (not (null? (rest (rest parsed)))) (not (null? (rest (rest (rest parsed))))) #f) (%ns-usage))
      (#t (%ns-lookup (first parsed) (first (rest parsed))
                      (if (null? (rest (rest parsed))) () (first (rest (rest parsed)))))))))

(def %ns-lookup
  (fn (_ types host server-arg)
    (def conf (if (null? server-arg) (%ns-resolv-conf) (pair () ())))
    (def names (if (null? server-arg)
                 (if (null? (first conf)) (list "127.0.0.1") (first conf))
                 (list server-arg)))
    (def servers (map %ns-server names))
    (def search (rest conf))
    (def ptr (if (null? types) (%ns-make-ptr host) ()))
    (def queries
      (match
        ((not (null? ptr)) (list (%ns-query ptr 12)))
        ((null? types) (append (%ns-with-search 1 host search) (%ns-with-search 28 host search)))
        (#t (%ns-flatten
              (map (fn (_ t) (%ns-with-search t host search))
                   (filter (fn (_ t) (%wget-memv t types)) (map (fn (_ e) (rest e)) %ns-types)))))))
    (%ns-set-ids queries)
    (def answered (%ns-each-server servers queries))
    (if (not answered)
      (do (file-write 1 ";; connection timed out; no servers could be reached\n\n") 1)
      (let ((missing (filter (fn (_ q) (not (first (rest (rest q))))) queries)))
        (do (map (fn (_ q) (file-write 1 (string-concat (list "*** Can't find " (first q) ": No answer\n"))))
                 missing)
            (unless (null? missing) (file-write 1 "\n"))
            %ns-exit)))))

(def %ns-flatten (fn (_ ls) (if (null? ls) () (append (first ls) (%ns-flatten (rest ls))))))

; ids from the clock, one after another, as busybox numbers them
(def %ns-set-ids
  (fn (_ queries)
    (let go ((qs queries) (id (sys-time-ms)))
      (unless (null? qs)
        (do (unless (null? (first (rest (first qs))))
              (let ((bs (first (rest (first qs)))))
                (do (set-first! bs (% (%wget-div id 256) 256))
                    (set-first! (rest bs) (% id 256)))))
            (go (rest qs) (+ id 1)))))))

; each server in turn until one answers; #t once one has
(def %ns-each-server
  (fn (self servers queries)
    (if (null? servers) #f
      (if (> (%ns-send-queries (first servers) queries) 0) #t
        (self (rest servers) queries)))))

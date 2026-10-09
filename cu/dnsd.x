; # x-coreutils -- the small tools, as applets
;
; ## cu/dnsd.x -- dnsd: busybox's small static DNS server
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; networking/dnsd.c: NAME ADDRESS lines from a config file, then a UDP socket
; on -i's address and -p's port answering A queries by name and PTR queries by
; the reversed address, each answer the question with one record after it,
; TTL -t's.  A name whose first label is * answers every A query.  A query it
; cannot answer gets the question back with a response code -- not
; implemented, or name error -- unless -s keeps it silent.
;
; Names are compared as busybox compares them: the wire form, each label after
; its length byte, against the config's name turned to the same form, with
; strcasecmp's folding of every byte, the lengths too.  -d daemonizes and, as
; busybox then logs to syslog, says nothing more.

(def %dn-verbose? #f)
(def %dn-quiet? #f)            ; -d: what busybox sends to syslog is not said
(def %dn-say
  (fn (_ msg) (unless %dn-quiet? (file-write 2 (string-concat (list "dnsd: " msg "\n"))))))

(def %dn-die (fn (_ msg) (Err raise (lit net) msg ())))

; --- addresses ------------------------------------------------------------------

; undot: ".a.bc" as the bytes 1 a 2 b c -- each dot the length of what follows
(def %dn-undot
  (fn (_ s)
    (let go ((labels (rest (Str8 split "." s))) (acc ()))
      (if (null? labels) acc
        (go (rest labels)
            (append acc (pair (byte-len (first labels)) (%cu-bytes (first labels) 0 (byte-len (first labels))))))))))

; --- the config file ---------------------------------------------------------------

; config_read's PARSE_NORMAL over "# \t" for 2 tokens: the comment cut at #,
; the words split on spaces and tabs, the second taking the rest of the line
(def %dn-tokens
  (fn (_ line)
    (def hash (%wget-index line #\# 0))
    (def text (%dn-trim (if (null? hash) line (substring line 0 hash))))
    (def sp (let go ((i 0)) (if (if (< i (byte-len text)) (not (%wget-memv (byte-at text i) (list #\space #\tab))) #f) (go (+ i 1)) i)))
    (if (= (byte-len text) 0) ()
      (if (= sp (byte-len text)) (list text)
        (list (substring text 0 sp) (%dn-trim (substring text sp (byte-len text))))))))

(def %dn-trim
  (fn (_ s)
    (def ws? (fn (_ c) (%wget-memv c (list #\space #\tab #\return))))
    (def a (let go ((i 0)) (if (if (< i (byte-len s)) (ws? (byte-at s i)) #f) (go (+ i 1)) i)))
    (def b (let go ((i (byte-len s))) (if (if (> i a) (ws? (byte-at s (- i 1))) #f) (go (- i 1)) i)))
    (substring s a b)))

; the entries: (NAME-BYTES IP-BYTES RIP-BYTES), in the file's order
(def %dn-conf
  (fn (_ path)
    (def fd (file-open-or-err file-open-read path))
    (if (Err err? fd)
      (do (%dn-say (string-concat (list path ": " (file-err-text fd)))) ())
      (let ((text (file-read-all path)))
        (do (file-close fd)
            (let go ((lines (%dn-lines text)) (no 1) (acc ()))
              (if (null? lines) (reverse acc)
                (go (rest lines) (+ no 1) (%dn-conf-line (first lines) no acc)))))))))

(def %dn-conf-line
  (fn (_ line no acc)
    (def ts (%dn-tokens line))
    (match
      ((null? ts) acc)
      ((null? (rest ts))
        (do (%dn-say (string-concat (list "bad line " (%cu-int->str no) ": 1 tokens found, 2 needed"))) acc))
      (#t (let ((ip (net-aton (first (rest ts)))))
            (if (null? ip)
              (do (%dn-say (string-concat (list "error at line " (%cu-int->str no) ", skipping"))) acc)
              (do (when %dn-verbose? (%dn-say (string-concat (list "name:" (first ts) ", ip:" (first (rest ts))))))
                  (pair (list (%dn-undot (string-append "." (first ts))) ip
                              (%dn-undot (string-concat (list "." (%cu-int->str (%cu-nth 3 ip)) "." (%cu-int->str (%cu-nth 2 ip))
                                                              "." (%cu-int->str (%cu-nth 1 ip)) "." (%cu-int->str (first ip))))))
                        acc))))))))

; TEXT's lines, without their newlines
(def %dn-lines
  (fn (_ s)
    (let go ((i 0) (acc ()))
      (let ((nl (%wget-index s #\newline i)))
        (if (null? nl) (reverse (if (< i (byte-len s)) (pair (substring s i (byte-len s)) acc) acc))
          (go (+ nl 1) (pair (substring s i nl) acc)))))))

; --- the lookup --------------------------------------------------------------------

(def %dn-lower (fn (_ b) (if (if (>= b 65) (<= b 90) #f) (+ b 32) b)))

(def %dn-same?
  (fn (self a b)
    (match ((null? a) (null? b))
           ((null? b) #f)
           ((= (%dn-lower (first a)) (%dn-lower (first b))) (self (rest a) (rest b)))
           (#t #f))))

(def %dn-prefix?
  (fn (self p s)
    (match ((null? p) #t) ((null? s) #f) ((= (first p) (first s)) (self (rest p) (rest s))) (#t #f))))

(def %dn-wild? (fn (_ name) (if (= (first name) 1) (= (%cu-nth 1 name) #\*) #f)))

; table_lookup: an A query's address bytes, or a PTR query's name bytes and
; their NUL; nil when no entry answers
(def %dn-lookup
  (fn (self entries type qname)
    (if (null? entries) ()
      (let ((name (first (first entries))))
        (match
          ((= type 1)
            (if (if (%dn-wild? name) #t (%dn-same? name qname))
              (%cu-nth 1 (first entries))
              (self (rest entries) type qname)))
          ((if (not (%dn-wild? name)) (%dn-prefix? (%cu-nth 2 (first entries)) qname) #f)
            (append name (list 0)))
          (#t (self (rest entries) type qname)))))))

; --- a packet -------------------------------------------------------------------------

(def %dn-u16 (fn (_ n) (list (% (%wget-div n 256) 256) (% n 256))))
(def %dn-word (fn (_ bs i) (+ (* 256 (%cu-nth i bs)) (%cu-nth (+ i 1) bs))))

; process_packet: the reply's bytes, or nil when none is sent
(def %dn-process
  (fn (_ entries ttl bs)
    (def n (length bs))
    (match
      ((= (%dn-word bs 4) 0) (do (%dn-say "packet has 0 queries, ignored") ()))
      ((>= (%dn-word bs 2) 32768) (do (%dn-say "response packet, ignored") ()))
      (#t (%dn-question entries ttl bs n)))))

(def %dn-question
  (fn (_ entries ttl bs n)
    (def after (let go ((xs (%cu-nthrest 12 bs)) (acc ()))
                 (if (if (null? xs) #t (= (first xs) 0)) (reverse acc) (go (rest xs) (pair (first xs) acc)))))
    (def qname after)
    (def query-len (+ (length qname) 1 4))
    (def answb (+ 12 query-len))
    (if (< n answb) (do (%dn-say "packet too short") ())
      (let ((type (%dn-word bs (+ 12 (length qname) 1))) (class (%dn-word bs (+ 12 (length qname) 3))))
        (%dn-answer entries ttl bs qname query-len answb
          (match ((not (= (bit-and (%dn-word bs 2) 30720) 0)) "opcode != 0")
                 ((not (= class 1)) "class != 1")
                 ((not (if (= type 1) #t (= type 12))) "type is !REQ_A and !REQ_PTR")
                 (#t ()))
          type)))))

(def %dn-answer
  (fn (_ entries ttl bs qname query-len answb refused type)
    (def found (if (null? refused) (%dn-lookup entries type qname) ()))
    (def rlen (if (null? found) 4 (length found)))
    (def fits? (<= (+ answb query-len 6 rlen) 512))
    (def flags (match ((not (null? refused)) 32772)
                      ((if (null? found) #t (not fits?)) 33795)
                      (#t 33792)))
    (def err (match ((not (null? refused)) refused) ((= flags 33795) "name is not found") (#t ())))
    (when (if %dn-verbose? (null? err) #f) (%dn-say "returning positive reply"))
    (when (if %dn-verbose? (not (null? err)) #f)
      (%dn-say (string-concat (list err ", " (if %dn-quiet-s? "dropping query" "sending error reply")))))
    (if (if (not (null? err)) %dn-quiet-s? #f) ()
      (append (%cu-take bs 2)
              (%dn-u16 (bit-or (%dn-word bs 2) flags))
              (%dn-u16 1)
              (if (null? err) (%dn-u16 1) (list (%cu-nth 6 bs) (%cu-nth 7 bs)))
              (list 0 0 0 0)
              (%cu-take (%cu-nthrest 12 bs) query-len)
              (if (not (null? err)) ()
                (append (%cu-take (%cu-nthrest 12 bs) query-len)
                        (list (% (%wget-div ttl 16777216) 256) (% (%wget-div ttl 65536) 256)
                              (% (%wget-div ttl 256) 256) (% ttl 256))
                        (%dn-u16 rlen)
                        found))))))

(def %dn-quiet-s? #f)          ; -s: no reply but a positive one

; --- the applet -----------------------------------------------------------------------

; xatou_range: S as a number from LO to HI, or the run ends naming it
(def %dn-range
  (fn (_ s lo hi)
    (def n (%wget-digits s))
    (match ((null? n) (%dn-die (string-concat (list "invalid number '" s "'"))))
           ((if (< n lo) #t (> n hi))
             (%dn-die (string-concat (list "number " s " is not in " (%cu-int->str lo) ".." (%cu-int->str hi) " range"))))
           (#t n))))

(def %dn-bind
  (fn (_ addr port)
    (let ((fd (net-udp-open addr port #f)))
      (if (Err err? fd) (%dn-die (string-append "bind: " (file-err-text fd))) fd))))

(def %cu-dnsd
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "dnsd" argv))
    (guard (e (if (eq? (Err label e) (lit net))
                (do (file-write 2 (string-concat (list "dnsd: " (e msg) "\n"))) 1)
                (error e)))
      (%dn-main o))))

(def %dn-main
  (fn (_ o)
    (set! %dn-verbose? (Opts on? o "-v"))
    (set! %dn-quiet-s? (Opts on? o "-s"))
    (def ttl (let ((t (Opts value o "-t"))) (if (null? t) 120 (%dn-range t 1 4294967295))))
    (def port (let ((p (Opts value o "-p"))) (if (null? p) 53 (%dn-range p 1 65535))))
    (when (Opts on? o "-d") (do (%hd-daemonize) (set! %dn-quiet? #t)))
    (def entries (%dn-conf (let ((c (Opts value o "-c"))) (if (null? c) "/etc/dnsd.conf" c))))
    (def addr (let ((i (Opts value o "-i"))) (if (null? i) "0.0.0.0" i)))
    (when (null? (%dn-dotted addr)) (%dn-die (string-concat (list "bad address '" addr "'"))))
    (def fd (%dn-bind addr port))
    (%dn-say (string-concat (list "accepting UDP packets on " addr ":" (%cu-int->str port))))
    (%dn-serve fd entries ttl)))

; xdotted2sockaddr: a numeric address, four dotted parts, each 0..255
(def %dn-dotted
  (fn (_ s)
    (let ((parts (Str8 split "." s)))
      (if (if (= (length parts) 4) (List all? (fn (_ p) (let ((n (%wget-digits p))) (if (null? n) #f (<= n 255)))) parts) #f)
        (map %wget-digits parts)
        ()))))

(def %dn-serve
  (fn (self fd entries ttl)
    (%cu-sweep-tick! %cu-sweep-lines)
    (let ((got (net-recv-from-run fd 513)))
      (let ((n (rest (first got))))
        (if (if (< n 12) #t (> n 512))
          (%dn-say (string-concat (list "packet size " (%cu-int->str n) ", ignored")))
          (do (when %dn-verbose? (%dn-say "got UDP packet"))
              (let ((reply (%dn-process entries ttl (%cu-bytes (first (first got)) 0 n))))
                (unless (null? reply)
                  (net-send-to-run fd (pair (bytes->str reply) (length reply)) (first (rest got)) (rest (rest got)))))))))
    (self fd entries ttl)))

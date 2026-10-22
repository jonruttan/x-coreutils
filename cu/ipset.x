; # x-coreutils -- the small tools, as applets
;
; ## cu/ipset.x -- ip's verbs that change the kernel's state: addresses and links
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's ipaddr_modify, the flush half of ipaddr_list_or_flush, and
; iplink's do_set and do_add_or_delete (networking/libiproute).  `ip addr
; add|change|replace|delete` builds an RTM_NEWADDR or RTM_DELADDR from its
; words and hands it to the kernel through rtnl_talk, which waits for the
; kernel's answer; `ip addr flush` dumps the addresses the filter keeps and
; sends each back as an RTM_DELADDR until a dump finds none.  `ip link set`
; reaches the kernel through the SIOCSIF ioctls (name, address, qlen, mtu,
; flags) and netlink (master, netns); `ip link add|delete` sends
; RTM_NEWLINK or RTM_DELLINK, with a vlan's or a vrf's options nested.

; --- requests ---------------------------------------------------------------------

; N as K little-endian bytes
(module cu/ipset)

(import cu/prims append byte-at byte-len char->integer cu-int->str cu-nth
  cu-ptr-call cu-ptr-ref cu-str->ptr cu-string-type cvt file-write filter
  length libc-strerror map reverse str-make-raw string-append string-concat
  string=? substring)

(def ip-le
  (fn (_ n k) (map (fn (_ i) (& (>> n (* 8 i)) 255)) (List range 0 k))))

(def %ip-str-bytes
  (fn (_ s) (map (fn (_ i) (char->integer (byte-at s i))) (List range 0 (byte-len s)))))

; an rtattr: its length and type, BYTES, and the padding to four
(def ip-rta
  (fn (_ type bytes)
    (def n (+ 4 (length bytes)))
    (append (ip-le n 2) (ip-le type 2) bytes (map (fn (_ k) 0) (List range n (ip-align n))))))

; a request: (KIND FLAGS MAX LEN ATTRS), ATTRS the rtattrs last first and LEN
; nlmsg_len so far, the body's length counted
(def ip-req (fn (_ kind flags max body-len) (list kind flags max (+ 16 body-len) ())))

; addattr_l: REQ with the attribute, or as it was where it would pass MAX
(def %ip-add
  (fn (_ req type bytes)
    (def len (ip-align (+ (cu-nth 3 req) 4 (length bytes))))
    (if (> len (cu-nth 2 req)) req
      (list (first req) (cu-nth 1 req) (cu-nth 2 req) len (pair (ip-rta type bytes) (cu-nth 4 req))))))

; the request's bytes, with BODY and SEQ
(def ip-req-bytes
  (fn (_ req body seq)
    (append (ip-le (cu-nth 3 req) 4) (ip-le (first req) 2) (ip-le (cu-nth 1 req) 2) (ip-le seq 4) (ip-le 0 4)
            body (List flatten (reverse (cu-nth 4 req))))))

; a raw buffer holding BYTES
(def ip-buf
  (fn (_ bytes)
    (let ((b (str-make-raw (if (null? bytes) 1 (length bytes)))))
      (do (map (fn (_ e) (inet-set! b (first e) (rest e) 1)) (ip-indexed bytes)) b))))

; rtnl_talk: the request sent with NLM_F_ACK and the kernel's answer read;
; 0 where it says yes, -1 where it refuses, said as RTNETLINK answers
(def ip-talk
  (fn (_ f fd bytes seq)
    (def out (ip-buf bytes))
    (inet-set! out 6 (| (cu-ptr-ref (cu-str->ptr out) 6 2) 4) 2)
    (let ((r (in-call (cu-ptr-call (in-c "write") fd (cu-str->ptr out) (length bytes)))))
      (if (< r 0) (do (ip-say f (string-append "can't talk to rtnetlink: " (libc-strerror (Err errno-of r)))) -1)
        (%ip-answer f fd seq (str-make-raw 8192))))))

(def %ip-answer
  (fn (_ f fd seq buf)
    (let ((n (in-call (cu-ptr-call (in-c "recv") fd (cu-str->ptr buf) 8192 0))))
      (match
        ((< n 0) (do (ip-say f (string-append "OVERRUN: " (libc-strerror (Err errno-of n)))) (%ip-answer f fd seq buf)))
        ((= n 0) (do (ip-say f "EOF on netlink") -1))
        (#t (let ((r (%ip-acks f (cu-str->ptr buf) n seq))) (if (null? r) (%ip-answer f fd seq buf) r)))))))

; the answers in the N bytes at P: 0 or -1 for the one to SEQ, nil where none is
(def %ip-acks
  (fn (_ f p n seq)
    (let go ((o 0))
      (let ((len (if (> (+ o 16) n) 0 (cu-ptr-ref p o 4))))
        (match
          ((> (+ o 16) n) ())
          ((if (< len 16) #t (> (+ o len) n)) (ip-die f (string-concat (list "malformed message: len=" (cu-int->str len) "!"))))
          ((not (= (cu-ptr-ref p (+ o 8) 4) seq)) (go (+ o (ip-align len))))
          ((not (= (cu-ptr-ref p (+ o 4) 2) 2)) (do (ip-say f "unexpected reply!") (go (+ o (ip-align len)))))
          ((< len 36) (do (ip-say f "ERROR truncated") -1))
          ((= (cu-ptr-ref p (+ o 16) 4) 0) 0)
          (#t (do (ip-say f (string-append "RTNETLINK answers: " (libc-strerror (- 0 (inet-int32 (cu-ptr-ref p (+ o 16) 4)))))) -1)))))))

; ll_init_map: the links dumped, as each verb does before it asks
(def ip-init-map (fn (_ f fd) (ip-dump f fd 18 0 1 ip-link-of)))

; --- numbers ----------------------------------------------------------------------

(def %ip-space? (fn (_ c) (if (= c #\space) #t (if (>= c #\tab) (<= c #\return) #f))))

; strtoul with base 0 over all of S: its value, or nil where S is empty, has
; more after the number, or passes LIMIT; a minus sign wraps it, as strtoul's does
(def ip-strtoul
  (fn (_ s limit)
    (def n (byte-len s))
    (def at (let go ((i 0)) (if (if (< i n) (%ip-space? (byte-at s i)) #f) (go (+ i 1)) i)))
    (def neg (if (< at n) (= (byte-at s at) #\-) #f))
    (def d0 (if (if (< at n) (if neg #t (= (byte-at s at) #\+)) #f) (+ at 1) at))
    ; 0x before a hex digit is base 16; a 0 before anything else, base 8
    (def x? (if (< (+ d0 2) n) (if (= (byte-at s d0) #\0) (if (if (= (byte-at s (+ d0 1)) #\x) #t (= (byte-at s (+ d0 1)) #\X)) (>= (ip-digit (byte-at s (+ d0 2)) 16) 0) #f) #f) #f))
    (def base (match (x? 16) ((if (< d0 n) (= (byte-at s d0) #\0) #f) 8) (#t 10)))
    (def start (if (= base 16) (+ d0 2) d0))
    (let go ((i start) (v 0))
      (let ((d (if (< i n) (ip-digit (byte-at s i) base) -1)))
        (match
          ((>= d 0) (go (+ i 1) (+ (* v base) d)))
          ((if (= i start) #t (< i n)) ())
          ((if neg (> v 0) #f) ())
          ((> v limit) ())
          (#t v))))))

; get_unsigned, get_u32 and get_u16: S's value, or the run ended as invarg ends it
(def ip-unsigned
  (fn (_ f s what limit)
    (let ((v (if (= (byte-len s) 0) () (ip-strtoul s limit)))) (if (null? v) (ip-invarg f s what) v))))

; sscanf "%x": the hex number S starts with, or nil
(def %ip-scanx
  (fn (_ s)
    (def n (byte-len s))
    (def at (let go ((i 0)) (if (if (< i n) (%ip-space? (byte-at s i)) #f) (go (+ i 1)) i)))
    (def neg (if (< at n) (= (byte-at s at) #\-) #f))
    (def d0 (if (if (< at n) (if neg #t (= (byte-at s at) #\+)) #f) (+ at 1) at))
    (def x? (if (< (+ d0 1) n) (if (= (byte-at s d0) #\0) (if (= (byte-at s (+ d0 1)) #\x) #t (= (byte-at s (+ d0 1)) #\X)) #f) #f))
    (let go ((i (if x? (+ d0 2) d0)) (v 0) (any x?))
      (let ((d (if (< i n) (ip-digit (byte-at s i) 16) -1)))
        (match ((>= d 0) (go (+ i 1) (+ (* v 16) d) #t))
               ((not any) ())
               (#t (if neg (- 0 v) v)))))))

; ll_addr_a2n: ARG as at most LEN link-layer bytes, (COUNT . BYTES), COUNT
; one past LEN where ARG has more; -1 where a part is no byte, said
(def %ip-lladdr
  (fn (_ f arg len)
    (if (>= (dp-find arg 0 #\.) 0)
      (let ((a (ip-addr1 arg 2)))
        (match ((not (first a)) (do (ip-say f (string-concat (list "\"" arg "\" is invalid lladdr"))) -1))
               ((< len 4) -1)
               (#t (pair 4 (List take 4 (List ref 2 a))))))
      (let go ((i 0) (s arg) (acc ()))
        (let ((c (dp-find s 0 #\:)))
          (let ((part (if (< c 0) s (substring s 0 c))) (more (if (< c 0) () (substring s (+ c 1) (byte-len s)))))
            (let ((v (%ip-scanx part)))
              (match
                ((>= i len) (pair (+ i 1) (reverse acc)))
                ((if (null? v) #t (if (< v 0) #t (> v 255))) (do (ip-say f (string-concat (list "\"" part "\" is invalid lladdr"))) -1))
                ((null? more) (pair (+ i 1) (reverse (pair v acc))))
                (#t (go (+ i 1) more (pair v acc)))))))))))

; --- ip addr add, change, replace, delete -----------------------------------------

; S, the modify's state, is an alist: req, family, peer and lcl (prefixes or
; nil), peer-len, local-len, brd-len, any-len, valid and pref (the words, or
; nil), lifetimes, scope (or nil), dev, label, flags, plen

(def %ip-s-get (fn (_ s k) (ip-get s k)))

(def ip-attr!
  (fn (_ s type bytes) (ip-put s (lit req) (%ip-add (ip-get s (lit req)) type bytes))))

; the family the first address sets where none was asked
(def ip-family!
  (fn (_ s family) (if (= (ip-get s (lit family)) 0) (ip-put s (lit family) family) s)))

(def ip-pfx-bytes (fn (_ p) (List take (List ref 3 p) (List ref 1 p))))

; get_addr: ARG as an address, (FAMILY BYTES BYTELEN), or the run ended
(def ip-address
  (fn (_ f arg family)
    (when (= family 17)
      (ip-die f (string-concat (list "\"" arg "\" may be inet address, but it is not allowed in this context"))))
    (let ((a (ip-addr1 arg family)))
      (if (first a) (rest a)
        (ip-die f (string-concat (list "an inet address is expected rather than \"" arg "\"")))))))

(def ip-prefix-in
  (fn (_ f arg family)
    (when (= family 17)
      (ip-die f (string-concat (list "\"" arg "\" may be inet prefix, but it is not allowed in this context"))))
    (ip-prefix f arg family)))

(def %ip-duparg
  (fn (_ f key arg) (ip-die f (string-concat (list "duplicate \"" key "\": \"" arg "\" is the second value")))))

; set_lifetime
(def %ip-lifetime
  (fn (_ f arg what) (if (string=? arg "forever") 4294967295 (ip-unsigned f arg what 4294967295))))

(def %ip-modify-words (list "peer" "remote" "broadcast" "brd" "anycast" "valid_lft" "preferred_lft" "scope" "dev" "label" "noprefixroute" "local"))

; one of the modify's words at the front of WS: (S . WORDS-LEFT)
(def %ip-modify-word
  (fn (_ f s ws)
    (def k (List find-index (fn (_ w) (string=? w (first ws))) %ip-modify-words))
    (def k1 (if (null? k) -1 k))
    (match
      ((if (>= k1 0) (<= k1 1) #f) (%ip-peer f s (ip-next f ws)))
      ((if (>= k1 2) (<= k1 3) #f) (%ip-brd f s (ip-next f ws)))
      ((= k1 4) (%ip-anycast f s (ip-next f ws)))
      ((if (= k1 5) #t (= k1 6)) (%ip-lft-word f s ws (if (= k1 5) "valid_lft" "preferred_lft") (if (= k1 5) (lit valid) (lit pref))))
      ((= k1 7) (let ((a (ip-next f ws)))
                  (let ((id (ip-scope-id f (first a))))
                    (if (null? id) (ip-invarg f (first a) "scope") (pair (ip-put s (lit scope) id) (rest a))))))
      ((= k1 8) (let ((a (ip-next f ws))) (pair (ip-put s (lit dev) (first a)) (rest a))))
      ((= k1 9) (let ((a (ip-next f ws)))
                  (pair (ip-attr! (ip-put s (lit label) (first a)) 3 (append (%ip-str-bytes (first a)) (list 0))) (rest a))))
      ((= k1 10) (pair (ip-put s (lit flags) (| (ip-get s (lit flags)) 512)) (rest ws)))
      (#t (%ip-local f s (if (= k1 11) (ip-next f ws) ws))))))

(def %ip-peer
  (fn (_ f s a)
    (unless (= (ip-get s (lit peer-len)) 0) (%ip-duparg f "peer" (first a)))
    (let ((p (ip-prefix-in f (first a) (ip-get s (lit family)))))
      (pair (List fold (fn (_ t kv) (ip-put t (first kv) (rest kv))) (ip-attr! (ip-family! s (first p)) 1 (ip-pfx-bytes p))
                       (list (pair (lit peer) p) (pair (lit peer-len) (List ref 3 p)) (pair (lit plen) (& (List ref 2 p) 255))))
            (rest a)))))

(def %ip-brd
  (fn (_ f s a)
    (unless (= (ip-get s (lit brd-len)) 0) (%ip-duparg f "broadcast" (first a)))
    (match
      ((string=? (first a) "+") (pair (ip-put s (lit brd-len) -1) (rest a)))
      ((string=? (first a) "-") (pair (ip-put s (lit brd-len) -2) (rest a)))
      (#t (let ((ad (ip-address f (first a) (ip-get s (lit family)))))
            (pair (ip-put (ip-attr! (ip-family! s (first ad)) 4 (List take (List ref 2 ad) (List ref 1 ad))) (lit brd-len) (List ref 2 ad))
                  (rest a)))))))

(def %ip-anycast
  (fn (_ f s a)
    (unless (= (ip-get s (lit any-len)) 0) (%ip-duparg f "anycast" (first a)))
    (let ((ad (ip-address f (first a) (ip-get s (lit family)))))
      (pair (ip-put (ip-attr! (ip-family! s (first ad)) 5 (List take (List ref 2 ad) (List ref 1 ad))) (lit any-len) (List ref 2 ad))
            (rest a)))))

; valid_lft and preferred_lft: a second one is refused before its value is read
(def %ip-lft-word
  (fn (_ f s ws what key)
    (unless (null? (ip-get s key)) (%ip-duparg f what (first ws)))
    (let ((a (ip-next f ws)))
      (pair (ip-put s key (%ip-lifetime f (first a) what)) (rest a)))))

(def %ip-local
  (fn (_ f s a)
    (unless (= (ip-get s (lit local-len)) 0)
      (ip-die f (string-concat (list "either \"local\" is duplicate, or \"" (first a) "\" is garbage"))))
    (let ((p (ip-prefix-in f (first a) (ip-get s (lit family)))))
      (pair (ip-put (ip-put (ip-attr! (ip-family! s (first p)) 2 (ip-pfx-bytes p)) (lit lcl) p) (lit local-len) (List ref 3 p))
            (rest a)))))

; the broadcast "+" or "-" asks for: PEER's host bits set or cleared, where its prefix leaves any
(def %ip-brd-of
  (fn (_ peer set?)
    (def bits (List ref 2 peer))
    (def v (ip-num (reverse (List take 4 (List ref 1 peer)))))
    (def host (- (<< 1 (- 32 bits)) 1))
    (def w (if set? (| v host) (& v (^ host 4294967295))))
    (List take (List ref 3 peer) (append (reverse (ip-le w 4)) (List drop 4 (List ref 1 peer))))))

; ipaddr_modify after its words: what the kernel is handed
(def %ip-modify-finish
  (fn (_ f s del?)
    (def dev (ip-get s (lit dev)))
    (def label (ip-get s (lit label)))
    (def zero (list 2 (ip-pad16 ()) 0 0))
    (def lcl (if (null? (ip-get s (lit lcl))) zero (ip-get s (lit lcl))))
    (def s1 (if (> (ip-get s (lit flags)) 255) (ip-attr! s 8 (ip-le (ip-get s (lit flags)) 4)) s))
    (when (null? dev) (ip-die f "need \"dev IFACE\""))
    (unless (if (null? label) #t (if (>= (byte-len label) (byte-len dev)) (string=? (substring label 0 (byte-len dev)) dev) #f))
      (ip-die f (string-concat (list "\"dev\" (" dev ") must match \"label\" (" label ")"))))
    (def own-peer? (if (= (ip-get s (lit peer-len)) 0) (if (> (ip-get s (lit local-len)) 0) (not del?) #f) #f))
    (def s2 (if own-peer? (ip-put (ip-attr! s1 1 (ip-pfx-bytes lcl)) (lit peer) lcl) s1))
    (def s3 (if (= (ip-get s2 (lit plen)) 0) (ip-put s2 (lit plen) (& (List ref 2 lcl) 255)) s2))
    (def s4 (if (if (< (ip-get s3 (lit brd-len)) 0) (not del?) #f) (%ip-brd-auto f s3) s3))
    (if (if (null? (ip-get s4 (lit scope))) (not del?) #f)
      (ip-put s4 (lit scope) (if (if (= (first lcl) 2) (if (>= (List ref 3 lcl) 1) (= (first (List ref 1 lcl)) 127) #f) #f) 254 0))
      s4)))

(def %ip-brd-auto
  (fn (_ f s)
    (def peer (if (null? (ip-get s (lit peer))) (list 2 (ip-pad16 ()) 0 0) (ip-get s (lit peer))))
    (unless (= (ip-get s (lit family)) 2) (ip-die f "broadcast can be set only for IPv4 addresses"))
    (if (> (List ref 2 peer) 30) s
      (ip-attr! s 4 (%ip-brd-of peer (= (ip-get s (lit brd-len)) -1))))))

; ipaddr_modify: KIND RTM_NEWADDR or RTM_DELADDR, FLAGS the request's
(def ip-modify
  (fn (_ f kind flags ws)
    (def s0 (List fold (fn (_ s kv) (ip-put s (first kv) (rest kv))) ()
                  (list (pair (lit req) (ip-req kind (| 1 flags) 280 8)) (pair (lit family) (ip-get f (lit preferred)))
                        (pair (lit peer) ()) (pair (lit lcl) ()) (pair (lit peer-len) 0) (pair (lit local-len) 0)
                        (pair (lit brd-len) 0) (pair (lit any-len) 0) (pair (lit valid) ()) (pair (lit pref) ())
                        (pair (lit scope) ()) (pair (lit dev) ()) (pair (lit label) ()) (pair (lit flags) 0) (pair (lit plen) 0))))
    (def f1 (ip-put f (lit scopes) (ip-scopes f)))
    (def s1 (let go ((s s0) (ws ws)) (if (null? ws) s (let ((r (%ip-modify-word f1 s ws))) (go (first r) (rest r))))))
    (def s (%ip-modify-finish f1 s1 (= kind 21)))
    (def fd (ip-open f1))
    (ip-init-map f1 fd)
    (def index (ip-dev-index f1 (ip-get s (lit dev))))
    (%ip-modify-send f1 fd s index)))

(def %ip-modify-send
  (fn (_ f fd s index)
    (def valid (if (null? (ip-get s (lit valid))) 4294967295 (ip-get s (lit valid))))
    (def pref (if (null? (ip-get s (lit pref))) 4294967295 (ip-get s (lit pref))))
    (def timed? (not (if (null? (ip-get s (lit valid))) (null? (ip-get s (lit pref))) #f)))
    (match
      ((if timed? (= valid 0) #f) (do (file-write 2 "valid_lft is zero\n") 1))
      ((if timed? (< valid pref) #f) (do (file-write 2 "preferred_lft is greater than valid_lft\n") 1))
      (#t (let ((req (if timed? (%ip-add (ip-get s (lit req)) 6 (append (ip-le pref 4) (ip-le valid 4) (ip-le 0 8)))
                       (ip-get s (lit req))))
                (body (append (list (ip-get s (lit family)) (ip-get s (lit plen)) (if (> (ip-get s (lit flags)) 255) 0 (ip-get s (lit flags)))
                                    (if (null? (ip-get s (lit scope))) 0 (ip-get s (lit scope))))
                              (ip-le index 4))))
            (if (< (ip-talk f fd (ip-req-bytes req body 3) 3) 0) 2 0))))))

; --- ip addr flush ----------------------------------------------------------------

; an address's message with its bytes kept: the parse, then the bytes
(def %ip-addr-raw-of
  (fn (_ p len kind)
    (let ((a (ip-addr-of p len kind))) (if (null? a) () (append a (list (ip-bytes p 0 len)))))))

; rtnl_send_check: BYTES written, then any refusal the kernel has queued; nil
; where there is none, else the errno
(def ip-send-check
  (fn (_ fd bytes)
    (def out (ip-buf bytes))
    (def r (in-call (cu-ptr-call (in-c "write") fd (cu-str->ptr out) (length bytes))))
    (if (< r 0) (Err errno-of r)
      (let ((resp (str-make-raw 1024)))
        (let ((n (in-call (cu-ptr-call (in-c "recv") fd (cu-str->ptr resp) 1024 66))))
          (match ((< n 0) (if (= (Err errno-of n) 11) () (Err errno-of n)))
                 (#t (%ip-peek-error (cu-str->ptr resp) n))))))))

(def %ip-peek-error
  (fn (_ p n)
    (let go ((o 0))
      (let ((len (if (> (+ o 16) n) 0 (cu-ptr-ref p o 4))))
        (match
          ((if (< len 16) #t (> (+ o len) n)) ())
          ((= (cu-ptr-ref p (+ o 4) 2) 2) (- 0 (inet-int32 (cu-ptr-ref p (+ o 16) 4))))
          (#t (go (+ o (ip-align len)))))))))

; the messages that delete those whose bytes MS holds, in batches of busybox's
; 3584 bytes, each a KIND (RTM_DELADDR, RTM_DELROUTE) of its own sequence number
(def ip-flush-batches
  (fn (_ ms kind seq)
    (let go ((ms ms) (seq seq) (batch ()) (used 0) (acc ()))
      (if (null? ms) (reverse (if (null? batch) acc (pair (List flatten (reverse batch)) acc)))
        (let ((m (first ms)))
          (let ((del (append (List take 4 m) (ip-le kind 2) (ip-le 1 2) (ip-le seq 4) (List drop 12 m)
                             (map (fn (_ k) 0) (List range (length m) (ip-align (length m)))))))
            (if (> (+ used (length m)) 3584)
              (go (rest ms) (+ seq 1) (list del) (length del) (pair (List flatten (reverse batch)) acc))
              (go (rest ms) (+ seq 1) (pair del batch) (+ used (length del)) acc))))))))

; the flush's rounds: dump, delete what the filter keeps, until a dump keeps none
(def %ip-flush-round
  (fn (_ f round)
    (def fd (ip-get f (lit fd)))
    (def ms (filter (fn (_ a) (if (= (first a) 20) (ip-addr-shown? f a) #f))
                    (ip-dump f fd 22 (ip-get f (lit family)) (+ 10 round) %ip-addr-raw-of)))
    (if (null? ms) 0
      (let ((bad (List find (fn (_ e) (not (null? e)))
                            (map (fn (_ b) (ip-send-check fd b)) (ip-flush-batches (map (fn (_ a) (List ref 7 a)) ms) 21 (+ 1000 (* round 1000)))))))
        (if (null? bad) (%ip-flush-round f (+ round 1))
          (do (ip-say f (string-append "can't send flush request: " (libc-strerror bad))) 1))))))

(def ip-flush
  (fn (_ f0 ws)
    (when (null? ws) (ip-die f0 "flush requires an argument"))
    (when (= (ip-get f0 (lit preferred)) 17) (ip-die f0 "can't flush link addresses"))
    (let ((f (ip-filter f0 ws)))
      (let ((r (%ip-flush-round f 0))) (do (cu-ptr-call (in-c "close") (ip-get f (lit fd))) r)))))

; --- ip link set ------------------------------------------------------------------

; get_ctl_fd: a datagram socket for the SIOCSIF ioctls
(def %ip-ctl-fd
  (fn (_ f)
    (let ((fd (in-call (cu-ptr-call (in-c "socket") 2 2 0))))
      (if (>= fd 0) fd
        (let ((fd2 (in-call (cu-ptr-call (in-c "socket") 17 2 0))))
          (if (>= fd2 0) fd2
            (let ((fd3 (in-call (cu-ptr-call (in-c "socket") 10 2 0))))
              (if (< fd3 0) (ip-die f (string-append "socket: " (libc-strerror (Err errno-of fd3)))) fd3))))))))

; xioctl: REQ on FD with the ifreq R, the run ended as busybox's ends it where it fails
(def %ip-xioctl
  (fn (_ f fd req r)
    (let ((n (in-call (cu-ptr-call (in-c "ioctl") fd req (cu-str->ptr r)))))
      (when (< n 0)
        (ip-die f (string-concat (list "ioctl 0x" (cvt req cu-string-type 16) " failed: " (libc-strerror (Err errno-of n)))))))))

; an ifreq naming DEV with N bytes of V at 16, set by REQ on a control socket
(def %ip-ifreq-set
  (fn (_ f dev req v n)
    (def fd (%ip-ctl-fd f))
    (def r (if-req dev))
    (inet-set! r 16 v n)
    (%ip-xioctl f fd req r)
    (cu-ptr-call (in-c "close") fd)))

; do_chflags: FLAGS under MASK, set where they differ
(def %ip-chflags
  (fn (_ f dev flags mask)
    (def fd (%ip-ctl-fd f))
    (def r (if-req dev))
    (%ip-xioctl f fd 35091 r)
    (def cur (if-ref r 16 2))
    (unless (= (& (^ cur flags) mask) 0)
      (inet-set! r 16 (| (& cur (^ mask 65535)) (& mask flags)) 2)
      (%ip-xioctl f fd 35092 r))
    (cu-ptr-call (in-c "close") fd)))

; do_changename
(def %ip-rename
  (fn (_ f dev new)
    (def fd (%ip-ctl-fd f))
    (def r (if-req dev))
    (map (fn (_ k) (inet-set! r (+ 16 k) (char->integer (byte-at new k)) 1)) (List range 0 (if (> (byte-len new) 16) 16 (byte-len new))))
    (%ip-xioctl f fd 35107 r)
    (cu-ptr-call (in-c "close") fd)))

; get_address: DEV's hardware type and address length, from a packet socket bound to it
(def %ip-hw-of
  (fn (_ f dev)
    (def fd (in-call (cu-ptr-call (in-c "socket") 17 2 0)))
    (when (< fd 0) (ip-die f (string-append "socket: " (libc-strerror (Err errno-of fd)))))
    (def r (if-req dev))
    (%ip-xioctl f fd 35123 r)
    (def me (inet-zeros 20))
    (inet-set! me 0 17 2)
    (inet-set! me 2 24576 2)
    (inet-set! me 4 (if-ref r 16 4) 4)
    (let ((b (in-call (cu-ptr-call (in-c "bind") fd (cu-str->ptr me) 20))))
      (when (< b 0) (ip-die f (string-append "bind: " (libc-strerror (Err errno-of b))))))
    (def len (inet-zeros 4))
    (inet-set! len 0 20 4)
    (cu-ptr-call (in-c "getsockname") fd (cu-str->ptr me) (cu-str->ptr len))
    (cu-ptr-call (in-c "close") fd)
    (pair (cu-ptr-ref (cu-str->ptr me) 8 2) (cu-ptr-ref (cu-str->ptr me) 11 1))))

; parse_address then set_address: LLA as DEV's hardware address
(def %ip-set-hw
  (fn (_ f dev lla)
    (def hw (%ip-hw-of f dev))
    (def a (%ip-lladdr f lla (if (= (first hw) 1) 14 19)))
    (when (not (pair? a)) (Err raise (lit ip-exit1) "lladdr" ()))
    (unless (= (first a) (rest hw))
      (ip-die f (string-concat (list "wrong address (" (if (>= (dp-find lla 0 #\.) 0) lla (first (Str8 split ":" lla)))
                                      ") length: expected " (cu-int->str (rest hw)) " bytes"))))
    (def r (if-req dev))
    (inet-set! r 16 (first hw) 2)
    (map (fn (_ e) (inet-set! r (+ 18 (first e)) (rest e) 1)) (ip-indexed (rest a)))
    (def fd (%ip-ctl-fd f))
    (%ip-xioctl f fd 35108 r)
    (cu-ptr-call (in-c "close") fd)))

; set_master and set_netns: an RTM_NEWLINK with the one attribute, the run ended where the kernel refuses it
(def %ip-link-attr
  (fn (_ f dev type v)
    (def fd (ip-open f))
    (def index (ip-dev-index f dev))
    (def req (%ip-add (ip-req 16 1 1056 16) type (ip-le v 4)))
    (def body (append (list (ip-get f (lit preferred)) 0) (ip-le 0 2) (ip-le index 4) (ip-le 0 8)))
    (when (< (ip-talk f fd (ip-req-bytes req body 2) 2) 0) (Err raise (lit ip) "talk" ()))
    (cu-ptr-call (in-c "close") fd)))

(def %ip-set-words (list "up" "down" "name" "mtu" "qlen" "multicast" "arp" "promisc" "address" "netns" "master" "nomaster" "dev"))

(def %ip-on-off
  (fn (_ f what arg)
    (match ((string=? arg "on") #t) ((string=? arg "off") #f)
           (#t (ip-die f (string-concat (list "argument of \"" what "\" must be \"on\" or \"off\"")))))))

; an on|off flag: BIT set in S's flags where ON? (or where not, for INVERT?)
(def %ip-flag-word
  (fn (_ s bit on?)
    (ip-put (ip-put s (lit mask) (| (ip-get s (lit mask)) bit)) (lit flags)
             (if on? (| (ip-get s (lit flags)) bit) (& (ip-get s (lit flags)) (^ bit 4294967295))))))

; one of do_set's words at the front of WS: (S . WORDS-LEFT)
(def %ip-set-word
  (fn (_ f s ws)
    (def k0 (ip-keyword %ip-set-words (first ws)))
    (def k (if (< k0 0) 12 k0))
    (match
      ((= k 0) (pair (%ip-flag-word s 1 #t) (rest ws)))
      ((= k 1) (pair (%ip-flag-word s 1 #f) (rest ws)))
      ((if (= k 2) #t (= k 8)) (let ((a (ip-next f ws))) (pair (ip-put s (if (= k 2) (lit name) (lit address)) (first a)) (rest a))))
      ((if (= k 3) #t (= k 4)) (%ip-set-num f s (ip-next f ws) (if (= k 3) "mtu" "qlen") (if (= k 3) (lit mtu) (lit qlen))))
      ((= k 9) (let ((a (ip-next f ws))) (pair (ip-put s (lit netns) (ip-unsigned f (first a) "netns" 4294967295)) (rest a))))
      ((= k 10) (let ((a (ip-next f ws))) (pair (ip-put s (lit master) (ip-dev-index f (first a))) (rest a))))
      ((= k 11) (pair (ip-put s (lit master) 0) (rest ws)))
      ((= k 12) (let ((a (if (= k0 12) (ip-next f ws) ws)))
                  (if (null? (ip-get s (lit dev))) (pair (ip-put s (lit dev) (first a)) (rest a))
                    (ip-die f (string-concat (list "either \"dev\" is duplicate, or \"" (first a) "\" is garbage"))))))
      (#t (%ip-set-flag f s k (ip-next f ws))))))

(def %ip-set-num
  (fn (_ f s a what key)
    (unless (null? (ip-get s key)) (%ip-duparg f what (first a)))
    (pair (ip-put s key (ip-unsigned f (first a) what 4294967295)) (rest a))))

; multicast, arp and promisc: arp on clears NOARP
(def %ip-set-flag
  (fn (_ f s k a)
    (match
      ((= k 5) (pair (%ip-flag-word s 4096 (%ip-on-off f "multicast" (first a))) (rest a)))
      ((= k 6) (pair (%ip-flag-word s 128 (not (%ip-on-off f "arp" (first a)))) (rest a)))
      (#t (pair (%ip-flag-word s 256 (%ip-on-off f "promisc" (first a))) (rest a))))))

; do_set
(def ip-set
  (fn (_ f ws)
    (def s0 (List fold (fn (_ s kv) (ip-put s (first kv) (rest kv))) ()
                  (list (pair (lit dev) ()) (pair (lit mask) 0) (pair (lit flags) 0) (pair (lit qlen) ()) (pair (lit mtu) ())
                        (pair (lit master) ()) (pair (lit netns) ()) (pair (lit address) ()) (pair (lit name) ()))))
    (def s (let go ((s s0) (ws ws)) (if (null? ws) s (let ((r (%ip-set-word f s ws))) (go (first r) (rest r))))))
    (def dev0 (ip-get s (lit dev)))
    (when (null? dev0) (ip-die f "\"dev\" requires an argument"))
    (unless (null? (ip-get s (lit address))) (%ip-set-hw f dev0 (ip-get s (lit address))))
    (def new (ip-get s (lit name)))
    (def dev (if (if (null? new) #t (string=? new dev0)) dev0 (do (%ip-rename f dev0 new) new)))
    (unless (null? (ip-get s (lit qlen))) (%ip-ifreq-set f dev 35139 (ip-get s (lit qlen)) 4))
    (unless (null? (ip-get s (lit mtu))) (%ip-ifreq-set f dev 35106 (ip-get s (lit mtu)) 4))
    (unless (null? (ip-get s (lit master))) (%ip-link-attr f dev 10 (ip-get s (lit master))))
    (unless (null? (ip-get s (lit netns))) (%ip-link-attr f dev 19 (ip-get s (lit netns))))
    (unless (= (ip-get s (lit mask)) 0) (%ip-chflags f dev (ip-get s (lit flags)) (ip-get s (lit mask))))
    0))

; --- ip link add, delete ----------------------------------------------------------

(def %ip-vlan-words (list "id" "protocol" "reorder_hdr" "gvrp" "mvrp" "loose_binding"))

; vlan_parse_opt: the vlan's attributes, ((TYPE . BYTES) ...) in order
(def %ip-vlan-attrs
  (fn (_ f ws)
    (let go ((ws ws) (acc ()) (flags 0) (mask 0))
      (if (null? ws)
        (reverse (if (= mask 0) acc (pair (pair 2 (append (ip-le flags 4) (ip-le mask 4))) acc)))
        (let ((k (ip-keyword %ip-vlan-words (first ws))))
          (let ((a (if (< k 0) (ip-invarg f (first ws) "type vlan") (ip-next f ws))))
            (match
              ((= k 0) (go (rest a) (pair (pair 1 (ip-le (ip-unsigned f (first a) "id" 65535) 2)) acc) flags mask))
              ((= k 1) (go (rest a) (pair (pair 5 (%ip-vlan-proto f (first a))) acc) flags mask))
              (#t (let ((bit (cu-nth (- k 2) (list 1 2 8 4))))
                    (go (rest a) acc
                        (if (%ip-on-off f (cu-nth k %ip-vlan-words) (first a)) (| flags bit) (& flags (^ bit 4294967295)))
                        (| mask bit)))))))))))

; the protocol's bytes, network order, from its name lowercased
(def %ip-vlan-proto
  (fn (_ f arg)
    (def low (Str8 downcase arg))
    (def k (ip-keyword (list "802.1q" "802.1ad") low))
    (match ((= k 0) (list 129 0)) ((= k 1) (list 136 168))
           (#t (ip-die f (string-concat (list "unknown VLAN encapsulation protocol '" low "'")))))))

; vrf_parse_opt: the table, the one word it reads
(def %ip-vrf-attrs
  (fn (_ f ws)
    (unless (string=? (first ws) "table") (ip-invarg f (first ws) "type vrf"))
    (let ((a (ip-next f ws))) (list (pair 1 (ip-le (ip-unsigned f (first a) "table" 4294967295) 4))))))

; IFLA_LINKINFO: the kind, and the kind's own words as IFLA_INFO_DATA
(def %ip-linkinfo
  (fn (_ f type ws)
    (def data (match ((null? ws) ())
                     ((string=? type "vlan") (%ip-vlan-attrs f ws))
                     ((string=? type "vrf") (%ip-vrf-attrs f ws))
                     (#t ())))
    (append (ip-rta 1 (%ip-str-bytes type))
            (if (null? ws) () (ip-rta 2 (List flatten (map (fn (_ e) (ip-rta (first e) (rest e))) data)))))))

(def %ip-add-words (list "link" "name" "type" "dev" "address"))

; do_add_or_delete's words: (S . TYPE-WORDS), the words after "type TYPE" left for the type
(def %ip-add-read
  (fn (_ f ws)
    (let go ((ws ws) (s (list (pair (lit link) ()) (pair (lit name) ()) (pair (lit type) ()) (pair (lit dev) ()) (pair (lit address) ()))))
      (if (null? ws) (pair s ())
        (let ((k (ip-keyword %ip-add-words (first ws))))
          (match
            ((= k 2) (let ((a (ip-next f ws))) (pair (ip-put s (lit type) (first a)) (rest a))))
            ((if (= k 0) #t (if (= k 1) #t (= k 4)))
              (let ((a (ip-next f ws))) (go (rest a) (ip-put s (cu-nth k (list (lit link) (lit name) () () (lit address))) (first a)))))
            (#t (let ((a (if (= k 3)
                           (do (unless (null? (ip-get s (lit dev))) (%ip-duparg f (first ws) "dev")) (ip-next f ws))
                           ws)))
                  (go (rest a) (ip-put s (lit dev) (first a)))))))))))

; do_add_or_delete: KIND RTM_NEWLINK or RTM_DELLINK
(def ip-add-link
  (fn (_ f ws kind)
    (def r (%ip-add-read f ws))
    (def s (first r))
    (def fd (ip-open f))
    (ip-init-map f fd)
    (def type (ip-get s (lit type)))
    (def req0 (ip-req kind (if (= kind 16) 1537 1) 1056 16))
    (def req1 (if (null? type) req0 (%ip-add req0 18 (%ip-linkinfo f type (rest r)))))
    (def dev (if (null? (ip-get s (lit dev))) (ip-get s (lit name)) (ip-get s (lit dev))))
    (def name (if (null? (ip-get s (lit name))) dev (ip-get s (lit name))))
    (if (if (= kind 17) (null? dev) #f) 1
      (%ip-add-send f fd s kind req1 dev name))))

(def %ip-add-send
  (fn (_ f fd s kind req1 dev name)
    (def index (if (= kind 17) (ip-dev-index f dev) 0))
    (def link (ip-get s (lit link)))
    (def req2 (if (if (= kind 16) (not (null? link)) #f) (%ip-add req1 5 (ip-le (ip-dev-index f link) 4)) req1))
    (def addr (if (if (= kind 16) (not (null? (ip-get s (lit address)))) #f) (%ip-lladdr f (ip-get s (lit address)) 32) ()))
    (if (if (null? addr) #f (not (pair? addr))) 255
      (let ((req3 (if (null? addr) req2 (%ip-add req2 1 (List take (first addr) (append (rest addr) (map (fn (_ k) 0) (List range 0 33))))))))
        (unless (if (null? name) #t (if (>= (byte-len name) 1) (<= (byte-len name) 15) #f)) (ip-invarg f name "name"))
        (let ((req (if (null? name) req3 (%ip-add req3 3 (append (%ip-str-bytes name) (list 0)))))
              (body (append (list (ip-get f (lit preferred)) 0) (ip-le 0 2) (ip-le index 4) (ip-le 0 8))))
          (if (< (ip-talk f fd (ip-req-bytes req body 2) 2) 0) 2 0))))))

(provide cu/ipset ip-add-link ip-address ip-attr! ip-buf ip-family! ip-flush
  ip-flush-batches ip-init-map ip-le ip-modify ip-pfx-bytes ip-prefix-in
  ip-req ip-req-bytes ip-rta ip-send-check ip-set ip-strtoul ip-talk
  ip-unsigned)

; # x-coreutils -- the small tools, as applets
;
; ## cu/ipneigh.x -- ip neigh and ipneigh: the kernel's neighbour tables, over netlink
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox 1.36's networking/libiproute/ipneigh.c.  `ip neigh show` dumps
; RTM_GETNEIGH and prints each entry the filter keeps -- dev, nud STATE (all,
; or one of the states by a unique prefix) and to PREFIX -- with its
; link-layer address, router and proxy, its reference count, the ages it
; was used, confirmed and updated, its probes, and its states.  `flush`
; prints and deletes those entries, a round at a time, until a round finds
; none, or gives up after ten.

(module cu/ipneigh)

(import cu/inet inet-int32)
(import cu/inetd in-call)
(import cu/ip ip-align ip-attr ip-attrs ip-bytes ip-dev-index ip-die ip-dump
  ip-dump-read ip-get ip-index-name ip-invarg ip-keyword ip-ll-addr ip-match?
  ip-next ip-ntoa ip-num ip-open ip-pad16 ip-put ip-run ip-say ip-some)
(import cu/iproute ip-hz)
(import cu/ipset ip-buf ip-flush-batches ip-init-map ip-le ip-prefix-in
  ip-send-check)
(import cu/prims append cal/ cu-int->str cu-libc-sym cu-nth cu-ptr-call
  cu-ptr-ref cu-str->ptr file-write filter length libc-strerror map reverse
  string-append string-concat string=?)

(def %ip-n-states
  (list (pair 1 "INCOMPLETE") (pair 2 "REACHABLE") (pair 4 "STALE") (pair 8 "DELAY")
        (pair 16 "PROBE") (pair 32 "FAILED") (pair 64 "NOARP") (pair 128 "PERMANENT")))

; nud_state_a2n: the state a word names by a unique prefix, or the run ended
(def %ip-n-nud
  (fn (_ f arg)
    (def k (ip-keyword (list "permanent" "reachable" "noarp" "none" "stale" "incomplete" "delay" "probe" "failed") arg))
    (if (< k 0) (ip-invarg f arg "nud state") (cu-nth k (list 128 2 64 0 4 1 8 16 32)))))

; NDA_DST LLADDR CACHEINFO PROBES
(def %ip-n-want (list 1 2 3 4))

; a neighbour's message at P of LEN bytes: (KIND FAMILY INDEX STATE FLAGS ATTRS BYTES), or nil
(def %ip-n-of
  (fn (_ p len kind)
    (if (if (if (= kind 28) #t (= kind 29)) (>= len 28) #f)
      (list kind (cu-ptr-ref p 16 1) (inet-int32 (cu-ptr-ref p 20 4)) (cu-ptr-ref p 24 2) (cu-ptr-ref p 26 1)
            (ip-attrs p 28 len %ip-n-want) (ip-bytes p 0 len))
      ())))

(def %ip-n-family (fn (_ n) (cu-nth 1 n)))
(def %ip-n-index (fn (_ n) (cu-nth 2 n)))
(def %ip-n-state (fn (_ n) (cu-nth 3 n)))
(def %ip-n-flags (fn (_ n) (cu-nth 4 n)))
(def %ip-n-attr (fn (_ n type) (ip-attr (cu-nth 5 n) type)))

; print_neigh's filter: the family, the device, a state the filter asks
; for (a proxy entry, a stateless one where "none" was asked, and DECnet's
; always), and the prefix
(def %ip-n-kept?
  (fn (_ f n)
    (def state (ip-get f (lit state)))
    (def index (ip-get f (lit index)))
    (def pfx (ip-get f (lit pfx)))
    (def dst (%ip-n-attr n 1))
    (match
      ((if (= (ip-get f (lit family)) 0) #f (not (= (ip-get f (lit family)) (%ip-n-family n)))) #f)
      ((if (= index 0) #f (not (= index (%ip-n-index n)))) #f)
      ((if (= (& state (%ip-n-state n)) 0)
         (if (= (& (%ip-n-flags n) 8) 0)
           (if (if (= (%ip-n-state n) 0) (= (& state 256) 0) #t) (not (= (%ip-n-family n) 12)) #f) #f) #f) #f)
      ((if (null? dst) #t (= (first pfx) 0)) #t)
      (#t (ip-match? (ip-pad16 (rest dst)) (List ref 1 pfx) (List ref 2 pfx))))))

; the cache info: the reference count and the ages, in the clock's seconds
(def %ip-n-cache
  (fn (_ b)
    (def hz (ip-hz))
    (def field (fn (_ at) (ip-num (List take 4 (List drop at b)))))
    (def age (fn (_ at) (cu-int->str (inet-int32 (cal/ (field at) hz)))))
    (string-concat
      (list (if (= (field 12) 0) "" (string-append " ref " (cu-int->str (inet-int32 (field 12)))))
            " used " (age 4) "/" (age 0) "/" (age 8)))))

; print_neigh's line for N
(def %ip-n-text
  (fn (_ f n)
    (def state (%ip-n-state n))
    (def on (filter (fn (_ e) (not (= (& state (first e)) 0))) %ip-n-states))
    (string-concat
      (list (ip-some (cu-nth 5 n) 1 (fn (_ b) (string-append (ip-ntoa (%ip-n-family n) b) " ")))
            (if (if (= (ip-get f (lit index)) 0) (not (= (%ip-n-index n) 0)) #f)
              (string-concat (list "dev " (ip-index-name f (%ip-n-index n)) " ")) "")
            (ip-some (cu-nth 5 n) 2 (fn (_ b) (string-append "lladdr " (ip-ll-addr b 1))))
            (if (= (& (%ip-n-flags n) 128) 0) "" " router")
            (if (= (& (%ip-n-flags n) 8) 0) "" " proxy")
            (ip-some (cu-nth 5 n) 3 %ip-n-cache)
            (ip-some (cu-nth 5 n) 4 (fn (_ b) (string-append " probes " (cu-int->str (ip-num b)))))
            (if (null? on) "" (string-append " " (Str8 join "," (map rest on))))
            "\n"))))

; one of the listing's words at the front of WS: (F . WORDS-LEFT)
(def %ip-n-word
  (fn (_ f flush? ws)
    (def k (ip-keyword (list "to" "dev" "nud") (first ws)))
    (match
      ((= k 1) (let ((a (ip-next f ws))) (pair (ip-put f (lit dev) (first a)) (rest a))))
      ((= k 2) (let ((a (ip-next f ws)))
                 (let ((f1 (if (ip-get f (lit given)) f (ip-put (ip-put f (lit state) 0) (lit given) #t)))
                       (s (if (string=? (first a) "all") (if flush? (^ 64 4294967295) 4294967295) (%ip-n-nud f (first a)))))
                   (pair (ip-put f1 (lit state) (| (ip-get f1 (lit state)) (if (= s 0) 256 s))) (rest a)))))
      (#t (let ((a (if (= k 0) (ip-next f ws) ws)))
            (let ((p (ip-prefix-in f (first a) (ip-get f (lit family)))))
              (pair (ip-put (ip-put f (lit pfx) p) (lit family) (if (= (ip-get f (lit family)) 0) (first p) (ip-get f (lit family))))
                    (rest a))))))))

; ipneigh_list_or_flush up to its dump: the filter read, the socket open, the
; links mapped and dev found
(def %ip-n-filter
  (fn (_ f0 flush? ws)
    (def f1 (List fold (fn (_ f kv) (ip-put f (first kv) (rest kv))) f0
                  (list (pair (lit family) (ip-get f0 (lit preferred))) (pair (lit index) 0) (pair (lit dev) ())
                        (pair (lit given) #f) (pair (lit pfx) (list 0 (ip-pad16 ()) 0 0))
                        (pair (lit state) (if flush? (^ 192 4294967295) 191)))))
    (def f2 (let go ((f f1) (ws ws)) (if (null? ws) f (let ((r (%ip-n-word f flush? ws))) (go (first r) (rest r))))))
    (def fd (ip-open f2))
    (def f3 (ip-put (ip-put f2 (lit links) (ip-init-map f2 fd)) (lit fd) fd))
    (if (null? (ip-get f3 (lit dev))) f3 (ip-put f3 (lit index) (ip-dev-index f3 (ip-get f3 (lit dev)))))))

; rtnl_dump_request with an ndmsg for the family, then the dump
(def %ip-n-dump
  (fn (_ f fd seq)
    (def req (append (ip-le 28 4) (ip-le 30 2) (ip-le 769 2) (ip-le seq 4) (ip-le 0 4)
                     (list (ip-get f (lit family)) 0 0 0) (ip-le 0 8)))
    (let ((r (in-call (cu-ptr-call (cu-libc-sym "write") fd (cu-str->ptr (ip-buf req)) 28))))
      (when (< r 0) (ip-die f (string-append "can't send dump request: " (libc-strerror (Err errno-of r))))))
    (ip-dump-read f fd seq %ip-n-of)))

(def %ip-n-list
  (fn (_ f0 ws)
    (def f (%ip-n-filter f0 #f ws))
    (map (fn (_ n) (when (%ip-n-kept? f n) (file-write 1 (%ip-n-text f n)))) (%ip-n-dump f (ip-get f (lit fd)) 2))
    0))

; the kept entries in busybox's batches of 3584 bytes: ((ENTRY ...) ...)
(def %ip-n-batches
  (fn (_ ns)
    (let go ((ns ns) (batch ()) (used 0) (acc ()))
      (if (null? ns) (reverse (if (null? batch) acc (pair (reverse batch) acc)))
        (let ((len (length (cu-nth 6 (first ns)))))
          (if (> (+ used len) 3584)
            (go (rest ns) (list (first ns)) (ip-align len) (pair (reverse batch) acc))
            (go (rest ns) (pair (first ns) batch) (+ used (ip-align len)) acc)))))))

; one round of the flush: each batch printed then sent; the count deleted,
; or -1 where the last batch was refused
(def %ip-n-round
  (fn (_ f round)
    (def fd (ip-get f (lit fd)))
    (def ns (filter (fn (_ n) (if (= (first n) 28) (%ip-n-kept? f n) #f)) (ip-dump f fd 30 (ip-get f (lit family)) (+ 10 round) %ip-n-of)))
    (let go ((bs (%ip-n-batches ns)))
      (if (null? bs) (length ns)
        (do (map (fn (_ n) (file-write 1 (%ip-n-text f n))) (first bs))
            (let ((bad (ip-send-check fd (first (ip-flush-batches (map (fn (_ n) (cu-nth 6 n)) (first bs)) 29 (+ 1000 (* round 1000)))))))
              (match
                ((null? bad) (go (rest bs)))
                ((null? (rest bs)) (do (ip-say f (string-append "can't send flush request: " (libc-strerror bad))) -1))
                (#t (do (ip-say f (string-append "can't send flush request: " (libc-strerror bad))) (ip-die f "dump terminated"))))))))))

(def %ip-n-flush
  (fn (_ f0 ws)
    (when (null? ws) (ip-die f0 "\"ip neigh flush\" requires an argument"))
    (def f1 (%ip-n-filter f0 #t ws))
    (def f (ip-put f1 (lit state) (& (ip-get f1 (lit state)) (^ 32 4294967295))))
    (let go ((round 0))
      (if (>= round 10) (ip-die f "*** Flush not complete bailing out after 10 rounds")
        (let ((n (%ip-n-round f round)))
          (match
            ((< n 0) 1)
            ((= n 0) (do (file-write 1 (if (= round 0) "Nothing to flush\n"
                                         (string-concat (list "*** Flush is complete after " (cu-int->str round) " round(s) ***\n"))))
                         0))
            (#t (do (file-write 1 (string-concat (list "\n*** Round " (cu-int->str (+ round 1)) ", deleting " (cu-int->str n) " entries ***\n")))
                    (go (+ round 1))))))))))

; do_ipneigh
(def ip-neigh
  (fn (_ f ws)
    (def k (if (null? ws) 0 (ip-keyword (list "show" "flush") (first ws))))
    (match
      ((null? ws) (%ip-n-list f ()))
      ((= k 0) (%ip-n-list f (rest ws)))
      ((= k 1) (%ip-n-flush f (rest ws)))
      (#t (ip-invarg f (first ws) (ip-get f (lit name)))))))

(def cu-ipneigh (fn (_ argv stdin-thunk) (ip-run "ipneigh" argv ip-neigh)))

(provide cu/ipneigh cu-ipneigh ip-neigh)

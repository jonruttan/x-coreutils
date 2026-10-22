; # x-coreutils -- the small tools, as applets
;
; ## cu/iproute.x -- ip route and iproute: the kernel's routes, over netlink
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox 1.36's networking/libiproute/iproute.c, as alpine ships it.
; `ip route list|show` dumps
; RTM_GETROUTE and prints each route print_route keeps -- by table (main
; unless table names another, all or cache), scope, to and from (root,
; match, exact), dev and via; `flush` sends those routes back as
; RTM_DELROUTE until a dump keeps none (table cache writes
; /proc/sys/net/ipv4/route/flush); add, append, change, delete, prepend,
; replace and test build an RTM_NEWROUTE or RTM_DELROUTE from the route's
; words (a type, the destination, via, src, dev, metric, mtu and advmss
; with lock, scope, protocol, table, onlink); `get` asks the kernel which
; route it takes to an address, and with `connected` asks again from the
; source that route gives.  Protocols and tables are named from
; /etc/iproute2/rt_protos and rt_tables over busybox's own names.

; --- names ------------------------------------------------------------------------

(def %ip-protos
  (fn (_ f)
    (%ip-names f "protos" (list (pair 0 "none") (pair 1 "redirect") (pair 2 "kernel") (pair 3 "boot") (pair 4 "static")
                                (pair 8 "gated") (pair 9 "ra") (pair 10 "mrt") (pair 11 "zebra") (pair 12 "bird")))))

(def %ip-tables
  (fn (_ f) (%ip-names f "tables" (list (pair 0 "unspec") (pair 255 "local") (pair 254 "main") (pair 253 "default")))))

; the route types, by RTN number
(def %ip-rtn-names
  (list "none" "unicast" "local" "broadcast" "anycast" "multicast" "blackhole" "unreachable" "prohibit" "throw" "nat" "xresolve"))

; rtnl_rtntype_n2a
(def %ip-rtn-name
  (fn (_ type) (if (< type 12) (cu-nth type %ip-rtn-names) (cu-int->str type))))

; rtnl_rtntype_a2n: the type a word names, by a unique prefix, else its
; number up to 255, else nil
(def %ip-rtn-id
  (fn (_ arg)
    (def k (%ip-keyword (list "local" "nat" "broadcast" "brd" "anycast" "multicast" "prohibit" "unreachable" "blackhole" "xresolve" "unicast" "throw") arg))
    (if (>= k 0) (cu-nth k (list 2 10 3 3 4 5 8 7 6 11 1 9))
      (let ((n (if (= (byte-len arg) 0) () (%ip-strtoul arg 255)))) n))))

; get_hz: the clock /proc/net/psched gives, else the C library's ticks a second
(def %ip-hz
  (fn (_)
    (def text (file-or-err (fn (_) (file-read-unsized "/proc/net/psched"))))
    (def ws (if (Err err? text) () (%inet-words (first (cu-lines text)))))
    (if (if (>= (length ws) 4) (= (%inet-hex (List ref 2 ws)) 1000000) #f) (%inet-hex (List ref 3 ws))
      (%in-call (cu-ptr-call (%in-c "sysconf") 2)))))

; --- the routes -------------------------------------------------------------------

; RTA_DST SRC IIF OIF GATEWAY PRIORITY PREFSRC CACHEINFO TABLE
(def %ip-route-want (list 1 2 3 4 5 6 7 12 15))

; a route's message at P of LEN bytes: (KIND FAMILY DST-LEN SRC-LEN TOS TABLE
; PROTOCOL SCOPE TYPE FLAGS ATTRS BYTES), or nil
(def %ip-route-of
  (fn (_ p len kind)
    (if (if (if (= kind 24) #t (= kind 25)) (>= len 28) #f)
      (list kind (cu-ptr-ref p 16 1) (cu-ptr-ref p 17 1) (cu-ptr-ref p 18 1) (cu-ptr-ref p 19 1)
            (cu-ptr-ref p 20 1) (cu-ptr-ref p 21 1) (cu-ptr-ref p 22 1) (cu-ptr-ref p 23 1) (cu-ptr-ref p 24 4)
            (%ip-attrs p 28 len %ip-route-want) (%ip-bytes p 0 len))
      ())))

(def %ip-r-family (fn (_ r) (cu-nth 1 r)))
(def %ip-r-dst-len (fn (_ r) (cu-nth 2 r)))
(def %ip-r-src-len (fn (_ r) (cu-nth 3 r)))
(def %ip-r-scope (fn (_ r) (cu-nth 7 r)))
(def %ip-r-type (fn (_ r) (cu-nth 8 r)))
(def %ip-r-flags (fn (_ r) (cu-nth 9 r)))
(def %ip-r-attr (fn (_ r type) (%ip-attr (cu-nth 10 r) type)))

; the route's table: RTA_TABLE's, else rtm_table
(def %ip-r-table
  (fn (_ r) (let ((e (%ip-r-attr r 15))) (if (null? e) (cu-nth 5 r) (%ip-num (rest e))))))

(def %ip-host-len
  (fn (_ family) (match ((= family 10) 128) ((= family 2) 32) (#t -1))))

(def %ip-cloned? (fn (_ r) (not (= (& (%ip-r-flags r) 512) 0))))

; the table filter, as busybox 1.36's: IPv6's cache only for table cache,
; its local table the local routes, main the rest, any other table none;
; IPv4's by table where one is named
(def %ip-table-ok?
  (fn (_ f r)
    (def tb (%ip-get f (lit tb)))
    (match
      ((not (= (%ip-r-family r) 10)) (if (> tb 0) (= tb (%ip-r-table r)) #t))
      ((= tb 0) #t)
      ((< tb 0) (%ip-cloned? r))
      ((%ip-cloned? r) #f)
      ((= tb 255) (= (%ip-r-type r) 2))
      ((= tb 254) (not (= (%ip-r-type r) 2)))
      (#t #f))))

; the root filter of one end: RT the prefix, LEN the route's length at that
; end, BYTES its address or zeros; a root holds the routes inside it
(def %ip-root-ok?
  (fn (_ r rt len bytes)
    (match
      ((= (first rt) 0) #t)
      ((not (= (%ip-r-family r) (first rt))) #f)
      ((> (List ref 2 rt) len) #f)
      (#t (%ip-match? bytes (List ref 1 rt) (List ref 2 rt))))))

; the match filter of one end: MT the prefix; a match holds the routes it lies inside
(def %ip-match-ok?
  (fn (_ r mt len bytes)
    (match
      ((= (first mt) 0) #t)
      ((not (= (%ip-r-family r) (first mt))) #f)
      ((< (List ref 2 mt) 0) #t)
      ((< (List ref 2 mt) len) #f)
      (#t (%ip-match? bytes (List ref 1 mt) len)))))

; the root and match filters of one end
(def %ip-ends-ok?
  (fn (_ r rt mt len bytes) (if (%ip-root-ok? r rt len bytes) (%ip-match-ok? r mt len bytes) #f)))

; an end's address as print_route copies it: its bytes, else zeros
(def %ip-end-bytes
  (fn (_ r type) (let ((e (%ip-r-attr r type))) (%ip-pad16 (if (null? e) () (rest e))))))

; print_route's filter
(def %ip-route-kept?
  (fn (_ f r)
    (def oif (%ip-get f (lit oif)))
    (def o (%ip-r-attr r 4))
    (match
      ((not (%ip-table-ok? f r)) #f)
      ((not (= (& (^ (%ip-get f (lit scope)) (%ip-r-scope r)) (%ip-get f (lit scopemask))) 0)) #f)
      ((not (%ip-ends-ok? r (%ip-get f (lit rdst)) (%ip-get f (lit mdst)) (%ip-r-dst-len r) (%ip-end-bytes r 1))) #f)
      ((not (%ip-ends-ok? r (%ip-get f (lit rsrc)) (%ip-get f (lit msrc)) (%ip-r-src-len r) (%ip-end-bytes r 2))) #f)
      ((= oif 0) #t)
      ((null? o) #f)
      (#t (= oif (%inet-int32 (%ip-num (rest o))))))))

; an end of the route: "ADDR/LEN ", "ADDR " at the host length, or NONE where it has no address
(def %ip-route-end
  (fn (_ r type len none)
    (def e (%ip-r-attr r type))
    (def family (%ip-r-family r))
    (match
      ((null? e) none)
      ((= len (%ip-host-len family)) (string-append (%ip-ntoa family (rest e)) " "))
      (#t (string-concat (list (%ip-ntoa family (rest e)) "/" (cu-int->str len) " "))))))

(def %ip-route-flag-words
  (fn (_ flags)
    (string-concat (map (fn (_ e) (if (= (& flags (first e)) 0) "" (rest e)))
                        (list (pair 1 "dead ") (pair 4 "onlink ") (pair 2 "pervasive ") (pair 256 "notify "))))))

; IPv6's cache line and cache info, as busybox 1.36 prints them: "cache"
; for a cloned route, its expiry, and its error
(def %ip-route-cache
  (fn (_ f r)
    (def ci (%ip-r-attr r 12))
    (def field (fn (_ at) (if (null? ci) 0 (%ip-num (List take 4 (List drop at (rest ci)))))))
    (def expires (field 8))
    (def err (if (= (field 12) 0) "" (string-append " error " (cu-int->str (%inet-int32 (field 12))))))
    (match
      ((not (= (%ip-r-family r) 10)) "")
      ((if (%ip-cloned? r) #t (not (= expires 0)))
        (string-concat (list (if (%ip-cloned? r) (string-append (%ip-sl f) "    cache ") "")
                             (if (= expires 0) "" (string-concat (list " expires " (cu-int->str (%inet-int32 (%cal/ expires (%ip-hz)))) "sec")))
                             err)))
      (#t err))))

; print_route's line for R
(def %ip-route-text
  (fn (_ f r)
    (def family (%ip-r-family r))
    (def host (%ip-host-len family))
    (def tid (%ip-r-table r))
    (def dst-len (%ip-r-dst-len r))
    (def src-len (%ip-r-src-len r))
    (string-concat
      (list (if (= (first r) 25) "Deleted " "")
            (if (= (%ip-r-type r) 1) "" (string-append (%ip-rtn-name (%ip-r-type r)) " "))
            (%ip-route-end r 1 dst-len (if (= dst-len 0) "default " (string-concat (list "0/" (cu-int->str dst-len) " "))))
            (%ip-route-end-from r src-len)
            (if (if (null? (%ip-r-attr r 5)) #f (not (= (List ref 2 (%ip-get f (lit rvia))) host)))
              (string-concat (list "via " (%ip-ntoa family (rest (%ip-r-attr r 5))) " ")) "")
            (%ip-some (cu-nth 10 r) 4 (fn (_ b) (string-concat (list "dev " (%ip-index-name f (%inet-int32 (%ip-num b))) " "))))
            (if (if (= tid 0) #f (if (= tid 254) #f (= (%ip-get f (lit tb)) 0)))
              (string-concat (list "table " (%ip-name (%ip-tables f) tid) " ")) "")
            (if (if (%ip-cloned? r) #f (if (= (%ip-r-scope r) 0) #f (not (= (%ip-get f (lit scopemask)) 4294967295))))
              (string-concat (list "scope " (%ip-scope-name f (%ip-r-scope r)) " ")) "")
            (%ip-some (cu-nth 10 r) 7 (fn (_ b) (string-concat (list " src " (%ip-ntoa family b) " "))))
            (%ip-some (cu-nth 10 r) 6 (fn (_ b) (string-concat (list " metric " (cu-int->str (%inet-int32 (%ip-num b))) " "))))
            (%ip-route-flag-words (%ip-r-flags r))
            (%ip-route-cache f r)
            (if (= (%ip-get f (lit iif)) 0)
              (%ip-some (cu-nth 10 r) 3 (fn (_ b) (string-append " iif " (%ip-index-name f (%inet-int32 (%ip-num b)))))) "")
            "\n"))))

(def %ip-route-end-from
  (fn (_ r src-len)
    (let ((s (%ip-route-end r 2 src-len "")))
      (match ((not (string=? s "")) (string-append "from " s))
             ((= src-len 0) "")
             (#t (string-concat (list "from 0/" (cu-int->str src-len) " ")))))))

; --- list and flush ---------------------------------------------------------------

(def %ip-route-words (list "protocol" "dev" "oif" "iif" "via" "table" "cache" "from" "to" "scope" "all" "root" "match" "exact" "main"))

(def %ip-no-prefix (list 0 (%ip-pad16 ()) 0 0))
(def %ip-no-match (list 0 (%ip-pad16 ()) -1 0))

; a prefix for the filter: get_prefix with the family the options asked
(def %ip-route-pfx
  (fn (_ f arg) (%ip-prefix-in f arg (%ip-get f (lit preferred)))))

; "from" or "to": root PREFIX, match PREFIX, exact PREFIX or PREFIX, onto the keys RT and MT
(def %ip-route-end-word
  (fn (_ f s a rt mt k)
    (match
      ((= k 11) (let ((b (%ip-next f a))) (pair (%ip-put s rt (%ip-route-pfx f (first b))) (rest b))))
      ((= k 12) (let ((b (%ip-next f a))) (pair (%ip-put s mt (%ip-route-pfx f (first b))) (rest b))))
      (#t (let ((b (if (= k 13) (%ip-next f a) a)))
            (let ((p (%ip-route-pfx f (first b)))) (pair (%ip-put (%ip-put s mt p) rt p) (rest b))))))))

; one of the listing's words at the front of WS: (S . WORDS-LEFT)
(def %ip-route-list-word
  (fn (_ f s ws)
    (def k (%ip-keyword %ip-route-words (first ws)))
    (match
      ((= k 0) (let ((a (%ip-next f ws)))
                 (if (if (null? (%ip-id (%ip-protos f) (first a))) (not (string=? (first a) "all")) #f)
                   (%ip-invarg f (first a) "protocol") (pair s (rest a)))))
      ((if (= k 1) #t (= k 2)) (let ((a (%ip-next f ws))) (pair (%ip-put s (lit od) (first a)) (rest a))))
      ((= k 3) (let ((a (%ip-next f ws))) (pair (%ip-put s (lit id) (first a)) (rest a))))
      ((= k 4) (let ((a (%ip-next f ws))) (pair (%ip-put s (lit rvia) (%ip-route-pfx f (first a))) (rest a))))
      ((= k 5) (%ip-route-table-word f s (%ip-next f ws)))
      ((= k 6) (pair (%ip-put s (lit tb) -1) (rest ws)))
      ((= k 7) (let ((a (%ip-next f ws))) (%ip-route-end-word f s a (lit rsrc) (lit msrc) (%ip-keyword %ip-route-words (first a)))))
      ((= k 9) (%ip-route-scope-word f s (%ip-next f ws)))
      ((= k 8) (let ((a (%ip-next f ws))) (%ip-route-end-word f s a (lit rdst) (lit mdst) (%ip-keyword %ip-route-words (first a)))))
      (#t (%ip-route-end-word f s ws (lit rdst) (lit mdst) k)))))

(def %ip-route-table-word
  (fn (_ f s a)
    (def k (%ip-keyword %ip-route-words (first a)))
    (match
      ((= k 6) (pair (%ip-put s (lit tb) -1) (rest a)))
      ((= k 10) (pair (%ip-put s (lit tb) 0) (rest a)))
      ((= k 14) (pair s (rest a)))
      (#t (let ((id (%ip-id (%ip-tables f) (first a))))
            (if (null? id) (%ip-invarg f (first a) "table") (pair (%ip-put s (lit tb) id) (rest a))))))))

(def %ip-route-scope-word
  (fn (_ f s a)
    (let ((id (%ip-scope-id f (first a))))
      (match
        ((not (null? id)) (pair (%ip-put (%ip-put s (lit scope) id) (lit scopemask) 4294967295) (rest a)))
        ((string=? (first a) "all") (pair (%ip-put (%ip-put s (lit scope) 255) (lit scopemask) 0) (rest a)))
        (#t (%ip-invarg f (first a) "scope"))))))

; iproute_list_or_flush up to its dump: the filter read, the socket open, the
; links mapped, dev and iif found
(def %ip-route-filter
  (fn (_ f0 ws)
    (def f1 (List fold (fn (_ f kv) (%ip-put f (first kv) (rest kv))) (%ip-put f0 (lit scopes) (%ip-scopes f0))
                  (list (pair (lit tb) 254) (pair (lit scope) 0) (pair (lit scopemask) 0) (pair (lit iif) 0) (pair (lit oif) 0)
                        (pair (lit od) ()) (pair (lit id) ()) (pair (lit rvia) %ip-no-prefix) (pair (lit rdst) %ip-no-prefix)
                        (pair (lit mdst) %ip-no-match) (pair (lit rsrc) %ip-no-prefix) (pair (lit msrc) %ip-no-match))))
    (def f2 (let go ((s f1) (ws ws)) (if (null? ws) s (let ((r (%ip-route-list-word f1 s ws))) (go (first r) (rest r))))))
    (def family (if (if (= (%ip-get f2 (lit preferred)) 0) (not (= (%ip-get f2 (lit tb)) 0)) #f) 2 (%ip-get f2 (lit preferred))))
    (def fd (%ip-open f2))
    (def links (%ip-init-map f2 fd))
    (def f3 (%ip-put (%ip-put (%ip-put f2 (lit links) links) (lit fd) fd) (lit dump-family) family))
    (def id (%ip-get f3 (lit id)))
    (def od (%ip-get f3 (lit od)))
    (def f4 (if (null? id) f3 (%ip-put f3 (lit iif) (%ip-dev-index f3 id))))
    (if (null? od) f4 (%ip-put f4 (lit oif) (%ip-dev-index f4 od)))))

; rtnl_rtcache_request: a dump of the cloned routes
(def %ip-cache-dump
  (fn (_ f fd family seq)
    (def req (append (%ip-le 28 4) (%ip-le 26 2) (%ip-le 257 2) (%ip-le seq 4) (%ip-le 0 4)
                     (list family 0 0 0 0 0 0 0) (%ip-le 512 4)))
    (let ((out (%ip-buf req)))
      (let ((r (%in-call (cu-ptr-call (%in-c "write") fd (cu-str->ptr out) 28))))
        (when (< r 0) (%ip-die f (string-append "sendto: " (libc-strerror (Err errno-of r)))))))
    (%ip-dump-read f fd seq %ip-route-of)))

(def %ip-route-list
  (fn (_ f0 ws)
    (def f (%ip-route-filter f0 ws))
    (def fd (%ip-get f (lit fd)))
    (def routes (if (= (%ip-get f (lit tb)) -1) (%ip-cache-dump f fd (%ip-get f (lit dump-family)) 2)
                  (%ip-dump f fd 26 (%ip-get f (lit dump-family)) 2 %ip-route-of)))
    (map (fn (_ r) (when (%ip-route-kept? f r) (file-write 1 (%ip-route-text f r)))) routes)
    (cu-ptr-call (%in-c "close") fd)
    0))

; iproute_flush_cache
(def %ip-flush-cache
  (fn (_ f)
    (def path "/proc/sys/net/ipv4/route/flush")
    (def fd (%in-call (cu-ptr-call (%in-c "open") path 1)))
    (if (< fd 0) (%ip-say f (string-concat (list "can't open '" path "': " (libc-strerror (Err errno-of fd)))))
      (let ((n (%in-call (cu-ptr-call (%in-c "write") fd "-1" 2))))
        (if (< n 2) (%ip-say f (string-append "can't flush routing cache: " (libc-strerror (Err errno-of n))))
          (cu-ptr-call (%in-c "close") fd))))))

; a route flush keeps: what the listing keeps, less IPv6's catch-all unreachable
(def %ip-route-flushed?
  (fn (_ f r)
    (if (= (first r) 24)
      (if (%ip-route-kept? f r)
        (not (if (= (%ip-r-family r) 10)
               (if (= (%ip-r-dst-len r) 0)
                 (if (= (%ip-r-type r) 7) (let ((p (%ip-r-attr r 6))) (if (null? p) #f (= (%ip-num (rest p)) 4294967295))) #f) #f) #f))
        #f)
      #f)))

(def %ip-route-flush-round
  (fn (_ f round)
    (def fd (%ip-get f (lit fd)))
    (def rs (filter (fn (_ r) (%ip-route-flushed? f r)) (%ip-dump f fd 26 (%ip-get f (lit dump-family)) (+ 10 round) %ip-route-of)))
    (if (null? rs) 0
      (let ((bad (List find (fn (_ e) (not (null? e)))
                            (map (fn (_ b) (%ip-send-check fd b)) (%ip-flush-batches (map (fn (_ r) (cu-nth 11 r)) rs) 25 (+ 1000 (* round 1000)))))))
        (if (null? bad) (%ip-route-flush-round f (+ round 1))
          (do (%ip-say f (string-append "can't send flush request: " (libc-strerror bad))) 1))))))

(def %ip-route-flush
  (fn (_ f0 ws)
    (when (null? ws) (%ip-die f0 "\"ip route flush\" requires an argument"))
    (def f (%ip-route-filter f0 ws))
    (def family (%ip-get f (lit dump-family)))
    (unless (if (= (%ip-get f (lit tb)) -1) (= family 10) #t) (%ip-flush-cache f))
    (if (if (= (%ip-get f (lit tb)) -1) (= family 2) #f) 0
      (%ip-route-flush-round f 0))))

; --- add, change, delete and the rest --------------------------------------------

(def %ip-route-mod-words (list "src" "via" "mtu" "advmss" "scope" "protocol" "table" "dev" "oif" "to" "metric" "onlink"))

; mtu and advmss: [lock] NUM as RTAX_MTU or RTAX_ADVMSS in the metrics
(def %ip-route-metric
  (fn (_ f s a what rtax)
    (def lock? (string=? (first a) "lock"))
    (def b (if lock? (%ip-next f a) a))
    (def v (%ip-unsigned f (first b) what 4294967295))
    (pair (%ip-put (%ip-put s (lit mx) (pair (%ip-rta rtax (%ip-le v 4)) (%ip-get s (lit mx))))
                   (lit mxlock) (if lock? (| (%ip-get s (lit mxlock)) (<< 1 rtax)) (%ip-get s (lit mxlock))))
          (rest b))))

; the destination, with the type that may lead it
(def %ip-route-dst
  (fn (_ f s a)
    (def digit? (if (> (byte-len (first a)) 0) (if (>= (byte-at (first a) 0) #\0) (<= (byte-at (first a) 0) #\9) #f) #f))
    (def type (if digit? () (%ip-rtn-id (first a))))
    (def b (if (null? type) a (%ip-next f a)))
    (def s1 (if (null? type) s (%ip-put s (lit type) type)))
    (when (%ip-get s1 (lit dst-ok))
      (%ip-die f (string-concat (list "either \"to\" is duplicate, or \"" (first b) "\" is garbage"))))
    (let ((p (%ip-prefix-in f (first b) (%ip-get s1 (lit family)))))
      (pair (List fold (fn (_ t kv) (%ip-put t (first kv) (rest kv)))
                       (if (> (List ref 3 p) 0) (%ip-attr! (%ip-family! s1 (first p)) 1 (%ip-pfx-bytes p)) (%ip-family! s1 (first p)))
                       (list (pair (lit dst-len) (& (List ref 2 p) 255)) (pair (lit dst-ok) #t)))
            (rest b)))))

; an address word: src or via, as the attribute TYPE
(def %ip-route-addr
  (fn (_ f s a type)
    (let ((ad (%ip-address f (first a) (%ip-get s (lit family)))))
      (pair (%ip-attr! (%ip-family! s (first ad)) type (List take (List ref 2 ad) (List ref 1 ad))) (rest a)))))

; a name table's word: scope, protocol or table, the run ended where TAB has no such name
(def %ip-route-named
  (fn (_ f s a tab what key)
    (let ((id (%ip-id tab (first a))))
      (if (null? id) (%ip-invarg f (first a) what) (pair (%ip-put s key id) (rest a))))))

; one of the route's words at the front of WS: (S . WORDS-LEFT)
(def %ip-route-mod-word
  (fn (_ f s ws)
    (def k (%ip-keyword %ip-route-mod-words (first ws)))
    (match
      ((= k 0) (%ip-route-addr f s (%ip-next f ws) 7))
      ((= k 1) (%ip-route-addr f (%ip-put s (lit gw-ok) #t) (%ip-next f ws) 5))
      ((= k 2) (%ip-route-metric f s (%ip-next f ws) "mtu" 2))
      ((= k 3) (%ip-route-metric f s (%ip-next f ws) "advmss" 8))
      ((= k 4) (%ip-route-named f (%ip-put s (lit scope-ok) #t) (%ip-next f ws) (%ip-get f (lit scopes)) "scope" (lit scope)))
      ((= k 5) (%ip-route-named f s (%ip-next f ws) (%ip-protos f) "protocol" (lit protocol)))
      ((= k 6) (%ip-route-named f s (%ip-next f ws) (%ip-tables f) "table" (lit table)))
      ((if (= k 7) #t (= k 8)) (let ((a (%ip-next f ws))) (pair (%ip-put s (lit dev) (first a)) (rest a))))
      ((= k 10) (let ((a (%ip-next f ws)))
                  (pair (%ip-attr! s 6 (%ip-le (%ip-unsigned f (first a) "metric" 4294967295) 4)) (rest a))))
      ((= k 11) (pair (%ip-put s (lit flags) (| (%ip-get s (lit flags)) 4)) (rest ws)))
      (#t (%ip-route-dst f s (if (= k 9) (%ip-next f ws) ws))))))

; the scope busybox gives a route that names none
(def %ip-route-scope
  (fn (_ s del?)
    (def type (%ip-get s (lit type)))
    (match
      ((%ip-get s (lit scope-ok)) (%ip-get s (lit scope)))
      ((if (= type 2) #t (= type 10)) 254)
      ((if (= type 3) #t (if (= type 5) #t (= type 4))) 253)
      ((if (= type 1) #t (= type 0)) (match (del? 255) ((%ip-get s (lit gw-ok)) (%ip-get s (lit scope))) (#t 253)))
      (#t (%ip-get s (lit scope))))))

; iproute_modify: KIND RTM_NEWROUTE or RTM_DELROUTE, FLAGS the request's
(def %ip-route-modify
  (fn (_ f0 kind flags ws)
    (def del? (= kind 25))
    (def f (%ip-put f0 (lit scopes) (%ip-scopes f0)))
    (def s0 (List fold (fn (_ s kv) (%ip-put s (first kv) (rest kv))) ()
                  (list (pair (lit req) (%ip-req kind (| 1 flags) 1052 12)) (pair (lit family) (%ip-get f (lit preferred)))
                        (pair (lit table) 254) (pair (lit scope) (if del? 255 0)) (pair (lit protocol) (if del? 0 3))
                        (pair (lit type) (if del? 0 1)) (pair (lit flags) 0) (pair (lit dst-len) 0) (pair (lit dst-ok) #f)
                        (pair (lit gw-ok) #f) (pair (lit scope-ok) #f) (pair (lit dev) ()) (pair (lit mx) ()) (pair (lit mxlock) 0))))
    (def s1 (let go ((s s0) (ws ws)) (if (null? ws) s (let ((r (%ip-route-mod-word f s ws))) (go (first r) (rest r))))))
    (def fd (%ip-open f))
    (def s2 (if (null? (%ip-get s1 (lit dev))) s1
              (do (%ip-init-map f fd) (%ip-attr! s1 4 (%ip-le (%ip-dev-index f (%ip-get s1 (lit dev))) 4)))))
    (def mx (reverse (%ip-get s2 (lit mx))))
    (def mx1 (if (if (null? mx) #f (> (%ip-get s2 (lit mxlock)) 0)) (append mx (list (%ip-rta 1 (%ip-le (%ip-get s2 (lit mxlock)) 4)))) mx))
    (def s3 (if (null? mx) s2 (%ip-attr! s2 8 (List flatten mx1))))
    (def table (%ip-get s3 (lit table)))
    (def s4 (if (> table 255) (%ip-attr! s3 15 (%ip-le table 4)) s3))
    (def body (list (if (= (%ip-get s4 (lit family)) 0) 2 (%ip-get s4 (lit family))) (%ip-get s4 (lit dst-len)) 0 0
                    (if (> table 255) 0 table) (%ip-get s4 (lit protocol)) (%ip-route-scope s4 del?) (%ip-get s4 (lit type))))
    (def r (%ip-talk f fd (%ip-req-bytes (%ip-get s4 (lit req)) (append body (%ip-le (%ip-get s4 (lit flags)) 4)) 3) 3))
    (cu-ptr-call (%in-c "close") fd)
    (if (< r 0) 2 0)))

; --- get --------------------------------------------------------------------------

; rtnl_talk with an answer: the request sent as it is, the first message to
; SEQ read back as its bytes; -1 where the kernel refuses it, said
(def %ip-ask
  (fn (_ f fd bytes seq)
    (def out (%ip-buf bytes))
    (let ((r (%in-call (cu-ptr-call (%in-c "write") fd (cu-str->ptr out) (length bytes)))))
      (if (< r 0) (do (%ip-say f (string-append "can't talk to rtnetlink: " (libc-strerror (Err errno-of r)))) -1)
        (%ip-dump-answer f fd seq (fn (_ p len kind) (if (= kind 2)
                                                       (let ((e (cu-ptr-ref p 16 4)))
                                                         (if (= e 0) (%ip-bytes p 0 len)
                                                           (do (%ip-say f (string-append "RTNETLINK answers: " (libc-strerror (- 0 (%inet-int32 e))))) -1)))
                                                       (%ip-bytes p 0 len))))))))

; the first message to SEQ, read as OF reads it
(def %ip-dump-answer
  (fn (_ f fd seq of)
    (def buf (str-make-raw 8192))
    (let go ()
      (let ((n (%in-call (cu-ptr-call (%in-c "recv") fd (cu-str->ptr buf) 8192 0))))
        (match
          ((< n 0) (do (%ip-say f (string-append "OVERRUN: " (libc-strerror (Err errno-of n)))) (go)))
          ((= n 0) (do (%ip-say f "EOF on netlink") -1))
          (#t (let ((m (%ip-first-to (cu-str->ptr buf) n seq of))) (if (null? m) (go) m))))))))

(def %ip-first-to
  (fn (_ p n seq of)
    (let go ((o 0))
      (let ((len (if (> (+ o 16) n) 0 (cu-ptr-ref p o 4))))
        (match
          ((if (< len 16) #t (> (+ o len) n)) ())
          ((not (= (cu-ptr-ref p (+ o 8) 4) seq)) (go (+ o (%ip-align len))))
          (#t (of (%ip-off p o) len (cu-ptr-ref p (+ o 4) 2))))))))

; print_route on an answer's bytes: the route printed, or "Not a route" said
(def %ip-print-answer
  (fn (_ f bytes)
    (def buf (%ip-buf bytes))
    (def kind (cu-ptr-ref (cu-str->ptr buf) 4 2))
    (def r (%ip-route-of (cu-str->ptr buf) (length bytes) kind))
    (if (null? r)
      (do (file-write 2 (string-concat (list "Not a route: " (%inet-hex8 (length bytes)) " " (%inet-hex8 kind) " "
                                             (%inet-hex8 (cu-ptr-ref (cu-str->ptr buf) 6 2)) "\n"))) ())
      (do (file-write 1 (%ip-route-text f r)) r))))

(def %ip-get-words (list "from" "iif" "oif" "dev" "notify" "connected" "to"))

; one of get's words: (S . WORDS-LEFT)
(def %ip-route-get-word
  (fn (_ f s ws)
    (def k (let ((i (List find-index (fn (_ w) (string=? w (first ws))) %ip-get-words))) (if (null? i) -1 i)))
    (match
      ((= k 0) (%ip-route-get-end f (%ip-put s (lit from-ok) #t) (%ip-next f ws) 2 (lit src-len)))
      ((= k 1) (let ((a (%ip-next f ws))) (pair (%ip-put s (lit idev) (first a)) (rest a))))
      ((if (= k 2) #t (= k 3)) (let ((a (%ip-next f ws))) (pair (%ip-put s (lit odev) (first a)) (rest a))))
      ((= k 4) (pair (%ip-put s (lit flags) (| (%ip-get s (lit flags)) 256)) (rest ws)))
      ((= k 5) (pair (%ip-put s (lit connected) #t) (rest ws)))
      (#t (%ip-route-get-end f s (if (= k 6) (%ip-next f ws) ws) 1 (lit dst-len))))))

(def %ip-route-get-end
  (fn (_ f s a type key)
    (let ((p (%ip-prefix-in f (first a) (%ip-get s (lit family)))))
      (pair (%ip-put (if (> (List ref 3 p) 0) (%ip-attr! (%ip-family! s (first p)) type (%ip-pfx-bytes p)) (%ip-family! s (first p)))
                     key (& (List ref 2 p) 255))
            (rest a)))))

; the attributes of the route's message at P of N bytes: ((AT TYPE LEN) ...), in order
(def %ip-rta-walk
  (fn (_ p n)
    (let go ((a 28) (acc ()))
      (if (> (+ a 4) n) (reverse acc)
        (let ((len (cu-ptr-ref p a 2)))
          (if (if (< len 4) #t (> (+ a len) n)) (reverse acc)
            (go (+ a (%ip-align len)) (pair (list a (cu-ptr-ref p (+ a 2) 2) len) acc))))))))

; the answer's attributes renamed for the second question connected asks:
; the last PREFSRC as SRC, its length the source's, and OIF, GATEWAY and IIF
; set aside where get named no device; the run ended where it has neither
(def %ip-connect-bytes
  (fn (_ f bytes s seq)
    (def buf (%ip-buf bytes))
    (def p (cu-str->ptr buf))
    (def walk (%ip-rta-walk p (length bytes)))
    (def last-of (fn (_ type) (List find (fn (_ e) (= (List ref 1 e) type)) (reverse walk))))
    (def prefsrc (last-of 7))
    (when (if (null? prefsrc) (null? (last-of 2)) #f) (%ip-die f "can't connect the route"))
    (unless (null? prefsrc)
      (%inet-set! buf (+ (first prefsrc) 2) 2 2)
      (%inet-set! buf 18 (* 8 (- (List ref 2 prefsrc) 4)) 1))
    (map (fn (_ e) (unless (null? e) (%inet-set! buf (+ (first e) 2) 0 2)))
         (list (if (null? (%ip-get s (lit odev))) (last-of 4) ()) (last-of 5) (if (null? (%ip-get s (lit idev))) (last-of 3) ())))
    (%inet-set! buf 4 26 2)
    (%inet-set! buf 6 1 2)
    (%inet-set! buf 8 seq 4)
    (%ip-bytes p 0 (length bytes))))

; iproute_get
(def %ip-route-get
  (fn (_ f ws)
    (def s0 (List fold (fn (_ s kv) (%ip-put s (first kv) (rest kv))) ()
                  (list (pair (lit req) (%ip-req 26 1 1052 12)) (pair (lit family) (%ip-get f (lit preferred))) (pair (lit flags) 0)
                        (pair (lit src-len) 0) (pair (lit dst-len) 0) (pair (lit idev) ()) (pair (lit odev) ())
                        (pair (lit connected) #f) (pair (lit from-ok) #f))))
    (def s1 (let go ((s s0) (ws ws)) (if (null? ws) s (let ((r (%ip-route-get-word f s ws))) (go (first r) (rest r))))))
    (when (= (%ip-get s1 (lit dst-len)) 0) (%ip-die f "need at least destination address"))
    (def fd (%ip-open f))
    (def links (%ip-init-map f fd))
    (def fl (List fold (fn (_ t kv) (%ip-put t (first kv) (rest kv))) f
                  (list (pair (lit links) links) (pair (lit tb) 0) (pair (lit scope) 0) (pair (lit scopemask) 0) (pair (lit iif) 0)
                        (pair (lit rvia) %ip-no-prefix) (pair (lit scopes) (%ip-scopes f)))))
    (def s2 (if (null? (%ip-get s1 (lit idev))) s1 (%ip-attr! s1 3 (%ip-le (%ip-dev-index f (%ip-get s1 (lit idev))) 4))))
    (def s3 (if (null? (%ip-get s2 (lit odev))) s2 (%ip-attr! s2 4 (%ip-le (%ip-dev-index f (%ip-get s2 (lit odev))) 4))))
    (def body (append (list (if (= (%ip-get s3 (lit family)) 0) 2 (%ip-get s3 (lit family))) (%ip-get s3 (lit dst-len)) (%ip-get s3 (lit src-len)) 0 0 0 0 0)
                      (%ip-le (%ip-get s3 (lit flags)) 4)))
    (def a (%ip-ask f fd (%ip-req-bytes (%ip-get s3 (lit req)) body 3) 3))
    (if (not (pair? a)) 2
      (if (if (%ip-get s3 (lit connected)) (not (%ip-get s3 (lit from-ok))) #f)
        (%ip-route-connect fl fd a s3)
        (do (%ip-print-answer fl a) 0)))))

(def %ip-route-connect
  (fn (_ f fd a s)
    (def r (%ip-print-answer f a))
    (when (null? r) (%ip-die f "not a route?"))
    (def b (%ip-ask f fd (%ip-connect-bytes f a s 4) 4))
    (if (not (pair? b)) 2 (do (%ip-print-answer f b) 0))))

; --- do_iproute -------------------------------------------------------------------

(def %ip-route-cmds (list "a" "add" "append" "change" "chg" "delete" "get" "list" "show" "prepend" "replace" "test" "flush"))

; the route verbs: list, flush and get, else a route handed to the kernel
(def %ip-route
  (fn (_ f ws)
    (def k (if (null? ws) 7 (%ip-keyword %ip-route-cmds (first ws))))
    (match
      ((null? ws) (%ip-route-list f ()))
      ((< k 0) (%ip-invarg f (first ws) (%ip-get f (lit name))))
      ((= k 6) (%ip-route-get f (rest ws)))
      ((if (= k 7) #t (= k 8)) (%ip-route-list f (rest ws)))
      ((= k 12) (%ip-route-flush f (rest ws)))
      ((= k 5) (%ip-route-modify f 25 0 (rest ws)))
      (#t (%ip-route-modify f 24 (cu-nth k (list 1536 1536 3072 256 256 0 0 0 0 1024 1280 512)) (rest ws))))))

(def %cu-iproute (fn (_ argv stdin-thunk) (%ip-run "iproute" argv %ip-route)))

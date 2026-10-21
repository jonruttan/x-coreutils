; # x-coreutils -- the small tools, as applets
;
; ## cu/iptunnel.x -- ip tunnel and iptunnel: IPv4 tunnels, through the tunnel ioctls
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox 1.36's networking/libiproute/iptunnel.c.  A tunnel's parameters
; are an ip_tunnel_parm -- name, link, the GRE flags and keys, and the outer
; IPv4 header's tos, frag_off, ttl, protocol and addresses -- read from the
; words (mode ipip|gre|sit, remote, local, dev, ttl, tos, key, ikey, okey,
; seq, csum, pmtudisc, name) and handed to the kernel by SIOCADDTUNNEL,
; SIOCCHGTUNNEL and SIOCDELTUNNEL on the mode's base device (tunl0, gre0,
; sit0).  show asks SIOCGETTUNNEL of one tunnel, or with no mode lists every
; tunnel /proc/net/dev names whose hardware type is a tunnel's.

; --- the parameters ---------------------------------------------------------------

; ip_tunnel_parm's fields: name 0, link 16, i_flags 20, o_flags 22, i_key 24,
; o_key 28, then the IPv4 header at 32 -- tos 33, frag_off 38, ttl 40,
; protocol 41, saddr 44, daddr 48 -- 52 bytes in all, as a list of bytes

; P with BYTES from AT
(def %ip-t-put
  (fn (_ p at bytes)
    (append (List take at p) bytes (List drop (+ at (length bytes)) p))))

(def %ip-t-get (fn (_ p at n) (%ip-num (List take n (List drop at p)))))
(def %ip-t-bytes (fn (_ p at n) (List take n (List drop at p))))
(def %ip-t-or (fn (_ p at n v) (%ip-t-put p at (%ip-le (| (%ip-t-get p at n) v) n))))

; the parameters parse_args starts from: an IPv4 header of version 4,
; length 5 and DF set
(def %ip-t-fresh
  (fn (_) (%ip-t-put (%ip-t-put (map (fn (_ k) 0) (List range 0 52)) 32 (list 69)) 38 (list 64 0))))

(def %ip-t-name (fn (_ p) (%ip-cstr (%ip-t-bytes p 0 16))))

; strncpy_IFNAMSIZ: NAME as the 16 bytes of a name field
(def %ip-t-name-bytes
  (fn (_ name) (List take 16 (append (%ip-str-bytes name) (map (fn (_ k) 0) (List range 0 16))))))

; GRE_KEY, GRE_SEQ and GRE_CSUM as the flags field holds them, network order
(def %ip-gre-key 32)
(def %ip-gre-seq 16)
(def %ip-gre-csum 128)

; IN_MULTICAST of an address's four bytes
(def %ip-t-multicast? (fn (_ bytes) (if (>= (first bytes) 224) (<= (first bytes) 239) #f)))

; --- the ioctls -------------------------------------------------------------------

; an AF_INET datagram socket, or the run ended as xsocket ends it
(def %ip-t-socket
  (fn (_ f)
    (let ((fd (%in-call (%cu-ptr-call (%in-c "socket") 2 2 0))))
      (if (< fd 0) (%ip-die f (string-append "socket: " (libc-strerror (Err errno-of fd)))) fd))))

; REQ on an ifreq naming DEV whose data points at the parameters P: (R . P'),
; R the call's answer, P' the parameters as the kernel left them; a failure
; said, and the run ended where DIE?
(def %ip-t-ioctl
  (fn (_ f req dev p die?)
    (def buf (%ip-buf p))
    (def r (%if-req dev))
    (%inet-set! r 16 (%td-ptr->int (%cu-str->ptr buf)) 8)
    (def fd (%ip-t-socket f))
    (def n (%in-call (%cu-ptr-call (%in-c "ioctl") fd req (%cu-str->ptr r))))
    (%cu-ptr-call (%in-c "close") fd)
    (when (< n 0)
      (let ((msg (string-concat (list "ioctl 0x" (%cvt req %cu-string-type 16) " failed: " (libc-strerror (Err errno-of n))))))
        (if die? (%ip-die f msg) (%ip-say f msg))))
    (pair n (%ip-bytes (%cu-str->ptr buf) 0 52))))

; an ifreq ioctl on DEV, warned where it fails: the ifreq after, or nil
(def %ip-t-ifreq
  (fn (_ f req r)
    (def fd (%ip-t-socket f))
    (def n (%in-call (%cu-ptr-call (%in-c "ioctl") fd req (%cu-str->ptr r))))
    (%cu-ptr-call (%in-c "close") fd)
    (if (< n 0) (do (%ip-say f (string-concat (list "ioctl 0x" (%cvt req %cu-string-type 16) " failed: " (libc-strerror (Err errno-of n))))) ())
      r)))

; do_ioctl_get_ifindex: DEV's index, or the run ended
(def %ip-t-ifindex
  (fn (_ f dev)
    (def fd (%ip-t-socket f))
    (def r (%if-req dev))
    (def n (%in-call (%cu-ptr-call (%in-c "ioctl") fd 35123 (%cu-str->ptr r))))
    (%cu-ptr-call (%in-c "close") fd)
    (if (< n 0) (%ip-die f (string-append "ioctl 0x8933 failed: " (libc-strerror (Err errno-of n)))) (%inet-int32 (%if-ref r 16 4)))))

; do_ioctl_get_ifname: the name of link IDX, or nil
(def %ip-t-ifname
  (fn (_ f idx)
    (def r (%inet-zeros 40))
    (%inet-set! r 16 idx 4)
    (let ((a (%ip-t-ifreq f 35088 r))) (if (null? a) () (%cu-ptr->str (%cu-str->ptr a))))))

; --- parse_args -------------------------------------------------------------------

(def %ip-t-words
  (list "mode" "ipip" "ip/ip" "gre" "gre/ip" "sit" "ipv6/ip" "key" "ikey" "okey" "seq" "iseq" "oseq"
        "csum" "icsum" "ocsum" "nopmtudisc" "pmtudisc" "remote" "any" "local" "dev" "ttl" "inherit" "tos" "dsfield" "name"))

(def %ip-t-k (fn (_ w) (let ((i (List find-index (fn (_ x) (string=? x w)) %ip-t-words))) (if (null? i) -1 i))))

; mode: the protocol, refused where another was asked
(def %ip-t-mode
  (fn (_ f p arg)
    (def k (%ip-t-k arg))
    (def proto (match ((if (= k 1) #t (= k 2)) 4) ((if (= k 3) #t (= k 4)) 47) ((if (= k 5) #t (= k 6)) 41) (#t 0)))
    (def cur (%ip-t-get p 41 1))
    (match
      ((= proto 0) (%ip-die f "can't guess tunnel mode"))
      ((if (= cur 0) #f (not (= cur proto))) (%ip-die f "you managed to ask for more than one tunnel mode"))
      (#t (%ip-t-put p 41 (list proto))))))

; a key word: KEY as the bytes of the key, dotted or a number in network order
(def %ip-t-key-bytes
  (fn (_ f arg what)
    (if (>= (%dp-find arg 0 #\.) 0) (%ip-addr32 f arg) (reverse (%ip-le (%ip-unsigned f arg what 4294967295) 4)))))

; key, ikey and okey: the flags they set, and where the key goes -- busybox's
; ikey sets the out key where it is dotted
(def %ip-t-key
  (fn (_ f p k arg)
    (def dotted? (>= (%dp-find arg 0 #\.) 0))
    (def b (%ip-t-key-bytes f arg (%cu-nth (- k 7) (list "key" "ikey" "okey"))))
    (match
      ((= k 7) (%ip-t-put (%ip-t-put (%ip-t-or (%ip-t-or p 20 2 %ip-gre-key) 22 2 %ip-gre-key) 24 b) 28 b))
      ((= k 8) (%ip-t-put (%ip-t-or p 20 2 %ip-gre-key) (if dotted? 28 24) b))
      (#t (%ip-t-put (%ip-t-or p 22 2 %ip-gre-key) 28 b)))))

; the flag words: seq, iseq, oseq, csum, icsum, ocsum, nopmtudisc, pmtudisc
(def %ip-t-flag
  (fn (_ p k)
    (match
      ((= k 10) (%ip-t-or (%ip-t-or p 20 2 %ip-gre-seq) 22 2 %ip-gre-seq))
      ((= k 11) (%ip-t-or p 20 2 %ip-gre-seq))
      ((= k 12) (%ip-t-or p 22 2 %ip-gre-seq))
      ((= k 13) (%ip-t-or (%ip-t-or p 20 2 %ip-gre-csum) 22 2 %ip-gre-csum))
      ((= k 14) (%ip-t-or p 20 2 %ip-gre-csum))
      ((= k 15) (%ip-t-or p 22 2 %ip-gre-csum))
      ((= k 16) (%ip-t-put p 38 (list 0 0)))
      (#t (%ip-t-put p 38 (list 64 0))))))

; ttl and tos: inherit, else a number up to 255 or a dsfield
(def %ip-t-ttl
  (fn (_ f p arg)
    (if (= (%ip-t-k arg) 23) p
      (let ((v (%ip-unsigned f arg "TTL" 4294967295)))
        (if (> v 255) (%ip-invarg f arg "TTL") (%ip-t-put p 40 (list v)))))))

(def %ip-t-tos
  (fn (_ f p arg)
    (if (= (%ip-t-k arg) 23) (%ip-t-put p 33 (list 1))
      (let ((v (%ip-id (%ip-dsfields f) arg 16))) (if (null? v) (%ip-invarg f arg "TOS") (%ip-t-put p 33 (list (& v 255))))))))

; the name: a second refused; for change, the first word's tunnel read from the kernel
(def %ip-t-name-word
  (fn (_ f p arg cmd count)
    (unless (string=? (%ip-t-name p) "") (%ip-die f (string-concat (list "either \"name\" is duplicate, or \"" arg "\" is garbage"))))
    (let ((p1 (%ip-t-put p 0 (%ip-t-name-bytes arg))))
      (if (if (= cmd 35315) (= count 0) #f)
        (let ((old (%ip-t-ioctl f 35312 arg (map (fn (_ k) 0) (List range 0 52)) #f)))
          (%ip-t-keep-medium p (if (< (first old) 0) (Err raise (lit ip-exit1) "tunnel" ()) (rest old))))
        p1))))

; one of parse_args's words at the front of WS: (P . WORDS-LEFT)
(def %ip-t-word
  (fn (_ f p ws cmd count)
    (def k (%ip-t-k (first ws)))
    (match
      ((= k 0) (let ((a (%ip-next f ws))) (pair (%ip-t-mode f p (first a)) (rest a))))
      ((if (>= k 7) (<= k 9) #f) (let ((a (%ip-next f ws))) (pair (%ip-t-key f p k (first a)) (rest a))))
      ((if (>= k 10) (<= k 17) #f) (pair (%ip-t-flag p k) (rest ws)))
      ((if (= k 18) #t (= k 20))
        (let ((a (%ip-next f ws))) (pair (if (= (%ip-t-k (first a)) 19) p (%ip-t-put p (if (= k 18) 48 44) (%ip-addr32 f (first a)))) (rest a))))
      ((= k 21) (let ((a (%ip-next f ws))) (pair (%ip-put-medium p (first a)) (rest a))))
      ((= k 22) (let ((a (%ip-next f ws))) (pair (%ip-t-ttl f p (first a)) (rest a))))
      ((if (= k 24) #t (= k 25)) (let ((a (%ip-next f ws))) (pair (%ip-t-tos f p (first a)) (rest a))))
      (#t (let ((a (if (= k 26) (%ip-next f ws) ws))) (pair (%ip-t-name-word f p (first a) cmd count) (rest a)))))))

; dev's name is held beside the parameters, as busybox's medium is
(def %ip-put-medium (fn (_ p name) (append (List take 52 p) (list name))))
(def %ip-t-medium (fn (_ p) (if (> (length p) 52) (List ref 52 p) ())))

; NEW with the dev P holds, where it holds one
(def %ip-t-keep-medium (fn (_ p new) (if (null? (%ip-t-medium p)) new (%ip-put-medium new (%ip-t-medium p)))))

; parse_args: the words as parameters, the protocol guessed from the name,
; the link found, and multicast's keys and source checked
(def %ip-t-parse
  (fn (_ f ws cmd)
    (def p0 (let go ((p (%ip-t-fresh)) (ws ws) (count 0))
              (if (null? ws) p (let ((r (%ip-t-word f p ws cmd count))) (go (first r) (rest r) (+ count 1))))))
    (def medium (%ip-t-medium p0))
    (def p1 (List take 52 p0))
    (def name (%ip-t-name p1))
    (def p2 (if (= (%ip-t-get p1 41 1) 0)
              (match ((%ip-t-prefix? name "gre") (%ip-t-put p1 41 (list 47)))
                     ((%ip-t-prefix? name "ipip") (%ip-t-put p1 41 (list 4)))
                     ((%ip-t-prefix? name "sit") (%ip-t-put p1 41 (list 41)))
                     (#t p1))
              p1))
    (when (if (if (= (%ip-t-get p2 41 1) 4) #t (= (%ip-t-get p2 41 1) 41))
            (not (= (& (| (%ip-t-get p2 20 2) (%ip-t-get p2 22 2)) %ip-gre-key) 0)) #f)
      (%ip-die f "keys are not allowed with ipip and sit"))
    (def p3 (if (null? medium) p2 (%ip-t-put p2 16 (%ip-le (%ip-t-ifindex f medium) 4))))
    (def mc? (%ip-t-multicast? (%ip-t-bytes p3 48 4)))
    (def p4 (if (if (= (%ip-t-get p3 24 4) 0) mc? #f) (%ip-t-or (%ip-t-put p3 24 (%ip-t-bytes p3 48 4)) 20 2 %ip-gre-key) p3))
    (def p5 (if (if (= (%ip-t-get p4 28 4) 0) mc? #f) (%ip-t-or (%ip-t-put p4 28 (%ip-t-bytes p4 48 4)) 22 2 %ip-gre-key) p4))
    (when (if mc? (= (%ip-t-get p5 44 4) 0) #f) (%ip-die f "broadcast tunnel requires a source address"))
    p5))

; memcmp(name, WORD, length of WORD)
(def %ip-t-prefix?
  (fn (_ name word) (if (>= (byte-len name) (byte-len word)) (string=? (substring name 0 (byte-len word)) word) #f)))

; the base device of the parameters' protocol, or nil
(def %ip-t-base
  (fn (_ p) (match ((= (%ip-t-get p 41 1) 4) "tunl0") ((= (%ip-t-get p 41 1) 47) "gre0") ((= (%ip-t-get p 41 1) 41) "sit0") (#t ()))))

; --- the verbs --------------------------------------------------------------------

; do_add: add and change on the protocol's base device (change on the name where it has one)
(def %ip-t-add
  (fn (_ f cmd ws)
    (def p (%ip-t-parse f ws cmd))
    (def base (%ip-t-base p))
    (when (if (= (%ip-t-get p 40 1) 0) #f (= (%ip-t-get p 38 2) 0)) (%ip-die f "ttl != 0 and noptmudisc are incompatible"))
    (when (null? base) (%ip-die f "can't determine tunnel mode (ipip, gre or sit)"))
    (%ip-t-ioctl f cmd (if (if (= cmd 35315) (not (string=? (%ip-t-name p) "")) #f) (%ip-t-name p) base) p #t)
    0))

; do_del: on the base device, or the name where it has none; the name where it has one
(def %ip-t-del
  (fn (_ f ws)
    (def p (%ip-t-parse f ws 35314))
    (def base (%ip-t-base p))
    (%ip-t-ioctl f 35314 (if (string=? (%ip-t-name p) "") (if (null? base) "" base) (%ip-t-name p)) p #t)
    0))

; print_tunnel's text for the parameters P
(def %ip-t-text
  (fn (_ f p)
    (def proto (%ip-t-get p 41 1))
    (def tos (%ip-t-get p 33 1))
    (def dotted (fn (_ at) (Str8 join "." (map %cu-int->str (%ip-t-bytes p at 4)))))
    (def addr (fn (_ at) (if (= (%ip-t-get p at 4) 0) "any" (dotted at))))
    (def link (%inet-int32 (%ip-t-get p 16 4)))
    (def iflags (%ip-t-get p 20 2))
    (def oflags (%ip-t-get p 22 2))
    (def keys? (if (= (& iflags %ip-gre-key) 0) #f (if (= (& oflags %ip-gre-key) 0) #f (= (%ip-t-get p 24 4) (%ip-t-get p 28 4)))))
    (string-concat
      (list (%ip-t-name p) ": " (match ((= proto 4) "ip") ((= proto 47) "gre") ((= proto 41) "ipv6") (#t "unknown"))
            "/ip  remote " (addr 48) "  local " (addr 44) " "
            (if (= link 0) "" (let ((n (%ip-t-ifname f link))) (if (null? n) "" (string-concat (list " dev " n " ")))))
            (if (= (%ip-t-get p 40 1) 0) " ttl inherit " (string-concat (list " ttl " (%cu-int->str (%ip-t-get p 40 1)) " ")))
            (if (= tos 0) ""
              (string-concat (list " tos" (if (= (& tos 1) 0) "" " inherit")
                                   (if (= (& tos 254) 0) ""
                                     (string-concat (list (if (= (& tos 1) 0) " " "/") (%ip-name (%ip-dsfields f) (& tos 254)) " "))))))
            (if (= (& (%ip-t-get p 38 2) 64) 0) " nopmtudisc" "")
            (if keys? (string-append " key " (dotted 24))
              (string-append (if (= (& iflags %ip-gre-key) 0) "" (string-concat (list " ikey " (dotted 24) " ")))
                             (if (= (& oflags %ip-gre-key) 0) "" (string-concat (list " okey " (dotted 28) " ")))))
            (if (= (& iflags %ip-gre-seq) 0) "" (string-append (%ip-sl f) "  Drop packets out of sequence.\n"))
            (if (= (& iflags %ip-gre-csum) 0) "" (string-append (%ip-sl f) "  Checksum in received packet is required."))
            (if (= (& oflags %ip-gre-seq) 0) "" (string-append (%ip-sl f) "  Sequence packets on output."))
            (if (= (& oflags %ip-gre-csum) 0) "" (string-append (%ip-sl f) "  Checksum output packets."))))))

; do_tunnels_list's filter: the link, name, addresses and in key the parameters ask for
(def %ip-t-matches?
  (fn (_ p q)
    (def ask (fn (_ at n) (let ((v (%ip-t-get p at n))) (if (= v 0) #t (= v (%ip-t-get q at n))))))
    (if (ask 16 4) (if (if (string=? (%ip-t-name p) "") #t (string=? (%ip-t-name p) (%ip-t-name q)))
                     (if (ask 48 4) (if (ask 44 4) (ask 24 4) #f) #f) #f) #f)))

; one /proc/net/dev line: the tunnel it names, printed where the filter keeps it; #f where the file is malformed
(def %ip-t-list-line
  (fn (_ f p line)
    (def c (%dp-find line 0 #\:))
    (def name (if (< c 0) "" (let ((ws (%inet-words (substring line 0 c)))) (if (null? ws) "" (first ws)))))
    (def nums (if (< c 0) () (%inet-words (substring line (+ c 1) (byte-len line)))))
    (match
      ((string=? name "") (do (%ip-say f "wrong format of /proc/net/dev") #f))
      ((< (length nums) 15) #t)
      ((if (string=? (%ip-t-name p) "") #f (not (string=? (%ip-t-name p) name))) #t)
      (#t (%ip-t-list-one f p name)))))

(def %ip-t-list-one
  (fn (_ f p name)
    (def hw (%ip-t-ifreq f 35111 (%if-req name)))
    (def type (if (null? hw) -1 (%if-ref hw 16 2)))
    (match
      ((< type 0) (do (%ip-say f (string-concat (list "can't get type of [" name "]"))) #t))
      ((not (if (= type 768) #t (if (= type 778) #t (= type 776)))) #t)
      (#t (let ((q (%ip-t-ioctl f 35312 name (map (fn (_ k) 0) (List range 0 52)) #f)))
            (do (when (if (>= (first q) 0) (%ip-t-matches? p (rest q)) #f) (file-write 1 (string-append (%ip-t-text f (rest q)) "\n")))
                #t))))))

; do_tunnels_list
(def %ip-t-list
  (fn (_ f p)
    (def text (file-or-err (fn (_) (file-read-unsized "/proc/net/dev"))))
    (if (Err err? text) (%ip-say f (string-append "can't open '/proc/net/dev': " (libc-strerror (Err errno-of text))))
      (let go ((lines (List drop 2 (%cu-lines text))))
        (when (if (pair? lines) (%ip-t-list-line f p (first lines)) #f) (go (rest lines)))))
    0))

; do_show: one tunnel where a mode or a name gives the protocol, else all of them
(def %ip-t-show
  (fn (_ f ws)
    (def p (%ip-t-parse f ws 35312))
    (def base (%ip-t-base p))
    (if (null? base) (%ip-t-list f p)
      (let ((q (%ip-t-ioctl f 35312 (if (string=? (%ip-t-name p) "") base (%ip-t-name p)) p #f)))
        (if (< (first q) 0) 255 (do (file-write 1 (string-append (%ip-t-text f (rest q)) "\n")) 0))))))

; do_iptunnel: its exit where change cannot read the tunnel it names is 1
(def %ip-tunnel
  (fn (_ f ws)
    (guard (e (if (eq? (%cu-err-label e) (lit ip-exit1)) 1 (error e)))
      (let ((k (if (null? ws) 3 (%ip-keyword (list "add" "change" "delete" "show" "list" "lst") (first ws)))))
        (match
          ((< k 0) (%ip-invarg f (first ws) (%ip-get f (lit name))))
          ((= k 0) (%ip-t-add f 35313 (rest ws)))
          ((= k 1) (%ip-t-add f 35315 (rest ws)))
          ((= k 2) (%ip-t-del f (rest ws)))
          (#t (%ip-t-show f (if (null? ws) () (rest ws)))))))))

(def %cu-iptunnel (fn (_ argv stdin-thunk) (%ip-run "iptunnel" argv %ip-tunnel)))

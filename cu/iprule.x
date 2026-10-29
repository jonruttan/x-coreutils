; # x-coreutils -- the small tools, as applets
;
; ## cu/iprule.x -- ip rule and iprule: the kernel's routing rules, over netlink
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox 1.36's networking/libiproute/iprule.c.  `ip rule list|show` dumps
; RTM_GETRULE for the family (IPv4 unless one was asked) and prints each rule:
; its priority, from and to, tos, fwmark and mask, iif, the table it looks
; up, the suppress limits, realms, and a nat's map-to or the rule's type.
; `add` and `delete` build an RTM_NEWRULE or RTM_DELRULE from the rule's
; words, each matched by a unique prefix.  TOS values are named from
; /etc/iproute2/rt_dsfield (hex), realms from rt_realms.

(module cu/iprule)

(import cu/dump dp-find)
(import cu/inet inet-int32)
(import cu/ip ip-addr1 ip-attrs ip-cstr ip-die ip-die-usage ip-dump ip-get
  ip-id ip-invarg ip-keyword ip-name ip-names ip-next ip-ntoa ip-num ip-open
  ip-put ip-run ip-say ip-some)
(import cu/iproute ip-host-len ip-r-attr ip-r-dst-len ip-r-family ip-r-src-len
  ip-r-type ip-rtn-id ip-rtn-name ip-tables)
(import cu/ipset ip-attr! ip-le ip-pfx-bytes ip-prefix-in ip-req ip-req-bytes
  ip-str-bytes ip-talk ip-unsigned)
(import cu/prims append byte-len cu-int->str cu-libc-sym cu-nth cu-ptr-call
  cu-ptr-ref cu-string-type cvt file-write map string-append string=?
  substring)

(def ip-dsfields (fn (_ f) (ip-names f "dsfield" (list (pair 0 "0")))))
(def %ip-realms (fn (_ f) (ip-names f "realms" (list (pair 0 "unknown")))))

; FRA_DST SRC IIFNAME GATEWAY PRIORITY FWMARK FLOW SUPPRESS_IFGROUP SUPPRESS_PREFIXLEN TABLE FWMASK
(def %ip-rule-want (list 1 2 3 5 6 10 11 13 14 15 16))

(def %ip-rule-of
  (fn (_ p len kind)
    (if (if (= kind 32) (>= len 28) #f)
      (list kind (cu-ptr-ref p 16 1) (cu-ptr-ref p 17 1) (cu-ptr-ref p 18 1) (cu-ptr-ref p 19 1)
            (cu-ptr-ref p 20 1) 0 0 (cu-ptr-ref p 23 1) (cu-ptr-ref p 24 4) (ip-attrs p 28 len %ip-rule-want))
      ())))

; %#x: N in hex with 0x before it, plain 0 for 0
(def %ip-hex-alt (fn (_ n) (if (= n 0) "0" (string-append "0x" (cvt n cu-string-type 16)))))

; an end of a rule: ADDR/LEN, ADDR at the host length, 0/LEN, or NONE
(def %ip-rule-end
  (fn (_ r type len none)
    (def e (ip-r-attr r type))
    (def family (ip-r-family r))
    (match
      ((not (null? e)) (if (= len (ip-host-len family)) (ip-ntoa family (rest e))
                         (%str-concat (list (ip-ntoa family (rest e)) "/" (cu-int->str len)))))
      ((= len 0) none)
      (#t (string-append "0/" (cu-int->str len))))))

(def %ip-rule-fwmark
  (fn (_ r)
    (def mark (ip-r-attr r 10))
    (def mask (ip-r-attr r 16))
    (def m (if (null? mark) 0 (ip-num (rest mark))))
    (match
      ((if (null? mark) (null? mask) #f) "")
      ((if (null? mask) #t (= (ip-num (rest mask)) 4294967295)) (%str-concat (list "fwmark " (%ip-hex-alt m) " ")))
      (#t (%str-concat (list "fwmark " (%ip-hex-alt m) "/" (%ip-hex-alt (ip-num (rest mask))) " "))))))

; a suppress limit, shown where it is not -1
(def %ip-rule-limit
  (fn (_ r type word)
    (let ((e (ip-r-attr r type)))
      (if (if (null? e) #t (= (ip-num (rest e)) 4294967295)) ""
        (%str-concat (list word " " (cu-int->str (inet-int32 (ip-num (rest e)))) " "))))))

(def %ip-rule-realms
  (fn (_ f r)
    (let ((e (ip-r-attr r 11)))
      (if (null? e) ""
        (let ((to (& (ip-num (rest e)) 65535)) (from (>> (ip-num (rest e)) 16)))
          (string-append (if (= from 0) "" (%str-concat (list "realms " (ip-name (%ip-realms f) from) "/")))
                         (string-append (ip-name (%ip-realms f) to) " ")))))))

; the rule's type: a nat's map-to, else any type but unicast, as its name
(def %ip-rule-type
  (fn (_ r)
    (match
      ((= (ip-r-type r) 10)
        (let ((g (ip-r-attr r 5))) (if (null? g) "masquerade" (%str-concat (list "map-to " (ip-ntoa (ip-r-family r) (rest g)) " ")))))
      ((= (ip-r-type r) 1) "")
      (#t (ip-rtn-name (ip-r-type r))))))

; print_rule's line for R
(def %ip-rule-text
  (fn (_ f r)
    (def prio (ip-r-attr r 6))
    (def table (ip-r-attr r 15))
    (%str-concat
      (list (cu-int->str (if (null? prio) 0 (ip-num (rest prio)))) ":\tfrom "
            (%ip-rule-end r 2 (ip-r-src-len r) "all") " "
            (let ((to (%ip-rule-end r 1 (ip-r-dst-len r) ""))) (if (string=? to "") "" (%str-concat (list "to " to " "))))
            (if (= (cu-nth 4 r) 0) "" (%str-concat (list "tos " (ip-name (ip-dsfields f) (cu-nth 4 r)) " ")))
            (%ip-rule-fwmark r)
            (ip-some (cu-nth 10 r) 3 (fn (_ b) (%str-concat (list "iif " (ip-cstr b) " "))))
            (match ((not (null? table)) (%str-concat (list "lookup " (ip-name (ip-tables f) (ip-num (rest table))) " ")))
                   ((= (cu-nth 5 r) 0) "")
                   (#t (%str-concat (list "lookup " (ip-name (ip-tables f) (cu-nth 5 r)) " "))))
            (%ip-rule-limit r 14 "suppress_prefixlength")
            (%ip-rule-limit r 13 "suppress_ifgroup")
            (%ip-rule-realms f r)
            (%ip-rule-type r)
            "\n"))))

; iprule_list: no words, or a warning and 255
(def %ip-rule-list
  (fn (_ f ws)
    (if (not (null? ws)) (do (ip-say f "ignoring all arguments") 255)
      (let ((fd (ip-open f)))
        (do (map (fn (_ r) (file-write 1 (%ip-rule-text f r)))
                 (ip-dump f fd 34 (if (= (ip-get f (lit preferred)) 0) 2 (ip-get f (lit preferred))) 1 %ip-rule-of))
            (cu-ptr-call (cu-libc-sym "close") fd)
            0)))))

(def %ip-rule-words
  (list "from" "to" "preference" "order" "priority" "tos" "fwmark" "realms" "table" "lookup"
        "suppress_prefixlength" "suppress_ifgroup" "dev" "iif" "nat" "map-to" "type" "help"))

; get_addr32: an IPv4 address's four bytes, or the run ended
(def ip-addr32
  (fn (_ f arg)
    (let ((a (ip-addr1 arg 2)))
      (if (first a) (List take 4 (List ref 2 a))
        (ip-die f (%str-concat (list "an IP address is expected rather than \"" arg "\"")))))))

; get_rt_realms: FROM/TO or TO, each a realm's name or number; nil where one is neither
(def %ip-rule-realm-of
  (fn (_ f arg)
    (def tab (%ip-realms f))
    (def slash (dp-find arg 0 #\/))
    (def from (if (< slash 0) 0 (ip-id tab (substring arg 0 slash))))
    (def rest-arg (if (< slash 0) arg (substring arg (+ slash 1) (byte-len arg))))
    (def to (if (= (byte-len rest-arg) 0) 0 (ip-id tab rest-arg)))
    (if (if (null? from) #t (null? to)) () (| (<< from 16) to))))

; a prefix word: from or to, as the attribute TYPE and length KEY
(def %ip-rule-pfx
  (fn (_ f s a type key)
    (let ((p (ip-prefix-in f (first a) (ip-get s (lit family)))))
      (pair (ip-put (ip-attr! s type (ip-pfx-bytes p)) key (& (List ref 2 p) 255)) (rest a)))))

; one of the rule's words at the front of WS: (S . WORDS-LEFT)
(def %ip-rule-word
  (fn (_ f s ws)
    (def k (ip-keyword %ip-rule-words (first ws)))
    (def u32 (fn (_ a word attr) (pair (ip-attr! s attr (ip-le (ip-unsigned f (first a) word 4294967295) 4)) (rest a))))
    (match
      ((< k 0) (ip-invarg f (first ws) (ip-get f (lit name))))
      ((= k 0) (%ip-rule-pfx f s (ip-next f ws) 2 (lit src-len)))
      ((= k 1) (%ip-rule-pfx f s (ip-next f ws) 1 (lit dst-len)))
      ((<= k 4) (u32 (ip-next f ws) "preference" 6))
      ((= k 5) (let ((a (ip-next f ws)))
                 (let ((t (ip-id (ip-dsfields f) (first a) 16)))
                   (if (null? t) (ip-invarg f (first a) "TOS") (pair (ip-put s (lit tos) t) (rest a))))))
      ((= k 6) (%ip-rule-mark f s (ip-next f ws)))
      ((= k 7) (let ((a (ip-next f ws)))
                 (let ((r (%ip-rule-realm-of f (first a))))
                   (if (null? r) (ip-invarg f (first a) "realms") (pair (ip-attr! s 11 (ip-le r 4)) (rest a))))))
      ((<= k 9) (let ((a (ip-next f ws)))
                  (let ((t (ip-id (ip-tables f) (first a))))
                    (if (null? t) (ip-invarg f (first a) "table ID")
                      (pair (ip-put (if (> t 255) (ip-attr! (ip-put s (lit table) 0) 15 (ip-le t 4)) (ip-put s (lit table) t)) (lit table-ok) #t)
                            (rest a))))))
      ((= k 10) (u32 (ip-next f ws) "suppress_prefixlength" 14))
      ((= k 11) (u32 (ip-next f ws) "suppress_ifgroup" 13))
      ((<= k 13) (let ((a (ip-next f ws))) (pair (ip-attr! s 3 (append (ip-str-bytes (first a)) (list 0))) (rest a))))
      ((<= k 15) (let ((a (ip-next f ws))) (pair (ip-put (ip-attr! s 5 (ip-addr32 f (first a))) (lit type) 10) (rest a))))
      ((= k 17) (ip-die-usage))
      (#t (let ((a (if (= k 16) (ip-next f ws) ws)))
            (let ((t (ip-rtn-id (first a))))
              (if (null? t) (ip-invarg f (first a) "type") (pair (ip-put s (lit type) t) (rest a)))))))))

; fwmark MARK[/MASK]
(def %ip-rule-mark
  (fn (_ f s a)
    (def slash (dp-find (first a) 0 #\/))
    (def mark (ip-unsigned f (if (< slash 0) (first a) (substring (first a) 0 slash)) "fwmark" 4294967295))
    (def s1 (ip-attr! s 10 (ip-le mark 4)))
    (pair (if (< slash 0) s1
            (ip-attr! s1 16 (ip-le (ip-unsigned f (substring (first a) (+ slash 1) (byte-len (first a))) "fwmask" 4294967295) 4)))
          (rest a))))

; iprule_modify: KIND RTM_NEWRULE or RTM_DELRULE
(def %ip-rule-modify
  (fn (_ f kind ws)
    (def new? (= kind 32))
    (def s0 (List fold (fn (_ t kv) (ip-put t (first kv) (rest kv))) ()
                  (list (pair (lit req) (ip-req kind (if new? 1537 1) 1052 12)) (pair (lit family) (ip-get f (lit preferred)))
                        (pair (lit type) (if new? 1 0)) (pair (lit table) 0) (pair (lit table-ok) #f) (pair (lit tos) 0)
                        (pair (lit src-len) 0) (pair (lit dst-len) 0))))
    (def s (let go ((s s0) (ws ws)) (if (null? ws) s (let ((r (%ip-rule-word f s ws))) (go (first r) (rest r))))))
    (def table (if (if (ip-get s (lit table-ok)) #f new?) 254 (ip-get s (lit table))))
    (def body (list (if (= (ip-get s (lit family)) 0) 2 (ip-get s (lit family))) (ip-get s (lit dst-len)) (ip-get s (lit src-len))
                    (ip-get s (lit tos)) table 3 0 (ip-get s (lit type))))
    (def fd (ip-open f))
    (def r (ip-talk f fd (ip-req-bytes (ip-get s (lit req)) (append body (ip-le 0 4)) 2) 2))
    (cu-ptr-call (cu-libc-sym "close") fd)
    (if (< r 0) 2 0)))

; do_iprule
(def ip-rule
  (fn (_ f ws)
    (def k (if (null? ws) 2 (ip-keyword (list "add" "delete" "list" "show") (first ws))))
    (match
      ((null? ws) (%ip-rule-list f ()))
      ((< k 0) (ip-invarg f (first ws) (ip-get f (lit name))))
      ((= k 0) (%ip-rule-modify f 32 (rest ws)))
      ((= k 1) (%ip-rule-modify f 33 (rest ws)))
      (#t (%ip-rule-list f (rest ws))))))

(def cu-iprule (fn (_ argv stdin-thunk) (ip-run "iprule" argv ip-rule)))

(provide cu/iprule cu-iprule ip-addr32 ip-dsfields ip-rule)

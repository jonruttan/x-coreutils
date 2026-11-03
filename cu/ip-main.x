; # x-coreutils -- the small tools, as applets
;
; ## cu/ip-main.x -- ip, ipaddr and iplink: ip_main and its address and link verbs
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox 1.36's networking/ip.c and the do_ipaddr / do_iplink fronts: the
; common options, then the object word hands the rest to its verb.

(module cu/ip-main)

(import cu/ip ip-die-usage ip-get ip-invarg ip-keyword ip-list ip-put ip-run)
(import cu/ipneigh ip-neigh)
(import cu/iproute ip-route)
(import cu/iprule ip-rule)
(import cu/ipset ip-add-link ip-flush ip-modify ip-set)
(import cu/iptunnel ip-tunnel)
(import cu/prims cu-err-label cu-nth)

; do_ipaddr: add, change (chg), replace and delete hand the kernel an address,
; flush deletes those the filter keeps, the rest list
(def %ip-addr
  (fn (_ f ws)
    (def k (if (null? ws) 5 (ip-keyword (list "add" "change" "chg" "replace" "delete" "list" "show" "lst" "flush") (first ws))))
    (match
      ((< k 0) (ip-invarg f (first ws) (ip-get f (lit name))))
      ((<= k 4) (ip-modify f (if (= k 4) 21 20) (cu-nth k (list 1536 256 256 1280 0)) (rest ws)))
      ((= k 8) (ip-flush f (rest ws)))
      (#t (ip-list f (if (null? ws) () (rest ws)))))))

; do_iplink: its errors end the run with 2, a link-layer address it cannot read with 1
(def %ip-link
  (fn (_ f ws)
    (guard (e (match ((eq? (cu-err-label e) (lit ip)) 2)
                     ((eq? (cu-err-label e) (lit ip-exit1)) 1)
                     (#t (error e))))
      (let ((k (if (null? ws) 3 (ip-keyword (list "add" "delete" "set" "show" "lst" "list") (first ws)))))
        (match
          ((< k 0) (ip-invarg f (first ws) (ip-get f (lit name))))
          ((<= k 1) (ip-add-link f (rest ws) (if (= k 0) 16 17)))
          ((= k 2) (ip-set f (rest ws)))
          (#t (ip-list (ip-put f (lit preferred) 17) (if (null? ws) () (rest ws)))))))))

; ip_main's keywords
(def %ip-main
  (fn (_ f ws)
    (def k (if (null? ws) -1 (ip-keyword (list "address" "route" "r" "link" "tunnel" "tunl" "rule" "neigh") (first ws))))
    (match
      ((< k 0) (ip-die-usage))
      ((= k 0) (%ip-addr f (rest ws)))
      ((if (= k 1) #t (= k 2)) (ip-route f (rest ws)))
      ((= k 3) (%ip-link f (rest ws)))
      ((if (= k 4) #t (= k 5)) (ip-tunnel f (rest ws)))
      ((= k 6) (ip-rule f (rest ws)))
      (#t (ip-neigh f (rest ws))))))

(def cu-ip (fn (_ argv stdin-thunk) (ip-run "ip" argv %ip-main)))

(def cu-ipaddr (fn (_ argv stdin-thunk) (ip-run "ipaddr" argv %ip-addr)))

(def cu-iplink (fn (_ argv stdin-thunk) (ip-run "iplink" argv %ip-link)))

(provide cu/ip-main cu-ip cu-ipaddr cu-iplink)

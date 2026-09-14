; # x-coreutils -- the small tools, as applets
;
; ## cu/walk.x -- the one directory walk
;
; @description Listing a directory, descending it, and folding what the
;   descent answered -- one walk, shared by the seven applets that need it.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; The dot-filter, the worst-status fold, and the two-tree step-descent (cp and
; diff) each appeared in several files; collected here so they cannot drift a
; copy at a time.
;
; The order is sorted, and that is a change: file-list-dir answers in the
; filesystem's order, so `rm -r` and `chmod -R` visit in whatever order it
; keeps (fine, since they touch every entry) but a report needs determinism.
; Sorting here costs a sort per directory and removes a class of "works on my
; filesystem" from the suite.

; The entries of DIR worth walking: no . or .., in sorted order.
(def %cu-walk-names
  (fn (_ dir)
    (%cu-msort
      (filter (fn (_ n) (not (%cu-dot? n))) (file-list-dir dir))
      %cu-str<)))

; Visit each entry of DIR and answer the WORST status any visit gave.
; The visitor takes the NAME, not the path: every caller joins it to a
; different root, and half of them join it to two.
(def %cu-walk-status
  (fn (_ dir visit)
    (def go
      (fn (self ns st)
        (if (null? ns) st
          (let ((r (visit (first ns))))
            (self (rest ns) (if (> r st) r st))))))
    (go (%cu-walk-names dir) 0)))

; Two trees in step: every name either side holds, once, in order, with which
; sides hold it. The visitor takes (NAME IN-A? IN-B?) and answers a status; the
; worst comes back. START, when not nil, is the name to begin at (entries sorted
; before it are skipped), and applies to this directory only: a caller that
; descends passes nil on the way down.
(def %cu-walk-pair
  (fn (_ a b start visit)
    (def from
      (fn (_ ns)
        (if (null? start) ns
          (let ((go (fn (self l)
                      (if (null? l) ()
                        (if (%cu-str< (first l) start) (self (rest l)) l)))))
            (go ns)))))
    (def go
      (fn (self as bs st)
        (if (if (null? as) (null? bs) #f)
          st
          (let ((n (match
                     ((null? as) (first bs))
                     ((null? bs) (first as))
                     ((%cu-str< (first as) (first bs)) (first as))
                     (#t (first bs)))))
            (let ((ina (if (null? as) #f (string=? (first as) n)))
                  (inb (if (null? bs) #f (string=? (first bs) n))))
              (let ((r (visit n ina inb)))
                (self (if ina (rest as) as)
                      (if inb (rest bs) bs)
                      (if (> r st) r st))))))))
    (go (from (%cu-walk-names a)) (from (%cu-walk-names b)) 0)))

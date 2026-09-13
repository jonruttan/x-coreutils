; # x-coreutils -- the small tools, as applets
;
; ## cu/walk.x -- the one directory walk
;
; @description Listing a directory, descending it, and folding what the
;   descent answered.  Seven applets did this, each its own way.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; ## WHAT WAS DUPLICATED
;
; `(filter (fn (_ n) (not (%cu-dot? n))) (file-list-dir path))` appeared
; five times, verbatim, in four files.  The fold that walks those names
; and keeps the WORST status appeared four times.  cp and diff both
; descend TWO trees in step, and wrote that twice.  None of it is hard;
; all of it is the kind of thing that drifts one copy at a time, which is
; how this bundle's option readers drifted before %cu-opts collected
; them.
;
; ## THE ORDER IS SORTED, AND THAT IS A CHANGE
;
; file-list-dir answers in whatever order the filesystem keeps, so `rm
; -r` and `chmod -R` used to visit in an order nobody chose and nobody
; could predict -- fine for them, since they touch every entry anyway,
; and NOT fine for a report.  diff names files in sorted order because
; its output is read by people.  Sorting here gives every caller the
; deterministic order, which costs a sort per directory and removes a
; class of "works on my filesystem" from the suite.

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

; TWO TREES IN STEP: every name either side holds, once, in order, with
; which sides hold it.  The visitor takes (NAME IN-A? IN-B?) and answers
; a status; the worst comes back.
;
; START, when it is not nil, is the name to begin at -- entries sorted
; before it are not visited.  It applies to THIS directory: a caller that
; descends passes nil on the way down, because a place named in one
; directory is not a place in the next.
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
          (let ((n (if (null? as) (first bs)
                    (if (null? bs) (first as)
                      (if (%cu-str< (first as) (first bs))
                        (first as) (first bs))))))
            (let ((ina (if (null? as) #f (string=? (first as) n)))
                  (inb (if (null? bs) #f (string=? (first bs) n))))
              (let ((r (visit n ina inb)))
                (self (if ina (rest as) as)
                      (if inb (rest bs) bs)
                      (if (> r st) r st))))))))
    (go (from (%cu-walk-names a)) (from (%cu-walk-names b)) 0)))

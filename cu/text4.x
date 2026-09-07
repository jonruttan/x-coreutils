; # x-coreutils -- the small tools, as applets
;
; ## cu/text4.x -- uniq and nl, with busybox's option sets
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox: uniq [-cduifsw], nl [-bnswvi].  Both turn on a COMPARISON
; or a FORMAT that the flags assemble, so both read their options
; through %cu-flag-value, which takes `-w3` and `-w 3` alike.

; --- uniq ---------------------------------------------------------------------

; what uniq actually compares: the line past -f fields and -s chars,
; cut to -w, folded when -i asks
(def %uniq-key
  (fn (_ line argv)
    (def skip-f (let ((v (%cu-flag-value argv "-f")))
                  (if (null? v) 0 (%cu-num-prefix v))))
    (def skip-s (let ((v (%cu-flag-value argv "-s")))
                  (if (null? v) 0 (%cu-num-prefix v))))
    (def width (let ((v (%cu-flag-value argv "-w")))
                 (if (null? v) (- 0 1) (%cu-num-prefix v))))
    (def after-fields
      (if (= skip-f 0) line
        (let ((fs (%cu-words-line line)))
          (%cu-join-with
            (let ((go (fn (self xs i acc)
                        (if (null? xs) (reverse acc)
                          (self (rest xs) (+ i 1)
                            (if (> i skip-f) (pair (first xs) acc) acc))))))
              (go fs 1 ()))
            " "))))
    (def end (byte-len after-fields))
    (def from (if (> skip-s end) end skip-s))
    (def cut (substring after-fields from end))
    (def sized (if (< width 0) cut
                 (if (> width (byte-len cut)) cut (substring cut 0 width))))
    (if (%cu-has-flag? argv "-i") (%sort-fold sized) sized)))

; -d prints only what repeated, -u only what did not; neither is both
(def %uniq-show?
  (fn (_ n argv)
    (if (%cu-has-flag? argv "-d") (> n 1)
      (if (%cu-has-flag? argv "-u") (= n 1) #t))))

(def %cu-uniq
  (fn (_ argv stdin-thunk)
    (def count? (%cu-has-flag? argv "-c"))
    (def ops (%cu-value-operands argv (list "-f" "-s" "-w")))
    (def lines (%cu-lines (%cu-gather ops stdin-thunk)))
    (def emit
      (fn (_ n line)
        (if (not (%uniq-show? n argv)) ()
          (display
            (if count?
              (string-concat
                (list (%cu-pad-left (%cu-int->str n) 4) " " line "\n"))
              (string-append line "\n"))))))
    (def go
      (fn (self ls cur key n)
        (if (null? ls)
          (if (null? cur) () (emit n cur))
          (let ((k (%uniq-key (first ls) argv)))
            (if (if (null? cur) #f (string=? k key))
              (self (rest ls) cur key (+ n 1))
              (do (if (null? cur) () (emit n cur))
                  (self (rest ls) (first ls) k 1)))))))
    (do (go lines () "" 0) 0)))

; --- nl -----------------------------------------------------------------------

; -b a numbers every line, t only the non-empty (the default), n none
(def %nl-number?
  (fn (_ line argv)
    (def style (let ((v (%cu-flag-value argv "-b"))) (if (null? v) "t" v)))
    (if (string=? style "a") #t
      (if (string=? style "n") #f
        (> (byte-len line) 0)))))

; -n ln left, rn right (the default), rz right with zeros
(def %nl-format
  (fn (_ n argv)
    (def width (let ((v (%cu-flag-value argv "-w")))
                 (if (null? v) 6 (%cu-num-prefix v))))
    (def style (let ((v (%cu-flag-value argv "-n"))) (if (null? v) "rn" v)))
    (def s (%cu-int->str n))
    (if (string=? style "ln") (%cu-pad s width #t)
      (if (string=? style "rz") (%cu-pad-zero s width)
        (%cu-pad-left s width)))))

(def %cu-nl
  (fn (_ argv stdin-thunk)
    (def sep (let ((v (%cu-flag-value argv "-s"))) (if (null? v) "\t" v)))
    (def start (let ((v (%cu-flag-value argv "-v")))
                 (if (null? v) 1 (%cu-num-prefix v))))
    (def step (let ((v (%cu-flag-value argv "-i")))
                (if (null? v) 1 (%cu-num-prefix v))))
    (def width (let ((v (%cu-flag-value argv "-w")))
                 (if (null? v) 6 (%cu-num-prefix v))))
    (def ops (%cu-value-operands argv (list "-b" "-n" "-s" "-w" "-v" "-i")))
    (def blank (let ((go (fn (self k acc)
                           (if (<= k 0) acc (self (- k 1) (string-append " " acc))))))
                 (go width "")))
    (def go
      (fn (self ls n)
        (if (null? ls) 0
          (if (%nl-number? (first ls) argv)
            (do (display
                  (string-concat
                    (list (%nl-format n argv) sep (first ls) "\n")))
                (self (rest ls) (+ n step)))
            (do (display (string-concat (list blank sep (first ls) "\n")))
                (self (rest ls) n))))))
    (go (%cu-lines (%cu-gather ops stdin-thunk)) start)))

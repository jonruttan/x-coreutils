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
  (fn (_ line o)
    (def skip-f (let ((v (Opts value o "-f")))
                  (if (null? v) 0 (%cu-num-prefix v))))
    (def skip-s (let ((v (Opts value o "-s")))
                  (if (null? v) 0 (%cu-num-prefix v))))
    (def width (let ((v (Opts value o "-w")))
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
    (if (Opts on? o "-i") (%sort-fold sized) sized)))

; -d prints only what repeated, -u only what did not; neither is both
(def %uniq-show?
  (fn (_ n o)
    (if (Opts on? o "-d") (> n 1)
      (if (Opts on? o "-u") (= n 1) #t))))

(def %cu-uniq
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "uniq" argv))
    (def count? (Opts on? o "-c"))
    (def ops (Opts operands o))
    (def lines (%cu-lines (%cu-gather ops stdin-thunk)))
    (def emit
      (fn (_ n line)
        (if (not (%uniq-show? n o)) ()
          (display
            (if count?
              (string-concat
                (list (%cu-pad-left (%cu-int->str n) 4) " " line "\n"))
              (string-append line "\n"))))))
    (def go
      (fn (self ls cur key n)
        (if (null? ls)
          (if (null? cur) () (emit n cur))
          (let ((k (%uniq-key (first ls) o)))
            (if (if (null? cur) #f (string=? k key))
              (self (rest ls) cur key (+ n 1))
              (do (if (null? cur) () (emit n cur))
                  (self (rest ls) (first ls) k 1)))))))
    (do (go lines () "" 0) 0)))

; --- nl -----------------------------------------------------------------------

; -b a numbers every line, t only the non-empty (the default), n none
(def %nl-number?
  (fn (_ line o)
    (def style (let ((v (Opts value o "-b"))) (if (null? v) "t" v)))
    (if (string=? style "a") #t
      (if (string=? style "n") #f
        (> (byte-len line) 0)))))

; -n ln left, rn right (the default), rz right with zeros
(def %nl-format
  (fn (_ n o)
    (def width (let ((v (Opts value o "-w")))
                 (if (null? v) 6 (%cu-num-prefix v))))
    (def style (let ((v (Opts value o "-n"))) (if (null? v) "rn" v)))
    (def s (%cu-int->str n))
    (if (string=? style "ln") (%cu-pad s width #t)
      (if (string=? style "rz") (%cu-pad-zero s width)
        (%cu-pad-left s width)))))

(def %cu-nl
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "nl" argv))
    (def sep (let ((v (Opts value o "-s"))) (if (null? v) "\t" v)))
    (def start (let ((v (Opts value o "-v")))
                 (if (null? v) 1 (%cu-num-prefix v))))
    (def step (let ((v (Opts value o "-i")))
                (if (null? v) 1 (%cu-num-prefix v))))
    (def width (let ((v (Opts value o "-w")))
                 (if (null? v) 6 (%cu-num-prefix v))))
    (def ops (Opts operands o))
    (def blank (let ((go (fn (self k acc)
                           (if (<= k 0) acc (self (- k 1) (string-append " " acc))))))
                 (go width "")))
    (def go
      (fn (self ls n)
        (if (null? ls) 0
          (if (%nl-number? (first ls) o)
            (do (display
                  (string-concat
                    (list (%nl-format n o) sep (first ls) "\n")))
                (self (rest ls) (+ n step)))
            (do (display (string-concat (list blank sep (first ls) "\n")))
                (self (rest ls) n))))))
    (go (%cu-lines (%cu-gather ops stdin-thunk)) start)))

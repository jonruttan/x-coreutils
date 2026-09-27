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

; What uniq compares a line by, made once from the options: the line past -f
; fields and -s chars, cut to -w, folded when -i asks.  The options are read
; here and not per line -- each read costs thousands of objects, and nothing
; is collected while an applet runs.
(def %uniq-key
  (fn (_ o)
    (def skip-f (let ((v (Opts value o "-f")))
                  (if (null? v) 0 (%cu-num-prefix v))))
    (def skip-s (let ((v (Opts value o "-s")))
                  (if (null? v) 0 (%cu-num-prefix v))))
    (def width (let ((v (Opts value o "-w")))
                 (if (null? v) (- 0 1) (%cu-num-prefix v))))
    (def fold? (Opts on? o "-i"))
    (fn (_ line)
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
      (def cut (if (= from 0) after-fields (substring after-fields from end)))
      (def sized (if (< width 0) cut
                   (if (> width (byte-len cut)) cut (substring cut 0 width))))
      (if fold? (%sort-fold sized) sized))))

; -d prints only what repeated, -u only what did not; neither is both
(def %uniq-show?
  (fn (_ n dups? singles?)
    (if dups? (> n 1)
      (if singles? (= n 1) #t))))

; uniq [IN [OUT]]: IN, or standard input where there is none or it is `-`, and
; OUT, or standard output likewise.  A third operand is refused before anything
; opens.  IN is opened before OUT, as uniq opens them, so an IN that will not
; open leaves OUT uncreated; OUT is truncated before IN is read, so the same
; file for both comes out empty.
(def %cu-uniq
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "uniq" argv))
    (def ops (Opts operands o))
    (match
      ((> (length ops) 2)
        (do (file-write 2
              (string-concat (list "uniq: extra operand '" (%cu-nth 2 ops) "'\n")))
            1))
      ((null? ops) (%uniq-into o "-" "-" stdin-thunk))
      ((null? (rest ops)) (%uniq-into o (first ops) "-" stdin-thunk))
      (#t (%uniq-into o (first ops) (%cu-nth 1 ops) stdin-thunk)))))

; a file that opened and would not read is "error reading" to uniq
(def %uniq-says
  (%cu-says-read "uniq"
    (fn (_ name err)
      (string-concat
        (list "uniq: error reading '" name "': " (file-err-text err))))))

; IN checked, OUT opened, then IN read a block of whole lines at a time and its
; runs written to OUT as they end
(def %uniq-into
  (fn (_ o in out stdin-thunk)
    (let ((shut (%cu-first-unopened (list in) %uniq-says)))
      (if (Err err? shut) 1
        (let ((fd (if (string=? out "-") 1 (file-open-or-err file-open-write out))))
          (if (Err err? fd)
            (do (%cu-say (%cu-says "uniq") out fd) 1)
            (let ((runs (%uniq-runs o fd)))
              (let ((r (%cu-fold-lines-said (list in) stdin-thunk %uniq-says
                         (first runs) (list () "" 0 0))))
                (do ((rest runs) (first r))
                    (if (= fd 1) () (file-close fd))
                    (rest r))))))))))

; The runs of the lines that the flags keep, each once, to FD -- under -c after
; its count, right-aligned in seven columns and wider when it needs to be.
; Answers (EACH . END): EACH takes a block of whole lines with the state (CUR
; KEY N I) -- the current run's line, its key and its count, and the lines
; walked, for the sweeps -- and END writes the run the last block left open.
(def %uniq-runs
  (fn (_ o fd)
    (def count? (Opts on? o "-c"))
    (def dups? (Opts on? o "-d"))
    (def singles? (Opts on? o "-u"))
    (def key-of (%uniq-key o))
    (def emit
      (fn (_ n line)
        (if (not (%uniq-show? n dups? singles?)) ()
          (file-write fd
            (if count?
              (string-concat
                (list (%cu-pad-left (%cu-int->str n) 7) " " line "\n"))
              (string-append line "\n"))))))
    (def go
      (fn (self ls cur key n i)
        (if (null? ls) (list cur key n i)
          (let ((k (do (%cu-sweep-at i %cu-sweep-lines) (key-of (first ls)))))
            (if (if (null? cur) #f (string=? k key))
              (self (rest ls) cur key (+ n 1) (+ i 1))
              (do (if (null? cur) () (emit n cur))
                  (self (rest ls) (first ls) k 1 (+ i 1))))))))
    (pair
      (fn (_ block s)
        (go (%cu-lines block) (first s) (%cu-nth 1 s) (%cu-nth 2 s) (%cu-nth 3 s)))
      (fn (_ s) (if (null? (first s)) () (emit (%cu-nth 2 s) (first s)))))))

; --- nl -----------------------------------------------------------------------

; Which lines -b numbers, chosen once from its STYLE: a every line, t only the
; non-empty (the default), n none.  nl reads its options once, not per line --
; each read costs thousands of objects, and nothing is collected while an
; applet runs.
(def %nl-number?
  (fn (_ style)
    (match
      ((string=? style "a") (fn (_ line) #t))
      ((string=? style "n") (fn (_ line) #f))
      (#t (fn (_ line) (> (byte-len line) 0))))))

; How -n lays a number out in WIDTH columns, chosen once from its STYLE: ln
; left, rn right (the default), rz right with zeros
(def %nl-format
  (fn (_ style width)
    (match
      ((string=? style "ln") (fn (_ n) (%cu-pad (%cu-int->str n) width #t)))
      ((string=? style "rz") (fn (_ n) (%cu-pad-zero (%cu-int->str n) width)))
      (#t (fn (_ n) (%cu-pad-left (%cu-int->str n) width))))))

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
    (def numbered? (%nl-number? (let ((v (Opts value o "-b"))) (if (null? v) "t" v))))
    (def layout (%nl-format (let ((v (Opts value o "-n"))) (if (null? v) "rn" v)) width))
    (def ops (Opts operands o))
    (def blank (let ((go (fn (self k acc)
                           (if (<= k 0) acc (self (- k 1) (string-append " " acc))))))
                 (go width "")))
    ; N is the next number, I the lines walked, for the sweeps; answers the
    ; number the line after LS takes
    (def go
      (fn (self ls n i)
        (if (null? ls) n
          (do (%cu-sweep-at i %cu-sweep-lines)
            (if (numbered? (first ls))
              (do (display
                    (string-concat
                      (list (layout n) sep (first ls) "\n")))
                  (self (rest ls) (+ n step) (+ i 1)))
              (do (display (string-concat (list blank sep (first ls) "\n")))
                  (self (rest ls) n (+ i 1))))))))
    ; each block of whole lines numbered and put out as it is read, the
    ; numbering going on from one block to the next
    (rest
      (%cu-fold-lines-said ops stdin-thunk (%cu-says "nl")
        (fn (_ block n) (go (%cu-lines block) n 0))
        start))))

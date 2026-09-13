; # x-coreutils -- the small tools, as applets
;
; ## cu/diff.x -- diff, normal format
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Line-based LCS by dynamic programming over a Vector (O(n*m) -- honest
; at tool scale), backtracked from the front into hunks, printed in the
; NORMAL format: XdY, XaY, XcY with < --- > bodies.  Status 0 same,
; 1 different.

; TWO OF THESE FLAGS DO NOTHING, AND THAT IS THE CORRECT BEHAVIOUR.
;
;   -a  "treat all files as text".  The alternative it turns off is
;       binary detection -- GNU answers "Binary files A and B differ"
;       and compares nothing.  This diff has no such mode: it is always
;       line-based, which is exactly what -a asks for.  Accepting it and
;       behaving identically HONOURS it; that is not the same defect as
;       accepting a flag whose behaviour would differ.
;   -d  "try hard to find a smaller set of changes".  The LCS below is
;       already minimal by construction, so there is no larger answer to
;       try harder than.
;
; The seven still missing -- -r -N -S -T -t -U -L -- are the directory
; walk and the unified format, and they are not declared until they are
; read.
;
; --- what counts as the same line ---------------------------------------------
;
; -i, -b and -w do not change what is PRINTED, only what is COMPARED, so
; every line is carried twice: once as it reads, once normalised.  The
; LCS and the walk run on the normalised copy and the hunks quote the
; original, which is what diff has always done and the only arrangement
; that can show a case change while ignoring it.

(def %cu-diff-lc
  (fn (_ b) (if (if (>= b 65) (<= b 90) #f) (+ b 32) b)))

(def %cu-diff-space?
  (fn (_ b) (if (= b 32) #t (= b 9))))

; One character of LINE as a string, lowered when it is an ASCII capital.
; The table is a substring of a literal rather than a byte->string door,
; which this bundle does not have and does not need one of for this.
(def %cu-diff-lower-alpha "abcdefghijklmnopqrstuvwxyz")
(def %cu-diff-lc-str
  (fn (_ line i)
    (let ((b (byte-at line i)))
      (if (if (>= b 65) (<= b 90) #f)
        (substring %cu-diff-lower-alpha (- b 65) (- b 64))
        (substring line i (+ i 1))))))

; -w drops every space and tab; -b keeps ONE for any run of them and
; drops those at the ends, which is the difference between "all
; whitespace" and "changes in the amount of it".
(def %cu-diff-norm
  (fn (_ line fold-case? squeeze? strip?)
    (def end (byte-len line))
    (def go
      (fn (self i acc gap?)
        (if (>= i end)
          acc
          (let ((raw (byte-at line i)))
            (if (%cu-diff-space? raw)
                (if strip?
                  (self (+ i 1) acc gap?)
                  (if squeeze?
                    (self (+ i 1) acc (> (byte-len acc) 0))
                    (self (+ i 1) (string-append acc (substring line i (+ i 1)))
                      #f)))
              (self (+ i 1)
                (string-append (if gap? (string-append acc " ") acc)
                  (if fold-case?
                    (%cu-diff-lc-str line i)
                    (substring line i (+ i 1))))
                #f))))))
    ; no flag asked for anything: the line IS its own normal form, and
    ; walking it would only cost a copy per line of both files.
    (if (if fold-case? #t (if squeeze? #t strip?))
      (go 0 "" #f)
      line)))

(def %cu-diff-lcs
  (fn (_ av bv n m)
    ; lcs[i][j] = LCS of a[i..], b[j..]; filled bottom-up
    (def t (vec-make (* (+ n 1) (+ m 1)) 0))
    (def at (fn (_ i j) (vec-ref t (+ (* i (+ m 1)) j))))
    (def put (fn (_ i j v) (vec-set! t (+ (* i (+ m 1)) j) v)))
    (def fill-row
      (fn (self i j)
        (if (< j 0) ()
          (do (put i j
                (if (string=? (vec-ref av i) (vec-ref bv j))
                  (+ 1 (at (+ i 1) (+ j 1)))
                  (let ((d (at (+ i 1) j)))
                    (def r (at i (+ j 1)))
                    (if (> d r) d r))))
              (self i (- j 1))))))
    (def fill
      (fn (self i)
        (if (< i 0) ()
          (do (fill-row i (- m 1)) (self (- i 1))))))
    (do (fill (- n 1)) t)))

(def %cu-range
  (fn (_ lo hi)
    (if (= lo hi) (%cu-int->str lo)
      (string-append (%cu-int->str lo)
        (string-append "," (%cu-int->str hi))))))

; a hunk to its NORMAL-format text; building a string (not displaying)
; keeps it spec-able -- the runner strips a literal "> " prompt from
; captured stdout, so diff's real output can only be asserted quoted
(def %cu-diff-emit
  (fn (_ dels adds i j)
    (def nd (length dels))
    (def na (length adds))
    (def show
      (fn (self ls mark acc)
        (if (null? ls) acc
          (self (rest ls) mark
            (pair (string-append mark
                    (string-append (first ls) "\n"))
              acc)))))
    (if (= na 0)
      (string-concat
        (reverse
          (show dels "< "
            (list (string-append (%cu-range i (+ i (- nd 1)))
                    (string-append "d"
                      (string-append (%cu-int->str (- j 1)) "\n")))))))
      (if (= nd 0)
        (string-concat
          (reverse
            (show adds "> "
              (list (string-append (%cu-int->str (- i 1))
                      (string-append "a"
                        (string-append (%cu-range j (+ j (- na 1)))
                          "\n")))))))
        (string-concat
          (reverse
            (show adds "> "
              (pair "---\n"
                (show dels "< "
                  (list (string-append (%cu-range i (+ i (- nd 1)))
                          (string-append "c"
                            (string-append (%cu-range j (+ j (- na 1)))
                              "\n"))))))))))))))

(def %cu-diff-str
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "diff" argv))
    (def ops (Opts operands o))
    (def fold? (Opts on? o "-i"))
    (def squeeze? (Opts on? o "-b"))
    (def strip? (Opts on? o "-w"))
    (def blanks? (Opts on? o "-B"))
    (def norm
      (fn (_ line) (%cu-diff-norm line fold? squeeze? strip?)))
    (def read-op
      (fn (_ op) (if (string=? op "-") (stdin-thunk)
                   (file-read-all op))))
    (def a (%cu-lines (read-op (first ops))))
    (def b (%cu-lines (read-op (first (rest ops)))))
    (def n (length a))
    (def m (length b))
    (def av (vec-make (+ n 1) ""))
    (def bv (vec-make (+ m 1) ""))
    (def avn (vec-make (+ n 1) ""))
    (def bvn (vec-make (+ m 1) ""))
    (def load!
      (fn (self v vn ls i)
        (if (null? ls) ()
          (do (vec-set! v i (first ls))
              (vec-set! vn i (norm (first ls)))
              (self v vn (rest ls) (+ i 1))))))
    (load! av avn a 0)
    (load! bv bvn b 0)
    ; THE LCS RUNS ON THE NORMALISED COPY, the hunks quote the original.
    (def t (%cu-diff-lcs avn bvn n m))
    (def at (fn (_ i j) (vec-ref t (+ (* i (+ m 1)) j))))
    ; -B: a hunk whose every line is blank is not a change.  Blankness is
    ; read AFTER normalising, so a line of spaces is blank under -w.
    (def all-blank?
      (fn (self ls)
        (if (null? ls) #t
          (if (= (byte-len (norm (first ls))) 0)
            (self (rest ls))
            #f))))
    (def skip?
      (fn (_ dels adds)
        (if blanks?
          (if (all-blank? dels) (all-blank? adds) #f)
          #f)))
    ; the walk: collect a hunk's dels and adds, flush the emit string at
    ; each resync into acc; answers (output-string . status)
    (def flush
      (fn (_ dels adds hi hj acc)
        (if (if (null? dels) (null? adds) #f) acc
          (if (skip? dels adds) acc
            (pair (%cu-diff-emit (reverse dels) (reverse adds) hi hj) acc)))))
    (def counts?
      (fn (_ dels adds)
        (if (if (null? dels) (null? adds) #f) #f
          (not (skip? dels adds)))))
    (def walk
      (fn (self i j dels adds hi hj changed acc)
        (if (if (>= i n) (>= j m) #f)
          (pair (string-concat (reverse (flush dels adds hi hj acc)))
            (if changed 1 (if (counts? dels adds) 1 0)))
          (if (if (< i n) (< j m) #f)
            (if (string=? (vec-ref avn i) (vec-ref bvn j))
              (self (+ i 1) (+ j 1) () () (+ i 2) (+ j 2)
                (if (counts? dels adds) #t changed)
                (flush dels adds hi hj acc))
              (if (>= (at (+ i 1) j) (at i (+ j 1)))
                (self (+ i 1) j (pair (vec-ref av i) dels) adds hi hj
                  changed acc)
                (self i (+ j 1) dels (pair (vec-ref bv j) adds) hi hj
                  changed acc)))
            (if (< i n)
              (self (+ i 1) j (pair (vec-ref av i) dels) adds hi hj
                changed acc)
              (self i (+ j 1) dels (pair (vec-ref bv j) adds) hi hj
                changed acc))))))
    (walk 0 0 () () 1 1 #f ())))

; The two names a report names.  "-" is stdin, and diff calls it that.
(def %cu-diff-pair-text
  (fn (_ ops verb)
    (string-append "Files "
      (string-append (first ops)
        (string-append " and "
          (string-append (first (rest ops))
            (string-append " " (string-append verb "\n"))))))))

; the applet: display the output, answer the status
(def %cu-diff
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "diff" argv))
    (def ops (Opts operands o))
    (def r (%cu-diff-str argv stdin-thunk))
    (def differ? (> (rest r) 0))
    ; -q and -s replace the body with one line about it; -q says nothing
    ; when the files match, which is why they are not one flag.
    (if (Opts on? o "-q")
      (do (if differ?
            (display (%cu-diff-pair-text ops "differ"))
            ())
          (rest r))
      (if (if (Opts on? o "-s") (not differ?) #f)
        (do (display (%cu-diff-pair-text ops "are identical")) 0)
        (do (display (first r)) (rest r))))))

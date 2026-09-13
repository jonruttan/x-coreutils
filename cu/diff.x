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

; --- the edit script, and the two ways to print it ---------------------------
;
; ONE WALK, TWO RENDERERS.  The walk answers a list of (TAG AI BI) in
; order -- eq, del or add, with the indices the op consumed -- and the
; normal and unified printers both read that.  Writing the second format
; as a second walk is how the two would drift.

(def %cu-diff-ops
  (fn (_ avn bvn n m at)
    (def go
      (fn (self i j acc)
        (if (if (>= i n) (>= j m) #f)
          (reverse acc)
          (if (if (< i n) (< j m) #f)
            (if (string=? (vec-ref avn i) (vec-ref bvn j))
              (self (+ i 1) (+ j 1) (pair (list (lit eq) i j) acc))
              (if (>= (at (+ i 1) j) (at i (+ j 1)))
                (self (+ i 1) j (pair (list (lit del) i j) acc))
                (self i (+ j 1) (pair (list (lit add) i j) acc))))
            (if (< i n)
              (self (+ i 1) j (pair (list (lit del) i j) acc))
              (self i (+ j 1) (pair (list (lit add) i j) acc)))))))
    (go 0 0 ())))

(def %cu-diff-tag (fn (_ op) (first op)))
(def %cu-diff-ai  (fn (_ op) (first (rest op))))
(def %cu-diff-bi  (fn (_ op) (first (rest (rest op)))))
(def %cu-diff-eq? (fn (_ op) (eq? (%cu-diff-tag op) (lit eq))))

; -t expands tabs to spaces on an eight-column stop; -T prefixes a tab so
; the marker does not shift the text.  Both shape the PRINTED line only.
(def %cu-diff-untab
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i col acc)
        (if (>= i end) acc
          (if (= (byte-at s i) 9)
            (let ((k (- 8 (% col 8))))
              (self (+ i 1) (+ col k)
                (string-append acc (%cu-diff-spaces k))))
            (self (+ i 1) (+ col 1)
              (string-append acc (substring s i (+ i 1))))))))
    (go 0 0 "")))

(def %cu-diff-spaces
  (fn (self k) (if (<= k 0) "" (string-append " " (self (- k 1))))))

(def %cu-diff-body
  (fn (_ s untab? tab?)
    (string-append (if tab? "\t" "")
      (if untab? (%cu-diff-untab s) s))))

; --- unified -----------------------------------------------------------------
;
; A HUNK IS A RUN OF CHANGES PLUS CTX LINES EITHER SIDE, and two runs
; close enough to share context become one hunk rather than two that
; overlap.  The header counts LINES, not ops: a hunk's a-count is its eq
; and del ops, its b-count is its eq and add ops.

(def %cu-diff-count
  (fn (self ops want-a?)
    (if (null? ops) 0
      (+ (if (%cu-diff-eq? (first ops)) 1
           (if (eq? (%cu-diff-tag (first ops))
                    (if want-a? (lit del) (lit add))) 1 0))
        (self (rest ops) want-a?)))))

(def %cu-diff-at-range
  (fn (_ start count)
    (if (= count 1)
      (%cu-int->str start)
      (string-append (%cu-int->str (if (= count 0) (- start 1) start))
        (string-append "," (%cu-int->str count))))))

(def %cu-diff-uni-hunk
  (fn (_ av bv hunk untab? tab?)
    (def ac (%cu-diff-count hunk #t))
    (def bc (%cu-diff-count hunk #f))
    (def astart (+ (%cu-diff-ai (first hunk)) 1))
    (def bstart (+ (%cu-diff-bi (first hunk)) 1))
    (def head
      (string-append "@@ -"
        (string-append (%cu-diff-at-range astart ac)
          (string-append " +"
            (string-append (%cu-diff-at-range bstart bc) " @@\n")))))
    (def go
      (fn (self ops acc)
        (if (null? ops) acc
          (let ((op (first ops)))
            (self (rest ops)
              (pair
                (match
                  ((%cu-diff-eq? op)
                    (string-append " "
                      (string-append
                        (%cu-diff-body (vec-ref av (%cu-diff-ai op)) untab? tab?)
                        "\n")))
                  ((eq? (%cu-diff-tag op) (lit del))
                    (string-append "-"
                      (string-append
                        (%cu-diff-body (vec-ref av (%cu-diff-ai op)) untab? tab?)
                        "\n")))
                  (#t
                    (string-append "+"
                      (string-append
                        (%cu-diff-body (vec-ref bv (%cu-diff-bi op)) untab? tab?)
                        "\n"))))
                acc))))))
    (string-concat (pair head (reverse (go hunk ()))))))

; THE HUNKS, by index rather than by accumulation.  Collect the ops that
; are real changes, group them -- two groups merge when the run of equal
; lines between them is no longer than the context either side would
; print anyway -- then take each group's span widened by CTX.
;
; The accumulating version of this got the lead-in BACKWARDS and split
; hunks the system merges; slicing an indexed vector cannot do either.
(def %cu-diff-hunks
  (fn (_ ops ctx change?)
    (def n (length ops))
    (def v (vec-make (+ n 1) ()))
    (def load!
      (fn (self l i)
        (if (null? l) ()
          (do (vec-set! v i (first l)) (self (rest l) (+ i 1))))))
    (load! ops 0)
    (def idx
      (let ((go (fn (self i acc)
                  (if (>= i n) (reverse acc)
                    (self (+ i 1)
                      (if (change? (vec-ref v i)) (pair i acc) acc))))))
        (go 0 ())))
    ; A gap of more than 2*CTX equal lines starts a new hunk.  The +1 is
    ; the step from one change op to the next: the ops BETWEEN them are
    ; one fewer than their distance.
    (def groups
      (let ((go (fn (self l cur acc)
                  (if (null? l)
                    (reverse (if (null? cur) acc (pair (reverse cur) acc)))
                    (if (null? cur)
                      (self (rest l) (list (first l)) acc)
                      (if (> (- (first l) (first cur)) (+ (* 2 ctx) 1))
                        (self (rest l) (list (first l)) (pair (reverse cur) acc))
                        (self (rest l) (pair (first l) cur) acc)))))))
        (go idx () ())))
    (def slice
      (fn (_ lo hi)
        (let ((go (fn (self i acc)
                    (if (> i hi) (reverse acc)
                      (self (+ i 1) (pair (vec-ref v i) acc))))))
          (go lo ()))))
    (map
      (fn (_ g)
        (let ((lo (let ((s (- (first g) ctx))) (if (< s 0) 0 s)))
              (hi (let ((e (+ (%cu-last g) ctx))) (if (>= e n) (- n 1) e))))
          (slice lo hi)))
      groups)))

(def %cu-diff-str
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "diff" argv))
    (def paths (Opts operands o))
    (def fold? (Opts on? o "-i"))
    (def squeeze? (Opts on? o "-b"))
    (def strip? (Opts on? o "-w"))
    (def blanks? (Opts on? o "-B"))
    (def untab? (Opts on? o "-t"))
    (def tab? (Opts on? o "-T"))
    (def uni (Opts value o "-U"))
    (def norm
      (fn (_ line) (%cu-diff-norm line fold? squeeze? strip?)))
    (def read-op
      (fn (_ op) (if (string=? op "-") (stdin-thunk)
                   (file-read-all op))))
    (def a (%cu-lines (read-op (first paths))))
    (def b (%cu-lines (read-op (first (rest paths)))))
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
    (def ops (%cu-diff-ops avn bvn n m at))
    ; -B: a change of nothing but blank lines is not a change.  Blankness
    ; is read AFTER normalising, so a line of spaces is blank under -w.
    (def blank-op?
      (fn (_ op)
        (= (byte-len
             (if (eq? (%cu-diff-tag op) (lit del))
               (vec-ref avn (%cu-diff-ai op))
               (vec-ref bvn (%cu-diff-bi op))))
           0)))
    (def change?
      (fn (_ op)
        (if (%cu-diff-eq? op) #f
          (if blanks? (not (blank-op? op)) #t))))
    (def any-change?
      (fn (self l)
        (if (null? l) #f
          (if (change? (first l)) #t (self (rest l))))))
    (def status (if (any-change? ops) 1 0))
    (if (null? uni)
      (pair (%cu-diff-normal av bv ops change? ) status)
      (let ((ctx (%cu-num-prefix uni)))
        (let ((hs (%cu-diff-hunks ops ctx change?)))
          (pair
            (if (= status 0) ""
              (string-append
                (%cu-diff-uni-head paths o)
                (string-concat
                  (map (fn (_ h) (%cu-diff-uni-hunk av bv h untab? tab?))
                    hs))))
            status))))))

; --- normal ------------------------------------------------------------------
;
; The same hunks the emitter always printed, read off the op list rather
; than collected during the walk.
(def %cu-diff-normal
  (fn (_ av bv ops change?)
    (def flush
      (fn (_ dels adds hi hj acc)
        (if (if (null? dels) (null? adds) #f) acc
          (pair (%cu-diff-emit (reverse dels) (reverse adds) hi hj) acc))))
    (def go
      (fn (self l dels adds hi hj acc)
        (if (null? l)
          (string-concat (reverse (flush dels adds hi hj acc)))
          (let ((op (first l)))
            (if (%cu-diff-eq? op)
              (self (rest l) () () (+ (%cu-diff-ai op) 2)
                (+ (%cu-diff-bi op) 2)
                (flush dels adds hi hj acc))
              (if (not (change? op))
                (self (rest l) dels adds hi hj acc)
                (if (eq? (%cu-diff-tag op) (lit del))
                  (self (rest l) (pair (vec-ref av (%cu-diff-ai op)) dels)
                    adds hi hj acc)
                  (self (rest l) dels
                    (pair (vec-ref bv (%cu-diff-bi op)) adds)
                    hi hj acc))))))))
    (go ops () () 1 1 ())))

; --- the unified header ------------------------------------------------------
;
; NO TIMESTAMP.  GNU and busybox write the file's mtime beside each name;
; this bundle has no clock a spec can pin, and patch reads a header
; without one.  -L replaces the name outright, which is what it is for --
; the first -L names the old file, the second the new.
(def %cu-diff-uni-head
  (fn (_ paths o)
    (def labels (Opts values o "-L"))
    ; THE LENGTH IS CHECKED FIRST, and not because it is tidier: (first
    ; ()) SEGFAULTS this engine, so %cu-nth past the end takes the whole
    ; process down rather than answering nil.  Filed as x-lang#688.
    (def pick
      (fn (_ k dflt)
        (if (> (length labels) k) (%cu-nth k labels) dflt)))
    (string-append "--- "
      (string-append (pick 0 (first paths))
        (string-append "\n+++ "
          (string-append (pick 1 (first (rest paths))) "\n"))))))

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

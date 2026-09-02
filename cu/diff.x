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
    (def read-op
      (fn (_ op) (if (string=? op "-") (stdin-thunk)
                   (file-read-all op))))
    (def a (%cu-lines (read-op (first argv))))
    (def b (%cu-lines (read-op (first (rest argv)))))
    (def n (length a))
    (def m (length b))
    (def av (vec-make (+ n 1) ""))
    (def bv (vec-make (+ m 1) ""))
    (def load!
      (fn (self v ls i)
        (if (null? ls) ()
          (do (vec-set! v i (first ls))
              (self v (rest ls) (+ i 1))))))
    (load! av a 0)
    (load! bv b 0)
    (def t (%cu-diff-lcs av bv n m))
    (def at (fn (_ i j) (vec-ref t (+ (* i (+ m 1)) j))))
    ; the walk: collect a hunk's dels and adds, flush the emit string at
    ; each resync into acc; answers (output-string . status)
    (def flush
      (fn (_ dels adds hi hj acc)
        (if (if (null? dels) (null? adds) #f) acc
          (pair (%cu-diff-emit (reverse dels) (reverse adds) hi hj) acc))))
    (def walk
      (fn (self i j dels adds hi hj changed acc)
        (if (if (>= i n) (>= j m) #f)
          (pair (string-concat (reverse (flush dels adds hi hj acc)))
            (if changed 1 (if (if (null? dels) (null? adds) #f) 0 1)))
          (if (if (< i n) (< j m) #f)
            (if (string=? (vec-ref av i) (vec-ref bv j))
              (self (+ i 1) (+ j 1) () () (+ i 2) (+ j 2)
                (if (if (null? dels) (null? adds) #f) changed #t)
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

; the applet: display the output, answer the status
(def %cu-diff
  (fn (_ argv stdin-thunk)
    (def r (%cu-diff-str argv stdin-thunk))
    (do (display (first r)) (rest r))))

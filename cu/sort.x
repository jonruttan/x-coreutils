; # x-coreutils -- the small tools, as applets
;
; ## cu/sort.x -- sort, with busybox's option set
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox: sort [-nrugMcszbdfiokt].  Everything but -z, which wants
; NUL-terminated lines: an x string ends at its first NUL, so a NUL
; separator cannot survive being read (the limit the README records
; for every byte-exact tool here).
;
; A sort is a COMPARISON built from flags, applied to a KEY drawn from
; each line.  -k names the key (F[.C][opts][,F[.C][opts]], 1-based) and
; -t the field separator; without -k the key is the whole line.  The
; ordering flags -b -d -f -i -n -g -M -r may ride the -k spec itself,
; where they apply to that key alone, or stand on the command line,
; where they apply to every key that names none of its own.

; --- the orderings ------------------------------------------------------------

(def %sort-blank? (fn (_ b) (if (= b 32) #t (= b 9))))

(def %sort-trim-left
  (fn (_ s)
    (def end (byte-len s))
    (def go (fn (self i)
              (if (>= i end) end
                (if (%sort-blank? (byte-at s i)) (self (+ i 1)) i))))
    (substring s (go 0) end)))

; -d keeps blanks and alphanumerics; -i keeps the printable bytes
(def %sort-filter
  (fn (_ s dict? print?)
    (if (if dict? #f (not print?)) s
      (let ((end (byte-len s)))
        (def keep?
          (fn (_ b)
            (if dict?
              (if (%sort-blank? b) #t
                (if (if (>= b 48) (<= b 57) #f) #t
                  (if (if (>= b 65) (<= b 90) #f) #t
                    (if (>= b 97) (<= b 122) #f))))
              (if (>= b 32) (< b 127) #f))))
        (def go (fn (self i acc)
                  (if (>= i end) (string-concat (reverse acc))
                    (self (+ i 1)
                      (if (keep? (byte-at s i))
                        (pair (%cu-b->s (byte-at s i)) acc) acc)))))
        (go 0 ())))))

(def %sort-fold
  (fn (_ s)
    (def end (byte-len s))
    (def go (fn (self i acc)
              (if (>= i end) (string-concat (reverse acc))
                (let ((b (byte-at s i)))
                  (self (+ i 1)
                    (pair (%cu-b->s (if (if (>= b 97) (<= b 122) #f) (- b 32) b))
                      acc))))))
    (go 0 ())))

; -g: a decimal, scaled to six places so the compare stays integral --
; there are no floats to rely on in this dialect
(def %sort-general
  (fn (_ s)
    (def t (%sort-trim-left s))
    (def end (byte-len t))
    (def neg (if (> end 0) (= (byte-at t 0) 45) #f))
    (def start (if (> end 0) (if (if neg #t (= (byte-at t 0) 43)) 1 0) 0))
    (def whole
      (let ((go (fn (self i acc)
                  (if (>= i end) (pair acc i)
                    (let ((b (byte-at t i)))
                      (if (if (>= b 48) (<= b 57) #f)
                        (self (+ i 1) (+ (* acc 10) (- b 48)))
                        (pair acc i)))))))
        (go start 0)))
    (def frac
      (if (>= (rest whole) end) 0
        (if (not (= (byte-at t (rest whole)) 46)) 0
          (let ((go (fn (self i k acc)
                      (if (>= k 6) acc
                        (if (>= i end) (self i (+ k 1) (* acc 10))
                          (let ((b (byte-at t i)))
                            (if (if (>= b 48) (<= b 57) #f)
                              (self (+ i 1) (+ k 1) (+ (* acc 10) (- b 48)))
                              (self i (+ k 1) (* acc 10)))))))))
            (go (+ (rest whole) 1) 0 0)))))
    (let ((v (+ (* (first whole) 1000000) frac)))
      (if neg (- 0 v) v))))

(def %sort-months
  (list "JAN" "FEB" "MAR" "APR" "MAY" "JUN"
        "JUL" "AUG" "SEP" "OCT" "NOV" "DEC"))

(def %sort-month
  (fn (_ s)
    (def t (%sort-fold (%sort-trim-left s)))
    (if (< (byte-len t) 3) 0
      (let ((head (substring t 0 3)))
        (def go (fn (self ms n)
                  (if (null? ms) 0
                    (if (string=? (first ms) head) n (self (rest ms) (+ n 1))))))
        (go %sort-months 1)))))

; --- keys ---------------------------------------------------------------------
;
; A key spec is (SF SC EF EC OPTS): start field and char, end field and
; char (0 meaning "to the end"), and the ordering letters that ride it.

(def %sort-fields
  (fn (_ line sep)
    (if (null? sep) (%cu-words-line line)
      (%cu-split-byte line (byte-at sep 0)))))

; join fields SF..EF, then take chars SC..EC of that
(def %sort-key
  (fn (_ line spec sep)
    (if (null? spec) line
      (let ((fs (%sort-fields line sep)))
        (def n (length fs))
        (def sf (%cu-nth 0 spec))
        (def ef (let ((e (%cu-nth 2 spec))) (if (= e 0) n e)))
        (def picked
          (let ((go (fn (self xs i acc)
                      (if (null? xs) (reverse acc)
                        (self (rest xs) (+ i 1)
                          (if (if (>= i sf) (<= i ef) #f)
                            (pair (first xs) acc) acc))))))
            (go fs 1 ())))
        (def joined (%cu-join-with picked (if (null? sep) " " sep)))
        (def end (byte-len joined))
        (def from (let ((c (%cu-nth 1 spec))) (if (> c 0) (- c 1) 0)))
        (def to (let ((c (%cu-nth 3 spec))) (if (= c 0) end (if (> c end) end c))))
        (if (>= from end) ""
          (substring joined from (if (< to from) from to)))))))

; F[.C][opts] -- answers (FIELD CHAR OPTS)
(def %sort-part
  (fn (_ s)
    (def end (byte-len s))
    (def num (fn (_ i)
               (let ((go (fn (self j acc)
                           (if (>= j end) (pair acc j)
                             (let ((b (byte-at s j)))
                               (if (if (>= b 48) (<= b 57) #f)
                                 (self (+ j 1) (+ (* acc 10) (- b 48)))
                                 (pair acc j)))))))
                 (go i 0))))
    (def f (num 0))
    (def c (if (>= (rest f) end) (pair 0 (rest f))
             (if (= (byte-at s (rest f)) 46) (num (+ (rest f) 1))
               (pair 0 (rest f)))))
    (list (first f) (first c) (substring s (rest c) end))))

(def %sort-spec
  (fn (_ keydef)
    (if (null? keydef) ()
      (let ((halves (%cu-split-byte keydef 44)))            ; ,
        (def a (%sort-part (first halves)))
        (def b (if (null? (rest halves)) (list 0 0 "")
                 (%sort-part (first (rest halves)))))
        (list (%cu-nth 0 a) (%cu-nth 1 a) (%cu-nth 0 b) (%cu-nth 1 b)
              (string-append (%cu-nth 2 a) (%cu-nth 2 b)))))))

; --- the comparison -----------------------------------------------------------

(def %sort-opt?
  (fn (_ o spec letter)
    (if (Opts on? o letter) #t
      (if (null? spec) #f
        (let ((opts (%cu-nth 4 spec)))
          (let ((go (fn (self i)
                      (if (>= i (byte-len opts)) #f
                        (if (= (byte-at opts i) (byte-at letter 1)) #t
                          (self (+ i 1)))))))
            (go 0)))))))

(def %sort-prepare
  (fn (_ s o spec)
    (def t (if (%sort-opt? o spec "-b") (%sort-trim-left s) s))
    (def u (%sort-filter t (%sort-opt? o spec "-d") (%sort-opt? o spec "-i")))
    (if (%sort-opt? o spec "-f") (%sort-fold u) u)))

; -1, 0 or 1 for one key, so the fallback can see a tie
(def %sort-cmp
  (fn (_ a b o spec sep)
    (def ka (%sort-prepare (%sort-key a spec sep) o spec))
    (def kb (%sort-prepare (%sort-key b spec sep) o spec))
    (def c
      (if (%sort-opt? o spec "-n")
        (%cu-cmp-int (%cu-num-prefix ka) (%cu-num-prefix kb))
        (if (%sort-opt? o spec "-g")
          (%cu-cmp-int (%sort-general ka) (%sort-general kb))
          (if (%sort-opt? o spec "-M")
            (%cu-cmp-int (%sort-month ka) (%sort-month kb))
            (if (string=? ka kb) 0 (if (%cu-str< ka kb) (- 0 1) 1))))))
    (if (%sort-opt? o spec "-r") (- 0 c) c)))

(def %cu-cmp-int
  (fn (_ x y) (if (< x y) (- 0 1) (if (> x y) 1 0))))

; the whole line breaks a tie, unless -s asks for the input's order
(def %sort-less
  (fn (_ o spec sep)
    (fn (_ a b)
      (let ((c (%sort-cmp a b o spec sep)))
        (if (not (= c 0)) (< c 0)
          (if (Opts on? o "-s") #f
            (if (Opts on? o "-r") (%cu-str< b a) (%cu-str< a b))))))))

; --- the applet ---------------------------------------------------------------

(def %cu-sort
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "sort" argv))
    (def sep (Opts value o "-t"))
    (def spec (%sort-spec (Opts value o "-k")))
    (def out (Opts value o "-o"))
    (def ops (Opts operands o))
    (def lines (%cu-lines (%cu-gather ops stdin-thunk)))
    (def less? (%sort-less o spec sep))
    (if (Opts on? o "-c")
      (%sort-check lines less? ops)
      (let ((sorted (%cu-msort lines less?)))
        (def final
          (if (Opts on? o "-u") (%sort-dedup sorted less?) sorted))
        (def text (string-concat (map (fn (_ l) (string-append l "\n")) final)))
        (if (null? out) (do (display text) 0)
          (do (file-write-all out text) 0))))))

; sort's operands come off the parse: a value flag's argument was
; never an operand, and this used to have to say so itself.

; -u drops a line the comparison calls equal to the one before it
(def %sort-dedup
  (fn (_ ls less?)
    (def go
      (fn (self xs acc)
        (if (null? xs) (reverse acc)
          (self (rest xs)
            (if (if (pair? acc)
                  (if (less? (first acc) (first xs)) #f
                    (not (less? (first xs) (first acc))))
                  #f)
              acc
              (pair (first xs) acc))))))
    (go ls ())))

; -c reports the FIRST line out of order, and says nothing when sorted
(def %sort-check
  (fn (_ ls less? ops)
    (def name (if (null? ops) "-" (first ops)))
    (def go
      (fn (self xs n)
        (if (null? xs) 0
          (if (null? (rest xs)) 0
            (if (less? (first (rest xs)) (first xs))
              (do (file-write 2
                    (string-concat
                      (list "sort: " name ":" (%cu-int->str (+ n 1))
                            ": disorder: " (first (rest xs)) "\n")))
                  1)
              (self (rest xs) (+ n 1)))))))
    (go ls 1)))

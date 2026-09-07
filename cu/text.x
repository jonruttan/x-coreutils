; # x-coreutils -- the small tools, as applets
;
; ## cu/text.x -- the line tools
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; sort uniq head tail cat wc comm join basename dirname.  An applet is
; (fn (_ argv stdin-thunk) -> status); output goes to stdout, and the
; shared %cu-gather answers the operands' concatenated text (stdin when
; none, - meaning stdin among them).

; --- shared helpers ----------------------------------------------------------

(def %cu-b->s
  (fn (_ b) (list->string (list (integer->char b)))))

(def %cu-lines-go
  (fn (self s end i start acc)
    (if (>= i end)
      (if (> i start)
        (reverse (pair (substring s start i) acc))
        (reverse acc))
      (if (= (byte-at s i) 10)
        (self s end (+ i 1) (+ i 1) (pair (substring s start i) acc))
        (self s end (+ i 1) start acc)))))
(def %cu-lines
  (fn (_ s) (%cu-lines-go s (byte-len s) 0 0 ())))

(def %cu-print-lines
  (fn (self ls)
    (if (null? ls) ()
      (do (display (string-append (first ls) "\n"))
          (self (rest ls))))))

(def %cu-str<
  (fn (_ a b)
    (def la (byte-len a))
    (def lb (byte-len b))
    (def go
      (fn (self i)
        (if (>= i la) (< la lb)
          (if (>= i lb) #f
            (let ((ca (byte-at a i)) (cb (byte-at b i)))
              (if (< ca cb) #t
                (if (> ca cb) #f (self (+ i 1)))))))))
    (go 0)))

; merge sort: n log n, shallow recursion
(def %cu-merge
  (fn (self a b less?)
    (if (null? a) b
      (if (null? b) a
        (if (less? (first b) (first a))
          (pair (first b) (self a (rest b) less?))
          (pair (first a) (self (rest a) b less?)))))))
(def %cu-msort
  (fn (self l less?)
    (if (null? l) ()
      (if (null? (rest l)) l
        (let ((split (let ((go (fn (self2 slow fast acc)
                                 (if (if (pair? fast) (pair? (rest fast)) #f)
                                   (self2 (rest slow) (rest (rest fast))
                                     (pair (first slow) acc))
                                   (pair (reverse acc) slow)))))
                       (go l l ()))))
          (%cu-merge (self (first split) less?)
            (self (rest split) less?) less?))))))

; a leading number for sort -n: optional blanks, sign, digits[.digits]
(def %cu-num-prefix
  (fn (_ s)
    (def end (byte-len s))
    (def i0 (let ((go (fn (self i)
                        (if (>= i end) i
                          (let ((b (byte-at s i)))
                            (if (if (= b 32) #t (= b 9)) (self (+ i 1)) i))))))
              (go 0)))
    (def neg (if (< i0 end) (= (byte-at s i0) 45) #f))
    (def i1 (if neg (+ i0 1) i0))
    (def ir (let ((go (fn (self i acc any)
                        (if (>= i end) (pair acc any)
                          (let ((b (byte-at s i)))
                            (if (if (>= b 48) (<= b 57) #f)
                              (self (+ i 1) (+ (* acc 10) (- b 48)) #t)
                              (pair acc any)))))))
              (go i1 0 #f)))
    (if (not (rest ir)) 0
      (if neg (- 0 (first ir)) (first ir)))))

(def %cu-int->str
  (fn (_ n)
    (if (= n 0) "0"
      (let ((go (fn (self t acc)
                  (if (= t 0) acc
                    (self (/ (- t (% t 10)) 10)
                      (pair (integer->char (+ 48 (% t 10))) acc))))))
        (if (< n 0)
          (string-append "-" (list->string (go (- 0 n) ())))
          (list->string (go n ())))))))

(def %cu-pad-left
  (fn (_ s w)
    (def gap (- w (byte-len s)))
    (def sp (fn (self k) (if (<= k 0) "" (string-append " " (self (- k 1))))))
    (if (<= gap 0) s (string-append (sp gap) s))))

; operands to one text: files in order, - or none meaning stdin
(def %cu-gather
  (fn (_ operands stdin-thunk)
    (if (null? operands)
      (stdin-thunk)
      (let ((go (fn (self ops acc)
                  (if (null? ops)
                    (string-concat (reverse acc))
                    (self (rest ops)
                      (pair
                        (if (string=? (first ops) "-")
                          (stdin-thunk)
                          (file-read-all (first ops)))
                        acc))))))
        (go operands ())))))

; THE LAST HAND-ROLLED READ.  Everything reads its options off
; cu/cli.x's declaration now -- except comm, whose flags are DIGITS:
; v0.13.0's Opts decides `-12` is a negative number before it consults
; the declaration, so the cluster never reaches the parse.  x-lang#650
; makes the declaration win, and these two go when it ships.
(def %cu-option-token-ish?
  (fn (_ s) (if (< (byte-len s) 2) #f (= (byte-at s 0) 45))))

(def %cu-token-has?
  (fn (_ tok d)
    (let ((go (fn (self i)
                (if (>= i (byte-len tok)) #f
                  (if (= (byte-at tok i) d) #t (self (+ i 1)))))))
      (go 1))))

(def %cu-head
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "head" argv))
    (def n (%cu-num-prefix (Opts value o "-n" "10")))
    (def go
      (fn (self ls k)
        (if (null? ls) ()
          (if (<= k 0) ()
            (do (display (string-append (first ls) "\n"))
                (self (rest ls) (- k 1)))))))
    (do (go (%cu-lines (%cu-gather (Opts operands o) stdin-thunk)) n) 0)))

(def %cu-tail
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "tail" argv))
    (def n (%cu-num-prefix (Opts value o "-n" "10")))
    (def lines (%cu-lines (%cu-gather (Opts operands o) stdin-thunk)))
    (def drop-n (- (length lines) n))
    (def go
      (fn (self ls k)
        (if (null? ls) ()
          (if (> k 0) (self (rest ls) (- k 1))
            (do (display (string-append (first ls) "\n"))
                (self (rest ls) 0))))))
    (do (go lines drop-n) 0)))

; counts for one text: (lines words bytes)
(def %cu-wc-counts
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i nl nw in-word)
        (if (>= i end)
          (list nl (if in-word (+ nw 1) nw) end)
          (let ((b (byte-at s i)))
            (def ws (if (= b 32) #t (if (= b 9) #t (= b 10))))
            (self (+ i 1)
              (if (= b 10) (+ nl 1) nl)
              (if (if in-word ws #f) (+ nw 1) nw)
              (not ws))))))
    (go 0 0 0 #f)))

(def %cu-wc
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "wc" argv))
    (def any? (if (Opts on? o "-l") #t (if (Opts on? o "-w") #t (Opts on? o "-c"))))
    ; with no flag at all, wc shows every column
    (def show? (fn (_ f) (if any? (Opts on? o f) #t)))
    (def row
      (fn (_ counts name)
        (def parts
          (append
            (if (show? "-l")
              (list (%cu-pad-left (%cu-int->str (first counts)) 8)) ())
            (append
              (if (show? "-w")
                (list (%cu-pad-left (%cu-int->str (first (rest counts))) 8))
                ())
              (if (show? "-c")
                (list (%cu-pad-left
                        (%cu-int->str (first (rest (rest counts)))) 8))
                ()))))
        (display
          (string-append (%cu-join-sp parts)
            (if (null? name) "\n"
              (string-append " " (string-append name "\n")))))))
    (if (null? (Opts operands o))
      (do (row (%cu-wc-counts (stdin-thunk)) ()) 0)
      (let ((go (fn (self ops)
                  (if (null? ops) 0
                    (do (row (%cu-wc-counts
                               (if (string=? (first ops) "-")
                                 (stdin-thunk)
                                 (file-read-all (first ops))))
                          (first ops))
                        (self (rest ops)))))))
        (go (Opts operands o))))))

(def %cu-join-sp
  (fn (self ws)
    (if (null? ws) ""
      (if (null? (rest ws)) (first ws)
        (string-append (first ws) (self (rest ws)))))))

; comm: three columns over two sorted inputs; -1 -2 -3 suppress
(def %cu-comm
  (fn (_ argv stdin-thunk)
    ; COMM'S FLAGS ARE DIGITS, and v0.13.0's Opts decides `-12` is a
    ; negative number before it consults the declaration, so the cluster
    ; never reaches the parse.  x-lang#650 makes the declaration win;
    ; until that ships, comm reads its three digits itself.  Everything
    ; else -- the operands, the guard -- still comes off the one parse.
    (def o (%cu-opts "comm" argv))
    (def digit?
      (fn (_ d)
        (let ((go (fn (self as)
                    (if (null? as) #f
                      (if (%cu-option-token-ish? (first as))
                        (if (%cu-token-has? (first as) d) #t (self (rest as)))
                        (self (rest as)))))))
          (go argv))))
    (def s1 (not (digit? 49)))
    (def s2 (not (digit? 50)))
    (def s3 (not (digit? 51)))
    (def ops (filter (fn (_ a) (not (%cu-option-token-ish? a))) argv))
    (def read-op
      (fn (_ op) (if (string=? op "-") (stdin-thunk) (file-read-all op))))
    (def a (%cu-lines (read-op (first ops))))
    (def b (%cu-lines (read-op (first (rest ops)))))
    (def ind2 (if s1 "\t" ""))
    (def ind3 (string-append (if s1 "\t" "") (if s2 "\t" "")))
    (def go
      (fn (self la lb)
        (if (null? la)
          (if (null? lb) ()
            (do (if s2 (display (string-append ind2
                                  (string-append (first lb) "\n"))) ())
                (self la (rest lb))))
          (if (null? lb)
            (do (if s1 (display (string-append (first la) "\n")) ())
                (self (rest la) lb))
            (if (string=? (first la) (first lb))
              (do (if s3 (display (string-append ind3
                                    (string-append (first la) "\n"))) ())
                  (self (rest la) (rest lb)))
              (if (%cu-str< (first la) (first lb))
                (do (if s1 (display (string-append (first la) "\n")) ())
                    (self (rest la) lb))
                (do (if s2 (display (string-append ind2
                                      (string-append (first lb) "\n"))) ())
                    (self la (rest lb)))))))))
    (do (go a b) 0)))

; join on field 1 of two sorted inputs; -t CHAR sets the delimiter
(def %cu-split-line
  (fn (_ line delim)
    (if (null? delim)
      (%cu-words-line line)
      (%cu-split-byte line (byte-at delim 0)))))

(def %cu-words-line
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i start acc in)
        (if (>= i end)
          (reverse (if in (pair (substring s start i) acc) acc))
          (let ((ws (let ((b (byte-at s i)))
                      (if (= b 32) #t (= b 9)))))
            (if ws
              (self (+ i 1) (+ i 1) (if in (pair (substring s start i) acc) acc) #f)
              (self (+ i 1) (if in start i) acc #t))))))
    (go 0 0 () #f)))

(def %cu-split-byte
  (fn (_ s b)
    (def end (byte-len s))
    (def go
      (fn (self i start acc)
        (if (>= i end)
          (reverse (pair (substring s start end) acc))
          (if (= (byte-at s i) b)
            (self (+ i 1) (+ i 1) (pair (substring s start i) acc))
            (self (+ i 1) start acc)))))
    (go 0 0 ())))

(def %cu-join
  (fn (_ argv stdin-thunk)
    (def delim
      (if (if (pair? argv) (string=? (first argv) "-t") #f)
        (first (rest argv))
        ()))
    (def ops (if (null? delim) argv (rest (rest argv))))
    (def sep (if (null? delim) " " delim))
    (def read-op
      (fn (_ op) (if (string=? op "-") (stdin-thunk) (file-read-all op))))
    (def a (%cu-lines (read-op (first ops))))
    (def b (%cu-lines (read-op (first (rest ops)))))
    (def key (fn (_ line)
               (let ((fs (%cu-split-line line delim)))
                 (if (null? fs) "" (first fs)))))
    (def rest-fields
      (fn (_ line)
        (let ((fs (%cu-split-line line delim)))
          (if (null? fs) () (rest fs)))))
    (def emit
      (fn (_ la lb)
        (display
          (string-append
            (%cu-join-with
              (pair (key la)
                (append (rest-fields la) (rest-fields lb)))
              sep)
            "\n"))))
    ; runs of equal keys pair cartesianly
    (def take-run
      (fn (_ ls k)
        (let ((go (fn (self l acc)
                    (if (if (pair? l) (string=? (key (first l)) k) #f)
                      (self (rest l) (pair (first l) acc))
                      (pair (reverse acc) l)))))
          (go ls ()))))
    (def go
      (fn (self la lb)
        (if (null? la) ()
          (if (null? lb) ()
            (let ((ka (key (first la))) (kb (key (first lb))))
              (if (string=? ka kb)
                (let ((ra (take-run la ka)))
                  (def rb (take-run lb ka))
                  ; equal-key runs pair cartesianly
                  (def outer
                    (fn (self2 xs)
                      (if (null? xs) ()
                        (do (let ((inner (fn (self3 ys)
                                           (if (null? ys) ()
                                             (do (emit (first xs) (first ys))
                                                 (self3 (rest ys)))))))
                              (inner (first rb)))
                            (self2 (rest xs))))))
                  (do (outer (first ra))
                      (self (rest ra) (rest rb))))
                (if (%cu-str< ka kb)
                  (self (rest la) lb)
                  (self la (rest lb)))))))))
    (do (go a b) 0)))

(def %cu-join-with
  (fn (self ws sep)
    (if (null? ws) ""
      (if (null? (rest ws)) (first ws)
        (string-append (first ws)
          (string-append sep (self (rest ws) sep)))))))

(def %cu-basename
  (fn (_ argv stdin-thunk)
    (def p (first argv))
    (def stripped
      (let ((go (fn (self e)
                  (if (if (> e 1) (= (byte-at p (- e 1)) 47) #f)
                    (self (- e 1))
                    e))))
        (substring p 0 (go (byte-len p)))))
    (def slash
      (let ((go (fn (self i last)
                  (if (>= i (byte-len stripped)) last
                    (self (+ i 1)
                      (if (= (byte-at stripped i) 47) i last))))))
        (go 0 (- 0 1))))
    (def base (if (< slash 0) stripped
                (substring stripped (+ slash 1) (byte-len stripped))))
    (def suf (if (null? (rest argv)) () (first (rest argv))))
    (def final
      (if (null? suf) base
        (let ((lb (byte-len base)) (ls (byte-len suf)))
          (if (if (> lb ls)
                (string=? (substring base (- lb ls) lb) suf)
                #f)
            (substring base 0 (- lb ls))
            base))))
    (do (display (string-append final "\n")) 0)))

(def %cu-dirname
  (fn (_ argv stdin-thunk)
    (def p (first argv))
    (def stripped
      (let ((go (fn (self e)
                  (if (if (> e 1) (= (byte-at p (- e 1)) 47) #f)
                    (self (- e 1))
                    e))))
        (substring p 0 (go (byte-len p)))))
    (def slash
      (let ((go (fn (self i last)
                  (if (>= i (byte-len stripped)) last
                    (self (+ i 1)
                      (if (= (byte-at stripped i) 47) i last))))))
        (go 0 (- 0 1))))
    (def d
      (if (< slash 0) "."
        (if (= slash 0) "/"
          (substring stripped 0 slash))))
    (do (display (string-append d "\n")) 0)))

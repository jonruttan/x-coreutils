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

; flag parsing for the simple applets: leading -x... bundles collect
; into a symbol list, everything after is operands; answers
; (flags . operands).  An applet with option ARGUMENTS parses by hand.
(def %cu-flags
  (fn (_ argv known)
    (def known?
      (fn (_ b)
        (let ((go (fn (self ks)
                    (if (null? ks) #f
                      (if (= (first ks) b) #t (self (rest ks)))))))
          (go known))))
    (def go
      (fn (self ops flags)
        (if (null? ops) (pair flags ())
          (let ((op (first ops)))
            (if (if (>= (byte-len op) 2) (= (byte-at op 0) 45) #f)
              (if (string=? op "-")
                (pair flags ops)
                (let ((go2 (fn (self2 i fs)
                             (if (>= i (byte-len op)) fs
                               (if (known? (byte-at op i))
                                 (self2 (+ i 1) (pair (byte-at op i) fs))
                                 (Err raise (lit cu)
                                   (string-append "unknown option: " op)
                                   ()))))))
                  (self (rest ops) (go2 1 flags))))
              (pair flags ops))))))
    (go argv ())))

(def %cu-flag?
  (fn (_ b flags)
    (def go
      (fn (self fs)
        (if (null? fs) #f
          (if (= (first fs) b) #t (self (rest fs))))))
    (go flags)))

; --- the applets -------------------------------------------------------------

(def %cu-cat
  (fn (_ argv stdin-thunk)
    (do (display (%cu-gather argv stdin-thunk)) 0)))

(def %cu-sort
  (fn (_ argv stdin-thunk)
    (def fo (%cu-flags argv (list 114 110 117)))          ; r n u
    (def flags (first fo))
    (def lines (%cu-lines (%cu-gather (rest fo) stdin-thunk)))
    (def numeric (%cu-flag? 110 flags))
    (def less?
      (if numeric
        (fn (_ a b)
          (let ((na (%cu-num-prefix a)) (nb (%cu-num-prefix b)))
            (if (< na nb) #t
              (if (> na nb) #f (%cu-str< a b)))))
        (fn (_ a b) (%cu-str< a b))))
    (def sorted (%cu-msort lines less?))
    (def uniqd
      (if (%cu-flag? 117 flags)
        (let ((go (fn (self ls acc)
                    (if (null? ls) (reverse acc)
                      (self (rest ls)
                        (if (if (pair? acc)
                              (string=? (first ls) (first acc)) #f)
                          acc
                          (pair (first ls) acc)))))))
          (go sorted ()))
        sorted))
    (do (%cu-print-lines
          (if (%cu-flag? 114 flags) (reverse uniqd) uniqd))
        0)))

(def %cu-uniq
  (fn (_ argv stdin-thunk)
    (def fo (%cu-flags argv (list 99)))                   ; c
    (def count? (%cu-flag? 99 (first fo)))
    (def lines (%cu-lines (%cu-gather (rest fo) stdin-thunk)))
    (def emit
      (fn (_ n line)
        (if count?
          (display (string-append (%cu-pad-left (%cu-int->str n) 4)
                     (string-append " " (string-append line "\n"))))
          (display (string-append line "\n")))))
    (def go
      (fn (self ls cur n)
        (if (null? ls)
          (if (null? cur) () (emit n cur))
          (if (if (null? cur) #f (string=? (first ls) cur))
            (self (rest ls) cur (+ n 1))
            (do (if (null? cur) () (emit n cur))
                (self (rest ls) (first ls) 1))))))
    (do (go lines () 0) 0)))

; -n N, joined -nN, or bare; default 10
(def %cu-count-arg
  (fn (_ argv)
    (if (if (pair? argv) (string=? (first argv) "-n") #f)
      (pair (%cu-num-prefix (first (rest argv))) (rest (rest argv)))
      (if (if (pair? argv)
            (if (> (byte-len (first argv)) 2)
              (if (= (byte-at (first argv) 0) 45)
                (= (byte-at (first argv) 1) 110)
                #f)
              #f)
            #f)
        (pair (%cu-num-prefix (substring (first argv) 2
                                (byte-len (first argv))))
          (rest argv))
        (pair 10 argv)))))

(def %cu-head
  (fn (_ argv stdin-thunk)
    (def na (%cu-count-arg argv))
    (def go
      (fn (self ls k)
        (if (null? ls) ()
          (if (<= k 0) ()
            (do (display (string-append (first ls) "\n"))
                (self (rest ls) (- k 1)))))))
    (do (go (%cu-lines (%cu-gather (rest na) stdin-thunk)) (first na)) 0)))

(def %cu-tail
  (fn (_ argv stdin-thunk)
    (def na (%cu-count-arg argv))
    (def lines (%cu-lines (%cu-gather (rest na) stdin-thunk)))
    (def drop-n (- (length lines) (first na)))
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
    (def fo (%cu-flags argv (list 108 119 99)))           ; l w c
    (def flags (first fo))
    (def all (if (null? flags) (list 108 119 99) ()))
    (def show?
      (fn (_ b) (if (null? flags) #t (%cu-flag? b flags))))
    (def row
      (fn (_ counts name)
        (def parts
          (append
            (if (show? 108)
              (list (%cu-pad-left (%cu-int->str (first counts)) 8)) ())
            (append
              (if (show? 119)
                (list (%cu-pad-left (%cu-int->str (first (rest counts))) 8))
                ())
              (if (show? 99)
                (list (%cu-pad-left
                        (%cu-int->str (first (rest (rest counts)))) 8))
                ()))))
        (display
          (string-append (%cu-join-sp parts)
            (if (null? name) "\n"
              (string-append " " (string-append name "\n")))))))
    (if (null? (rest fo))
      (do (row (%cu-wc-counts (stdin-thunk)) ()) 0)
      (let ((go (fn (self ops)
                  (if (null? ops) 0
                    (do (row (%cu-wc-counts
                               (if (string=? (first ops) "-")
                                 (stdin-thunk)
                                 (file-read-all (first ops))))
                          (first ops))
                        (self (rest ops)))))))
        (go (rest fo))))))

(def %cu-join-sp
  (fn (self ws)
    (if (null? ws) ""
      (if (null? (rest ws)) (first ws)
        (string-append (first ws) (self (rest ws)))))))

; comm: three columns over two sorted inputs; -1 -2 -3 suppress
(def %cu-comm
  (fn (_ argv stdin-thunk)
    (def fo (%cu-flags argv (list 49 50 51)))             ; 1 2 3
    (def flags (first fo))
    (def s1 (not (%cu-flag? 49 flags)))
    (def s2 (not (%cu-flag? 50 flags)))
    (def s3 (not (%cu-flag? 51 flags)))
    (def ops (rest fo))
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

; # x-coreutils -- the small tools, as applets
;
; ## cu/text2.x -- the busybox expansion, text half
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; echo printf seq rev tac nl fold paste tee.

(def %cu-echo
  (fn (_ argv stdin-thunk)
    (def n? (if (pair? argv) (string=? (first argv) "-n") #f))
    (def e? (if (pair? argv) (string=? (first argv) "-e") #f))
    (def ops (if (if n? #t e?) (rest argv) argv))
    (def unescape
      (fn (_ s)
        (def end (byte-len s))
        (def go
          (fn (self i acc)
            (if (>= i end) (string-concat (reverse acc))
              (let ((b (byte-at s i)))
                (if (if (= b 92) (< (+ i 1) end) #f)
                  (let ((e (byte-at s (+ i 1))))
                    (match
                      ((= e 110) (self (+ i 2) (pair "\n" acc)))
                      ((= e 116) (self (+ i 2) (pair "\t" acc)))
                      ((= e 92)  (self (+ i 2) (pair "\\" acc)))
                      (#t (self (+ i 1) (pair "\\" acc)))))
                  (self (+ i 1) (pair (%cu-b->s b) acc)))))))
        (go 0 ())))
    (def joined (%cu-join-with ops " "))
    (do (display (if e? (unescape joined) joined))
        (if n? () (display "\n"))
        0)))

; printf(1): the format REUSES until the arguments run out; %s %d %c
; %x %o %% with optional width and the - flag; \n \t \\ in the format
; The escapes and the % scanning are cu/fmt-lex.x's; what stays here is the
; table of what a conversion means to printf.

(def %cu-oct->str
  (fn (_ n)
    (if (= n 0) "0"
      (let ((go (fn (self t acc)
                  (if (= t 0) (list->string acc)
                    (self (/ (- t (% t 8)) 8)
                      (pair (integer->char (+ 48 (% t 8))) acc))))))
        (go n ())))))

(def %cu-hexs
  (fn (_ n)
    (if (= n 0) "0"
      (let ((go (fn (self t acc)
                  (if (= t 0) (list->string acc)
                    (let ((d (% t 16)))
                      (self (/ (- t d) 16)
                        (pair (integer->char
                                (if (< d 10) (+ 48 d) (+ 87 d)))
                          acc)))))))
        (go n ())))))

(def %cu-pad
  (fn (_ s w left)
    (def gap (- w (byte-len s)))
    (def sp (fn (self k) (if (<= k 0) "" (string-append " " (self (- k 1))))))
    (if (<= gap 0) s
      (if left (string-append s (sp gap))
        (string-append (sp gap) s)))))

; one pass of the format over the argument list; answers (consumed-any?
; . rest-args)
(def %cu-printf-once
  (fn (_ toks args)
    (def go
      (fn (self ts as used acc)
        (if (null? ts)
          (do (display (string-concat (reverse acc)))
              (pair used as))
          (let ((t (first ts)))
            (if (not (%cu-fmt-dir? t))
              (self (rest ts) as used (pair t acc))
              (let ((conv (%cu-fmt-conv t))
                    (w (%cu-fmt-width t))
                    (left (%cu-fmt-left? t)))
                (def arg (if (null? as) "" (first as)))
                (def as2 (if (null? as) () (rest as)))
                (match
                  ; a format ending in a bare % keeps it as a directive
                  ; with no conversion
                  ((= (byte-len conv) 0) (self (rest ts) as used (pair "%" acc)))
                  ((string=? conv "%") (self (rest ts) as used (pair "%" acc)))
                  ((string=? conv "s")
                    (self (rest ts) as2 #t (pair (%cu-pad arg w left) acc)))
                  ((string=? conv "d")
                    (self (rest ts) as2 #t
                      (pair (%cu-pad (%cu-int->str (%cu-num-prefix arg)) w left)
                        acc)))
                  ((string=? conv "x")
                    (self (rest ts) as2 #t
                      (pair (%cu-hexs (%cu-num-prefix arg)) acc)))
                  ((string=? conv "o")
                    (self (rest ts) as2 #t
                      (pair (%cu-oct->str (%cu-num-prefix arg)) acc)))
                  ((string=? conv "c")
                    (self (rest ts) as2 #t
                      (pair (if (> (byte-len arg) 0) (substring arg 0 1) "")
                        acc)))
                  (#t (Err raise (lit cu)
                        "printf: only %s %d %x %o %c %%" ())))))))))
    (go toks args #f ())))

(def %cu-printf
  (fn (_ argv stdin-thunk)
    (if (null? argv)
      (do (file-write 2 "printf: need a format\n") 1)
      ; Parsed once, walked per argument group: printf repeats its format
      ; until the arguments run out.
      (let ((toks (%cu-fmt-parse (first argv) #t)))
        (def go
          (fn (self as)
            (let ((r (%cu-printf-once toks as)))
              (if (if (first r) (pair? (rest r)) #f)
                (self (rest r))
                0))))
        (go (rest argv))))))

(def %cu-seq
  (fn (_ argv stdin-thunk)
    (def n (length argv))
    (def a (if (>= n 2) (%cu-num-prefix (first argv)) 1))
    (def step
      (if (= n 3) (%cu-num-prefix (first (rest argv))) 1))
    (def z (%cu-num-prefix
             (match
               ((= n 1) (first argv))
               ((= n 2) (first (rest argv)))
               (#t (first (rest (rest argv)))))))
    (def go
      (fn (self i)
        (if (if (> step 0) (> i z) (< i z))
          0
          (do (display (string-append (%cu-int->str i) "\n"))
              (self (+ i step))))))
    (go a)))

(def %cu-rev-line
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i acc)
        (if (>= i end) (list->string acc)
          (self (+ i 1) (pair (integer->char (byte-at s i)) acc)))))
    (go 0 ())))

(def %cu-rev-applet
  (fn (_ argv stdin-thunk)
    (do (%cu-print-lines
          (map (fn (_ l) (%cu-rev-line l))
            (%cu-lines (%cu-gather argv stdin-thunk))))
        0)))

(def %cu-tac
  (fn (_ argv stdin-thunk)
    (do (%cu-print-lines
          (reverse (%cu-lines (%cu-gather argv stdin-thunk))))
        0)))

; nl: %6d + TAB for nonempty lines; six spaces + TAB for empty ones
; nl moved to cu/sort.x's neighbours in cu/text4.x with -b -n -s -w -v -i.

(def %cu-fold
  (fn (_ argv stdin-thunk)
    (def w
      (if (if (pair? argv) (string=? (first argv) "-w") #f)
        (%cu-num-prefix (first (rest argv)))
        80))
    (def ops (if (if (pair? argv) (string=? (first argv) "-w") #f)
               (rest (rest argv)) argv))
    (def chop
      (fn (self s)
        (if (<= (byte-len s) w)
          (display (string-append s "\n"))
          (do (display (string-append (substring s 0 w) "\n"))
              (self (substring s w (byte-len s)))))))
    (def go
      (fn (self ls)
        (if (null? ls) 0
          (do (chop (first ls)) (self (rest ls))))))
    (go (%cu-lines (%cu-gather ops stdin-thunk)))))

(def %cu-paste
  (fn (_ argv stdin-thunk)
    (def delim
      (if (if (pair? argv)
            (if (> (byte-len (first argv)) 2)
              (string=? (substring (first argv) 0 2) "-d")
              #f)
            #f)
        (substring (first argv) 2 3)
        (if (if (pair? argv) (string=? (first argv) "-d") #f)
          (substring (first (rest argv)) 0 1)
          "\t")))
    (def ops
      (if (if (pair? argv) (string=? (first argv) "-d") #f)
        (rest (rest argv))
        (if (if (pair? argv)
              (if (> (byte-len (first argv)) 2)
                (string=? (substring (first argv) 0 2) "-d")
                #f)
              #f)
          (rest argv)
          argv)))
    (def columns
      (map (fn (_ op)
             (%cu-lines
               (if (string=? op "-") (stdin-thunk)
                 (file-read-all op))))
        ops))
    (def any?
      (fn (self cs)
        (if (null? cs) #f
          (if (pair? (first cs)) #t (self (rest cs))))))
    (def go
      (fn (self cs)
        (if (not (any? cs)) 0
          (do (display
                (string-append
                  (%cu-join-with
                    (map (fn (_ c) (if (pair? c) (first c) "")) cs)
                    delim)
                  "\n"))
              (self (map (fn (_ c) (if (pair? c) (rest c) ())) cs))))))
    (go columns)))

(def %cu-tee
  (fn (_ argv stdin-thunk)
    (def a? (if (pair? argv) (string=? (first argv) "-a") #f))
    (def ops (if a? (rest argv) argv))
    (def text (stdin-thunk))
    (def go
      (fn (self os)
        (if (null? os) ()
          (let ((fd (if a? (file-open-append (first os))
                      (file-open-write (first os)))))
            (do (file-write fd text)
                (file-close fd)
                (self (rest os)))))))
    (do (display text) (go ops) 0)))

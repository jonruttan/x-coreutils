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
                    (if (= e 110) (self (+ i 2) (pair "\n" acc))
                      (if (= e 116) (self (+ i 2) (pair "\t" acc))
                        (if (= e 92) (self (+ i 2) (pair "\\" acc))
                          (self (+ i 1) (pair "\\" acc))))))
                  (self (+ i 1) (pair (%cu-b->s b) acc)))))))
        (go 0 ())))
    (def joined (%cu-join-with ops " "))
    (do (display (if e? (unescape joined) joined))
        (if n? () (display "\n"))
        0)))

; printf(1): the format REUSES until the arguments run out; %s %d %c
; %x %o %% with optional width and the - flag; \n \t \\ in the format
(def %cu-printf-esc
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i acc)
        (if (>= i end) (string-concat (reverse acc))
          (let ((b (byte-at s i)))
            (if (if (= b 92) (< (+ i 1) end) #f)
              (let ((e (byte-at s (+ i 1))))
                (if (= e 110) (self (+ i 2) (pair "\n" acc))
                  (if (= e 116) (self (+ i 2) (pair "\t" acc))
                    (if (= e 92) (self (+ i 2) (pair "\\" acc))
                      (self (+ i 2) (pair (%cu-b->s e) acc))))))
              (self (+ i 1) (pair (%cu-b->s b) acc)))))))
    (go 0 ())))

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
  (fn (_ fmt args)
    (def end (byte-len fmt))
    (def go
      (fn (self i as used acc)
        (if (>= i end)
          (do (display (string-concat (reverse acc)))
              (pair used as))
          (let ((b (byte-at fmt i)))
            (if (not (= b 37))                             ; %
              (self (+ i 1) as used (pair (%cu-b->s b) acc))
              (let ((left (if (< (+ i 1) end)
                            (= (byte-at fmt (+ i 1)) 45) #f)))
                (def j0 (if left (+ i 2) (+ i 1)))
                (def wr (let ((go2 (fn (self2 j acc2)
                                     (if (>= j end) (pair acc2 j)
                                       (let ((d (byte-at fmt j)))
                                         (if (if (>= d 48) (<= d 57) #f)
                                           (self2 (+ j 1)
                                             (+ (* acc2 10) (- d 48)))
                                           (pair acc2 j)))))))
                          (go2 j0 0)))
                (def w (first wr))
                (def j (rest wr))
                (def c (if (< j end) (byte-at fmt j) 0))
                (def arg (if (null? as) "" (first as)))
                (def as2 (if (null? as) () (rest as)))
                (if (= c 37)
                  (self (+ j 1) as used (pair "%" acc))
                  (if (= c 115)                            ; s
                    (self (+ j 1) as2 #t
                      (pair (%cu-pad arg w left) acc))
                    (if (= c 100)                          ; d
                      (self (+ j 1) as2 #t
                        (pair (%cu-pad
                                (%cu-int->str (%cu-num-prefix arg))
                                w left)
                          acc))
                      (if (= c 120)                        ; x
                        (self (+ j 1) as2 #t
                          (pair (%cu-hexs (%cu-num-prefix arg)) acc))
                        (if (= c 111)                      ; o
                          (self (+ j 1) as2 #t
                            (pair (%cu-oct->str (%cu-num-prefix arg))
                              acc))
                          (if (= c 99)                     ; c
                            (self (+ j 1) as2 #t
                              (pair
                                (if (> (byte-len arg) 0)
                                  (substring arg 0 1) "")
                                acc))
                            (Err raise (lit cu)
                              "printf: only %s %d %x %o %c %%"
                              ())))))))))))))
    (go 0 args #f ())))

(def %cu-printf
  (fn (_ argv stdin-thunk)
    (if (null? argv)
      (do (file-write 2 "printf: need a format\n") 1)
      (let ((fmt (%cu-printf-esc (first argv))))
        (def go
          (fn (self as)
            (let ((r (%cu-printf-once fmt as)))
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
             (if (= n 1) (first argv)
               (if (= n 2) (first (rest argv))
                 (first (rest (rest argv)))))))
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
(def %cu-nl
  (fn (_ argv stdin-thunk)
    (def go
      (fn (self ls n)
        (if (null? ls) 0
          (if (= (byte-len (first ls)) 0)
            (do (display "      \t\n") (self (rest ls) n))
            (do (display
                  (string-append (%cu-pad (%cu-int->str n) 6 #f)
                    (string-append "\t"
                      (string-append (first ls) "\n"))))
                (self (rest ls) (+ n 1)))))))
    (go (%cu-lines (%cu-gather argv stdin-thunk)) 1)))

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

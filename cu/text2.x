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
    (def o (%cu-opts "echo" argv))
    (def n? (Opts on? o "-n"))
    ; -E turns escapes off and is the default; it exists so a caller can
    ; undo an -e that came earlier on the same line.
    (def e? (if (Opts on? o "-E") #f (Opts on? o "-e")))
    (def ops (Opts operands o))
    ; the escapes are cu/fmt-lex.x's, read as echo's manual spells them; a \c
    ; ends the output, newline and all
    (let ((r (let ((joined (%cu-join-with ops " ")))
               (if e? (%cu-esc-string joined (lit arg)) (pair joined #f)))))
      (do (display (first r))
          (if (if n? #t (rest r)) () (display "\n"))
          0))))

; printf(1): the format REUSES until the arguments run out.  The conversions
; are %s, %d %i %u, %x %X, %o, %c, %b and %%, with an optional width and the -
; flag; any other is refused by name, as printf refuses one.  %b reads its
; argument's escapes.  The escapes and the % scanning are cu/fmt-lex.x's; what
; stays here is the table of what a conversion means to printf.

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

; One pass of the format over the argument list, printing as it goes.  Answers
; (USED-AN-ARGUMENT? REST WHAT-NEXT): WHAT-NEXT is `more` to go on with the
; arguments left, `stop` where a \c ended the output, and otherwise the
; directive printf does not read, which it refuses by name.
(def %cu-printf-once
  (fn (_ toks args)
    (def go
      (fn (self ts as used acc)
        (if (null? ts)
          (do (display (string-concat (reverse acc)))
              (list used as (lit more)))
          (let ((t (first ts)))
            (match
              ((eq? t (lit stop))
                (do (display (string-concat (reverse acc)))
                    (list used as (lit stop))))
              ((not (%cu-fmt-dir? t)) (self (rest ts) as used (pair t acc)))
              (#t
                (let ((conv (%cu-fmt-conv t))
                      (w (%cu-fmt-width t))
                      (left (%cu-fmt-left? t))
                      (arg (if (null? as) "" (first as)))
                      (as2 (if (null? as) () (rest as))))
                  (match
                    ((string=? conv "%") (self (rest ts) as used (pair "%" acc)))
                    ((string=? conv "s")
                      (self (rest ts) as2 #t (pair (%cu-pad arg w left) acc)))
                    ((%cu-member-s? conv (list "d" "i" "u"))
                      (self (rest ts) as2 #t
                        (pair (%cu-pad (%cu-int->str (%cu-num-prefix arg)) w left)
                          acc)))
                    ((string=? conv "x")
                      (self (rest ts) as2 #t
                        (pair (%cu-hexs (%cu-num-prefix arg)) acc)))
                    ((string=? conv "X")
                      (self (rest ts) as2 #t
                        (pair (Str8 upcase (%cu-hexs (%cu-num-prefix arg))) acc)))
                    ((string=? conv "o")
                      (self (rest ts) as2 #t
                        (pair (%cu-oct->str (%cu-num-prefix arg)) acc)))
                    ((string=? conv "c")
                      (self (rest ts) as2 #t
                        (pair (if (> (byte-len arg) 0) (substring arg 0 1) "")
                          acc)))
                    ; %b reads the argument's escapes, as echo -e reads them
                    ((string=? conv "b")
                      (let ((r (%cu-esc-string arg (lit arg))))
                        (if (rest r)
                          (do (display
                                (string-concat (reverse (pair (first r) acc))))
                              (list #t as2 (lit stop)))
                          (self (rest ts) as2 #t (pair (first r) acc)))))
                    (#t
                      (do (display (string-concat (reverse acc)))
                          (list used as (%cu-fmt-raw t))))))))))))
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
              (match
                ((eq? (%cu-nth 2 r) (lit stop)) 0)
                ((not (eq? (%cu-nth 2 r) (lit more)))
                  (do (file-write 2
                        (string-concat
                          (list "printf: " (%cu-nth 2 r)
                                ": invalid conversion specification\n")))
                      1))
                ((if (first r) (pair? (%cu-nth 1 r)) #f) (self (%cu-nth 1 r)))
                (#t 0)))))
        (go (rest argv))))))

; -s puts a separator between the values instead of a newline, and -w pads
; them to the width of the widest so a column lines up.
;
; -s separates BETWEEN and ends with a newline, which is what GNU and busybox
; do. The BSD seq on this machine appends the separator after the last value
; and ends without a newline ("1,2,3," for -s, 3); busybox is the parity
; target, so that difference is deliberate.
(def %cu-seq
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "seq" argv))
    (def ops (Opts operands o))
    (def n (length ops))
    (def a (if (>= n 2) (%cu-num-prefix (first ops)) 1))
    (def step (if (= n 3) (%cu-num-prefix (first (rest ops))) 1))
    (def z (%cu-num-prefix
             (match
               ((= n 1) (first ops))
               ((= n 2) (first (rest ops)))
               (#t (first (rest (rest ops)))))))
    (def sep (let ((v (Opts value o "-s"))) (if (null? v) "\n" v)))
    (def width
      (match
        ((not (Opts on? o "-w")) 0)
        (#t (let ((wa (byte-len (%cu-int->str a)))
                  (wz (byte-len (%cu-int->str z))))
              (if (> wa wz) wa wz)))))
    (def fmt
      (fn (_ i)
        (let ((t (%cu-int->str i)))
          (if (<= width (byte-len t)) t (%cu-pad-left-zero t width)))))
    (def vals
      (let ((go (fn (self i acc)
                  (if (if (> step 0) (> i z) (< i z)) (reverse acc)
                    (self (+ i step) (pair (fmt i) acc))))))
        (go a ())))
    (if (null? vals) 0
      (do (display (string-append (%cu-join-with vals sep) "\n")) 0))))

(def %cu-pad-left-zero
  (fn (self t width)
    (if (>= (byte-len t) width) t
      (self (string-append "0" t) width))))

(def %cu-rev-line
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i acc)
        (if (>= i end) (bytes->str acc)
          (self (+ i 1) (pair (byte-at s i) acc)))))
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

; One line, folded.  Column mode counts a tab to the next stop of eight, a
; backspace back one and a carriage return back to the margin; -b counts
; every byte as one.  A byte that would carry the column past the width
; starts a new line -- under -s, after the last space of the segment
; instead, when there is one before it.  A byte that is too wide on its
; own (a tab at the margin under a width below eight) is kept whole.
(def %cu-fold-line
  (fn (_ s w bytes? spaces?)
    (def end (byte-len s))
    (def col-after
      (fn (_ col b)
        (match
          (bytes? (+ col 1))
          ((= b 9) (+ col (- 8 (% col 8))))
          ((= b 8) (if (> col 0) (- col 1) 0))
          ((= b 13) 0)
          (#t (+ col 1)))))
    ; START is where the current line begins, BLANK the index of its last
    ; space so far or -1, ACC the lines already cut, newest first.  A
    ; break under -s puts the rest of the segment back and rewalks it.
    (def go
      (fn (self i start col blank acc)
        (if (>= i end) (reverse (pair (substring s start end) acc))
          (let ((b (byte-at s i)))
            (def adv (col-after col b))
            (match
              ((if (> adv w) (> i start) #f)
                (if (if spaces? (>= blank 0) #f)
                  (self (+ blank 1) (+ blank 1) 0 -1
                    (pair (substring s start (+ blank 1)) acc))
                  (self i i 0 -1 (pair (substring s start i) acc))))
              (#t (self (+ i 1) start adv (if (= b 32) i blank) acc)))))))
    (go 0 0 0 -1 ())))

(def %cu-fold
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "fold" argv))
    (def w (let ((v (Opts value o "-w"))) (if (null? v) 80 (%cu-num-prefix v))))
    (def bytes? (Opts on? o "-b"))
    (def spaces? (Opts on? o "-s"))
    (def go
      (fn (self ls)
        (if (null? ls) 0
          (do (%cu-print-lines (%cu-fold-line (first ls) w bytes? spaces?))
              (self (rest ls))))))
    (go (%cu-lines (%cu-gather (Opts operands o) stdin-thunk)))))

(def %cu-paste
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "paste" argv))
    (def delim
      (let ((v (Opts value o "-d")))
        (if (null? v) "\t" (substring v 0 1))))
    (def ops (Opts operands o))
    (def columns
      (map (fn (_ op)
             (%cu-lines
               (if (string=? op "-") (stdin-thunk)
                 (file-read-all op))))
        ops))
    ; -s pastes each file onto ONE line instead of pasting the files
    ; against each other line by line.
    (def serial
      (fn (self cs)
        (if (null? cs) 0
          (do (display
                (string-append (%cu-join-with (first cs) delim) "\n"))
              (self (rest cs))))))
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
    (if (Opts on? o "-s") (serial columns) (go columns))))

(def %cu-tee
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "tee" argv))
    (def a? (Opts on? o "-a"))
    ; -i: an interrupt ends whatever is feeding the pipe, not the copy.
    ; Under x the disposition is already that -- the engine ignores
    ; SIGINT for every applet (measured: a 4s sleep runs its full 4s
    ; through an INT at 1s and exits 0, where TERM ends it at 1s with
    ; 143) -- so the flag changes nothing observable here and is set for
    ; what it means.
    (if (Opts on? o "-i") (sys-signal cu-sigint cu-sig-ign) ())
    (def ops (Opts operands o))
    (def text (stdin-thunk))
    ; a file tee cannot open is said, and the copy goes on to the rest
    (def go
      (fn (self os st)
        (if (null? os) st
          (let ((fd (file-open-or-err
                      (if a? file-open-append file-open-write) (first os))))
            (if (Err err? fd)
              (do (file-write 2
                    (string-concat
                      (list "tee: " (first os) ": " (file-err-text fd) "\n")))
                  (self (rest os) 1))
              (do (file-write fd text)
                  (file-close fd)
                  (self (rest os) st)))))))
    (do (display text) (go ops 0))))

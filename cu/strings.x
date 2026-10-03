; # x-coreutils -- the small tools, as applets
;
; ## cu/strings.x -- strings
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's strings (miscutils/strings.c): each run of at least LEN (-n, 4)
; printable bytes -- ASCII from the space to the tilde, and the tab -- put out
; on a line of its own, after the file's name (-f) and the run's offset (-o in
; octal, -t o, d or x), seven wide.  With no operand the name is `{standard
; input}`.  A file that will not open is said, the rest are read, and the
; status is 1.  -a, busybox's only way, is taken and changes nothing.
;
; A piece is scanned by libc's strspn and strcspn through the FFI, a run at a
; time, where a loop in x would cost hundreds of objects a byte.  Both stop at
; a NUL, so a NUL is passed over in x; and both read on past the bytes a read
; filled, so each answer is cut at the piece's count.

(def %sg+ (prim-ref (lit int) (lit +)))
(def %sg-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %sg-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %sg-bsub (prim-ref (lit str) (lit byte-sub)))
(def %sg-min (fn (_ a b) (if (< a b) a b)))
(def %sg-c-strspn ())
(def %sg-c-strcspn ())

(def %sg-printable
  (bytes->str (pair #\tab (List range #\space #\delete))))

(def %sg-resolve!
  (fn (_)
    (def lib (%cu-dlopen () 1))
    (set! %sg-c-strspn (%cu-dlsym lib "strspn"))
    (set! %sg-c-strcspn (%cu-dlsym lib "strcspn"))))

; --- busybox's numbers ----------------------------------------------------------

; S as busybox's xatou_range reads it, for APPLET: decimal digits and nothing
; else, from LO to HI.  Answers the number, or nil once the trouble is said --
; `invalid number 'S'`, which a number past an unsigned int is too, or `number
; S is not in LO..HI range`.
(def %cu-range-number
  (fn (_ applet s lo hi)
    (def end (byte-len s))
    (def digits?
      (fn (self i)
        (if (>= i end) #t
          (if (if (>= (byte-at s i) #\0) (<= (byte-at s i) #\9) #f)
            (self (+ i 1)) #f))))
    (def n (if (if (> end 0) (digits? 0) #f) (%cu-num-prefix s) ()))
    (match
      ((if (null? n) #t (> n 4294967295))
        (do (file-write 2 (string-concat (list applet ": invalid number '" s "'\n")))
            ()))
      ((if (< n lo) #t (> n hi))
        (do (file-write 2
              (string-concat
                (list applet ": number " s " is not in " (%cu-int->str lo) ".."
                      (%cu-int->str hi) " range\n")))
            ()))
      (#t n))))

; N in RADIX, 8, 10 or 16, the hex digits lower case
(def %sg-radix
  (fn (_ n radix)
    (def go
      (fn (self t acc)
        (if (= t 0) acc
          (let ((d (% t radix)))
            (self (/ (- t d) radix)
              (pair (if (< d 10) (+ #\0 d) (+ #\a (- d 10))) acc))))))
    (if (= n 0) "0" (bytes->str (go n ())))))

; --- the scan -------------------------------------------------------------------

; The state of a file's scan: the runs and lines to go out, newest first; the
; offset of the next byte; where the run under way started; the bytes of it
; held while it is shorter than LEN, newest first; how many there are; and
; whether it is going out.
(def %sg-out ())
(def %sg-offset 0)
(def %sg-start 0)
(def %sg-held ())
(def %sg-count 0)
(def %sg-on #f)

; the settings: LEN, the name's words, the radix or nil
(def %sg-least 4)
(def %sg-label ())
(def %sg-radix-of ())

(def %sg-put (fn (_ s) (set! %sg-out (pair s %sg-out))))

; the run ended, by a byte that is not printable or by the end of the file
(def %sg-end-run!
  (fn (_)
    (do (if %sg-on (%sg-put "\n") ())
        (set! %sg-on #f)
        (set! %sg-held ())
        (set! %sg-count 0))))

; K printable bytes of TEXT from I, the run's next
(def %sg-run!
  (fn (_ text i k)
    (def bytes (%sg-bsub text i k))
    (do (if (= %sg-count 0) (set! %sg-start %sg-offset) ())
        (if %sg-on (%sg-put bytes)
          (do (set! %sg-held (pair bytes %sg-held))
              (set! %sg-count (+ %sg-count k))
              (if (>= %sg-count %sg-least)
                (do (if (null? %sg-label) () (%sg-put %sg-label))
                    (if (null? %sg-radix-of) ()
                      (%sg-put
                        (string-append
                          (%cu-pad-left (%sg-radix %sg-start %sg-radix-of) 7) " ")))
                    (%sg-put (string-concat (reverse %sg-held)))
                    (set! %sg-held ())
                    (set! %sg-on #t))
                ())))
        (set! %sg-offset (+ %sg-offset k)))))

; a piece P scanned, a run and then what is between runs at a time
(def %sg-take
  (fn (_ p s)
    (def text (first p))
    (def n (rest p))
    (def addr (%sg-ptr->int (%sg-str->ptr text)))
    (def nuls
      (fn (self i)
        (if (if (< i n) (= (byte-at text i) 0) #f) (self (+ i 1)) i)))
    (def go
      (fn (self i)
        (if (>= i n) ()
          (let ((k (%sg-min (%cu-ptr-call %sg-c-strspn (%sg+ addr i) %sg-printable)
                             (- n i))))
            (do (if (> k 0) (%sg-run! text i k) ())
                (let ((j (+ i k)))
                  (if (>= j n) ()
                    (let ((m (%sg-min (%cu-ptr-call %sg-c-strcspn (%sg+ addr j) %sg-printable)
                                       (- n j))))
                      (let ((e (nuls (+ j m))))
                        (do (%sg-end-run!)
                            (set! %sg-offset (+ %sg-offset (- e j)))
                            (%cu-sweep-tick! %cu-sweep-lines)
                            (self e)))))))))))
    (do (go 0)
        (file-write 1 (string-concat (reverse %sg-out)))
        (set! %sg-out ())
        s)))

; NAME scanned, its runs written: answers nil, or the io Err that stopped it
(def %sg-file
  (fn (_ name stdin-thunk)
    (do (set! %sg-offset 0)
        (set! %sg-held ())
        (set! %sg-count 0)
        (set! %sg-on #f)
        (set! %sg-out ())
        (let ((r (%cu-fold-one name stdin-thunk %sg-take ())))
          (do (%sg-end-run!)
              (file-write 1 (string-concat (reverse %sg-out)))
              (set! %sg-out ())
              (rest r))))))

; strings [-fo] [-t o|d|x] [-n LEN] [FILE]...
(def %cu-strings-applet
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "strings" argv))
    (def ops (Opts operands o))
    (def n-arg (let ((v (Opts value o "-n"))) (if (null? v) "4" v)))
    (def t-arg (let ((v (Opts value o "-t"))) (if (null? v) "o" v)))
    (def len (%cu-range-number "strings" n-arg 1 2147483647))
    (def radix
      (match
        ((string=? t-arg "o") 8)
        ((string=? t-arg "d") 10)
        ((string=? t-arg "x") 16)
        (#t ())))
    (def offsets? (if (Opts on? o "-o") #t (not (null? (Opts value o "-t")))))
    (def each
      (fn (self names st)
        (if (null? names) st
          (let ((name (first names)))
            (do (set! %sg-label
                  (match
                    ((not (Opts on? o "-f")) ())
                    ((null? ops) "{standard input}: ")
                    (#t (string-append name ": "))))
                (let ((err (%sg-file name stdin-thunk)))
                  (if (if (null? err) #t (eq? (file-err-op err) (lit read)))
                    (self (rest names) st)
                    (do (file-write 2
                          (string-concat
                            (list "strings: " name ": " (file-err-text err) "\n")))
                        (self (rest names) 1)))))))))
    (match
      ((null? len) 1)
      ((null? radix) (%cu-usage "strings"))
      (#t (do (%sg-resolve!)
              (set! %sg-least len)
              (set! %sg-radix-of (if offsets? radix ()))
              (each (if (null? ops) (list "-") ops) 0))))))

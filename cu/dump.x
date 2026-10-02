; # x-coreutils -- the small tools, as applets
;
; ## cu/dump.x -- busybox's dump engine, for hexdump, hd and xxd
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's libbb/dump.c.  A format string is a list of format units, each an
; iteration count, a byte count and a printf format in double quotes:
; `16/1 "%02x "`.  The formats added together read the input a block at a
; time, the block as long as the longest of them, and each prints its view of
; the same block.  The conversions are printf's (d i o u x X c s, with flags,
; width and precision) and dump's own: %_a and %_A the offset (at each line,
; and once at the end), %_c a byte as a character or its escape, %_p one with
; a dot for what does not print, %_u one with its ASCII name.  A block the
; same as the last is folded into one `*` line unless -v is given, and the
; last, short block is printed with blanks where the input ran out.
;
; The floating-point conversions (e E f g G) are refused: their digits are
; libc's printf, which the platform does not reach.
;
; The engine's state is the run's own: an applet sets it up with
; %cu-dump-reset!, adds formats, and runs %cu-dump.

; --- the state of a run -------------------------------------------------------

(def %dp-applet "hexdump")
(def %dp-fss ())            ; the format strings, each (FUS . BCNT) in a cell
(def %dp-error ())          ; the first refusal, said and fatal
(def %dp-skip 0)            ; -s: the bytes still to pass over
(def %dp-length -1)         ; -n: the bytes still to read, -1 for all
(def %dp-vflag (lit first)) ; all, dup, first or wait, as busybox's
(def %dp-xxd-eof ())        ; xxd: what ends the dump at the end of the input
(def %dp-displayoff 0)      ; xxd -o: added to every offset shown
(def %dp-address 0)
(def %dp-savaddress 0)
(def %dp-eaddress 0)
(def %dp-blocksize 0)
(def %dp-exit 0)
(def %dp-done #f)           ; the last file has been opened
(def %dp-ateof #t)
(def %dp-cur ())            ; the block being read, newest byte first
(def %dp-sav ())            ; the block before it, in order
(def %dp-started #f)
(def %dp-endfu ())
(def %dp-argv ())
(def %dp-stdin ())
(def %dp-src ())            ; the pieces of the file being read
(def %dp-name "")
(def %dp-piece ())
(def %dp-pos 0)
(def %dp-out ())            ; what is to be written, newest first
(def %dp-stop #f)

(def %cu-dump-reset!
  (fn (_ applet stdin-thunk)
    (do (set! %dp-applet applet)
        (set! %dp-fss ())
        (set! %dp-error ())
        (set! %dp-skip 0)
        (set! %dp-length -1)
        (set! %dp-vflag (lit first))
        (set! %dp-xxd-eof ())
        (set! %dp-displayoff 0)
        (set! %dp-address 0)
        (set! %dp-savaddress 0)
        (set! %dp-eaddress 0)
        (set! %dp-blocksize 0)
        (set! %dp-exit 0)
        (set! %dp-done #f)
        (set! %dp-ateof #t)
        (set! %dp-cur ())
        (set! %dp-sav ())
        (set! %dp-started #f)
        (set! %dp-endfu ())
        (set! %dp-argv ())
        (set! %dp-stdin stdin-thunk)
        (set! %dp-src ())
        (set! %dp-name "")
        (set! %dp-piece ())
        (set! %dp-pos 0)
        (set! %dp-out ())
        (set! %dp-stop #f))))

(def %cu-dump-skip! (fn (_ n) (set! %dp-skip n)))
(def %cu-dump-length! (fn (_ n) (set! %dp-length n)))
(def %cu-dump-all! (fn (_) (set! %dp-vflag (lit all))))
(def %cu-dump-xxd-eof! (fn (_ s) (set! %dp-xxd-eof s)))
(def %cu-dump-displayoff! (fn (_ n) (set! %dp-displayoff n)))
(def %cu-dump-address (fn (_) %dp-address))

; the first refusal: said once, and the run ends with 1
(def %dp-fail!
  (fn (_ msg)
    (if (null? %dp-error)
      (do (set! %dp-error msg)
          (file-write 2 (string-concat (list %dp-applet ": " msg "\n"))))
      ())))

; --- the output -----------------------------------------------------------------

; S onto what is to be written; an empty string is passed over
(def %dp-put
  (fn (_ s)
    (if (if (eq? s (lit nul)) #f (= (byte-len s) 0)) ()
      (set! %dp-out (pair s %dp-out)))))

(def %dp-nul-run (pair (bytes->str (list 0)) 1))

; what was put, in order: the strings joined, a NUL written by its count
(def %dp-flush!
  (fn (_)
    (def go
      (fn (self ps acc)
        (match
          ((null? ps) (if (null? acc) () (file-write 1 (string-concat (reverse acc)))))
          ((eq? (first ps) (lit nul))
            (do (if (null? acc) () (file-write 1 (string-concat (reverse acc))))
                (file-write-run 1 %dp-nul-run)
                (self (rest ps) ())))
          (#t (self (rest ps) (pair (first ps) acc))))))
    (let ((ps (reverse %dp-out)))
      (do (set! %dp-out ()) (go ps ())))))

; --- bytes and characters -----------------------------------------------------

(def %dp-digit? (fn (_ c) (if (>= c #\0) (<= c #\9) #f)))

; C in the string SET
(def %dp-in?
  (fn (_ c set)
    (def n (byte-len set))
    (def go (fn (self i) (if (>= i n) #f (if (= (byte-at set i) c) #t (self (+ i 1))))))
    (go 0)))

; the byte of S at I, 0 past its end, as C reads its terminator
(def %dp-at (fn (_ s i) (if (< i (byte-len s)) (byte-at s i) 0)))

(def %dp-skip-ws
  (fn (self s i) (if (if (< i (byte-len s)) (%ts-space? (byte-at s i)) #f) (self s (+ i 1)) i)))

; the decimal digits of S from I, as atoi reads them
(def %dp-atoi
  (fn (_ s i)
    (def go
      (fn (self j acc)
        (if (%dp-digit? (%dp-at s j)) (self (+ j 1) (+ (* acc 10) (- (byte-at s j) #\0))) acc)))
    (go i 0)))

(def %dp-digits-end
  (fn (self s i) (if (%dp-digit? (%dp-at s i)) (self s (+ i 1)) i)))

; --- the escapes of a format ------------------------------------------------------

; busybox's bb_process_escape_sequence on the escape after a backslash at Q of
; S: (BYTE . NEXT).  Octal up to three digits, \x and up to two hex digits,
; and \a \b \e \f \n \r \t \v \\; anything else is a backslash, the character
; after it left to be read.
(def %dp-escape
  (fn (_ s q)
    (def hex (= (%dp-at s q) #\x))
    (def base (if hex 16 8))
    (def digit
      (fn (_ c)
        (let ((d (- c #\0)))
          (if (if (>= d 0) (< d 10) #f) d
            (let ((e (- (| c 32) #\a)))
              (if (>= e 0) (+ e 10) -1))))))
    (def go
      (fn (self j n k)
        ; K counts the digits as busybox's num_digits does, \x as one
        (let ((d (digit (%dp-at s j))))
          (if (if (< d 0) #t (>= d base))
            (if (if hex (= k 1) #f) (lit bad) (list n j k))
            (let ((r (+ (* n base) d)))
              (if (> r 255) (list n j k)
                (if (>= (+ k 1) 3) (list r (+ j 1) (+ k 1))
                  (self (+ j 1) r (+ k 1)))))))))
    (let ((r (go (if hex (+ q 1) q) 0 (if hex 1 0))))
      (match
        ((eq? r (lit bad)) (pair #\\ q))
        ((> (%cu-nth 2 r) 0) (pair (first r) (%cu-nth 1 r)))
        (#t
          (let ((c (%dp-at s q)))
            (match
              ((= c #\a) (pair #\alarm (+ q 1)))
              ((= c #\b) (pair #\backspace (+ q 1)))
              ((= c #\e) (pair #\escape (+ q 1)))
              ((= c #\f) (pair 12 (+ q 1)))
              ((= c #\n) (pair #\newline (+ q 1)))
              ((= c #\r) (pair #\return (+ q 1)))
              ((= c #\t) (pair #\tab (+ q 1)))
              ((= c #\v) (pair 11 (+ q 1)))
              ((= c #\\) (pair #\\ (+ q 1)))
              (#t (pair #\\ q)))))))))

; S with its escapes read, up to a NUL one makes, as C's string ends there
(def %dp-escapes
  (fn (_ s)
    (def n (byte-len s))
    (def go
      (fn (self i acc)
        (if (>= i n) (bytes->str (reverse acc))
          (let ((c (byte-at s i)))
            (if (= c #\\)
              (let ((r (%dp-escape s (+ i 1))))
                (if (= (first r) 0) (bytes->str (reverse acc))
                  (self (rest r) (pair (first r) acc))))
              (self (+ i 1) (pair c acc)))))))
    (go 0 ())))

; --- the format units -----------------------------------------------------------

; a format unit: (REPS BCNT FMT SETREP IGNORE PRS) in a vector, so the rewrite
; can fill in its byte count and print units
(def %dp-fu-reps (fn (_ fu) (vec-ref fu 0)))
(def %dp-fu-bcnt (fn (_ fu) (vec-ref fu 1)))
(def %dp-fu-fmt (fn (_ fu) (vec-ref fu 2)))
(def %dp-fu-setrep (fn (_ fu) (vec-ref fu 3)))
(def %dp-fu-ignore (fn (_ fu) (vec-ref fu 4)))
(def %dp-fu-prs (fn (_ fu) (vec-ref fu 5)))

; busybox's bb_dump_add: FMT broken into its format units, added as a format
; string of its own
(def %cu-dump-add
  (fn (_ fmt)
    (def n (byte-len fmt))
    (def bad (fn (_) (do (%dp-fail! (string-concat (list "bad format {" fmt "}"))) ())))
    (def unit
      (fn (_ p)
        ; a unit from P: (FU . NEXT), or nil once refused
        (let ((rep-end (%dp-digits-end fmt p)))
          (if (if (> rep-end p) (not (if (%ts-space? (%dp-at fmt rep-end)) #t
                                       (= (%dp-at fmt rep-end) #\/)))
                #f)
            (bad)
            (let ((reps (if (> rep-end p) (%dp-atoi fmt p) 1))
                  (p1 (if (> rep-end p) (%dp-skip-ws fmt (+ rep-end 1)) p)))
              (let ((p2 (if (= (%dp-at fmt p1) #\/) (%dp-skip-ws fmt (+ p1 1)) p1)))
                (let ((b-end (%dp-digits-end fmt p2)))
                  (if (if (> b-end p2) (not (%ts-space? (%dp-at fmt b-end))) #f)
                    (bad)
                    (let ((bcnt (if (> b-end p2) (%dp-atoi fmt p2) 0))
                          (p3 (if (> b-end p2) (%dp-skip-ws fmt (+ b-end 1)) p2)))
                      (if (not (= (%dp-at fmt p3) #\"))
                        (bad)
                        (let ((close (%dp-find fmt (+ p3 1) #\")))
                          (if (< close 0) (bad)
                            (pair (vec-build 6
                                    (fn (_ i)
                                      (match
                                        ((= i 0) reps)
                                        ((= i 1) bcnt)
                                        ((= i 2) (%dp-escapes (substring fmt (+ p3 1) close)))
                                        ((= i 3) (> rep-end p))
                                        ((= i 4) #f)
                                        (#t ()))))
                                  (+ close 1))))))))))))))
    (def go
      (fn (self p acc)
        (let ((q (%dp-skip-ws fmt p)))
          (if (>= q n) (reverse acc)
            (let ((r (unit q)))
              (if (null? r) ()
                (self (rest r) (pair (first r) acc))))))))
    (let ((fus (go 0 ())))
      (if (null? %dp-error)
        (set! %dp-fss (append %dp-fss (list (vec-build 2 (fn (_ i) (if (= i 0) fus 0))))))
        ()))))

; the index of C in S from I, or -1
(def %dp-find
  (fn (_ s i c)
    (def n (byte-len s))
    (def go (fn (self j) (if (>= j n) -1 (if (= (byte-at s j) c) j (self (+ j 1))))))
    (go i)))

(def %dp-flag-chars "#-+ 0123456789")
(def %dp-dot-flag-chars ".#-+ 0123456789")

; busybox's bb_dump_size: the bytes a format string reads in a block
(def %dp-size
  (fn (_ fus)
    (def unit-size
      (fn (_ fmt)
        (def n (byte-len fmt))
        (def go
          (fn (self i bcnt prec)
            (if (>= i n) bcnt
              (if (not (= (byte-at fmt i) #\%)) (self (+ i 1) bcnt prec)
                (let ((j (%dp-skip-in fmt (+ i 1) %dp-flag-chars)))
                  (let ((dot (= (%dp-at fmt j) #\.)))
                    (let ((k (if dot (+ j 1) j)))
                      (let ((prec2 (if (if dot (%dp-digit? (%dp-at fmt k)) #f) (%dp-atoi fmt k) prec))
                            (k2 (if (if dot (%dp-digit? (%dp-at fmt k)) #f) (%dp-digits-end fmt k) k)))
                        (let ((c (%dp-at fmt k2)))
                          (match
                            ((= c #\c) (self (+ k2 1) (+ bcnt 1) prec2))
                            ((%dp-in? c "diouxX") (self (+ k2 1) (+ bcnt 4) prec2))
                            ((%dp-in? c "eEfgG") (self (+ k2 1) (+ bcnt 8) prec2))
                            ((= c #\s) (self (+ k2 1) (+ bcnt prec2) prec2))
                            ((= c #\_)
                              (if (%dp-in? (%dp-at fmt (+ k2 1)) "cpu")
                                (self (+ k2 2) (+ bcnt 1) prec2)
                                (self (+ k2 2) bcnt prec2)))
                            (#t (self (+ k2 1) bcnt prec2))))))))))))
        (go 0 0 0)))
    (def go
      (fn (self us total)
        (if (null? us) total
          (let ((fu (first us)))
            (self (rest us)
              (+ total (* (%dp-fu-reps fu)
                          (if (> (%dp-fu-bcnt fu) 0) (%dp-fu-bcnt fu)
                            (unit-size (%dp-fu-fmt fu))))))))))
    (go fus 0)))

; the index past the run of SET's characters in S from I
(def %dp-skip-in
  (fn (self s i set)
    (if (if (< i (byte-len s)) (%dp-in? (byte-at s i) set) #f) (self s (+ i 1) set) i)))

; --- the print units --------------------------------------------------------------

; A print unit: (KIND BCNT PRE SPEC CONV POST NOSPACE) in a vector -- the text
; before the %, the flags, width and precision after it, the conversion
; character and the text after it, up to the next %.  KIND is text, address, c,
; char, int, p, str, u or uint.  NOSPACE: the last whitespace
; character goes on the unit's last iteration.
(def %dp-pr
  (fn (_ kind bcnt pre spec conv post)
    (vec-build 7
      (fn (_ i)
        (match
          ((= i 0) kind) ((= i 1) bcnt) ((= i 2) pre) ((= i 3) spec)
          ((= i 4) conv) ((= i 5) post) (#t #f))))))

; busybox's rewrite: each unit's format broken into print units, a byte count
; for each, and the iteration count of a format string's last unit raised to
; fill the block
(def %dp-rewrite
  (fn (_ fs)
    (def fus (vec-ref fs 0))
    (def unit
      (fn (_ fu)
        (def fmt (%dp-fu-fmt fu))
        (def n (byte-len fmt))
        (def fbcnt (%dp-fu-bcnt fu))
        (def go
          (fn (self fmtp nconv acc)
            (if (if (>= fmtp n) #t (not (null? %dp-error))) (reverse acc)
              (let ((pct (%dp-find fmt fmtp #\%)))
                (if (< pct 0)
                  (reverse (pair (%dp-pr (lit text) 0 (substring fmt fmtp n) "" 0 "") acc))
                  (let ((r (%dp-conversion fmt pct fbcnt fu)))
                    (if (null? r) (reverse acc)
                      (let ((pr (first r)) (p2 (rest r)))
                        (let ((p3 (let ((f (%dp-find fmt p2 #\%))) (if (< f 0) n f))))
                          ; busybox counts a conversion only where the unit
                          ; has a byte count and it is not an offset
                          (let ((counts (if (eq? (vec-ref pr 0) (lit address)) #f (> fbcnt 0))))
                            (do (vec-set! pr 2 (substring fmt fmtp pct))
                                (vec-set! pr 5 (substring fmt p2 p3))
                                (if (if counts (> nconv 0) #f)
                                  (%dp-fail! "byte count with multiple conversion characters")
                                  ())
                                (self p3 (if counts (+ nconv 1) nconv) (pair pr acc)))))))))))))
        (let ((prs (go 0 0 ())))
          (do (vec-set! fu 5 prs)
              (if (= fbcnt 0)
                (vec-set! fu 1 (%cal-sum (map (fn (_ pr) (vec-ref pr 1)) prs)))
                ())))))
    (def adjust
      (fn (self us)
        (if (null? us) ()
          (let ((fu (first us)))
            (do (if (if (null? (rest us))
                      (if (< (vec-ref fs 1) %dp-blocksize)
                        (if (not (%dp-fu-setrep fu)) (> (%dp-fu-bcnt fu) 0) #f) #f) #f)
                  (vec-set! fu 0 (+ (%dp-fu-reps fu)
                                    (%cal/ (- %dp-blocksize (vec-ref fs 1)) (%dp-fu-bcnt fu))))
                  ())
                (if (if (> (%dp-fu-reps fu) 1) (pair? (%dp-fu-prs fu)) #f)
                  (let ((last (List last (%dp-fu-prs fu))))
                    (vec-set! last 6 (%dp-ends-in-space? last)))
                  ())
                (self (rest us)))))))
    (do (map unit fus)
        (adjust fus))))

; the last character of print unit PR's format is whitespace
(def %dp-ends-in-space?
  (fn (_ pr)
    (let ((s (if (eq? (vec-ref pr 0) (lit text)) (vec-ref pr 2) (vec-ref pr 5))))
      (if (= (byte-len s) 0) #f (%ts-space? (byte-at s (- (byte-len s) 1)))))))

; the refusal of the conversion character at AT of FMT
(def %dp-bad
  (fn (_ fmt at)
    (do (%dp-fail! (string-concat
                     (list "bad conversion character %" (substring fmt at (byte-len fmt)))))
        ())))

; A conversion of KIND whose spec runs from PCT to AT, CONV its character and
; END where its text starts: (PR . END).  Its byte count is the unit's own,
; FBCNT, which must be one of COUNTS, or else the first of them.
(def %dp-counted
  (fn (_ fmt pct fbcnt kind counts at conv end)
    (if (if (> fbcnt 0) (not (%dp-member? fbcnt counts)) #f)
      (do (%dp-fail! (string-concat
                       (list "bad byte count for conversion character "
                             (substring fmt at (byte-len fmt)))))
          ())
      (pair (%dp-pr kind (if (> fbcnt 0) fbcnt (first counts)) ""
              (substring fmt (+ pct 1) at) conv "")
            end))))

; the integer conversion at AT: d and i signed, of 8 4 2 or 1 bytes; o u x X
; unsigned, of 4 2 or 1
(def %dp-int-conv
  (fn (_ fmt pct fbcnt at)
    (let ((c (%dp-at fmt at)))
      (match
        ((%dp-in? c "di") (%dp-counted fmt pct fbcnt (lit int) (list 8 4 2 1) at c (+ at 1)))
        ((%dp-in? c "ouxX") (%dp-counted fmt pct fbcnt (lit uint) (list 4 2 1) at c (+ at 1)))
        (#t (%dp-bad fmt at))))))

; dump's own conversions, at P1 the _: %_a and %_A (d o or x), %_c, %_p, %_u
(def %dp-underscore
  (fn (_ fmt pct fbcnt fu p1)
    (let ((k (%dp-at fmt (+ p1 1))) (x (%dp-at fmt (+ p1 2))))
      (match
        ((if (if (= k #\a) #t (= k #\A)) (not (%dp-in? x "dox")) #f) (%dp-bad fmt p1))
        ((if (= k #\a) #t (= k #\A))
          (do (if (= k #\A) (do (set! %dp-endfu fu) (vec-set! fu 4 #t)) ())
              (pair (%dp-pr (lit address) 0 "" (substring fmt (+ pct 1) p1) x "") (+ p1 3))))
        ((= k #\c) (%dp-counted fmt pct fbcnt (lit c) (list 1) p1 #\c (+ p1 2)))
        ((= k #\p) (%dp-counted fmt pct fbcnt (lit p) (list 1) p1 #\c (+ p1 2)))
        ((= k #\u) (%dp-counted fmt pct fbcnt (lit u) (list 1) p1 #\c (+ p1 2)))
        (#t (%dp-bad fmt p1))))))

; The conversion at PCT of FMT, in a unit of byte count FBCNT: (PR . P2), P2
; where the text after it starts -- or nil once refused.  With a byte count the
; precision is part of the flags; without one, it is %s's byte count.
(def %dp-conversion
  (fn (_ fmt pct fbcnt fu)
    (def p1a (%dp-skip-in fmt (+ pct 1) (if (> fbcnt 0) %dp-dot-flag-chars %dp-flag-chars)))
    (def dot (if (> fbcnt 0) #f (= (%dp-at fmt p1a) #\.)))
    (def p1b (if dot (+ p1a 1) p1a))
    (def prec? (if dot (%dp-digit? (%dp-at fmt p1b)) #f))
    (def p1 (if prec? (%dp-digits-end fmt p1b) p1b))
    (def c (%dp-at fmt p1))
    (match
      ((= c #\c) (%dp-counted fmt pct fbcnt (lit char) (list 1) p1 c (+ p1 1)))
      ((= c #\l)
        (let ((q (if (= (%dp-at fmt (+ p1 1)) #\l) (+ p1 2) (+ p1 1))))
          (%dp-int-conv fmt pct fbcnt q)))
      ((%dp-in? c "diouxX") (%dp-int-conv fmt pct fbcnt p1))
      ((%dp-in? c "eEfgG")
        (do (%dp-fail! (string-concat
                         (list "floating-point conversion %" (bytes->str (list c))
                               " is not supported")))
            ()))
      ((if (= c #\s) (if (= fbcnt 0) (not prec?) #f) #f)
        (do (%dp-fail! "%s needs precision or byte count") ()))
      ((= c #\s)
        (pair (%dp-pr (lit str) (if (> fbcnt 0) fbcnt (%dp-atoi fmt p1b)) ""
                (substring fmt (+ pct 1) p1) #\s "")
              (+ p1 1)))
      ((= c #\_) (%dp-underscore fmt pct fbcnt fu p1))
      (#t (%dp-bad fmt p1)))))

(def %dp-member?
  (fn (self x l) (if (null? l) #f (if (= (first l) x) #t (self x (rest l))))))

; --- printf, one conversion -----------------------------------------------------

; N's digits in RADIX, N read as an unsigned 64-bit number
(def %dp-udigits
  (fn (_ n radix upper)
    (def digit (fn (_ d) (if (< d 10) (+ #\0 d) (+ (if upper #\A #\a) (- d 10)))))
    (def go
      (fn (self t acc)
        (if (= t 0) acc
          (let ((d (% t radix)))
            (self (%cal/ (- t d) radix) (pair (digit d) acc))))))
    (match
      ((= n 0) "0")
      ((> n 0) (bytes->str (go n ())))
      ; a negative N is its two's complement: the low digit off its bits, and
      ; the rest shifted down with the sign bit cleared
      ((= radix 16)
        (bytes->str (go (& (>> n 4) 1152921504606846975) (list (digit (& n 15))))))
      ((= radix 8)
        (bytes->str (go (& (>> n 3) 2305843009213693951) (list (digit (& n 7))))))
      (#t
        (let ((hi (& (>> n 1) 9223372036854775807)))
          (let ((q (%cal/ hi 5)))
            (bytes->str (go q (list (digit (+ (* 2 (- hi (* 5 q))) (& n 1))))))))))))

; SPEC read as printf reads it: (FLAGS WIDTH PREC), PREC nil when not given
(def %dp-spec
  (fn (_ spec)
    (def flags-end (%dp-skip-in spec 0 "#-+ 0"))
    (def w-end (%dp-digits-end spec flags-end))
    (def dot (= (%dp-at spec w-end) #\.))
    (list (substring spec 0 flags-end)
          (if (> w-end flags-end) (%dp-atoi spec flags-end) 0)
          (if dot (%dp-atoi spec (+ w-end 1)) ()))))

; VALUE converted by CONV under SPEC, put out: printf's %d %i %o %u %x %X %c
; %s, with the flags # - + space 0, a width and a precision
(def %dp-conv!
  (fn (_ spec conv value)
    (let ((sp (%dp-spec spec)))
      (%dp-conv-p! (%dp-flagset (first sp)) (%cu-nth 1 sp) (%cu-nth 2 sp) conv value))))

; FLAGS as (LEFT ZERO PLUS SPACE ALT), read once
(def %dp-flagset
  (fn (_ flags)
    (map (fn (_ c) (%dp-in? c flags)) (list #\- #\0 #\+ #\space #\#))))

; %dp-conv! with its spec read: FL the flag set, WIDTH, PREC nil or a count
(def %dp-conv-p!
  (fn (_ fl width prec conv value)
    (def left (first fl))
    (def zero (%cu-nth 1 fl))
    (def alt (%cu-nth 4 fl))
    ; the sign or prefix, and the body: a string, or for %c the byte
    (def lead
      (match
        ((if (= conv #\d) #t (= conv #\i))
          (match ((< value 0) "-") ((%cu-nth 2 fl) "+") ((%cu-nth 3 fl) " ") (#t "")))
        ((if (if alt (not (= value 0)) #f) (= conv #\x) #f) "0x")
        ((if (if alt (not (= value 0)) #f) (= conv #\X) #f) "0X")
        (#t "")))
    (def body
      (match
        ((= conv #\c) value)
        ((= conv #\s)
          (if (if (null? prec) #t (<= (byte-len value) prec)) value (substring value 0 prec)))
        ((= conv #\x) (%dp-precise (%dp-udigits value 16 #f) prec value))
        ((= conv #\X) (%dp-precise (%dp-udigits value 16 #t) prec value))
        ((= conv #\o)
          (let ((b (%dp-precise (%dp-udigits value 8 #f) prec value)))
            (if (if alt (not (if (> (byte-len b) 0) (= (byte-at b 0) #\0) #f)) #f)
              (string-append "0" b) b)))
        ((= conv #\u) (%dp-precise (%dp-udigits value 10 #f) prec value))
        (#t (%dp-precise (%dp-udigits (if (< value 0) (- 0 value) value) 10 #f) prec value))))
    (def gap (- width (+ (byte-len lead) (if (= conv #\c) 1 (byte-len body)))))
    (def put-body
      (fn (_)
        (match
          ((not (= conv #\c)) (%dp-put body))
          ((= body 0) (%dp-put (lit nul)))
          (#t (%dp-put (bytes->str (list body)))))))
    (match
      ((<= gap 0) (do (%dp-put lead) (put-body)))
      (left (do (%dp-put lead) (put-body) (%dp-put (%cu-pad-left "" gap))))
      ((if zero (if (null? prec) (not (if (= conv #\c) #t (= conv #\s))) #f) #f)
        (do (%dp-put lead) (%dp-put (%cu-pad-zero "" gap)) (put-body)))
      (#t (do (%dp-put (%cu-pad-left "" gap)) (%dp-put lead) (put-body))))))

; DIGITS to at least PREC of them; a precision of 0 prints no digit for 0
(def %dp-precise
  (fn (_ digits prec value)
    (match
      ((null? prec) digits)
      ((if (= prec 0) (= value 0) #f) "")
      (#t (%cu-pad-zero digits prec)))))

; --- the block's values -------------------------------------------------------------

; the K bytes of BP, a list, as an unsigned little-endian number
(def %dp-unsigned
  (fn (_ bp k)
    (def go
      (fn (self l i acc)
        (if (if (= i k) #t (null? l)) acc
          (self (rest l) (+ i 1) (| acc (<< (first l) (* 8 i)))))))
    (go bp 0 0)))

(def %dp-signed
  (fn (_ bp k)
    (let ((u (%dp-unsigned bp k)))
      (match
        ((= k 1) (if (>= u 128) (- u 256) u))
        ((= k 2) (if (>= u 32768) (- u 65536) u))
        ((= k 4) (if (>= u 2147483648) (- u 4294967296) u))
        (#t u)))))

(def %dp-byte (fn (_ bp) (if (null? bp) 0 (first bp))))

(def %dp-c-escapes (list "\\0" "\\a" "\\b" "\\t" "\\n" "\\v" "\\f" "\\r"))

(def %dp-u-names
  (list "nul" "soh" "stx" "etx" "eot" "enq" "ack" "bel" "bs" "ht" "lf" "vt" "ff"
        "cr" "so" "si" "dle" "dc1" "dc2" "dc3" "dc4" "nak" "syn" "etb" "can" "em"
        "sub" "esc" "fs" "gs" "rs" "us"))

(def %dp-octal3 (fn (_ b) (%cu-pad-zero (%dp-udigits b 8 #f) 3)))

; A print unit compiled, once, for the display: (BCNT NOSPACE . PRINT), PRINT
; called with the block's bytes from the unit's place, DROP to leave off the
; last whitespace character, and PAD when the input has run out -- where the
; unit prints blanks as wide as its conversion, as busybox's bpad makes it.
(def %dp-compile
  (fn (_ pr)
    (def kind (vec-ref pr 0))
    (def bcnt (vec-ref pr 1))
    (def pre (vec-ref pr 2))
    (def spec (vec-ref pr 3))
    (def conv (vec-ref pr 4))
    (def text (if (eq? kind (lit text)) pre (vec-ref pr 5)))
    (def text-dropped (if (vec-ref pr 6) (substring text 0 (- (byte-len text) 1)) text))
    (def sp (%dp-spec spec))
    (def fl (%dp-flagset (first sp)))
    (def width (%cu-nth 1 sp))
    (def prec (%cu-nth 2 sp))
    (def blank (%cu-pad-left "" width))
    (def long (%dp-in? #\l spec))
    (def conv! (fn (_ c v) (%dp-conv-p! fl width prec c v)))
    (def value
      (fn (_ bp)
        (let ((b (%dp-byte bp)))
          (match
            ((eq? kind (lit address)) (conv! conv (+ %dp-address %dp-displayoff)))
            ((eq? kind (lit c))
              (match
                ((= b 0) (conv! #\s "\\0"))
                ((if (>= b 7) (<= b 13) #f) (conv! #\s (%cu-nth (- b 6) %dp-c-escapes)))
                ((if (>= b 32) (< b 127) #f) (conv! #\c b))
                (#t (conv! #\s (%dp-octal3 b)))))
            ((eq? kind (lit char)) (conv! #\c b))
            ((eq? kind (lit int))
              (conv! conv
                (match
                  ; a %d without an l reads the low half, as C's varargs do
                  ((not (= bcnt 8)) (%dp-signed bp bcnt))
                  (long (%dp-unsigned bp 8))
                  (#t (%dp-signed bp 4)))))
            ((eq? kind (lit p)) (conv! #\c (if (if (>= b 32) (< b 127) #f) b #\.)))
            ((eq? kind (lit str)) (conv! #\s (%dp-cstring bp bcnt)))
            ((eq? kind (lit u))
              (match
                ((<= b 31) (conv! #\s (%cu-nth b %dp-u-names)))
                ((= b 127) (conv! #\s "del"))
                ((< b 127) (conv! #\c b))
                (#t (conv! #\x b))))
            ((eq? kind (lit uint)) (conv! conv (if (= bcnt 8) b (%dp-unsigned bp bcnt))))
            (#t ())))))
    (pair bcnt
      (pair (vec-ref pr 6)
        (if (eq? kind (lit text))
          (fn (_ bp drop pad) (%dp-put (if drop text-dropped text)))
          (fn (_ bp drop pad)
            (do (%dp-put pre)
                (if pad (%dp-put blank) (value bp))
                (%dp-put (if drop text-dropped text)))))))))

; the first K bytes of BP up to a NUL, as a string
(def %dp-cstring
  (fn (_ bp k)
    (def go
      (fn (self l i acc)
        (if (if (= i k) #t (if (null? l) #t (= (first l) 0))) (bytes->str (reverse acc))
          (self (rest l) (+ i 1) (pair (first l) acc)))))
    (go bp 0 ())))

; --- reading ------------------------------------------------------------------------

(def %dp-say
  (fn (_ name err)
    (file-write 2 (string-concat (list %dp-applet ": " name ": " (file-err-text err) "\n")))))

; the next file, opened, and the skip taken out of it: #f when there is none
(def %dp-next!
  (fn (self)
    (if (pair? %dp-argv)
      (let ((name (first %dp-argv)))
        (do (set! %dp-argv (rest %dp-argv))
            (let ((src (%cu-pieces name %dp-stdin)))
              (if (Err err? src)
                (do (%dp-say name src) (set! %dp-exit 1) (set! %dp-done #t) (self))
                (do (%dp-close!)
                    (set! %dp-src src)
                    (set! %dp-name name)
                    (%dp-opened! name))))))
      (if %dp-done #f
        (do (if (null? %dp-src) (set! %dp-src (%cu-pieces "-" %dp-stdin)) ())
            (set! %dp-name "stdin")
            (%dp-opened! ()))))))

; a file just opened, NAME nil for standard input: the skip passed over, and
; on to the next file where the skip is longer than this one
(def %dp-opened!
  (fn (_ name)
    (do (set! %dp-done #t)
        (if (> %dp-skip 0) (%dp-do-skip! name) ())
        (if (= %dp-skip 0) #t (%dp-next!)))))

; busybox's do_skip: a regular file no longer than the skip is passed whole;
; otherwise the skip is read past.  (busybox seeks, and a pipe it cannot seek
; ends the run; standard input here is read past.)
(def %dp-do-skip!
  (fn (_ name)
    (let ((st (if (if (null? name) #t (string=? name "-")) () (file-stat-full name))))
      (if (if (null? st) #f
            (if (= (& (%cu-stat-get st (lit mode)) 61440) 32768)
              (>= %dp-skip (%cu-stat-get st (lit size))) #f))
        (do (set! %dp-skip (- %dp-skip (%cu-stat-get st (lit size))))
            (set! %dp-address (+ %dp-address (%cu-stat-get st (lit size)))))
        (do (set! %dp-src (%cu-pieces-past %dp-src %dp-skip))
            (set! %dp-piece ())
            (set! %dp-address (+ %dp-address %dp-skip))
            (set! %dp-savaddress %dp-address)
            (set! %dp-skip 0))))))

(def %dp-close!
  (fn (_)
    (do (if (null? %dp-src) () (%dp-src (lit close)))
        (set! %dp-src ())
        (set! %dp-piece ())
        (set! %dp-pos 0))))

; up to WANT bytes of the open file onto the block: how many, 0 at its end
(def %dp-read!
  (fn (_ want)
    (def go
      (fn (self k)
        (if (= k want) k
          (if (if (null? %dp-piece) #t (>= %dp-pos (rest %dp-piece)))
            (let ((p (if (null? %dp-src) (pair "" 0) (%dp-src))))
              (match
                ((Err err? p)
                  (do (%dp-say %dp-name p) (set! %dp-src ()) (set! %dp-piece ()) k))
                ((= (rest p) 0) (do (set! %dp-piece ()) k))
                (#t (do (set! %dp-piece p) (set! %dp-pos 0) (self k)))))
            (do (set! %dp-cur (pair (byte-at (first %dp-piece) %dp-pos) %dp-cur))
                (set! %dp-pos (+ %dp-pos 1))
                (self (+ k 1)))))))
    (go 0)))

; the first K bytes of the lists A and B are the same
(def %dp-same?
  (fn (self a b k)
    (match
      ((= k 0) #t)
      ((if (null? a) #t (null? b)) #f)
      ((= (first a) (first b)) (self (rest a) (rest b) (- k 1)))
      (#t #f))))

(def %dp-zeros (fn (self k acc) (if (<= k 0) acc (self (- k 1) (pair 0 acc)))))

; busybox's get: the next block, in order, or nil at the end of the input.  A
; block the same as the last is folded: the first of a run is `*`.
(def %dp-get!
  (fn (_)
    (def bs %dp-blocksize)
    (def go
      (fn (self need nread)
        (if (if (= %dp-length 0) #t (if %dp-ateof (not (%dp-next!)) #f))
          (if (= need bs) ()
            (let ((block (append (reverse %dp-cur) (%dp-zeros need ()))))
              (do (if (if (eq? %dp-vflag (lit all)) #f
                        (if (eq? %dp-vflag (lit first)) #f (%dp-same? (reverse %dp-cur) %dp-sav nread)))
                    (if (eq? %dp-vflag (lit dup)) () (%dp-put "*\n"))
                    ())
                  (set! %dp-eaddress (+ %dp-address nread))
                  (set! %dp-cur ())
                  block)))
          (let ((n (%dp-read! (if (= %dp-length -1) need (if (< %dp-length need) %dp-length need)))))
            (if (= n 0) (do (set! %dp-ateof #t) (self need nread))
              (do (set! %dp-ateof #f)
                  (if (= %dp-length -1) () (set! %dp-length (- %dp-length n)))
                  (if (> (- need n) 0) (self (- need n) (+ nread n))
                    (let ((block (reverse %dp-cur)))
                      (if (if (eq? %dp-vflag (lit all)) #t
                            (if (eq? %dp-vflag (lit first)) #t (not (%dp-same? block %dp-sav bs))))
                        (do (if (if (eq? %dp-vflag (lit dup)) #t (eq? %dp-vflag (lit first)))
                              (set! %dp-vflag (lit wait)) ())
                            (set! %dp-cur ())
                            block)
                        (do (if (eq? %dp-vflag (lit wait)) (%dp-put "*\n") ())
                            (set! %dp-vflag (lit dup))
                            (set! %dp-savaddress (+ %dp-savaddress bs))
                            (set! %dp-address %dp-savaddress)
                            (set! %dp-cur ())
                            (self bs 0)))))))))))
    (do (if %dp-started
          (do (set! %dp-savaddress (+ %dp-savaddress bs))
              (set! %dp-address %dp-savaddress))
          (do (set! %dp-started #t)
              (set! %dp-address 0)
              (set! %dp-sav (%dp-zeros bs ()))))
        (go bs 0))))

; --- the dump ---------------------------------------------------------------------------

; the format strings compiled: each a list of its units, each unit (IGNORE
; REPS PRINTERS)
(def %dp-compiled ())

(def %dp-compile-all!
  (fn (_)
    (set! %dp-compiled
      (map (fn (_ fs)
             (map (fn (_ fu)
                    (list (%dp-fu-ignore fu) (%dp-fu-reps fu) (map %dp-compile (%dp-fu-prs fu))))
                  (vec-ref fs 0)))
           %dp-fss))))

; one block through every format string
(def %dp-block!
  (fn (_ block)
    (def saveaddress %dp-address)
    (def pr-loop
      (fn (self ps bp cnt)
        (if (if (null? ps) #t %dp-stop) bp
          (let ((u (first ps)))
            (let ((past (if (> %dp-eaddress 0) (>= %dp-address %dp-eaddress) #f)))
              (if (if past (not (null? %dp-xxd-eof)) #f)
                (do (%dp-put %dp-xxd-eof) (set! %dp-stop #t) bp)
                (do ((rest (rest u)) bp (if (= cnt 1) (first (rest u)) #f) past)
                    (set! %dp-address (+ %dp-address (first u)))
                    (self (rest ps) (%cu-nthrest-or-nil (first u) bp) cnt))))))))
    (def rep-loop
      (fn (self prs bp cnt)
        (if (if (= cnt 0) #t %dp-stop) bp
          (self prs (pr-loop prs bp cnt) (- cnt 1)))))
    (def fu-loop
      (fn (self fus bp)
        (if (if (null? fus) #t (if %dp-stop #t (first (first fus)))) ()
          (let ((fu (first fus)))
            (self (rest fus) (rep-loop (%cu-nth 2 fu) bp (%cu-nth 1 fu)))))))
    (def fs-loop
      (fn (self fss)
        (if (if (null? fss) #t %dp-stop) ()
          (do (set! %dp-address saveaddress)
              (fu-loop (first fss) block)
              (self (rest fss))))))
    (do (fs-loop %dp-compiled)
        (set! %dp-sav block))))

(def %cu-nthrest-or-nil
  (fn (self n l) (if (if (= n 0) #t (null? l)) l (self (- n 1) (rest l)))))

; the end: the %_A unit's offset and text, once
(def %dp-end!
  (fn (_)
    (if (if (null? %dp-endfu) #t %dp-stop) ()
      (if (if (= %dp-eaddress 0) (= %dp-address 0) #f) ()
        (do (if (= %dp-eaddress 0) (set! %dp-eaddress %dp-address) ())
            (map (fn (_ pr)
                   (match
                     ((eq? (vec-ref pr 0) (lit address))
                       (do (%dp-put (vec-ref pr 2))
                           (%dp-conv! (vec-ref pr 3) (vec-ref pr 4) (+ %dp-eaddress %dp-displayoff))
                           (%dp-put (vec-ref pr 5))))
                     ((eq? (vec-ref pr 0) (lit text)) (%dp-put (vec-ref pr 2)))
                     (#t ())))
              (%dp-fu-prs %dp-endfu)))))))

; busybox's bb_dump_dump: the formats sized and rewritten, then FILES dumped
; (standard input when there are none).  Answers the status.
(def %cu-dump
  (fn (_ files)
    (def size-all
      (fn (self fss)
        (if (null? fss) ()
          (let ((b (%dp-size (vec-ref (first fss) 0))))
            (do (vec-set! (first fss) 1 b)
                (if (> b %dp-blocksize) (set! %dp-blocksize b) ())
                (self (rest fss)))))))
    (def run
      (fn (self k)
        (if %dp-stop ()
          (let ((block (%dp-get!)))
            (if (null? block) ()
              (do (%dp-block! block)
                  (%dp-flush!)
                  (%cu-sweep-tick! 7)
                  (self (+ k 1))))))))
    (if (not (null? %dp-error)) 1
      (do (size-all %dp-fss)
          (map %dp-rewrite %dp-fss)
          (if (not (null? %dp-error)) 1
            (do (%dp-compile-all!)
                (set! %dp-argv files)
                (run 0)
                (%dp-end!)
                (%dp-flush!)
                (%dp-close!)
                %dp-exit))))))

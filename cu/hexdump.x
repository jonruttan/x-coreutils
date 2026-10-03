; # x-coreutils -- the small tools, as applets
;
; ## cu/hexdump.x -- hexdump, hd and xxd
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's util-linux/hexdump.c and hexdump_xxd.c, each a set of formats for
; the dump engine (cu/dump.x).  hd is hexdump -C.  xxd's -r reads a dump back
; into bytes, which is its own loop and not the engine's.

; --- busybox's numbers ------------------------------------------------------------

(def %hx-suffixes
  (list (pair "KiB" 1024) (pair "kiB" 1024) (pair "K" 1024) (pair "k" 1024)
        (pair "MiB" 1048576) (pair "miB" 1048576) (pair "M" 1048576) (pair "m" 1048576)
        (pair "GiB" 1073741824) (pair "giB" 1073741824) (pair "G" 1073741824)
        (pair "g" 1073741824) (pair "KB" 1000) (pair "MB" 1000000) (pair "GB" 1000000000)))

(def %hx-hex-digit
  (fn (_ c)
    (match
      ((if (>= c #\0) (<= c #\9) #f) (- c #\0))
      ((if (>= (| c 32) #\a) (<= (| c 32) #\f) #f) (+ (- (| c 32) #\a) 10))
      (#t -1))))

; S read by strtoul with base 0 from I: 0x hex, 0 octal, else decimal.
; Answers (VALUE . END), VALUE nil past LIMIT, END where the digits stop.
(def %hx-strtoul
  (fn (_ s i base limit)
    (def n (byte-len s))
    (def at (fn (_ k) (if (< k n) (byte-at s k) 0)))
    (def hex-prefix
      (if (if (= (at i) #\0) (= (| (at (+ i 1)) 32) #\x) #f)
        (>= (%hx-hex-digit (at (+ i 2))) 0) #f))
    (def b (match ((> base 0) base) (hex-prefix 16) ((= (at i) #\0) 8) (#t 10)))
    (def start (if (if hex-prefix (if (= base 0) #t (= base 16)) #f) (+ i 2) i))
    (def go
      (fn (self k acc)
        (let ((d (%hx-hex-digit (at k))))
          (if (if (< d 0) #t (>= d b)) (pair acc k)
            (if (if (null? acc) #t (> acc (%cal/ (- limit d) b)))
              (self (+ k 1) ())
              (self (+ k 1) (+ (* acc b) d)))))))
    (go start 0)))

; S as busybox's xstrtou_range_sfx reads it for APPLET: no sign, no blank,
; base 0, then one of SUFFIXES or nothing; past LIMIT, what the type holds,
; is invalid, and outside LO..HI out of range.  Answers the number, or nil
; once the trouble is said.
(def %hx-number
  (fn (_ applet s lo hi limit suffixes)
    (def c0 (if (> (byte-len s) 0) (byte-at s 0) 0))
    ; a sign or a blank first is refused before strtoul sees it
    (def signed (match ((= (byte-len s) 0) #t) ((= c0 #\-) #t) ((= c0 #\+) #t) (#t (%ts-space? c0))))
    (def r (if signed (pair () 0) (%hx-strtoul s 0 0 limit)))
    (def tail (substring s (rest r) (byte-len s)))
    (def e (%hx-assoc tail suffixes))
    (def scale (match ((= (byte-len tail) 0) 1) ((null? e) ()) (#t (rest e))))
    (def v (match ((null? (first r)) ()) ((null? scale) ()) ((= (rest r) 0) ()) (#t (* (first r) scale))))
    (match
      ((null? v)
        (do (file-write 2 (string-concat (list applet ": invalid number '" s "'\n"))) ()))
      ((if (> v hi) #t (< v lo))
        (do (file-write 2
              (string-concat
                (list applet ": number " s " is not in " (%cu-int->str lo) ".."
                      (%cu-int->str hi) " range\n")))
            ()))
      (#t v))))

(def %hx-assoc
  (fn (self k l) (if (null? l) () (if (string=? (first (first l)) k) (first l) (self k (rest l))))))

(def %hx-uint-max 4294967295)
(def %hx-int-max 2147483647)
(def %hx-off-max 9223372036854775807)

; --- hexdump and hd ---------------------------------------------------------------

; busybox's add_format: the offset at each line, and once at the end
(def %hx-add-format
  (fn (_ fmt)
    (do (%cu-dump-add "\"%07_Ax\n\"")
        (%cu-dump-add (string-concat (list "\"%07_ax\"" fmt "\"\"\n\""))))))

(def %hx-add-c
  (fn (_)
    (do (%cu-dump-add "\"%08_Ax\n\"")
        (%cu-dump-add "\"%08_ax \"8/1 \" %02x\"\" \"8/1 \" %02x\"")
        (%cu-dump-add "\"  |\"16/1 \"%_p\"\"|\n\""))))

(def %hx-flag-formats
  (list (pair "-b" "16/1 \" %03o")
        (pair "-c" "16/1 \" %3_c")
        (pair "-d" "8/2 \"   %05u")
        (pair "-o" "8/2 \"  %06o")
        (pair "-x" "8/2 \"    %04x")))

; a -f file's lines, each that is not blank or a # comment added as a format;
; nil once it will not open
(def %hx-add-file
  (fn (_ name)
    (let ((text (if (file-exists? name) (file-read-all name) ())))
      (if (null? text)
        (do (file-write 2 (string-concat (list "hexdump: can't open '" name
                                               "': No such file or directory\n")))
            ())
        (do (map (fn (_ line)
                   (let ((i (%dp-skip-ws line 0)))
                     (if (if (< i (byte-len line)) (not (= (byte-at line i) #\#)) #f)
                       (%cu-dump-add (substring line i (byte-len line)))
                       ())))
                 (%cu-lines text))
            #t)))))

(def %cu-hd
  (fn (_ argv stdin-thunk)
    (do (%cu-dump-reset! "hd" stdin-thunk)
        (%hx-add-c)
        (%cu-dump argv))))

; hexdump [-bcdoxCv] [-e FMT] [-f FMT_FILE] [-n LEN] [-s OFS] [FILE]...  Each
; of -b -c -d -o -x -C adds its formats, each -e and -f its own; with none,
; -x's two-byte hex less one space.
(def %cu-hexdump
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "hexdump" argv))
    (def on (Assoc get (lit on) o))
    (def n-arg (Opts value o "-n"))
    (def s-arg (Opts value o "-s"))
    (def len (if (null? n-arg) -1
               (%hx-number "hexdump" n-arg 0 %hx-int-max %hx-uint-max %hx-suffixes)))
    (def skip (if (null? s-arg) 0
                (%hx-number "hexdump" s-arg 0 %hx-off-max %hx-off-max %hx-suffixes)))
    (def add-flags
      (fn (self fs)
        (if (null? fs) ()
          (let ((f (first fs)))
            (do (let ((e (%hx-assoc f %hx-flag-formats)))
                  (if (null? e) () (%hx-add-format (rest e))))
                (if (string=? f "-C") (%hx-add-c) ())
                (self (rest fs)))))))
    (def add-files
      (fn (self names)
        (if (null? names) #t
          (if (%hx-add-file (first names)) (self (rest names)) #f))))
    (if (if (null? len) #t (null? skip)) 1
      (do (%cu-dump-reset! "hexdump" stdin-thunk)
          (add-flags on)
          (map %cu-dump-add (Opts values o "-e"))
          (if (add-files (Opts values o "-f"))
            (do (if (null? %dp-fss) (%hx-add-format "8/2 \" %04x") ())
                (%cu-dump-length! len)
                (%cu-dump-skip! skip)
                (if (Opts on? o "-v") (%cu-dump-all!) ())
                (%cu-dump (Opts operands o)))
            1)))))

; --- xxd ----------------------------------------------------------------------------

; NAME as a C identifier, as busybox's print_C_style spells it
(def %xxd-c-name
  (fn (_ name)
    (def alnum?
      (fn (_ c) (if (if (>= c #\0) (<= c #\9) #f) #t
                  (if (>= (| c 32) #\a) (<= (| c 32) #\z) #f))))
    (def go
      (fn (self i acc)
        (if (>= i (byte-len name)) (bytes->str (reverse acc))
          (self (+ i 1) (pair (if (alnum? (byte-at name i)) (byte-at name i) #\_) acc)))))
    (string-append
      (if (if (> (byte-len name) 0) (%dp-digit? (byte-at name 0)) #f) "__" "")
      (go 0 ()))))

; -o: busybox's xstrtoll, base 0, a leading - allowed
(def %xxd-signed
  (fn (_ s)
    (if (if (> (byte-len s) 0) (= (byte-at s 0) #\-) #f)
      (let ((v (%hx-number "xxd" (substring s 1 (byte-len s)) 0 %hx-off-max %hx-off-max ())))
        (if (null? v) () (- 0 v)))
      (%hx-number "xxd" s 0 %hx-off-max %hx-off-max ()))))

; the formats for a dump of COLS bytes a line in groups of BYTES
(def %xxd-formats
  (fn (_ p? i? bytes cols)
    (do (if p? ()
          (if i? (%cu-dump-add "\" \"") (%cu-dump-add "\"%08_ax: \"")))
        (match
          ((if (< bytes 1) #t (>= bytes cols))
            (%cu-dump-add (string-concat (list (%cu-int->str cols) "/1 \"%02x\""))))
          ((= bytes 1)
            (%cu-dump-add
              (string-concat (list (%cu-int->str cols) (if i? "/1 \" 0x%02x,\"" "/1 \"%02x \"")))))
          (#t
            (%cu-dump-add
              (string-concat
                (map (fn (_ i) (if (if (= i cols) #t (not (= (% i bytes) 0)))
                                 "/1 \"%02x\"" "/1 \"%02x \""))
                     (List range 1 (+ cols 1)))))))
        (if (if p? #t i?)
          (do (%cu-dump-add "\"\n\"") (%cu-dump-xxd-eof! "\n"))
          (%cu-dump-add
            (string-concat (list "\"  \"" (%cu-int->str cols) "/1 \"%_p\"\"\n\"")))))))

; xxd [-ri] [-ps] [-g N] [-c N] [-l LEN] [-s OFS] [-o OFS] [FILE]
(def %cu-xxd
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "xxd" argv))
    (def ops (Opts operands o))
    (def p? (if (Opts on? o "-p") #t (Opts on? o "-ps")))
    (def num
      (fn (_ flag lo hi limit dflt)
        (let ((v (Opts value o flag)))
          (if (null? v) dflt (%hx-number "xxd" v lo hi limit ())))))
    (def len (num "-l" 0 %hx-int-max %hx-uint-max -1))
    (def skip (if (null? len) () (num "-s" 0 %hx-off-max %hx-off-max 0)))
    (match
      ((> (length ops) 1) (%cu-usage "xxd"))
      ((null? skip) 1)
      ((Opts on? o "-r") (%xxd-reverse p? (if (null? ops) "-" (first ops)) skip stdin-thunk))
      (#t (%xxd-dump o ops p? len skip stdin-thunk)))))

; the dump: -o, then -g and -c, decimal as busybox's xatoi_positive reads
; them; -i names the array for the file, when there is one
(def %xxd-dump
  (fn (_ o ops p? len skip stdin-thunk)
    (def i? (Opts on? o "-i"))
    (def off (let ((v (Opts value o "-o"))) (if (null? v) 0 (%xxd-signed v))))
    (def g (let ((v (Opts value o "-g"))) (if (null? v) 2 (%cu-range-number "xxd" v 0 %hx-int-max))))
    (def c (let ((v (Opts value o "-c"))) (if (null? v) 0 (%cu-range-number "xxd" v 0 %hx-int-max))))
    (def cols (match ((null? c) 0) ((> c 0) c) (p? 30) (i? 12) (#t 16)))
    (def named (if i? (pair? ops) #f))
    (match
      ((null? off) 1)
      ((null? g) 1)
      ((null? c) 1)
      (#t
        (do (%cu-dump-reset! "xxd" stdin-thunk)
            (%cu-dump-all!)
            (%cu-dump-length! len)
            (%cu-dump-skip! skip)
            (%cu-dump-displayoff! off)
            (%xxd-formats p? i? (match (p? cols) (i? 1) (#t g)) cols)
            (if named
              (file-write 1 (string-concat
                              (list "unsigned char " (%xxd-c-name (first ops)) "[] = {\n")))
              ())
            (let ((st (%cu-dump ops)))
              (do (if (if named (= st 0) #f)
                    (file-write 1 (string-concat
                                    (list "};\nunsigned int " (%xxd-c-name (first ops)) "_len = "
                                          (%cu-int->str (%cu-dump-address)) ";\n")))
                    ())
                  st)))))))

; --- xxd -r ------------------------------------------------------------------------

; NAME's lines, read on demand: a thunk answering the next line without its
; newline, or nil at the end
(def %xxd-lines
  (fn (_ src)
    (def held (list "" #f))        ; the text not yet split, and the end reached
    (def next
      (fn (self)
        (let ((t (first held)))
          (let ((nl (%dp-find t 0 #\newline)))
            (if (>= nl 0)
              (do (%set-first! held (substring t (+ nl 1) (byte-len t)))
                  (substring t 0 nl))
              (if (%cu-nth 1 held)
                (if (= (byte-len t) 0) ()
                  (do (%set-first! held "") t))
                (let ((p (src)))
                  (if (if (Err err? p) #t (= (rest p) 0))
                    (do (%set-first! (rest held) #t) (self))
                    (do (%set-first! held (string-append t (%cu-run-text p))) (self))))))))))
    next))

; busybox's reverse: a dump read back, the offset at each line's start (not
; under -p) placing what follows -- by seeking standard output, or where it
; will not seek, by writing zeros up to it -- and the hex digits in pairs
; written as bytes.  One stray character between digits is passed over.
;
; The run's state is a vector: the bytes to write (newest first), the offset
; of the next, the -s offset added to each line's, -p, and the line source.
(def %xr-out (fn (_ rv) (vec-ref rv 0)))
(def %xr-cur (fn (_ rv) (vec-ref rv 1)))
(def %xr-skip (fn (_ rv) (vec-ref rv 2)))
(def %xr-p? (fn (_ rv) (vec-ref rv 3)))
(def %xr-line (fn (_ rv) ((vec-ref rv 4))))

(def %xr-flush!
  (fn (_ rv)
    (let ((bs (reverse (%xr-out rv))))
      (if (null? bs) ()
        (do (file-write-run 1 (pair (bytes->str bs) (length bs)))
            (vec-set! rv 0 ()))))))

(def %xr-put!
  (fn (_ rv b)
    (do (vec-set! rv 0 (pair b (%xr-out rv)))
        (vec-set! rv 1 (+ (%xr-cur rv) 1)))))

(def %xr-die
  (fn (_ rv msg)
    (do (%xr-flush! rv) (file-write 2 (string-concat (list "xxd: " msg "\n"))) 1)))

(def %hx-alnum?
  (fn (_ c) (if (>= (%hx-hex-digit c) 0) #t (if (>= (| c 32) #\a) (<= (| c 32) #\z) #f))))

; standard output moved to OFS: sought, or where it will not seek, zeros
; written up to it; #f where it is behind and will not seek
(def %xr-seek!
  (fn (_ rv ofs)
    (match
      ((= ofs (%xr-cur rv)) #t)
      ((>= (do (%xr-flush! rv) (File seek 1 ofs)) 0) (do (vec-set! rv 1 ofs) #t))
      ((< ofs (%xr-cur rv)) #f)
      (#t (do (vec-set! rv 0 (%dp-zeros (- ofs (%xr-cur rv)) ()))
              (vec-set! rv 1 ofs)
              (%xr-flush! rv)
              #t)))))

; a line's offset, read in hex and sought to: (#t . P) the place after it
; and its colon, #f where it would not seek, or the text that is not a number
(def %xr-address
  (fn (_ rv buf)
    (def p (%dp-skip-ws buf 0))
    (def r (if (%hx-alnum? (%dp-at buf p)) (%hx-strtoul buf p 16 %hx-off-max) (pair () p)))
    (def e (rest r))
    (match
      ((null? (first r)) (substring buf p (byte-len buf)))
      ((%hx-alnum? (%dp-at buf e)) (substring buf p (byte-len buf)))
      ((%xr-seek! rv (+ (first r) (%xr-skip rv)))
        (pair #t (if (= (%dp-at buf e) #\:) (+ e 1) e)))
      (#t #f))))

; The walk, from a STEP: `line` starts BUF, a line (nil at the end); `high`
; reads a byte's first digit from P, BAD once one character has been passed
; over; `low` its second, VAL holding the first.  Answers the status.
(def %xr-walk
  (fn (self rv step buf p val bad)
    (def p? (%xr-p? rv))
    (def p1 (if (if p? (not (eq? step (lit line))) #f) (%dp-skip-ws buf p) p))
    (def c (if (eq? step (lit line)) 0 (%dp-at buf p1)))
    (def d (%hx-hex-digit c))
    (match
      ((eq? step (lit line))
        (match
          ((null? buf) (do (%xr-flush! rv) 0))
          (p? (self rv (lit high) buf 0 0 #f))
          (#t
            (let ((r (%xr-address rv buf)))
              (match
                ((eq? r #f) (%xr-die rv "cannot seek: Illegal seek"))
                ((pair? r) (self rv (lit high) buf (rest r) 0 #f))
                (#t (%xr-die rv (string-concat (list "invalid number '" r "'")))))))))
      ((eq? step (lit high))
        (match
          ((>= d 0) (self rv (lit low) buf (+ p1 1) (* 16 d) bad))
          ((if (= c 0) #t bad) (self rv (lit line) (%xr-line rv) 0 0 #f))
          (#t (self rv (lit high) buf (+ p1 1) 0 #t))))
      ((>= d 0)
        (do (%xr-put! rv (+ val d)) (self rv (lit high) buf (+ p1 1) 0 #f)))
      ((not (= c 0))
        (let ((q (%hx-next-xdigit buf (+ p1 1))))
          (if (< q 0) (self rv (lit line) (%xr-line rv) 0 0 #f)
            (self rv (lit high) buf q 0 bad))))
      (#t (%xr-low-next self rv val bad)))))

; a second digit wanted at the end of a line: under -p the digits pair across
; the newline; otherwise the next line starts afresh
(def %xr-low-next
  (fn (_ walk rv val bad)
    (let ((next (%xr-line rv)))
      (match
        ((null? next) (do (%xr-flush! rv) 0))
        ((%xr-p? rv) (walk rv (lit low) next 0 val bad))
        (#t (walk rv (lit line) next 0 0 #f))))))

(def %xxd-reverse
  (fn (_ p? name skip stdin-thunk)
    (def src (%cu-pieces name stdin-thunk))
    (if (Err err? src)
      (do (file-write 2 (string-concat (list "xxd: can't open '" name "': "
                                             (file-err-text src) "\n")))
          1)
      (let ((rv (vec-build 5 (fn (_ i)
                               (match ((= i 0) ()) ((= i 1) 0) ((= i 2) skip) ((= i 3) p?)
                                      (#t (%xxd-lines src)))))))
        (let ((st (%xr-walk rv (lit line) (%xr-line rv) 0 0 #f)))
          (do (src (lit close)) st))))))

; the index of the next hex digit in S from I, or -1 at its end
(def %hx-next-xdigit
  (fn (self s i)
    (if (>= i (byte-len s)) -1
      (if (>= (%hx-hex-digit (byte-at s i)) 0) i (self s (+ i 1))))))

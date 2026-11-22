; # x-coreutils -- the small tools, as applets
;
; ## lib/coreutils/stty.x -- stty: a terminal's settings, shown and changed
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's stty (coreutils/stty.c).  Alone it shows the speed, the line
; discipline, every control character and the modes that differ from `sane`;
; -a shows every mode and the window's size too, and -g the settings as one
; line stty reads back.  Otherwise each SETTING is checked before any is made:
; a mode (-MODE turns one off where that may be done), a control character and
; its value, rows, cols, size, speed, ispeed, ospeed, line, a baud, or a line
; -g wrote.  They are made in order on a copy of the settings, which is then
; applied and read again: a terminal that kept any of its own is said.  -F
; names the device; standard input is the one otherwise.
;
; The modes, their values and the struct they live in are x's Term, which
; names each one the way busybox does; this file holds what busybox adds:
; which modes `sane` sets and clears, which may be turned off, which are shown,
; and the order they are shown in.  A mode this OS lacks is left out, as
; busybox's #if leaves it out.  The device is opened as busybox opens it, to
; read without waiting; busybox then makes it block again, which nothing here
; would notice, as stty never reads it.

(module coreutils/stty)

(import coreutils/prims byte-at byte-len cu-err-label cu-hexs cu-int->str
  cu-stdin-to-command! file-close file-err-text file-open-err file-write
  hx-strtoul libc-strerror string-append string=? substring sys-getenv sys-isatty)
(import coreutils/vi vi-dim)

(import x/repl/term)

(def %st-die
  (fn (_ msg)
    (do (file-write 2 (%str-concat (list "stty: " msg "\n")))
        (Err raise (lit stty) msg ()))))

; --- the modes ------------------------------------------------------------------

; Busybox's flags for a mode: set by `sane`, cleared by `sane`, may be turned
; off with a leading -, and not shown.
(def %st-sane-set 1)
(def %st-sane-unset 2)
(def %st-rev 4)
(def %st-omit 8)

(def %st-num= (fn (_ a b) (if (null? a) (null? b) (if (null? b) #f (= a b)))))

(def %st-has? (fn (_ name) (not (null? (List find (fn (_ r) (eq? (first r) name)) (Term mode-rows))))))

; (NAME KIND FLAGS TERM): KIND busybox's control, input, output or local --
; the c_cflag, c_iflag, c_oflag or c_lflag the mode is in, which is also the
; line it is shown on -- or combination, a mode made of others; TERM the mode
; Term names, which an alias shares.  In busybox's order.
(def %st-all-modes
  (let ((sset %st-sane-set) (sunset %st-sane-unset) (rev %st-rev) (omit %st-omit))
    (list
      (list "evenp" (lit combination) (| rev omit) ()) (list "parity" (lit combination) (| rev omit) ())
      (list "oddp" (lit combination) (| rev omit) ()) (list "nl" (lit combination) (| rev omit) ())
      (list "ek" (lit combination) omit ()) (list "sane" (lit combination) omit ())
      (list "cooked" (lit combination) (| rev omit) ()) (list "raw" (lit combination) (| rev omit) ())
      (list "pass8" (lit combination) (| rev omit) ()) (list "litout" (lit combination) (| rev omit) ())
      (list "cbreak" (lit combination) (| rev omit) ()) (list "crt" (lit combination) omit ())
      (list "dec" (lit combination) omit ())
      (list "decctlq" (lit combination) (| rev omit) (lit ixany))
      (list "tabs" (lit combination) (| rev omit) (lit tab0))
      (list "lcase" (lit combination) (| rev omit) (lit xcase))
      (list "LCASE" (lit combination) (| rev omit) (lit xcase))
      (list "parenb" (lit control) rev (lit parenb)) (list "parodd" (lit control) rev (lit parodd))
      (list "cmspar" (lit control) rev (lit cmspar))
      (list "cs5" (lit control) 0 (lit cs5)) (list "cs6" (lit control) 0 (lit cs6))
      (list "cs7" (lit control) 0 (lit cs7)) (list "cs8" (lit control) 0 (lit cs8))
      (list "hupcl" (lit control) rev (lit hupcl)) (list "hup" (lit control) (| rev omit) (lit hupcl))
      (list "cstopb" (lit control) rev (lit cstopb)) (list "cread" (lit control) (| sset rev) (lit cread))
      (list "clocal" (lit control) rev (lit clocal)) (list "crtscts" (lit control) rev (lit crtscts))
      (list "ignbrk" (lit input) (| sunset rev) (lit ignbrk)) (list "brkint" (lit input) (| sset rev) (lit brkint))
      (list "ignpar" (lit input) rev (lit ignpar)) (list "parmrk" (lit input) rev (lit parmrk))
      (list "inpck" (lit input) rev (lit inpck)) (list "istrip" (lit input) rev (lit istrip))
      (list "inlcr" (lit input) (| sunset rev) (lit inlcr)) (list "igncr" (lit input) (| sunset rev) (lit igncr))
      (list "icrnl" (lit input) (| sset rev) (lit icrnl)) (list "ixon" (lit input) rev (lit ixon))
      (list "ixoff" (lit input) (| sunset rev) (lit ixoff)) (list "tandem" (lit input) (| omit rev) (lit ixoff))
      (list "iuclc" (lit input) (| sunset rev) (lit iuclc)) (list "ixany" (lit input) (| sunset rev) (lit ixany))
      (list "imaxbel" (lit input) (| sset rev) (lit imaxbel)) (list "iutf8" (lit input) (| sunset rev) (lit iutf8))
      (list "opost" (lit output) (| sset rev) (lit opost)) (list "olcuc" (lit output) (| sunset rev) (lit olcuc))
      (list "ocrnl" (lit output) (| sunset rev) (lit ocrnl)) (list "onlcr" (lit output) (| sset rev) (lit onlcr))
      (list "onocr" (lit output) (| sunset rev) (lit onocr)) (list "onlret" (lit output) (| sunset rev) (lit onlret))
      (list "ofill" (lit output) (| sunset rev) (lit ofill)) (list "ofdel" (lit output) (| sunset rev) (lit ofdel))
      (list "nl1" (lit output) sunset (lit nl1)) (list "nl0" (lit output) sset (lit nl0))
      (list "cr3" (lit output) sunset (lit cr3)) (list "cr2" (lit output) sunset (lit cr2))
      (list "cr1" (lit output) sunset (lit cr1)) (list "cr0" (lit output) sset (lit cr0))
      (list "tab3" (lit output) sunset (lit tab3)) (list "tab2" (lit output) sunset (lit tab2))
      (list "tab1" (lit output) sunset (lit tab1)) (list "tab0" (lit output) sset (lit tab0))
      (list "bs1" (lit output) sunset (lit bs1)) (list "bs0" (lit output) sset (lit bs0))
      (list "vt1" (lit output) sunset (lit vt1)) (list "vt0" (lit output) sset (lit vt0))
      (list "ff1" (lit output) sunset (lit ff1)) (list "ff0" (lit output) sset (lit ff0))
      (list "isig" (lit local) (| sset rev) (lit isig)) (list "icanon" (lit local) (| sset rev) (lit icanon))
      (list "iexten" (lit local) (| sset rev) (lit iexten)) (list "echo" (lit local) (| sset rev) (lit echo))
      (list "echoe" (lit local) (| sset rev) (lit echoe)) (list "crterase" (lit local) (| omit rev) (lit echoe))
      (list "echok" (lit local) (| sset rev) (lit echok)) (list "echonl" (lit local) (| sunset rev) (lit echonl))
      (list "noflsh" (lit local) (| sunset rev) (lit noflsh)) (list "xcase" (lit local) (| sunset rev) (lit xcase))
      (list "tostop" (lit local) (| sunset rev) (lit tostop)) (list "echoprt" (lit local) (| sunset rev) (lit echoprt))
      (list "prterase" (lit local) (| omit rev) (lit echoprt)) (list "echoctl" (lit local) (| sset rev) (lit echoctl))
      (list "ctlecho" (lit local) (| omit rev) (lit echoctl)) (list "echoke" (lit local) (| sset rev) (lit echoke))
      (list "crtkill" (lit local) (| omit rev) (lit echoke)) (list "flusho" (lit local) (| sunset rev) (lit flusho))
      (list "extproc" (lit local) (| sunset rev) (lit extproc)))))

; the modes this OS has: a combination whose TERM is nil is everywhere, one
; with a TERM is where that mode is (lcase where xcase, iuclc and olcuc all are)
(def %st-modes
  (List filter
    (fn (_ m)
      (let ((t (List ref 3 m)))
        (match
          ((null? t) #t)
          ((eq? t (lit xcase)) (if (%st-has? (lit xcase)) (if (%st-has? (lit iuclc)) (%st-has? (lit olcuc)) #f) #f))
          (#t (%st-has? t)))))
    %st-all-modes))

(def %st-mode (fn (_ name) (List find (fn (_ m) (string=? (first m) name)) %st-modes)))
(def %st-flag? (fn (_ m flag) (not (= (& (List ref 2 m) flag) 0))))

; --- the control characters -------------------------------------------------

; (NAME TERM SANE SHOWN): SANE the value `sane` gives it, nil for one turned
; off; SHOWN #f for swtch on Darwin, which has no VSWTCH, so busybox makes it
; susp under another name.  min and time are last, as busybox shows them.
(def %st-controls
  (List filter (fn (_ c) (%st-has? (List ref 1 c)))
    (list (list "intr" (lit vintr) 3 #t) (list "quit" (lit vquit) 28 #t)
          (list "erase" (lit verase) 127 #t) (list "kill" (lit vkill) 21 #t)
          (list "eof" (lit veof) 4 #t) (list "eol" (lit veol) () #t)
          (list "eol2" (lit veol2) () #t)
          (if (%st-has? (lit vswtch)) (list "swtch" (lit vswtch) () #t) (list "swtch" (lit vsusp) 26 #f))
          (list "start" (lit vstart) 17 #t) (list "stop" (lit vstop) 19 #t)
          (list "susp" (lit vsusp) 26 #t) (list "dsusp" (lit vdsusp) 25 #t)
          (list "rprnt" (lit vreprint) 18 #t) (list "werase" (lit vwerase) 23 #t)
          (list "lnext" (lit vlnext) 22 #t) (list "flush" (lit vdiscard) 15 #t)
          (list "status" (lit vstatus) 20 #t)
          (list "min" (lit vmin) 1 #t) (list "time" (lit vtime) 0 #t))))

(def %st-control (fn (_ name) (List find (fn (_ c) (string=? (first c) name)) %st-controls)))
(def %st-count? (fn (_ c) (if (string=? (first c) "min") #t (string=? (first c) "time"))))

; --- numbers -------------------------------------------------------------------

; S as busybox's xatoul_range_sfx reads it: decimal digits, then where SFX? one
; of b (512), k and B (1024), from LO to HI
(def %st-number
  (fn (_ s lo hi sfx?)
    (def n (byte-len s))
    (def r (if (if (> n 0) (if (>= (byte-at s 0) #\0) (<= (byte-at s 0) #\9) #f) #f)
             (hx-strtoul s 0 10 18446744073709551615) (pair () 0)))
    (def tail (if (= (rest r) 0) "" (substring s (rest r) n)))
    (def mult (match ((string=? tail "") 1)
                     ((not sfx?) ())
                     ((string=? tail "b") 512)
                     ((string=? tail "k") 1024)
                     ((string=? tail "B") 1024)
                     (#t ())))
    (def v (if (if (= (rest r) 0) #t (null? mult)) () (first r)))
    (match
      ((if (= (rest r) 0) #t (null? mult)) (%st-die (%str-concat (list "invalid number '" s "'"))))
      ((if (null? v) #t (if (< v lo) #t (> (* v mult) hi)))
        (%st-die (%str-concat (list "number " s " is not in " (cu-int->str lo) ".." (cu-int->str hi) " range"))))
      (#t (* v mult)))))

; a speed: an unsigned number, and nil unless it is a baud busybox's table has
(def %st-baud
  (fn (_ s)
    (let ((v (%st-number s 0 4294967295 #f)))
      (if (null? (List find (fn (_ b) (= b v)) (Term bauds))) () v))))

; a control character's value, nil for one turned off: min and time a number,
; else one character as it is, ^- or undef off, ^X its control, ^? DEL, or a
; number
(def %st-char-value
  (fn (_ c arg)
    (def n (byte-len arg))
    (match
      ((%st-count? c) (%st-number arg 0 255 #t))
      ((< n 2) (if (= n 0) 0 (byte-at arg 0)))
      ((if (string=? arg "^-") #t (string=? arg "undef")) ())
      ((= (byte-at arg 0) #\^) (if (= (byte-at arg 1) #\?) 127 (& (byte-at arg 1) 31)))
      (#t (%st-number arg 0 255 #t)))))

; a line -g wrote: four flag words and each control character, in hex,
; colon-separated; nil when ARG is not one
(def %st-recover
  (fn (_ arg)
    (def fields (Str8 split ":" arg))
    (def hex
      (fn (_ f)
        (def n (byte-len f))
        (if (= n 0) ()
          (let ((r (hx-strtoul f 0 16 18446744073709551615)))
            (if (if (= (rest r) n) (not (null? (first r))) #f) (first r) ())))))
    (if (not (= (List length fields) (+ 4 (Term nccs)))) ()
      (let ((ws (List map hex fields)))
        (if (null? (List find (fn (_ w) (null? w)) ws)) ws ())))))

; --- the first pass: every argument checked ---------------------------------

(def %st-params (list "line" "rows" "cols" "columns" "size" "speed" "ispeed" "ospeed"))
(def %st-param-arg? (fn (_ p) (not (if (string=? p "size") #t (string=? p "speed")))))

(def %st-bad (fn (_ arg) (%st-die (%str-concat (list "invalid argument '" arg "'")))))
(def %st-needs (fn (_ arg next) (when (null? next) (%st-die (string-append arg " requires an argument")))))
(def %st-dash? (fn (_ arg) (if (> (byte-len arg) 0) (= (byte-at arg 0) #\-) #f)))

; Each step of the first pass answers (TAKEN ACTION ALL? G? DEVICE): TAKEN the
; words it read (1, or 2 with the argument after), ACTION nil where there is
; none for the second pass.

; -F in ARG at I: the rest of ARG names the device, or NEXT does
(def %st-option-f
  (fn (_ arg i next all? g? dev)
    (unless (null? dev) (%st-die "only one device may be specified"))
    (if (< (+ i 1) (byte-len arg))
      (list 1 () all? g? (substring arg (+ i 1) (byte-len arg)))
      (do (%st-needs "-F" next) (list 2 () all? g? next)))))

; ARG's cluster of -a, -g and -F
(def %st-options
  (fn (_ arg next all? g? dev)
    (def go
      (fn (self i all? g?)
        (if (>= i (byte-len arg)) (list 1 () all? g? dev)
          (let ((c (byte-at arg i)))
            (match
              ((= c #\a) (self (+ i 1) #t g?))
              ((= c #\g) (self (+ i 1) all? #t))
              ((= c #\F) (%st-option-f arg i next all? g? dev))
              (#t (%st-bad arg)))))))
    (go 1 all? g?)))

; a parameter, as (TAKEN . ACTION); the line where there is none is read and dropped
(def %st-param-word
  (fn (_ arg next)
    (when (%st-param-arg? arg) (%st-needs arg next))
    (def v (match
             ((if (string=? arg "ispeed") #t (string=? arg "ospeed")) (%st-baud next))
             ((%st-param-arg? arg) (%st-number next 1 2147483647 #t))
             (#t ())))
    (pair (if (%st-param-arg? arg) 2 1)
          (if (if (string=? arg "line") (not (%st-has? (lit line))) #f) () (pair (lit param) (pair arg v))))))

; a line -g wrote, or a speed
(def %st-other-word
  (fn (_ arg)
    (def ws (%st-recover arg))
    (if (not (null? ws)) (pair 1 (pair (lit words) ws))
      (let ((b (%st-baud arg)))
        (if (null? b) (%st-bad arg) (pair 1 (pair (lit speed) b)))))))

; a word with no -, as (TAKEN . ACTION)
(def %st-word
  (fn (_ arg next)
    (def c (%st-control arg))
    (match
      ((not (null? (%st-mode arg))) (pair 1 (pair (lit mode) (pair (%st-mode arg) #f))))
      ((not (null? c)) (do (%st-needs arg next) (pair 2 (pair (lit control) (pair c (%st-char-value c next))))))
      ((not (null? (List find (fn (_ p) (string=? p arg)) %st-params))) (%st-param-word arg next))
      (#t (%st-other-word arg)))))

(def %st-step
  (fn (_ arg next all? g? dev)
    (def m (if (%st-dash? arg) (%st-mode (substring arg 1 (byte-len arg))) ()))
    (match
      ((not (null? m)) (if (%st-flag? m %st-rev) (list 1 (pair (lit mode) (pair m #t)) all? g? dev) (%st-bad arg)))
      ((%st-dash? arg) (%st-options arg next all? g? dev))
      (#t (let ((w (%st-word arg next))) (list (first w) (rest w) all? g? dev))))))

; ARGV checked as busybox's first pass checks it, as (ACTIONS ALL? G? DEVICE):
; ACTIONS what the second pass does, each (KIND . DATA)
(def %st-parse
  (fn (_ argv)
    (def go
      (fn (self args acts all? g? dev)
        (if (null? args) (list (reverse acts) all? g? dev)
          (let ((s (%st-step (first args) (if (null? (rest args)) () (first (rest args))) all? g? dev)))
            (self (if (= (first s) 2) (rest (rest args)) (rest args))
                  (if (null? (List ref 1 s)) acts (pair (List ref 1 s) acts))
                  (List ref 2 s) (List ref 3 s) (List ref 4 s))))))
    (go argv () #f #f ())))

; --- showing ----------------------------------------------------------------------

; busybox's wrapf over STATE (COLUMN MAX . PIECES): MSG after a space, or on a
; line of its own once it would reach MAX; a message ending in a newline ends
; the line
(def %st-wrap
  (fn (_ st msg)
    (def col (first st))
    (def max (first (rest st)))
    (def out (rest (rest st)))
    (def n (byte-len msg))
    (def lead (match ((= col 0) "") ((= (byte-at msg 0) 10) "") ((>= (+ col 1 n) max) "\n") (#t " ")))
    (def col2 (if (= col 0) n (if (string=? lead "\n") n (+ col 1 n))))
    (pair (if (= (byte-at msg (- n 1)) 10) 0 col2)
          (pair max (pair msg (pair lead out))))))

(def %st-newline (fn (_ st) (if (= (first st) 0) st (%st-wrap st "\n"))))
(def %st-text (fn (_ st) (%str-concat (reverse (rest (rest st))))))

; busybox's visible: M- for the top bit, then ^ and the character a control
; or DEL stands for
(def %st-visible
  (fn (_ ch)
    (def hi (>= ch 128))
    (def c (if hi (- ch 128) ch))
    (def ctl (if (< c 32) #t (= c 127)))
    (%str-concat (list (if hi "M-" "") (if ctl "^" "")
                       (bytes->str (list (match ((= c 127) 63) (ctl (+ c 64)) (#t c))))))))

(def %st-window
  (fn (_ fd)
    (def m (Term measure fd))
    (def rows-env (sys-getenv "LINES"))
    (def cols-env (sys-getenv "COLUMNS"))
    (if (if (null? m) (if (null? rows-env) (null? cols-env) #f) #f) ()
      (pair (vi-dim (if (null? m) 0 (rest m)) rows-env 24)
            (vi-dim (if (null? m) 0 (first m)) cols-env 80)))))

(def %st-show-window
  (fn (_ st fd dev fancy?)
    (def w (%st-window fd))
    (match
      ((not (null? w))
        (%st-wrap st (if fancy?
                       (%str-concat (list "rows " (cu-int->str (first w)) "; columns " (cu-int->str (rest w)) ";"))
                       (%str-concat (list (cu-int->str (first w)) " " (cu-int->str (rest w)) "\n")))))
      (fancy? st)
      (#t (do (file-write 2 (%str-concat (list "stty: " dev ": no size information for this device\n"))) st)))))

(def %st-show-speed
  (fn (_ st s fancy?)
    (def i (Term setting s (lit ispeed)))
    (def o (Term setting s (lit ospeed)))
    (def is (cu-int->str (if (null? i) 0 i)))
    (def os (cu-int->str (if (null? o) 0 o)))
    (%st-wrap st
      (if (if (null? i) #t (if (= i 0) #t (%st-num= i o)))
        (if fancy? (%str-concat (list "speed " os " baud;")) (string-append os "\n"))
        (if fancy? (%str-concat (list "ispeed " is " baud; ospeed " os " baud;"))
          (%str-concat (list is " " os "\n")))))))

(def %st-show
  (fn (_ s fd dev all? max)
    (def st0 (%st-show-speed (list 0 max) s #t))
    (def st1 (if all? (%st-show-window st0 fd dev #t) st0))
    (def st2 (if (%st-has? (lit line))
               (%st-wrap st1 (%str-concat (list "line = " (cu-int->str (Term setting s (lit line))) ";\n")))
               (%st-newline st1)))
    (def chars (List filter (fn (_ c) (if (List ref 3 c) (not (%st-count? c)) #f)) %st-controls))
    (def st3 (List fold
               (fn (_ st c)
                 (let ((v (Term setting s (List ref 1 c))))
                   (%st-wrap st (%str-concat (list (first c) " = " (if (null? v) "<undef>" (%st-visible v)) ";")))))
               st2 chars))
    (def st4 (%st-newline
               (%st-wrap st3 (%str-concat (list "min = " (cu-int->str (Term setting s (lit vmin)))
                                                "; time = " (cu-int->str (Term setting s (lit vtime))) ";")))))
    (def shown (List filter (fn (_ m) (not (%st-flag? m %st-omit))) %st-modes))
    (def st5
      (first
        (List fold
          (fn (_ acc m)
            (let ((st (if (eq? (List ref 1 m) (rest acc)) (first acc) (%st-newline (first acc))))
                  (on (Term setting s (List ref 3 m))))
              (pair
                (match
                  ((eq? on #t) (if (if all? #t (%st-flag? m %st-sane-unset)) (%st-wrap st (first m)) st))
                  ((if all? (%st-flag? m %st-rev)
                     (= (& (List ref 2 m) (| %st-sane-set %st-rev)) (| %st-sane-set %st-rev)))
                    (%st-wrap st (string-append "-" (first m))))
                  (#t st))
                (List ref 1 m))))
          (pair st4 (lit control)) shown)))
    (%st-text (%st-newline st5))))

(def %st-recoverable
  (fn (_ s)
    (let ((ws (Term words s)))
      (%str-concat
        (pair (cu-hexs (first ws))
              (List append (List map (fn (_ w) (string-append ":" (cu-hexs w))) (rest ws)) (list "\n")))))))

; --- the second pass: the settings made -----------------------------------------

(def %st-set (fn (_ s name v) (do (Term setting! s name v) ())))
(def %st-sets (fn (_ s pairs) (List for-each (fn (_ p) (%st-set s (first p) (rest p))) pairs)))

(def %st-sane!
  (fn (_ s)
    (do (List for-each (fn (_ c) (%st-set s (List ref 1 c) (List ref 2 c))) %st-controls)
        (List for-each
          (fn (_ m)
            (match
              ((eq? (List ref 1 m) (lit combination)) ())
              ((%st-flag? m %st-sane-set) (%st-set s (List ref 3 m) #t))
              ; a delay's other settings: the one sane sets follows and clears
              ; the field, which Term sets but never clears to nothing
              ((%st-flag? m %st-sane-unset)
                (if (null? (List find (fn (_ r) (if (eq? (first r) (List ref 3 m)) (eq? (List ref 1 r) (lit field)) #f))
                                 (Term mode-rows)))
                  (%st-set s (List ref 3 m) #f) ()))
              (#t ())))
          %st-modes))))

; the iflag word cleared whole, as busybox's raw clears it
(def %st-iflag-zero!
  (fn (_ s) (let ((w (Term words s))) (Term words! s (pair 0 (rest w))))))

(def %st-combination!
  (fn (_ s name rev?)
    (match
      ((if (string=? name "evenp") #t (string=? name "parity"))
        (%st-sets s (if rev? (list (pair (lit parenb) #f) (pair (lit cs8) #t))
                      (list (pair (lit parodd) #f) (pair (lit parenb) #t) (pair (lit cs7) #t)))))
      ((string=? name "oddp")
        (%st-sets s (if rev? (list (pair (lit parenb) #f) (pair (lit cs8) #t))
                      (list (pair (lit cs7) #t) (pair (lit parodd) #t) (pair (lit parenb) #t)))))
      ((string=? name "nl")
        (%st-sets s (if rev? (list (pair (lit icrnl) #t) (pair (lit inlcr) #f) (pair (lit igncr) #f)
                                   (pair (lit onlcr) #t) (pair (lit ocrnl) #f) (pair (lit onlret) #f))
                      (list (pair (lit icrnl) #f) (pair (lit onlcr) #f)))))
      ((string=? name "ek") (%st-sets s (list (pair (lit verase) 127) (pair (lit vkill) 21))))
      ((string=? name "sane") (%st-sane! s))
      ((string=? name "cbreak") (%st-set s (lit icanon) rev?))
      ((string=? name "pass8")
        (%st-sets s (if rev? (list (pair (lit cs7) #t) (pair (lit parenb) #t) (pair (lit istrip) #t))
                      (list (pair (lit parenb) #f) (pair (lit cs8) #t) (pair (lit istrip) #f)))))
      ((string=? name "litout")
        (%st-sets s (if rev? (list (pair (lit cs7) #t) (pair (lit parenb) #t) (pair (lit istrip) #t) (pair (lit opost) #t))
                      (list (pair (lit parenb) #f) (pair (lit cs8) #t) (pair (lit istrip) #f) (pair (lit opost) #f)))))
      ((if (string=? name "raw") (not rev?) (if (string=? name "cooked") rev? #f))
        (do (%st-iflag-zero! s)
            (%st-sets s (list (pair (lit opost) #f) (pair (lit isig) #f) (pair (lit icanon) #f) (pair (lit xcase) #f)
                              (pair (lit vmin) 1) (pair (lit vtime) 0)))))
      ((if (string=? name "raw") #t (string=? name "cooked"))
        (%st-sets s (list (pair (lit brkint) #t) (pair (lit ignpar) #t) (pair (lit istrip) #t) (pair (lit icrnl) #t)
                          (pair (lit ixon) #t) (pair (lit opost) #t) (pair (lit isig) #t) (pair (lit icanon) #t))))
      ((string=? name "decctlq") (%st-set s (lit ixany) rev?))
      ((string=? name "tabs") (%st-set s (if rev? (lit tab3) (lit tab0)) #t))
      ((if (string=? name "lcase") #t (string=? name "LCASE"))
        (%st-sets s (list (pair (lit xcase) (not rev?)) (pair (lit iuclc) (not rev?)) (pair (lit olcuc) (not rev?)))))
      ((string=? name "crt") (%st-sets s (list (pair (lit echoe) #t) (pair (lit echoctl) #t) (pair (lit echoke) #t))))
      ((string=? name "dec")
        (%st-sets s (list (pair (lit vintr) 3) (pair (lit verase) 127) (pair (lit vkill) 21)
                          (pair (lit echoe) #t) (pair (lit echoctl) #t) (pair (lit echoke) #t) (pair (lit ixany) #f))))
      (#t ()))))

(def %st-window!
  (fn (_ fd dev cols rows)
    (unless (Term window! fd cols rows)
      (file-write 2 (%str-concat (list "stty: " dev ": " (libc-strerror (Err errno-of -1)) "\n"))))))

; ACTIONS made on S, in order; answers whether any must be applied, and the
; STATE of what was shown
(def %st-act
  (fn (_ s fd dev acts)
    (List fold
      (fn (_ apply? a)
        (let ((kind (first a)) (d (rest a)))
          (match
            ((eq? kind (lit mode))
              (let ((m (first d)) (rev? (rest d)))
                (do (if (eq? (List ref 1 m) (lit combination)) (%st-combination! s (first m) rev?)
                      (%st-set s (List ref 3 m) (not rev?)))
                    #t)))
            ((eq? kind (lit control)) (do (%st-set s (List ref 1 (first d)) (rest d)) #t))
            ((eq? kind (lit words)) (do (Term words! s d) #t))
            ((eq? kind (lit speed)) (do (%st-set s (lit ispeed) d) (%st-set s (lit ospeed) d) #t))
            ((eq? kind (lit param))
              (let ((p (first d)) (v (rest d)))
                (match
                  ((string=? p "line") (do (%st-set s (lit line) v) #t))
                  ((if (string=? p "cols") #t (string=? p "columns")) (do (%st-window! fd dev v ()) apply?))
                  ((string=? p "rows") (do (%st-window! fd dev () v) apply?))
                  ((string=? p "size")
                    (do (file-write 1 (%st-text (%st-show-window (list 0 80) fd dev #f))) apply?))
                  ((string=? p "speed")
                    (do (file-write 1 (%st-text (%st-show-speed (list 0 80) s #f))) apply?))
                  ((string=? p "ispeed") (do (%st-set s (lit ispeed) v) #t))
                  ((string=? p "ospeed") (do (%st-set s (lit ospeed) v) #t))
                  (#t apply?))))
            (#t apply?))))
      #f acts)))

; the settings as busybox's memcmp sees them: the words and the two speeds
(def %st-same?
  (fn (_ a b)
    (def words=
      (fn (self x y)
        (match ((null? x) (null? y)) ((null? y) #f) ((= (first x) (first y)) (self (rest x) (rest y))) (#t #f))))
    (if (words= (Term words a) (Term words b))
      (if (%st-num= (Term setting a (lit ispeed)) (Term setting b (lit ispeed)))
        (%st-num= (Term setting a (lit ospeed)) (Term setting b (lit ospeed))) #f)
      #f)))

; --- stty -------------------------------------------------------------------------

(def %st-device-fail
  (fn (_ dev fd)
    (%st-die (%str-concat (list dev ": " (libc-strerror (if (sys-isatty fd) (Err errno-of -1) 25)))))))

(def %st-main
  (fn (_ argv)
    (def parsed (%st-parse argv))
    (def acts (first parsed))
    (def all? (List ref 1 parsed))
    (def g? (List ref 2 parsed))
    (def file (List ref 3 parsed))
    (when (if all? g? #f) (%st-die "-a and -g are mutually exclusive"))
    (when (if (if all? #t g?) (not (null? acts)) #f) (%st-die "modes may not be set when -a or -g is used"))
    (def dev (if (null? file) "standard input" file))
    (def fd (if (null? file) (do (cu-stdin-to-command!) 0)
              (let ((r (File open file (list (lit rdonly) (lit nonblock)))))
                (if (< r 0)
                  (%st-die (%str-concat (list "can't open '" file "': " (file-err-text (file-open-err r file)))))
                  r))))
    (def s (Term settings fd))
    (when (null? s) (%st-device-fail dev fd))
    (def st
      (match
        ((if all? #t (if g? #t (null? acts)))
          (do (file-write 1 (if g? (%st-recoverable s)
                              (%st-show s fd dev all? (vi-dim (let ((m (Term measure 1))) (if (null? m) 0 (first m)))
                                                              (sys-getenv "COLUMNS") 80))))
              0))
        ((%st-act s fd dev acts)
          (do (unless (Term apply! fd s) (%st-device-fail dev fd))
              (let ((again (Term settings fd)))
                (when (if (null? again) #t (not (%st-same? s again)))
                  (%st-die (string-append dev ": cannot perform all requested operations"))))
              0))
        (#t 0)))
    (unless (null? file) (file-close fd))
    st))

(def cu-stty
  (fn (_ argv stdin-thunk)
    (guard (e (if (eq? (cu-err-label e) (lit stty)) 1 (error e)))
      (%st-main argv))))

(provide coreutils/stty cu-stty)

; # x-coreutils -- the small tools, as applets
;
; ## cu/nmeter.x -- nmeter
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's nmeter (procps/nmeter.c): a line each interval, laid out by a
; format string whose %-fields each show one reading -- a CPU bar, an
; interface's traffic, memory and swap, open files, interrupt, context switch
; and fork rates, the process count, block traffic, the time.  It reads
; Host's cpu, memory, counters, tasks, interfaces, interrupts and disks
; records; a reading the kernel does not give shows as question marks, as
; busybox shows a /proc file it cannot read.
;
; A field is (LABEL READ . STATE): LABEL the text before it, READ a function
; of the field and the sample that answers (TEXT . NEW-STATE).  The first
; sample is taken and thrown away, as busybox's is, to set each rate's last
; count.

(def %nm-scale (fn (_ n) (%vm-four n " kmgtpezy")))
(def %nm-marks (fn (_ k) (%str-make-raw-of k #\?)))

; K copies of the byte C
(def %str-make-raw-of
  (fn (_ k c) (bytes->str ((fn (self i acc) (if (<= i 0) acc (self (- i 1) (pair c acc)))) k ()))))

; A count's change, 0 where it went backwards, as busybox sanitizes one
(def %nm-delta (fn (_ now old) (if (< now old) 0 (- now old))))

; A sample: the records each field reads from, fetched once a line
(def %nm-sample
  (fn (_)
    (list (pair (lit cpu) (host-cpu)) (pair (lit memory) (host-memory))
          (pair (lit counters) (host-counters)) (pair (lit tasks) (host-tasks))
          (pair (lit interfaces) (host-interfaces)) (pair (lit interrupts) (host-interrupts))
          (pair (lit disks) (host-disks)) (pair (lit time) (Sys time-of-day)))))

; --- the readings ------------------------------------------------------------

; %c: a bar of SIZE marks split among system, user, nice, iowait, irq and
; softirq time in proportion, idle the dots, the remainders going to the
; largest fractions
(def %nm-cpu
  (fn (_ size)
    (fn (_ s old)
      (def t (Assoc get (lit cpu) s))
      (def now (map (fn (_ k) (%vm-ticks (Assoc get k t))) (lit (user nice system idle iowait irq softirq))))
      (def d (map (fn (_ p) (%nm-delta (first p) (rest p))) (%vm-zip now (if (null? old) (map (fn (_ x) 0) now) old))))
      (def all (List fold + 0 d))
      (if (= all 0) (pair (%nm-marks size) now)
        (let ((shares (map (fn (_ v) (%ps-div (* size v) all)) d))
              (fracs (map (fn (_ v) (% (* size v) all)) d)))
          (def bumped (%nm-bump shares fracs (- size (List fold + 0 shares))))
          (def run (fn (_ i c) (%str-make-raw-of (cu-nth i bumped) c)))
          (def bar (string-concat (list (run 2 #\S) (run 0 #\U) (run 1 #\N) (run 4 #\D) (run 5 #\I) (run 6 #\i))))
          (pair (%cu-pad-right-with bar size #\.) now))))))

; SHARES with LEFT more added, one at a time to the share with the largest
; fraction, the first of equals, that fraction then spent
(def %nm-bump
  (fn (self shares fracs left)
    (if (<= left 0) shares
      (let ((pos (%nm-max-at fracs)))
        (self (%nm-set-at shares pos (+ (cu-nth pos shares) 1)) (%nm-set-at fracs pos 0) (- left 1))))))

(def %nm-max-at
  (fn (_ vs)
    (def go (fn (self vs i best at) (if (null? vs) at (if (> (first vs) best) (self (rest vs) (+ i 1) (first vs) i) (self (rest vs) (+ i 1) best at)))))
    (go (rest vs) 1 (first vs) 0)))

(def %nm-set-at (fn (self vs i v) (if (= i 0) (pair v (rest vs)) (pair (first vs) (self (rest vs) (- i 1) v)))))

(def %cu-pad-right-with
  (fn (_ s w c) (if (>= (byte-len s) w) s (string-append s (%str-make-raw-of (- w (byte-len s)) c)))))

; A rate of one counter: its change since the last line, compactly; question
; marks where the kernel does not count it
(def %nm-rate
  (fn (_ get)
    (fn (_ s old)
      (def v (get s))
      (if (null? v) (pair "????" old)
        (pair (%nm-scale (%nm-delta v (if (null? old) 0 old))) v)))))

(def %nm-counter (fn (_ k) (fn (_ s) (Assoc get k (Assoc get (lit counters) s)))))

; %i: all interrupts, or source N's, its count summed over the processors
(def %nm-irq
  (fn (_ name)
    (if (str=? name "") (%nm-counter (lit interrupts)) (%nm-irq-of name))))

(def %nm-irq-of (fn (_ name) (fn (_ s) (%nm-irq-count name s))))

; Source NAME's count in sample S, 0 where the table has no such source, nil
; where the kernel counts no interrupts
(def %nm-irq-count
  (fn (_ name s)
    (def hits (filter (fn (_ r) (if (str=? (Assoc get (lit name) r) name) (not (Assoc get (lit soft?) r)) #f))
                (Assoc get (lit interrupts) s)))
    (match
      ((null? (Assoc get (lit interrupts) (Assoc get (lit counters) s))) ())
      ((null? hits) 0)
      (#t (%vm-get (lit total) (first hits))))))

; %n: an interface's bytes in and out, a * before each where errors came
(def %nm-if
  (fn (_ name)
    (fn (_ s old)
      (def r (filter (fn (_ r) (str=? (Assoc get (lit name) r) name)) (Assoc get (lit interfaces) s)))
      (if (null? r) (pair "??????????" old)
        (let ((now (map (fn (_ k) (%vm-get k (first r))) (lit (rx-bytes rx-errors tx-bytes tx-errors)))))
          (def d (map (fn (_ p) (%nm-delta (first p) (rest p))) (%vm-zip now (if (null? old) (list 0 0 0 0) old))))
          (pair (string-concat (list (if (> (cu-nth 1 d) 0) "*" " ") (%nm-scale (first d))
                                     (if (> (cu-nth 3 d) 0) "*" " ") (%nm-scale (cu-nth 2 d))))
                now))))))

; %m and its variants: used (total less free, buffers, cached and slab),
; free, total, dirty, under writeback; bytes
(def %nm-mem
  (fn (_ opt)
    (fn (_ s old)
      (def m (Assoc get (lit memory) s))
      (def g (fn (_ k) (%vm-get k m)))
      (def free (+ (+ (g (lit free)) (g (lit buffers))) (+ (g (lit cached)) (g (lit slab)))))
      (pair (%nm-scale
              (match
                ((str=? opt "d") (g (lit dirty)))
                ((str=? opt "w") (g (lit writeback)))
                ((str=? opt "t") (g (lit total)))
                ((str=? opt "f") free)
                (#t (- (g (lit total)) free))))
            old))))

(def %nm-swap
  (fn (_ s old)
    (def m (Assoc get (lit memory) s))
    (pair (%nm-scale (- (%vm-get (lit swap-total) m) (%vm-get (lit swap-free) m))) old)))

; %f: the file handles in use
(def %nm-files
  (fn (_ s old)
    (def v (Assoc get (lit open-files) (Assoc get (lit counters) s)))
    (pair (if (null? v) "????" (%nm-scale v)) old)))

; %[pn]: the processes there are
(def %nm-procs
  (fn (_ s old)
    (def v (Assoc get (lit total) (Assoc get (lit tasks) s)))
    (pair (if (null? v) "????" (%nm-scale v)) old)))

; %b: bytes read and written by the disks, a partition (a name that is the
; last disk's and a digit) left out
(def %nm-blk
  (fn (_ s old)
    (def go
      (fn (self ds last rd wr)
        (if (null? ds) (list rd wr)
          (let ((n (Assoc get (lit name) (first ds))))
            (if (if (null? last) #f
                  (if (> (byte-len n) (byte-len last))
                    (if (str=? (substring n 0 (byte-len last)) last)
                      (let ((c (byte-at n (byte-len last)))) (if (>= c #\0) (<= c #\9) #f)) #f) #f))
              (self (rest ds) last rd wr)
              (self (rest ds) n (+ rd (%ps-div (%vm-get (lit read-bytes) (first ds)) 512))
                (+ wr (%ps-div (%vm-get (lit write-bytes) (first ds)) 512))))))))
    (def now (go (Assoc get (lit disks) s) () 0 0))
    (def o (if (null? old) (list 0 0) old))
    (pair (string-concat (list (%nm-scale (* 512 (%nm-delta (first now) (first o)))) " "
                               (%nm-scale (* 512 (%nm-delta (first (rest now)) (first (rest o)))))))
          now)))

; When the lines began, (SECONDS . MICROSECONDS), the microseconds taken back
; to a multiple of the interval, as busybox lines %T up with %t
(def %nm-t0 (pair 0 0))

; %t and %T: hh:mm:ss, and PREC digits of the second, rounded; local time,
; or the time since the lines began
(def %nm-clock
  (fn (_ prec since)
    (def scale ((fn (self k acc) (if (= k 0) acc (self (- k 1) (* acc 10)))) (- 6 prec) 1))
    (fn (_ s old)
      (def t (Assoc get (lit time) s))
      (def secs (if since (- (first t) (first %nm-t0)) (first t)))
      (def us (if since (- (rest t) (rest %nm-t0)) (rest t)))
      (def borrow (< us 0))
      (def sec0 (if borrow (- secs 1) secs))
      (def us0 (+ (if borrow (+ us 1000000) us) (%ps-div scale 2)))
      (def carry (>= us0 1000000))
      (def sec1 (if carry (+ sec0 1) sec0))
      (def us1 (if carry (- us0 1000000) us0))
      (def hms (if since (%cu-date-fmt "%H:%M:%S" (%cu-date-split sec1 #t) sec1) (%io-time sec1)))
      (pair (if (= prec 0) hms (string-concat (list hms "." (cu-pad-zero (cu-int->str (%ps-div us1 scale)) prec))))
            old))))

; --- the format ----------------------------------------------------------------

; The fields of FMT, and whether a line ends in a carriage return:
; (FIELDS . CR), or nil where the format is not one nmeter reads.  A field is
; (LABEL READ . STATE).
(def %nm-parse
  (fn (_ fmt)
    (def n (byte-len fmt))
    (def at (fn (_ i) (byte-at fmt i)))
    (def digit? (fn (_ c) (if (>= c #\0) (<= c #\9) #f)))
    ; the text from I up to the next lone %, %% made one: (TEXT . I)
    (def text
      (fn (self i acc)
        (match
          ((>= i n) (pair (bytes->str (reverse acc)) i))
          ((if (= (at i) #\%) (if (< (+ i 1) n) (= (at (+ i 1)) #\%) #f) #f) (self (+ i 2) (pair #\% acc)))
          ((= (at i) #\%) (pair (bytes->str (reverse acc)) i))
          (#t (self (+ i 1) (pair (at i) acc))))))
    (def close (fn (self i) (match ((>= i n) ()) ((= (at i) #\]) i) (#t (self (+ i 1))))))
    (def digits-end (fn (self i) (if (if (< i n) (digit? (at i)) #f) (self (+ i 1)) i)))
    (def go
      (fn (self i label fields cr)
        (def t (text i ()))
        (def lab (string-append label (first t)))
        (def j (rest t))
        (if (>= j n)
          (pair (reverse (if (str=? lab "") fields (pair (pair lab (pair %nm-literal ())) fields))) cr)
          (let ((spec (if (>= (+ j 1) n) ()
                        (if (= (at (+ j 1)) #\[)
                        (let ((e (close (+ j 2))))
                          (if (if (null? e) #t (= e (+ j 2))) ()
                            (list (at (+ j 2)) (substring fmt (+ j 3) e) (+ e 1))))
                        (let ((e (digits-end (+ j 1))))
                          (if (>= e n) () (list (at e) (substring fmt (+ j 1) e) (+ e 1))))))))
            (if (null? spec) ()
              (let ((read (%nm-reader (first spec) (first (rest spec)))))
                (match
                  ((null? read) ())
                  ((eq? read (lit cr)) (self (first (rest (rest spec))) lab fields #t))
                  (#t (self (first (rest (rest spec))) "" (pair (pair lab (pair read ())) fields) cr)))))))))
    (go 0 "" () #f)))

(def %nm-literal (fn (_ s old) (pair "" old)))

; The reader for format letter C with its argument ARG (the digits before the
; letter, or what follows it in brackets), 'cr for %r, nil for a letter
; nmeter does not know
(def %nm-reader
  (fn (_ c arg)
    (match
      ((= c #\n) (if (str=? arg "") () (%nm-if arg)))
      ((= c #\c) (%nm-cpu (let ((k (if (str=? arg "") 10 (%nm-number arg)))) (match ((<= k 0) 1) ((> k 1000) 1000) (#t k)))))
      ((= c #\m) (%nm-mem (if (str=? arg "") "" (substring arg 0 1))))
      ((= c #\s) %nm-swap)
      ((= c #\f) %nm-files)
      ((= c #\i) (%nm-rate (%nm-irq (if (str=? arg "") "" (cu-int->str (%nm-number arg))))))
      ((= c #\x) (%nm-rate (%nm-counter (lit context-switches))))
      ((= c #\p) (if (if (> (byte-len arg) 0) (= (byte-at arg 0) #\n) #f) %nm-procs (%nm-rate (%nm-counter (lit forks)))))
      ((= c #\t) (%nm-clock (%nm-prec arg) #f))
      ((= c #\T) (%nm-clock (%nm-prec arg) #t))
      ((= c #\b) %nm-blk)
      ((= c #\r) (lit cr))
      (#t ()))))

; The leading digits of S as a number, 0 for none, as strtoul reads them
(def %nm-number
  (fn (_ s)
    (def go (fn (self i acc) (if (if (< i (byte-len s)) (if (>= (byte-at s i) #\0) (<= (byte-at s i) #\9) #f) #f) (self (+ i 1) (+ (* acc 10) (- (byte-at s i) #\0))) acc)))
    (go 0 0)))

; %t's digits: the first character of the parameter, 0 to 6
(def %nm-prec
  (fn (_ p)
    (def k (if (str=? p "") -1 (- (byte-at p 0) #\0)))
    (match ((< k 0) 0) ((> k 6) 6) (#t k))))

; One line over sample S: (TEXT . FIELDS), each field's state brought up to S.
; A clock field's state is the first line's time, kept.
(def %nm-line
  (fn (_ fields s)
    (def go
      (fn (self fs acc out)
        (if (null? fs) (pair (string-concat (reverse out)) (reverse acc))
          (let ((f (first fs)))
            (def r ((first (rest f)) s (rest (rest f))))
            (self (rest fs) (pair (pair (first f) (pair (first (rest f)) (rest r))) acc)
              (pair (first r) (pair (first f) out)))))))
    (go fields () ())))

; --- nmeter --------------------------------------------------------------------

(def %cu-nmeter
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "nmeter" argv))
    (def ops (Opts operands o))
    (def d (Opts value o "-d"))
    (def delta (if (null? d) 1000000 (let ((v (%nm-xatoi d))) (if (null? v) () (* v 1000)))))
    (def parsed (if (null? ops) () (%nm-parse (first ops))))
    (match
      ((not (null? (Opts unknown o))) (cu-refuse-option "nmeter" (Opts unknown o)))
      ((null? delta) (do (file-write 2 (string-concat (list "nmeter: invalid number '" d "'\n"))) 1))
      ((null? parsed) (cu-usage "nmeter"))
      (#t (%nm-main (first parsed) (if (rest parsed) "\r" "\n") delta)))))

; xatoi: an optionally signed decimal that fits an int, or nil
(def %nm-xatoi
  (fn (_ s)
    (def neg (if (> (byte-len s) 0) (= (byte-at s 0) #\-) #f))
    (def body (if neg (substring s 1 (byte-len s)) s))
    (def digits? ((fn (self i) (if (>= i (byte-len body)) #t (if (if (>= (byte-at body i) #\0) (<= (byte-at body i) #\9) #f) (self (+ i 1)) #f))) 0))
    (if (if (> (byte-len body) 0) digits? #f)
      (let ((v (%nm-number body)))
        (if (> v (if neg 2147483648 2147483647)) () (if neg (- 0 v) v)))
      ())))

; The lines: a first sample thrown away, then one each DELTA microseconds,
; the sleep lined up on the clock as busybox lines it up; no sleep for a
; negative DELTA
(def %nm-main
  (fn (_ fields end delta)
    (def nz (if (> delta 0) delta 1))
    (def seconds (not (= (% 1000000 nz) 0)))
    (def primed (rest (%nm-line fields (%nm-sample))))
    (def us (fn (_ t) (if seconds (% (+ (* (first t) 1000000) (rest t)) nz) (% (rest t) nz))))
    (if (>= delta 0)
      (let ((t (Sys time-of-day))) (%vm-wait (if (> delta 1000000) 1000000 (- delta (% (rest t) nz))))))
    (def first-sample (%nm-sample))
    (def t0 (Assoc get (lit time) first-sample))
    (set! %nm-t0 (if (> delta 0) (pair (first t0) (- (rest t0) (% (rest t0) delta))) t0))
    (def go
      (fn (self fields s)
        (def r (%nm-line fields s))
        (file-write 1 (string-append (first r) end))
        (if (>= delta 0)
          (let ((rem (- delta (us (Sys time-of-day)))))
            (%vm-wait (if (< rem (%ps-div delta 128)) (+ rem delta) rem))))
        (self (rest r) (%nm-sample))))
    (go primed first-sample)))

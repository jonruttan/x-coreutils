; # x-coreutils -- the small tools, as applets
;
; ## cu/mpstat.x -- mpstat
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's mpstat (procps/mpstat.c, after sysstat 9.1.2): each processor's
; shares of CPU time, interrupts a second in all and by source, since boot or
; over each interval with an average at the end.  It reads Host's cpu, cpus,
; counters and interrupts records.  Darwin keeps no interrupt counts, so its
; interrupt reports show none.
;
; busybox's arithmetic is kept: the shares are a CPU's ticks over the
; interval's, the "all" line's over every CPU's; with more than one CPU the
; interrupt rates are over CPU 0's ticks, times USER_HZ; an interrupt count is
; an unsigned int, its difference taken as one.

; --- a sample ----------------------------------------------------------------

; A CPU record's ticks: user nice system idle iowait irq softirq steal guest
(module cu/mpstat)

(import cu/cli cu-opts cu-refuse-option cu-usage)
(import cu/prims append byte-at byte-len cu-int->str cu-nth file-write filter
  host-counters host-cpu host-cpus host-interrupts length map reverse
  string-append string-concat substring)
(import cu/text cu-member-s? cu-pad-right)

(def %mp-ticks
  (fn (_ r)
    (map (fn (_ k) (vm-ticks (Assoc get k r))) (lit (user nice system idle iowait irq softirq steal guest)))))

; The ticks a CPU has counted: its fields but guest, which user counts already
(def %mp-up (fn (_ v) (- (List fold + 0 v) (cu-nth 8 v))))

; An interrupt table's sources as (NAME COUNT ...), a count for each of CPUS
; (processor numbers) in order.  A source the kernel counts once has it in
; the first processor's column, as busybox reads the line.
(def %mp-table
  (fn (_ records cpus)
    (map (fn (_ r)
           (def counts (Assoc get (lit counts) r))
           (pair (Assoc get (lit name) r)
             (if (null? counts)
               (pair (& (vm-get (lit total) r) 4294967295) (map (fn (_ c) 0) (if (null? cpus) () (rest cpus))))
               (map (fn (_ c) (let ((e (Assoc find c counts))) (if (null? e) 0 (& (rest e) 4294967295)))) cpus))))
      records)))

; The processor numbers an interrupt table names, from its first source with
; a count each
(def %mp-columns
  (fn (self records)
    (match
      ((null? records) ())
      ((null? (Assoc get (lit counts) (first records))) (self (rest records)))
      (#t (map first (Assoc get (lit counts) (first records)))))))

; A name of digits ends in one: busybox counts those sources in a CPU's total
(def %mp-numbered?
  (fn (_ name)
    (if (> (byte-len name) 0)
      (let ((c (byte-at name (- (byte-len name) 1)))) (if (>= c #\0) (<= c #\9) #f))
      #f)))

; A sample: (TIME CPUS GLOBAL-UP PER-CPU-UP IRQS HARD SOFT).  CPUS is the
; ticks of all, then of each processor; IRQS the interrupts in all, then each
; processor's numbered ones; HARD and SOFT the two tables.
(def %mp-sample
  (fn (_ n)
    (def all (%mp-ticks (host-cpu)))
    (def each (map %mp-ticks (host-cpus)))
    (def ints (host-interrupts))
    (def hard-recs (filter (fn (_ r) (not (Assoc get (lit soft?) r))) ints))
    (def soft-recs (filter (fn (_ r) (Assoc get (lit soft?) r)) ints))
    (def cols (%mp-columns hard-recs))
    (def hard (%mp-table hard-recs cols))
    (def per-cpu
      (map (fn (_ i)
             (List fold + 0 (map (fn (_ s) (if (%mp-numbered? (first s)) (%mp-col s cols i) 0)) hard)))
        (%mp-range 0 n)))
    (list (host-now) (pair all each) (%mp-up all)
          (if (> n 1) (if (null? each) 0 (%mp-up (first each))) 0)
          (pair (vm-get (lit interrupts) (host-counters)) per-cpu)
          hard (%mp-table soft-recs (%mp-columns soft-recs)))))

; A source's count on processor number I, 0 when the table has no column for it
(def %mp-col
  (fn (_ s cols i)
    (def go (fn (self cs vs) (match ((null? cs) 0) ((= (first cs) i) (first vs)) (#t (self (rest cs) (rest vs))))))
    (go cols (rest s))))

(def %mp-range (fn (self a b) (if (>= a b) () (pair a (self (+ a 1) b)))))

; A sample of nothing: the since-boot report's last sample
(def %mp-zero
  (fn (_ n)
    (def z (list 0 0 0 0 0 0 0 0 0))
    (list 0 (map (fn (_ i) z) (%mp-range 0 (+ n 1))) 0 0 (map (fn (_ i) 0) (%mp-range 0 (+ n 1))) () ())))

; --- the reports ---------------------------------------------------------------

(def %mp-label (fn (_ s) (cu-pad-right s 11)))
(def %mp-cpu-label (fn (_ s cpu) (string-append (%mp-label s) (if (= cpu 0) "  all" (vm-right (cu-int->str (- cpu 1)) 5)))))
(def %mp-pct (fn (_ d itv) (string-append " " (vm-right (vm-fixed (vm-rate d itv 100) 2) 7))))
(def %mp-gap (fn (_ a b) (let ((d (- b a))) (if (= d 0) 1 d))))

; The shares: user less guest, nice, system, iowait, irq, softirq, steal,
; guest, idle
(def %mp-shares
  (fn (_ p c itv)
    (def at (fn (_ v i) (cu-nth i v)))
    (def d (fn (_ i) (- (at c i) (at p i))))
    (string-append
      (string-concat
        (list (%mp-pct (- (- (at c 0) (at c 8)) (- (at p 0) (at p 8))) itv)
              (%mp-pct (d 1) itv) (%mp-pct (d 2) itv) (%mp-pct (d 4) itv) (%mp-pct (d 5) itv)
              (%mp-pct (d 6) itv) (%mp-pct (d 7) itv) (%mp-pct (d 8) itv) (%mp-pct (d 3) itv)))
      "\n")))

(def %mp-zeros
  (fn (_ idle)
    (string-append (string-concat (map (fn (_ i) (%mp-pct 0 1)) (%mp-range 0 8)))
      (string-append " " (vm-right (vm-fixed (Float from idle) 2) 7) "\n"))))

(def %mp-cpu-report
  (fn (_ p c pl cl bitmap)
    (def global-itv (%mp-gap (cu-nth 2 p) (cu-nth 2 c)))
    (def line
      (fn (_ cpu)
        (def pv (cu-nth cpu (cu-nth 1 p)))
        (def cv (cu-nth cpu (cu-nth 1 c)))
        (string-append (%mp-cpu-label cl cpu)
          (match
            ((= cpu 0) (%mp-shares pv cv global-itv))
            ((= 0 (%mp-up cv)) (%mp-zeros 0))
            ((= 0 (- (%mp-up cv) (%mp-up pv))) (%mp-zeros 100))
            (#t (%mp-shares pv cv (- (%mp-up cv) (%mp-up pv))))))))
    (string-concat
      (pair (string-concat (list "\n" (%mp-label pl) "  CPU    %usr   %nice    %sys %iowait    %irq   %soft  %steal  %guest   %idle\n"))
        (map line (filter (fn (_ i) (cu-nth i bitmap)) (%mp-range 0 (length bitmap))))))))

(def %mp-sum-report
  (fn (_ p c pl cl bitmap itv)
    (def line
      (fn (_ cpu)
        (def per (if (= cpu 0) itv
                   (- (%mp-up (cu-nth cpu (cu-nth 1 c))) (%mp-up (cu-nth cpu (cu-nth 1 p))))))
        (string-append (%mp-cpu-label cl cpu) " "
          (vm-right
            (vm-fixed (if (= per 0) (Float from 0)
                         (vm-rate (- (cu-nth cpu (cu-nth 4 c)) (cu-nth cpu (cu-nth 4 p))) per 100))
              2)
            9)
          "\n")))
    (string-concat
      (pair (string-concat (list "\n" (%mp-label pl) "  CPU    intr/s\n"))
        (map line (filter (fn (_ i) (cu-nth i bitmap)) (%mp-range 0 (length bitmap))))))))

; A table's rates, a column a source and a line a processor.  A source whose
; name moved since the last sample is looked for one place up and one down;
; one not found is N/A.
(def %mp-irq-report
  (fn (_ ptab ctab pl cl bitmap only n itv interval)
    (def name-at (fn (_ tab j) (if (< j (length tab)) (first (cu-nth j tab)) "")))
    (def total (+ (length ctab) 3))
    (def match-at
      (fn (_ j name)
        (match
          ((if (= interval 0) #t (str=? name (name-at ptab j))) j)
          ((if (> j 0) (str=? name (name-at ptab (- j 1))) #f) (- j 1))
          ((if (< (+ j 1) total) (str=? name (name-at ptab (+ j 1))) #f) (+ j 1))
          (#t ()))))
    (def header
      (fn (self js printed expected acc)
        (if (null? js) (string-concat (reverse acc))
          (let ((w (- 7 (- printed expected))))
            (def s (string-concat (list " " (vm-right (first (cu-nth (first js) ctab)) (if (> w 0) w 0)) "/s")))
            (self (rest js) (+ printed (byte-len s)) (+ expected 10) (pair s acc))))))
    (def count (fn (_ tab j cpu) (if (< j (length tab)) (cu-nth (+ cpu 1) (cu-nth j tab)) 0)))
    (def js (%mp-range 0 (length ctab)))
    (def line
      (fn (_ cpu)
        (string-append (%mp-cpu-label cl (+ cpu 1))
          (string-append
            (string-concat
              (map (fn (_ j)
                     (def k (match-at j (first (cu-nth j ctab))))
                     (if (null? k) "        N/A"
                       (vm-right
                         (vm-fixed (vm-rate (& (- (count ctab j cpu) (count ptab k cpu)) 4294967295) itv 100) 2)
                         10)))
                js))
            "\n"))))
    (string-concat
      (pair (string-concat (list "\n" (%mp-label pl) "  CPU" (header js 0 0 ()) "\n"))
        (map line (filter (fn (_ i) (if only (cu-nth (+ i 1) bitmap) #t)) (%mp-range 0 n)))))))

; One report of sample C against P, labelled with PL and CL
(def %mp-report
  (fn (_ p c pl cl shows bitmap only n interval)
    (def itv (if (> n 1) (%mp-gap (cu-nth 3 p) (cu-nth 3 c)) (%mp-gap (cu-nth 2 p) (cu-nth 2 c))))
    (string-concat
      (list (if (cu-member-s? "cpu" shows) (%mp-cpu-report p c pl cl bitmap) "")
            (if (cu-member-s? "sum" shows) (%mp-sum-report p c pl cl bitmap itv) "")
            (if (cu-member-s? "irq" shows) (%mp-irq-report (cu-nth 5 p) (cu-nth 5 c) pl cl bitmap only n itv interval) "")
            (if (cu-member-s? "soft" shows) (%mp-irq-report (cu-nth 6 p) (cu-nth 6 c) pl cl bitmap only n itv interval) "")))))

; --- mpstat ------------------------------------------------------------------

(def cu-mpstat
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "mpstat" argv))
    (def ops (Opts operands o))
    (def unknown (if (null? (Opts unknown o)) (vm-dash-number ops) (Opts unknown o)))
    (def n (length (host-cpus)))
    (def i-arg (Opts value o "-I"))
    (def ints (if (null? i-arg) ()
                (match ((str=? i-arg "CPU") (list "irq")) ((str=? i-arg "SUM") (list "sum"))
                       ((str=? i-arg "SCPU") (list "soft")) ((str=? i-arg "ALL") (list "irq" "sum" "soft"))
                       (#t (lit bad)))))
    (def all (Opts on? o "-A"))
    (def p-arg (Opts value o "-P"))
    (def shows (append (if all (list "cpu" "sum" "irq" "soft") ())
                 (if (eq? ints (lit bad)) () ints)
                 (if (if (Opts on? o "-u") #t (if all #f (null? (if (eq? ints (lit bad)) () ints)))) (list "cpu") ())))
    ; in busybox's order: the options, the interval, a count after an interval
    ; of 0 refused before it is read, the count, -I, then -P
    (if (not (null? unknown)) (cu-refuse-option "mpstat" unknown)
      (let ((interval (if (null? ops) 0 (cu-range-number "mpstat" (first ops) 0 2147483647))))
        (def counted (if (null? ops) #f (not (null? (rest ops)))))
        (match
          ((null? interval) 1)
          ((if counted (= interval 0) #f) (cu-usage "mpstat"))
          (#t (let ((count (if counted (cu-range-number "mpstat" (first (rest ops)) 0 2147483647) -1)))
                (match
                  ((null? count) 1)
                  ((eq? ints (lit bad)) (cu-usage "mpstat"))
                  (#t (let ((bitmap (%mp-bitmap n all p-arg)))
                        (if (null? bitmap) 1
                          (%mp-main shows bitmap (if all #t (not (null? p-arg))) n interval count))))))))))))

; Which of all and each processor to show, a flag apiece: all alone without
; -A or -P; with -P, the processors it names, ALL for every one; nil once a
; bad one is said
(def %mp-bitmap
  (fn (_ n all p-arg)
    (def none (map (fn (_ i) #f) (%mp-range 0 (+ n 1))))
    (def every (map (fn (_ i) #t) (%mp-range 0 (+ n 1))))
    (def set (fn (_ bits k) (map (fn (_ i) (if (= i k) #t (cu-nth i bits))) (%mp-range 0 (+ n 1)))))
    (def go
      (fn (self ws bits)
        (match
          ((null? ws) bits)
          ((str=? (first ws) "ALL") (self (rest ws) every))
          (#t (let ((k (cu-range-number "mpstat" (first ws) 0 2147483647)))
                (match
                  ((null? k) ())
                  ((>= k n) (do (file-write 2 "mpstat: not that many processors\n") ()))
                  (#t (self (rest ws) (set bits (+ k 1))))))))))
    (match
      (all (if (null? p-arg) every (go (%mp-commas p-arg) every)))
      ((null? p-arg) (set none 0))
      (#t (go (%mp-commas p-arg) none)))))

; S's comma-separated words, empty ones gone, as strtok_r gives them
(def %mp-commas
  (fn (_ s)
    (def go
      (fn (self i start acc)
        (match
          ((>= i (byte-len s)) (reverse (if (> i start) (pair (substring s start i) acc) acc)))
          ((= (byte-at s i) #\,) (self (+ i 1) (+ i 1) (if (> i start) (pair (substring s start i) acc) acc)))
          (#t (self (+ i 1) start acc)))))
    (go 0 0 ())))

(def %mp-main
  (fn (_ shows bitmap only n interval count)
    (def first-sample (%mp-sample n))
    (file-write 1 (io-uname-line (first first-sample) n #f))
    (def clock (fn (_ s) (io-time (first s))))
    (if (= interval 0)
      (do (file-write 1 (%mp-report (%mp-zero n) first-sample (clock first-sample) (clock first-sample) shows bitmap only n 0)) 0)
      (let ((go (fn (self prev count)
                  (host-wait (* interval 1000000))
                  (def c (%mp-sample n))
                  (file-write 1 (%mp-report prev c (clock prev) (clock c) shows bitmap only n interval))
                  (def left (if (> count 0) (- count 1) count))
                  (if (if (> count 0) (= left 0) #f) c (self c left)))))
        (def last (go first-sample count))
        (file-write 1 (%mp-report first-sample last "Average:" "Average:" shows bitmap only n interval))
        0))))

(provide cu/mpstat cu-mpstat)

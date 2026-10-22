; # x-coreutils -- the small tools, as applets
;
; ## cu/vmstat.x -- vmstat, and what the counter applets share
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's vmstat (procps/vmstat.c): one line a sample of the run queue,
; memory, swap and block traffic, interrupts, context switches and the CPU's
; shares, the counts as rates over the interval.  It reads Host's counters,
; memory and cpu records through cu/prims.x; a field Darwin does not report
; shows as 0.
;
; Also here, for iostat, mpstat and nmeter: busybox's compact numbers
; (smart_ulltoa4 and smart_ulltoa5), printf's %.Nf of a double, the CPU time
; in USER_HZ ticks, and the wait between samples, which a spec replaces to
; step a fixture /proc from one sample to the next.

(def %vm-tick 10000000)                 ; nanoseconds in a USER_HZ tick

; Host's nanoseconds as USER_HZ ticks, the unit of /proc's times and of
; Darwin's CLK_TCK both; 0 for a time the kernel does not report
(def %vm-ticks (fn (_ ns) (if (null? ns) 0 (%ps-div ns %vm-tick))))

; A record's field, 0 when the kernel does not report it
(def %vm-get (fn (_ k r) (let ((v (Assoc get k r))) (if (null? v) 0 v))))

; The wait between two samples, in microseconds
(def %vm-wait (fn (_ us) (sys-usleep us)))

; Now, in unix seconds, for the times a report shows
(def %vm-now (fn (_) (date-now-unix)))

; The time since boot in hundredths of a second, as /proc/uptime gives it:
; the wall clock less Host's boot time
(def %vm-uptime
  (fn (_)
    (def t (Sys time-of-day))
    (+ (* 100 (- (first t) (host-boot-time))) (%ps-div (rest t) 10000))))

; --- busybox's compact numbers ------------------------------------------------

(def %vm-digit (fn (_ k) (substring "0123456789" k (+ k 1))))

; A leading digit, or a space for a leading zero while ZERO? is still true
(def %vm-lead (fn (_ k zero?) (if (if (= k 0) zero? #f) " " (%vm-digit k))))

; N scaled by 1024 until it is under LIMIT, with N times ten scaled along:
; (TENS . IDX), IDX the scale letter's place in SCALE
(def %vm-scale-down
  (fn (_ n limit)
    (def up (fn (self v idx) (if (>= v limit) (self (%ps-div v 1024) (+ idx 1)) (pair v idx))))
    (up (%ps-div (* n 10) 1024) 1)))

; smart_ulltoa5: N in five characters, "12345" up to 99999, then scaled by
; 1024 as "92.1M" or " 123M" with SCALE's letter for the step
(def %vm-five
  (fn (_ n scale)
    (if (<= n 99999)
      (let ((u (%ps-div n 10)))
        (def a (%vm-lead (%ps-div u 1000) #t))
        (def b (%vm-lead (% (%ps-div u 100) 10) (str=? a " ")))
        (def c (%vm-lead (% (%ps-div u 10) 10) (str=? b " ")))
        (string-concat (list a b c (%vm-lead (% u 10) (str=? c " ")) (%vm-digit (% n 10)))))
      (let ((r (%vm-scale-down n 100000)))
        (def u (%ps-div (first r) 10))
        (def unit (substring scale (rest r) (+ (rest r) 1)))
        (if (>= u 100)
          (let ((a (%vm-lead (%ps-div u 1000) #t)))
            (def b (%vm-lead (% (%ps-div u 100) 10) (str=? a " ")))
            (string-concat (list a b (%vm-lead (% (%ps-div u 10) 10) (str=? b " ")) (%vm-digit (% u 10)) unit)))
          (let ((a (%vm-lead (%ps-div u 10) #t)))
            (string-concat (list a (%vm-lead (% u 10) (str=? a " ")) "." (%vm-digit (% (first r) 10)) unit))))))))

; smart_ulltoa4: N in four characters, "1234" up to 9999, then "9.2M" or
; " 27M" with SCALE's letter
(def %vm-four
  (fn (_ n scale)
    (if (<= n 9999)
      (let ((u (%ps-div n 10)))
        (def a (%vm-lead (%ps-div u 100) #t))
        (def b (%vm-lead (% (%ps-div u 10) 10) (str=? a " ")))
        (string-concat (list a b (%vm-lead (% u 10) (str=? b " ")) (%vm-digit (% n 10)))))
      (let ((r (%vm-scale-down n 10000)))
        (def u (%ps-div (first r) 10))
        (def unit (substring scale (rest r) (+ (rest r) 1)))
        (if (>= u 10)
          (let ((a (%vm-lead (%ps-div u 100) #t)))
            (string-concat (list a (%vm-lead (% (%ps-div u 10) 10) (str=? a " ")) (%vm-digit (% u 10)) unit)))
          (string-concat (list (%vm-digit u) "." (%vm-digit (% (first r) 10)) unit)))))))

; S with its leading spaces gone, as skip_whitespace leaves it
(def %vm-trim-left
  (fn (_ s)
    (def go (fn (self i) (if (if (< i (byte-len s)) (= (byte-at s i) #\space) #f) (self (+ i 1)) i)))
    (substring s (go 0) (byte-len s))))

; --- printf's %.Nf --------------------------------------------------------------

; A double as printf's %.PREC f writes it: the exact value of its bits rounded
; to PREC places, a tie to even, as the C library rounds.  X is a Float.  PREC
; is at most 6, so the scaled mantissa fits a machine integer.
(def %vm-fixed
  (fn (_ x prec)
    (def bits (first x))
    (def ex (& (>> bits 52) 2047))
    (def frac (& bits (- (<< 1 52) 1)))
    (def m (if (= ex 0) frac (| frac (<< 1 52))))
    (def e (if (= ex 0) -1074 (- ex 1075)))
    (def scale ((fn (self k acc) (if (= k 0) acc (self (- k 1) (* acc 10)))) prec 1))
    ; the value times 10^PREC, rounded to an integer
    (def q
      (match
        ((>= e 0) (* (* m scale) (<< 1 e)))
        ((> (- 0 e) 62) 0)
        (#t (let ((p (<< 1 (- 0 e))) (num (* m scale)))
              (def whole (%ps-div num p))
              (def twice (* 2 (- num (* whole p))))
              (match
                ((> twice p) (+ whole 1))
                ((< twice p) whole)
                (#t (+ whole (% whole 2))))))))
    (def int-part (cu-int->str (%ps-div q scale)))
    (string-append (if (< bits 0) "-" "")
      (if (= prec 0) int-part
        (string-concat (list int-part "." (cu-pad-zero (cu-int->str (% q scale)) prec)))))))

; A divided by B times K, as C computes (double)A / B * K
(def %vm-rate (fn (_ a b k) (Float * (Float / (Float from a) (Float from b)) (Float from k))))

; S right-aligned in W columns, as printf's %*s puts it
(def %vm-right (fn (_ s w) (cu-pad-left s w)))

; --- vmstat -------------------------------------------------------------------

; A sample: the columns' raw values in their order.  r b swpd free buff cache
; si so bi bo in cs, then us sy id wa st gu in ticks.  Memory is in
; kilobytes, paged-in and paged-out too, as /proc/vmstat counts them.
(def %vm-sample
  (fn (_)
    (def c (host-counters))
    (def m (host-memory))
    (def t (host-cpu))
    (def kb (fn (_ k) (%ps-div (%vm-get k m) 1024)))
    (def tk (fn (_ k) (%vm-ticks (Assoc get k t))))
    (def guest (+ (tk (lit guest)) (tk (lit guest-nice))))
    (list (%vm-get (lit running) c) (%vm-get (lit blocked) c)
          (- (kb (lit swap-total)) (kb (lit swap-free))) (kb (lit free)) (kb (lit buffers))
          (+ (kb (lit cached)) (kb (lit reclaimable)))
          (%vm-get (lit swap-ins) c) (%vm-get (lit swap-outs) c)
          (%ps-div (%vm-get (lit paged-in) c) 1024) (%ps-div (%vm-get (lit paged-out) c) 1024)
          (%vm-get (lit interrupts) c) (%vm-get (lit context-switches) c)
          (- (+ (tk (lit user)) (tk (lit nice))) guest)
          (+ (+ (tk (lit system)) (tk (lit irq))) (tk (lit softirq)))
          (tk (lit idle)) (tk (lit iowait)) (tk (lit steal)) guest)))

; Each column: (WIDTH . HOW), HOW nil for a value shown as it is, 'rate for a
; count differentiated, 'share for a CPU time differentiated and shown as a
; percentage of the six, 'self for the run queue, which counts vmstat
(def %vm-columns
  (list (pair 2 (lit self)) (pair 2 ()) (pair 6 ()) (pair 6 ()) (pair 6 ()) (pair 6 ())
        (pair 4 (lit rate)) (pair 4 (lit rate)) (pair 5 (lit rate)) (pair 5 (lit rate))
        (pair 4 (lit rate)) (pair 4 (lit rate))
        (pair 2 (lit share)) (pair 2 (lit share)) (pair 2 (lit share)) (pair 2 (lit share))
        (pair 2 (lit share)) (pair 2 (lit share))))

(def %vm-header
  "procs -----------memory---------- ---swap-- -----io---- -system-- -------cpu-------\n r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st gu\n")

; A count's change, truncated to 32 bits as busybox keeps it, and 0 where it
; went backwards
(def %vm-delta
  (fn (_ now before)
    (def v (& (- now before) 4294967295))
    (if (>= v 2147483648) 0 v)))

; The CPU shares: (SUM . VSHIFT) over the deltas D of the share columns, the
; sum halved and the shift grown while a delta is 2^25 or more after it
(def %vm-share-sum
  (fn (_ ds)
    (def go
      (fn (self ds sum shift)
        (match
          ((null? ds) (pair sum shift))
          ((>= (>> (first ds) shift) 33554432) (self ds (>> sum 1) (+ shift 1)))
          (#t (self (rest ds) (+ sum (>> (first ds) shift)) shift)))))
    (go ds 0 0)))

; One row of DATA against PREV over INTERVAL seconds (0 for none), with
; busybox's overrun rule: a field that runs wide narrows the next
(def %vm-row
  (fn (_ data prev interval)
    (def deltas
      (map (fn (_ c) (if (null? (rest (first c))) (first (rest c))
                       (if (eq? (rest (first c)) (lit self)) (first (rest c))
                         (%vm-delta (first (rest c)) (rest (rest c))))))
        (%vm-zip3 %vm-columns data prev)))
    (def shares (map rest (filter (fn (_ p) (eq? (rest (first p)) (lit share))) (%vm-zip %vm-columns deltas))))
    (def ss (%vm-share-sum shares))
    (def value
      (fn (_ col v)
        (match
          ((= v 0) 0)
          ((eq? (rest col) (lit share))
            (if (= (first ss) 0) v
              (let ((p (%ps-div (* 100 (>> v (rest ss))) (first ss)))) (if (>= p 100) 99 p))))
          ((eq? (rest col) (lit self)) (- v 1))
          (#t v))))
    (def field
      (fn (_ col v overrun)
        (def width (if (>= (- (first col) overrun) 0) (- (first col) overrun) 0))
        (if (eq? (rest col) (lit rate))
          (let ((r (if (= interval 0) v (%ps-div v interval))))
            (%vm-right (%vm-trim-left (if (= (first col) 4) (%vm-four r " kmgtpezy") (%vm-five r " kmgtpezy"))) width))
          (%vm-right (cu-int->str v) width))))
    (def go
      (fn (self cols vs overrun acc)
        (if (null? cols) (string-concat (reverse (pair "\n" acc)))
          (let ((s (field (first cols) (value (first cols) (first vs)) overrun)))
            (self (rest cols) (rest vs) (+ overrun (- (byte-len s) (first (first cols))))
              (pair s (if (null? acc) acc (pair " " acc))))))))
    (go %vm-columns deltas 0 ())))

; The first of OPS that is a dash and more, or nil: Opts reads -2 as a number,
; where getopt, and so busybox, reads it as the option 2
(def %vm-dash-number
  (fn (self ops)
    (match
      ((null? ops) ())
      ((if (> (byte-len (first ops)) 1) (= (byte-at (first ops) 0) #\-) #f) (first ops))
      (#t (self (rest ops))))))

(def %vm-zip
  (fn (self a b) (if (if (null? a) #t (null? b)) () (pair (pair (first a) (first b)) (self (rest a) (rest b))))))
(def %vm-zip3
  (fn (self a b c)
    (if (null? a) () (pair (pair (first a) (pair (first b) (first c))) (self (rest a) (rest b) (rest c))))))

(def %cu-vmstat
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "vmstat" argv))
    (def ops (Opts operands o))
    (def unknown (if (null? (Opts unknown o)) (%vm-dash-number ops) (Opts unknown o)))
    ; the options are refused before an operand is read, as getopt runs first
    (if (not (null? unknown)) (cu-refuse-option "vmstat" unknown)
      (let ((interval (if (null? ops) 0 (%cu-range-number "vmstat" (first ops) 0 2147483647))))
        (def count
          (match
            ((null? interval) ())
            ((null? ops) 1)
            ((null? (rest ops)) 0)
            (#t (let ((n (%cu-range-number "vmstat" (first (rest ops)) 0 2147483647)))
                  (if (null? n) () (if (= n 0) 1 n))))))
        (if (null? count) 1
          (%vm-main interval count (if (Opts on? o "-n") 0 (- (rest (Term window 1)) 3))))))))

; The samples: the first against one taken just before it, each later one
; against the last, the header again every HEIGHT rows (never, for 0 or less)
(def %vm-main
  (fn (_ interval count height)
    (def go
      (fn (self prev row count)
        (if (= row 0) (file-write 1 %vm-header))
        (def left (if (<= (if (= row 0) height row) 0) -1 (- (if (= row 0) height row) 1)))
        (def data (%vm-sample))
        (file-write 1 (%vm-row data prev interval))
        (def more (if (< count 0) count (- count 1)))
        (if (= more 0) 0
          (do (%vm-wait (* interval 1000000))
              (self data left (if (< more 0) -1 more))))))
    (go (%vm-sample) 0 (if (= count 0) -1 count))))

; # x-coreutils -- the small tools, as applets
;
; ## cu/top.x -- top
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's top (procps/top.c), as busybox's own configuration builds it: CPU
; percentages with one decimal, a line per CPU on the 1 key, the CPU each
; process last ran on, the memory view (-m, the s key) and threads (-H, the h
; key).  What it shows comes from x/sys/host through cu/prims.x: the process
; table, its threads and mappings, the CPU times, the memory record, the load
; averages and the run queue.  Darwin keeps no run queue, last pid or last
; CPU: its load line has the three averages alone and its CPU column is
; empty.
;
; The percentages are busybox's integer arithmetic over clock ticks, its
; unsigned 32- and 16-bit truncations included, so the columns round as its
; do.  Host times are nanoseconds; a tick is USER_HZ's hundredth of a second,
; the unit of /proc's times and of Darwin's CLK_TCK both.
;
; Interactive, the keys are busybox's: N M P T sort by pid, memory, CPU and
; time; S the memory view, R reverse, H threads, 1 or C a line per CPU, the
; arrows, Home, End and the page keys scroll, Q, ^C and ^D quit.  With -b, or
; once standard input ends, it reads no keys and waits the delay between
; screens.

(def %top-tick 10000000)                ; nanoseconds in a USER_HZ tick
(def %top-line-max 446)                 ; busybox's LINE_BUF_SIZE less 2
(def %top-esc (bytes->str (list 27)))

; --- the run's state, set by %cu-top ------------------------------------------

(def %top-batch #f)
(def %top-eof #f)                       ; no keys: -b, or standard input ended
(def %top-lines 0)                      ; screen rows
(def %top-width 0)                      ; screen columns, at most %top-line-max
(def %top-mem-view #f)                  ; the -m screen
(def %top-threads #f)                   ; -H: a row a thread
(def %top-smp #f)                       ; a CPU line a processor
(def %top-sorts ())                     ; three comparators, busybox's sort_function
(def %top-inverted #f)
(def %top-sort-field 0)                 ; the memory view's sort column
(def %top-scroll 0)
(def %top-hist ())                      ; (pid . ticks) of the last scan, by pid
(def %top-jif ())                       ; the aggregate ticks, this scan and the last
(def %top-jif-prev ())
(def %top-cpu-jif ())                   ; a processor's ticks, this scan and the last
(def %top-cpu-prev ())
(def %top-total-pcpu 0)
(def %top-rows ())                      ; the scan, sorted
(def %top-names ())                     ; (uid . name), the names seen this run

(def %top-u32 (fn (_ n) (& n 4294967295)))
(def %top-u16 (fn (_ n) (& n 65535)))
(def %top-ticks (fn (_ ns) (if (null? ns) 0 (%ps-div ns %top-tick))))

; --- %cu-top ------------------------------------------------------------------

(def %cu-top
  (fn (_ argv stdin-thunk)
    ; busybox's make_all_argv_opts: an argument without its dash gets one, so
    ; `top bn1` is `top -bn1`
    (def o (%cu-opts "top" (map (fn (_ a) (if (if (> (byte-len a) 0) (= (byte-at a 0) #\-) #f) a (string-append "-" a))) argv)))
    (def value (fn (_ f) (let ((v (Opts value o f))) (if (null? v) () (if (if (> (byte-len v) 0) (= (byte-at v 0) #\-) #f) (substring v 1 (byte-len v)) v)))))
    (def unknown (Opts unknown o))
    (def d (value "-d"))
    (def n (value "-n"))
    (def interval (if (null? d) 5000 (%top-duration-ms d)))
    ; -d is read before -n, as busybox reads them: a bad -d is the one named
    (match
      ((not (null? unknown)) (%cu-refuse-option "top" unknown))
      ((null? interval) (do (file-write 2 (string-concat (list "top: invalid number '" d "'\n"))) 1))
      (#t (let ((iterations (if (null? n) 0 (%cu-range-number "top" n 0 2147483647))))
            (if (null? iterations) 1
              (%top-main (Opts on? o "-b") (Opts on? o "-m") (Opts on? o "-H") interval iterations)))))))

; parse_duration_str with busybox's FLOAT_DURATION: seconds, a fraction
; allowed, and an s, m, h or d after them; nil when it is not one
(def %top-duration-ms
  (fn (_ s)
    (def end (byte-len s))
    (def last (if (> end 0) (byte-at s (- end 1)) 0))
    (def scale (match ((= last #\s) 1000) ((= last #\m) 60000) ((= last #\h) 3600000) ((= last #\d) 86400000) (#t ())))
    (def digits (if (null? scale) s (substring s 0 (- end 1))))
    (def dot (%top-index digits #\.))
    (def whole (if (null? dot) digits (substring digits 0 dot)))
    (def frac (if (null? dot) "" (substring digits (+ dot 1) (byte-len digits))))
    (def ms-frac (substring (string-append frac "000") 0 3))
    (if (if (%top-digits? whole) (if (%top-digits? frac) (> (+ (byte-len whole) (byte-len frac)) 0) #f) #f)
      (%ps-div (* (+ (* (%top-number whole) 1000) (%top-number ms-frac)) (if (null? scale) 1000 scale)) 1000)
      ())))

(def %top-index
  (fn (_ s c)
    (def go (fn (self i) (match ((>= i (byte-len s)) ()) ((= (byte-at s i) c) i) (#t (self (+ i 1))))))
    (go 0)))
(def %top-digits?
  (fn (_ s)
    (def go (fn (self i) (if (>= i (byte-len s)) #t (if (if (>= (byte-at s i) #\0) (<= (byte-at s i) #\9) #f) (self (+ i 1)) #f))))
    (go 0)))
(def %top-number
  (fn (_ s)
    (def go (fn (self i acc) (if (>= i (byte-len s)) acc (self (+ i 1) (+ (* acc 10) (- (byte-at s i) #\0))))))
    (go 0 0)))

(def %top-main
  (fn (_ batch mem threads interval iterations)
    (set! %top-batch batch)
    (set! %top-eof batch)
    (set! %top-mem-view mem)
    (set! %top-threads threads)
    (set! %top-smp #f)
    (set! %top-sorts (list %top-pcpu-sort %top-mem-sort %top-time-sort))
    (set! %top-inverted #f)
    (set! %top-sort-field 0)
    (set! %top-scroll 0)
    (set! %top-hist ())
    (set! %top-jif (%top-zero-jif))
    (set! %top-jif-prev (%top-zero-jif))
    (set! %top-cpu-jif ())
    (set! %top-cpu-prev ())
    (set! %top-names ())
    ; raw keys, ^C a byte like any other; nil when stdin is no terminal
    (def saved (if batch () (Term raw! 0)))
    (def r (%top-cycle iterations interval))
    (if batch () (file-write 1 "\n"))
    (if (null? saved) () (Term restore! 0 saved))
    r))

; --- the loop -----------------------------------------------------------------

; One scan and its screens: the size, the processes, the first scan's stats
; and a tenth of a second's wait before the second, as busybox takes them;
; then the screens and the keys.  Answers the exit status.
(def %top-cycle
  (fn (self iterations interval)
    ; the last screen's garbage goes before the next scan
    (%cu-heap-collect)
    (set! %top-floor (%top-live))
    (%top-size!)
    (match
      ((if %top-batch #f (if (< %top-lines 5) #t (< %top-width 10)))
        (do (%top-wait interval) (self iterations interval)))
      (#t
        (let ((rows (if %top-mem-view (%top-mem-scan) (%top-scan))))
          (match
            ((null? rows) (do (file-write 2 "top: no process info in /proc\n") 0))
            (%top-mem-view
              (do (set! %top-rows (%cu-msort rows %top-mem-less)) (%top-screens self iterations interval interval)))
            ((null? %top-hist)
              (do (%top-stats! rows) (sys-usleep 100000) (self iterations interval)))
            (#t
              (do (set! %top-rows (%cu-msort (%top-stats! rows) %top-less))
                  (%top-screens self iterations interval interval)))))))))

; A screen of the scan, then the keys: a redraw shows the same scan again,
; waiting a second for the next key; anything else scans afresh.
(def %top-screens
  (fn (self rescan iterations interval wait)
    (file-write 1 (if %top-mem-view (%top-mem-screen) (%top-screen)))
    ; busybox's `if (iterations >= 0 && !--iterations) break`: 0 runs for ever
    (def left (if (>= iterations 0) (- iterations 1) iterations))
    (if (= left 0) 0
      (let ((next (%top-keys wait)))
        (match
          ((eq? next (lit exit)) 0)
          ((eq? next (lit redraw)) (self rescan left interval 1000))
          (#t (rescan left interval)))))))

(def %top-wait (fn (_ ms) (sys-usleep (* ms 1000))))

; the screen's size: busybox's batch screen is as long as the scan and its
; lines LINE_BUF_SIZE wide; a terminal's is its own, 80x24 when it says none
(def %top-size!
  (fn (_)
    (if %top-batch
      (do (set! %top-lines 2147483647) (set! %top-width %top-line-max))
      (let ((w (Term window 1)))
        (set! %top-width (if (> (first w) %top-line-max) %top-line-max (first w)))
        (set! %top-lines (rest w))))))

; --- the scan -----------------------------------------------------------------

; A row: (pid ppid rss-kb ticks uid state comm cpu pcpu).
(def %top-row
  (fn (_ p)
    (def get (fn (_ k) (Assoc get k p)))
    (def rss (get (lit rss)))
    (list (get (lit pid)) (if (null? (get (lit ppid))) 0 (get (lit ppid)))
          (if (null? rss) 0 (%ps-div rss 1024))
          (+ (%top-ticks (get (lit utime))) (%top-ticks (get (lit stime))))
          (get (lit uid)) (%cu-pad-right (%ps-stat p) 3) (get (lit comm))
          (get (lit processor)) 0)))

(def %top-scan
  (fn (_)
    (def procs (%ps-sorted (host-processes)))
    (%top-swept-map %top-row
      (if %top-threads
        (%top-flatten (%top-swept-map (fn (_ p) (let ((ts (host-threads (Assoc get (lit pid) p)))) (if (null? ts) (list p) ts))) procs))
        procs))))

(def %top-flatten
  (fn (_ ls)
    (def go (fn (self ls acc) (if (null? ls) (reverse acc) (self (rest ls) (%top-onto (first ls) acc)))))
    (go ls ())))
(def %top-onto (fn (self l acc) (if (null? l) acc (self (rest l) (pair (first l) acc)))))

; busybox's do_stats: this scan's ticks against the last's, process by process
; -- both by pid, so one walk pairs them -- and the CPU times read again.
; Fewer ticks than last time is a process whose times the kernel no longer
; gives -- Darwin answers none for a zombie -- and counts as none used, where
; busybox's unsigned difference would wrap to a share of millions of percent.
(def %top-stats!
  (fn (_ rows)
    (def by-pid (%cu-msort rows (fn (_ a b) (< (first a) (first b)))))
    (def used (fn (_ now was) (if (< now was) 0 (- now was))))
    (def walk
      (fn (self rs hist acc total)
        (match
          ((null? rs) (pair (reverse acc) total))
          ((if (null? hist) #t (< (first (first rs)) (first (first hist))))
            (self (rest rs) hist (pair (first rs) acc) total))
          ((> (first (first rs)) (first (first hist))) (self rs (rest hist) acc total))
          (#t (let ((d (used (%cu-nth 3 (first rs)) (rest (first hist)))))
                (self (rest rs) (rest hist) (pair (%top-with-pcpu (first rs) d) acc) (%top-u32 (+ total d))))))))
    (%top-read-jif!)
    (def r (walk by-pid %top-hist () 0))
    (set! %top-hist (map (fn (_ e) (pair (first e) (%cu-nth 3 e))) by-pid))
    (set! %top-total-pcpu (rest r))
    (first r)))

(def %top-with-pcpu
  (fn (_ e d)
    (def go (fn (self e i) (if (= i 8) (list d) (pair (first e) (self (rest e) (+ i 1))))))
    (go e 0)))

; --- CPU ticks ----------------------------------------------------------------

; (usr nic sys idle iowait irq softirq steal total busy), busybox's jiffy_counts
(def %top-zero-jif (fn (_) (list 0 0 0 0 0 0 0 0 0 0)))
(def %top-jif-of
  (fn (_ c)
    (def v (map (fn (_ k) (%top-ticks (Assoc get k c)))
                (list (lit user) (lit nice) (lit system) (lit idle)
                      (lit iowait) (lit irq) (lit softirq) (lit steal))))
    (def total (+ (first v) (+ (%cu-nth 1 v) (+ (%cu-nth 2 v) (+ (%cu-nth 3 v) (+ (%cu-nth 4 v) (+ (%cu-nth 5 v) (+ (%cu-nth 6 v) (%cu-nth 7 v)))))))))
    (append v (list total (- total (+ (%cu-nth 3 v) (%cu-nth 4 v)))))))

; busybox's get_jiffy_counts: the aggregate always, a line a processor when
; they are shown, the first reading of those against zeros after 50 ms
(def %top-read-jif!
  (fn (_)
    (set! %top-jif-prev %top-jif)
    (set! %top-jif (%top-jif-of (host-cpu)))
    (if (not %top-smp) ()
      (if (null? %top-cpu-jif)
        (do (set! %top-cpu-jif (map %top-jif-of (host-cpus)))
            (set! %top-cpu-prev (map (fn (_ c) (%top-zero-jif)) %top-cpu-jif))
            (sys-usleep 50000))
        (do (set! %top-cpu-prev %top-cpu-jif)
            (set! %top-cpu-jif (map %top-jif-of (host-cpus))))))))

; --- sorting ------------------------------------------------------------------

; busybox's comparators: negative when P comes first
(def %top-pid-sort (fn (_ p q) (- (first q) (first p))))
(def %top-mem-sort
  (fn (_ p q) (let ((a (%cu-nth 2 p)) (b (%cu-nth 2 q))) (if (< b a) -1 (if (= a b) 0 1)))))
(def %top-pcpu-sort (fn (_ p q) (- (%cu-nth 8 q) (%cu-nth 8 p))))
(def %top-time-sort
  (fn (_ p q) (let ((a (%cu-nth 3 p)) (b (%cu-nth 3 q))) (if (< b a) -1 (if (= a b) 0 1)))))

; mult_lvl_cmp: the first comparator that tells them apart, R turning it over
(def %top-less
  (fn (_ p q)
    (def go (fn (self fs) (if (null? fs) 0 (let ((v ((first fs) p q))) (if (= v 0) (self (rest fs)) v)))))
    (def v (go %top-sorts))
    (< (if %top-inverted (- 0 v) v) 0)))

; --- numbers as busybox prints them -------------------------------------------

; smart_ulltoa5: N in five characters, "12345" up to 99999, then "92.1m" or
; " 123m" in steps of 1024 through " mgtpezy"
(def %top-five
  (fn (_ n)
    (def digit (fn (_ k) (substring "0123456789" k (+ k 1))))
    (def lead (fn (_ k z) (if (if (= k 0) z #f) " " (digit k))))
    (def up (fn (self v idx) (if (>= v 100000) (self (%ps-div v 1024) (+ idx 1)) (pair v idx))))
    (if (<= n 99999)
      (let ((u (%ps-div n 10)) (v (% n 10)))
        (def a (lead (%ps-div u 1000) #t))
        (def b (lead (% (%ps-div u 100) 10) (str=? a " ")))
        (def c (lead (% (%ps-div u 10) 10) (str=? b " ")))
        (def d (lead (% u 10) (str=? c " ")))
        (string-concat (list a b c d (digit v))))
      (let ((r (up (%ps-div (* n 10) 1024) 1)))
        (def u (%ps-div (first r) 10))
        (def unit (substring " mgtpezy" (rest r) (+ (rest r) 1)))
        (if (>= u 100)
          (let ((a (lead (%ps-div u 1000) #t)))
            (def b (lead (% (%ps-div u 100) 10) (str=? a " ")))
            (string-concat (list a b (lead (% (%ps-div u 10) 10) (str=? b " ")) (digit (% u 10)) unit)))
          (let ((a (lead (%ps-div u 10) #t)))
            (string-concat (list a (lead (% u 10) (str=? a " ")) "." (digit (% (first r) 10)) unit))))))))

; fmt_100percent_8: VALUE of TOTAL as " NN.N% ", seven characters
(def %top-percent
  (fn (_ value total)
    (if (>= value total) "  100% "
      (let ((v (%ps-div (%top-u32 (* 1000 value)) total)))
        (def t (%ps-div v 100))
        (def r (% v 100))
        (string-concat (list " " (if (= t 0) " " (%cu-int->str t)) (%cu-int->str (%ps-div r 10))
                             "." (%cu-int->str (% r 10)) "% "))))))

; "%3u.%c": tenths, the last digit after the point
(def %top-tenths
  (fn (_ v plus)
    (if plus (string-append (%cu-pad-left "99" 3) ".+")
      (string-concat (list (%cu-pad-left (%cu-int->str (%ps-div v 10)) 3) "." (%cu-int->str (% v 10)))))))

; --- the screen ---------------------------------------------------------------

; The lines, each cut to the width less one, as busybox's print_line_buf
; prints them: the first homes the cursor, a bold one is in reverse video,
; each clears to the end of its line, and the last clears the rest of the
; screen -- in batch mode, the lines and a newline alone.
(def %top-frame
  (fn (_ lines)
    (def cut (fn (_ s) (if (> (byte-len s) (- %top-width 1)) (substring s 0 (- %top-width 1)) s)))
    (def clr (if %top-batch "" (string-append %top-esc "[K")))
    (def one
      (fn (_ l first?)
        (def text (cut (rest l)))
        (match
          (first? (if %top-batch text (string-concat (list %top-esc "[H" text clr))))
          ((if (first l) (not %top-batch) #f) (string-concat (list "\n" %top-esc "[7m" text %top-esc "[m" clr)))
          (#t (string-concat (list "\n" text clr))))))
    (def go (fn (self ls first? acc) (if (null? ls) (reverse acc) (self (rest ls) #f (pair (one (first ls) first?) acc)))))
    (string-concat (append (go lines #t ()) (list (if %top-batch "\n" (string-append %top-esc "[J\r")))))))

; the memory line and its total, busybox's /proc/meminfo figures in kilobytes
(def %top-mem
  (fn (_)
    (def m (host-memory))
    (def kb (fn (_ k) (let ((v (Assoc get k m))) (if (null? v) 0 (%ps-div v 1024)))))
    (pair (string-concat
            (list "Mem: " (%cu-int->str (- (kb (lit total)) (kb (lit free)))) "K used, "
                  (%cu-int->str (kb (lit free))) "K free, "
                  (%cu-int->str (kb (lit shared))) "K shrd, "
                  (%cu-int->str (kb (lit buffers))) "K buff, "
                  (%cu-int->str (kb (lit cached))) "K cached"))
          (kb (lit total)))))

; the CPU lines: one, or one a processor, each field's share of the ticks
(def %top-cpu-lines
  (fn (_ room)
    (def line
      (fn (_ name cur prev)
        (def d (fn (_ i) (%top-u32 (- (%cu-nth i cur) (%cu-nth i prev)))))
        (def total (let ((t (d 8))) (if (= t 0) 1 t)))
        (def p (fn (_ i) (%top-percent (d i) total)))
        (string-concat (list "CPU" name ":" (p 0) "usr" (p 2) "sys" (p 1) "nic" (p 3) "idle"
                             (p 4) "io" (p 5) "irq" (p 6) "sirq"))))
    (if (if %top-smp (not (null? %top-cpu-jif)) #f)
      (let ((n (if (> (length %top-cpu-jif) room) room (length %top-cpu-jif))))
        (def go (fn (self i cs ps acc)
                  (if (>= i n) (reverse acc)
                    (self (+ i 1) (rest cs) (rest ps) (pair (line (%cu-int->str i) (first cs) (first ps)) acc)))))
        (go 0 %top-cpu-jif %top-cpu-prev ()))
      (list (line "" %top-jif %top-jif-prev)))))

; the load line: /proc/loadavg as the kernel writes it, each average with the
; kernel's rounding (FIXED_1/200 added) and two decimals, then the run queue
; and the last pid where the kernel keeps them
(def %top-load (fn (_) (%top-load-line (host-load-fixed) (host-tasks))))

; the same from the fixed-point LOADS and the tasks record T
(def %top-load-line
  (fn (_ loads t)
    (def avg
      (fn (_ a)
        (def b (+ a 10))
        (string-concat (list (%cu-int->str (>> b 11)) "."
                             (%cu-pad-zero (%cu-int->str (>> (* (& b 2047) 100) 11)) 2)))))
    (def get (fn (_ k) (Assoc get k t)))
    (string-concat
      (list "Load average: " (%cu-join-with (map avg loads) " ")
            (if (null? (get (lit running))) ""
              (string-concat (list " " (%cu-int->str (get (lit running))) "/" (%cu-int->str (get (lit total)))
                                   " " (%cu-int->str (get (lit last-pid))))))))))

(def %top-user
  (fn (_ uid)
    (def hit (Assoc get uid %top-names))
    (if (not (null? hit)) hit
      (let ((n (if (null? uid) "?" (let ((s (sys-user-name uid))) (if (null? s) (%cu-int->str uid) s)))))
        (set! %top-names (pair (pair uid n) %top-names))
        n))))

; "%5u %5u %-8.8s", then squeezed to twenty characters as busybox squeezes a
; wide pid: spaces before the pid go, then those between it and the ppid,
; then the user is cut
(def %top-ppu
  (fn (_ pid ppid user)
    (def u (if (> (byte-len user) 8) (substring user 0 8) user))
    (def s (string-concat (list (%cu-pad-left (%cu-int->str pid) 5) " "
                                (%cu-pad-left (%cu-int->str ppid) 5) " " (%cu-pad-right u 8))))
    (def lead (fn (self s) (if (if (> (byte-len s) 20) (= (byte-at s 0) #\space) #f) (self (substring s 1 (byte-len s))) s)))
    (def t (lead s))
    (if (<= (byte-len t) 20) t
      (let ((sp (%top-index t #\space)))
        (def gap (fn (self i) (if (if (> (- (byte-len t) (- i (+ sp 1))) 20) (= (byte-at t i) #\space) #f) (self (+ i 1)) i)))
        (def j (gap (+ sp 1)))
        (def u2 (string-append (substring t 0 (+ sp 1)) (substring t j (byte-len t))))
        (substring u2 0 20)))))

(def %top-screen
  (fn (_)
    (def room (fn (_ used) (- %top-lines used)))
    (def mem (%top-mem))
    (def total-kb (rest mem))
    (def cpus (%top-cpu-lines (room 1)))
    (def head (append (list (pair #f (first mem))) (map (fn (_ l) (pair #f l)) cpus)
                      (list (pair #f (%top-load))
                            (pair #t "  PID  PPID USER     STAT   RSS %RSS CPU %CPU COMMAND"))))
    (def left (let ((n (room (length head))) (more (- (length %top-rows) %top-scroll)))
                (if (> n more) more n)))
    (def scale (%top-scales total-kb))
    (def rows (%top-take (%top-drop %top-rows %top-scroll) left))
    (%top-frame (append head (%top-swept-map (fn (_ e) (pair #f (%top-row-line e scale))) rows)))))

(def %top-drop (fn (self l n) (if (if (> n 0) (not (null? l)) #f) (self (rest l) (- n 1)) l)))
(def %top-take
  (fn (_ l n)
    (def go (fn (self l n acc) (if (if (> n 0) (not (null? l)) #f) (self (rest l) (- n 1) (pair (first l) acc)) (reverse acc))))
    (go l n ())))

; busybox's multiply-and-shift for %RSS and %CPU, as (mem-scale mem-shift
; mem-half cpu-scale cpu-shift cpu-half), in its unsigned 32-bit arithmetic
(def %top-scales
  (fn (_ total-kb)
    (%top-scales-of total-kb
      (%top-u32 (- (%cu-nth 9 %top-jif) (%cu-nth 9 %top-jif-prev)))
      (%top-u32 (- (%cu-nth 8 %top-jif) (%cu-nth 8 %top-jif-prev)))
      %top-total-pcpu)))

; the same from MemTotal in kilobytes, the BUSY and TOTAL ticks since the last
; scan and the ticks the processes used, TOTAL-PCPU
(def %top-scales-of
  (fn (_ total-kb busy total total-pcpu)
    (def down (fn (self s sh limit) (if (>= s limit) (self (%ps-div s 4) (- sh 2) limit) (pair s sh))))
    (def up (fn (self s sh) (if (< s 1073741824) (self (%top-u32 (* s 4)) (+ sh 2)) (pair s sh))))
    (def m (down (%ps-div 2097152000 (if (= total-kb 0) 1 total-kb)) 21 512))
    (def pcpu-total (if (< total-pcpu busy) busy total-pcpu))
    (def c0 (let ((s (%top-u32 (* 64000 (%top-u16 busy))))) (up (if (= s 0) 1 s) 6)))
    (def tmp (%top-u32 (* (%top-u16 total) pcpu-total)))
    (def c (down (if (= tmp 0) (first c0) (%ps-div (first c0) tmp)) (rest c0) 1024))
    (list (first m) (rest m) (%ps-div (<< 1 (rest m)) 20)
          (first c) (rest c) (%ps-div (<< 1 (rest c)) 20))))

; a row's %RSS and %CPU in tenths, from its kilobytes, its ticks and the scales
(def %top-shares
  (fn (_ kb pcpu s)
    (pair (>> (+ (* kb (first s)) (%cu-nth 2 s)) (%cu-nth 1 s))
          (>> (%top-u32 (+ (%top-u32 (* pcpu (%cu-nth 3 s))) (%cu-nth 5 s))) (%cu-nth 4 s)))))

(def %top-row-line
  (fn (_ e s)
    (def shares (%top-shares (%cu-nth 2 e) (%cu-nth 8 e) s))
    (def pmem (first shares))
    (def pcpu (rest shares))
    (def cpu (%cu-nth 7 e))
    (def col (string-concat
               (list (%top-ppu (first e) (%cu-nth 1 e) (%top-user (%cu-nth 4 e))) " "
                     (%cu-nth 5 e) "  " (%top-five (%cu-nth 2 e))
                     (%top-tenths pmem (> (%ps-div pmem 10) 99))
                     " " (if (null? cpu) "   " (%cu-pad-left (%cu-int->str cpu) 3))
                     (%top-tenths pcpu #f) " ")))
    (string-append col (%ps-args (host-args (first e)) (%cu-nth 6 e)))))

; --- the memory view ----------------------------------------------------------

; A row: (pid comm vsz vszrw rss rss-shared dirty dirty-shared stack), in
; kilobytes from the platform's mapping sums; a process with no mappings,
; a kernel thread, is not one
(def %top-mem-scan
  (fn (_)
    ; the walk needs a process's pid and name alone: the table's records go
    ; before it starts, so the live set the sweeps measure from is small
    (def ids (map (fn (_ p) (pair (Assoc get (lit pid) p) (Assoc get (lit comm) p))) (%ps-sorted (host-processes))))
    (%cu-heap-collect)
    (set! %top-floor (%top-live))
    (def row
      (fn (_ id)
        (def pid (first id))
        (def m (host-maps pid))
        (def kb (fn (_ k) (%ps-div (Assoc get k m) 1024)))
        (if (null? m) ()
          (let ((ro (kb (lit mapped-ro))) (rw (kb (lit mapped-rw)))
                (sc (kb (lit shared-clean))) (sd (kb (lit shared-dirty)))
                (pc (kb (lit private-clean))) (pd (kb (lit private-dirty))))
            (if (= (+ ro rw) 0) ()
              (list pid (rest id) (+ rw ro) rw (+ pc (+ pd (+ sc sd))) (+ sc sd)
                    (+ pd sd) sd (kb (lit stack))))))))
    (filter (fn (_ r) (not (null? r))) (%top-swept-map row ids))))

; topmem_sort: the chosen column, larger first, dirty breaking a tie
(def %top-mem-less
  (fn (_ a b)
    (def at (fn (_ e) (%cu-nth (+ 2 %top-sort-field) e)))
    (def l (if (= (at a) (at b)) (%cu-nth 6 a) (at a)))
    (def r (if (= (at a) (at b)) (%cu-nth 6 b) (at b)))
    (def n (if (> l r) -1 (if (= l r) 0 1)))
    (< (if %top-inverted (- 0 n) n) 0)))

(def %top-mem-screen
  (fn (_)
    (def m (host-memory))
    (def kb (fn (_ k) (let ((v (Assoc get k m))) (if (null? v) 0 (%ps-div v 1024)))))
    (def n (fn (_ k) (%cu-int->str (kb k))))
    ; the column header with the sort column marked ^ (_ reversed)
    (def mark (if %top-inverted #\_ #\^))
    (def head (%top-bytes "  PID   VSZ VSZRW   RSS (SHR) DIRTY (SHR) STACK COMMAND"))
    (def from (+ 5 (* %top-sort-field 6)))
    (def marked
      (fn (self bs i)
        (match
          ((null? bs) ())
          ((= i (+ from 6)) (pair mark (self (rest bs) (+ i 1))))
          ((= i from) (pair mark (self (rest bs) (+ i 1))))
          ((if (> i from) (if (< i (+ from 6)) (= (first bs) #\space) #f) #f)
            (if (%top-run-on? head from i) (pair mark (self (rest bs) (+ i 1))) (pair (first bs) (self (rest bs) (+ i 1)))))
          (#t (pair (first bs) (self (rest bs) (+ i 1)))))))
    (def lines
      (append
        (list (pair #f (string-concat (list "Mem total:" (n (lit total)) " anon:" (n (lit anon)) " map:" (n (lit mapped)) " free:" (n (lit free)))))
              (pair #f (string-concat (list " slab:" (n (lit slab)) " buf:" (n (lit buffers)) " cache:" (n (lit cached))
                                            " dirty:" (n (lit dirty)) " write:" (n (lit writeback)))))
              (pair #f (string-concat (list "Swap total:" (n (lit swap-total)) " free:" (n (lit swap-free)))))
              (pair #t (bytes->str (marked head 0))))))
    (def left (let ((room (- %top-lines (length lines))) (more (- (length %top-rows) %top-scroll)))
                (if (> room more) more room)))
    (%top-frame (append lines (%top-swept-map (fn (_ e) (pair #f (%top-mem-line e)))
                                   (%top-take (%top-drop %top-rows %top-scroll) left))))))

; busybox marks the sort column from its start through the spaces after it
(def %top-run-on?
  (fn (_ bs from i)
    (def go (fn (self j) (if (>= j i) #t (if (= (%cu-nth j bs) #\space) (self (+ j 1)) #f))))
    (go (+ from 1))))

(def %top-mem-line
  (fn (_ e)
    (def pid (%cu-int->str (first e)))
    (def five (fn (_ k) (string-append (%top-five (%cu-nth k e)) " ")))
    (def four (fn (_ k) (string-append (%ps-four (%cu-nth k e) " mgtpezy") " ")))
    (def p (string-append (%cu-pad-left pid 5) " "))
    (def lead
      (match
        ((> (byte-len p) 7) (string-concat (list p (four 2) (four 3))))
        ((= (byte-len p) 7) (string-concat (list p (four 2) (five 3))))
        (#t (string-concat (list p (five 2) (five 3))))))
    (string-concat (list lead (five 4) (five 5) (five 6) (five 7) (five 8)
                         (%ps-args (host-args (first e)) (%cu-nth 1 e))))))

; --- the keys -----------------------------------------------------------------

; busybox's handle_input: keys until the delay passes with none, each acted on
; at once.  Answers 'exit, 'redraw (the same scan shown again), or 'scan.
(def %top-keys
  (fn (_ wait)
    (if %top-eof (do (%top-wait wait) (lit scan))
      (%top-key-loop wait))))

(def %top-key-loop
  (fn (self wait)
    (def k (%top-read-key wait))
    (def page (%ps-div %top-lines 2))
    (def scrolled
      (fn (_ ofs)
        (def n (length %top-rows))
        (set! %top-scroll (if (>= ofs n) (- n 1) ofs))
        (if (< %top-scroll 0) (set! %top-scroll 0) ())
        (lit redraw)))
    (match
      ((eq? k (lit timeout)) (lit scan))
      ((eq? k (lit eof)) (do (set! %top-eof #t) (lit scan)))
      ((= k 3) (lit exit))                ; ^C, VINTR
      ((= k 4) (lit exit))                ; ^D, VEOF
      ((= k %vi-key-up) (scrolled (- %top-scroll 1)))
      ((= k %vi-key-down) (scrolled (+ %top-scroll 1)))
      ((= k %vi-key-home) (scrolled 0))
      ((= k %vi-key-end) (scrolled (- (length %top-rows) page)))
      ((= k %vi-key-page-up) (scrolled (- %top-scroll page)))
      ((= k %vi-key-page-down) (scrolled (+ %top-scroll page)))
      ((< k 0) (self 0))
      (#t (%top-letter self k (| k 32))))))

(def %top-letter
  (fn (_ again cc c)
    (def sorts (fn (_ fs) (do (set! %top-mem-view #f) (set! %top-sorts fs) (again 0))))
    (match
      ((= c #\q) (lit exit))
      ((= c #\n) (sorts (pair %top-pid-sort (rest %top-sorts))))
      ((= c #\m) (sorts (list %top-mem-sort %top-pcpu-sort %top-time-sort)))
      ((= c #\p) (sorts (list %top-pcpu-sort %top-mem-sort %top-time-sort)))
      ((= c #\t) (sorts (list %top-time-sort %top-mem-sort %top-pcpu-sort)))
      ((if (= c #\h) (not %top-mem-view) #f)
        (do (set! %top-threads (not %top-threads)) (set! %top-hist ()) (again 0)))
      ((= c #\s)
        ; S steps back: two back, then the one forward s takes
        (do (if (= cc #\S) (set! %top-sort-field (% (+ %top-sort-field 5) 7)) ())
            (set! %top-sort-field (% (+ %top-sort-field 1) 7))
            (if %top-mem-view (lit redraw)
              (do (set! %top-mem-view #t) (set! %top-hist ()) (again 0)))))
      ((= c #\r) (do (set! %top-inverted (not %top-inverted)) (lit redraw)))
      ((if (= c #\c) #t (= c #\1))
        (do (set! %top-smp (not %top-smp)) (set! %top-cpu-jif ()) (%top-read-jif!) (again 0)))
      (#t (again 0)))))

; busybox's read_key: a byte, a code for an escape sequence (the table vi
; reads, cu/vi.x), 'timeout when none comes in WAIT ms, 'eof at the end
(def %top-read-key
  (fn (_ wait)
    (if (null? (sys-poll (list (pair 0 (list (lit in)))) wait)) (lit timeout)
      (let ((b (%top-byte)))
        (match
          ((null? b) (lit eof))
          ((= b #\escape) (%top-escape ""))
          (#t b))))))

(def %top-byte
  (fn (_) (let ((s (file-read-fd 0 1))) (if (= (byte-len s) 0) () (byte-at s 0)))))

; the bytes after an Escape, each waited for 50 ms, until a sequence is known;
; a lone Escape, or one no sequence starts with, is a key top ignores
(def %top-escape
  (fn (self buf)
    (def hit (filter (fn (_ e) (str=? (first e) buf)) %vi-sequences))
    (def prefix? (fn (_ e) (if (> (byte-len (first e)) (byte-len buf)) (str=? (substring (first e) 0 (byte-len buf)) buf) #f)))
    (match
      ((not (null? hit)) (rest (first hit)))
      ((null? (filter prefix? %vi-sequences)) -1)
      ((null? (sys-poll (list (pair 0 (list (lit in)))) 50)) -1)
      (#t (let ((b (%top-byte))) (if (null? b) -1 (self (string-append buf (bytes->str (list b))))))))))

(def %top-bytes
  (fn (_ s)
    (def go (fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (byte-at s i) acc)))))
    (go (- (byte-len s) 1) ())))

; map, sweeping once the heap has doubled since the last sweep: a process
; record, a row laid out with its arguments read, or one big process's
; mappings can cost from thousands of objects to millions, so a sweep every
; so many items is too often for the small and too rare for the large.  The
; live count is the engine's, read without a walk, as vi reads it.
(def %top-floor 0)
(def %top-live (fn (_) (%cell-int (first (%reflect-base-cell (lit alloc-count))))))
(def %top-sweep-if-due!
  (fn (_)
    (if (< (* 2 %top-floor) (%top-live))
      (do (%cu-heap-collect) (set! %top-floor (%top-live)))
      ())))

(def %top-swept-map
  (fn (_ f l)
    (def go
      (fn (self l acc)
        (if (null? l) (reverse acc)
          (let ((v (f (first l))))
            (%top-sweep-if-due!)
            (self (rest l) (pair v acc))))))
    (go l ())))

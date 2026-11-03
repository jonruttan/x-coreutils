; # x-coreutils -- the small tools, as applets
;
; ## cu/powertop.x -- powertop: the wakeups the kernel counts, and their causes
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's powertop (procps/powertop.c) with FEATURE_POWERTOP_INTERACTIVE
; and its PROCIRQ.  It reads what busybox reads, under the /proc root Host
; names: stat for the processors, interrupts for each source's count,
; acpi/processor/*/power for the C-states and timer_stats for the timers,
; each in the pieces fgets hands busybox, a line or 127 bytes of one.  Every
; ten seconds, or at once at a key, it clears the screen and shows the
; C-states' residency, the wakeups since the last screen and what caused
; them, the most first; q, the terminal's interrupt key or the end of input
; ends it, a fatal signal with status 1.  timer_stats left the kernel in
; 4.11, so a kernel since has no stats to show.  The C-states busybox asks
; CPUID for on i386 are not asked for.  Darwin has no /proc, so there it
; answers as busybox does: it cannot open /proc/stat.

(module cu/powertop)

(import cu/inetd in-call)
(import cu/prims byte-at byte-len cu-err-label cu-heap-collect cu-int->str
  cu-libc-sym cu-nth cu-nthrest cu-ptr-call cu-ptr-ref cu-ptr-set!
  cu-stdin-to-command! cu-str->ptr file-close file-list-dir file-open-read
  file-open-write file-read-fd file-read-to-end file-write length
  libc-strerror map ps-div set-first! str-make-raw string-append substring
  sys-getenv sys-geteuid sys-isatty sys-poll sys-signal sys-signals vec-ref
  vec-set!)
(import cu/text cu-pad-left)
(import cu/vmstat vm-fixed)

(def %ptop-esc (bytes->str (list 27)))
(def %ptop-sleep 10)
(def %ptop-freq-1000 3579545)

; --- the run's state ------------------------------------------------------------

(def %ptop-cpus 0)
(def %ptop-maxcstate 0)
(def %ptop-cant #f)           ; cant_enable_timer_stats
(def %ptop-lines ())          ; ((TEXT . COUNT) ...), the newest first
(def %ptop-cumulative 0)
(def %ptop-irq-slots ())      ; IRQCOUNT cells: (ACTIVE NUMBER COUNT)
(def %ptop-irq0 0)
(def %ptop-irq-total 0)
(def %ptop-last ())           ; the C-states' (USAGE . DURATION) last read
(def %ptop-saved ())          ; the terminal's settings before raw, or nil
(def %ptop-vintr 0)
(def %ptop-sigs ())
(def %ptop-buffered #f)       ; stdout no terminal: written at fflush only
(def %ptop-pending ())        ; what stdio holds for stdout, the newest first

(def %ptop-reset!
  (fn (_)
    (do (set! %ptop-maxcstate 0)
        (set! %ptop-cant #f)
        (set! %ptop-lines ())
        (set! %ptop-cumulative 0)
        (set! %ptop-irq-slots (map (fn (_ i) (list #f 0 0)) (List range 0 40)))
        (set! %ptop-irq0 0)
        (set! %ptop-irq-total 0)
        (set! %ptop-saved ())
        (set! %ptop-vintr 0)
        (set! %ptop-sigs ())
        (set! %ptop-buffered (not (sys-isatty 1)))
        (set! %ptop-pending ()))))

; --- stdout as stdio holds it ---------------------------------------------------

; a terminal's stdout is line-buffered, every piece here ending a line; any
; other is written at fflush, so stderr's words come before the screen's.
; musl starts stdout line-buffered and learns it is no terminal at its
; first write, so the first line is written as it ends
(def %ptop-out
  (fn (_ s) (if %ptop-buffered (set! %ptop-pending (pair s %ptop-pending)) (file-write 1 s))))

(def %ptop-flush!
  (fn (_)
    (do (file-write 1 (%str-concat (List reverse %ptop-pending)))
        (set! %ptop-pending ()))))

(def %ptop-die
  (fn (_ msg)
    (do (file-write 2 (%str-concat (list "powertop: " msg "\n")))
        (Err raise (lit powertop) msg ()))))

; --- C's numbers ----------------------------------------------------------------

(def %ptop-u32 (fn (_ n) (& n 4294967295)))
(def %ptop-i32
  (fn (_ n) (let ((u (& n 4294967295))) (if (>= u 2147483648) (- u 4294967296) u))))

; an unsigned 64-bit N as a double, N read as the machine word it is
(def %ptop-u64->float
  (fn (_ n)
    (if (>= n 0) (Float from n)
      (Float + (Float from (& n 9223372036854775807)) (Float + (Float from 9223372036854775807) (Float from 1))))))

; unsigned 64-bit A divided by B, B above 0 and below 2^62; 0 for B 0, as
; arm64 divides
(def %ptop-udiv
  (fn (_ a b)
    (match
      ((= b 0) 0)
      ((>= a 0) (ps-div a b))
      (#t (let ((q (<< (ps-div (& (>> a 1) 9223372036854775807) b) 1)))
            (if (>= (- a (* q b)) b) (+ q 1) q))))))

(def %ptop-u64->str
  (fn (_ n)
    (if (>= n 0) (cu-int->str n)
      (let ((q (ps-div (& (>> n 1) 9223372036854775807) 5)))
        (string-append (cu-int->str q) (cu-int->str (- n (* q 10))))))))

; --- C's strings ----------------------------------------------------------------

; the byte at I, a C string's NUL past its end
(def %ptop-at (fn (_ s i) (if (< i (byte-len s)) (byte-at s i) 0)))
(def %ptop-space? (fn (_ c) (if (= c 32) #t (if (>= c 9) (<= c 13) #f))))
(def %ptop-alnum?
  (fn (_ c)
    (match ((Char numeric? c) #t)
           ((if (>= c 65) (<= c 90) #f) #t)
           (#t (if (>= c 97) (<= c 122) #f)))))

(def %ptop-skip (fn (self s i) (if (%ptop-space? (%ptop-at s i)) (self s (+ i 1)) i)))

; where SUB is first found in S from I, or nil
(def %ptop-find
  (fn (_ s sub i)
    (let ((k (Str8 index-of sub (substring s i (byte-len s))))) (if (null? k) () (+ k i)))))

(def %ptop-chomp
  (fn (_ s)
    (def n (byte-len s))
    (if (if (> n 0) (= (byte-at s (- n 1)) 10) #f) (substring s 0 (- n 1)) s)))

; the run of decimal digits at I: (VALUE END OVER), OVER when it passes 2^64
(def %ptop-digits
  (fn (self s i v over)
    (def c (%ptop-at s i))
    (if (not (Char numeric? c)) (list v i over)
      (self s (+ i 1) (+ (* v 10) (- c 48))
        (match (over #t)
               ((< v 0) #t)
               ((> v 1844674407370955161) #t)
               (#t (if (= v 1844674407370955161) (> c 53) #f)))))))

; bb_strtoull at I: (VALUE . END), every refusal the largest value, -1 here
(def %ptop-strtoull
  (fn (_ s i)
    (if (not (%ptop-alnum? (%ptop-at s i))) (pair -1 i)
      (let ((r (%ptop-digits s i 0 #f)))
        (def end (cu-nth 1 r))
        (if (if (cu-nth 2 r) #t (%ptop-alnum? (%ptop-at s end))) (pair -1 end) (pair (first r) end))))))

; bb_strtou on the whole of S, its refusals UINT_MAX
(def %ptop-strtou
  (fn (_ s)
    (let ((r (%ptop-strtoull s 0)))
      (if (if (< (first r) 0) #t (> (first r) 4294967295)) 4294967295 (first r)))))

; strtoul as musl reads a number, blanks and a sign first: the value as an
; int, or nil where it sets errno -- no digits, or past 2^64
(def %ptop-strtoul
  (fn (_ s)
    (def i (%ptop-skip s 0))
    (def c (%ptop-at s i))
    (def j (if (if (= c 43) #t (= c 45)) (+ i 1) i))
    (def r (%ptop-digits s j 0 #f))
    (match ((= (cu-nth 1 r) j) ())
           ((cu-nth 2 r) ())
           (#t (%ptop-i32 (if (= c 45) (- 0 (first r)) (first r)))))))

; the pieces fgets reads into a SIZE-byte buffer: a line, or SIZE-1 bytes of it
(def %ptop-pieces
  (fn (_ text size)
    (def n (byte-len text))
    (def end
      (fn (self i limit)
        (match ((>= i n) n)
               ((>= i limit) limit)
               ((= (byte-at text i) 10) (+ i 1))
               (#t (self (+ i 1) limit)))))
    (def go
      (fn (self i acc)
        (if (>= i n) (List reverse acc)
          (let ((e (end i (+ i (- size 1))))) (self e (pair (substring text i e) acc))))))
    (go 0 ())))

; --- the files ------------------------------------------------------------------

(def %ptop-path (fn (_ name) (%str-concat (list (Host proc-root) "/" name))))

; PATH's text, or the errno its open answered
(def %ptop-slurp
  (fn (_ path)
    (def fd (file-open-read path))
    (if (< fd 0) (Err errno-of fd)
      (let ((t (file-read-to-end fd path)))
        (do (file-close fd) (if (Err err? t) "" t))))))

; xfopen_for_read: NAME's text, or busybox's death
(def %ptop-must-read
  (fn (_ name)
    (def path (%ptop-path name))
    (def r (%ptop-slurp path))
    (if (number? r) (%ptop-die (%str-concat (list "can't open '" path "': " (libc-strerror r)))) r)))

; write_str_to_file: #t when the file would not open
(def %ptop-timer!
  (fn (_ s)
    (def fd (file-open-write (%ptop-path "timer_stats")))
    (if (< fd 0) #t (do (file-write fd s) (file-close fd) #f))))

; get_cpu_count: one past the highest N of /proc/stat's cpuN lines
(def %ptop-cpu-count
  (fn (_)
    (def go
      (fn (self ls nr)
        (match
          ((null? ls) (+ nr 1))
          ((not (Str8 starts? "cpu" (first ls))) (if (>= nr 0) (+ nr 1) (self (rest ls) nr)))
          ((= (%ptop-at (first ls) 3) 32) (self (rest ls) nr))
          (#t (let ((n (%ptop-strtoul (substring (first ls) 3 (byte-len (first ls))))))
                (self (rest ls) (if (if (null? n) #f (> n nr)) n nr)))))))
    (%ptop-u32 (go (%ptop-pieces (%ptop-must-read "stat") 256) -1))))

; --- the lines shown ------------------------------------------------------------

(def %ptop-save-line!
  (fn (_ text count)
    (if (null? (List find (fn (_ l) (str=? (first l) text)) %ptop-lines))
      (set! %ptop-lines (pair (pair text count) %ptop-lines))
      (set! %ptop-lines
        (map (fn (_ l) (if (str=? (first l) text) (pair text (%ptop-i32 (+ (rest l) count))) l))
             %ptop-lines)))))

; --- interrupts -----------------------------------------------------------------

; save_irq_count: NR's new COUNT kept in its slot, or the first free one;
; answers the change since the last, or COUNT when NR has no slot yet
(def %ptop-save-irq
  (fn (_ nr count)
    (def go
      (fn (self ss free)
        (def s (if (null? ss) () (first ss)))
        (match
          ((null? ss)
            (do (if (null? free) ()
                  (do (set-first! free #t) (set-first! (rest free) nr) (set-first! (cu-nthrest 2 free) count)))
                (%ptop-i32 count)))
          ((if (first s) (= (cu-nth 1 s) nr) #f)
            (let ((old (cu-nth 2 s)))
              (do (set-first! (cu-nthrest 2 s) count) (%ptop-i32 (- count old)))))
          (#t (self (rest ss) (if (if (null? free) (not (first s)) #f) s free))))))
    (go %ptop-irq-slots ())))

(def %ptop-ipis (list "NMI" "RES" "CAL" "TLB" "TRM" "THR" "SPU"))

; the number a label before the colon gives: an IPI's place past 20000, or
; the label as strtoul reads it; nil for one it refuses
(def %ptop-irq-nr
  (fn (_ label)
    (def go (fn (self ns k) (match ((null? ns) ()) ((str=? (first ns) label) k) (#t (self (rest ns) (+ k 1))))))
    (def ipi (go %ptop-ipis 0))
    (if (null? ipi) (%ptop-strtoul label) (+ ipi 20000))))

; the counts from I summed: (SUM . END), END past the blanks after the last
(def %ptop-counts
  (fn (self s i sum)
    (def j (%ptop-skip s i))
    (if (not (Char numeric? (%ptop-at s j))) (pair sum j)
      (let ((r (%ptop-strtoull s j))) (self s (rest r) (+ sum (first r)))))))

(def %ptop-hpet?
  (fn (_ name)
    (let ((k (Str8 index-of "hpet" name)))
      (if (null? k) #f (Char numeric? (%ptop-at name (+ k 4)))))))

; a source's piece: its count saved, its line and the totals added to
(def %ptop-irq-piece!
  (fn (_ s)
    (def colon (Str8 index-of ":" s))
    (def nr (if (null? colon) () (%ptop-irq-nr (substring s 0 colon))))
    (if (null? nr) ()
      (let ((c (%ptop-counts s (+ colon 1) 0)))
        ; a numbered source's name follows the word after the counts
        (def sp (if (>= nr 20000) (rest c) (%ptop-find s " " (rest c))))
        (if (null? sp) ()
          (%ptop-irq-source! nr (first c)
            (%ptop-chomp (substring s (%ptop-skip s sp) (byte-len s)))))))))

(def %ptop-irq-source!
  (fn (_ nr count name)
    (def delta (%ptop-save-irq nr count))
    (if (%ptop-hpet? name) ()
      (do (if (if (= nr 0) #f (not (= delta 0)))
            (%ptop-save-line! (string-append (if (>= nr 20000) "   <kernel IPI> : " "    <interrupt> : ") name) delta)
            ())
          (if (= nr 0) (set! %ptop-irq0 delta)
            (set! %ptop-irq-total (%ptop-i32 (+ %ptop-irq-total delta))))))))

; process_irq_counts
(def %ptop-irq-counts!
  (fn (_)
    (do (set! %ptop-irq0 0)
        (set! %ptop-irq-total 0)
        (map %ptop-irq-piece! (%ptop-pieces (%ptop-must-read "interrupts") 128))
        ())))

; --- C-states -------------------------------------------------------------------

(def %ptop-zeros (fn (_) (list 0 0 0 0 0 0 0 0)))
(def %ptop-add (fn (_ l i v) (map (fn (_ k) (if (= k i) (+ (cu-nth k l) v) (cu-nth k l))) (List range 0 8))))

; one piece of a power file over the state (LEVEL USAGE DURATION DONE)
(def %ptop-power-piece
  (fn (_ st s)
    (def level (first st))
    (def a (Str8 index-of "age[" s))
    (def u (if (null? a) () (%ptop-add (cu-nth 1 st) level (+ (first (%ptop-strtoull s (+ a 4))) 1))))
    (def b (if (null? a) () (Str8 index-of "ation[" s)))
    (match
      ((null? a) st)
      ((null? b) (list level u (cu-nth 2 st) #f))
      (#t (let ((d (%ptop-add (cu-nth 2 st) level (first (%ptop-strtoull s (+ b 6))))))
            (if (>= level 7) (list level u d #t)
              (do (if (> (+ level 1) %ptop-maxcstate) (set! %ptop-maxcstate (+ level 1)) ())
                  (list (+ level 1) u d #f))))))))

(def %ptop-power
  (fn (_ acc text)
    (def go
      (fn (self ps st)
        (if (if (null? ps) #t (cu-nth 3 st)) (pair (cu-nth 1 st) (cu-nth 2 st))
          (self (rest ps) (%ptop-power-piece st (first ps))))))
    (go (%ptop-pieces text 192) (list 0 (first acc) (rest acc) #f))))

; read_cstate_counts: each C-state's (USAGE . DURATION) summed over the
; processors' power files
(def %ptop-cstate-counts
  (fn (_)
    (def dir (%ptop-path "acpi/processor"))
    (def names (guard (e ()) (file-list-dir dir)))
    (def go
      (fn (self ns acc)
        (if (null? ns) acc
          (let ((n (byte-len (first ns))))
            (if (if (< n 3) #t (> n 16)) (self (rest ns) acc)
              (let ((r (%ptop-slurp (%str-concat (list dir "/" (first ns) "/power")))))
                (self (rest ns) (if (number? r) acc (%ptop-power acc r)))))))))
    (go names (pair (%ptop-zeros) (%ptop-zeros)))))

(def %ptop-fixed (fn (_ x w) (cu-pad-left (vm-fixed x 1) w)))

; the C-state lines and the wakeups they count: (TEXT . EVENTS)
(def %ptop-cstates
  (fn (_ cur)
    (def on (List filter (fn (_ i) (not (= (cu-nth i (first cur)) 0))) (List range 0 8)))
    (def du (fn (_ i) (- (cu-nth i (first cur)) (cu-nth i (first %ptop-last)))))
    (def dd (fn (_ i) (- (cu-nth i (rest cur)) (cu-nth i (rest %ptop-last)))))
    (def sum (fn (self is f acc) (if (null? is) acc (self (rest is) f (+ acc (f (first is)))))))
    (def events (sum on du 0))
    (pair
      (if (if (= events 0) (<= %ptop-maxcstate 1) #f) "C-state information is not available\n"
        (%str-concat (pair "Cn\t\t  Avg residency\n" (%ptop-cstate-lines on du dd (sum on dd 0)))))
      events)))

(def %ptop-cstate-lines
  (fn (_ on du dd ticks)
    (def total (%ptop-u32 (* %ptop-cpus (* %ptop-sleep %ptop-freq-1000))))
    (def new (%ptop-u32 (- total ticks)))
    (def pct (fn (_ v) (Float / (Float * (Float from v) (Float from 100)) (Float from total))))
    (pair
      (%str-concat (list "C0 (cpu running)        (" (%ptop-fixed (pct (if (>= new 2147483648) 0 new)) 4) "%)\n"))
      (map (fn (_ i)
             (def slept
               (Float / (Float / (%ptop-u64->float (dd i)) (Float + (%ptop-u64->float (du i)) (Float / (Float from 1) (Float from 10))))
                        (Float / (Float from %ptop-freq-1000) (Float from 1000))))
             (%str-concat (list "C" (cu-int->str (+ i 1)) "\t\t" (%ptop-fixed slept 5) "ms ("
                                  (%ptop-fixed (%ptop-u64->float (%ptop-udiv (* (dd i) 100) total)) 4) "%)\n")))
           on))))

; --- timer_stats ----------------------------------------------------------------

(def %ptop-process
  (fn (_ p)
    (match ((str=? p "insmod") "[kernel module]")
           ((str=? p "modprobe") "[kernel module]")
           ((str=? p "swapper") "<kernel core>")
           (#t p))))

; %15.15s
(def %ptop-pad15
  (fn (_ s) (cu-pad-left (if (> (byte-len s) 15) (substring s 0 15) s) 15)))

; a timer's line, counted CNT: PID, the process and the function after it
(def %ptop-timer-line!
  (fn (_ s cnt i)
    (def e1 (%ptop-find s " " (%ptop-skip s i)))
    (def ps (if (null? e1) () (%ptop-skip s (+ e1 1))))
    (def e2 (if (null? ps) () (%ptop-find s " " ps)))
    (if (null? e2) ()
      (let ((func (substring s (%ptop-skip s (+ e2 1)) (byte-len s))))
        (if (if (Str8 starts? "tick_nohz_" func) #t (Str8 starts? "tick_setup_sched_timer" func)) ()
          (%ptop-save-line!
            (%str-concat (list (%ptop-pad15 (%ptop-process (substring s ps e2))) " : " (%ptop-chomp func)))
            (%ptop-i32 cnt)))))))

; "N total events": the timers' extra interrupts, and N a processor
(def %ptop-total-events!
  (fn (_ cnt)
    (def n (%ptop-i32 (if (= %ptop-cpus 0) 0 (ps-div cnt %ptop-cpus))))
    (do (if (if (> n 0) (< n %ptop-irq0) #f)
          (%ptop-save-line! "    <interrupt> : extra timer interrupt" (%ptop-i32 (- %ptop-irq0 n)))
          ())
        n)))

; the COUNT before a line's comma, from its first blank on
(def %ptop-from-blank
  (fn (self s i) (if (if (< i (byte-len s)) (not (%ptop-space? (byte-at s i))) #f) (self s (+ i 1)) (substring s i (byte-len s)))))

(def %ptop-timer-pieces
  (fn (self ps)
    (if (null? ps) 0
      (let ((s (first ps)))
        (def c (%ptop-skip s 0))
        (def comma (%ptop-find s "," c))
        (def count (if (null? comma) "" (substring s c comma)))
        (match
          ((null? comma) (self (rest ps)))
          ((str=? (%ptop-from-blank count 0) " total events") (%ptop-total-events! (%ptop-strtou count)))
          ((null? (Str8 index-of "D" count)) (do (%ptop-timer-line! s (%ptop-strtou count) (+ comma 1)) (self (rest ps))))
          (#t (self (rest ps))))))))

; process_timer_stats: the timers' lines saved; answers the timers' wakeups
; a processor, 0 without them
(def %ptop-timer-stats!
  (fn (_)
    (if %ptop-cant 0
      (let ((r (%ptop-slurp (%ptop-path "timer_stats"))))
        (if (number? r) 0 (%ptop-timer-pieces (%ptop-pieces r 128)))))))

; --- musl's qsort --------------------------------------------------------------

; busybox sorts the lines with qsort, and Alpine's is musl's smoothsort
; (src/stdlib/qsort.c), which is not stable: lines of one count come out in
; its order.  This is that sort, over a vector V and CMP, an element a step
; where musl steps by the element's width.  P, musl's two-word bit set of
; the heaps' orders, is one integer: its high word is only reached by more
; elements than memory holds.

(def %ptop-ctz (fn (self n) (if (= (& n 1) 1) 0 (+ 1 (self (>> n 1))))))

; ROOTS' elements rotated, each taking the next one's, the last the first's
(def %ptop-cycle
  (fn (_ v roots)
    (if (< (length roots) 2) ()
      (let ((tmp (vec-ref v (first roots))))
        (def go
          (fn (self rs)
            (if (null? (rest rs)) (vec-set! v (first rs) tmp)
              (do (vec-set! v (first rs) (vec-ref v (first (rest rs)))) (self (rest rs))))))
        (go roots)))))

(def %ptop-sift
  (fn (_ v cmp lp head pshift)
    (def top (vec-ref v head))
    (def go
      (fn (self at shift acc)
        (if (<= shift 1) acc
          (let ((rt (- at 1)) (lf (- (- at 1) (cu-nth (- shift 2) lp))))
            (match
              ((if (>= (cmp top (vec-ref v lf)) 0) (>= (cmp top (vec-ref v rt)) 0) #f) acc)
              ((>= (cmp (vec-ref v lf) (vec-ref v rt)) 0) (self lf (- shift 1) (pair lf acc)))
              (#t (self rt (- shift 2) (pair rt acc))))))))
    (%ptop-cycle v (List reverse (go head pshift (list head))))))

; the stepsons' walk: (ROOTS HEAD PSHIFT), ROOTS in order
(def %ptop-stepsons
  (fn (self v cmp lp top roots head p pshift trusty)
    (def stepson (if (= p 1) () (- head (cu-nth pshift lp))))
    (def blocked?
      (fn (_)
        (if (if trusty #t (<= pshift 1)) #f
          (let ((rt (- head 1)) (lf (- (- head 1) (cu-nth (- pshift 2) lp))))
            (if (>= (cmp (vec-ref v rt) (vec-ref v stepson)) 0) #t (>= (cmp (vec-ref v lf) (vec-ref v stepson)) 0))))))
    (match
      ((null? stepson) (list (List reverse roots) head pshift))
      ((<= (cmp (vec-ref v stepson) top) 0) (list (List reverse roots) head pshift))
      ((blocked?) (list (List reverse roots) head pshift))
      (#t (let ((trail (%ptop-ctz (- p 1))))
            (self v cmp lp top (pair stepson roots) stepson (>> p trail) (+ pshift trail) #f))))))

(def %ptop-trinkle
  (fn (_ v cmp lp head p pshift trusty)
    (def r (%ptop-stepsons v cmp lp (vec-ref v head) (list head) head p pshift trusty))
    (if (if trusty (= (length (first r)) 1) #f) ()
      (do (%ptop-cycle v (first r))
          (%ptop-sift v cmp lp (cu-nth 1 r) (cu-nth 2 r))))))

; the Leonardo numbers past N, in elements
(def %ptop-leonardo
  (fn (_ n)
    (def go (fn (self a b acc) (if (>= b (+ n 8)) (List reverse acc) (let ((c (+ (+ a b) 1))) (self b c (pair c acc))))))
    (go 1 1 (list 1 1))))

; the heaps built, an element at a time: (P . PSHIFT) with HEAD at the last
(def %ptop-heapify
  (fn (self v cmp lp head high p pshift)
    (if (>= head high) (pair p pshift)
      (if (= (& p 3) 3)
        (do (%ptop-sift v cmp lp head pshift)
            (self v cmp lp (+ head 1) high (| (>> p 2) 1) (+ pshift 2)))
        (do (if (>= (cu-nth (- pshift 1) lp) (- high head))
              (%ptop-trinkle v cmp lp head p pshift #f)
              (%ptop-sift v cmp lp head pshift))
            (if (= pshift 1)
              (self v cmp lp (+ head 1) high (| (<< p 1) 1) 0)
              (self v cmp lp (+ head 1) high (| (<< p (- pshift 1)) 1) 1)))))))

; the heaps taken down, the largest root put last each step
(def %ptop-dequeue
  (fn (self v cmp lp head p pshift)
    (match
      ((if (= pshift 1) (= p 1) #f) ())
      ((<= pshift 1)
        (let ((trail (%ptop-ctz (- p 1))))
          (self v cmp lp (- head 1) (>> p trail) (+ pshift trail))))
      (#t
        (let ((q (>> (^ (<< p 2) 7) 1)) (shift (- pshift 2)))
          (do (%ptop-trinkle v cmp lp (- (- head (cu-nth shift lp)) 1) q (+ shift 1) #t)
              (%ptop-trinkle v cmp lp (- head 1) (| (<< q 1) 1) shift #t)
              (self v cmp lp (- head 1) (| (<< q 1) 1) shift)))))))

(def %ptop-qsort
  (fn (_ items cmp)
    (def n (length items))
    (if (< n 2) items
      (let ((v (Vector from-list items)) (lp (%ptop-leonardo n)))
        (def r (%ptop-heapify v cmp lp 0 (- n 1) 1 1))
        (%ptop-trinkle v cmp lp (- n 1) (first r) (rest r) #f)
        (%ptop-dequeue v cmp lp (- n 1) (first r) (rest r))
        (Vector ->list v)))))

; --- the screen -----------------------------------------------------------------

; smart_ulltoa5 with " KMGTPEZY": N in five places
(def %ptop-five
  (fn (_ n)
    (def scaled
      (fn (self v idx) (if (< v 100000) (pair v idx) (self (ps-div v 1024) (+ idx 1)))))
    (def s (if (> n 99999) (scaled (ps-div (* n 10) 1024) 1) (pair n 0)))
    (def u (ps-div (first s) 10))
    (def v (% (first s) 10))
    (def ch (fn (_ t k) (substring t k (+ k 1))))
    (def lead " 123456789")
    (def digits "0123456789")
    ; each place after the first a digit once a place before it was
    (def next (fn (_ prev) (if (str=? prev " ") lead digits)))
    (match
      ((= (rest s) 0)
        (let ((c0 (ch lead (ps-div u 1000))))
          (def c1 (ch (next c0) (% (ps-div u 100) 10)))
          (def c2 (ch (next (if (str=? c0 " ") c1 c0)) (% (ps-div u 10) 10)))
          (def f3 (next (match ((not (str=? c0 " ")) c0) ((not (str=? c1 " ")) c1) (#t c2))))
          (%str-concat (list c0 c1 c2 (ch f3 (% u 10)) (ch digits v)))))
      ((>= u 100)
        (let ((c0 (ch lead (ps-div u 1000))))
          (def c1 (ch (next c0) (% (ps-div u 100) 10)))
          (def f2 (next (if (str=? c0 " ") c1 c0)))
          (%str-concat (list c0 c1 (ch f2 (% (ps-div u 10) 10)) (ch digits (% u 10)) (ch " KMGTPEZY" (rest s))))))
      (#t
        (let ((c0 (ch lead (ps-div u 10))))
          (%str-concat (list c0 (ch (next c0) (% u 10)) "." (ch digits v) (ch " KMGTPEZY" (rest s)))))))))

; C's atoi: blanks, a sign, digits
(def %ptop-atoi
  (fn (_ s)
    (def i (%ptop-skip s 0))
    (def c (%ptop-at s i))
    (def v (first (%ptop-digits s (if (if (= c 43) #t (= c 45)) (+ i 1) i) 0 #f)))
    (%ptop-i32 (if (= c 45) (- 0 v) v))))

; get_terminal_width_height's height of stdout: LINES over the terminal's,
; 24 for one at most 1 or from 30000 on
(def %ptop-height
  (fn (_)
    (def env (sys-getenv "LINES"))
    (def m (if (null? env) (Term measure 1) ()))
    (def v (if (null? env) (if (null? m) 0 (rest m)) (%ptop-atoi env)))
    (if (if (<= v 1) #t (>= v 30000)) 24 v)))

(def %ptop-causes
  (fn (_ lines)
    (def most (%ptop-u32 (- (%ptop-height) 12)))
    (def go
      (fn (self ls n acc)
        (match
          ((null? ls) (%str-concat (List reverse acc)))
          ((<= (rest (first ls)) 0) (self (rest ls) n acc))
          ((>= n most) (self (rest ls) (+ n 1) acc))
          (#t (let ((l (first ls)))
                (self (rest ls) (+ n 1)
                  (pair (%str-concat
                          (list " " (%ptop-fixed (Float / (Float * (Float from (rest l)) (Float from 100)) (Float from %ptop-cumulative)) 5)
                                "% (" (%ptop-five (rest l)) ")   " (first l) "\n"))
                        acc)))))))
    (go lines 0 ())))

; show_timerstats
(def %ptop-show-causes
  (fn (_)
    (def lines (%ptop-qsort (List reverse %ptop-lines) (fn (_ a b) (%ptop-i32 (- (rest b) (rest a))))))
    (if %ptop-cant
      (do (%ptop-out "\n")
          (file-write 2 "powertop: no stats available; run as root or enable the timer_stats module\n"))
      (%ptop-out (string-append "\nTop causes for wakeups:\n" (%ptop-causes lines))))))

(def %ptop-screen!
  (fn (_)
    (set! %ptop-lines ())
    (%ptop-irq-counts!)
    (def cs (%ptop-cstates (%ptop-cstate-counts)))
    (%ptop-out (%str-concat (list %ptop-esc "[H" %ptop-esc "[J" (first cs))))
    (def n (%ptop-timer-stats!))
    (def events
      (if (= (rest cs) 0) (%ptop-u32 (+ (* n %ptop-cpus) %ptop-irq-total)) (rest cs)))
    (%ptop-out (%str-concat (list "\nWakeups-from-idle in 10 seconds: " (%ptop-u64->str events) "\n")))
    (map (fn (_ l) (set! %ptop-cumulative (%ptop-i32 (+ %ptop-cumulative (rest l))))) %ptop-lines)
    (%ptop-show-causes)
    (%ptop-flush!)
    (set! %ptop-last (%ptop-cstate-counts))))

; --- the terminal and the keys --------------------------------------------------

(def %ptop-tio-at (fn (_ k) (* k (if os-darwin? 8 4))))
(def %ptop-cc (fn (_ k) (+ k (if os-darwin? 32 17))))

; set_termios_to_raw with TERMIOS_CLEAR_ISIG on fd 0: ICANON, ECHO, ECHONL
; and ISIG off, a read of one byte with no timeout.  Answers the settings
; before, or nil when fd 0 is no terminal.
(def %ptop-raw!
  (fn (_)
    (def saved (str-make-raw 128))
    (if (< (in-call (cu-ptr-call (cu-libc-sym "tcgetattr") 0 (cu-str->ptr saved))) 0) ()
      (let ((raw (str-make-raw 128)))
        (do (cu-ptr-call (cu-libc-sym "tcgetattr") 0 (cu-str->ptr raw))
            (let ((p (cu-str->ptr raw)) (at (%ptop-tio-at 3)) (off (if os-darwin? 408 75)))
              (do (cu-ptr-set! p at (- (cu-ptr-ref p at 4) (& (cu-ptr-ref p at 4) off)) 4)
                  (cu-ptr-set! p (%ptop-cc (if os-darwin? 16 6)) 1 1)
                  (cu-ptr-set! p (%ptop-cc (if os-darwin? 17 5)) 0 1)
                  (cu-ptr-call (cu-libc-sym "tcsetattr") 0 0 p)))
            saved)))))

(def %ptop-restore!
  (fn (_)
    (if (null? %ptop-saved) ()
      (cu-ptr-call (cu-libc-sym "tcsetattr") 0 0 (cu-str->ptr %ptop-saved)))))

; BB_FATAL_SIGS, caught: each ends the run as busybox's handler ends it
(def %ptop-fatal (list "HUP" "INT" "TERM" "PIPE" "QUIT" "ABRT" "ALRM" "VTALRM" "XCPU" "XFSZ" "USR1" "USR2"))

(def %ptop-catch!
  (fn (_)
    (do (set! %ptop-sigs
          (map rest (List filter (fn (_ e) (List any? (fn (_ n) (str=? n (first e))) %ptop-fatal)) (sys-signals))))
        (map (fn (_ n) (Sys catch-signal n)) %ptop-sigs))))

(def %ptop-signalled?
  (fn (_) (List any? (fn (_ n) (Sys take-signal n)) %ptop-sigs)))

; the wait for a key, a second at a time so a signal is seen: 'timeout,
; 'key, 'quit for q, the interrupt key or the end of input, 'signal
(def %ptop-key
  (fn (self seconds)
    (def ready (sys-poll (list (pair 0 (list (lit in)))) 1000))
    (match
      ((%ptop-signalled?) (lit signal))
      ((null? ready) (if (<= seconds 1) (lit timeout) (self (- seconds 1))))
      (#t (let ((s (file-read-fd 0 1)))
            (match ((= (byte-len s) 0) (lit quit))
                   ((= (byte-at s 0) %ptop-vintr) (lit quit))
                   ((= (| (byte-at s 0) 32) #\q) (lit quit))
                   (#t (lit key))))))))

; --- the applet -----------------------------------------------------------------

(def %ptop-end
  (fn (_ status)
    (do (%ptop-flush!)
        (%ptop-restore!)
        (map (fn (_ n) (sys-signal n 0)) %ptop-sigs)
        status)))

; a fatal signal: the terminal put back and _exit(1), what stdio held lost
(def %ptop-killed
  (fn (_)
    (do (set! %ptop-pending ())
        (%ptop-end 1))))

(def %ptop-loop
  (fn (self)
    (cu-heap-collect)
    (if (%ptop-timer! "1\n") (set! %ptop-cant #t) ())
    (def k (%ptop-key %ptop-sleep))
    (match
      ((eq? k (lit quit)) (do (%ptop-out "\n") (%ptop-end 0)))
      ((eq? k (lit signal)) (%ptop-killed))
      (#t (do (if (%ptop-timer! "0\n") (set! %ptop-cant #t) ())
              (%ptop-screen!)
              (self))))))

(def %ptop-main
  (fn (_)
    (if (= (sys-geteuid) 0) () (file-write 2 "powertop: run as root to collect enough information\n"))
    (set! %ptop-cpus (%ptop-cpu-count))
    (file-write 1 "Collecting data for 10 seconds\n")
    (cu-stdin-to-command!)
    (set! %ptop-saved (%ptop-raw!))
    (set! %ptop-vintr (if (null? %ptop-saved) 0 (cu-ptr-ref (cu-str->ptr %ptop-saved) (%ptop-cc 0) 1)))
    (%ptop-catch!)
    (%ptop-irq-counts!)
    (set! %ptop-last (%ptop-cstate-counts))
    (set! %ptop-cant (%ptop-timer! "0\n"))
    (%ptop-loop)))

; busybox's powertop reads no options: its words are ignored
(def cu-powertop
  (fn (_ argv stdin-thunk)
    (%ptop-reset!)
    (guard (e (if (eq? (cu-err-label e) (lit powertop)) (%ptop-end 1) (error e)))
      (%ptop-main))))

(provide cu/powertop cu-powertop)

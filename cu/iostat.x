; # x-coreutils -- the small tools, as applets
;
; ## cu/iostat.x -- iostat
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's iostat (procps/iostat.c, after sysstat 9.1.2): the CPU's shares
; and each disk's transfers a second, since boot and then over each interval.
; It reads Host's cpu and disks records; a disk's sectors are its bytes over
; 512, as /proc/diskstats counts them.  The rates are busybox's doubles,
; printed as its printf prints them (%vm-fixed).
;
; busybox's quirks are kept: a disk's rates are a count over the interval in
; USER_HZ ticks times 100, a partition is an sd name and a digit, and a disk
; skipped as unused keeps its last sample.

; --- the sysstat header --------------------------------------------------------

; Unix seconds as busybox's strftime writes them in the C locale: %x is
; mm/dd/yy and %X hh:mm:ss
(def %io-date (fn (_ secs) (%cu-date-fmt "%m/%d/%y" (%cu-date-split secs #f) secs)))
(def %io-time (fn (_ secs) (%cu-date-fmt "%H:%M:%S" (%cu-date-split secs #f) secs)))

; SYSNAME RELEASE (NODENAME), then what AFTER-NAME formats from the date and
; the machine: iostat's and mpstat's first lines differ in their tabs
(def %io-uname-line
  (fn (_ secs cpus tabbed)
    (def u (sys-uname))
    (def get (fn (_ k) (Assoc get k u)))
    (string-concat
      (list (get (lit sysname)) " " (get (lit release)) " (" (get (lit nodename)) ")"
            (if tabbed " \t" "\t") (%io-date secs) (if tabbed " \t_" "\t_") (get (lit machine))
            "_\t(" (cu-int->str cpus) " CPU)\n"))))

; --- a sample --------------------------------------------------------------------

; The CPU's ticks: user nice system idle iowait irq softirq steal guest, then
; their sum less guest, which user already counts
(def %io-cpu
  (fn (_)
    (def t (host-cpu))
    (def ts (map (fn (_ k) (%vm-ticks (Assoc get k t)))
              (lit (user nice system idle iowait irq softirq steal guest))))
    (append ts (list (- (List fold + 0 ts) (cu-nth 8 ts))))))

; A disk's (NAME RD-OPS RD-SECTORS WR-OPS WR-SECTORS), the name cut to the 12
; characters busybox keeps
(def %io-disk
  (fn (_ d)
    (def name (Assoc get (lit name) d))
    (list (if (> (byte-len name) 12) (substring name 0 12) name)
          (%vm-get (lit reads) d) (%ps-div (%vm-get (lit read-bytes) d) 512)
          (%vm-get (lit writes) d) (%ps-div (%vm-get (lit write-bytes) d) 512))))

; is_partition: an sd name, then a digit
(def %io-partition?
  (fn (_ n)
    (if (>= (byte-len n) 4)
      (if (str=? (substring n 0 2) "sd")
        (if (= (byte-at n 2) #\a) (if (>= (byte-at n 3) #\0) (<= (byte-at n 3) #\9) #f) #f)
        #f)
      #f)))

; --- the reports ---------------------------------------------------------------

(def %io-cpu-report
  (fn (_ p c itv)
    (def pc (fn (_ a b) (%vm-right (%vm-fixed (%vm-rate (- b a) itv 100) 2) 7)))
    (def at (fn (_ v i) (cu-nth i v)))
    (def sys (fn (_ v) (+ (+ (at v 2) (at v 6)) (at v 5))))
    (string-concat
      (list "avg-cpu:  %user   %nice %system %iowait  %steal   %idle\n        "
            (pc (at p 0) (at c 0)) " " (pc (at p 1) (at c 1)) " " (pc (sys p) (sys c)) " "
            (pc (at p 4) (at c 4)) " " (pc (at p 7) (at c 7)) " " (pc (at p 3) (at c 3)) "\n"))))

(def %io-dev-header
  (fn (_ unit)
    (string-concat
      (list "Device:" (%vm-right "tps" 15) (%vm-right unit 6) "_read/s" (%vm-right unit 6) "_wrtn/s"
            (%vm-right unit 6) "_read" (%vm-right unit 6) "_wrtn\n"))))

; One disk's line from its last sample P and this one C, both
; (NAME RD-OPS RD-SECTORS WR-OPS WR-SECTORS)
(def %io-dev-line
  (fn (_ p c itv div)
    (def at (fn (_ v i) (cu-nth i v)))
    (def rate (fn (_ a b) (Float / (%vm-rate (- b a) itv 100) (Float from div))))
    (string-concat
      (list (cu-pad-right (first c) 13) " "
            (%vm-right (%vm-fixed (%vm-rate (- (+ (at c 1) (at c 3)) (+ (at p 1) (at p 3))) itv 100) 2) 8) " "
            (%vm-right (%vm-fixed (rate (at p 2) (at c 2)) 2) 12) " "
            (%vm-right (%vm-fixed (rate (at p 4) (at c 4)) 2) 12) " "
            (%vm-right (cu-int->str (%ps-div (- (at c 2) (at p 2)) div)) 10) " "
            (%vm-right (cu-int->str (%ps-div (- (at c 4) (at p 4)) div)) 10) "\n"))))

; The disks' lines, and the last samples kept: (TEXT . PREVS), PREVS an alist
; by name.  With NAMES, those disks alone; otherwise every disk but a
; partition and, unless ALL, one never used.  -z leaves out a disk with no
; transfers since its last sample, which it still takes as its last.
(def %io-dev-report
  (fn (_ disks prevs names all z itv div)
    (def zero (fn (_ name) (list name 0 0 0 0)))
    ; the alist is keyed by name, a string, so by equal?
    (def put (fn (_ name v ps) (pair (pair name v) (filter (fn (_ e) (not (str=? (first e) name))) ps))))
    (def go
      (fn (self ds prevs acc)
        (if (null? ds) (pair (string-concat (reverse acc)) prevs)
          (let ((c (%io-disk (first ds))))
            (def name (first c))
            (def seen (Assoc find name prevs))
            (def p (if (null? seen) (zero name) (rest seen)))
            (def known (if (null? seen) (put name (zero name) prevs) prevs))
            (match
              ((if (null? names) (%io-partition? name) (not (cu-member-s? name names)))
                (self (rest ds) known acc))
              ((if (null? names) (if all #f (if (= (cu-nth 1 c) 0) (= (cu-nth 3 c) 0) #f)) #f)
                (self (rest ds) known acc))
              (#t (self (rest ds) (put name c known)
                    (if (if z (if (= (cu-nth 1 p) (cu-nth 1 c)) (= (cu-nth 3 p) (cu-nth 3 c)) #f) #f)
                      acc
                      (pair (%io-dev-line p c itv div) acc)))))))))
    (go disks prevs ())))

; --- iostat ------------------------------------------------------------------

(def %cu-iostat
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "iostat" argv))
    (def ops (Opts operands o))
    (def unknown (if (null? (Opts unknown o)) (%vm-dash-number ops) (Opts unknown o)))
    (def on (fn (_ f) (Opts on? o f)))
    ; the device names lead, up to the first word that starts with a digit
    (def split
      (fn (self ops acc)
        (if (if (null? ops) #t (if (> (byte-len (first ops)) 0) (if (>= (byte-at (first ops) 0) #\0) (<= (byte-at (first ops) 0) #\9) #f) #f))
          (pair (reverse acc) ops)
          (self (rest ops) (pair (first ops) acc)))))
    (def parts (split ops ()))
    (def words (first parts))
    (def nums (rest parts))
    (def unit (cu-last-given o (list "-k" "-m")))
    (def both (not (if (on "-c") #t (on "-d"))))
    ; the options are refused before an operand is read, as getopt runs first
    (if (not (null? unknown)) (cu-refuse-option "iostat" unknown)
      (let ((interval (if (null? nums) 0 (%cu-range-number "iostat" (first nums) 0 2147483647))))
        (def count
          (match
            ((null? interval) ())
            ((null? nums) 1)
            ((null? (rest nums)) (if (= interval 0) 1 -1))
            (#t (%cu-range-number "iostat" (first (rest nums)) 0 2147483647))))
        (if (null? count) 1
          (%io-main (if both #t (on "-c")) (if both #t (on "-d")) (on "-t") (on "-z")
            (match ((null? unit) (pair "Blk" 1)) ((str=? unit "-m") (pair " MB" 2048)) (#t (pair " kB" 2)))
            (%io-devices words) (cu-member-s? "ALL" words) interval count))))))

; The device names asked for, a /dev/ prefix gone, ALL and repeats left out
(def %io-devices
  (fn (_ words)
    (def strip (fn (_ w) (if (if (> (byte-len w) 5) (str=? (substring w 0 5) "/dev/") #f) (substring w 5 (byte-len w)) w)))
    (def go
      (fn (self ws acc)
        (if (null? ws) (reverse acc)
          (let ((n (strip (first ws))))
            (self (rest ws) (if (if (str=? (first ws) "ALL") #t (cu-member-s? n acc)) acc (pair n acc)))))))
    (go words ())))

(def %io-main
  (fn (_ cpu dev stamp z unit names all interval count)
    (def cpus (length (host-cpus)))
    (def smp (> cpus 1))
    (file-write 1 (string-append (%io-uname-line (%vm-now) (if (= cpus 0) 1 cpus) #t) "\n"))
    (def go
      (fn (self prev prev-up prevs count)
        (def now (%vm-now))
        (def c (%io-cpu))
        (def up (if smp (%vm-uptime) 0))
        (def itv (let ((d (- (cu-nth 9 c) (cu-nth 9 prev)))) (if (= d 0) 1 d)))
        (if stamp (file-write 1 (string-concat (list (%io-date now) " " (%io-time now) "\n"))))
        (if cpu (file-write 1 (string-append (%io-cpu-report prev c itv) (if dev "\n" ""))))
        (def r
          (if dev
            (let ((ditv (if smp (let ((d (- up prev-up))) (if (= d 0) 1 d)) itv)))
              (%io-dev-report (host-disks) prevs names all z ditv (rest unit)))
            (pair "" prevs)))
        (if dev (file-write 1 (string-append (%io-dev-header (first unit)) (first r))))
        (file-write 1 "\n")
        (def left (if (> count 0) (- count 1) count))
        (if (if (> count 0) (= left 0) #f) 0
          (do (%vm-wait (* interval 1000000))
              (self c up (rest r) left)))))
    (go (list 0 0 0 0 0 0 0 0 0 0) 0 () count)))

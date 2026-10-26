; # x-coreutils -- the small tools, as applets
;
; ## cu/taskset.x -- taskset: a process's CPU affinity shown and set
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's taskset with FEATURE_TASKSET_FANCY and FEATURE_TASKSET_CPULIST
; (util-linux/taskset.c).  The mask is sched_getaffinity's, read in a buffer
; of 8 bytes doubled until the kernel takes it (sys-affinity, cu/prims.x),
; and written as the CPUs' bits in hex, each 8-byte word's own, the word of
; the lowest CPUs first; with -c it is the CPUs' list, 0-3,7.  A mask given
; is hex, a 0x before it allowed, as long as it likes, its bits past the
; buffer's dropped; -c's list takes N, N-M and N-M:STRIDE, joined by commas.
; Without -p the mask is this process's, which then becomes PROG; with -p
; it is PID's, shown, and when a mask comes before PID set and shown again;
; with -a too, each thread's in /proc/PID/task, or PID's alone without it.

(module cu/taskset)

(import cu/cli cu-opts cu-refuse-option cu-usage)
(import cu/inet inet-set! inet-zeros)
(import cu/prims byte-at byte-len cu-err-label cu-int->str cu-stdin-to-command!
  file-err-text file-list-dir file-write libc-strerror map string-append
  string-concat substring sys-affinity sys-affinity! sys-exec-or-err sys-exit)
(import cu/strings cu-range-number)

(def %tk-die
  (fn (_ msg)
    (do (file-write 2 (string-concat (list "taskset: " msg "\n")))
        (Err raise (lit taskset) msg ()))))

(def %tk-uint-max 4294967295)

; PID's mask, the buffer's size doubled from BYTES while the kernel calls it
; too small: (BUFFER . BYTES)
(def %tk-mask
  (fn (self pid bytes)
    (def buf (inet-zeros bytes))
    (def e (sys-affinity pid buf bytes))
    (match ((= e 0) (pair buf bytes))
           ((if (= e 22) (< bytes 1073741824) #f) (self pid (* bytes 2)))
           (#t (%tk-die (string-concat (list "can't get pid " (cu-int->str pid) "'s affinity: " (libc-strerror e))))))))

; a byte's two hex digits
(def %tk-hex2
  (fn (_ b)
    (def d (fn (_ n) (substring "0123456789abcdef" n (+ n 1))))
    (string-append (d (>> b 4)) (d (& b 15)))))

; from_mask: each 8-byte word's 16 digits, the first word first, the
; leading zeros dropped but the last
(def %tk-mask-hex
  (fn (_ buf bytes)
    (def digits
      (string-concat
        (map (fn (_ i) (%tk-hex2 (& (byte-at buf (+ (* (>> i 3) 8) (- 7 (& i 7)))) 255)))
             (List range 0 bytes))))
    (def end (byte-len digits))
    (def lead (fn (self i) (if (if (< i (- end 1)) (= (byte-at digits i) #\0) #f) (self (+ i 1)) i)))
    (substring digits (lead 0) end)))

(def %tk-bit?
  (fn (_ buf c) (not (= (& (byte-at buf (>> c 3)) (<< 1 (& c 7))) 0))))

; the last CPU of the run in BUF that C starts, END its bits
(def %tk-run-end
  (fn (self buf c end)
    (if (if (< (+ c 1) end) (%tk-bit? buf (+ c 1)) #f) (self buf (+ c 1) end) c)))

(def %tk-run-text
  (fn (_ c last)
    (if (= last c) (cu-int->str c) (string-concat (list (cu-int->str c) "-" (cu-int->str last))))))

; print_cpulist: the runs of CPUs in the mask, N or N-M, joined by commas
(def %tk-mask-list
  (fn (_ buf bytes)
    (def end (* bytes 8))
    (def go
      (fn (self c runs)
        (match ((>= c end) (Str8 join "," (List reverse runs)))
               ((%tk-bit? buf c)
                 (let ((last (%tk-run-end buf c end))) (self (+ last 2) (pair (%tk-run-text c last) runs))))
               (#t (self (+ c 1) runs)))))
    (go 0 ())))

(def %tk-or!
  (fn (_ buf at v) (inet-set! buf at (| (& (byte-at buf at) 255) v) 1)))

(def %tk-digit? (fn (_ c) (if (>= c #\0) (<= c #\9) #f)))

(def %tk-alnum?
  (fn (_ c) (if (%tk-digit? c) #t (if (>= (| c 32) #\a) (<= (| c 32) #\z) #f))))

; bb_strtou base 10 from S's I: (N . NEXT), N the unsigned int max when no
; number starts there, it is past an unsigned int, or a letter follows it
(def %tk-strtou
  (fn (_ s i)
    (def end (byte-len s))
    (def go
      (fn (self j n)
        (if (if (< j end) (%tk-digit? (byte-at s j)) #f)
          (self (+ j 1) (if (> n %tk-uint-max) n (+ (* n 10) (- (byte-at s j) #\0))))
          (pair (if (if (> n %tk-uint-max) #t (if (< j end) (%tk-alnum? (byte-at s j)) #f)) %tk-uint-max n) j))))
    (if (if (< i end) (%tk-alnum? (byte-at s i)) #f) (go i 0) (pair %tk-uint-max i))))

; one item of S's list at I: (FIRST LAST STRIDE NEXT)
(def %tk-item
  (fn (_ s i)
    (def end (byte-len s))
    (def at? (fn (_ j c) (if (< j end) (= (byte-at s j) c) #f)))
    (def a (%tk-strtou s i))
    (def b (if (at? (rest a) #\-) (%tk-strtou s (+ (rest a) 1)) a))
    (def st (if (if (at? (rest a) #\-) (at? (rest b) #\:) #f) (%tk-strtou s (+ (rest b) 1)) (pair 1 (rest b))))
    (list (first a) (first b) (first st) (rest st))))

; parse_cpulist: S's CPUs set in BUF, as many as its BYTES hold
(def %tk-list!
  (fn (self buf bytes s i)
    (def end (byte-len s))
    (def it (%tk-item s i))
    (def lo (first it))
    (def hi (List ref 1 it))
    (def stride (List ref 2 it))
    (def next (List ref 3 it))
    (when (match ((if (< next end) (not (= (byte-at s next) #\,)) #f) #t)
                 ((> lo hi) #t)
                 ((= hi %tk-uint-max) #t)
                 ((= stride 0) #t)
                 (#t (> (- stride 1) 1073741823)))
      (%tk-die (string-concat (list "bad affinity '" s "'"))))
    (def put
      (fn (self c)
        (when (if (<= c hi) (< c (* bytes 8)) #f)
          (do (%tk-or! buf (>> c 3) (<< 1 (& c 7))) (self (+ c stride))))))
    (put lo)
    (when (< next end) (self buf bytes s (+ next 1)))))

; a hex digit's value, or nil
(def %tk-nibble
  (fn (_ c)
    (match ((%tk-digit? c) (- c #\0))
           ((if (>= (| c 32) #\a) (<= (| c 32) #\f) #f) (+ 10 (- (| c 32) #\a)))
           (#t ()))))

; the hex mask S in BUF, from its last digit, the least, the bits past BYTES
; dropped
(def %tk-hex!
  (fn (_ buf bytes s)
    (def end (byte-len s))
    (def from (if (if (> end 1) (if (= (byte-at s 0) #\0) (= (| (byte-at s 1) 32) #\x) #f) #f) 2 0))
    (def go
      (fn (self j bit)
        (when (>= j from)
          (let ((v (%tk-nibble (byte-at s j))))
            (do (when (null? v) (%tk-die (string-concat (list "bad affinity '" (substring s from end) "'"))))
                (when (< bit (* bytes 8)) (%tk-or! buf (>> bit 3) (<< v (& bit 7))))
                (self (- j 1) (+ bit 4)))))))
    (go (- end 1) 0)))

; PID's mask, M, as -p shows it, WHEN current or new
(def %tk-show
  (fn (_ o pid m when)
    (file-write 1
      (string-concat
        (if (Opts on? o "-c")
          (list "pid " (cu-int->str pid) "'s " when " affinity list: " (%tk-mask-list (first m) (rest m)) "\n")
          (list "pid " (cu-int->str pid) "'s " when " affinity mask: " (%tk-mask-hex (first m) (rest m)) "\n"))))))

; AFF set as PID's affinity, in a buffer of BYTES
(def %tk-set
  (fn (_ o pid aff bytes)
    (def buf (inet-zeros bytes))
    (if (Opts on? o "-c") (%tk-list! buf bytes aff 0) (%tk-hex! buf bytes aff))
    (def e (sys-affinity! pid buf bytes))
    (unless (= e 0)
      (%tk-die (string-concat (list "can't set pid " (cu-int->str pid) "'s affinity: " (libc-strerror e)))))))

; process_pid_str: PID's affinity, PID 0 this process's; shown with -p,
; then AFF, when given, set, and with -p shown again
(def %tk-pid
  (fn (_ o pid aff)
    (def m (%tk-mask pid 8))
    (when (Opts on? o "-p") (%tk-show o pid m "current"))
    (unless (null? aff)
      (do (%tk-set o pid aff (rest m))
          (when (Opts on? o "-p") (%tk-show o pid (%tk-mask pid (rest m)) "new"))))
    0))

; xatou_range 1..INT_MAX: "taskset -p 0" is refused
(def %tk-pid-of
  (fn (_ s)
    (let ((n (cu-range-number "taskset" s 1 2147483647)))
      (if (null? n) (Err raise (lit taskset) "pid" ()) n))))

; the threads in /proc/PID/task, those whose names start with a digit, in
; the directory's order, or nil with no such directory
(def %tk-tasks
  (fn (_ pid-word)
    (def names (guard (e ()) (file-list-dir (string-concat (list "/proc/" pid-word "/task")))))
    (List filter (fn (_ n) (if (> (byte-len n) 0) (%tk-digit? (byte-at n 0)) #f)) (List reverse names))))

; PROG run in place of this process, as BB_EXECVP_or_die runs it
(def %tk-exec
  (fn (_ prog)
    (cu-stdin-to-command!)
    (def err (sys-exec-or-err (first prog) (rest prog)))
    (file-write 2 (string-concat (list "taskset: can't execute '" (first prog) "': " (file-err-text err) "\n")))
    (sys-exit (if (string=? (file-err-text err) "No such file or directory") 127 126))))

; -p: AFF and PID, or PID alone; the rest is ignored
(def %tk-p
  (fn (_ o words)
    (def pid-word (if (null? (rest words)) (first words) (first (rest words))))
    (def aff (if (null? (rest words)) () (first words)))
    (def tasks (if (Opts on? o "-a") (%tk-tasks pid-word) ()))
    (if (pair? tasks)
      (do (map (fn (_ t) (%tk-pid o (%tk-pid-of t) aff)) tasks) 0)
      (%tk-pid o (%tk-pid-of pid-word) aff))))

; the first word among the leading options that is a dash and a digit, which
; Opts reads as a number and getopt as an option: nil for none
(def %tk-dash-digit
  (fn (self argv)
    (match ((null? argv) ())
           ((if (> (byte-len (first argv)) 1) (not (= (byte-at (first argv) 0) #\-)) #t) ())
           ((string=? (first argv) "--") ())
           ((%tk-digit? (byte-at (first argv) 1)) (first argv))
           (#t (self (rest argv))))))

(def %tk-main
  (fn (_ argv)
    (def dd (%tk-dash-digit argv))
    (if (null? dd) (%tk-run argv) (cu-refuse-option "taskset" dd))))

(def %tk-run
  (fn (_ argv)
    (def o (cu-opts "taskset" argv))
    (def words (Opts operands o))
    (match ((null? words) (cu-usage "taskset"))
           ((Opts on? o "-p") (%tk-p o words))
           ((null? (rest words)) (cu-usage "taskset"))
           (#t (do (%tk-pid o 0 (first words)) (%tk-exec (rest words)))))))

(def cu-taskset
  (fn (_ argv stdin-thunk)
    (guard (e (if (eq? (cu-err-label e) (lit taskset)) 1 (error e)))
      (%tk-main argv))))

(provide cu/taskset cu-taskset)

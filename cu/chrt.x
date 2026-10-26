; # x-coreutils -- the small tools, as applets
;
; ## cu/chrt.x -- chrt: a process's scheduling policy and priority
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's chrt (util-linux/chrt.c).  -m shows each policy's priorities;
; -p PID shows PID's policy and priority, and with a PRIO before the PID
; sets them and shows them again; otherwise PRIO is set on this process,
; which then becomes PROG.  The policy is RR unless -f, -o, -b or -i names
; another, and one at most may be named.  The calls are the kernel's
; through syscall doors, as busybox makes them where musl's would not;
; Darwin has the priority ranges alone, so its other calls fail as ENOSYS.

(module cu/chrt)

(import cu/cli cu-opts cu-usage)
(import cu/inet inet-set! inet-zeros)
(import cu/inetd in-c in-call)
(import cu/prims byte-at byte-len cu-err-label cu-int->str cu-ptr-call
  cu-ptr-ref cu-stdin-to-command! cu-str->ptr file-err-text file-write
  hx-strtoul libc-strerror string-append string-concat string=?
  sys-exec-or-err sys-exit)

(def %ch-die
  (fn (_ msg)
    (do (file-write 2 (string-concat (list "chrt: " msg "\n")))
        (Err raise (lit chrt) msg ()))))

(def %ch-usage (fn (_) (Err raise (lit chrt-usage) "usage" ())))

; the policies by their Linux numbers, as busybox names them
(def %ch-names (list "OTHER" "FIFO" "RR" "BATCH" "ISO" "IDLE" "DEADLINE"))
(def %ch-name
  (fn (_ pol) (if (> pol 6) (cu-int->str pol) (List ref pol %ch-names))))

; NAME's door, or nil where this platform has no such call
(def %ch-door
  (fn (_ name) (guard (_ ()) (syscall-door name))))

; CALL through its door with ARGS: what it answers, -1 with errno set on a
; failure, and -1 with ENOSYS where the platform lacks it
(def %ch-enosys (if os-darwin? 78 38))
(def %ch-call
  (fn (_ name a0 a1 a2)
    (let ((door (%ch-door name)))
      (if (null? door) (pair -1 %ch-enosys)
        (let ((r (in-call (door a0 a1 a2))))
          (if (< r 0) (pair r (Err errno-of r)) (pair r 0)))))))

; POL's priority bound, sched_get_priority_min or _max; Darwin's libc has
; these where its kernel has no call
(def %ch-bound
  (fn (_ which pol)
    (def name (if (eq? which (lit min)) "sched_get_priority_min" "sched_get_priority_max"))
    (if os-darwin? (in-call (cu-ptr-call (in-c name) pol))
      (first (%ch-call (if (eq? which (lit min)) (lit sched_get_priority_min) (lit sched_get_priority_max))
                       pol () ())))))

(def %ch-show-min-max
  (fn (_ pol)
    (def lo (%ch-bound (lit min) pol))
    (def hi (%ch-bound (lit max) pol))
    (file-write 1
      (if (if (< lo 0) #t (< hi 0))
        (string-concat (list "SCHED_" (%ch-name pol) " not supported\n"))
        (string-concat (list "SCHED_" (%ch-name pol) " min/max priority\t: "
                             (cu-int->str lo) "/" (cu-int->str hi) "\n"))))))

; xstrtou_range's template: S in BASE, no sign or space before it and
; nothing after, at most LIMIT, from LO to HI
(def %ch-number
  (fn (_ s base lo hi limit)
    (def c (if (> (byte-len s) 0) (byte-at s 0) 0))
    (def r (if (match ((= c #\-) #t) ((= c #\+) #t) ((= c 32) #t) ((if (>= c 9) (<= c 13) #f) #t) (#t #f))
             (pair () 0) (hx-strtoul s 0 base limit)))
    (match
      ((if (= (rest r) 0) #t (if (null? (first r)) #t (< (rest r) (byte-len s))))
        (%ch-die (string-concat (list "invalid number '" s "'"))))
      ((if (< (first r) lo) #t (> (first r) hi))
        (%ch-die (string-concat (list "number " s " is not in " (cu-int->str lo) ".." (cu-int->str hi) " range"))))
      (#t (first r)))))

(def %ch-fail
  (fn (_ what pid errno)
    (%ch-die (string-concat (list "can't " what " pid " (cu-int->str pid) "'s policy: " (libc-strerror errno))))))

; PID's policy and priority, as now or as just set; the policy without
; SCHED_RESET_ON_FORK, which the kernel answers in it
(def %ch-print
  (fn (_ pid which)
    (def p (%ch-call (lit sched_getscheduler) pid () ()))
    (when (< (first p) 0) (%ch-fail "get" pid (rest p)))
    (file-write 1 (string-concat (list "pid " (cu-int->str pid) "'s " which " scheduling policy: SCHED_"
                                       (%ch-name (& (first p) 1073741823)) "\n")))
    (def sp (inet-zeros 4))
    (def g (%ch-call (lit sched_getparam) pid sp ()))
    (when (< (first g) 0)
      (%ch-die (string-concat (list "can't get pid " (cu-int->str pid) "'s attributes: " (libc-strerror (rest g))))))
    (file-write 1 (string-concat (list "pid " (cu-int->str pid) "'s " which " scheduling priority: "
                                       (cu-int->str (cu-ptr-ref (cu-str->ptr sp) 0 4)) "\n")))))

(def %ch-set
  (fn (_ pid policy priority)
    (def n (%ch-number priority 0 (%ch-bound (lit min) policy) (%ch-bound (lit max) policy) 4294967295))
    (def sp (inet-zeros 4))
    (inet-set! sp 0 n 4)
    (def r (%ch-call (lit sched_setscheduler) pid policy sp))
    (when (< (first r) 0) (%ch-fail "set" pid (rest r)))))

(def %ch-policy
  (fn (_ o)
    (def named (List filter (fn (_ f) (Opts on? o f)) (list "-r" "-f" "-o" "-b" "-i")))
    (match
      ((> (length named) 1) (%ch-usage))
      ((null? named) 2)
      (#t (let ((f (first named)))
            (match ((string=? f "-f") 1) ((string=? f "-o") 0) ((string=? f "-b") 3)
                   ((string=? f "-i") 5) (#t 2)))))))

(def %ch-exec
  (fn (_ argv)
    (cu-stdin-to-command!)
    (let ((err (sys-exec-or-err (first argv) (rest argv))))
      (do (file-write 2 (string-concat (list "chrt: can't execute '" (first argv) "': " (file-err-text err) "\n")))
          (sys-exit (if (string=? (file-err-text err) "No such file or directory") 127 126))))))

(def %ch-main
  (fn (_ argv)
    (def o (cu-opts "chrt" argv))
    (def policy (%ch-policy o))
    (def args (Opts operands o))
    (match
      ((Opts on? o "-m")
        (do (List map %ch-show-min-max (list 0 1 2 3 5)) 0))
      ((null? args) (%ch-usage))
      ((Opts on? o "-p")
        (let ((prio (if (null? (rest args)) () (first args)))
              (pid (%ch-number (if (null? (rest args)) (first args) (first (rest args)))
                               10 1 2147483647 18446744073709551615)))
          (do (%ch-print pid "current")
              (unless (null? prio)
                (do (%ch-set pid policy prio) (%ch-print pid "new")))
              0)))
      ((null? (rest args)) (%ch-usage))
      (#t (do (%ch-set 0 policy (first args)) (%ch-exec (rest args)))))))

(def cu-chrt
  (fn (_ argv stdin-thunk)
    (guard (e (match ((eq? (cu-err-label e) (lit chrt-usage)) (cu-usage "chrt"))
                     ((eq? (cu-err-label e) (lit chrt)) 1)
                     (#t (error e))))
      (%ch-main argv))))

(provide cu/chrt cu-chrt)

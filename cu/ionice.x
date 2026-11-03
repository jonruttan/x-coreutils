; # x-coreutils -- the small tools, as applets
;
; ## cu/ionice.x -- ionice: a process's I/O scheduling class and priority
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's ionice (util-linux/ionice.c).  Without -c or -n it asks the
; kernel, through ioprio_get, the class and priority of -p's process, of
; the one its first operand numbers, or its own, and prints them.  With
; either it sets them, the class in bits 13 and up, through ioprio_set,
; on -p's process or its own, then becomes PROG.  -t ignores a refusal to
; set.  A platform with neither call, as Darwin is, answers as a kernel
; without them does: Function not implemented.

(module cu/ionice)

(import cu/cli cu-opts)
(import cu/prims bit-and bit-or bit-shl bit-shr cu-err-label cu-int->str
  cu-nth cu-stdin-to-command! file-err-sym file-err-text file-write
  libc-strerror string-append sys-exec-or-err sys-exit)
(import cu/strings cu-range-number)

(def %ion-die
  (fn (_ msg)
    (do (file-write 2 (%str-concat (list "ionice: " msg "\n")))
        (Err raise (lit ionice) msg ()))))

; the system call NAME, or nil where the platform has none
(def %ion-door (fn (_ name) (guard (_ ()) (syscall-door name))))
(def %ion-get (%ion-door (lit ioprio_get)))
(def %ion-set (%ion-door (lit ioprio_set)))

; DOOR made by CALL, answered as (WHY . R): R what it answers, WHY nil, or
; the reason it refused as perror says it after OP
(def %ion-call
  (fn (_ door op call)
    (if (null? door) (pair (string-append op ": Function not implemented") -1)
      (let ((r (call door)))
        (pair (if (< r 0) (%str-concat (list op ": " (libc-strerror (Err errno-of r)))) ()) r)))))

; S as getopt32's + reads a number, xatoi_positive, the run ending if not one
(def %ion-number
  (fn (_ s)
    (let ((n (cu-range-number "ionice" s 0 2147483647)))
      (if (null? n) (Err raise (lit ionice) "number" ()) n))))

(def %ion-num
  (fn (_ o flag)
    (let ((v (Opts value o flag))) (if (null? v) 0 (%ion-number v)))))

(def %ion-classes (list "none" "realtime" "best-effort" "idle"))

; the class and priority of process PID, printed
(def %ion-show
  (fn (_ pid)
    (def got (%ion-call %ion-get "ioprio_get" (fn (_ door) (door 1 pid))))
    (unless (null? (first got)) (%ion-die (first got)))
    (def ioclass (bit-and (bit-shr (rest got) 13) 3))
    (file-write 1 (string-append (cu-nth ioclass %ion-classes)
                                 (if (= ioclass 3) "\n"
                                   (%str-concat (list ": prio " (cu-int->str (bit-and (rest got) 255)) "\n")))))))

; PROG run in place of this process, with busybox's statuses if it cannot be
(def %ion-exec
  (fn (_ prog)
    (do (cu-stdin-to-command!)
        (let ((e (sys-exec-or-err (first prog) (rest prog))))
          (do (file-write 2 (%str-concat (list "ionice: can't execute '" (first prog) "': " (file-err-text e) "\n")))
              (sys-exit (if (eq? (file-err-sym e) (lit enoent)) 127 126)))))))

(def %ion-main
  (fn (_ argv)
    (def o (cu-opts "ionice" argv))
    (def prog (Opts operands o))
    (def pri (%ion-num o "-n"))
    (def ioclass (%ion-num o "-c"))
    (def pid (%ion-num o "-p"))
    (when (> ioclass 3) (%ion-die (string-append "bad class " (cu-int->str ioclass))))
    (if (if (null? (Opts value o "-n")) (null? (Opts value o "-c")) #f)
      (%ion-show (if (if (null? (Opts value o "-p")) (pair? prog) #f) (%ion-number (first prog)) pid))
      (do (def done (%ion-call %ion-set "ioprio_set"
                     (fn (_ door) (door 1 pid (bit-or pri (bit-shl ioclass 13))))))
          (when (if (null? (first done)) #f (not (Opts on? o "-t"))) (%ion-die (first done)))
          (when (pair? prog) (%ion-exec prog))))
    0))

(def cu-ionice
  (fn (_ argv stdin-thunk)
    (guard (e (if (eq? (cu-err-label e) (lit ionice)) 1 (error e)))
      (%ion-main argv))))

(provide cu/ionice cu-ionice)

; # x-coreutils -- the small tools, as applets
;
; ## cu/runparts.x -- run-parts
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's run-parts (debianutils/run_parts.c): the executable files of a
; directory run one after the other in byte order of their names (--reverse
; the other way), each with the -a arguments, under -u's umask.  A name must
; be letters, digits, _ - and ., not starting with a dot; a link counts as
; what it points to, and a directory is passed over.  --test prints the names
; it would run, --list the names whether they may run or not.  A command that
; ends with a status is said and the run goes on, unless --exit-on-error; one
; that will not run is said too.  A directory that will not open is said, and
; is not a failure.
;
; A command that will not run is told from one that ran and failed by a pipe
; closed on exec: the child writes why its exec failed into it, and the
; parent reads nothing there when the exec went through.

(def %rp-c-access ())
(def %rp-c-umask ())

(def %rp-resolve!
  (fn (_)
    (def lib (%cu-dlopen () 1))
    (set! %rp-c-access (%cu-dlsym lib "access"))
    (set! %rp-c-umask (%cu-dlsym lib "umask"))))

; NAME as busybox's invalid_name reads it: letters, digits, _ - and ., and no
; leading dot
(def %rp-valid?
  (fn (_ name)
    (def n (byte-len name))
    (def ok?
      (fn (_ c)
        (match
          ((if (>= c #\0) (<= c #\9) #f) #t)
          ((if (>= (| c 32) #\a) (<= (| c 32) #\z) #f) #t)
          (#t (%dp-in? c "_-.")))))
    (def go (fn (self i) (if (>= i n) #t (if (ok? (byte-at name i)) (self (+ i 1)) #f))))
    (if (= n 0) #f (if (= (byte-at name 0) #\.) #f (go 0)))))

; DIR's entries that run-parts takes, as paths, sorted; or the io Err it
; would not open with.  LIST? takes those it may not run as well.
(def %rp-names
  (fn (_ dir list?)
    (def base (if (if (> (byte-len dir) 0) (= (byte-at dir (- (byte-len dir) 1)) #\/) #f)
                dir (string-append dir "/")))
    (def listed (guard (e e) (file-list-dir dir)))
    (def taken?
      (fn (_ path name)
        ; S_IFREG or S_IFLNK among the mode's type bits, as busybox tests it,
        ; on the file a link points to
        (let ((st (file-stat-full path)))
          (match
            ((null? st) #f)
            ((= (& (& (%cu-stat-get st (lit mode)) 61440) 40960) 0) #f)
            ((not (%rp-valid? name)) #f)
            (list? #t)
            (#t (= (Sys %sign-fold (%cu-ptr-call %rp-c-access path 1)) 0))))))
    (if (Err err? listed) listed
      (%cu-msort
        (map (fn (_ name) (string-append base name))
             (filter (fn (_ name) (taken? (string-append base name) name)) listed))
        %cu-str<))))

; COMMAND run in a child: its status as busybox's wait4pid answers it -- the
; exit status, or 128 and a signal's number -- or the text of why the exec
; failed, which the child writes into a pipe closed on exec
(def %rp-spawn
  (fn (_ command)
    (def p (Sys pipe))
    (def setfd (fn (_ fd) ((syscall-door (lit fcntl)) fd 2 1)))
    (do (setfd (first p))
        (setfd (rest p))
        (let ((pid (sys-fork)))
          (if (= pid 0)
            (do (sys-close (first p))
                (let ((err (sys-exec-or-err (first command) (rest command))))
                  (do (file-write (rest p) (file-err-text err))
                      (sys-exit 127))))
            (do (sys-close (rest p))
                (let ((why (file-read-fd (first p) 256)))
                  (do (sys-close (first p))
                      (let ((st (sys-wait pid)))
                        (if (> (byte-len why) 0) why st))))))))))

; an octal number from 0 to 07777, or nil once said
(def %rp-umask
  (fn (_ s)
    (def r (%hx-strtoul s 0 8 4294967295))
    (match
      ((if (= (byte-len s) 0) #t (if (null? (first r)) #t (not (= (rest r) (byte-len s)))))
        (do (file-write 2 (string-concat (list "run-parts: invalid number '" s "'\n"))) ()))
      ((> (first r) 4095)
        (do (file-write 2 (string-concat (list "run-parts: number " s " is not in 0..4095 range\n"))) ()))
      (#t (first r)))))

; run-parts [-a ARG]... [-u UMASK] [--reverse] [--test] [--exit-on-error] [--list] DIRECTORY
(def %cu-run-parts
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "run-parts" argv))
    (def ops (Opts operands o))
    (def args (append (Opts values o "-a") (Opts values o "--arg")))
    (def u (let ((v (Opts value o "-u"))) (if (null? v) (Opts value o "--umask") v)))
    (def mask (if (null? u) 18 (%rp-umask u)))
    (def list? (Opts on? o "--list"))
    (def show? (if list? #t (Opts on? o "--test")))
    (def each
      (fn (self names st)
        (if (null? names) st
          (if show?
            (do (file-write 1 (string-append (first names) "\n")) (self (rest names) st))
            (let ((r (%rp-spawn (pair (first names) args))))
              (match
                ((eq? (%cu-type-of r) %cu-string-type)
                  (do (file-write 2 (string-concat (list "run-parts: can't execute '" (first names)
                                                         "': " r "\n")))
                      (if (Opts on? o "--exit-on-error") 1 (self (rest names) 1))))
                ((= r 0) (self (rest names) st))
                (#t
                  (do (file-write 2 (string-concat (list "run-parts: " (first names) ": exit status "
                                                         (%cu-int->str r) "\n")))
                      (if (Opts on? o "--exit-on-error") 1 (self (rest names) 1))))))))))
    (match
      ((not (= (length ops) 1)) (%cu-usage "run-parts"))
      ((null? mask) 1)
      (#t
        (do (%rp-resolve!)
            (%cu-ptr-call %rp-c-umask mask)
            (let ((names (%rp-names (first ops) list?)))
              (match
                ; a file that is not a directory has nothing under it
                ((if (Err err? names) (not (null? (file-stat-full (first ops)))) #f) 0)
                ((Err err? names)
                  (do (file-write 2 (string-concat (list "run-parts: " (first ops) ": "
                                                         (file-err-text names) "\n")))
                      0))
                (#t (each (if (Opts on? o "--reverse") (reverse names) names) 0)))))))))

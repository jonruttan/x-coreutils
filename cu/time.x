; # x-coreutils -- the small tools, as applets
;
; ## cu/time.x -- time
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's time (miscutils/time.c): PROG run with its ARGS, and when it
; ends, what it used, on standard error or -o FILE (-a to append).  The
; format is $TIME, or -f FMT, or -v's long one or -p's POSIX one, -p over -v
; over -f; its % conversions are GNU time's -- elapsed, user and system time,
; the CPU share, the resource counts wait4 answers, the exit status -- and \n
; \t \\ its escapes.  An unknown one prints as ?C.  A command that did not
; exit 0 is said first; the status is the command's, or its signal's number.
;
; The child is waited for by libc's wait4, which fills the struct rusage the
; counts come from: two timevals, then fourteen longs, the layout of every
; 64-bit Linux and Darwin.  ru_maxrss is in kilobytes on Linux and in bytes
; on Darwin, and %M prints it as the kernel gives it, as busybox does.

(def %tm-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %tm-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %tm-c-wait4 ())
(def %tm-c-getpagesize ())

(def %tm-resolve!
  (fn (_)
    (def lib (%cu-dlopen () 1))
    (set! %tm-c-wait4 (%cu-dlsym lib "wait4"))
    (set! %tm-c-getpagesize (%cu-dlsym lib "getpagesize"))))

; the K bytes of S from I, a little-endian number
(def %tm-le
  (fn (_ s i k)
    (def go
      (fn (self j acc)
        (if (< j 0) acc (self (- j 1) (+ (* acc 256) (byte-at s (+ i j)))))))
    (go (- k 1) 0)))

; --- the formats ---------------------------------------------------------------

(def %tm-default "real\t%E\nuser\t%u\nsys\t%T")
(def %tm-posix "real %e\nuser %U\nsys %S")
(def %tm-long
  (string-concat
    (list "\tCommand being timed: \"%C\"\n"
          "\tUser time (seconds): %U\n"
          "\tSystem time (seconds): %S\n"
          "\tPercent of CPU this job got: %P\n"
          "\tElapsed (wall clock) time (h:mm:ss or m:ss): %E\n"
          "\tAverage shared text size (kbytes): %X\n"
          "\tAverage unshared data size (kbytes): %D\n"
          "\tAverage stack size (kbytes): %p\n"
          "\tAverage total size (kbytes): %K\n"
          "\tMaximum resident set size (kbytes): %M\n"
          "\tAverage resident set size (kbytes): %t\n"
          "\tMajor (requiring I/O) page faults: %F\n"
          "\tMinor (reclaiming a frame) page faults: %R\n"
          "\tVoluntary context switches: %w\n"
          "\tInvoluntary context switches: %c\n"
          "\tSwaps: %W\n"
          "\tFile system inputs: %I\n"
          "\tFile system outputs: %O\n"
          "\tSocket messages sent: %s\n"
          "\tSocket messages received: %r\n"
          "\tSignals delivered: %k\n"
          "\tPage size (bytes): %Z\n"
          "\tExit status: %x")))

(def %tm-2 (fn (_ n) (%cu-pad-zero (%cu-int->str n) 2)))

; seconds and microseconds as busybox's h:m:s or m:s spells them
(def %tm-hms
  (fn (_ sec usec)
    (if (>= sec 3600)
      (string-concat
        (list (%cu-int->str (%cal/ sec 3600)) "h " (%cu-int->str (%cal/ (% sec 3600) 60)) "m "
              (%tm-2 (% sec 60)) "s"))
      (string-concat
        (list (%cu-int->str (%cal/ sec 60)) "m " (%cu-int->str (% sec 60)) "."
              (%tm-2 (%cal/ usec 10000)) "s")))))

(def %tm-secs
  (fn (_ sec usec) (string-concat (list (%cu-int->str sec) "." (%tm-2 (%cal/ usec 10000))))))

; The record of a run: (STATUS ELAPSED-MS RUSAGE COMMAND), RUSAGE the raw
; struct rusage.  A field of it by name.
(def %tm-ru-longs
  (list (lit maxrss) (lit ixrss) (lit idrss) (lit isrss) (lit minflt) (lit majflt)
        (lit nswap) (lit inblock) (lit oublock) (lit msgsnd) (lit msgrcv)
        (lit nsignals) (lit nvcsw) (lit nivcsw)))

(def %tm-ru
  (fn (_ ru field)
    (def find
      (fn (self l i) (if (eq? (first l) field) i (self (rest l) (+ i 1)))))
    (%tm-le ru (+ 32 (* 8 (find %tm-ru-longs 0))) 8)))

; One conversion C of the format against the run: its text.
(def %tm-conv
  (fn (_ c run)
    (def status (first run))
    (def elapsed (%cu-nth 1 run))
    (def ru (%cu-nth 2 run))
    (def usec (%tm-le ru 0 8))
    (def uusec (%tm-le ru 8 4))
    (def ssec (%tm-le ru 16 8))
    (def susec (%tm-le ru 24 4))
    (def vv (+ (* (+ usec ssec) 1000) (%cal/ (+ uusec susec) 1000)))
    (def ticks (let ((t (%cal/ vv 10))) (if (= t 0) 1 t)))
    (def n (fn (_ f) (%cu-int->str (%tm-ru ru f))))
    (match
      ((= c #\C) (%cu-join-with (%cu-nth 3 run) " "))
      ((= c #\D) (%cu-int->str (%cal/ (+ (%tm-ru ru (lit idrss)) (%tm-ru ru (lit isrss))) ticks)))
      ((= c #\E)
        (let ((sec (%cal/ elapsed 1000)))
          (if (>= sec 3600) (%tm-hms sec 0)
            (string-concat (list (%cu-int->str (%cal/ sec 60)) "m " (%cu-int->str (% sec 60)) "."
                                 (%tm-2 (% (%cal/ elapsed 10) 100)) "s")))))
      ((= c #\F) (n (lit majflt)))
      ((= c #\I) (n (lit inblock)))
      ((= c #\K)
        (%cu-int->str (%cal/ (+ (%tm-ru ru (lit idrss)) (+ (%tm-ru ru (lit isrss)) (%tm-ru ru (lit ixrss))))
                             ticks)))
      ((= c #\M) (n (lit maxrss)))
      ((= c #\O) (n (lit oublock)))
      ((= c #\P) (if (> elapsed 0) (string-append (%cu-int->str (%cal/ (* vv 100) elapsed)) "%") "?%"))
      ((= c #\R) (n (lit minflt)))
      ((= c #\S) (%tm-secs ssec susec))
      ((= c #\T) (%tm-hms ssec susec))
      ((= c #\U) (%tm-secs usec uusec))
      ((= c #\u) (%tm-hms usec uusec))
      ((= c #\W) (n (lit nswap)))
      ((= c #\X) (%cu-int->str (%cal/ (%tm-ru ru (lit ixrss)) ticks)))
      ((= c #\Z) (%cu-int->str (%cu-ptr-call %tm-c-getpagesize)))
      ((= c #\c) (n (lit nivcsw)))
      ((= c #\e) (%tm-secs (%cal/ elapsed 1000) (* (% (%cal/ elapsed 10) 100) 10000)))
      ((= c #\k) (n (lit nsignals)))
      ((= c #\p) (%cu-int->str (%cal/ (%tm-ru ru (lit isrss)) ticks)))
      ((= c #\r) (n (lit msgrcv)))
      ((= c #\s) (n (lit msgsnd)))
      ((= c #\t) (%cu-int->str (%cal/ (%tm-ru ru (lit idrss)) ticks)))
      ((= c #\w) (n (lit nvcsw)))
      ((= c #\x) (%cu-int->str (%tm-exit-of status)))
      ((= c #\%) "%")
      (#t (string-append "?" (bytes->str (list c)))))))

(def %tm-exit-of (fn (_ st) (& (>> st 8) 255)))
(def %tm-signal-of (fn (_ st) (& st 127)))

; busybox's summarize: FMT against the run, the line about how the command
; ended before it.  A trailing % prints ? and no newline; a trailing \ prints
; ?\ and the command's name.
(def %tm-summary
  (fn (_ fmt run)
    (def n (byte-len fmt))
    (def status (first run))
    (def go
      (fn (self i acc)
        (if (>= i n) (reverse (pair "\n" acc))
          (let ((c (byte-at fmt i)) (d (if (< (+ i 1) n) (byte-at fmt (+ i 1)) 0)))
            (match
              ((if (= c #\%) (= d 0) #f) (reverse (pair "?" acc)))
              ((= c #\%) (self (+ i 2) (pair (%tm-conv d run) acc)))
              ((if (= c #\\) (= d 0) #f)
                (reverse (pair "\n" (pair (first (%cu-nth 3 run)) (pair "?\\" acc)))))
              ((= c #\\)
                (self (+ i 2)
                  (pair (match ((= d #\n) "\n") ((= d #\t) "\t") ((= d #\\) "\\")
                               (#t (string-append "?\\" (bytes->str (list d)))))
                        acc)))
              (#t (self (+ i 1) (pair (bytes->str (list c)) acc))))))))
    (string-concat
      (pair (match
              ((not (= (%tm-signal-of status) 0))
                (string-concat (list "Command terminated by signal "
                                     (%cu-int->str (%tm-signal-of status)) "\n")))
              ((not (= (%tm-exit-of status) 0))
                (string-concat (list "Command exited with non-zero status "
                                     (%cu-int->str (%tm-exit-of status)) "\n")))
              (#t ""))
            (go 0 ())))))

; --- running it ------------------------------------------------------------------

(def %tm-now-ms
  (fn (_) (let ((t (Sys time-of-day))) (+ (* (first t) 1000) (%cal/ (rest t) 1000)))))

; COMMAND run: (STATUS ELAPSED-MS RUSAGE COMMAND), STATUS the raw wait status.
; SIGINT and SIGQUIT are ignored while it runs, so they reach it and not time.
(def %tm-run
  (fn (_ command)
    (def t0 (%tm-now-ms))
    (def pid (sys-fork))
    (if (= pid 0)
      ; busybox's BB_EXECVP_or_die: 127 for a command not found, else 126
      (do (cu-stdin-to-command!)
          (let ((why (file-err-text (sys-exec-or-err (first command) (rest command)))))
            (do (file-write 2 (string-concat (list "time: can't execute '" (first command)
                                                   "': " why "\n")))
                (sys-exit (if (string=? why "No such file or directory") 127 126)))))
      (let ((st (%str-make-raw 4)) (ru (%str-make-raw 144)))
        (def wait
          (fn (self)
            (let ((r (Sys %sign-fold (%cu-ptr-call %tm-c-wait4 pid (%tm-ptr->int (%tm-str->ptr st)) 0
                                       (%tm-ptr->int (%tm-str->ptr ru))))))
              (if (if (< r 0) (not (= r pid)) #f) (self) r))))
        (do (sys-signal 2 (Sys sig-ign))
            (sys-signal 3 (Sys sig-ign))
            (wait)
            (sys-signal 2 (Sys sig-dfl))
            (sys-signal 3 (Sys sig-dfl))
            (list (%tm-le st 0 4) (- (%tm-now-ms) t0) ru command))))))

(def %tm-usage
  (fn (_)
    (do (file-write 2
          (string-concat
            (list "Usage: time [-vpa] [-o FILE] PROG ARGS\n\n"
                  "Run PROG, display resource usage when it exits\n\n"
                  "\t-v\tVerbose\n"
                  "\t-p\tPOSIX output format\n"
                  "\t-f FMT\tCustom format\n"
                  "\t-o FILE\tWrite result to FILE\n"
                  "\t-a\tAppend (else overwrite)\n")))
        1)))

; time [-vpa] [-o FILE] [-f FMT] PROG ARGS
(def %cu-time
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "time" argv))
    (def command (Opts operands o))
    (def env (sys-getenv "TIME"))
    (def fmt
      (match
        ((Opts on? o "-p") %tm-posix)
        ((Opts on? o "-v") %tm-long)
        ((not (null? (Opts value o "-f"))) (Opts value o "-f"))
        ((null? env) %tm-default)
        (#t env)))
    (def out-name (Opts value o "-o"))
    (def out
      (if (null? out-name) 2
        (file-open-or-err
          (fn (_ p) (File open p (if (Opts on? o "-a") (list (lit wronly) (lit creat) (lit append))
                                   (list (lit wronly) (lit creat) (lit trunc)))
                      438))
          out-name)))
    (match
      ((null? command) (%tm-usage))
      ((Err err? out)
        (do (file-write 2 (string-concat (list "time: can't open '" out-name "': "
                                               (file-err-text out) "\n")))
            1))
      (#t
        (do (%tm-resolve!)
            (let ((run (%tm-run command)))
              (do (file-write out (%tm-summary fmt run))
                  (if (= out 2) () (file-close out))
                  (if (= (%tm-signal-of (first run)) 0)
                    (%tm-exit-of (first run))
                    (%tm-signal-of (first run))))))))))

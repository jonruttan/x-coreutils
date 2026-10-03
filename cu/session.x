; # x-coreutils -- the small tools, as applets
;
; ## cu/session.x -- fsync, flock, setsid, ttysize, nologin, pipe_progress
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Six of busybox's small ones over the system's own calls.  fsync
; (coreutils/sync.c) flushes each file to disk, -d its data alone.  flock
; (util-linux/flock.c) locks a file and runs a command holding the lock, or
; locks or unlocks a descriptor.  setsid (util-linux/setsid.c) runs a
; command in a new session.  ttysize (miscutils/ttysize.c) prints the
; terminal's size, 80 by 24 off one.  nologin (util-linux/nologin, a script)
; refuses a login politely, slowly.  pipe_progress (debianutils) copies its
; input to its output and puts a dot on stderr each second it takes.
;
; flock, setsid and fdatasync are libc's, through the FFI; the ioctl that
; makes setsid -c's terminal the controlling one is a system call, as ioctl
; must be (its third argument is variadic).

(import x/repl/term)

(def %ss-c-flock ())
(def %ss-c-setsid ())
(def %ss-c-fdatasync ())

(def %ss-resolve!
  (fn (_)
    (def lib (%cu-dlopen () 1))
    (set! %ss-c-flock (%cu-dlsym lib "flock"))
    (set! %ss-c-setsid (%cu-dlsym lib "setsid"))
    (set! %ss-c-fdatasync (%cu-dlsym lib "fdatasync"))))

; a libc call's result, and the io Err it failed with as OP on NAME, or nil
(def %ss-call
  (fn (_ r op name)
    (let ((n (Sys %sign-fold r)))
      (if (< n 0) (Err from-errno (Err errno-of n) op name) ()))))

; COMMAND run in a child: its exit status, or 128 and the signal's number.
; A command that will not run is said by the child, as BB_EXECVP_or_die says
; it under APPLET, and the child ends with FAILED.
(def %ss-run
  (fn (_ applet command failed)
    (def pid (sys-fork))
    (if (= pid 0)
      (do (cu-stdin-to-command!)
          (let ((err (sys-exec-or-err (first command) (rest command))))
            (do (file-write 2 (string-concat (list applet ": " (first command) ": "
                                                   (file-err-text err) "\n")))
                (sys-exit failed))))
      (sys-wait pid))))

; --- fsync ---------------------------------------------------------------------

(def %fsync-usage
  (fn (_)
    (do (file-write 2 "Usage: fsync [-d] FILE...\n\nWrite all buffered blocks in FILEs to disk\n\n\t-d\tAvoid syncing metadata\n")
        1)))

; fsync [-d] FILE...: each opened to read, without waiting on it, and flushed
(def %cu-fsync
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "fsync" argv))
    (def data? (Opts on? o "-d"))
    (def one
      (fn (_ name)
        (let ((fd (File open name (list (lit rdonly) (lit nonblock) (lit noctty)))))
          (if (< fd 0)
            (do (file-write 2 (string-concat
                                (list "fsync: can't open '" name "': "
                                      (file-err-text (file-open-err fd name)) "\n")))
                1)
            (let ((err (if (if data? (not (null? %ss-c-fdatasync)) #f)
                         (%ss-call (%cu-ptr-call %ss-c-fdatasync fd) (lit fdatasync) name)
                         (if (< (sys-fsync fd) 0)
                           (Err from-errno (Err errno-of -1) (lit fsync) name) ()))))
              (do (file-close fd)
                  (if (null? err) 0
                    (do (file-write 2 (string-concat (list "fsync: " name ": "
                                                           (file-err-text err) "\n")))
                        1))))))))
    (def each
      (fn (self names st)
        (if (null? names) st
          (self (rest names) (if (= (one (first names)) 0) st 1)))))
    (if (null? (Opts operands o)) (%fsync-usage)
      (do (%ss-resolve!) (each (Opts operands o) 0)))))

; --- flock -----------------------------------------------------------------------

(def %flock-usage
  (fn (_)
    (do (file-write 2
          (string-concat
            (list "Usage: flock [-sxun] FD | { FILE [-c] PROG ARGS }\n\n"
                  "[Un]lock file descriptor, or lock FILE, run PROG\n\n"
                  "\t-s\tShared lock\n"
                  "\t-x\tExclusive lock (default)\n"
                  "\t-u\tUnlock FD\n"
                  "\t-n\tFail rather than wait\n")))
        1)))

; the flock(2) operation the options ask for: LOCK_SH 1, LOCK_EX 2, LOCK_NB
; 4, LOCK_UN 8 -- the same numbers on Linux and Darwin -- -u over -s over the
; exclusive default
(def %flock-mode
  (fn (_ o)
    (def on (fn (_ short long) (if (Opts on? o short) #t (Opts on? o long))))
    (+ (match ((on "-u" "--unlock") 8) ((on "-s" "--shared") 1) (#t 2))
       (if (on "-n" "--nonblock") 4 0))))

; FILE opened to be locked: created if it is not there, a directory read
(def %flock-open
  (fn (_ name)
    (let ((fd (File open name (list (lit rdonly) (lit noctty) (lit creat)) 438)))
      (if (>= fd 0) fd
        (let ((err (file-open-err fd name)))
          (if (string=? (file-err-text err) "Is a directory")
            (let ((fd2 (File open name (list (lit rdonly) (lit noctty)))))
              (if (>= fd2 0) fd2 (file-open-err fd2 name)))
            err))))))

; the shell flock -c runs a command with: $SHELL, or /bin/sh
(def %flock-shell
  (fn (_) (let ((s (sys-getenv "SHELL"))) (if (if (null? s) #t (= (byte-len s) 0)) "/bin/sh" s))))

; flock [-sxun] FD | { FILE [-c] PROG ARGS }
(def %cu-flock
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "flock" argv))
    (def ops (Opts operands o))
    (def cmd (if (pair? ops) (rest ops) ()))
    (def c? (if (pair? cmd) (if (string=? (first cmd) "-c") #t (string=? (first cmd) "--command")) #f))
    (def target
      (match
        ((null? ops) ())
        ((pair? cmd) (%flock-open (first ops)))
        (#t (%cu-range-number "flock" (first ops) 0 2147483647))))
    (match
      ((null? ops) (%flock-usage))
      ((null? target) 1)
      ((Err err? target)
        (do (file-write 2 (string-concat (list "flock: can't open '" (first ops) "': "
                                               (file-err-text target) "\n")))
            1))
      ((if c? (> (length cmd) 2) #f)
        (do (file-write 2 "flock: -c takes only one argument\n") 1))
      (#t
        (do (%ss-resolve!)
            (let ((err (%ss-call (%cu-ptr-call %ss-c-flock target (%flock-mode o)) (lit flock) "")))
              (match
                ((null? err)
                  (match
                    ((null? cmd) 0)
                    ; the lock goes with the file's descriptor, closed when
                    ; the command ends, as busybox's goes when it exits
                    (#t (let ((st (if c? (%ss-run "flock" (list (%flock-shell) "-c" (first (rest cmd))) 255)
                                    (%ss-run "flock" cmd 255))))
                          (do (file-close target) st)))))
                ; the lock is taken elsewhere, under -n: no word, status 1
                ((string=? (file-err-text err) "Resource temporarily unavailable") 1)
                (#t (do (file-write 2 (string-concat (list "flock: : " (file-err-text err) "\n")))
                        1)))))))))

; --- setsid ----------------------------------------------------------------------

(def %setsid-usage
  (fn (_)
    (do (file-write 2
          (string-concat
            (list "Usage: setsid [-c] PROG ARGS\n\n"
                  "Run PROG in a new session. PROG will have no controlling terminal\n"
                  "and will not be affected by keyboard signals (^C etc).\n\n"
                  "\t-c\tSet controlling terminal to stdin\n")))
        1)))

; TIOCSCTTY, the request that makes a terminal the session's
(def %setsid-tiocsctty (if os-darwin? 536900705 21518))

; setsid [-c] PROG ARGS.  A process group's leader cannot start a session,
; so where setsid fails it forks, the parent ending at once with 0 and the
; child starting the session.  Then PROG replaces it.
(def %cu-setsid
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "setsid" argv))
    (def command (Opts operands o))
    (def exec!
      (fn (_)
        (do (if (Opts on? o "-c") ((syscall-door (lit ioctl)) 0 %setsid-tiocsctty 1) ())
            (cu-stdin-to-command!)
            (let ((err (sys-exec-or-err (first command) (rest command))))
              (do (file-write 2 (string-concat (list "setsid: can't execute '" (first command)
                                                     "': " (file-err-text err) "\n")))
                  (sys-exit (if (string=? (file-err-text err) "No such file or directory")
                              127 126)))))))
    (if (null? command) (%setsid-usage)
      (do (%ss-resolve!)
          (if (>= (Sys %sign-fold (%cu-ptr-call %ss-c-setsid)) 0) (exec!)
            (if (= (sys-fork) 0)
              (do (%cu-ptr-call %ss-c-setsid) (exec!))
              0))))))

; --- ttysize, nologin, pipe_progress ---------------------------------------------

; ttysize [w] [h]: the size of the first of standard input, output and error
; that is a terminal, or 80 by 24; with operands, each starting w or h its
; number, and the rest nothing
(def %cu-ttysize
  (fn (_ argv stdin-thunk)
    (def m (let ((a (Term measure 0)))
             (if (pair? a) a
               (let ((b (Term measure 1))) (if (pair? b) b (Term measure 2))))))
    (def w (if (pair? m) (first m) 80))
    (def h (if (pair? m) (rest m) 24))
    (def go
      (fn (self args sep acc)
        (if (null? args) (reverse acc)
          (let ((c (if (> (byte-len (first args)) 0) (byte-at (first args) 0) 0)))
            (self (rest args) " "
              (match
                ((= c #\w) (pair (string-append sep (%cu-int->str w)) acc))
                ((= c #\h) (pair (string-append sep (%cu-int->str h)) acc))
                (#t acc)))))))
    (do (file-write 1
          (string-concat
            (append (if (null? argv) (list (%cu-int->str w) " " (%cu-int->str h)) (go argv "" ()))
                    (list "\n"))))
        0)))

; busybox's nologin script: /etc/nologin.txt, or the polite line; five
; seconds; and 1
(def %cu-nologin
  (fn (_ argv stdin-thunk)
    (do (file-write 1 (if (file-exists? "/etc/nologin.txt") (file-read-all "/etc/nologin.txt")
                        "This account is not available\n"))
        (sys-usleep 5000000)
        1)))

; pipe_progress: standard input to standard output a piece at a time, a dot
; on stderr each time the second has changed since the last, and a newline
; at the end
(def %cu-pipe-progress
  (fn (_ argv stdin-thunk)
    (def src (%cu-pieces "-" stdin-thunk))
    (def go
      (fn (self t)
        (let ((p (src)))
          (if (if (Err err? p) #t (= (rest p) 0)) ()
            (let ((now (Sys now)))
              (do (if (= now t) () (file-write 2 "."))
                  (file-write-run 1 p)
                  (self now)))))))
    (do (go (Sys now))
        (file-write 2 "\n")
        0)))

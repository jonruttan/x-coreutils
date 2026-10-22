; # x-coreutils -- the small tools, as applets
;
; ## cu/popmaildir.x -- popmaildir: a POP3 mailbox fetched into a maildir
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; mailutils/popmaildir.c: the user and password are stdin's first two lines
; (asked for when stdin is a terminal) unless -s; then into MAILDIR, the
; server on stdin and stdout, or on a pair of pipes to the connection helper
; PROG ARGS.  USER and PASS, or APOP with -a when the greeting is "+OK
; <stamp>"; STAT, then each message from the last to the first by RETR (TOP
; with -T, -H's count of lines) written to tmp/, DELE'd unless -k, and moved
; to new/.  -F or -M PROG (the last given) takes each message on its stdin
; instead, $FILENAME naming the file it would have been, and the message stays
; on the server.  A reply not "+" ends the run, "COMMAND failed, reply was:
; REPLY".  -b -d -m -V -c -R -Z and -L are taken and ignored.

(module cu/popmaildir)

(import cu/cli cu-opts cu-usage)
(import cu/prims append byte-at byte-len cu-int->str cu-ptr-ref cu-str->ptr
  file-close file-read-run file-rename file-write map reverse set-first!
  string-append string-concat string=? substring sys-close sys-dup2 sys-exit
  sys-fork sys-getpid sys-isatty sys-pipe sys-poll sys-setenv sys-signal
  sys-uname sys-wait)

(def %pm-wr 1)                  ; the server, written
(def %pm-rd 0)                  ; the server, polled for -t
(def %pm-timeout 0)
(def %pm-alarm? #f)             ; a reply is awaited

(def %pm-die (fn (_ msg) (Err raise (lit net) msg ())))

; --- the server's side ------------------------------------------------------------

; THUNK as stdin's source, -t's seconds without a byte ending the run while a
; reply is awaited
(def %pm-source
  (fn (_ thunk)
    (fn (_ k)
      (when (if %pm-alarm? (> %pm-timeout 0) #f)
        (when (null? (sys-poll (list (pair %pm-rd (list (lit in)))) (* 1000 %pm-timeout)))
          (%pm-die "timed out")))
      (thunk k))))

; xmalloc_fgetline: the next line without its newline, or nil at the end
(def %pm-getline
  (fn (_)
    (let go ((acc ()))
      (let ((c (%mm-getc)))
        (match ((null? c) (if (null? acc) () (bytes->str (reverse acc))))
               ((= c #\newline) (bytes->str (reverse acc)))
               (#t (go (pair c acc))))))))

; xmalloc_fgets_str with "\r\n": the next line with its CR LF -- a bare LF
; ends nothing -- or nil at the end
(def %pm-get-crlf
  (fn (_)
    (let go ((acc ()))
      (let ((c (%mm-getc)))
        (match ((null? c) (if (null? acc) () (bytes->str (reverse acc))))
               ((if (= c #\newline) (if (pair? acc) (= (first acc) #\return) #f) #f) (bytes->str (reverse (pair c acc))))
               (#t (go (pair c acc))))))))

(def %pm-send (fn (_ s) (guard (_ ()) (file-write %pm-wr (string-append s "\r\n")))))

; what busybox's memmove(answer, answer + 4, strlen - 4) leaves, the
; terminator not moved: the reply past "+OK ", then its last four bytes again
(def %pm-skip4
  (fn (_ a)
    (let ((n (byte-len a)))
      (if (< n 4) "" (string-append (substring a 4 n) (substring a (- n 4) n))))))

; pop3_checkr: MSG sent (nil sends nothing), then the reply, or the run ends
(def %pm-check
  (fn (_ msg)
    (unless (null? msg) (%pm-send msg))
    (set! %pm-alarm? #t)
    (def answer (%pm-getline))
    (set! %pm-alarm? #f)
    (if (match ((null? answer) #f) ((= (byte-len answer) 0) #f) (#t (= (byte-at answer 0) #\+)))
      (%pm-skip4 answer)
      (do (%sm-helper-check)
          (%pm-die (string-concat (list (if (null? msg) "(null)" msg) " failed, reply was: " (if (null? answer) "(null)" answer))))))))

; atoi: the leading number of S, past spaces and a plus
(def %pm-atoi
  (fn (_ s)
    (def n (byte-len s))
    (def i (let go ((i 0)) (if (if (< i n) (%sm-space? (byte-at s i)) #f) (go (+ i 1)) i)))
    (%sm-atoi (substring s (if (if (< i n) (= (byte-at s i) #\+) #f) (+ i 1) i) n))))

; --- the login --------------------------------------------------------------------

; bb_ask_noecho: PROMPT, then a line read with the echo off
(def %pm-ask
  (fn (_ prompt)
    (file-write 1 prompt)
    (def saved (Term raw-with-signals! 0))
    (def line
      (let go ((acc ()))
        (let ((r (guard (_ (pair "" 0)) (file-read-run 0 1))))
          (def b (if (= (rest r) 0) () (cu-ptr-ref (cu-str->ptr (first r)) 0 1)))
          (match ((null? b) (if (null? acc) () (bytes->str (reverse acc))))
                 ((%wget-memv b (list #\newline #\return)) (bytes->str (reverse acc)))
                 ((%wget-memv b (list 8 127)) (go (if (null? acc) acc (rest acc))))
                 (#t (go (pair b acc)))))))
    (Term restore! 0 saved)
    (file-write 1 "\n")
    line))

; get_cred_or_die: (USER . PASSWORD)
(def %pm-cred
  (fn (_)
    (def tty? (sys-isatty 0))
    (def u (if tty? (%pm-ask "User: ") (%pm-getline)))
    (def p (if tty? (%pm-ask "Password: ") (%pm-getline)))
    (if (match ((null? u) #t) ((= (byte-len u) 0) #t) (#t (null? p)))
      (%pm-die "no username or password")
      (pair u p))))

; APOP when asked for and the greeting BUF holds a stamp, else USER and PASS
(def %pm-login!
  (fn (_ buf cred apop?)
    (if (match ((not apop?) #f) ((= (byte-len buf) 0) #f) (#t (= (byte-at buf 0) #\<)))
      (let ((gt (%wget-index buf #\> 0)))
        (let ((stamp (if (null? gt) buf (substring buf 0 (+ gt 1)))))
          (%pm-check (string-concat (list "APOP " (first cred) " " (cu-md5 (string-append stamp (rest cred))))))))
      (do (%pm-check (string-append "USER " (first cred)))
          (%pm-check (string-append "PASS " (rest cred)))))))

; --- the connection helper and the delivery program ---------------------------------

; launch_helper: ARGV on a pair of pipes, its stdout read as the server
(def %pm-helper!
  (fn (_ argv)
    (def to (sys-pipe))
    (def from (sys-pipe))
    (def pid (sys-fork))
    (when (= pid 0)
      (do (sys-close (rest to)) (sys-close (first from))
          (sys-dup2 (first to) 0) (sys-dup2 (rest from) 1)
          (sys-close (first to)) (sys-close (rest from)) (sys-close 3)
          (let ((r (in-exec (first argv) argv)))
            (do (file-write 2 (string-concat (list "popmaildir: can't execute '" (first argv) "': " (in-errtext r) "\n")))
                (sys-exit 127)))))
    (sys-close (first to))
    (sys-close (rest from))
    (set! %sm-helper pid)
    (set! %pm-rd (first from))
    (set! %pm-wr (rest to))
    (set! %mm-thunk (%pm-source (fn (_ k) (guard (_ (pair "" 0)) (file-read-run %pm-rd 4096)))))
    (set-first! %mm-in ())))

; popen(PROG, "w"): sh -c PROG on a pipe, $FILENAME set, its stdout the
; server's as busybox's is; (FD . PID)
(def %pm-deliver
  (fn (_ prog filename)
    (def p (sys-pipe))
    (def pid (sys-fork))
    (when (= pid 0)
      (do (sys-close (rest p))
          (sys-dup2 (first p) 0)
          (sys-close (first p))
          (unless (= %pm-wr 1) (sys-dup2 %pm-wr 1))
          (sys-setenv "FILENAME" filename)
          (sys-signal 13 0)
          (let ((r (in-exec "sh" (list "sh" "-c" prog))))
            (do (file-write 2 (string-concat (list "popmaildir: can't execute 'sh': " (in-errtext r) "\n")))
                (sys-exit 127)))))
    (sys-close (first p))
    (pair (rest p) pid)))

; --- the messages -------------------------------------------------------------------

; the message to FD up to its lone dot, the first of a leading pair of dots
; dropped
(def %pm-copy
  (fn (_ fd)
    (let go ()
      (let ((l (%pm-get-crlf)))
        (unless (if (null? l) #t (string=? l ".\r\n"))
          (do (guard (_ ()) (file-write fd (if (Str8 starts? ".." l) (substring l 1 (byte-len l)) l)))
              (go)))))))

; tmp/NAME to new/NAME: #f, said, when the move fails
(def %pm-move
  (fn (_ name)
    (def target (string-append "new" (substring name 3 (byte-len name))))
    (def r (guard (e e) (file-rename name target)))
    (def why (match ((Err err? r) (%wget-err-text r))
                    ((not (number? r)) ())
                    ((< r 0) (tar-why (lit rename) name))
                    (#t ())))
    (if (null? why) #t
      (do (file-write 2 (string-concat (list "popmaildir: can't move '" name "' to '" target "': " why "\n")))
          #f))))

; message K fetched by the command RETR makes of it, to tmp/NAME or to
; DELIVERY; DELE unless KEEP?, then new/NAME.  #f stops the run.
(def %pm-fetch
  (fn (_ k retr delivery keep? suffix)
    (def name (string-concat (list "tmp/" (let ((t (si-now))) (cu-int->str (+ (* (first t) 1000000) (rest t)))) suffix)))
    (%pm-check (retr k))
    (if (not (null? delivery))
      ; busybox skips DELE and the move whatever the program answers
      (let ((d (%pm-deliver delivery name)))
        (do (%pm-copy (first d)) (sys-close (first d)) (sys-wait (rest d)) #t))
      (let ((fd (let ((r (guard (e e) (File open name (list (lit wronly) (lit creat) (lit trunc)) 438))))
                  (match ((Err err? r) (%pm-die (string-concat (list "can't open '" name "': " (%wget-err-text r)))))
                         ((< r 0) (%pm-die (string-concat (list "can't open '" name "': " (tar-why (lit open) name)))))
                         (#t r)))))
        (do (%pm-copy fd)
            (file-close fd)
            (unless keep? (%pm-check (string-append "DELE " (cu-int->str k))))
            (%pm-move name))))))

; --- the applet ----------------------------------------------------------------------

(def cu-popmaildir
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "popmaildir" argv))
    (def ops (Opts operands o))
    (if (null? ops) (cu-usage "popmaildir")
      (guard (e (if (eq? (Err label e) (lit net))
                  (do (file-write 2 (string-concat (list "popmaildir: " (e msg) "\n"))) 1)
                  (error e)))
        (%pm-main o ops stdin-thunk)))))

(def %pm-main
  (fn (_ o ops stdin-thunk)
    (set! %pm-timeout (let ((t (Opts value o "-t"))) (if (null? t) 0 (in-count t))))
    (map in-count (append (Opts values o "-R") (Opts values o "-L")))
    (def lines (let ((h (Opts value o "-H"))) (if (null? h) 0 (in-count h))))
    ; -M and -F are one: the last given of either
    (def delivery (List fold (fn (_ acc e) (if (if (string=? (first e) "-F") #t (string=? (first e) "-M")) (rest e) acc))
                    () (rest (Assoc entry (lit values) o))))
    (set! %pm-wr 1)
    (set! %pm-rd 0)
    (set! %pm-alarm? #f)
    (set! %sm-helper -1)
    (set! %mm-thunk (%pm-source stdin-thunk))
    (set-first! %mm-in ())
    (def cred (if (Opts on? o "-s") () (%pm-cred)))
    (when (< (Sys chdir (first ops)) 0)
      (%pm-die (string-concat (list "can't change directory to '" (first ops) "': " (tar-why (lit chdir) (first ops))))))
    (unless (null? (rest ops)) (%pm-helper! (rest ops)))
    (def greeting (%pm-check ()))
    (unless (Opts on? o "-s") (%pm-login! greeting cred (Opts on? o "-a")))
    (def n (%pm-atoi (%pm-check "STAT")))
    (def suffix (string-concat (list "." (cu-int->str (sys-getpid)) "." (cu-uname-field (sys-uname) (lit nodename)))))
    (def retr (if (Opts on? o "-T")
                (fn (_ k) (string-concat (list "TOP " (cu-int->str k) " " (cu-int->str lines))))
                (fn (_ k) (string-append "RETR " (cu-int->str k)))))
    (let go ((k n))
      (when (> k 0)
        (when (%pm-fetch k retr delivery (Opts on? o "-k") suffix) (go (- k 1)))))
    (%pm-check "QUIT")
    0))

(provide cu/popmaildir cu-popmaildir)

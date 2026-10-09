; # x-coreutils -- the small tools, as applets
;
; ## cu/tcpsvd.x -- tcpsvd and udpsvd: a program run for each connection
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; networking/tcpudp.c: a socket bound to IP:PORT, and PROG run in a child for
; each connection -- for udpsvd, each new sender -- with the connection its
; stdin and stdout and, unless -E, PROTO and the PROTO-prefixed LOCALADDR,
; REMOTEADDR (and with -h LOCALHOST, REMOTEHOST) in its environment.
;
; busybox reaps its children in a SIGCHLD handler that interrupts accept; here
; SIGCHLD is caught, which interrupts the poll the listener is waited on, and
; the ended children are taken with a waitpid that does not wait.  The parent
; goes on once the child has run PROG or ended -- vfork's order, so a start
; line or a can't-execute comes before the status line -- read from a pipe
; whose write end closes on exec.  The fatal signals end the run as
; busybox's handler ends it: -v says so, and the signal is sent again with its
; default action.

(def %ts-app "tcpsvd")
(def %ts-tcp #t)
(def %ts-verbose 0)
(def %ts-cnum 0)
(def %ts-cmax 30)
(def %ts-hosts ())            ; -C: (PID . IP) for each running child
(def %ts-libc ())
; fcntl is a system call here, not libc's: its third argument is variadic
(def %ts-fcntl (syscall-door (lit fcntl)))

(def %ts-die (fn (_ msg) (Err raise (lit net) msg ())))

(def %ts-say
  (fn (_ msg) (file-write 2 (string-concat (list %ts-app ": " msg "\n")))))

(def %ts-c
  (fn (_ name)
    (when (null? %ts-libc) (set! %ts-libc (%cu-dlopen () 1)))
    (%cu-dlsym %ts-libc name)))

; a libc call's result folded to a signed int, as the platform folds its own
(def %ts-call (fn (_ r) (Sys %sign-fold r)))

; --- numbers and addresses ----------------------------------------------------

; xatou: S as a count, or the run ends naming it
(def %ts-count
  (fn (_ s)
    (let ((n (%wget-digits s)))
      (if (null? n) (%ts-die (string-concat (list "invalid number '" s "'"))) n))))

; the decimal digits S starts with: (N . END)
(def %ts-leading
  (fn (_ s)
    (let go ((j 0) (n 0))
      (if (if (< j (byte-len s)) (if (>= (byte-at s j) #\0) (<= (byte-at s j) #\9) #f) #f)
        (go (+ j 1) (+ (* n 10) (- (byte-at s j) #\0)))
        (pair n j)))))

; bb_lookup_port: digits up to 65535, else a service's port for the protocol
(def %ts-port
  (fn (_ s)
    (def n (%wget-digits s))
    (if (if (null? n) #f (<= n 65535)) n
      (let ((sv (%cu-ptr-call (%ts-c "getservbyname") s (if %ts-tcp "tcp" "udp"))))
        (if (= sv 0) (%ts-die (string-concat (list "bad port '" s "'")))
          (let ((p (%cu-ptr-ref (%cu-int->ptr sv) 16 4)))
            (+ (* (% p 256) 256) (% (%wget-div p 256) 256))))))))

; a zeroed sockaddr_in for QUAD:PORT -- Darwin leads with its length byte and a
; one-byte family, Linux with a two-byte family; the port and address are in
; network order on both
(def %ts-sockaddr
  (fn (_ quad port)
    (def s (%str-make-raw 16))
    (def p (%cu-str->ptr s))
    (let go ((i 0)) (when (< i 16) (do (%cu-ptr-set! p i 0 1) (go (+ i 1)))))
    (if os-darwin? (do (%cu-ptr-set! p 0 16 1) (%cu-ptr-set! p 1 2 1)) (%cu-ptr-set! p 0 2 1))
    (%cu-ptr-set! p 2 (%wget-div port 256) 1)
    (%cu-ptr-set! p 3 (% port 256) 1)
    (let go ((i 0) (parts (Str8 split "." quad)))
      (unless (null? parts)
        (do (%cu-ptr-set! p (+ 4 i) (%wget-digits (first parts)) 1) (go (+ i 1) (rest parts)))))
    s))

; a sockaddr_in's (QUAD . PORT)
(def %ts-sockaddr-read
  (fn (_ s)
    (def b (fn (_ i) (byte-at s i)))
    (pair (string-concat (list (%cu-int->str (b 4)) "." (%cu-int->str (b 5)) "."
                               (%cu-int->str (b 6)) "." (%cu-int->str (b 7))))
          (+ (* (b 2) 256) (b 3)))))

; a length cell for a sockaddr, 16
(def %ts-len16
  (fn (_)
    (let ((s (%str-make-raw 4)))
      (do (%cu-ptr-set! (%cu-str->ptr s) 0 16 4) s))))

; FD's own address, through getsockname
(def %ts-local
  (fn (_ fd)
    (def sa (%ts-sockaddr "0.0.0.0" 0))
    (%cu-ptr-call (%ts-c "getsockname") fd (%cu-str->ptr sa) (%cu-str->ptr (%ts-len16)))
    (%ts-sockaddr-read sa)))

(def %ts-dotted (fn (_ a) (string-concat (list (first a) ":" (%cu-int->str (rest a))))))

; gethostbyaddr's name for QUAD, or nil
(def %ts-host-name
  (fn (_ quad)
    (def buf (%str-make-raw 4))
    (let go ((i 0) (parts (Str8 split "." quad)))
      (unless (null? parts)
        (do (%cu-ptr-set! (%cu-str->ptr buf) i (%wget-digits (first parts)) 1) (go (+ i 1) (rest parts)))))
    (def r (%cu-ptr-call (%ts-c "gethostbyaddr") (%cu-str->ptr buf) 4 2))
    (if (= r 0) () (%cu-ptr->str (%cu-int->ptr (%cu-ptr-word (%cu-int->ptr r) 0))))))

; --- the sockets ----------------------------------------------------------------

; xsocket + setsockopt_reuseaddr + xbind for UDP: Darwin lets a second socket
; bind the same address and port only with SO_REUSEPORT as well
(def %ts-udp-bind
  (fn (_ quad port)
    (def fd (%ts-call (%cu-ptr-call (%ts-c "socket") 2 2 0)))
    (when (< fd 0) (%ts-die "socket: can't create"))
    (def one (%str-make-raw 4))
    (%cu-ptr-set! (%cu-str->ptr one) 0 1 4)
    (def sol (if os-darwin? 65535 1))
    (%cu-ptr-call (%ts-c "setsockopt") fd sol (if os-darwin? 4 2) (%cu-str->ptr one) 4)
    (when os-darwin? (%cu-ptr-call (%ts-c "setsockopt") fd sol 512 (%cu-str->ptr one) 4))
    (def r (%ts-call (%cu-ptr-call (%ts-c "bind") fd (%cu-str->ptr (%ts-sockaddr quad port)) 16)))
    (when (< r 0)
      (%ts-die (string-append "bind: " (file-err-text (Err from-errno (Err errno-of r) (lit bind) ())))))
    fd))

; the next datagram's sender, left in the queue for the child to read
(def %ts-udp-peek
  (fn (_ fd)
    (def sa (%ts-sockaddr "0.0.0.0" 0))
    (def buf (%str-make-raw 4))
    (def r (%ts-call (%cu-ptr-call (%ts-c "recvfrom") fd (%cu-str->ptr buf) 1 2
                                   (%cu-str->ptr sa) (%cu-str->ptr (%ts-len16)))))
    (if (< r 0) () (%ts-sockaddr-read sa))))

(def %ts-listen
  (fn (_ quad port backlog)
    (guard (e (if (eq? (Err label e) (lit io)) (%ts-die (string-append "bind: " (%wget-err-text e))) (error e)))
      (if %ts-tcp (Socket tcp-listen-on quad port backlog) (%ts-udp-bind quad port)))))

; -u: xsetgid then xsetuid, the supplementary groups left as they are
(def %ts-drop!
  (fn (_ ug)
    (def fail? (fn (_ r sym)
      (let ((e (%ss-call r (lit call) sym)))
        (unless (null? e) (%ts-die (string-concat (list sym ": " (file-err-text e))))))))
    (fail? (%cu-ptr-call (%ts-c "setgid") (rest ug)) "setgid")
    (fail? (%cu-ptr-call (%ts-c "setuid") (first ug)) "setuid")))

; --- the children ---------------------------------------------------------------

(def %ts-signal-number
  (fn (_ name)
    (let ((e (List find (fn (_ e) (string=? (first e) name)) (sys-signals)))) (if (null? e) () (rest e)))))

; BB_FATAL_SIGS, by number, those this kernel has
(def %ts-fatal
  (fn (_)
    (filter (fn (_ n) (not (null? n)))
      (map %ts-signal-number (list "TERM" "HUP" "INT" "QUIT" "ABRT" "ALRM" "VTALRM" "XCPU" "XFSZ" "USR1" "USR2")))))

; print_waitstat and the bookkeeping for each child that has ended
(def %ts-reap!
  (fn (self)
    (def st (%str-make-raw 4))
    (def pid (%ts-call (%cu-ptr-call (%ts-c "waitpid") -1 (%cu-str->ptr st) 1)))
    (when (> pid 0)
      (do (%ts-ended pid (%cu-ptr-ref (%cu-str->ptr st) 0 4))
          (self)))))

; one child ended with wait status RAW
(def %ts-ended
  (fn (_ pid raw)
    (set! %ts-hosts (filter (fn (_ h) (not (= (first h) pid))) %ts-hosts))
    (when (> %ts-cnum 0) (set! %ts-cnum (- %ts-cnum 1)))
    (when (> %ts-verbose 0)
      (%ts-say (string-concat (list "end " (%cu-int->str pid) " "
        (if (= (% raw 128) 0)
          (string-append "exit " (%cu-int->str (% (%wget-div raw 256) 256)))
          (string-append "signal " (%cu-int->str (% raw 128))))))))
    (%ts-status)))

(def %ts-status
  (fn (_)
    (when (if (> %ts-verbose 0) (> %ts-cmax 1) #f)
      (%ts-say (string-concat (list "status " (%cu-int->str %ts-cnum) "/" (%cu-int->str %ts-cmax)))))))

; sig_term_handler: a fatal signal ends the run with that signal's own death
(def %ts-fatal-check
  (fn (_ sigs)
    (unless (null? sigs)
      (if (Sys take-signal (first sigs))
        (do (when (> %ts-verbose 0) (%ts-say (string-concat (list "got signal " (%cu-int->str (first sigs)) ", exit"))))
            (sys-signal (first sigs) 0)
            (sys-kill (sys-getpid) (first sigs))
            (sys-exit (+ 128 (first sigs))))
        (%ts-fatal-check (rest sigs))))))

; --- a connection ---------------------------------------------------------------

(def %ts-env? #t)
(def %ts-h? #f)
(def %ts-lname ())
(def %ts-maxph 0)
(def %ts-msg ())
(def %ts-prog ())
(def %ts-bound ())             ; the listener's (QUAD . PORT)
(def %ts-sigs ())
(def %ts-chld 0)
(def %ts-idle -1)              ; a pipe's read end that never reads: the wait while -c is full

; the next connection: (CONN . REMOTE), CONN the descriptor PROG gets.  For UDP
; it is the listening socket itself, connected to its sender, and a fresh one
; takes its place; LFD then answers the new one.
(def %ts-next
  (fn (_ lfd)
    (if %ts-tcp
      (let ((c (guard (_ ()) (net-accept lfd))))
        (if (null? c) () (list c (net-peer c) lfd)))
      (let ((remote (%ts-udp-peek lfd)))
        (if (null? remote) ()
          (do (%cu-ptr-call (%ts-c "connect") lfd (%cu-str->ptr (%ts-sockaddr (first remote) (rest remote))) 16)
              (list lfd remote (%ts-udp-bind (first %ts-bound) (rest %ts-bound)))))))))

; ipsvd_perhost_add: how many connections REMOTE's address would have, this one
; counted
(def %ts-per-host
  (fn (_ quad) (+ 1 (length (filter (fn (_ h) (string=? (rest h) quad)) %ts-hosts)))))

; a connection taken: refused for -C, or handed to a child; the listener to
; wait on next
(def %ts-take
  (fn (_ lfd)
    (def n (%ts-next lfd))
    (if (null? n) lfd
      (let ((conn (first n)) (remote (first (rest n))) (next (first (rest (rest n)))))
        (def cur (if (> %ts-maxph 0) (%ts-per-host (first remote)) 0))
        (if (if (> %ts-maxph 0) (> cur %ts-maxph) #f)
          (do (unless (null? %ts-msg) (guard (_ ()) (%cu-ptr-call (%ts-c "send") conn %ts-msg (byte-len %ts-msg) (if os-darwin? 128 64))))
              (net-close conn)
              next)
          (do (%ts-fork conn remote cur lfd) next))))))

(def %ts-fork
  (fn (_ conn remote cur lfd)
    (def sync (sys-pipe))
    (%ts-fcntl (rest sync) 2 1)               ; F_SETFD FD_CLOEXEC
    (def pid (sys-fork))
    (if (= pid 0)
      (do (sys-close (first sync))
          (%ts-child conn remote cur lfd))
      (do (sys-close (rest sync))
          (file-read-run (first sync) 1)
          (sys-close (first sync))
          (net-close conn)
          (set! %ts-cnum (+ %ts-cnum 1))
          (when (> %ts-maxph 0) (set! %ts-hosts (pair (pair pid (first remote)) %ts-hosts)))
          (%ts-status)))))

; the child: the connection on stdin and stdout, the environment, PROG
(def %ts-child
  (fn (_ conn remote cur lfd)
    (when %ts-tcp (net-close lfd))
    (sys-dup2 conn 0)
    (unless (= conn 0) (net-close conn))
    ; the platform's copy of the stdin x started with, which PROG has no use for
    (unless (= conn 3) (sys-close 3))
    (def proto (if %ts-tcp "TCP" "UDP"))
    (def raddr (if (> %ts-maxph 0) (first remote) (%ts-dotted remote)))
    (def rhost (if %ts-h?
                 (let ((h (%ts-host-name (first remote))))
                   (if (null? h) (do (%ts-say (string-append "can't look up hostname for " raddr)) raddr) h))
                 ()))
    (def local (%ts-local 0))
    (def laddr (%ts-dotted local))
    (def lhost (if %ts-h?
                 (if (null? %ts-lname)
                   (let ((h (%ts-host-name (first local))))
                     (if (null? h) (do (%ts-say (string-append "can't look up hostname for " laddr)) (sys-exit 1)) h))
                   %ts-lname)
                 ()))
    (when (> %ts-verbose 0)
      (do (when (> %ts-maxph 0)
            (%ts-say (string-concat (list "concurrency " raddr " " (%cu-int->str cur) "/" (%cu-int->str %ts-maxph)))))
          (%ts-say (string-concat (list "start " (%cu-int->str (sys-getpid)) " " laddr "-" raddr
                                        (if %ts-h? (string-concat (list " (" lhost "-" rhost ")")) ""))))))
    (when %ts-env?
      (do (sys-setenv "PROTO" proto)
          (sys-setenv (string-append proto "LOCALADDR") laddr)
          (sys-setenv (string-append proto "REMOTEADDR") raddr)
          (when %ts-h?
            (do (sys-setenv (string-append proto "LOCALHOST") lhost)
                (sys-setenv (string-append proto "REMOTEHOST") rhost)))
          (when (> cur 0) (sys-setenv "TCPCONCURRENCY" (%cu-int->str cur)))))
    (sys-dup2 0 1)
    (sys-signal 13 0)
    (map (fn (_ s) (sys-signal s 0)) %ts-sigs)
    (let ((err (sys-exec-or-err (first %ts-prog) (rest %ts-prog))))
      (do (%ts-say (string-concat (list "can't execute '" (first %ts-prog) "': " (file-err-text err))))
          (sys-exit 127)))))

(def %ts-loop
  (fn (self lfd)
    (%cu-sweep-tick! %cu-sweep-lines)
    (Sys take-signal %ts-chld)
    (%ts-reap!)
    (%ts-fatal-check %ts-sigs)
    (if (>= %ts-cnum %ts-cmax)
      (do (sys-poll (list (pair %ts-idle (list (lit in)))) 500) (self lfd))
      (let ((ready (sys-poll (list (pair lfd (list (lit in)))) 500)))
        (self (if (null? ready) lfd (%ts-take lfd)))))))

; --- the applets -----------------------------------------------------------------

(def %cu-tcpsvd (fn (_ argv stdin-thunk) (%ts-main "tcpsvd" argv)))
(def %cu-udpsvd (fn (_ argv stdin-thunk) (%ts-main "udpsvd" argv)))

(def %ts-main
  (fn (_ app argv)
    (set! %ts-app app)
    (set! %ts-tcp (string=? app "tcpsvd"))
    (def o (%cu-opts app argv))
    (if (< (length (Opts operands o)) 3) (%cu-usage app)
      (guard (e (if (eq? (Err label e) (lit net))
                  (do (%ts-say (e msg)) 1)
                  (error e)))
        (%ts-start app o)))))

; -C N[:MSG]: (N . MSG), or nil when what follows N is not :MSG
(def %ts-per-host-opt
  (fn (_ s)
    (def r (%ts-leading s))
    (match ((= (rest r) (byte-len s)) (pair (first r) ()))
           ((= (byte-at s (rest r)) #\:) (pair (first r) (substring s (+ (rest r) 1) (byte-len s))))
           (#t ()))))

(def %ts-start
  (fn (_ app o)
    (def ops (Opts operands o))
    (set! %ts-verbose (%nc-count o "-v"))
    (set! %ts-env? (not (Opts on? o "-E")))
    (set! %ts-h? (if (Opts on? o "-h") #t (Opts on? o "-p")))
    (set! %ts-lname (Opts value o "-l"))
    (set! %ts-cmax (let ((c (Opts value o "-c"))) (if (null? c) 30 (%ts-count c))))
    (def backlog (let ((b (Opts value o "-b"))) (if (null? b) 20 (%ts-count b))))
    (def ph (let ((c (Opts value o "-C"))) (if (null? c) (pair 0 ()) (%ts-per-host-opt c))))
    (if (null? ph) (%cu-usage app)
      (do (set! %ts-maxph (if %ts-tcp (if (> (first ph) %ts-cmax) %ts-cmax (first ph)) 0))
          (set! %ts-msg (rest ph))
          (%ts-run o ops backlog)))))

; the socket bound, the user dropped to, and the connections served
(def %ts-run
  (fn (_ o ops backlog)
    (def ug (let ((u (Opts value o "-u"))) (if (null? u) () (%hd-ugid u))))
    (def host (first ops))
    (def quad (if (if (= (byte-len host) 0) #t (string=? host "0")) "0.0.0.0"
                (let ((q (guard (_ ()) (net-resolve host))))
                  (if (null? q) (%ts-die (string-concat (list "bad address '" host "'"))) q))))
    (def port (%ts-port (first (rest ops))))
    (set! %ts-prog (rest (rest ops)))
    (set! %ts-chld (%ts-signal-number "CHLD"))
    (set! %ts-sigs (%ts-fatal))
    (Sys catch-signal %ts-chld)
    (map (fn (_ s) (Sys catch-signal s)) %ts-sigs)
    (sys-signal 13 cu-sig-ign)
    (def lfd (%ts-listen quad port backlog))
    (set! %ts-bound (pair quad port))
    (unless (null? ug) (%ts-drop! ug))
    (when (> %ts-verbose 0)
      (%ts-say (string-concat (list "listening on " quad ":" (%cu-int->str port) ", starting"
        (if (null? ug) "" (string-concat (list ", uid " (%cu-int->str (first ug)) ", gid " (%cu-int->str (rest ug)))))))))
    (let ((p (sys-pipe)))
      (do (%ts-fcntl (first p) 2 1) (%ts-fcntl (rest p) 2 1) (set! %ts-idle (first p))))
    (%ts-loop lfd)))

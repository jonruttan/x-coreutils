; # x-coreutils -- the small tools, as applets
;
; ## cu/telnetd.x -- telnetd: a login on a pseudo-terminal for each connection
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; networking/telnetd.c: each connection gets a pseudo-terminal, and LOGIN
; (-l, else /bin/login) runs on its terminal side in a session of its own,
; after the issue file (-f, else /etc/issue.net) is printed there.  The
; connection is told WILL ECHO, WILL SGA and DO NAWS, and from then the
; bytes between it and the terminal are passed along: from the client, IAC
; IAC is a 0xff, the two-byte commands and the WILL/WONT/DO/DONT replies are
; dropped, AYT is answered IAC NOP, NAWS sets the terminal's window, and a CR
; drops the LF or NUL after it; to the client, each 0xff is doubled.
;
; The connection's end hangs the terminal up -- two EOF characters first,
; then 20 ms for them to be read -- and the terminal's end closes the
; connection; with -K, so does LOGIN's.  -i serves the one connection inetd
; hands it, -w SEC the listening socket inetd hands it until SEC seconds pass
; with no connection; otherwise telnetd listens on -p PORT (23) or -b
; ADDR[:PORT] and, without -F, leaves the terminal.  Each session is recorded
; in utmp, as busybox records it.

(module cu/telnetd)

(import x/sys/pty)
(import cu/cli cu-opts cu-usage)
(import cu/date cu-date-fmt cu-date-split)
(import cu/inetd in-af in-bind in-c in-call in-count in-errtext in-exec
  in-percent in-reuse! in-sockaddr6 in-strtou in-zeroed)
(import cu/nc nc-count)
(import cu/prims append byte-at byte-len cu-int->str cu-nth cu-ptr->str
  cu-ptr-call cu-ptr-ref cu-ptr-set! cu-sig-ign cu-str->ptr cu-sweep-lines
  cu-sweep-tick! date-now-unix file-close file-err-sym file-exists?
  file-read-all file-read-run file-write filter in-index-of length map
  net-aton net-peer net-send-run net-sockaddr net-stdin-socket reverse
  str-make-raw string-append string-concat substring sys-close
  sys-exit sys-fork sys-poll sys-signal sys-time-ms sys-uname vec-make vec-ref
  vec-set!)
(import cu/session hd-daemonize)
(import cu/signal ts-signal-number)
(import cu/telnet tn-run)
(import cu/who cu-uname-field)

(def %td-login "/bin/login")
(def %td-issue "/etc/issue.net")
(def %td-verbose 0)
(def %td-watch? #f)             ; -K
(def %td-syslog? #f)
(def %td-sessions ())
(def %td-chld 0)

(def %td-iac 255)
(def %td-se 240)
(def %td-ayt 246)
(def %td-nop 241)
(def %td-sb 250)
(def %td-opt-naws 31)

(def %td-say
  (fn (_ msg)
    (if %td-syslog?
      (cu-ptr-call (in-c "syslog") 3 (in-percent msg))
      (file-write 2 (string-concat (list "telnetd: " msg "\n"))))))

(def %td-die (fn (_ msg) (Err raise (lit net) msg ())))

(def %td-now-ms (fn (_) (sys-time-ms)))

; fcntl is a system call here: its third argument is variadic
(def %td-cloexec! (fn (_ fd) ((syscall-door (lit fcntl)) fd 2 1)))

; --- the terminal --------------------------------------------------------------

; xgetpty: the controlling side's descriptor and the terminal's path
(def %td-getpty
  (fn (_)
    (def p (Pty open))
    (when (null? p) (%td-die "can't find free pty"))
    p))

(def td-ptr->int (prim-ref (lit ptr) (lit ->int)))

; the termios flag words, by offset: Darwin's tcflag_t is eight bytes, Linux's four
(def %td-tio-at (fn (_ k) (* k (if os-darwin? 8 4))))
(def %td-tio-get (fn (_ buf k) (cu-ptr-ref (cu-str->ptr buf) (%td-tio-at k) 4)))
(def %td-tio-set! (fn (_ buf k v) (cu-ptr-set! (cu-str->ptr buf) (%td-tio-at k) v 4)))

; cooked mode with ECHO, ONLCR and XTABS on and ICRNL, IXOFF off, as the child
; sets its terminal before LOGIN
(def %td-cook-terminal!
  (fn (_)
    (def buf (str-make-raw 128))
    (when (>= (in-call (cu-ptr-call (in-c "tcgetattr") 0 (cu-str->ptr buf))) 0)
      (do (%td-tio-set! buf 3 (| (%td-tio-get buf 3) 8))
          (%td-tio-set! buf 1 (| (%td-tio-get buf 1) (if os-darwin? (| 2 4) (| 4 6144))))
          (let ((iflag (| (%td-tio-get buf 0) 256)) (ixoff (if os-darwin? 1024 4096)))
            (%td-tio-set! buf 0 (- iflag (& iflag ixoff))))
          (cu-ptr-call (in-c "tcsetattr") 0 0 (cu-str->ptr buf))))))

; fabricate_ctrl_D_on_pty: in canonical mode, the EOF character twice
(def %td-ctrl-d!
  (fn (_ fd)
    (def buf (str-make-raw 128))
    (when (>= (in-call (cu-ptr-call (in-c "tcgetattr") fd (cu-str->ptr buf))) 0)
      (let ((icanon? (> (& (%td-tio-get buf 3) (if os-darwin? 256 2)) 0))
            (eof (cu-ptr-ref (cu-str->ptr buf) (if os-darwin? 32 21) 1)))
        (when (if icanon? (> eof 0) #f)
          (let ((b (str-make-raw 2)))
            (do (cu-ptr-set! (cu-str->ptr b) 0 eof 1)
                (cu-ptr-set! (cu-str->ptr b) 1 eof 1)
                (File write fd b 1)
                (File write fd b 1))))))))

; --- the issue file ---------------------------------------------------------------

(def %td-domainname
  (fn (_)
    (def buf (in-zeroed 256))
    (cu-ptr-call (in-c "getdomainname") (cu-str->ptr buf) 255)
    (cu-ptr->str (cu-str->ptr buf))))

; \D, \o and \O: the domainname, which only Linux's utsname has
(def %td-domain-escape?
  (fn (_ c) (if os-darwin? #f (match ((= c #\D) #t) ((= c #\o) #t) (#t (= c #\O))))))

; print_login_issue: each \ or % escape replaced, each newline followed by CR
(def %td-issue-text
  (fn (_ text tty)
    (def u (sys-uname))
    (def field (fn (_ k) (cu-uname-field u k)))
    (def n (byte-len text))
    (def now (date-now-unix))
    (def escape
      (fn (_ c)
        (match ((if (= c #\S) #t (= c #\s)) (field (lit sysname)))
               ((if (= c #\n) #t (= c #\h)) (field (lit nodename)))
               ((= c #\r) (field (lit release)))
               ((= c #\v) (field (lit version)))
               ((= c #\m) (field (lit machine)))
               ((%td-domain-escape? c) (%td-domainname))
               ((= c #\d) (cu-date-fmt "%A, %d %B %Y" (cu-date-split now #f) now))
               ((= c #\t) (cu-date-fmt "%H:%M:%S" (cu-date-split now #f) now))
               ((= c #\l) tty)
               (#t (bytes->str (list c))))))
    (let go ((i 0) (acc ()))
      (if (>= i n) (string-concat (reverse acc))
        (let ((c (byte-at text i)))
          (match
            ((= c #\newline) (go (+ i 1) (pair "\n\r" acc)))
            ((if (if (= c #\\) #t (= c #\%)) (< (+ i 1) n) #f) (go (+ i 2) (pair (escape (byte-at text (+ i 1))) acc)))
            (#t (go (+ i 1) (pair (bytes->str (list c)) acc)))))))))

; --- utmp -------------------------------------------------------------------------

; struct utmpx, as libc lays it out: Darwin's and glibc's
(def %td-ut-size (if os-darwin? 640 384))
(def %td-ut-user (if os-darwin? 0 44))
(def %td-ut-id (if os-darwin? 256 40))
(def %td-ut-line (if os-darwin? 260 8))
(def %td-ut-pid (if os-darwin? 292 4))
(def %td-ut-type (if os-darwin? 296 0))
(def %td-ut-tv (if os-darwin? 304 340))
(def %td-ut-host (if os-darwin? 320 76))
(def %td-ut-line-len 32)
(def %td-ut-user-len (if os-darwin? 256 32))
(def %td-ut-host-len 256)

(def %td-put-str!
  (fn (_ buf at s cap)
    (let go ((i 0)) (when (if (< i (byte-len s)) (< i (- cap 1)) #f)
                      (do (cu-ptr-set! (cu-str->ptr buf) (+ at i) (byte-at s i) 1) (go (+ i 1)))))))

(def %td-skip-dev (fn (_ tty) (if (Str8 starts? "/dev/" tty) (substring tty 5 (byte-len tty)) tty)))

; write_new_utmp: a LOGIN_PROCESS record for PID on TTY from HOST
(def %td-utmp-login!
  (fn (_ pid tty host)
    (def u (in-zeroed %td-ut-size))
    (def line (%td-skip-dev tty))
    (cu-ptr-set! (cu-str->ptr u) %td-ut-pid pid 4)
    (cu-ptr-set! (cu-str->ptr u) %td-ut-type 6 2)
    (%td-put-str! u %td-ut-line line %td-ut-line-len)
    (%td-put-str! u %td-ut-user "LOGIN" %td-ut-user-len)
    (unless (null? host) (%td-put-str! u %td-ut-host host %td-ut-host-len))
    (cu-ptr-set! (cu-str->ptr u) %td-ut-tv (date-now-unix) (if os-darwin? 8 4))
    (def id (string-append (if (= (byte-at line 0) #\p) "p" "")
                           (if (> (byte-len line) 3) (substring line 3 (byte-len line)) line)))
    (let go ((i 0)) (when (if (< i 4) (< i (byte-len id)) #f)
                      (do (cu-ptr-set! (cu-str->ptr u) (+ %td-ut-id i) (byte-at id i) 1) (go (+ i 1)))))
    (%td-utmp-write! u)))

; touch: the utmp file made when it is not there, as busybox makes it
(def %td-utmp-file (if os-darwin? "/var/run/utmpx" "/var/run/utmp"))
(def %td-utmp-touch!
  (fn (_)
    (unless (file-exists? %td-utmp-file)
      (guard (_ ()) (file-close (File open %td-utmp-file (list (lit wronly) (lit creat)) 436))))))

(def %td-utmp-write!
  (fn (_ u)
    (%td-utmp-touch!)
    (cu-ptr-call (in-c "setutxent"))
    (cu-ptr-call (in-c "pututxline") (cu-str->ptr u))
    (cu-ptr-call (in-c "endutxent"))
    (unless os-darwin? (cu-ptr-call (in-c "updwtmpx") "/var/log/wtmp" (cu-str->ptr u)))))

; update_utmp_DEAD_PROCESS: PID's record, if it has one, made DEAD_PROCESS
(def %td-utmp-dead!
  (fn (_ pid)
    (%td-utmp-touch!)
    (cu-ptr-call (in-c "setutxent"))
    (let go ()
      (let ((p (cu-ptr-call (in-c "getutxent"))))
        (if (= (td-ptr->int p) 0) (cu-ptr-call (in-c "endutxent"))
          (let ((type (cu-ptr-ref p %td-ut-type 2)))
            (if (if (= (cu-ptr-ref p %td-ut-pid 4) pid)
                  (if (> (cu-ptr-ref p %td-ut-id 1) 0) (if (>= type 5) (<= type 8) #f) #f) #f)
              (let ((u (str-make-raw %td-ut-size)))
                (do (let copy ((i 0)) (when (< i %td-ut-size)
                                        (do (cu-ptr-set! (cu-str->ptr u) i (cu-ptr-ref p i 1) 1) (copy (+ i 1)))))
                    (cu-ptr-set! (cu-str->ptr u) %td-ut-type 8 2)
                    (cu-ptr-set! (cu-str->ptr u) %td-ut-tv (date-now-unix) (if os-darwin? 8 4))
                    (cu-ptr-call (in-c "pututxline") (cu-str->ptr u))
                    (cu-ptr-call (in-c "endutxent"))
                    (unless os-darwin? (cu-ptr-call (in-c "updwtmpx") "/var/log/wtmp" (cu-str->ptr u)))))
              (go))))))))

; --- a session ---------------------------------------------------------------------

; a session's fields, by place in its vector
(def %td-rd 0)                  ; the connection, read
(def %td-wr 1)                  ; the connection, written
(def %td-pty 2)                 ; the terminal's controlling side, or -1 once closed
(def %td-pid 3)                 ; LOGIN, or -1 once it has ended (-K)
(def %td-in 4)                  ; bytes from the client not yet passed on
(def %td-skip 5)                ; the last byte to the terminal was CR
(def %td-net-eof 6)
(def %td-hangup-at 7)           ; when the terminal is closed, the client gone
(def %td-eio 8)
(def %td-eio-at 9)
(def %td-fields 10)

(def %td-get (fn (_ s k) (vec-ref s k)))
(def %td-set! (fn (_ s k v) (vec-set! s k v)))

(def %td-preamble (bytes->str (list 255 251 1 255 251 3 255 253 31)))

(def %td-peer-host
  (fn (_ fd) (let ((a (guard (_ ()) (net-peer fd)))) (if (null? a) () (first a)))))

; make_new_session: the terminal, the IACs to the client, LOGIN in a child
(def %td-session!
  (fn (_ rd wr others)
    (def mp (%td-getpty))
    (def m (first mp))
    (def tty (rest mp))
    (Sys nonblock! m)
    (%td-cloexec! m)
    (%td-keepalive! rd)
    (Sys nonblock! rd)
    (unless (= rd wr) (Sys nonblock! wr))
    (File write wr %td-preamble 9)
    (def host (%td-peer-host rd))
    (def pid (sys-fork))
    (match
      ((< pid 0) (do (sys-close m) (sys-close rd) (%td-say "fork failed")))
      ((= pid 0) (%td-child m tty rd wr host others))
      (#t (let ((s (vec-make %td-fields ())))
            (do (%td-set! s %td-rd rd) (%td-set! s %td-wr wr) (%td-set! s %td-pty m) (%td-set! s %td-pid pid)
                (%td-set! s %td-skip #f) (%td-set! s %td-net-eof #f) (%td-set! s %td-eio 0)
                (set! %td-sessions (append %td-sessions (list s)))))))))

(def %td-keepalive!
  (fn (_ fd)
    (let ((one (str-make-raw 4)))
      (do (cu-ptr-set! (cu-str->ptr one) 0 1 4)
          (cu-ptr-call (in-c "setsockopt") fd (if os-darwin? 65535 1) (if os-darwin? 8 9) (cu-str->ptr one) 4)))))

; the child: a new session on the terminal, its settings, the issue, LOGIN
(def %td-child
  (fn (_ m tty rd wr host others)
    (sys-signal %td-chld 0)
    (sys-signal 13 0)
    (map (fn (_ fd) (when (>= fd 0) (sys-close fd))) (append (list m rd wr 3) others))
    ; the window is the client's to give, by NAWS
    (unless (Pty attach! tty 0 0) (sys-exit 1))
    (def pid (Sys getpid))
    (cu-ptr-call (in-c "tcsetpgrp") 0 pid)
    (%td-utmp-login! pid tty host)
    (%td-cook-terminal!)
    (let ((text (guard (_ ()) (file-read-all %td-issue))))
      (unless (null? text) (file-write 1 (%td-issue-text text tty))))
    (in-exec %td-login (list %td-login))
    (sys-exit 1)))

; --- from the client to the terminal --------------------------------------------------

; IAC SB NAWS's four values, each possibly an escaped IAC: (COLS ROWS USED),
; or nil while the buffer holds too few
(def %td-naws
  (fn (_ l)
    (let go ((l (rest (rest (rest l)))) (vals ()) (used 3))
      (match ((= (length vals) 4)
               (pair (+ (* 256 (cu-nth 3 vals)) (cu-nth 2 vals))
                     (list (+ (* 256 (cu-nth 1 vals)) (first vals)) used)))
             ((null? l) ())
             ((if (= (first l) %td-iac) (if (null? (rest l)) #f (= (first (rest l)) %td-iac)) #f)
               (go (rest (rest l)) (pair %td-iac vals) (+ used 2)))
             ((= (first l) %td-iac) (if (null? (rest l)) () (go (rest l) (pair %td-iac vals) (+ used 1))))
             (#t (go (rest l) (pair (first l) vals) (+ used 1)))))))

; net_to_pty: the bytes the terminal gets from IN, and what is left for later
(def %td-to-pty!
  (fn (_ s)
    (def pty (%td-get s %td-pty))
    (let go ((l (%td-get s %td-in)) (out ()))
      (def flush (fn (_ rest-bytes)
        (do (unless (null? out) (let ((r (tn-run (reverse out)))) (guard (_ ()) (File write pty (first r) (rest r)))))
            (%td-set! s %td-in (if (%td-get s %td-net-eof) () rest-bytes)))))
      (match
        ((null? l) (flush ()))
        ((if (%td-get s %td-skip) (if (= (first l) #\newline) #t (= (first l) 0)) #f)
          (do (%td-set! s %td-skip #f) (go (rest l) out)))
        ((not (= (first l) %td-iac))
          (do (%td-set! s %td-skip (= (first l) #\return)) (go (rest l) (pair (first l) out))))
        ((null? (rest l)) (flush l))
        (#t (let ((c (first (rest l))))
              (do (%td-set! s %td-skip #f)
                  (match
                    ((= c %td-iac) (go (rest (rest l)) (pair %td-iac out)))
                    ((if (>= c %td-se) (<= c 249) #f)
                      (do (when (= c %td-ayt) (guard (_ ()) (net-send-run (%td-get s %td-wr) (tn-run (list %td-iac %td-nop)))))
                          (go (rest (rest l)) out)))
                    ((null? (rest (rest l))) (flush l))
                    ((if (= c %td-sb) (= (first (rest (rest l))) %td-opt-naws) #f)
                      (if (< (length l) 9) (flush l)
                        (let ((w (%td-naws l)))
                          (if (null? w) (flush l)
                            (do (when (if (> (first w) 0) (> (cu-nth 1 w) 0) #f)
                                  (Pty window! pty (first w) (cu-nth 1 w)))
                                (when (> %td-verbose 0)
                                  (%td-say (string-concat (list "pfd:" (cu-int->str pty) " window size:"
                                                                (cu-int->str (cu-nth 1 w)) "x" (cu-int->str (first w))))))
                                (go (List drop (cu-nth 2 w) l) out))))))
                    (#t (go (rest (rest (rest l))) out))))))))))

; a read from the client: its bytes queued and passed on, or its end noted
(def %td-from-net!
  (fn (_ s)
    (def r (file-read-run (%td-get s %td-rd) 2048))
    (if (= (rest r) 0) (%td-set! s %td-net-eof #t)
      (do (%td-set! s %td-in (append (%td-get s %td-in) (%td-buf-bytes (first r) (rest r))))
          (%td-to-pty! s)))))

; --- from the terminal to the client -------------------------------------------------

; a read from the terminal, its 0xff doubled for the client: #f once the
; terminal is gone -- its end, or ten EIOs a millisecond apart
(def %td-from-pty!
  (fn (_ s)
    (def pty (%td-get s %td-pty))
    (def buf (str-make-raw 2048))
    (def r (in-call (cu-ptr-call (in-c "read") pty (cu-str->ptr buf) 2048)))
    (def errno (if (< r 0) (file-err-sym (Err from-errno (Err errno-of r) (lit read) ())) ()))
    (match
      ((> r 0)
        (do (%td-set! s %td-eio 0)
            (let ((out (tn-run (%td-double-iac (%td-buf-bytes buf r)))))
              (guard (_ #f) (do (net-send-run (%td-get s %td-wr) out) #t)))))
      ((if (< r 0) (eq? errno (lit eagain)) #f) #t)
      ((if (< r 0) (eq? errno (lit eio)) #f)
        (let ((n (+ (%td-get s %td-eio) 1)))
          (do (%td-set! s %td-eio n)
              (%td-set! s %td-eio-at (+ (%td-now-ms) 1))
              (< n 10))))
      (#t #f))))

; the first N bytes of the raw buffer BUF, read through its pointer: a NUL
; among them would end a substring's byte-len
(def %td-buf-bytes
  (fn (_ buf n)
    (let go ((i (- n 1)) (acc ())) (if (< i 0) acc (go (- i 1) (pair (cu-ptr-ref (cu-str->ptr buf) i 1) acc))))))

(def %td-double-iac
  (fn (_ bytes)
    (let go ((l bytes) (acc ()))
      (if (null? l) (reverse acc)
        (go (rest l) (if (= (first l) %td-iac) (pair %td-iac (pair %td-iac acc)) (pair (first l) acc)))))))

; --- the loop -------------------------------------------------------------------------

; a session's end: its terminal and its connection closed
(def %td-end!
  (fn (_ s)
    (when (>= (%td-get s %td-pty) 0) (sys-close (%td-get s %td-pty)))
    (sys-close (%td-get s %td-rd))
    (unless (= (%td-get s %td-wr) (%td-get s %td-rd)) (sys-close (%td-get s %td-wr)))
    (set! %td-sessions (filter (fn (_ x) (not (eq? x s))) %td-sessions))))

; the client gone and its bytes passed on: ^D to the terminal, and 20 ms on,
; the hangup
(def %td-tend!
  (fn (_ s)
    (match
      ((if (< (%td-get s %td-pid) 0) %td-watch? #f) (%td-end! s))
      ((if (%td-get s %td-net-eof) (null? (%td-get s %td-in)) #f)
        (match ((null? (%td-get s %td-hangup-at))
                 (do (%td-ctrl-d! (%td-get s %td-pty)) (%td-set! s %td-hangup-at (+ (%td-now-ms) 20))))
               ((>= (%td-now-ms) (%td-get s %td-hangup-at)) (%td-end! s))
               (#t ())))
      (#t ()))))

; reap: each child that has ended; with -K its session marked to end
(def %td-reap!
  (fn (self)
    (def st (str-make-raw 4))
    (def pid (in-call (cu-ptr-call (in-c "waitpid") -1 (cu-str->ptr st) 1)))
    (when (> pid 0)
      (do (%td-utmp-dead! pid)
          (map (fn (_ s) (when (= (%td-get s %td-pid) pid) (%td-set! s %td-pid -1))) %td-sessions)
          (self)))))

(def %td-ready? (fn (_ ready fd) (List any? (fn (_ e) (= (first e) fd)) ready)))

(def %td-loop
  (fn (self lfd linger quiet-since)
    (cu-sweep-tick! cu-sweep-lines)
    (when (if %td-watch? (Sys take-signal %td-chld) #f) (%td-reap!))
    (map %td-tend! %td-sessions)
    (def now (%td-now-ms))
    (def pending? (List any? (fn (_ s) (not (null? (%td-get s %td-hangup-at)))) %td-sessions))
    (def watched
      (append (if (< lfd 0) () (list (pair lfd (list (lit in)))))
              (%td-append-all (map (fn (_ s)
                                 (append (if (%td-get s %td-net-eof) () (list (pair (%td-get s %td-rd) (list (lit in)))))
                                         (if (if (> (%td-get s %td-eio) 0) (< now (%td-get s %td-eio-at)) #f) ()
                                           (list (pair (%td-get s %td-pty) (list (lit in)))))))
                               %td-sessions))))
    (%td-wait lfd linger quiet-since now self watched pending?)))

(def %td-append-all (fn (_ ls) (let go ((ls ls) (acc ())) (if (null? ls) acc (go (rest ls) (append acc (first ls)))))))

; one turn of the loop's wait, and its end: -i with no session left, -w after
; SEC seconds with none
(def %td-wait
  (fn (_ lfd linger quiet-since now self watched pending?)
    (match
      ((if (< lfd 0) (null? %td-sessions) #f) 0)
      ((if (> linger 0) (if (null? %td-sessions) (>= (- now quiet-since) (* 1000 linger)) #f) #f) 0)
      (#t
        (let ((ready (sys-poll watched (if pending? 5 (if (> linger 0) 200 1000)))))
          (do (when (if (>= lfd 0) (%td-ready? ready lfd) #f)
                (let ((c (in-call (cu-ptr-call (in-c "accept") lfd 0 0))))
                  (when (>= c 0) (do (%td-cloexec! c) (%td-session! c c (list lfd))))))
              (map (fn (_ s)
                     (do (when (if (not (%td-get s %td-net-eof)) (%td-ready? ready (%td-get s %td-rd)) #f)
                           (%td-from-net! s))
                         (when (if (%td-memq s %td-sessions) (%td-ready? ready (%td-get s %td-pty)) #f)
                           (unless (%td-from-pty! s) (%td-end! s)))))
                   %td-sessions)
              (self lfd linger (if (null? %td-sessions) (if (null? ready) quiet-since (%td-now-ms)) (%td-now-ms)))))))))

(def %td-memq (fn (_ x l) (List any? (fn (_ y) (eq? x y)) l)))

; --- the applet --------------------------------------------------------------------------

(def cu-telnetd
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "telnetd" argv))
    (if (if (Opts on? o "-i") (not (null? (Opts value o "-w"))) #f) (cu-usage "telnetd")
      (guard (e (if (eq? (Err label e) (lit net))
                  (do (%td-say (e msg)) 1)
                  (error e)))
        (%td-main o)))))

; create_and_bind_stream_or_die: PORT on ADDR (whose own :PORT wins), or on
; every interface
(def %td-bind
  (fn (_ addr port)
    (def colon (if (null? addr) () (in-index-of addr #\:)))
    (def host (if (null? colon) addr (substring addr 0 colon)))
    (def p (if (null? colon) port (%td-port (substring addr (+ colon 1) (byte-len addr)))))
    (def sa (if (if (null? host) #t (= (byte-len host) 0)) (in-sockaddr6 () p)
              (if (null? (net-aton host)) (%td-die (string-concat (list "bad address '" host "'")))
                (pair (net-sockaddr host p) 16))))
    (def fd (in-call (cu-ptr-call (in-c "socket") (if (= (rest sa) 16) 2 (in-af (lit inet6))) 1 0)))
    (when (< fd 0) (%td-die (string-append "socket: " (in-errtext fd))))
    (in-reuse! fd)
    (def r (in-bind fd sa))
    (when (< r 0) (%td-die (string-append "bind: " (in-errtext r))))
    (cu-ptr-call (in-c "listen") fd 1)
    fd))

; xatou16
(def %td-port
  (fn (_ s)
    (let ((n (in-strtou s)))
      (match ((null? n) (%td-die (string-concat (list "invalid number '" s "'"))))
             ((> n 65535) (%td-die (string-concat (list "number " s " is not in 0..65535 range"))))
             (#t n)))))

(def %td-main
  (fn (_ o)
    (set! %td-login (let ((l (Opts value o "-l"))) (if (null? l) "/bin/login" l)))
    (set! %td-issue (let ((f (Opts value o "-f"))) (if (null? f) "/etc/issue.net" f)))
    (set! %td-verbose (nc-count o "-v"))
    (set! %td-watch? (Opts on? o "-K"))
    (def inetd? (Opts on? o "-i"))
    (def w (let ((v (Opts value o "-w"))) (if (null? v) () (in-count v))))
    (def fg? (if (Opts on? o "-F") #t (not (null? w))))
    (def port (let ((p (Opts value o "-p"))) (if (null? p) 23 (%td-port p))))
    (unless (if inetd? #t fg?) (hd-daemonize))
    (when (if inetd? #t (if (Opts on? o "-S") #t (not fg?)))
      (do (cu-ptr-call (in-c "openlog") "telnetd" 1 24) (set! %td-syslog? #t)))
    (set! %td-chld (ts-signal-number "CHLD"))
    (sys-signal 13 cu-sig-ign)
    (if %td-watch? (Sys catch-signal %td-chld) (sys-signal %td-chld cu-sig-ign))
    (match
      (inetd?
        (let ((rd (net-stdin-socket)))
          (do (%td-session! (if (null? rd) 0 rd) 1 ()) (%td-loop -1 0 (%td-now-ms)))))
      ((not (null? w))
        (let ((lfd (net-stdin-socket)))
          (do (%td-cloexec! (if (null? lfd) 0 lfd))
              (%td-loop (if (null? lfd) 0 lfd) w (%td-now-ms)))))
      (#t (let ((lfd (%td-bind (Opts value o "-b") port)))
            (do (%td-cloexec! lfd) (%td-loop lfd 0 (%td-now-ms))))))))

(provide cu/telnetd cu-telnetd td-ptr->int)

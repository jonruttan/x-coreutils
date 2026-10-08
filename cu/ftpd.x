; # x-coreutils -- the small tools, as applets
;
; ## cu/ftpd.x -- ftpd: busybox's FTP server, one connection on stdin
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; networking/ftpd.c: run from inetd or tcpsvd with the control connection on
; stdin and stdout.  A login with USER and PASS unless -A (or -a USER's
; anonymous), then DIR as the root -- chroot to it, or a chdir when that is
; refused -- and the commands until QUIT or the end of input.  The data
; connections are PASV's or EPSV's listener, or PORT's address on the peer;
; LIST, NLST and STAT FILE are ls -lA or ls -1A run in a child.  -w allows the
; commands that write.
;
; A command is known by its last four letters, each with bit 5 cleared, as
; busybox packs them into a word: XQUIT quits, and syst is SYST.  The replies,
; their codes and the 0xff and NUL escapes are busybox's.  -v logs the error
; replies on stderr, -vv every command and reply; without -v nothing is said,
; not even why a run ended.  -S, busybox's syslog, is accepted and says
; nothing.

(def %fd-verbose 0)
(def %fd-say? #f)              ; -v: anything said goes to stderr
(def %fd-name "ftpd")
(def %fd-write? #f)
(def %fd-timeout 120)
(def %fd-inbuf "")
(def %fd-arg ())
(def %fd-pasv -1)              ; PASV's or EPSV's listener
(def %fd-port ())              ; PORT's (QUAD . PORT)
(def %fd-rest 0)
(def %fd-rnfr ())
(def %fd-local-ip "0.0.0.0")
(def %fd-in 0)                 ; the control connection: net-stdin-socket's fd
(def %fd-libc ())

(def %fd-c
  (fn (_ name)
    (when (null? %fd-libc) (set! %fd-libc (%cu-dlopen () 1)))
    (%cu-dlsym %fd-libc name)))

; bb_error_msg: said only when -v put stderr in the log mode
(def %fd-say
  (fn (_ msg) (when %fd-say? (file-write 2 (string-concat (list %fd-name ": " msg "\n"))))))

(def %fd-die (fn (_ msg) (do (%fd-say msg) (sys-exit 1))))

; verbose_log: the text up to its first CR, LF or NUL
(def %fd-log
  (fn (_ s)
    (let go ((i 0))
      (if (if (< i (byte-len s)) (not (%wget-memv (byte-at s i) (list 13 10 0))) #f)
        (go (+ i 1))
        (%fd-say (substring s 0 i))))))

; --- the control connection ------------------------------------------------------

(def %fd-send (fn (_ s) (file-write-run 1 (pair s (byte-len s)))))

; escape_text: each BYTE in S doubled
(def %fd-double
  (fn (_ s byte)
    (if (null? (%wget-index s byte 0)) s
      (bytes->str (let go ((i (- (byte-len s) 1)) (acc ()))
                    (if (< i 0) acc
                      (go (- i 1) (if (= (byte-at s i) byte) (pair byte (pair byte acc)) (pair (byte-at s i) acc)))))))))

; cmdio_write: CODE and TEXT, 0xff doubled and a LF sent as NUL
(def %fd-write
  (fn (_ code text)
    (def body (string-append code (%fd-double text 255)))
    (def s (string-append (if (null? (%wget-index body 10 0)) body
                            (bytes->str (map (fn (_ b) (if (= b 10) 0 b)) (%cu-bytes body 0 (byte-len body)))))
                          "\r\n"))
    (%fd-send s)
    (when (> %fd-verbose 1) (%fd-log s))))

(def %fd-ok
  (fn (_ code)
    (def s (string-append (%cu-int->str code) " Operation successful\r\n"))
    (%fd-send s)
    (when (> %fd-verbose 1) (%fd-log s))))

(def %fd-err
  (fn (_ code)
    (def s (string-append (%cu-int->str code) " Error\r\n"))
    (%fd-send s)
    (when (> %fd-verbose 0) (%fd-log s))))

(def %fd-raw
  (fn (_ s)
    (%fd-send s)
    (when (> %fd-verbose 1) (%fd-log s))))

; xmalloc_fgets_str_len(stdin, "\r\n"): a line through its CR LF, what is left
; at the end of input, or at most 8K; an idle wait past the timeout ends the run
; with 421, and the end of input with nothing read ends it with 0
(def %fd-getline
  (fn (self)
    (def crlf (%wget-find %fd-inbuf "\r\n"))
    (match
      ((not (null? crlf)) (%fd-take (+ crlf 2)))
      ((>= (byte-len %fd-inbuf) 8192) (%fd-take 8192))
      (#t (let ((ready (sys-poll (list (pair %fd-in (list (lit in)))) (if (= %fd-timeout 0) -1 (* 1000 %fd-timeout)))))
            (if (null? ready)
              (do (%fd-raw "421 Timeout\r\n") (sys-exit 1))
              (let ((r (file-read-run %fd-in 4096)))
                (if (= (rest r) 0)
                  (if (= (byte-len %fd-inbuf) 0) (sys-exit 0) (%fd-take (byte-len %fd-inbuf)))
                  (do (set! %fd-inbuf (string-append %fd-inbuf (substring (first r) 0 (rest r))))
                      (self))))))))))

(def %fd-take
  (fn (_ n)
    (def line (substring %fd-inbuf 0 n))
    (set! %fd-inbuf (substring %fd-inbuf n (byte-len %fd-inbuf)))
    line))

; the telnet escapes undone -- 255 255 is 255, 255 and any other byte are
; dropped -- and a NUL read as LF
(def %fd-unescape
  (fn (_ s)
    (if (if (null? (%wget-index s 255 0)) (null? (%wget-index s 0 0)) #f) s
      (bytes->str
        (let go ((bs (%cu-bytes s 0 (byte-len s))) (acc ()))
          (match ((null? bs) (reverse acc))
                 ((= (first bs) 255)
                   (match ((null? (rest bs)) (reverse acc))
                          ((= (first (rest bs)) 255) (go (rest (rest bs)) (pair 255 acc)))
                          (#t (go (rest (rest bs)) acc))))
                 ((= (first bs) 0) (go (rest bs) (pair 10 acc)))
                 (#t (go (rest bs) (pair (first bs) acc)))))))))

; cmdio_get_cmd_and_arg: the next command, its argument left in %fd-arg (nil
; when there is no space), answered as busybox's word: the last four letters
; with bit 5 of each cleared
(def %fd-command
  (fn (_)
    (def raw (%fd-getline))
    (def n (byte-len raw))
    (def n1 (if (if (> n 0) (= (byte-at raw (- n 1)) 10) #f)
              (if (if (> n 1) (= (byte-at raw (- n 2)) 13) #f) (- n 2) (- n 1))
              n))
    (def cmd (%fd-unescape (substring raw 0 n1)))
    (when (> %fd-verbose 1) (%fd-log cmd))
    (def sp (%wget-index cmd #\space 0))
    (set! %fd-arg (if (null? sp) () (substring cmd (+ sp 1) (byte-len cmd))))
    (def word (if (null? sp) cmd (substring cmd 0 sp)))
    (def k (byte-len word))
    (bytes->str (map (fn (_ b) (bit-and b 223)) (%cu-bytes word (if (> k 4) (- k 4) 0) k)))))

; --- the data connection ---------------------------------------------------------

(def %fd-cleanup
  (fn (_)
    (set! %fd-port ())
    (when (> %fd-pasv 1) (guard (_ ()) (net-close %fd-pasv)))
    (set! %fd-pasv -1)))

(def %fd-seen?
  (fn (_)
    (if (if (> %fd-pasv 1) #t (not (null? %fd-port))) #t
      (do (%fd-raw "425 Use PORT/PASV first\r\n") #f))))

; get_remote_transfer_fd: the data connection, MSG said with 150 -- or -1, 425
; said, when PASV's listener takes none; a PORT address that refuses ends the run
(def %fd-data
  (fn (_ msg)
    (def fd
      (if (> %fd-pasv 1)
        (let ((c (guard (_ -1) (net-accept %fd-pasv))))
          (do (when (< c 0) (%fd-err 425)) c))
        (guard (e (%fd-die (string-concat (list "can't connect to remote host (" (first %fd-port) "): "
                                                 (%wget-err-text e)))))
          (net-connect (first %fd-port) (rest %fd-port)))))
    (%fd-cleanup)
    (when (>= fd 0) (%fd-write "150" msg))
    fd))

; bind_for_passive_mode: a listener on the control connection's own address
(def %fd-passive
  (fn (_)
    (%fd-cleanup)
    (set! %fd-pasv (Socket tcp-listen-on %fd-local-ip 0 1))
    (Socket local-port %fd-pasv)))

; bb_copyfd_eof: FROM to TO until FROM's end; #f when a write fails
(def %fd-copy
  (fn (self from to)
    (let ((r (file-read-run from 65536)))
      (if (= (rest r) 0) #t
        (let ((w (File write to (first r) (rest r))))
          (if (if (number? w) (= w (rest r)) #f) (self from to) #f))))))

; --- the commands ----------------------------------------------------------------

; #t when THUNK's call did not fail: a negative answer or a raise is a failure
(def %fd-try
  (fn (_ thunk)
    (guard (_ #f) (let ((r (thunk))) (if (number? r) (>= r 0) #t)))))

(def %fd-regular?
  (fn (_ path)
    (let ((st (guard (_ ()) (file-stat path))))
      (if (null? st) #f (eq? (Assoc get (lit file-type) st) (lit file))))))

(def %fd-pwd
  (fn (_)
    (let ((cwd (guard (_ "") (sys-getcwd))))
      (%fd-write "257" (string-concat (list " \"" (%fd-double cwd #\") "\""))))))

(def %fd-cwd
  (fn (_ dir)
    (if (if (null? dir) #f (%fd-try (fn (_) (Sys chdir dir)))) (%fd-ok 250) (%fd-err 550))))

(def %fd-feat
  (fn (_ code)
    (%fd-write code "-Features:")
    (%fd-raw " EPSV\r\n PASV\r\n REST STREAM\r\n MDTM\r\n SIZE\r\n")
    (%fd-write code " Ok")))

(def %fd-pasv-cmd
  (fn (_)
    (def port (%fd-passive))
    (%fd-raw (string-concat (list "227 PASV ok (" (Str8 replace "." "," %fd-local-ip) ","
                                  (%cu-int->str (%wget-div port 256)) "," (%cu-int->str (% port 256)) ")\r\n")))))

(def %fd-epsv-cmd
  (fn (_) (%fd-raw (string-concat (list "229 EPSV ok (|||" (%cu-int->str (%fd-passive)) "|)\r\n")))))

; PORT h1,h2,h3,h4,p1,p2: the peer's own address, at the port the last two name
(def %fd-port-cmd
  (fn (_)
    (%fd-cleanup)
    (def raw %fd-arg)
    (def c2 (if (null? raw) () (%wget-last-index raw #\,)))
    (def lo (if (null? c2) () (%wget-digits (substring raw (+ c2 1) (byte-len raw)))))
    (def c1 (if (null? lo) () (%wget-last-index (substring raw 0 c2) #\,)))
    (def hi (if (null? c1) () (%wget-digits (substring raw (+ c1 1) c2))))
    (if (if (null? hi) #t (if (> lo 255) #t (> hi 255)))
      (%fd-err 500)
      (do (set! %fd-port (pair (first (net-peer %fd-in)) (+ (* hi 256) lo))) (%fd-ok 200)))))

(def %fd-rest-cmd
  (fn (_)
    (set! %fd-rest (if (null? %fd-arg) 0
                     (let ((n (%wget-digits %fd-arg)))
                       (if (null? n) (%fd-die (string-concat (list "invalid number '" %fd-arg "'"))) n))))
    (%fd-ok 350)))

(def %fd-retr
  (fn (_)
    (def offset %fd-rest)
    (set! %fd-rest 0)
    (when (%fd-seen?)
      (let ((fd (if (null? %fd-arg) -1 (guard (_ -1) (file-open-read %fd-arg)))))
        (match
          ((< fd 0) (%fd-err 550))
          ((not (%fd-regular? %fd-arg)) (do (%fd-err 550) (file-close fd)))
          (#t (%fd-retr-send fd offset)))))))

(def %fd-retr-send
  (fn (_ fd offset)
    (unless (= offset 0) (file-seek fd offset))
    (def size (Assoc get (lit size) (file-stat %fd-arg)))
    (def remote (%fd-data (string-concat (list " Opening BINARY connection for " %fd-arg
                                               " (" (%cu-int->str size) " bytes)"))))
    (when (>= remote 0)
      (do (if (%fd-copy fd remote) (do (net-close remote) (%fd-ok 226)) (do (net-close remote) (%fd-err 451)))))
    (file-close fd)))

; popen_ls: ls -lA or -1A -- ARG in a child, its output read whole; an ARG
; starting with - is a client's LIST -l, and what follows its space is listed
; instead.  OPTS are the flags apart, as Opts reads -1A as a number.
(def %fd-ls
  (fn (_ opts)
    (def arg (if (if (null? %fd-arg) #f (Str8 starts? "-" %fd-arg))
               (let ((sp (%wget-index %fd-arg #\space 0))) (if (null? sp) () (substring %fd-arg (+ sp 1) (byte-len %fd-arg))))
               %fd-arg))
    (def p (sys-pipe))
    (def pid (sys-fork))
    (if (= pid 0)
      (do (sys-close (first p))
          (sys-dup2 (rest p) 1)
          (sys-close (rest p))
          (sys-dup2 1 0)
          (unless %fd-say? (sys-dup2 (file-open-wronly "/dev/null") 2))
          (sys-exit (guard (_ 1) (cu-run (append (list "ls") opts (list "--") (if (null? arg) () (list arg))) ""))))
      (do (sys-close (rest p))
          (let go ((acc ()))
            (let ((r (file-read-run (first p) 65536)))
              (if (= (rest r) 0)
                (do (sys-close (first p)) (string-concat (reverse acc)))
                (go (pair (substring (first r) 0 (rest r)) acc)))))))))

(def %fd-lines
  (fn (_ s)
    (let go ((i 0) (acc ()))
      (let ((nl (%wget-index s #\newline i)))
        (if (null? nl) (reverse (if (< i (byte-len s)) (pair (substring s i (byte-len s)) acc) acc))
          (go (+ nl 1) (pair (substring s i nl) acc)))))))

; LIST and NLST: the listing on a data connection, each line ending CR LF
(def %fd-list
  (fn (_ opts)
    (when (%fd-seen?)
      (let ((text (%fd-ls opts)))
        (let ((remote (%fd-data " Directory listing")))
          (do (when (>= remote 0)
                (do (map (fn (_ l) (file-write remote (string-append l "\r\n"))) (%fd-lines text))
                    (net-close remote)))
              (%fd-ok 226)))))))

; STAT FILE: the listing on the control connection
(def %fd-stat-file
  (fn (_)
    (def text (%fd-ls (list "-l" "-A")))
    (%fd-raw "213-File status:\r\n")
    (map (fn (_ l) (%fd-write "" l)) (%fd-lines text))
    (%fd-ok 213)))

(def %fd-size-or-mdtm
  (fn (_ size?)
    (if (if (null? %fd-arg) #t (not (%fd-regular? %fd-arg)))
      (%fd-err 550)
      (let ((st (file-stat %fd-arg)))
        (%fd-raw (string-concat (list "213 "
          (if size? (%cu-int->str (Assoc get (lit size) st)) (%fd-stamp (Assoc get (lit mtime) st)))
          "\r\n")))))))

; YYYYMMDDhhmmss in UTC
(def %fd-stamp
  (fn (_ secs)
    (def d (Date from-unix secs))
    (def f (fn (_ k w) (%cu-pad-zero (%cu-int->str (Assoc get k d)) w)))
    (string-concat (list (f (lit year) 4) (f (lit month) 2) (f (lit day) 2)
                         (f (lit hour) 2) (f (lit minute) 2) (f (lit second) 2)))))

; --- the commands that write (-w) -----------------------------------------------

(def %fd-simple
  (fn (_ thunk code)
    (if (if (null? %fd-arg) #f (%fd-try thunk)) (%fd-ok code) (%fd-err 550))))

(def %fd-rnto
  (fn (_)
    (if (if (null? %fd-rnfr) #t (null? %fd-arg))
      (%fd-raw "503 Use RNFR first\r\n")
      (let ((from %fd-rnfr))
        (do (set! %fd-rnfr ())
            (if (%fd-try (fn (_) (file-rename from %fd-arg))) (%fd-ok 250) (%fd-err 550)))))))

; mkstemp's uniq.XXXXXX: (FD . NAME)
(def %fd-mkstemp
  (fn (_)
    (def t (%str-make-raw 12))
    (let go ((i 0) (bs (%cu-bytes "uniq.XXXXXX" 0 11)))
      (unless (null? bs) (do (%cu-ptr-set! (%cu-str->ptr t) i (first bs) 1) (go (+ i 1) (rest bs)))))
    (%cu-ptr-set! (%cu-str->ptr t) 11 0 1)
    (def fd (Sys %sign-fold (%cu-ptr-call (%fd-c "mkstemp") (%cu-str->ptr t))))
    (pair fd (%cu-ptr->str (%cu-str->ptr t)))))

; handle_upload_common: STOR, APPE (append?) and STOU (unique?)
(def %fd-upload
  (fn (_ append? unique?)
    (def offset %fd-rest)
    (set! %fd-rest 0)
    (when (%fd-seen?)
      (let ((target (match (unique? (%fd-mkstemp))
                           ((null? %fd-arg) (pair -1 ()))
                           (#t (pair (guard (_ -1)
                                       (File open %fd-arg
                                         (match (append? (list (lit wronly) (lit creat) (lit append)))
                                                ((> offset 0) (list (lit wronly) (lit creat)))
                                                (#t (list (lit wronly) (lit creat) (lit trunc))))
                                         438))
                                     %fd-arg)))))
        (let ((fd (first target)) (name (rest target)))
          (match
            ((if (number? fd) (< fd 0) #t) (%fd-err 553))
            ((not (%fd-regular? name)) (do (%fd-err 553) (file-close fd)))
            (#t (%fd-upload-take fd offset (if unique? (string-append " FILE: " name) " Ok to send data")))))))))

(def %fd-upload-take
  (fn (_ fd offset msg)
    (unless (= offset 0) (file-seek fd offset))
    (def remote (%fd-data msg))
    (when (>= remote 0)
      (if (%fd-copy remote fd) (do (net-close remote) (%fd-ok 226)) (do (net-close remote) (%fd-err 451))))
    (file-close fd)))

(def %fd-write-cmd
  (fn (_ w)
    (match
      ((string=? w "STOR") (%fd-upload #f #f))
      ((string=? w "MKD") (%fd-simple (fn (_) (file-mkdir %fd-arg)) 257))
      ((string=? w "RMD") (%fd-simple (fn (_) (file-rmdir %fd-arg)) 250))
      ((string=? w "DELE") (%fd-simple (fn (_) (file-unlink %fd-arg)) 250))
      ((string=? w "RNFR") (do (set! %fd-rnfr %fd-arg) (%fd-ok 350)))
      ((string=? w "RNTO") (%fd-rnto))
      ((string=? w "APPE") (do (set! %fd-rest 0) (%fd-upload #t #f)))
      ((string=? w "STOU") (do (set! %fd-rest 0) (%fd-upload #f #t)))
      (#t (%fd-raw "500 Unknown command\r\n")))))

(def %fd-one-of?
  (fn (self w ws) (if (null? ws) #f (if (string=? w (first ws)) #t (self w (rest ws))))))

; one command; #f once QUIT is answered
(def %fd-dispatch
  (fn (_ w)
    (match
      ((string=? w "QUIT") (do (%fd-ok 221) #f))
      ((%fd-one-of? w (list "USER" "PASS")) (do (%fd-ok 230) #t))
      ((string=? w "NOOP") (do (%fd-ok 200) #t))
      ((%fd-one-of? w (list "TYPE" "STRU" "MODE")) (do (%fd-ok 200) #t))
      ((string=? w "ALLO") (do (%fd-ok 202) #t))
      ((string=? w "SYST") (do (%fd-raw "215 UNIX Type: L8\r\n") #t))
      ((%fd-one-of? w (list "PWD" "XPWD")) (do (%fd-pwd) #t))
      ((string=? w "CWD") (do (%fd-cwd %fd-arg) #t))
      ((string=? w "CDUP") (do (%fd-cwd "..") #t))
      ((string=? w "HELP") (do (%fd-feat "214") #t))
      ((string=? w "FEAT") (do (%fd-feat "211") #t))
      (#t (%fd-dispatch2 w)))))

(def %fd-dispatch2
  (fn (_ w)
    (match
      ((string=? w "LIST") (%fd-list (list "-l" "-A")))
      ((string=? w "NLST") (%fd-list (list "-1" "-A")))
      ((string=? w "SIZE") (%fd-size-or-mdtm #t))
      ((string=? w "MDTM") (%fd-size-or-mdtm #f))
      ((string=? w "STAT")
        (if (null? %fd-arg) (%fd-raw "211-Server status:\r\n TYPE: BINARY\r\n211 Ok\r\n") (%fd-stat-file)))
      ((string=? w "PASV") (%fd-pasv-cmd))
      ((string=? w "EPSV") (%fd-epsv-cmd))
      ((string=? w "RETR") (%fd-retr))
      ((string=? w "PORT") (%fd-port-cmd))
      ((string=? w "REST") (%fd-rest-cmd))
      (%fd-write? (%fd-write-cmd w))
      (#t (%fd-raw "500 Unknown command\r\n")))
    #t))

(def %fd-loop
  (fn (self)
    (%cu-sweep-tick! %cu-sweep-lines)
    (when (%fd-dispatch (%fd-command)) (self))))

; --- the login --------------------------------------------------------------------

; check_password: PLAIN against USER's system password -- an empty one lets
; anyone in, md5-crypt is compared, and nothing else ever agrees
(def %fd-password-ok?
  (fn (_ user plain)
    (if (null? user) #f
      (let ((stored (%hd-system-password user)))
        (match ((null? stored) #f)
               ((= (byte-len stored) 0) #t)
               (#t (%hd-crypt-equal? (if (null? plain) "" plain) stored)))))))

; USER anonymous with -a ANON, a user the system knows
(def %fd-anonymous?
  (fn (_ anon)
    (match ((null? anon) #f)
           ((null? %fd-arg) #f)
           ((not (string=? %fd-arg "anonymous")) #f)
           (#t (not (null? (sys-user-id anon)))))))

; USER and PASS until one agrees: the user logged in as, or nil when QUIT came
; first.  -a ANON lets USER anonymous in as ANON with no password.
(def %fd-login
  (fn (self anon user)
    (def w (%fd-command))
    (match
      ((string=? w "USER")
        (if (%fd-anonymous? anon)
          anon
          (do (%fd-raw "331 Specify password\r\n")
              (self anon (if (null? %fd-arg) () (if (null? (sys-user-id %fd-arg)) () %fd-arg))))))
      ((string=? w "PASS")
        (if (%fd-password-ok? user %fd-arg) user
          (do (%fd-raw "530 Login failed\r\n") (self anon ()))))
      ((string=? w "QUIT") (do (%fd-ok 221) ()))
      (#t (do (%fd-raw "530 Login with USER+PASS\r\n") (self anon user))))))

; change_identity: initgroups, setgid, setuid -- each failure the end of the run
(def %fd-become
  (fn (_ user)
    (def uid (sys-user-id user))
    (def gid (sys-user-group user))
    (def fail? (fn (_ r what)
      (let ((e (%ss-call r (lit call) what)))
        (unless (null? e) (%fd-die (string-concat (list what ": " (file-err-text e))))))))
    (fail? (%cu-ptr-call (%fd-c "initgroups") user gid) "can't set groups")
    (fail? (%cu-ptr-call (%fd-c "setgid") gid) "setgid")
    (fail? (%cu-ptr-call (%fd-c "setuid") uid) "setuid")))

; --- the applet -------------------------------------------------------------------

(def %cu-ftpd
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "ftpd" argv))
    (guard (e (if (eq? (Err label e) (lit net))
                (do (file-write 2 (string-concat (list "ftpd: " (e msg) "\n"))) 1)
                (error e)))
      (%fd-main o))))

(def %fd-num
  (fn (_ s)
    (let ((n (%wget-digits s)))
      (if (null? n) (Err raise (lit net) (string-concat (list "invalid number '" s "'")) ()) n))))

(def %fd-main
  (fn (_ o)
    (def v (%nc-count o "-v"))
    (def vs (%nc-count o "-S"))
    (set! %fd-verbose (if (> vs v) vs v))
    (set! %fd-write? (Opts on? o "-w"))
    (set! %fd-timeout (let ((t (Opts value o "-t"))) (if (null? t) 120 (%fd-num t))))
    (def abs (let ((t (Opts value o "-T"))) (if (null? t) 3600 (%fd-num t))))
    (when (if (> abs 0) (> %fd-timeout abs) #f) (set! %fd-timeout abs))
    (def in (net-stdin-socket))
    (if (null? in) (%cu-usage "ftpd")
      (do (set! %fd-in in)
          (set! %fd-local-ip (first (net-sock-addr in)))
          (set! %fd-say? (> v 0))
          (when (if (> v 0) #t (> vs 0))
            (set! %fd-name (string-concat (list "ftpd[" (%cu-int->str (sys-getpid)) "]"))))
          (%fd-serve o)))))

(def %fd-serve
  (fn (_ o)
    (sys-signal 13 cu-sig-ign)
    (let ((chld (List find (fn (_ e) (string=? (first e) "CHLD")) (sys-signals))))
      (unless (null? chld) (sys-signal (rest chld) cu-sig-ign)))
    (%fd-ok 220)
    (def user (if (Opts on? o "-A") ()
                (let ((u (%fd-login (Opts value o "-a") ())))
                  (do (when (null? u) (sys-exit 0)) (%fd-ok 230) u))))
    (def dir (let ((ops (Opts operands o))) (if (null? ops) () (first ops))))
    (unless (null? dir)
      (let ((base (if (%fd-try (fn (_ ) (sys-chroot dir))) "/" dir)))
        (unless (%fd-try (fn (_) (Sys chdir base)))
          (%fd-die (string-concat (list "can't change directory to '" base "'"))))))
    (unless (null? user) (%fd-become user))
    (%fd-loop)
    0))

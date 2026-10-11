; # x-coreutils -- the small tools, as applets
;
; ## cu/inetd.x -- inetd: one listener for many services
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; networking/inetd.c: each line of CONFFILE names a service -- [HOST:]SERVICE
; SOCKTYPE PROTO [no]wait[.MAX] USER[:GROUP] PROG ARGS -- whose socket inetd
; binds and watches.  A stream nowait service is accepted and each connection
; handed to PROG in a child, the connection its stdin, stdout and stderr; a
; datagram nowait service hands its socket, connected to the sender, and binds
; a fresh one in its place; a wait service hands the socket itself and is not
; watched again until that child ends.  PROG internal is one of the services
; inetd answers itself: echo, discard, chargen, time and daytime.
;
; SIGHUP reads CONFFILE again, keeping the sockets of the services it still
; names; SIGCHLD reaps; SIGTERM and SIGINT end the run.  busybox does that in
; signal handlers that interrupt its select; here the signals are caught and
; taken between polls.  A service that would not bind, or that is paused for
; taking MAX connections within a minute, is tried again a minute later --
; busybox's alarm, kept here as a time to retry at.  Messages go to syslog,
; or with -e to stderr.  Service names are looked up in /etc/services, read
; as busybox reads it, not through the C library.

(def %in-services-file "/etc/services")
(def %in-pidfile "/var/run/inetd.pid")
(def %in-libc ())
(def %in-stderr? #f)
(def %in-quiet? #f)            ; a builtin's child: nothing said
(def %in-ident "inetd")
(def %in-uid 0)
(def %in-conf ())
(def %in-queue 128)
(def %in-max 0)                ; -R: connections a minute before a pause
(def %in-list ())              ; the services, the newest first
(def %in-default-host "*")
(def %in-retry-at ())          ; when the services without a socket are tried again
(def %in-ring-pos 0)           ; chargen's place for datagrams
(def %in-sigs ())              ; (CHLD HUP ALRM TERM INT)

(def %in-c
  (fn (_ name)
    (when (null? %in-libc) (set! %in-libc (%cu-dlopen () 1)))
    (%cu-dlsym %in-libc name)))

(def %in-call (fn (_ r) (Sys %sign-fold r)))

; the text of the errno a libc call that answered R left
(def %in-errtext (fn (_ r) (file-err-text (Err from-errno (Err errno-of r) (lit call) ()))))

(def %in-now (fn (_) (first (Sys time-of-day))))

; --- messages ---------------------------------------------------------------------

; MSG with each % doubled: syslog's format, given no arguments
(def %in-percent
  (fn (_ msg)
    (let go ((i 0) (from 0) (acc ()))
      (match ((>= i (byte-len msg)) (string-concat (reverse (pair (substring msg from i) acc))))
             ((= (byte-at msg i) #\%) (go (+ i 1) (+ i 1) (pair "%%" (pair (substring msg from i) acc))))
             (#t (go (+ i 1) from acc))))))

(def %in-say
  (fn (_ msg)
    (unless %in-quiet?
      (if %in-stderr?
        (file-write 2 (string-concat (list "inetd: " msg "\n")))
        (%cu-ptr-call (%in-c "syslog") 3 (%in-percent msg))))))

(def %in-die (fn (_ msg) (Err raise (lit net) msg ())))

; xatoi_positive: S as a count, or the run ends naming it
(def %in-count
  (fn (_ s)
    (let ((n (%wget-digits s)))
      (if (null? n) (%in-die (string-concat (list "invalid number '" s "'"))) n))))

; bb_strtou: S as a whole decimal number, or nil
(def %in-strtou
  (fn (_ s)
    (if (if (> (byte-len s) 0) (>= (byte-at s 0) #\0) #f)
      (let ((n (%wget-digits s))) (if (null? n) () (if (> n 4294967295) () n)))
      ())))

; --- a service ---------------------------------------------------------------------

; a service's fields, by place in its vector
(def %in-host 0)
(def %in-service 1)
(def %in-type 2)               ; SOCK_STREAM 1, SOCK_DGRAM 2, ..., -1 unknown
(def %in-proto 3)
(def %in-family 4)             ; inet, inet6 or unix
(def %in-wait 5)               ; 0 nowait, 1 wait, a pid while its child runs
(def %in-max-of 6)
(def %in-user 7)
(def %in-group 8)
(def %in-program 9)
(def %in-argv 10)
(def %in-builtin 11)
(def %in-fd 12)
(def %in-addr 13)              ; the sockaddr bound, or nil
(def %in-count-of 14)
(def %in-time 15)
(def %in-checked 16)
(def %in-watched 17)           ; in the poll set
(def %in-fields 18)

(def %in-get (fn (_ s k) (vec-ref s k)))
(def %in-set! (fn (_ s k v) (vec-set! s k v)))

(def %in-stream? (fn (_ s) (= (%in-get s %in-type) 1)))
(def %in-dgram? (fn (_ s) (= (%in-get s %in-type) 2)))

(def %in-name
  (fn (_ s) (string-concat (list (%in-get s %in-service) "/" (%in-get s %in-proto)))))

; --- the config file -----------------------------------------------------------------

; config_read's lines: each physical line, a trailing backslash joining the
; next, as (LINENO . TEXT)
(def %in-lines
  (fn (_ text)
    (def n (byte-len text))
    (let go ((i 0) (lineno 0) (acc ()) (pending ""))
      (if (>= i n)
        (reverse (if (> (byte-len pending) 0) (pair (pair lineno pending) acc) acc))
        (let ((nl (%wget-index text #\newline i)))
          (def end (if (null? nl) n nl))
          (def line (string-append pending (substring text i end)))
          (def next (if (null? nl) n (+ nl 1)))
          (if (if (> (byte-len line) 0) (= (byte-at line (- (byte-len line) 1)) #\\) #f)
            (if (>= next n)
              (reverse (pair (pair (+ lineno 1) (substring line 0 (- (byte-len line) 1))) acc))
              (go next (+ lineno 1) acc (substring line 0 (- (byte-len line) 1))))
            (go next (+ lineno 1) (pair (pair (+ lineno 1) line) acc) "")))))))

(def %in-blank? (fn (_ c) (if (= c #\space) #t (= c #\tab))))

; config_read with "# \t" and PARSE_NORMAL: the tokens of LINE, at most 26,
; the last taking the rest of the line; nil for a blank or comment line
(def %in-tokens
  (fn (_ line)
    (def n (byte-len line))
    (def skip (fn (self i) (if (if (< i n) (%in-blank? (byte-at line i)) #f) (self (+ i 1)) i)))
    (def stop? (fn (_ i) (if (>= i n) #t (= (byte-at line i) #\#))))
    (def word-end (fn (self i) (if (if (stop? i) #t (%in-blank? (byte-at line i))) i (self (+ i 1)))))
    (def rest-end
      (fn (_ i)
        (let ((e (let go ((j i)) (if (stop? j) j (go (+ j 1))))))
          (let back ((e e)) (if (if (> e i) (%in-blank? (byte-at line (- e 1))) #f) (back (- e 1)) e)))))
    (let go ((i (skip 0)) (t 0) (acc ()))
      (if (stop? i) (reverse acc)
        (let ((e (if (= t 25) (rest-end i) (word-end i))))
          (go (if (= t 25) n (skip e)) (+ t 1) (pair (substring line i e) acc)))))))

(def %in-index-of
  (fn (_ s c)
    (let go ((i (- (byte-len s) 1))) (match ((< i 0) ()) ((= (byte-at s i) c) i) (#t (go (- i 1)))))))

(def %in-first-index (fn (_ s c) (%wget-index s c 0)))

(def %in-socktype
  (fn (_ w)
    (match ((string=? w "stream") 1) ((string=? w "dgram") 2) ((string=? w "rdm") 4)
           ((string=? w "seqpacket") 5) ((string=? w "raw") 3) (#t -1))))

(def %in-builtins (list "echo" "discard" "chargen" "time" "daytime"))

; parse_one_line on TOKENS of line LINENO: the services it names -- one for
; each of a HOST list -- or nil, said as busybox says it.  A HOST: line alone
; sets the host the lines after it default to.
(def %in-parse
  (fn (_ lineno tokens)
    (def err (fn (_) (do (%in-say (string-concat (list "parse error on line " (%cu-int->str lineno) ", line is ignored"))) ())))
    (def t0 (first tokens))
    (def colon (%in-index-of t0 #\:))
    (def host (if (null? colon) %in-default-host (substring t0 0 colon)))
    (def service (if (null? colon) t0 (substring t0 (+ colon 1) (byte-len t0))))
    (if (if (null? colon) #f (if (= (byte-len service) 0) (= (length tokens) 1) #f))
      (do (set! %in-default-host host) ())
      (if (< (length tokens) 6) (err)
        (%in-parse-fields err host service tokens)))))

(def %in-parse-fields
  (fn (_ err host service tokens)
    (def s (vec-make %in-fields ()))
    (%in-set! s %in-host host)
    (%in-set! s %in-service service)
    (%in-set! s %in-type (%in-socktype (%cu-nth 1 tokens)))
    (def proto (%cu-nth 2 tokens))
    (%in-set! s %in-proto proto)
    (def six? (if (> (byte-len proto) 0) (= (byte-at proto (- (byte-len proto) 1)) #\6) #f))
    (def base (if six? (substring proto 0 (- (byte-len proto) 1)) proto))
    (match
      ((string=? proto "unix") (do (%in-set! s %in-family (lit unix)) (%in-parse-wait err s tokens)))
      ((if (>= (byte-len base) 4) (string=? (substring base 0 4) "rpc/") #f)
        (do (%in-say "no support for rpc services") (err)))
      ((if (string=? base "tcp") #t (string=? base "udp"))
        (do (%in-set! s %in-family (if six? (lit inet6) (lit inet)))
            (%in-parse-wait err s tokens)))
      (#t (err)))))

(def %in-parse-wait
  (fn (_ err s tokens)
    (def w (%cu-nth 3 tokens))
    (def dot (%in-first-index w #\.))
    (def max (if (null? dot) %in-max (%in-strtou (substring w (+ dot 1) (byte-len w)))))
    (def word (if (null? dot) w (substring w 0 dot)))
    (def nowait? (if (>= (byte-len word) 2) (string=? (substring word 0 2) "no") #f))
    (if (if (null? max) #t (not (string=? (if nowait? (substring word 2 (byte-len word)) word) "wait"))) (err)
      (do (%in-set! s %in-max-of max)
          (%in-set! s %in-wait (if nowait? 0 1))
          (%in-parse-prog err s tokens)))))

(def %in-parse-prog
  (fn (_ err s tokens)
    (def u (%cu-nth 4 tokens))
    (def sep (let ((d (%in-first-index u #\.))) (if (null? d) (%in-first-index u #\:) d)))
    (%in-set! s %in-user (if (null? sep) u (substring u 0 sep)))
    (%in-set! s %in-group (if (null? sep) () (substring u (+ sep 1) (byte-len u))))
    (def prog (%cu-nth 5 tokens))
    (%in-set! s %in-program prog)
    (def service (%in-get s %in-service))
    (def internal? (if (string=? prog "internal")
                     (if (<= (byte-len service) 7) (if (%in-stream? s) #t (%in-dgram? s)) #f) #f))
    (def args (rest (rest (rest (rest (rest (rest tokens)))))))
    (%in-set! s %in-argv (if (null? args) (list prog) (List take 20 args)))
    (%in-set! s %in-fd -1)
    (%in-set! s %in-count-of 0)
    (%in-set! s %in-time 0)
    (%in-set! s %in-watched #f)
    (def tcp? (if (eq? (%in-get s %in-family) (lit unix)) #f (string=? (substring (%in-get s %in-proto) 0 3) "tcp")))
    (def udp? (if (eq? (%in-get s %in-family) (lit unix)) #f (not tcp?)))
    (match
      ((if internal? (not (List any? (fn (_ b) (string=? b service)) %in-builtins)) #f)
        (do (%in-say (string-append "unknown internal service " service)) (err)))
      ((if internal? (not (eq? (= (%in-get s %in-wait) 0) (%in-stream? s))) #f) (err))
      ((if (%in-stream? s) udp? #f) (err))
      ((if (%in-dgram? s) tcp? #f) (err))
      (#t (do (%in-set! s %in-builtin (if internal? service ()))
              (%in-hosts s))))))

; a HOST list: a copy of the service for each host, in the list's order
(def %in-hosts
  (fn (_ s)
    (map (fn (_ h) (let ((c (Vector from-list (Vector ->list s)))) (do (%in-set! c %in-host h) c)))
         (Str8 split "," (%in-get s %in-host)))))

; --- /etc/services --------------------------------------------------------------------

; bb_get_servport_by_name: NAME's port for PROTO, from a line SERVNAME
; NUM/PROTO [ALIAS...] on which NAME is SERVNAME or an alias; nil when none
(def %in-servport
  (fn (_ name proto)
    (def text (guard (_ ()) (file-read-all %in-services-file)))
    (if (if (null? text) #t (= (byte-len name) 0)) ()
      (let go ((lines (Str8 split "\n" text)))
        (if (null? lines) ()
          (let ((p (%in-servline (first lines) name proto)))
            (if (null? p) (go (rest lines)) p)))))))

(def %in-servline
  (fn (_ line name proto)
    (def hash (%in-first-index line #\#))
    (def words (filter (fn (_ w) (> (byte-len w) 0))
                       (Str8 split " " (Str8 replace "\t" " " (if (null? hash) line (substring line 0 hash))))))
    (if (< (length words) 2) ()
      (let ((np (%cu-nth 1 words)))
        (def slash (%in-first-index np #\/))
        (def n (if (null? slash) () (%in-strtou (substring np 0 slash))))
        (if (if (null? n) #t (if (> n 65535) #t
              (not (string=? (substring np (+ slash 1) (byte-len np)) proto)))) ()
          (if (List any? (fn (_ w) (string=? w name)) (pair (first words) (rest (rest words)))) n ()))))))

; --- addresses ----------------------------------------------------------------------------

(def %in-af (fn (_ fam) (match ((eq? fam (lit inet)) 2) ((eq? fam (lit unix)) 1) (#t (if os-darwin? 30 10)))))

(def %in-zeroed
  (fn (_ n)
    (let ((s (%str-make-raw n)))
      (do (let go ((i 0)) (when (< i n) (do (%cu-ptr-set! (%cu-str->ptr s) i 0 1) (go (+ i 1))))) s))))

; a sockaddr_in6 for the 16 bytes ADDR (nil: any) and PORT, as (BYTES . LEN) --
; a raw buffer's byte-len stops at its first zero byte, so the length goes with it
(def %in-sockaddr6
  (fn (_ addr port)
    (def s (%in-zeroed 28))
    (def p (%cu-str->ptr s))
    (if os-darwin? (do (%cu-ptr-set! p 0 28 1) (%cu-ptr-set! p 1 30 1)) (%cu-ptr-set! p 0 10 1))
    (%cu-ptr-set! p 2 (/ (- port (% port 256)) 256) 1)
    (%cu-ptr-set! p 3 (% port 256) 1)
    (unless (null? addr)
      (let go ((i 0)) (when (< i 16) (do (%cu-ptr-set! p (+ 8 i) (%cu-ptr-ref (%cu-str->ptr addr) i 1) 1) (go (+ i 1))))))
    (pair s 28)))

; a sockaddr_un for PATH, cut to what sun_path holds: (BYTES . LEN)
(def %in-sockaddr-un
  (fn (_ path)
    (def size (if os-darwin? 106 110))
    (def s (%in-zeroed size))
    (def p (%cu-str->ptr s))
    (if os-darwin? (do (%cu-ptr-set! p 0 size 1) (%cu-ptr-set! p 1 1 1)) (%cu-ptr-set! p 0 1 1))
    (let go ((i 0)) (when (if (< i (byte-len path)) (< i (- size 3)) #f)
                      (do (%cu-ptr-set! p (+ 2 i) (byte-at path i) 1) (go (+ i 1)))))
    (pair s size)))

; host_and_af2sockaddr: HOST's address in FAMILY with PORT, or nil said as
; a bad address
(def %in-host-addr
  (fn (_ host port fam)
    (def a
      (if (eq? fam (lit inet))
        (let ((q (if (null? (net-aton host)) (guard (_ ()) (net-resolve host)) host)))
          (if (null? q) () (pair (net-sockaddr q port) 16)))
        (let ((buf (%in-zeroed 16)))
          (if (= (%in-call (%cu-ptr-call (%in-c "inet_pton") (%in-af fam) host (%cu-str->ptr buf))) 1)
            (%in-sockaddr6 buf port) ()))))
    (when (null? a) (%in-say (string-concat (list "bad address '" host "'"))))
    a))

(def %in-same-bytes?
  (fn (_ a b)
    (if (if (null? a) #t (null? b)) #f
      (if (not (= (rest a) (rest b))) #f
        (let go ((i 0))
          (if (>= i (rest a)) #t
            (if (= (%cu-ptr-ref (%cu-str->ptr (first a)) i 1) (%cu-ptr-ref (%cu-str->ptr (first b)) i 1)) (go (+ i 1)) #f)))))))

; --- sockets ---------------------------------------------------------------------------------

(def %in-reuse!
  (fn (_ fd)
    (let ((one (%str-make-raw 4)))
      (do (%cu-ptr-set! (%cu-str->ptr one) 0 1 4)
          (%cu-ptr-call (%in-c "setsockopt") fd (if os-darwin? 65535 1) (if os-darwin? 4 2) (%cu-str->ptr one) 4)))))

; a datagram socket also takes SO_REUSEPORT on Darwin, where SO_REUSEADDR
; alone does not let the socket a nowait child holds share its address
(def %in-reuse-port!
  (fn (_ fd)
    (when os-darwin?
      (let ((one (%str-make-raw 4)))
        (do (%cu-ptr-set! (%cu-str->ptr one) 0 1 4)
            (%cu-ptr-call (%in-c "setsockopt") fd 65535 512 (%cu-str->ptr one) 4))))))

(def %in-bind
  (fn (_ fd addr) (%in-call (%cu-ptr-call (%in-c "bind") fd (%cu-str->ptr (first addr)) (rest addr)))))

(def %in-close!
  (fn (_ s)
    (when (>= (%in-get s %in-fd) 0) (sys-close (%in-get s %in-fd)))
    (%in-set! s %in-fd -1)
    (%in-set! s %in-watched #f)))

(def %in-rearm!
  (fn (_) (when (null? %in-retry-at) (set! %in-retry-at (+ (%in-now) 60)))))

; prepare_socket_fd: the service's socket made, bound and, for a stream,
; listening; a failure said and tried again in a minute
(def %in-open!
  (fn (_ s)
    (def fd (%in-call (%cu-ptr-call (%in-c "socket") (%in-af (%in-get s %in-family)) (%in-get s %in-type) 0)))
    (if (< fd 0) (%in-say (string-append "socket: " (%in-errtext fd)))
      (do (%in-reuse! fd)
          (when (%in-dgram? s) (%in-reuse-port! fd))
          (when (eq? (%in-get s %in-family) (lit unix)) (guard (_ ()) (file-unlink (%in-get s %in-service))))
          (let ((r (%in-bind fd (%in-get s %in-addr))))
            (if (< r 0)
              (do (%in-say (string-concat (list (%in-name s) ": bind: " (%in-errtext r))))
                  (sys-close fd)
                  (%in-rearm!))
              (do (when (%in-stream? s) (%cu-ptr-call (%in-c "listen") fd %in-queue))
                  (%in-set! s %in-fd fd)
                  (%in-set! s %in-watched #t))))))))

; --- reading the config ----------------------------------------------------------------------

(def %in-same-service?
  (fn (_ a b)
    (if (string=? (%in-get a %in-host) (%in-get b %in-host))
      (if (string=? (%in-get a %in-service) (%in-get b %in-service))
        (string=? (%in-get a %in-proto) (%in-get b %in-proto)) #f) #f)))

; reread_config_file: each service the file names kept, changed or added,
; its socket opened; those it no longer names closed and dropped
(def %in-reread!
  (fn (_)
    (set! %in-default-host "*")
    (def text (guard (e (if (eq? (%cu-err-label e) (lit io))
                          (do (%in-say (string-concat (list %in-conf ": " (file-err-text e)))) ())
                          (error e)))
                (file-read-all %in-conf)))
    (unless (null? text)
      (do (map (fn (_ s) (%in-set! s %in-checked #f)) %in-list)
          (map (fn (_ l)
                 (let ((tokens (%in-tokens (rest l))))
                   (unless (null? tokens) (map %in-take! (%in-parse (first l) tokens)))))
               (%in-lines text))
          (map (fn (_ s)
                 (unless (%in-get s %in-checked)
                   (do (%in-close! s)
                       (when (eq? (%in-get s %in-family) (lit unix)) (guard (_ ()) (file-unlink (%in-get s %in-service)))))))
               %in-list)
          (set! %in-list (filter (fn (_ s) (%in-get s %in-checked)) %in-list))))))

; one service from the file: merged into the one already listed for the same
; host, service and protocol, or listed; its address worked out, its socket
; opened when there is none or the address moved
(def %in-take!
  (fn (_ cp)
    (def old (List find (fn (_ s) (%in-same-service? s cp)) %in-list))
    (def s (if (null? old) (do (set! %in-list (pair cp %in-list)) cp) old))
    (unless (null? old)
      (do (when (= (%in-get cp %in-wait) 0) (when (>= (%in-get s %in-fd) 0) (%in-set! s %in-watched #t)))
          (map (fn (_ k) (%in-set! s k (%in-get cp k)))
               (list %in-wait %in-max-of %in-user %in-group %in-program %in-argv))))
    (%in-set! s %in-checked #t)
    (def addr (%in-address s))
    (unless (null? addr)
      (do (unless (%in-same-bytes? addr (%in-get s %in-addr))
            (do (%in-close! s) (%in-set! s %in-addr addr)))
          (when (< (%in-get s %in-fd) 0) (%in-open! s))))))

; the sockaddr the service binds, or nil said as busybox says it
(def %in-address
  (fn (_ s)
    (def fam (%in-get s %in-family))
    (if (eq? fam (lit unix)) (%in-sockaddr-un (%in-get s %in-service))
      (let ((port (let ((n (%in-strtou (%in-get s %in-service))))
                    (if (if (null? n) #f (<= n 65535)) n
                      (%in-servport (%in-get s %in-service) (substring (%in-get s %in-proto) 0 3))))))
        (match
          ((null? port) (do (%in-say (string-append (%in-name s) ": unknown service")) ()))
          ((string=? (%in-get s %in-host) "*")
            (if (eq? fam (lit inet)) (pair (net-sockaddr "0.0.0.0" port) 16) (%in-sockaddr6 () port)))
          (#t (let ((a (%in-host-addr (%in-get s %in-host) port fam)))
                (when (null? a)
                  (%in-say (string-concat (list (%in-name s) ": unknown host '" (%in-get s %in-host) "'"))))
                a)))))))

; --- the builtins ---------------------------------------------------------------------------

(def %in-dontwait (if os-darwin? 128 64))

; a datagram taken without waiting: (DATA COUNT SOCKADDR LEN), or nil
(def %in-recvfrom
  (fn (_ fd n)
    (def buf (%str-make-raw n))
    (def sa (%in-zeroed 128))
    (def len (%str-make-raw 4))
    (%cu-ptr-set! (%cu-str->ptr len) 0 128 4)
    (def r (%in-call (%cu-ptr-call (%in-c "recvfrom") fd (%cu-str->ptr buf) n %in-dontwait
                                   (%cu-str->ptr sa) (%cu-str->ptr len))))
    (if (< r 0) () (list buf r sa (%cu-ptr-ref (%cu-str->ptr len) 0 4)))))

(def %in-sendto
  (fn (_ fd data n from)
    (%cu-ptr-call (%in-c "sendto") fd (%cu-str->ptr data) n 0 (%cu-str->ptr (%cu-nth 2 from)) (%cu-nth 3 from))))

(def %in-eat (fn (_ fd) (%cu-ptr-call (%in-c "recv") fd (%cu-str->ptr (%str-make-raw 256)) 256 %in-dontwait)))

; the bytes ' ' through '~', and a chargen line: 72 of them from POS, around
; the ring, and CRLF
(def %in-ring
  (let go ((c 126) (acc ())) (if (< c 32) (bytes->str acc) (go (- c 1) (pair c acc)))))

(def %in-chargen-line
  (fn (_ pos)
    (def len (byte-len %in-ring))
    (def line (if (<= (+ pos 72) len) (substring %in-ring pos (+ pos 72))
                (string-append (substring %in-ring pos len) (substring %in-ring 0 (- 72 (- len pos))))))
    (string-append line "\r\n")))

; the seconds since 1900, four bytes, the most significant first
(def %in-machtime
  (fn (_)
    (def t (% (+ (%in-now) 2208988800) 4294967296))
    (bytes->str (list (% (/ (- t (% t 16777216)) 16777216) 256) (% (/ (- t (% t 65536)) 65536) 256)
                      (% (/ (- t (% t 256)) 256) 256) (% t 256)))))

(def %in-daytime
  (fn (_)
    (def now (%in-now))
    (string-append (%cu-date-fmt "%a %b %e %H:%M:%S %Y" (%cu-date-split now #f) now) "\r\n")))

; a stream builtin on the connection FD
(def %in-stream-builtin
  (fn (_ name fd)
    (guard (_ ())
      (match
        ((string=? name "echo")
          (let go () (let ((r (Socket recv-run fd 256))) (unless (null? r) (do (net-send-run fd r) (go))))))
        ((string=? name "discard")
          (let go () (unless (null? (Socket recv-run fd 256)) (go))))
        ((string=? name "chargen")
          (let go ((pos 0))
            (do (file-write fd (%in-chargen-line pos))
                (go (if (= (+ pos 1) (byte-len %in-ring)) 0 (+ pos 1))))))
        ((string=? name "time") (File write fd (%in-machtime) 4))
        (#t (file-write fd (%in-daytime)))))))

; a datagram builtin, answering the datagram waiting on FD
(def %in-dgram-builtin
  (fn (_ name fd)
    (match
      ((string=? name "echo")
        (let ((d (%in-recvfrom fd 12288))) (unless (null? d) (when (> (%cu-nth 1 d) 0) (%in-sendto fd (first d) (%cu-nth 1 d) d)))))
      ((string=? name "discard") (%in-eat fd))
      ((string=? name "chargen")
        (let ((d (%in-recvfrom fd 74)))
          (unless (null? d)
            (let ((line (%in-chargen-line %in-ring-pos)))
              (do (set! %in-ring-pos (if (= (+ %in-ring-pos 1) (byte-len %in-ring)) 0 (+ %in-ring-pos 1)))
                  (%in-sendto fd line 74 d))))))
      (#t
        (let ((d (%in-recvfrom fd 256)))
          (unless (null? d)
            (let ((out (if (string=? name "time") (%in-machtime) (%in-daytime))))
              (%in-sendto fd out (if (string=? name "time") 4 (byte-len out)) d))))))))

; --- the children -----------------------------------------------------------------------------

(def %in-nul (bytes->str (list 0)))

; execvp with PROG and ARGV as given, argv[0] among them: the errno it
; failed with
(def %in-exec
  (fn (_ prog argv)
    (def ptr->int (prim-ref (lit ptr) (lit ->int)))
    (def strs (map (fn (_ a) (string-append a %in-nul)) argv))
    (def vec (%in-zeroed (* 8 (+ (length strs) 1))))
    (let go ((i 0) (l strs))
      (unless (null? l)
        (do (%cu-ptr-set! (%cu-str->ptr vec) (* 8 i) (ptr->int (%cu-str->ptr (first l))) 8) (go (+ i 1) (rest l)))))
    (def p (string-append prog %in-nul))
    (%in-call (%cu-ptr-call (%in-c "execvp") (%cu-str->ptr p) (%cu-str->ptr vec)))))

; a child's end: for a datagram service, the datagram that started it eaten
(def %in-exit1
  (fn (_ s fd)
    (unless (%in-stream? s) (%in-eat fd))
    (sys-exit 1)))

; the child for service S: CTRL its stdin and stdout (and stderr, nowait),
; the user it runs as, PROG
(def %in-child
  (fn (_ s ctrl new-udp)
    (%cu-ptr-call (%in-c "setsid"))
    (when (>= new-udp 0)
      (do (sys-close new-udp)
          (let ((d (%in-peek ctrl)))
            (if (null? d) (%in-exit1 s ctrl)
              (%cu-ptr-call (%in-c "connect") ctrl (%cu-str->ptr (%cu-nth 2 d)) (%cu-nth 3 d))))))
    (def user (%in-get s %in-user))
    (def group (%in-get s %in-group))
    (def uid (sys-user-id user))
    (def gid (if (null? group) () (sys-group-id group)))
    (match
      ((null? uid) (do (%in-say (string-append user ": no such user")) (%in-exit1 s ctrl)))
      ((if (null? group) #f (null? gid)) (do (%in-say (string-append group ": no such group")) (%in-exit1 s ctrl)))
      ((if (= %in-uid 0) #f (not (= %in-uid uid))) (do (%in-say "non-root must run services as himself") (%in-exit1 s ctrl)))
      (#t ()))
    (%in-identity! user uid gid)
    (sys-dup2 ctrl 0)
    (unless (= ctrl 0) (sys-close ctrl))
    (sys-dup2 0 1)
    (when (= (%in-get s %in-wait) 0) (sys-dup2 0 2))
    (map (fn (_ o) (let ((fd (%in-get o %in-fd))) (when (if (>= fd 0) (not (= fd ctrl)) #f) (sys-close fd)))) %in-list)
    (unless (= ctrl 3) (sys-close 3))
    (sys-signal 13 0)
    (map (fn (_ n) (sys-signal n 0)) %in-sigs)
    (def r (%in-exec (%in-get s %in-program) (%in-get s %in-argv)))
    (%in-say (string-concat (list "can't execute '" (%in-get s %in-program) "': " (%in-errtext r))))
    (%in-exit1 s 0)))

; the waiting datagram's sender, left in the queue: (DATA COUNT SOCKADDR LEN)
(def %in-peek
  (fn (_ fd)
    (def sa (%in-zeroed 128))
    (def len (%str-make-raw 4))
    (%cu-ptr-set! (%cu-str->ptr len) 0 128 4)
    (def r (%in-call (%cu-ptr-call (%in-c "recvfrom") fd 0 0 (+ 2 %in-dontwait) (%cu-str->ptr sa) (%cu-str->ptr len))))
    (if (< r 0) () (list "" 0 sa (%cu-ptr-ref (%cu-str->ptr len) 0 4)))))

; another user's identity -- initgroups, setgid, setuid -- or, for this
; user, the group alone
(def %in-identity!
  (fn (_ user uid gid)
    (if (not (= uid %in-uid))
      (let ((g (if (null? gid) (sys-user-group user) gid)))
        (do (%cu-ptr-call (%in-c "initgroups") user g)
            (%cu-ptr-call (%in-c "setgid") g)
            (%cu-ptr-call (%in-c "setuid") uid)))
      (unless (null? gid)
        (let ((buf (%str-make-raw 4)))
          (do (%cu-ptr-set! (%cu-str->ptr buf) 0 gid 4)
              (%cu-ptr-call (%in-c "setgid") gid)
              (%cu-ptr-call (%in-c "setgroups") 1 (%cu-str->ptr buf))))))))

; --- a service ready -----------------------------------------------------------------------------

; MAX connections within a minute pause the service: nil when this one is
; refused for it
(def %in-admit?
  (fn (_ s)
    (def max (%in-get s %in-max-of))
    (if (= max 0) #t
      (let ((c (+ (%in-get s %in-count-of) 1)))
        (do (%in-set! s %in-count-of c)
            (match ((= c 1) (do (%in-set! s %in-time (%in-now)) #t))
                   ((< c max) #t)
                   ((<= (- (%in-now) (%in-get s %in-time)) 60)
                     (do (%in-say (string-append (%in-name s) ": too many connections, pausing"))
                         (%in-close! s)
                         (%in-set! s %in-count-of 0)
                         (%in-rearm!)
                         #f))
                   (#t (do (%in-set! s %in-count-of 0) #t))))))))

(def %in-ready
  (fn (_ s)
    (def fd (%in-get s %in-fd))
    (def nowait? (= (%in-get s %in-wait) 0))
    (def accepted
      (if (if nowait? (%in-stream? s) #f)
        (let ((c (%in-call (%cu-ptr-call (%in-c "accept") fd 0 0))))
          (do (when (< c 0) (%in-say (string-concat (list "accept (for " (%in-get s %in-service) "): " (%in-errtext c))))) c))
        -1))
    (def new-udp
      (if (if nowait? (if (%in-dgram? s) (not (eq? (%in-get s %in-family) (lit unix))) #f) #f)
        (let ((u (%in-call (%cu-ptr-call (%in-c "socket") (%in-af (%in-get s %in-family)) 2 0))))
          (if (< u 0) -2
            (do (%in-reuse! u) (%in-reuse-port! u)
                (if (< (%in-bind u (%in-get s %in-addr)) 0) (do (sys-close u) -2) u))))
        -1))
    (match
      ((if (if nowait? (%in-stream? s) #f) (< accepted 0) #f) ())
      ((= new-udp -2) (%in-eat fd))
      (#t (%in-serve s (if (>= accepted 0) accepted fd) accepted new-udp)))))

(def %in-serve
  (fn (_ s ctrl accepted new-udp)
    (def bi (%in-get s %in-builtin))
    (def fork? (if (null? bi) #t (if (%in-stream? s) (not (if (string=? bi "time") #t (string=? bi "daytime"))) #f)))
    (def drop (fn (_) (do (when (>= new-udp 0) (sys-close new-udp)) (when (>= accepted 0) (sys-close accepted)))))
    (if (not fork?)
      (do (if (%in-stream? s) (%in-stream-builtin bi ctrl) (%in-dgram-builtin bi ctrl))
          (when (>= accepted 0) (sys-close accepted)))
      (if (not (%in-admit? s)) (drop)
        (let ((pid (sys-fork)))
          (match
            ((< pid 0) (do (%in-say "fork failed") (drop)))
            ((= pid 0)
              (if (null? bi) (%in-child s ctrl new-udp)
                (do (sys-close (%in-get s %in-fd))
                    (set! %in-quiet? #t)
                    (%in-stream-builtin bi ctrl)
                    (sys-exit 1))))
            (#t
              (do (when (= (%in-get s %in-wait) 1)
                    (do (%in-set! s %in-wait pid) (%in-set! s %in-watched #f)))
                  (when (>= new-udp 0)
                    (do (sys-dup2 new-udp (%in-get s %in-fd)) (sys-close new-udp)))
                  (when (>= accepted 0) (sys-close accepted))))))))))

; --- signals -------------------------------------------------------------------------------------

; reap_child: each child that has ended; a wait service's own said when it
; failed, and the service watched again
(def %in-reap!
  (fn (self)
    (def st (%str-make-raw 4))
    (def pid (%in-call (%cu-ptr-call (%in-c "waitpid") -1 (%cu-str->ptr st) 1)))
    (when (> pid 0)
      (do (let ((s (List find (fn (_ s) (= (%in-get s %in-wait) pid)) %in-list))
                (raw (%cu-ptr-ref (%cu-str->ptr st) 0 4)))
            (unless (null? s)
              (do (match ((if (= (% raw 128) 0) (> (% (%wget-div raw 256) 256) 0) #f)
                           (%in-say (string-concat (list (%in-get s %in-program) ": exit status "
                                                         (%cu-int->str (% (%wget-div raw 256) 256))))))
                         ((if (> (% raw 128) 0) (not (= (% raw 128) 127)) #f)
                           (%in-say (string-concat (list (%in-get s %in-program) ": exit signal "
                                                         (%cu-int->str (% raw 128))))))
                         (#t ()))
                  (%in-set! s %in-wait 1)
                  (when (>= (%in-get s %in-fd) 0) (%in-set! s %in-watched #t)))))
          (self)))))

; retry_network_setup: each service without a socket tried again
(def %in-retry!
  (fn (_)
    (set! %in-retry-at ())
    (map (fn (_ s) (when (if (< (%in-get s %in-fd) 0) (not (null? (%in-get s %in-addr))) #f) (%in-open! s))) %in-list)))

; clean_up_and_exit
(def %in-quit!
  (fn (_)
    (map (fn (_ s)
           (when (>= (%in-get s %in-fd) 0)
             (do (when (eq? (%in-get s %in-family) (lit unix)) (guard (_ ()) (file-unlink (%in-get s %in-service))))
                 (sys-close (%in-get s %in-fd)))))
         %in-list)
    (guard (_ ()) (file-unlink %in-pidfile))
    (sys-exit 0)))

(def %in-signals!
  (fn (_)
    (def take (fn (_ i) (Sys take-signal (%cu-nth i %in-sigs))))
    (when (if (take 3) #t (take 4)) (%in-quit!))
    (when (take 0) (%in-reap!))
    (when (take 1) (%in-reread!))
    (when (if (take 2) #t (if (null? %in-retry-at) #f (>= (%in-now) %in-retry-at))) (%in-retry!))))

(def %in-loop
  (fn (self)
    (%cu-sweep-tick! %cu-sweep-lines)
    (%in-signals!)
    (def watched (filter (fn (_ s) (if (%in-get s %in-watched) (>= (%in-get s %in-fd) 0) #f)) %in-list))
    (def ready (sys-poll (map (fn (_ s) (pair (%in-get s %in-fd) (list (lit in)))) watched) 500))
    (unless (null? ready)
      (map (fn (_ s)
             (when (if (%in-get s %in-watched)
                     (List any? (fn (_ r) (if (= (first r) (%in-get s %in-fd)) (List any? (fn (_ e) (eq? e (lit in))) (rest r)) #f)) ready) #f)
               (%in-ready s)))
           watched))
    (self)))

; --- the applet ------------------------------------------------------------------------------------

(def %cu-inetd
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "inetd" argv))
    (guard (e (if (eq? (Err label e) (lit net))
                (do (file-write 2 (string-concat (list "inetd: " (e msg) "\n"))) 1)
                (error e)))
      (%in-main o))))

(def %in-main
  (fn (_ o)
    (set! %in-uid (sys-getuid))
    (def ops (Opts operands o))
    (set! %in-max (let ((r (Opts value o "-R"))) (if (null? r) 0 (%in-count r))))
    (set! %in-queue (let ((q (Opts value o "-q"))) (if (null? q) 128 (%in-count q))))
    (set! %in-conf (match ((not (null? ops)) (first ops)) ((= %in-uid 0) "/etc/inetd.conf") (#t ())))
    (when (null? %in-conf) (%in-die "non-root must specify config file"))
    (unless (Opts on? o "-f") (%hd-daemonize))
    (set! %in-stderr? (Opts on? o "-e"))
    (unless %in-stderr? (%cu-ptr-call (%in-c "openlog") %in-ident 9 24))
    (when (= %in-uid 0)
      (let ((buf (%str-make-raw 4)))
        (do (%cu-ptr-set! (%cu-str->ptr buf) 0 (sys-getgid) 4)
            (%cu-ptr-call (%in-c "setgroups") 1 (%cu-str->ptr buf)))))
    (guard (_ ())
      (let ((fd (File open %in-pidfile (list (lit wronly) (lit creat) (lit trunc)) 438)))
        (do (file-write fd (string-append (%cu-int->str (sys-getpid)) "\n")) (file-close fd))))
    (set! %in-sigs (map %ts-signal-number (list "CHLD" "HUP" "ALRM" "TERM" "INT")))
    (map (fn (_ n) (Sys catch-signal n)) %in-sigs)
    (sys-signal 13 cu-sig-ign)
    (%in-reread!)
    (%in-loop)))

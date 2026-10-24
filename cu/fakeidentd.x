; # x-coreutils -- the small tools, as applets
;
; ## cu/fakeidentd.x -- fakeidentd: the same ident answer for every query
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; networking/isrv_identd.c: each query's first line -- what comes before its
; first CR or LF, at most 59 bytes, or all of it at its end -- answered with
; "LINE : USERID : UNIX : STRING" and the connection closed.  -i answers the
; one query on stdin and stdout; -w serves the listening socket inetd hands it
; on stdin, and ends once 20 seconds pass with no connection open; otherwise
; it binds port 113 (-b ADDR's address, else every interface) and, without
; -f, leaves the terminal first.  A connection quiet for 20 seconds is closed
; unanswered, as is a -i query, by busybox's alarm.

(module cu/fakeidentd)

(import cu/cli cu-opts)
(import cu/inetd in-af in-bind in-c in-call in-errtext in-now in-percent
  in-reuse! in-sockaddr6)
(import cu/prims append byte-at byte-len cu-nth cu-ptr-call cu-sig-ign
  cu-str->ptr cu-sweep-lines cu-sweep-tick! file-write filter map net-aton
  net-sockaddr net-stdin-socket str-make-raw string-append string-concat
  substring sys-close sys-poll sys-signal)
(import cu/session hd-daemonize)

(def %fi-limit 59)
(def %fi-timeout 20)
(def %fi-user "nobody")
(def %fi-syslog? #f)

(def %fi-say
  (fn (_ msg)
    (if %fi-syslog?
      (cu-ptr-call (in-c "syslog") 3 (in-percent msg))
      (file-write 2 (string-concat (list "fakeidentd: " msg "\n"))))))

(def %fi-die (fn (_ msg) (Err raise (lit net) msg ())))

; the query in TEXT: what comes before its first CR, LF or NUL, or nil when
; none has come and there is room for more
(def %fi-line
  (fn (_ text at-end?)
    (def n (byte-len text))
    (let go ((i 0))
      (match ((>= i n) (if (if at-end? #t (>= n %fi-limit)) text ()))
             ((if (= (byte-at text i) #\return) #t (if (= (byte-at text i) #\newline) #t (= (byte-at text i) 0)))
               (substring text 0 i))
             (#t (go (+ i 1)))))))

(def %fi-answer
  (fn (_ line) (string-concat (list line " : USERID : UNIX : " %fi-user "\r\n"))))

; -i: the query read from stdin as it comes, the answer on stdout
(def %fi-inetd
  (fn (_ stdin-thunk)
    (cu-ptr-call (in-c "alarm") %fi-timeout)
    (let go ((acc ""))
      (let ((r (stdin-thunk (lit chunk))))
        (def piece (if (pair? r) (substring (first r) 0 (rest r)) r))
        (def text (string-append acc piece))
        (def text59 (if (> (byte-len text) %fi-limit) (substring text 0 %fi-limit) text))
        (def line (%fi-line text59 (= (byte-len piece) 0)))
        (if (null? line) (go text59)
          (do (file-write 1 (%fi-answer line))
              (cu-ptr-call (in-c "alarm") 0)
              0))))))

; --- the server ---------------------------------------------------------------------

; create_and_bind_stream_or_die: port 113 on ADDR, or on every interface --
; IPv6's, which takes IPv4 too, where the system has it
(def %fi-bind
  (fn (_ addr)
    (def sa
      (if (null? addr)
        (in-sockaddr6 () 113)
        (if (null? (net-aton addr)) (%fi-die (string-concat (list "bad address '" addr "'")))
          (pair (net-sockaddr addr 113) 16))))
    (def af (if (= (rest sa) 16) 2 (in-af (lit inet6))))
    (def fd (in-call (cu-ptr-call (in-c "socket") af 1 0)))
    (when (< fd 0) (%fi-die (string-append "socket: " (in-errtext fd))))
    (in-reuse! fd)
    (def r (in-bind fd sa))
    (when (< r 0) (%fi-die (string-append "bind: " (in-errtext r))))
    (cu-ptr-call (in-c "listen") fd 5)
    fd))

; a peer: (FD TEXT LAST-HEARD)
(def %fi-close! (fn (_ p) (sys-close (first p))))

; one peer's turn to read: the peer as it now stands, or nil once answered
; or failed
(def %fi-read
  (fn (_ p)
    (def fd (first p))
    (def text (cu-nth 1 p))
    (def room (- %fi-limit (byte-len text)))
    (def buf (str-make-raw (+ room 1)))
    (def r (in-call (cu-ptr-call (in-c "read") fd (cu-str->ptr buf) room)))
    (if (< r 0) (do (%fi-close! p) ())
      (let ((now-text (string-append text (substring buf 0 r))))
        (let ((line (%fi-line now-text (= r 0))))
          (if (null? line) (list fd now-text (in-now))
            (do (guard (_ ()) (file-write fd (%fi-answer line)))
                (%fi-close! p)
                ())))))))

; isrv_run: the listener and the peers polled; LINGER, for -w, the seconds
; with no peer after which the run ends
(def %fi-serve
  (fn (_ lfd linger)
    (let loop ((peers ()) (heard (in-now)))
      (cu-sweep-tick! cu-sweep-lines)
      (def now (in-now))
      (def live (filter (fn (_ p) (if (> (- now (cu-nth 2 p)) %fi-timeout) (do (%fi-close! p) #f) #t)) peers))
      (if (if (> linger 0) (if (null? live) (>= (- now heard) linger) #f) #f) 0
        (let ((ready (sys-poll (map (fn (_ fd) (pair fd (list (lit in)))) (pair lfd (map first live))) 1000)))
          (def ready? (fn (_ fd) (List any? (fn (_ e) (= (first e) fd)) ready)))
          (if (null? ready) (loop live heard)
            (let ((kept (filter (fn (_ p) (not (null? p)))
                                (map (fn (_ p) (if (ready? (first p)) (%fi-read p) p)) live))))
              (loop (if (ready? lfd)
                      (let ((c (in-call (cu-ptr-call (in-c "accept") lfd 0 0))))
                        (if (< c 0) kept (append kept (list (list c "" (in-now))))))
                      kept)
                    (in-now)))))))))

; --- the applet ---------------------------------------------------------------------

(def cu-fakeidentd
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "fakeidentd" argv))
    (guard (e (if (eq? (Err label e) (lit net))
                (do (%fi-say (e msg)) 1)
                (error e)))
      (%fi-main o stdin-thunk))))

(def %fi-main
  (fn (_ o stdin-thunk)
    (def ops (Opts operands o))
    (set! %fi-user (if (null? ops) "nobody" (first ops)))
    (def inetd? (Opts on? o "-i"))
    (def wait? (Opts on? o "-w"))
    (def fiw? (if (Opts on? o "-f") #t (if inetd? #t wait?)))
    (unless fiw?
      (do (hd-daemonize)
          (cu-ptr-call (in-c "openlog") "fakeidentd" 1 24)
          (set! %fi-syslog? #t)))
    (if inetd? (%fi-inetd stdin-thunk)
      (do (sys-signal 13 cu-sig-ign)
          (if wait?
            (let ((fd (net-stdin-socket))) (%fi-serve (if (null? fd) 0 fd) %fi-timeout))
            (%fi-serve (%fi-bind (Opts value o "-b")) 0))))))

(provide cu/fakeidentd cu-fakeidentd)

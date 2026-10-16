; # x-coreutils -- the small tools, as applets
;
; ## cu/sslclient.x -- ssl_client: standard input and output through a TLS session
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; networking/ssl_client.c: a TLS session to HOST (port 443 unless HOST:PORT
; names one), over the descriptors -s FD (and -r FD to read, else the same
; one), or over a pair of pipes to PROG ARGS run with -e; -n SNI names the
; server, by default HOST without its port (busybox's sends HOST:PORT whole,
; which a server may refuse: OpenSSL 3.5 answers it with alert 47).  Then what comes in on standard input is sent and
; what the server sends goes to standard output, until the server closes --
; or, with -s, until standard input ends.  As busybox's, the server is not
; authenticated.  The session is x-lang's TLS 1.3 (Tls13); busybox's speaks
; TLS 1.2, so a server that takes only 1.2 is refused here.

(import x/net/tls13)

(def %sc-say (fn (_ msg) (file-write 2 (string-concat (list "ssl_client: " msg "\n")))))

(def %cu-ssl-client
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "ssl_client" argv))
    (def ops (Opts operands o))
    (def s? (Opts on? o "-s"))
    (def r? (Opts on? o "-r"))
    (def e? (Opts on? o "-e"))
    (if (match ((if e? (if s? #t r?) #f) #t)          ; -e excludes -s and -r
               (e? (null? ops))                         ; -e needs PROG
               ((if s? #t r?) (if s? (not (null? ops)) #t)) ; -s FD alone; -r only with -s
               (#t (if (null? ops) #t (not (null? (rest ops))))))  ; exactly one HOST
      (%cu-usage "ssl_client")
      (guard (e (match ((eq? (Err label e) (lit net)) (do (%sc-say (e msg)) 1))
                       ((eq? (Err label e) (lit io)) (do (%sc-say (e msg)) 1))
                       (#t (error e))))
        (%sc-main o ops e? s?)))))

(def %sc-main
  (fn (_ o ops e? s?)
    (cu-stdin-to-command!)
    (sys-signal 13 cu-sig-ign)
    (def fds
      (match (e? (%sc-run-prog ops))
             (s? (let ((w (%in-count (Opts value o "-s"))))
                   (pair (if (Opts on? o "-r") (%in-count (Opts value o "-r")) w) w)))
             (#t (let ((fd (%cu-dial (first ops) 443))) (pair fd fd)))))
    (def sni (let ((n (Opts value o "-n"))) (if (not (null? n)) n (if (if e? #f (not s?)) (%cu-dial-host (first ops)) ()))))
    (def session (Tls13 over (first fds) (rest fds)
                   (if (null? sni) (list (list (lit insecure))) (list (pair (lit host) sni) (list (lit insecure))))))
    (%sc-copy session (first fds) s? #t)
    0))

; -e PROG ARGS: PROG run on a pair of pipes, (READ . WRITE) to talk to it
(def %sc-run-prog
  (fn (_ argv)
    (def to (sys-pipe))
    (def from (sys-pipe))
    (def pid (sys-fork))
    (when (= pid 0)
      (do (sys-close (rest to)) (sys-close (first from))
          (sys-dup2 (first to) 0) (sys-dup2 (rest from) 1)
          (sys-close (first to)) (sys-close (rest from))
          (let ((r (%in-exec (first argv) argv)))
            (do (%sc-say (string-concat (list "can't execute '" (first argv) "': " (%in-errtext r))))
                (sys-exit 1)))))
    (sys-close (first to))
    (sys-close (rest from))
    (pair (first from) (rest to))))

; tls_run_copy_loop: standard input sent, the server's data to standard
; output; ends at the server's close, or with -s at standard input's end.
; What the session has already read ahead is taken first: poll does not see it.
(def %sc-copy
  (fn (self session in s? stdin?)
    (%cu-sweep-tick! 0)
    (if (Tls13 pending? session)
      (if (%sc-from-server session) (self session in s? stdin?) ())
      (let ((ready (sys-poll (append (if stdin? (list (pair 0 (list (lit in)))) ()) (list (pair in (list (lit in))))) 1000)))
        (def ready? (fn (_ fd) (List any? (fn (_ e) (= (first e) fd)) ready)))
        (match
          ((null? ready) (self session in s? stdin?))
          ((if stdin? (ready? 0) #f)
            (let ((r (file-read-run 0 4096)))
              (if (= (rest r) 0)
                (if s? () (self session in s? #f))
                (do (Tls13 send session (list (first r) 0 (rest r)))
                    (if (ready? in)
                      (if (%sc-from-server session) (self session in s? stdin?) ())
                      (self session in s? stdin?))))))
          (#t (if (%sc-from-server session) (self session in s? stdin?) ())))))))

; a record of the server's data to standard output: #f at its close
(def %sc-from-server
  (fn (_ session)
    (let ((r (Tls13 recv-run session 16384)))
      (if (null? r) #f
        (do (File write 1 (first r) (rest r)) #t)))))

; # x-coreutils -- the small tools, as applets
;
; ## cu/nc.x -- nc, busybox's netcat 1.10
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's nc_bloaty: connect to HOST PORT, or with -l take one connection
; on -p PORT, then copy standard input to the connection and the connection
; to standard output at once -- the platform's poll waits on both -- until
; the connection closes.  Standard input running out shuts the connection's
; write side, so the peer reads end of input while its answer still comes
; back.  -e PROG runs PROG with the connection as its standard input and
; output instead; -z only connects; -o hex-dumps what went each way; -i
; sends a line at a time with a pause before each; -w gives up on a quiet
; connection after two of its waits; -v says what it connected to, and -vv
; also what failed and how much went each way.
;
; The connection is read and written as a file descriptor, a run at a time,
; so every byte crosses -- a NUL too.
;
; What busybox's nc does and this one does not, refused or left unread: UDP
; (-u, -b), -s and a client's -p (binding the local end), -w during the connect
; itself, -lk, -v while listening, which names the peer by a reverse lookup, a
; service name for a port, and sending on once the peer has closed outright.

; --- the command line ------------------------------------------------------------

; ARGV split at -e: (ARGS . PROG), PROG the program and its arguments or nil.
; busybox also reads -e at the end of a cluster of flags that take no value,
; as -lve PROG
(def %nc-split-exec
  (fn (_ argv)
    (let go ((l argv) (acc ()))
      (match
        ((null? l) (pair (reverse acc) ()))
        ((string=? (first l) "-e") (pair (reverse acc) (rest l)))
        ((%nc-cluster-e? (first l))
          (pair (reverse (pair (substring (first l) 0 (- (byte-len (first l)) 1)) acc))
                (rest l)))
        (#t (go (rest l) (pair (first l) acc)))))))

; -XYe: a dash, flags from nuvlkz, then e last
(def %nc-cluster-e?
  (fn (_ s)
    (def n (byte-len s))
    (if (if (> n 2) (if (= (byte-at s 0) #\-) (= (byte-at s (- n 1)) #\e) #f) #f)
      (let go ((i 1))
        (match
          ((= i (- n 1)) #t)
          ((%wget-memv (byte-at s i) (list #\n #\u #\v #\l #\k #\z)) (go (+ i 1)))
          (#t #f)))
      #f)))

; -u, -b (UDP's broadcasts) and -s are not here: refused, rather than read as
; TCP or as no address at all.  -e is split off before the parse.
(def %nc-flags (list "-n" "-v" "-l" "-k" "-z"))
(def %nc-values (list "-p" "-w" "-i" "-o" "-e"))

; how many times FLAG was given: -vv is two
(def %nc-count
  (fn (_ o flag)
    (length (filter (fn (_ f) (string=? f flag)) (rest (Assoc entry (lit on) o))))))

; busybox's usage text, less the banner naming its binary; status 1
(def %nc-usage
  (fn (_)
    (do (file-write 2
          (string-concat
            (list "Usage: " %nc-name " [OPTIONS] HOST PORT  - connect\n"
                  "nc [OPTIONS] -l -p PORT [HOST] [PORT]  - listen\n\n"
                  "\t-e PROG\tRun PROG after connect (must be last)\n"
                  "\t-l\tListen mode, for inbound connects\n"
                  "\t-lk\tWith -e, provides persistent server\n"
                  "\t-p PORT\tLocal port\n"
                  "\t-s ADDR\tLocal address\n"
                  "\t-w SEC\tTimeout for connects and final net reads\n"
                  "\t-i SEC\tDelay interval for lines sent\n"
                  "\t-n\tDon't do DNS resolution\n"
                  "\t-u\tUDP mode\n"
                  "\t-b\tAllow broadcasts\n"
                  "\t-v\tVerbose\n"
                  "\t-o FILE\tHex dump traffic\n"
                  "\t-z\tZero-I/O mode (scanning)\n")))
        1)))

; a port as busybox's bb_lookup_port reads one: digits, or nil
(def %nc-port
  (fn (_ s) (if (null? s) 0 (%wget-digits s))))

; --- the run's state -----------------------------------------------------------

(def %nc-verbose 0)
(def %nc-name "nc")            ; the name run as: nc, or netcat, busybox's other name for it
(def %nc-hex-fd -1)       ; -o's file, -1 when none
(def %nc-wrote-net 0)     ; bytes sent, for -o's offsets and -vv
(def %nc-wrote-out 0)     ; bytes written to stdout

; --- -o: netcat's hex dump -----------------------------------------------------------

; one line of up to 16 bytes: DIR (62, >, sent; 60, <, received), the offset in eight hex digits, the bytes
; in hex padded to 16 columns, then "# " and the bytes, a dot for any outside
; space to tilde
(def %nc-hex-line
  (fn (_ dir off bs)
    (def hex (fn (_ n) (integer->char (if (< n 10) (+ n #\0) (+ n 87)))))
    (def h8 (let go ((v off) (k 8) (acc ()))
              (if (= k 0) acc (go (%wget-div v 16) (- k 1) (pair (hex (% v 16)) acc)))))
    (string-concat
      (list (bytes->str (list dir)) " " (list->string h8) " "
            (string-concat
              (map (fn (_ b) (list->string (list (hex (%wget-div b 16)) (hex (% b 16)) #\space))) bs))
            (%wget-times (* 3 (- 16 (length bs))) #\space)
            "# "
            (list->string (map (fn (_ b) (if (if (> b 31) (< b 127) #f) (integer->char b) #\.)) bs))
            "\n"))))

; a run's bytes into the dump, sixteen a line, from OFFSET
(def %nc-hex
  (fn (_ dir run offset)
    (unless (< %nc-hex-fd 0)
      (let go ((i 0) (off offset))
        (when (< i (rest run))
          (let ((k (if (< (- (rest run) i) 16) (- (rest run) i) 16)))
            (do (file-write %nc-hex-fd
                  (%nc-hex-line dir off
                    (let take ((j (- (+ i k) 1)) (acc ()))
                      (if (< j i) acc
                        (take (- j 1) (pair (& (byte-at (first run) j) 255) acc))))))
                (go (+ i k) (+ off k)))))))))

; --- the copy: busybox's readwrite ---------------------------------------------------

; the first line of a run -- through its newline -- or all of it
(def %nc-line-end
  (fn (_ run)
    (let go ((i 0))
      (match
        ((>= i (rest run)) (rest run))
        ((= (byte-at (first run) i) 10) (+ i 1))
        (#t (go (+ i 1)))))))

; write the first N bytes of RUN to the connection; answers what is left of it
(def %nc-send
  (fn (_ net run n)
    (do (file-write-run net (pair (first run) n))
        (%nc-hex 62 (pair (first run) n) %nc-wrote-net)
        (set! %nc-wrote-net (+ %nc-wrote-net n))
        (if (= n (rest run)) ()
          (let ((rest-bytes (let go ((j (- (rest run) 1)) (acc ()))
                              (if (< j n) acc (go (- j 1) (pair (& (byte-at (first run) j) 255) acc))))))
            (pair (bytes->str rest-bytes) (- (rest run) n)))))))

; copy stdin to NET and NET to stdout until both have ended -- stdin still goes
; to NET after NET has sent all it will -- or until -w's two waits pass with
; nothing heard; PENDING is stdin's bytes read and not yet sent
(def %nc-copy
  (fn (self net net-open? stdin-open? pending wait-ms retries interval)
    (match
      ; -i: a line at a time, the pause after each
      ((if (> interval 0) (not (null? pending)) #f)
        (let ((left (%nc-send net pending (%nc-line-end pending))))
          (do (sys-sleep interval)
              (self net net-open? stdin-open? left wait-ms retries interval))))
      ((not (null? pending))
        (self net net-open? stdin-open? (%nc-send net pending (rest pending))
              wait-ms retries interval))
      ; both ends done: busybox's loop runs while either is open
      ((not (if net-open? #t stdin-open?)) 0)
      (#t
        (let ((ready (sys-poll (append (if stdin-open? (list (pair 0 (list (lit in)))) ())
                                       (if net-open? (list (pair net (list (lit in)))) ()))
                               wait-ms)))
          (match
            ((null? ready)
              (if (= retries 1) 0
                (self net net-open? stdin-open? () wait-ms (- retries 1) interval)))
            ((%nc-ready? ready net)
              (let ((r (file-read-run net 65536)))
                (if (= (rest r) 0)
                  ; the peer has sent all it will; stdin still goes to it
                  (self net #f stdin-open? () wait-ms retries interval)
                  (do (file-write-run 1 r)
                      (%nc-hex 60 r %nc-wrote-out)
                      (set! %nc-wrote-out (+ %nc-wrote-out (rest r)))
                      (self net net-open? stdin-open? () wait-ms retries interval)))))
            (#t
              (let ((r (file-read-run 0 65536)))
                (if (= (rest r) 0)
                  (do (guard (_ ()) (net-shutdown net))
                      (self net net-open? #f () wait-ms retries interval))
                  (self net net-open? stdin-open? r wait-ms retries interval))))))))))

(def %nc-ready?
  (fn (_ ready fd)
    (if (null? ready) #f (if (= (first (first ready)) fd) #t (%nc-ready? (rest ready) fd)))))

; the connection becomes PROG's standard input and output, and PROG replaces nc
(def %nc-exec
  (fn (_ net prog)
    (do (sys-dup2 net 0)
        (sys-dup2 0 1)
        (sys-exec (first prog) (rest prog))
        (file-write 2 (string-concat (list %nc-name ": can't execute '" (first prog) "'\n")))
        (sys-exit 1))))

; --- the applet ----------------------------------------------------------------

(def %nc-connect-or-fail
  (fn (_ host ip port)
    (guard (e (do (when (if (> %nc-verbose 1) #t
                          (if (> %nc-verbose 0) (not (eq? (file-err-sym e) (lit econnrefused))) #f))
                    (file-write 2 (string-concat
                      (list %nc-name ": " host " (" ip ":" (%cu-int->str port) "): " (%wget-err-text e) "\n"))))
                  ()))
      (net-connect ip port))))

(def %nc-run
  (fn (_ o ops prog)
    (def listen? (Opts on? o "-l"))
    (def lport (%nc-port (Opts value o "-p")))
    (def w (let ((v (Opts value o "-w"))) (if (null? v) 0 (%wget-digits v))))
    (def interval (let ((v (Opts value o "-i"))) (if (null? v) 0 (%wget-digits v))))
    (def wait-ms (if (> w 0) (* w 1000) -1))
    (set! %nc-verbose (+ (%nc-count o "-v") 0))
    (set! %nc-wrote-net 0)
    (set! %nc-wrote-out 0)
    (sys-signal 13 cu-sig-ign)                    ; SIGPIPE, as busybox ignores it
    (when (if (not (null? (Opts value o "-o"))) (null? prog) #f)
      (set! %nc-hex-fd (file-open-write (Opts value o "-o"))))
    (def net
      (if listen?
        (let ((lfd (net-listen lport)))
          (let ((c (net-accept lfd)))
            (do (net-close lfd) c)))
        (let ((host (first ops)) (port (%nc-port (if (null? (rest ops)) () (first (rest ops))))))
          (do (when (null? port)
                (%net-die (string-concat (list "bad port '" (first (rest ops)) "'"))))
              (let ((ip (guard (_ ()) (net-resolve host))))
                (do (when (null? ip) (%net-die (string-concat (list "bad address '" host "'"))))
                    (let ((fd (%nc-connect-or-fail host ip port)))
                      (do (when (if (> %nc-verbose 0) (not (null? fd)) #f)
                            (file-write 2 (string-concat
                              (list host " (" ip ":" (%cu-int->str port) ") open\n"))))
                          fd))))))))
    (def st
      (match
        ((null? net) 1)
        ((not (null? prog)) (%nc-exec net prog))
        ((Opts on? o "-z") (do (net-close net) 0))
        (#t (do (when (> interval 0) (sys-sleep interval))
                (let ((r (%nc-copy net #t #t () wait-ms 2 interval)))
                  (do (net-close net) r))))))
    (when (> %nc-verbose 1)
      (file-write 2 (string-concat
        (list "sent " (%cu-int->str %nc-wrote-net) ", rcvd " (%cu-int->str %nc-wrote-out) "\n"))))
    (unless (< %nc-hex-fd 0) (do (file-close %nc-hex-fd) (set! %nc-hex-fd -1)))
    st))

(def %cu-nc (fn (_ argv stdin-thunk) (%nc-main "nc" argv)))
(def %cu-netcat (fn (_ argv stdin-thunk) (%nc-main "netcat" argv)))

(def %nc-main
  (fn (_ name argv)
    (set! %nc-name name)
    (def split (%nc-split-exec argv))
    (def o (Opts parse %nc-flags %nc-values (first split)))
    (def ops (Opts operands o))
    (match
      ((not (null? (Opts unknown o))) (%cu-refuse-option name (Opts unknown o)))
      ((if (null? ops) (not (Opts on? o "-l")) #f) (%nc-usage))
      ((> (length ops) 2) (%nc-usage))
      (#t
        (guard (e (if (eq? (Err label e) (lit net))
                    (do (file-write 2 (string-concat (list name ": " (e msg) "\n"))) 1)
                    (error e)))
          (%nc-run o ops (rest split)))))))

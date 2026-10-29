; # x-coreutils -- the small tools, as applets
;
; ## cu/pscan.x -- pscan: busybox's TCP port scanner
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox 1.36.1's pscan (networking/pscan.c).  HOST, a name or an address,
; is scanned over the TCP ports -p MIN (1 unless named) to -P MAX (1024): a
; non-blocking connect to each, then a one-byte write tried until it goes
; through ("open"), the connection is refused ("closed"), or four round
; trips pass ("blocked").  The open ports are written, with -c the closed
; and with -b the blocked too, each with its service name from
; getservbyport ("unknown" where it has none); a footer counts the closed,
; the open and the rest.  The round-trip estimate starts at -t's timeout
; and follows each port's time, four times over, held between -T's minimum
; and the timeout, both in milliseconds.  A connect that fails in another
; way ends the run with its errno's text.

(module cu/pscan)

(import cu/cli cu-opts cu-usage)
(import cu/inet inet-service inet-set! inet-zeros)
(import cu/inetd in-call)
(import cu/ping pn-be16! pn-div pn-family pn-now pn-number pn-resolve
  pn-setopt pn-sol-socket)
(import cu/prims cu-err-label cu-int->str cu-libc-sym cu-ptr-call cu-ptr-ref
  cu-str->ptr file-write length libc-strerror string-append sys-usleep)
(import cu/text cu-pad-left)

(def %ps-die
  (fn (_ msg)
    (do (file-write 2 (%str-concat (list "pscan: " msg "\n")))
        (Err raise (lit pscan) msg ()))))

(def %ps-eagain (if os-darwin? 35 11))
(def %ps-einprogress (if os-darwin? 36 115))
(def %ps-econnrefused (if os-darwin? 61 111))

; the errno a libc call that answered R left, 0 where it went through
(def %ps-errno (fn (_ r) (if (< r 0) (Err errno-of r) 0)))

; Darwin's write to a refused connection fails EPIPE, and raises SIGPIPE
; unless SO_NOSIGPIPE is set; the refusal waits in SO_ERROR.  Linux's write
; answers it, as busybox reads it.
(def %ps-epipe 32)
(def %ps-write-errno
  (fn (_ s r)
    (def errno (%ps-errno r))
    (if (if os-darwin? (= errno %ps-epipe) #f)
      (let ((v (inet-zeros 4)) (n (inet-zeros 4)))
        (do (inet-set! n 0 4 4)
            (cu-ptr-call (cu-libc-sym "getsockopt") s pn-sol-socket 4103 (cu-str->ptr v) (cu-str->ptr n))
            (let ((e (cu-ptr-ref (cu-str->ptr v) 0 4))) (if (= e 0) errno e))))
      errno)))

; one port's line: its number right-justified in five, "tcp", its state and
; its service
(def %ps-line
  (fn (_ port state)
    (let ((name (inet-service port 0)))
      (file-write 1 (%str-concat
        (list (cu-pad-left (cu-int->str port) 5) "\ttcp\t" state "\t" (if (null? name) "unknown" name) "\n"))))))

; one port of the scan, as pscan_main's loop body: the socket SA (of LEN
; bytes) gets PORT, a non-blocking connect is made and a byte written until
; the port reads open, closed or blocked.  Answers (STATE . DIFF), STATE 'open,
; 'closed or 'blocked and DIFF the microseconds it took, which the next
; round-trip estimate follows.
(def %ps-port
  (fn (_ sa len port rtt-4)
    (pn-be16! (cu-str->ptr sa) 2 port)
    (def s (in-call (cu-ptr-call (cu-libc-sym "socket") (pn-family sa) 1 0)))
    (when (< s 0) (%ps-die (string-append "socket: " (libc-strerror (Err errno-of s)))))
    (Sys nonblock! s)
    (when os-darwin? (pn-setopt s pn-sol-socket 4130 1))
    (def start (pn-now))
    (def write-byte (fn (_) (in-call (cu-ptr-call (cu-libc-sym "write") s (cu-str->ptr " ") 1))))
    ; the write after a sleep, or at once where the connect went through
    (def try-write
      (fn (_ again)
        (let ((diff (- (pn-now) start)))
          (let ((w (write-byte)))
            (if (>= w 0) (pair (lit open) diff) (again (%ps-write-errno s w) diff))))))
    (def wait
      (fn (self errno diff)
        (match
          ((= errno %ps-econnrefused) (pair (lit closed) diff))
          ((> diff rtt-4) (pair (lit blocked) diff))
          (#t (do (sys-usleep (pn-div rtt-4 8)) (try-write self))))))
    (def c (in-call (cu-ptr-call (cu-libc-sym "connect") s (cu-str->ptr sa) len)))
    (def errno (%ps-errno c))
    (def result
      (match
        ((= c 0) (try-write wait))
        ((if (= errno %ps-eagain) #f (if (= errno %ps-einprogress) #f (not (= errno %ps-econnrefused))))
          (do (cu-ptr-call (cu-libc-sym "close") s) (%ps-die (libc-strerror errno))))
        (#t (wait errno 0))))
    (cu-ptr-call (cu-libc-sym "close") s)
    result))

(def %ps-main
  (fn (_ argv)
    (def o (cu-opts "pscan" argv))
    (def ops (Opts operands o))
    (unless (= (length ops) 1) (Err raise (lit pscan-usage) "usage" ()))
    (def host (first ops))
    (def arg (fn (_ flag default) (let ((v (Opts value o flag))) (if (null? v) default v))))
    ; busybox's order: the max, the min against it, then the timing bounds
    ; (INT_MAX/1000/4), each in microseconds
    (def max-port (pn-number (arg "-P" "1024") 1 65535 %ps-die))
    (def min-port (pn-number (arg "-p" "1") 1 max-port %ps-die))
    (def min-rtt (* 1000 (pn-number (arg "-T" "5") 1 536870 %ps-die)))
    (def timeout (* 1000 (pn-number (arg "-t" "5000") 1 536870 %ps-die)))
    (def show-closed (Opts on? o "-c"))
    (def show-blocked (Opts on? o "-b"))
    (def lsa (pn-resolve host 0 0 %ps-die))
    (file-write 1 (%str-concat
      (list "Scanning " host " ports " (cu-int->str min-port) " to " (cu-int->str max-port) "\n"
            " Port\tProto\tState\tService\n")))
    (let go ((port min-port) (rtt-4 timeout) (closed 0) (open 0))
      (if (> port max-port)
        (do (file-write 1 (%str-concat
              (list (cu-int->str closed) " closed, " (cu-int->str open) " open, "
                    (cu-int->str (- (+ (- max-port min-port) 1) (+ closed open)))
                    " timed out (or blocked) ports\n")))
            0)
        (let ((r (%ps-port (first lsa) (rest lsa) port rtt-4)))
          (do
            (match
              ((eq? (first r) (lit open)) (%ps-line port "open"))
              ((if (eq? (first r) (lit closed)) show-closed #f) (%ps-line port "closed"))
              ((if (eq? (first r) (lit blocked)) show-blocked #f) (%ps-line port "blocked"))
              (#t ()))
            ; up quickly, down slowly, between the minimum and the timeout
            (let ((next (* 4 (rest r))))
              (go (+ port 1)
                  (match ((< next min-rtt) min-rtt) ((> next timeout) timeout) (#t next))
                  (if (eq? (first r) (lit closed)) (+ closed 1) closed)
                  (if (eq? (first r) (lit open)) (+ open 1) open)))))))))

(def cu-pscan
  (fn (_ argv stdin-thunk)
    (guard (e (match ((eq? (cu-err-label e) (lit pscan-usage)) (cu-usage "pscan"))
                     ((eq? (cu-err-label e) (lit pscan)) 1)
                     (#t (error e))))
      (%ps-main argv))))

(provide cu/pscan cu-pscan)

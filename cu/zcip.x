; # x-coreutils -- the small tools, as applets
;
; ## cu/zcip.x -- zcip: a ZeroConf link-local address, probed, announced, defended
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's zcip (networking/zcip.c), RFC 3927.  IFACE is given an address
; on 169.254/16, or -l's /16: -r's first, else one picked at random from
; the range less its first and last 256.  After a wait of up to a second
; it is probed three times, one to two seconds apart, with ARP requests
; from 0.0.0.0; then announced three times, two seconds apart; then
; SCRIPT is run as "SCRIPT config" with ip set, and with -q the run ends.
; Otherwise the address is watched: a host claiming it is answered once,
; and a second claim within ten seconds runs "SCRIPT deconfig" and starts
; over.  A claim seen while probing or announcing picks a new address
; after a wait that grows with the conflicts.  SCRIPT is first run as
; "SCRIPT init"; interface names IFACE for every run.
;
; The addresses are picked by the C library's rand, seeded from the
; interface's hardware address, so the same interface tries the same
; addresses in the same order; musl's rand, which busybox is built on, is
; the 64-bit generator kept here.  Without -f the run goes to the
; background once the interface is bound, and says what it does to
; syslog; LOGGING=none says nothing, LOGGING=syslog only to syslog.
; AF_PACKET is Linux's; elsewhere the socket is refused as Linux refuses
; an unknown family.

(module cu/zcip)

(import cu/cli cu-opts cu-usage)
(import cu/inet inet-aton inet-dotted inet-set! inet-zeros)
(import cu/inetd in-call in-percent)
(import cu/ping pn-byte pn-now)
(import cu/prims byte-at byte-len cu-err-label cu-int->str cu-libc-sym
  cu-ptr-call cu-ptr-ref cu-stdin-to-command! cu-str->ptr file-close
  file-write libc-strerror string-append string-concat string=? sys-dup2
  sys-getenv sys-pipe sys-poll sys-setenv)

; --- saying ----------------------------------------------------------------------------

(def %zc-stdio #t)
(def %zc-syslog #f)
(def %zc-child #f)               ; the background run, which exits, never returns

(def %zc-log
  (fn (_ level msg)
    (do (when %zc-stdio (file-write 2 (string-concat (list "zcip: " msg "\n"))))
        (when %zc-syslog (cu-ptr-call (cu-libc-sym "syslog") level (in-percent msg))))))
(def %zc-say (fn (_ msg) (%zc-log 3 msg)))
(def %zc-info (fn (_ msg) (%zc-log 6 msg)))
(def %zc-status 0)
(def %zc-end (fn (_ status) (do (set! %zc-status status) (Err raise (lit zcip) "end" ()))))
(def %zc-die (fn (_ msg) (do (%zc-say msg) (%zc-end 1))))
(def %zc-errno-die (fn (_ what r) (%zc-die (string-concat (list what ": " (libc-strerror (Err errno-of r)))))))

; --- musl's rand -----------------------------------------------------------------------

; the seed, 64 bits as two halves of 32
(def %zc-hi 0)
(def %zc-lo 0)

; the low 32 bits of A * B, each under 2^32, in 16-bit limbs
(def %zc-mul32
  (fn (_ a b)
    (def a0 (& a 65535))
    (def a1 (>> a 16))
    (def b0 (& b 65535))
    (def b1 (>> b 16))
    (& (+ (* a0 b0) (<< (& (+ (* a0 b1) (* a1 b0)) 65535) 16)) 4294967295)))

; the full 64 bits of A * B, each under 2^32: (HIGH . LOW)
(def %zc-mul64
  (fn (_ a b)
    (def a0 (& a 65535))
    (def a1 (>> a 16))
    (def b0 (& b 65535))
    (def b1 (>> b 16))
    (def mid (+ (* a0 b1) (* a1 b0)))
    (def low (+ (* a0 b0) (<< (& mid 65535) 16)))
    (pair (& (+ (>> low 32) (>> mid 16) (* a1 b1)) 4294967295) (& low 4294967295))))

; srand: the seed S - 1, S unsigned
(def %zc-srand (fn (_ s) (do (set! %zc-hi 0) (set! %zc-lo (& (- s 1) 4294967295)))))

; rand: seed = 6364136223846793005 * seed + 1, the top 31 bits answered
(def %zc-rand
  (fn (_)
    (def ah 1481765933)              ; 0x5851f42d
    (def al 1284865837)              ; 0x4c957f2d
    (def ll (%zc-mul64 al %zc-lo))
    (def hi (& (+ (first ll) (%zc-mul32 ah %zc-lo) (%zc-mul32 al %zc-hi)) 4294967295))
    (def lo (+ (rest ll) 1))
    (set! %zc-lo (& lo 4294967295))
    (set! %zc-hi (if (> lo 4294967295) (& (+ hi 1) 4294967295) hi))
    (>> %zc-hi 1)))

(def %zc-delay (fn (_ secs) (% (%zc-rand) (* secs 1000))))

; --- the addresses ---------------------------------------------------------------------

; inet_aton's addresses are kept as they lie in memory, the first byte
; lowest; the range and the address picked are kept in host order
(def %zc-swap
  (fn (_ n)
    (+ (<< (& n 255) 24) (<< (& (>> n 8) 255) 16) (<< (& (>> n 16) 255) 8) (& (>> n 24) 255))))
(def %zc-dotted (fn (_ host) (inet-dotted (%zc-swap host))))

(def %zc-net 0)                  ; the range, host order

; pick_nip: an address in the range, less its first and last 256
(def %zc-pick
  (fn (self)
    (let ((tmp (& (%zc-rand) 65535)))
      (if (> tmp 65023) (self) (+ %zc-net 256 tmp)))))

; --- the packets -----------------------------------------------------------------------

(def %zc-fd -1)
(def %zc-to ())                  ; the sockaddr bound, and sent to
(def %zc-mac ())                 ; six bytes
(def %zc-buf ())

(def %zc-put-be32!
  (fn (_ b at n)
    (do (inet-set! b at (& (>> n 24) 255) 1) (inet-set! b (+ at 1) (& (>> n 16) 255) 1)
        (inet-set! b (+ at 2) (& (>> n 8) 255) 1) (inet-set! b (+ at 3) (& n 255) 1))))
(def %zc-be32
  (fn (_ b at)
    (let ((p (cu-str->ptr b)))
      (+ (<< (pn-byte p at) 24) (<< (pn-byte p (+ at 1)) 16) (<< (pn-byte p (+ at 2)) 8) (pn-byte p (+ at 3))))))
(def %zc-copy!
  (fn (_ to at from from-at n)
    (let go ((i 0)) (when (< i n) (do (inet-set! to (+ at i) (pn-byte (cu-str->ptr from) (+ from-at i)) 1) (go (+ i 1)))))))
(def %zc-same?
  (fn (_ a at b b-at n)
    (let go ((i 0)) (match ((>= i n) #t)
                           ((= (pn-byte (cu-str->ptr a) (+ at i)) (pn-byte (cu-str->ptr b) (+ b-at i))) (go (+ i 1)))
                           (#t #f)))))

; send_arp_request: an ARP request from our hardware address and SOURCE,
; broadcast, for TARGET at TARGET-MAC (our own, or none)
(def %zc-send!
  (fn (_ source target-mac? target)
    (def p (inet-zeros 42))
    (let go ((i 0)) (when (< i 6) (do (inet-set! p i 255 1) (go (+ i 1)))))
    (%zc-copy! p 6 %zc-mac 0 6)
    (inet-set! p 12 8 1) (inet-set! p 13 6 1)
    (inet-set! p 15 1 1) (inet-set! p 16 8 1)
    (inet-set! p 18 6 1) (inet-set! p 19 4 1) (inet-set! p 21 1 1)
    (%zc-copy! p 22 %zc-mac 0 6)
    (%zc-put-be32! p 28 source)
    (when target-mac? (%zc-copy! p 32 %zc-mac 0 6))
    (%zc-put-be32! p 38 target)
    (let ((r (in-call (cu-ptr-call (cu-libc-sym "sendto") %zc-fd (cu-str->ptr p) 42 0 (cu-str->ptr %zc-to) 16))))
      (when (< r 0) (%zc-errno-die "sendto" r)))))

; --- the script ------------------------------------------------------------------------

(def %zc-iface "")
(def %zc-script "")

; run: SCRIPT WORD, with ip set where HOST is not 0; its status, or minus
; errno where it could not be run.  The child writes exec's errno down a
; pipe closed on exec, so an end-of-file there is a script that ran.
(def %zc-run
  (fn (_ word host)
    (def addr (if (= host 0) "" (%zc-dotted host)))
    (%zc-info (string-concat (list word " " %zc-iface (if (= host 0) "" (string-append " " addr)))))
    (def fds (sys-pipe))
    (cu-ptr-call (cu-libc-sym "fcntl") (rest fds) 2 1)
    (def pid (Sys fork))
    (when (= pid 0)
      (do (guard (_ (Sys exit 111))
            (do (file-close (first fds))
                (sys-setenv "interface" %zc-iface)
                (unless (= host 0) (sys-setenv "ip" addr))
                (cu-stdin-to-command!)
                (Sys exec %zc-script (list word))
                (let ((err (Err errno-of (- 0 1))) (b (inet-zeros 4)))
                  (do (inet-set! b 0 err 4)
                      (cu-ptr-call (cu-libc-sym "write") (rest fds) (cu-str->ptr b) 4)))))
          (Sys exit 111)))
    (file-close (rest fds))
    (def b (inet-zeros 4))
    (def got (in-call (cu-ptr-call (cu-libc-sym "read") (first fds) (cu-str->ptr b) 4)))
    (file-close (first fds))
    (def status (Sys wait pid))
    (match ((= got 4)
            (let ((err (cu-ptr-ref (cu-str->ptr b) 0 4)))
              (do (%zc-say (string-concat (list word " " %zc-iface ": " (libc-strerror err))))
                  (- 0 err))))
           ((= status 0) 0)
           (#t (do (%zc-say (string-concat (list "script " %zc-script " " word " failed, exitcode="
                                                 (cu-int->str (& status 255)))))
                   status)))))

; --- the negotiation -------------------------------------------------------------------

; the states
(def %zc-probe 0)
(def %zc-announce 1)
(def %zc-monitor 2)
(def %zc-defend 3)

(def %zc-quit #f)
(def %zc-chosen 0)
(def %zc-state 0)
(def %zc-nsent 0)
(def %zc-conflicts 0)
(def %zc-timeout 0)              ; milliseconds; -1 for none
(def %zc-deadline 0)             ; microseconds

(def %zc-new-probe! (fn (_) (do (set! %zc-chosen (%zc-pick)) (set! %zc-nsent 0) (set! %zc-state %zc-probe))))

(def %zc-send-announce!
  (fn (_)
    (do (set! %zc-nsent (+ %zc-nsent 1))
        (set! %zc-timeout 2000)
        (%zc-send! %zc-chosen #t %zc-chosen))))

; the poll timed out: the next step of the state
(def %zc-step
  (fn (_)
    (match ((= %zc-state %zc-probe)
            (if (< %zc-nsent 3)
              (do (set! %zc-nsent (+ %zc-nsent 1))
                  (set! %zc-timeout (+ 1000 (%zc-delay 1)))
                  (%zc-send! 0 #f %zc-chosen))
              (do (set! %zc-nsent 0) (set! %zc-state %zc-announce) (%zc-send-announce!))))
           ((if (= %zc-state %zc-announce) (< %zc-nsent 3) #f) (%zc-send-announce!))
           ((= %zc-state %zc-announce)
            (do (%zc-run "config" %zc-chosen)
                (when %zc-quit (%zc-end 0))
                (set! %zc-timeout -1)
                (set! %zc-state %zc-monitor)))
           (#t (do (set! %zc-timeout -1) (set! %zc-state %zc-monitor))))))

; a packet came: a claim on the address, answered as the state says
(def %zc-packet
  (fn (_)
    (def p %zc-buf)
    (def op (| (<< (pn-byte (cu-str->ptr p) 20) 8) (pn-byte (cu-str->ptr p) 21)))
    (def theirs (not (%zc-same? p 22 %zc-mac 0 6)))
    (def conflict
      (if (not theirs) 0
        (| (if (= (%zc-be32 p 28) %zc-chosen) 1 0)
           (if (if (= op 1) (if (= (%zc-be32 p 28) 0) (= (%zc-be32 p 38) %zc-chosen) #f) #f) 2 0))))
    (when (if (if (= (pn-byte (cu-str->ptr p) 12) 8) (= (pn-byte (cu-str->ptr p) 13) 6) #f)
            (if (if (= op 1) #t (= op 2)) (> conflict 0) #f) #f)
      (match ((<= %zc-state %zc-announce)
              (do (set! %zc-conflicts (+ %zc-conflicts 1))
                  (set! %zc-timeout (+ 1000 (* 2 (%zc-delay %zc-conflicts))))
                  (%zc-new-probe!)))
             ((= (& conflict 1) 0) ())
             ((= %zc-state %zc-monitor)
              (do (set! %zc-timeout 10000)
                  (set! %zc-state %zc-defend)
                  (%zc-send! %zc-chosen #t %zc-chosen)))
             (#t (do (%zc-run "deconfig" %zc-chosen)
                     (set! %zc-conflicts 0)
                     (set! %zc-timeout 0)
                     (%zc-new-probe!)))))))

; the poll: nil where the timeout passed, else what the socket is ready for
(def %zc-wait
  (fn (self)
    (def ms (if (< %zc-timeout 0) -1
              (let ((left (- %zc-deadline (pn-now)))) (if (< left 0) 0 (/ (- left (% left 1000)) 1000)))))
    (let ((r (sys-poll (list (pair %zc-fd (list (lit in)))) ms)))
      (match ((pair? r) (rest (first r)))
             ((< %zc-timeout 0) (self))
             ((< (pn-now) %zc-deadline) (self))
             (#t ())))))

(def %zc-loop
  (fn (self)
    (when (= %zc-timeout 0) (set! %zc-timeout (%zc-delay 1)))
    (when (>= %zc-timeout 0) (set! %zc-deadline (+ (pn-now) (* %zc-timeout 1000))))
    (def ready (%zc-wait))
    (if (null? ready) (%zc-step)
      (do (when (> %zc-timeout 0)
            (let ((left (- %zc-deadline (pn-now))))
              (set! %zc-timeout (| (if (< left 0) 0 (/ (- left (% left 1000)) 1000)) 1))))
          (match ((List find (fn (_ e) (eq? e (lit in))) ready)
                  (do (let go ((i 0)) (when (< i 42) (do (inet-set! %zc-buf i 0 1) (go (+ i 1)))))
                      (let ((r (in-call (cu-ptr-call (cu-libc-sym "read") %zc-fd (cu-str->ptr %zc-buf) 42))))
                        (if (< r 0) (%zc-errno-die "read error" r) (%zc-packet)))))
                 ((List find (fn (_ e) (eq? e (lit err))) ready)
                  (do (%zc-say (string-concat (list "iface " %zc-iface " is down")))
                      (when (>= %zc-state %zc-monitor) (%zc-run "deconfig" %zc-chosen))
                      (%zc-end 1)))
                 (#t ()))))
    (Heap collect)
    (self)))

; --- the run ---------------------------------------------------------------------------

; bb_daemonize: the caller's run ends here with 0; the child, in a session
; of its own on /dev/null, goes on
(def %zc-daemonize
  (fn (_)
    (def pid (Sys fork))
    (when (> pid 0) (%zc-end 0))
    (set! %zc-child #t)
    (cu-stdin-to-command!)
    (cu-ptr-call (cu-libc-sym "setsid"))
    (let ((fd (File open "/dev/null" (lit rdwr))))
      (do (sys-dup2 fd 0) (sys-dup2 fd 1) (sys-dup2 fd 2)
          (when (> fd 2) (file-close fd))))))

(def %zc-main
  (fn (_ argv)
    (def o (cu-opts "zcip" argv))
    (def ops (Opts operands o))
    (unless (if (pair? ops) (if (pair? (rest ops)) (null? (rest (rest ops))) #f) #f)
      (Err raise (lit zcip-usage) "usage" ()))
    (def fg (if (Opts on? o "-f") #t (Opts on? o "-v")))
    (set! %zc-quit (Opts on? o "-q"))
    (set! %zc-fd
      (if os-darwin? (%zc-die (string-append "socket(AF_PACKET,10,1544): " (libc-strerror 47)))
        (let ((fd (in-call (cu-ptr-call (cu-libc-sym "socket") 17 10 1544))))
          (if (< fd 0) (%zc-errno-die "socket(AF_PACKET,10,1544)" fd) fd))))
    (unless fg
      (do (cu-ptr-call (cu-libc-sym "openlog") "zcip" 0 24)
          (set! %zc-syslog #t)))
    (let ((mode (sys-getenv "LOGGING")))
      (match ((null? mode) ())
             ((string=? mode "none") (do (set! %zc-stdio #f) (set! %zc-syslog #f)))
             ((string=? mode "syslog") (do (set! %zc-stdio #f) (set! %zc-syslog #t)))
             (#t ())))
    (let ((net (inet-aton (let ((l (Opts value o "-l"))) (if (null? l) "169.254.0.0" l)))))
      (if (if (null? net) #t (not (= (& (%zc-swap net) 65535) 0)))
        (%zc-die "invalid network address")
        (set! %zc-net (%zc-swap net))))
    (set! %zc-chosen 0)
    (let ((r (Opts value o "-r")))
      (unless (null? r)
        (let ((ip (inet-aton r)))
          (if (if (null? ip) #t (not (= (& (%zc-swap ip) 4294901760) %zc-net)))
            (%zc-die "invalid link address")
            (set! %zc-chosen (%zc-swap ip))))))
    (set! %zc-iface (first ops))
    (set! %zc-script (first (rest ops)))
    (sys-setenv "interface" %zc-iface)
    (unless (= (%zc-run "init" 0) 0) (%zc-end 1))
    (set! %zc-to (inet-zeros 16))
    (let copy ((i 0)) (when (if (< i (byte-len %zc-iface)) (< i 13) #f)
                        (do (inet-set! %zc-to (+ 2 i) (byte-at %zc-iface i) 1) (copy (+ i 1)))))
    (let ((r (in-call (cu-ptr-call (cu-libc-sym "bind") %zc-fd (cu-str->ptr %zc-to) 16))))
      (when (< r 0) (%zc-errno-die "bind" r)))
    (def ifr (inet-zeros 40))
    (let copy ((i 0)) (when (if (< i (byte-len %zc-iface)) (< i 15) #f)
                        (do (inet-set! ifr i (byte-at %zc-iface i) 1) (copy (+ i 1)))))
    (let ((r (in-call (cu-ptr-call (cu-libc-sym "ioctl") %zc-fd 35111 (cu-str->ptr ifr)))))
      (when (< r 0) (%zc-errno-die "ioctl 0x8927 failed" r)))
    (set! %zc-mac (inet-zeros 6))
    (%zc-copy! %zc-mac 0 ifr 18 6)
    (%zc-srand (cu-ptr-ref (cu-str->ptr %zc-mac) 2 4))
    (unless fg
      (do (%zc-daemonize)
          (%zc-info (string-append "start, interface " %zc-iface))))
    (set! %zc-buf (inet-zeros 42))
    (set! %zc-conflicts 0)
    (set! %zc-timeout 0)
    (if (= %zc-chosen 0) (%zc-new-probe!) (do (set! %zc-nsent 0) (set! %zc-state %zc-probe)))
    (%zc-loop)))

(def cu-zcip
  (fn (_ argv stdin-thunk)
    (set! %zc-fd -1) (set! %zc-stdio #t) (set! %zc-syslog #f) (set! %zc-child #f)
    (def status
      (guard (e (match ((eq? (cu-err-label e) (lit zcip-usage)) (cu-usage "zcip"))
                       ((eq? (cu-err-label e) (lit zcip)) %zc-status)
                       (#t (do (when %zc-child (Sys exit 1))
                               (unless (< %zc-fd 0) (cu-ptr-call (cu-libc-sym "close") %zc-fd))
                               (error e)))))
        (%zc-main argv)))
    (when %zc-child (Sys exit status))
    (unless (< %zc-fd 0) (cu-ptr-call (cu-libc-sym "close") %zc-fd))
    (set! %zc-fd -1)
    status))

(provide cu/zcip cu-zcip)

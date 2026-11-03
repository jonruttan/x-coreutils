; # x-coreutils -- the small tools, as applets
;
; ## cu/arping.x -- arping: ARP requests, and the replies timed
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's arping (networking/arping.c).  DST_IP is sent an ARP request
; out of -I's interface, eth0 unless named, once a second, broadcast until
; a reply names its hardware address and unicast after, -b broadcasting
; throughout; each reply is written with the address it came from and its
; time.  The run ends after -c requests, after -w seconds, at the first
; reply with -f, or on SIGINT, and the counts close it; the status is 1
; where nothing replied.  -D probes for a duplicate from 0.0.0.0, its status
; 1 where one replied; -U announces DST_IP's address as ours, -A in replies;
; -s names the sender's address; -q leaves out all but the errors.
;
; busybox reads its options into a mask whose bits two of them share: -c
; lands on the bit that marks the run unicast, so with -c no request counts
; as a broadcast.  That is kept.  Its SIGALRM ticks become one poll loop
; over the socket, the tick and SIGINT.  AF_PACKET is Linux's; elsewhere
; the socket is refused as Linux refuses an unknown family.

(module cu/arping)

(import cu/cli cu-opts cu-usage)
(import cu/inet inet-aton inet-set! inet-zeros)
(import cu/inetd in-call in-dontwait)
(import cu/ping pn-be16! pn-bind-device pn-byte pn-div pn-ms pn-now pn-number
  pn-resolve pn-setopt pn-sol-socket)
(import cu/prims byte-at byte-len cu-err-label cu-int->str cu-libc-sym
  cu-ptr-call cu-ptr-ref cu-ptr-set! cu-str->ptr cu-string-type cvt file-write
  libc-strerror map string-append sys-poll sys-signal)
(import cu/text cu-pad-zero)

(def %ap-say (fn (_ msg) (file-write 2 (%str-concat (list "arping: " msg "\n")))))
(def %ap-status 1)               ; xfunc_error_retval: 2 once the options are read
(def %ap-die (fn (_ msg) (do (%ap-say msg) (Err raise (lit arping) msg ()))))
(def %ap-errno-die (fn (_ what r) (%ap-die (%str-concat (list what ": " (libc-strerror (Err errno-of r)))))))
(def %ap-done (fn (_ status) (do (set! %ap-status status) (Err raise (lit arping-done) "done" ()))))
(def %ap-out (fn (_ s) (file-write 1 s)))

; --- the run's state -----------------------------------------------------------------

(def %ap-fd -1)
(def %ap-dad #f)                 ; -D
(def %ap-unsolicited #f)         ; -U, and -A
(def %ap-advert #f)              ; -A
(def %ap-quiet #f)
(def %ap-quit #f)                ; -f, and -D
(def %ap-bcast #f)               ; -b
(def %ap-unicasting #f)          ; set by the first reply, and by -c
(def %ap-count -1)
(def %ap-timeout 0)              ; microseconds, 0 for none
(def %ap-start 0)
(def %ap-last 0)
(def %ap-tick 0)                 ; the clock the next tick is due at
(def %ap-src ())                 ; four bytes each
(def %ap-dst ())
(def %ap-me ())                  ; sockaddr_ll, 20 bytes: family, protocol, ifindex,
(def %ap-he ())                  ; hatype, pkttype, halen, addr
(def %ap-halen 0)
(def %ap-sent 0)
(def %ap-brd-sent 0)
(def %ap-received 0)
(def %ap-brd-recv 0)
(def %ap-req-recv 0)
(def %ap-buf ())
(def %ap-from ())
(def %ap-alen ())

(def %ap-dotted
  (fn (_ b at) (Str8 join "." (List map (fn (_ k) (cu-int->str (pn-byte (cu-str->ptr b) (+ at k)))) (list 0 1 2 3)))))
(def %ap-mac
  (fn (_ b at)
    (Str8 join ":" (List map (fn (_ k) (cu-pad-zero (cvt (pn-byte (cu-str->ptr b) (+ at k)) cu-string-type 16) 2))
                             (list 0 1 2 3 4 5)))))
(def %ap-copy!
  (fn (_ to at from from-at n)
    (let go ((i 0)) (when (< i n) (do (cu-ptr-set! (cu-str->ptr to) (+ at i) (pn-byte (cu-str->ptr from) (+ from-at i)) 1) (go (+ i 1)))))))
(def %ap-same?
  (fn (_ a at b b-at n)
    (let go ((i 0)) (match ((>= i n) #t)
                           ((= (pn-byte (cu-str->ptr a) (+ at i)) (pn-byte (cu-str->ptr b) (+ b-at i))) (go (+ i 1)))
                           (#t #f)))))
(def %ap-zero? (fn (_ b) (= (cu-ptr-ref (cu-str->ptr b) 0 4) 0)))

; --- sending and the ticks -----------------------------------------------------------

; send_pack: the ARP request, or with -A the reply, from us to HE
(def %ap-send!
  (fn (_)
    (def n (+ 8 (* 2 (+ %ap-halen 4))))
    (def b (inet-zeros 256))
    (def p (cu-str->ptr b))
    (pn-be16! p 0 1)
    (pn-be16! p 2 2048)
    (cu-ptr-set! p 4 %ap-halen 1)
    (cu-ptr-set! p 5 4 1)
    (pn-be16! p 6 (if %ap-advert 2 1))
    (%ap-copy! b 8 %ap-me 12 %ap-halen)
    (%ap-copy! b (+ 8 %ap-halen) %ap-src 0 4)
    (%ap-copy! b (+ 12 %ap-halen) (if %ap-advert %ap-me %ap-he) 12 %ap-halen)
    (%ap-copy! b (+ 12 (* 2 %ap-halen)) %ap-dst 0 4)
    (let ((r (in-call (cu-ptr-call (cu-libc-sym "sendto") %ap-fd p n 0 (cu-str->ptr %ap-he) 20))))
      (when (= r n)
        (do (set! %ap-last (pn-now))
            (set! %ap-sent (+ %ap-sent 1))
            (unless %ap-unicasting (set! %ap-brd-sent (+ %ap-brd-sent 1))))))))

; finish: the counts, and the status
(def %ap-finish
  (fn (_)
    (sys-signal 2 1)
    (unless %ap-quiet
      (%ap-out (%str-concat (list "Sent " (cu-int->str %ap-sent) " probe(s) (" (cu-int->str %ap-brd-sent) " broadcast(s))\n"
                                    "Received " (cu-int->str %ap-received) " response(s) (" (cu-int->str %ap-req-recv)
                                    " request(s), " (cu-int->str %ap-brd-recv) " broadcast(s))\n"))))
    (%ap-done (match (%ap-dad (if (> %ap-received 0) 1 0))
                     (%ap-unsolicited 0)
                     (#t (if (> %ap-received 0) 0 1))))))

; catcher: a tick, a second after the last
(def %ap-catcher
  (fn (_)
    (def now (pn-now))
    (when (= %ap-start 0) (set! %ap-start now))
    (when (if (= %ap-count 0) #t (if (> %ap-timeout 0) (> (- now %ap-start) %ap-timeout) #f)) (%ap-finish))
    (when (> %ap-count 0) (set! %ap-count (- %ap-count 1)))
    (when (if (= %ap-last 0) #t (> (- now %ap-last) 500000))
      (do (%ap-send!)
          (when (if (= %ap-count 0) %ap-unsolicited #f) (%ap-finish))))
    (set! %ap-tick (+ now 1000000))))

; --- receiving -----------------------------------------------------------------------

; recv_pack: LEN bytes in the buffer, from the sockaddr_ll in %ap-from
(def %ap-recv-pack
  (fn (_ len)
    (def b %ap-buf)
    (def p (cu-str->ptr b))
    (def ftype (pn-byte (cu-str->ptr %ap-from) 10))
    (def hatype (| (pn-byte (cu-str->ptr %ap-from) 8) (<< (pn-byte (cu-str->ptr %ap-from) 9) 8)))
    (def be (fn (_ i) (| (<< (pn-byte p i) 8) (pn-byte p (+ i 1)))))
    (def op (be 6))
    (def hln (pn-byte p 4))
    (def sha 8)
    (def spa (+ 8 hln))
    (def tha (+ 12 hln))
    (def tpa (+ 12 (* 2 hln)))
    (when (if (> ftype 2) #f
            (if (if (= op 1) #t (= op 2))
              (if (if (= (be 0) hatype) #t (if (= hatype 774) (= (be 0) 1) #f))
                (if (= (be 2) 2048) (if (= (pn-byte p 5) 4) (if (= hln %ap-halen) (>= len (+ 8 (* 2 (+ 4 hln)))) #f) #f) #f)
                #f)
              #f))
      (when (if (%ap-same? %ap-dst 0 b spa 4)
              (if %ap-dad
                (not (if (%ap-same? b sha %ap-me 12 %ap-halen) #t (if (%ap-zero? %ap-src) #f (not (%ap-same? %ap-src 0 b tpa 4)))))
                (if (%ap-same? %ap-src 0 b tpa 4) (%ap-same? b tha %ap-me 12 hln) #f))
              #f)
        (do (unless %ap-quiet
              (let ((other (not (%ap-same? b tpa %ap-src 0 4))))
                (%ap-out (%str-concat
                  (list (if (= ftype 0) "Uni" "Broad") "cast re" (if (= op 2) "ply" "quest") " from " (%ap-dotted b spa)
                        " [" (%ap-mac b sha) "]"
                        (if other (string-append "for " (%ap-dotted b tpa)) "")
                        (if (%ap-same? b tha %ap-me 12 hln) ""
                          (%str-concat (list (if other "" " for") " [" (%ap-mac b tha) "]")))
                        (if (= %ap-last 0) " UNSOLICITED?\n"
                          (string-append " " (string-append (pn-ms (- (pn-now) %ap-last)) "ms\n"))))))))
            (set! %ap-received (+ %ap-received 1))
            (unless (= ftype 0) (set! %ap-brd-recv (+ %ap-brd-recv 1)))
            (when (= op 1) (set! %ap-req-recv (+ %ap-req-recv 1)))
            (when %ap-quit (%ap-finish))
            (unless %ap-bcast
              (do (%ap-copy! %ap-he 12 b sha %ap-halen) (set! %ap-unicasting #t))))))))

; the replies taken until the run ends
(def %ap-loop
  (fn (self)
    (when (Sys take-signal 2) (%ap-finish))
    (def now (pn-now))
    (if (>= now %ap-tick) (%ap-catcher)
      (let ((wait (let ((ms (pn-div (+ (- %ap-tick now) 999) 1000))) (if (> ms 250) 250 ms))))
        (unless (null? (sys-poll (list (pair %ap-fd (list (lit in)))) wait))
          (do (inet-set! %ap-alen 0 20 4)
              (let ((r (in-call (cu-ptr-call (cu-libc-sym "recvfrom") %ap-fd (cu-str->ptr %ap-buf) 4096 in-dontwait
                                             (cu-str->ptr %ap-from) (cu-str->ptr %ap-alen)))))
                (match ((>= r 0) (%ap-recv-pack r))
                       ((if (= (Err errno-of r) 4) #t (= (Err errno-of r) 11)) ())
                       (#t (%ap-say (string-append "recvfrom: " (libc-strerror (Err errno-of r)))))))))))
    (self)))

; --- the run ---------------------------------------------------------------------------

; ioctl on the packet socket with an ifreq naming DEVICE; the result, the
; ifreq after it
(def %ap-ifreq
  (fn (_ device req)
    (let ((ifr (inet-zeros 40)))
      (do (let copy ((i 0)) (when (if (< i (byte-len device)) (< i 15) #f)
                              (do (inet-set! ifr i (byte-at device i) 1) (copy (+ i 1)))))
          (pair (in-call (cu-ptr-call (cu-libc-sym "ioctl") %ap-fd req (cu-str->ptr ifr))) ifr)))))

(def %ap-check (fn (_ r what) (when (< r 0) (%ap-errno-die what r))))

; the probe socket: a source named is bound to, to check it is ours; none
; named, a UDP connect to DST_IP out of DEVICE finds the address the
; kernel would send from
(def %ap-probe-src!
  (fn (_ device)
    (def pfd (in-call (cu-ptr-call (cu-libc-sym "socket") 2 2 0)))
    (def sa (inet-zeros 16))
    (def len (inet-zeros 4))
    (%ap-check pfd "socket(AF_INET,2,0)")
    (pn-bind-device pfd device %ap-say)
    (inet-set! sa 0 2 2)
    (if (not (%ap-zero? %ap-src))
      (do (%ap-copy! sa 4 %ap-src 0 4)
          (%ap-check (in-call (cu-ptr-call (cu-libc-sym "bind") pfd (cu-str->ptr sa) 16)) "bind"))
      (let ((r (do (pn-be16! (cu-str->ptr sa) 2 1025) (%ap-copy! sa 4 %ap-dst 0 4) (pn-setopt pfd pn-sol-socket 5 1))))
        (do (when (< r 0) (%ap-say (string-append "setsockopt(SO_DONTROUTE): " (libc-strerror (Err errno-of r)))))
            (%ap-check (in-call (cu-ptr-call (cu-libc-sym "connect") pfd (cu-str->ptr sa) 16))
                       (%str-concat (list "can't connect to remote host (" (%ap-dotted %ap-dst 0) ")")))
            (inet-set! len 0 16 4)
            (%ap-check (in-call (cu-ptr-call (cu-libc-sym "getsockname") pfd (cu-str->ptr sa) (cu-str->ptr len))) "getsockname")
            (unless (= (cu-ptr-ref (cu-str->ptr sa) 0 2) 2) (%ap-die "no IP address configured"))
            (%ap-copy! %ap-src 0 sa 4 4))))
    (cu-ptr-call (cu-libc-sym "close") pfd)))

(def %ap-main
  (fn (_ argv)
    (set! %ap-fd
      (if os-darwin? (%ap-die (string-append "socket(AF_PACKET,2,0): " (libc-strerror 47)))
        (let ((fd (in-call (cu-ptr-call (cu-libc-sym "socket") 17 2 0))))
          (if (< fd 0) (%ap-errno-die "socket(AF_PACKET,2,0)" fd) fd))))
    (def o (cu-opts "arping" argv))
    (def ops (Opts operands o))
    (def c (Opts value o "-c"))
    (set! %ap-count (if (null? c) -1 (pn-number c 0 2147483647 %ap-die)))
    (unless (if (pair? ops) (null? (rest ops)) #f) (Err raise (lit arping-usage) "usage" ()))
    (def w (Opts value o "-w"))
    (set! %ap-timeout (if (null? w) 0 (+ (* (pn-number w 0 1073 %ap-die) 1000000) 500000)))
    (set! %ap-dad (Opts on? o "-D"))
    (set! %ap-advert (Opts on? o "-A"))
    (set! %ap-unsolicited (if %ap-advert #t (Opts on? o "-U")))
    (set! %ap-quiet (Opts on? o "-q"))
    (set! %ap-quit (if %ap-dad #t (Opts on? o "-f")))
    (set! %ap-bcast (Opts on? o "-b"))
    (set! %ap-unicasting (not (null? c)))
    (def device (let ((v (Opts value o "-I"))) (if (null? v) "eth0" v)))
    (def source (Opts value o "-s"))
    (set! %ap-status 2)
    (def not-arpable
      (fn (_ why) (do (%ap-say (%str-concat (list "interface " device " " why))) (%ap-done (if %ap-dad 0 2)))))
    (def idx (%ap-ifreq device 35123))
    (when (< (first idx) 0) (%ap-errno-die (%str-concat (list "interface " device " not found")) (first idx)))
    (def flags (let ((f (%ap-ifreq device 35091)))
                 (if (< (first f) 0) (%ap-errno-die "ioctl 0x8913 failed" (first f)) (cu-ptr-ref (cu-str->ptr (rest f)) 16 2))))
    (when (= (& flags 1) 0) (%ap-die (%str-concat (list "interface " device " is down"))))
    (unless (= (& flags 136) 0) (not-arpable "is not ARPable"))
    (set! %ap-dst (let ((sa (first (pn-resolve (first ops) 2 0 %ap-die)))) (let ((b (inet-zeros 4))) (do (%ap-copy! b 0 sa 4 4) b))))
    (set! %ap-src (inet-zeros 4))
    (unless (null? source)
      (let ((a (inet-aton source)))
        (if (null? a) (%ap-die (string-append "invalid source address " source)) (inet-set! %ap-src 0 a 4))))
    (when (if %ap-unsolicited (if (not %ap-dad) (%ap-zero? %ap-src) #f) #f) (%ap-copy! %ap-src 0 %ap-dst 0 4))
    (when (if (not %ap-dad) #t (not (%ap-zero? %ap-src))) (%ap-probe-src! device))
    (set! %ap-me (inet-zeros 20))
    (inet-set! %ap-me 0 17 2)
    (pn-be16! (cu-str->ptr %ap-me) 2 2054)
    (inet-set! %ap-me 4 (cu-ptr-ref (cu-str->ptr (rest idx)) 16 4) 4)
    (let ((r (in-call (cu-ptr-call (cu-libc-sym "bind") %ap-fd (cu-str->ptr %ap-me) 20))))
      (when (< r 0) (%ap-errno-die "bind" r)))
    (let ((len (inet-zeros 4)))
      (do (inet-set! len 0 20 4)
          (cu-ptr-call (cu-libc-sym "getsockname") %ap-fd (cu-str->ptr %ap-me) (cu-str->ptr len))))
    (set! %ap-halen (pn-byte (cu-str->ptr %ap-me) 11))
    (when (= %ap-halen 0) (not-arpable "is not ARPable (no ll address)"))
    (set! %ap-he (inet-zeros 20))
    (%ap-copy! %ap-he 0 %ap-me 0 20)
    (let fill ((i 0)) (when (< i %ap-halen) (do (inet-set! %ap-he (+ 12 i) 255 1) (fill (+ i 1)))))
    (unless %ap-quiet
      (%ap-out (%str-concat (list "ARPING " (%ap-dotted %ap-dst 0) " from " (%ap-dotted %ap-src 0) " " device "\n"))))
    (set! %ap-buf (inet-zeros 4096))
    (set! %ap-from (inet-zeros 20))
    (set! %ap-alen (inet-zeros 4))
    (Sys catch-signal 2)
    (%ap-catcher)
    (%ap-loop)))

(def cu-arping
  (fn (_ argv stdin-thunk)
    (set! %ap-fd -1) (set! %ap-status 1) (set! %ap-start 0) (set! %ap-last 0)
    (set! %ap-sent 0) (set! %ap-brd-sent 0) (set! %ap-received 0) (set! %ap-brd-recv 0) (set! %ap-req-recv 0)
    (def status
      (guard (e (match ((eq? (cu-err-label e) (lit arping-usage)) (cu-usage "arping"))
                       ((eq? (cu-err-label e) (lit arping)) %ap-status)
                       ((eq? (cu-err-label e) (lit arping-done)) %ap-status)
                       (#t (do (sys-signal 2 0) (unless (< %ap-fd 0) (cu-ptr-call (cu-libc-sym "close") %ap-fd)) (error e)))))
        (%ap-main argv)))
    (sys-signal 2 0)
    (unless (< %ap-fd 0) (cu-ptr-call (cu-libc-sym "close") %ap-fd))
    status))

(provide cu/arping cu-arping)

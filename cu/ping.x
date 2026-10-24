; # x-coreutils -- the small tools, as applets
;
; ## cu/ping.x -- ping and ping6: ICMP echo requests, and the replies timed
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's ping with FEATURE_FANCY_PING (networking/ping.c).  HOST, named or
; numeric, -4 or -6 choosing the family, is sent an echo request over a raw
; socket every -i seconds, -c of them or until -w's deadline; each reply is
; written `N bytes from ADDR: seq=S ttl=T time=MS ms`, a repeat marked
; (DUP!), and the statistics close the run, at the last reply asked for,
; after -W's wait for the last, or on SIGINT.  The status is 1 where nothing
; came back, or -w ended the run short of -c.  -A sends the next request as a
; reply comes; -s sets the data length, -p its byte, -t the TTL; -I names the
; interface to bind to, or the source address.  ping6 is ping -6.
;
; busybox times out with SIGALRM; here one poll loop waits on the socket, the
; send timer and SIGINT together.

(module cu/ping)

(import cu/cli cu-families cu-opts cu-usage)
(import cu/inet inet-aton inet-set! inet-zeros)
(import cu/inetd in-c in-call in-dontwait in-strtou)
(import cu/prims byte-at byte-len cu-err-label cu-int->ptr cu-int->str
  cu-ptr->str cu-ptr-call cu-ptr-ref cu-ptr-set! cu-ptr-word cu-str->ptr
  file-write libc-strerror map reverse str-make-raw string-append
  string-concat string=? substring sys-getpid sys-poll sys-signal wget-digits)
(import cu/telnetd td-ptr->int)
(import cu/text cu-pad-zero)

(def %pn-applet "ping")
(def %pn-say (fn (_ msg) (file-write 2 (string-concat (list %pn-applet ": " msg "\n")))))
(def %pn-die (fn (_ msg) (do (%pn-say msg) (Err raise (lit ping) msg ()))))
(def %pn-usage (fn (_) (Err raise (lit ping-usage) "usage" ())))
(def %pn-errno-die (fn (_ what r) (%pn-die (string-concat (list what ": " (libc-strerror (Err errno-of r)))))))

(def %pn-af6 (if os-darwin? 30 10))
(def %pn-sol-socket (if os-darwin? 65535 1))

; --- the run's state -----------------------------------------------------------------

(def %pn-fd -1)
(def %pn-v6 #f)
(def %pn-sa ())                  ; the target's sockaddr, and its length
(def %pn-salen 0)
(def %pn-host "")
(def %pn-datalen 56)
(def %pn-count 0)
(def %pn-ntx 0)
(def %pn-nrx 0)
(def %pn-nrep 0)
(def %pn-tmin ())                ; in microseconds; nil before the first time
(def %pn-tmax 0)
(def %pn-tsum 0)
(def %pn-id 0)
(def %pn-pattern 0)
(def %pn-deadline 0)             ; the clock -w ends the run at, 0 for none
(def %pn-interval 1000000)
(def %pn-timeout 10)
(def %pn-quiet #f)
(def %pn-verbose #f)
(def %pn-ttl 0)
(def %pn-again #f)               ; -A
(def %pn-timer ())               ; (send . AT) or (stats . AT), or nil
(def %pn-pkt ())
(def %pn-dups ())                ; rcvd_tbl: a bit for each of 1024 sequence numbers
(def %pn-status 0)

(def %pn-now (fn (_) (let ((t (Sys time-of-day))) (+ (* 1000000 (first t)) (rest t)))))
(def %pn-div (fn (_ a b) (/ (- a (% a b)) b)))
(def %pn-byte (fn (_ p i) (& (cu-ptr-ref p i 1) 255)))
(def %pn-be16 (fn (_ p i) (| (<< (%pn-byte p i) 8) (%pn-byte p (+ i 1)))))
(def %pn-be16! (fn (_ p i v) (do (cu-ptr-set! p i (& (>> v 8) 255) 1) (cu-ptr-set! p (+ i 1) (& v 255) 1))))
(def %pn-at (fn (_ p o) (cu-int->ptr (+ (td-ptr->int p) o))))

; N microseconds as %u.%03u milliseconds
(def %pn-ms
  (fn (_ n) (string-concat (list (cu-int->str (%pn-div n 1000)) "." (cu-pad-zero (cu-int->str (% n 1000)) 3)))))

; N bytes of BYTE: the send buffer, filled once a run -- the header and the
; clock are written over it at each send
(def %pn-filled
  (fn (_ n byte)
    (let ((b (str-make-raw n)))
      (do (let fill ((i 0)) (when (< i n) (do (cu-ptr-set! (cu-str->ptr b) i byte 1) (fill (+ i 1))))) b))))

; setsockopt with an int
(def %pn-setopt
  (fn (_ fd level opt v)
    (let ((b (inet-zeros 4)))
      (do (inet-set! b 0 v 4) (in-call (cu-ptr-call (in-c "setsockopt") fd level opt (cu-str->ptr b) 4))))))

; --- numbers ---------------------------------------------------------------------------

(def %pn-range-die
  (fn (_ s lo hi)
    (%pn-die (string-concat (list "number " s " is not in " (cu-int->str lo) ".." (cu-int->str hi) " range")))))

; xatou_range: S as a decimal number from LO to HI; past UINT_MAX it is no number
(def %pn-number
  (fn (_ s lo hi)
    (let ((n (wget-digits s)))
      (match ((if (null? n) #t (> n 4294967295)) (%pn-die (string-concat (list "invalid number '" s "'"))))
             ((if (< n lo) #t (> n hi)) (%pn-range-die s lo hi))
             (#t n)))))

; xstrtou_range base 16: S, a 0x before it allowed, from 0 to 255
(def %pn-hex-byte
  (fn (_ s)
    (def n (byte-len s))
    (def from (if (if (> n 2) (if (= (byte-at s 0) #\0) (= (| (byte-at s 1) 32) #\x) #f) #f) 2 0))
    (def digit (fn (_ c) (match ((if (>= c #\0) (<= c #\9) #f) (- c #\0))
                                ((if (>= (| c 32) #\a) (<= (| c 32) #\f) #f) (+ 10 (- (| c 32) #\a)))
                                (#t ()))))
    (let go ((i from) (v 0))
      (match ((>= i n) (if (= i 0) (%pn-die (string-concat (list "invalid number '" s "'")))
                         (if (> v 255) (%pn-range-die s 0 255) v)))
             ((null? (digit (byte-at s i))) (%pn-die (string-concat (list "invalid number '" s "'"))))
             (#t (go (+ i 1) (+ (* v 16) (digit (byte-at s i)))))))))

; xatoul_sfx with the duration suffixes: S's seconds as a multiplier, or the
; run ended naming S
(def %pn-seconds
  (fn (_ s)
    (def n (byte-len s))
    (def last (if (> n 0) (byte-at s (- n 1)) 0))
    (def scale (match ((= last #\s) 1) ((= last #\m) 60) ((= last #\h) 3600) ((= last #\d) 86400) (#t ())))
    (let ((v (wget-digits (if (null? scale) s (substring s 0 (- n 1))))))
      (if (if (null? v) #t (> v 4294967295)) (%pn-die (string-concat (list "invalid number '" s "'")))
        (* v (if (null? scale) 1 scale))))))

; parse_duration_str, FLOAT_DURATION: -i's seconds as microseconds, at most
; INT_MAX/1000000 seconds.  With a dot, the digits and dots strtod reads, a
; bad one the usage, and the suffix read as "1" and it.
(def %pn-duration
  (fn (_ s)
    (def dot (%pn-index s #\. 0))
    (def us
      (if (null? dot) (* (%pn-seconds s) 1000000)
        (let ((len (let go ((i 0)) (if (if (< i (byte-len s)) (if (= (byte-at s i) #\.) #t (if (>= (byte-at s i) #\0) (<= (byte-at s i) #\9) #f)) #f) (go (+ i 1)) i))))
          (let ((num (substring s 0 len)) (sfx (substring s len (byte-len s))))
            (let ((d (%pn-index num #\. 0)))
              (let ((whole (substring num 0 d)) (frac (substring num (+ d 1) (byte-len num))))
                (if (if (= (+ (byte-len whole) (byte-len frac)) 0) #t (not (null? (%pn-index frac #\. 0)))) (%pn-usage)
                  (let ((mult (%pn-seconds (string-append "1" sfx)))
                        (f6 (wget-digits (substring (string-append frac "000000") 0 6))))
                    (* mult (+ (* (if (= (byte-len whole) 0) 0 (wget-digits whole)) 1000000) f6))))))))))
    (if (> us 2147000000) 2147000000 us)))

; --- the address -----------------------------------------------------------------------

(def %pn-index
  (fn (_ s c from)
    (let go ((i from)) (match ((>= i (byte-len s)) ()) ((= (byte-at s i) c) i) (#t (go (+ i 1)))))))
(def %pn-rindex
  (fn (_ s c)
    (let go ((i (- (byte-len s) 1))) (match ((< i 0) ()) ((= (byte-at s i) c) i) (#t (go (- i 1)))))))

; str2sockaddr's host: HOST without its :PORT or [...]:PORT, the port checked
(def %pn-host-part
  (fn (_ org)
    (def port-check
      (fn (_ p) (let ((n (in-strtou p))) (when (if (null? n) #t (> n 65535)) (%pn-die (string-concat (list "bad port '" p "'")))))))
    (if (if (> (byte-len org) 0) (= (byte-at org 0) #\[) #f)
      (let ((h (substring org 1 (byte-len org))))
        (let ((cp (%pn-index h #\] 0)))
          (match
            ((if (null? cp) #t (if (< (+ cp 1) (byte-len h)) (not (= (byte-at h (+ cp 1)) #\:)) #f))
              (%pn-die (string-concat (list "bad address '" org "'"))))
            ((= (+ cp 1) (byte-len h)) (substring h 0 cp))
            (#t (do (port-check (substring h (+ cp 2) (byte-len h))) (substring h 0 cp))))))
      (let ((cp (%pn-rindex org #\:)))
        (if (if (null? cp) #t (not (= (%pn-index org #\: 0) cp))) org
          (do (port-check (substring org (+ cp 1) (byte-len org))) (substring org 0 cp)))))))

(def %pn-sockaddr
  (fn (_ len fam)
    (let ((b (inet-zeros len)))
      (do (if os-darwin? (do (inet-set! b 0 len 1) (inet-set! b 1 fam 1)) (inet-set! b 0 fam 2)) b))))

(def %pn-family (fn (_ sa) (if os-darwin? (%pn-byte (cu-str->ptr sa) 1) (cu-ptr-ref (cu-str->ptr sa) 0 2))))

; getaddrinfo: HOST's first address in AF as SOCK_STREAM gives them -- the
; resolver's order, alpine's busybox preferring no family -- as (SOCKADDR .
; LENGTH); nil where it has none.
; struct addrinfo: ai_family @4, ai_socktype @8, ai_addrlen @16; ai_addr @32
; on Darwin (canonname @24), @24 on Linux
(def %pn-getaddrinfo
  (fn (_ host af flags)
    (def hint (inet-zeros 48))
    (inet-set! hint 0 flags 4)
    (inet-set! hint 4 af 4)
    (inet-set! hint 8 1 4)
    (def cell (inet-zeros 8))
    (def r (in-call (cu-ptr-call (in-c "getaddrinfo") host 0 (cu-str->ptr hint) (cu-str->ptr cell))))
    (def head (cu-ptr-word (cu-str->ptr cell) 0))
    (if (if (not (= r 0)) #t (= head 0)) ()
      (let ((np (cu-int->ptr head)))
        (let ((len (cu-ptr-ref np 16 4)) (src (cu-int->ptr (cu-ptr-word np (if os-darwin? 32 24)))))
          (let ((b (inet-zeros len)))
            (do (let copy ((i 0)) (when (< i len) (do (inet-set! b i (%pn-byte src i) 1) (copy (+ i 1)))))
                (cu-ptr-call (in-c "freeaddrinfo") (cu-int->ptr head))
                (pair b len))))))))

; inet_pton: HOST as an IPv6 sockaddr, or nil where it is no IPv6 address
(def %pn-pton6
  (fn (_ host)
    (let ((b (%pn-sockaddr 28 %pn-af6)))
      (if (= (in-call (cu-ptr-call (in-c "inet_pton") %pn-af6 host (%pn-at (cu-str->ptr b) 8))) 1) (pair b 28) ()))))

; xhost_and_af2sockaddr: HOST's address in AF (0 for either, 2, or AF_INET6)
; as (SOCKADDR . LENGTH); FLAGS getaddrinfo's (4 for numeric only).  The run
; ends "bad address 'HOST'" where it has none.
(def pn-resolve
  (fn (_ org af flags)
    (def host (%pn-host-part org))
    (def v4 (if (= af %pn-af6) () (inet-aton host)))
    (def v6 (if (if (null? v4) (not (= af 2)) #f) (%pn-pton6 host) ()))
    (def found
      (match ((not (null? v4)) (let ((b (%pn-sockaddr 16 2))) (do (inet-set! b 4 v4 4) (pair b 16))))
             ((not (null? v6)) v6)
             (#t (%pn-getaddrinfo host af flags))))
    (if (null? found) (%pn-die (string-concat (list "bad address '" org "'"))) found)))

; xmalloc_sockaddr2dotted_noport: the address SA holds
(def pn-dotted
  (fn (_ sa)
    (def p (cu-str->ptr sa))
    (if (= (%pn-family sa) 2)
      (Str8 join "." (List map (fn (_ k) (cu-int->str (%pn-byte p (+ 4 k)))) (list 0 1 2 3)))
      (let ((out (str-make-raw 64)))
        (do (cu-ptr-call (in-c "inet_ntop") %pn-af6 (%pn-at p 8) (cu-str->ptr out) 64)
            (cu-ptr->str (cu-str->ptr out)))))))

; --- the statistics --------------------------------------------------------------------

; print_stats_and_exit
(def %pn-stats
  (fn (_)
    (sys-signal 2 1)
    (def loss (if (= %pn-ntx 0) 0 (%pn-div (* (- %pn-ntx %pn-nrx) 100) %pn-ntx)))
    (file-write 1 (string-concat
      (list "\n--- " %pn-host " ping statistics ---\n"
            (cu-int->str %pn-ntx) " packets transmitted, " (cu-int->str %pn-nrx) " packets received, "
            (if (= %pn-nrep 0) "" (string-append (cu-int->str %pn-nrep) " duplicates, "))
            (cu-int->str loss) "% packet loss\n"
            (if (null? %pn-tmin) ""
              (string-concat (list "round-trip min/avg/max = " (%pn-ms %pn-tmin) "/"
                                   (%pn-ms (%pn-div %pn-tsum (+ %pn-nrx %pn-nrep))) "/" (%pn-ms %pn-tmax) " ms\n"))))))
    (set! %pn-status (if (= %pn-nrx 0) 1 (if (if (> %pn-deadline 0) (< %pn-nrx %pn-count) #f) 1 0)))
    (Err raise (lit ping-done) "done" ())))

; --- sending ---------------------------------------------------------------------------

; inet_cksum's sum: the 16-bit words of the bytes FROM to END, a last odd
; byte the high half of one; and the one's complement of it folded
(def %pn-sum
  (fn (_ p from end)
    (let go ((i from) (sum 0))
      (if (< (+ i 1) end) (go (+ i 2) (+ sum (%pn-be16 p i)))
        (if (< i end) (+ sum (<< (%pn-byte p i) 8)) sum)))))
(def %pn-fold
  (fn (_ s)
    (let ((f (+ (& s 65535) (>> s 16))))
      (^ (& (+ (& f 65535) (>> f 16)) 65535) 65535))))

; the request's fixed part: type, code and id written, and the sum of the
; packet with its checksum, sequence number and clock taken as 0 -- a send
; adds those two to it
(def %pn-base 0)
(def %pn-header!
  (fn (_)
    (def n (+ 8 %pn-datalen))
    (def p (cu-str->ptr %pn-pkt))
    (cu-ptr-set! p 0 (if %pn-v6 128 8) 1)
    (cu-ptr-set! p 1 0 1)
    (cu-ptr-set! p 2 0 2)
    (%pn-be16! p 4 %pn-id)
    (cu-ptr-set! p 6 0 2)
    (cu-ptr-set! p 8 0 4)
    (set! %pn-base (%pn-sum p 0 n))))

; sendping4, sendping6 and sendping_tail: the next request, and the timer for
; the one after it or for the wait on the last
(def %pn-send!
  (fn (_)
    (def now (%pn-now))
    (when (if (> %pn-deadline 0) (>= now %pn-deadline) #f) (%pn-stats))
    (def n (+ 8 %pn-datalen))
    (def p (cu-str->ptr %pn-pkt))
    (def seq (& %pn-ntx 65535))
    (%pn-be16! p 6 seq)
    (%pn-dup! (& %pn-ntx 1023) #f)
    (set! %pn-ntx (+ %pn-ntx 1))
    ; the clock, native order: it is read back here, the checksum and the
    ; send all that follow it
    (cu-ptr-set! p 8 (& (%pn-now) 4294967295) 4)
    (unless %pn-v6 (%pn-be16! p 2 (%pn-fold (+ (+ %pn-base seq) (%pn-sum p 8 (if (< n 12) n 12))))))
    (def sz (in-call (cu-ptr-call (in-c "sendto") %pn-fd p n 0 (cu-str->ptr %pn-sa) %pn-salen)))
    (when (< sz 0) (%pn-errno-die "sendto" sz))
    (unless (= sz n) (%pn-die "write error"))
    (set! %pn-timer
      (if (if (= %pn-count 0) #t (< %pn-ntx %pn-count))
        (if (= %pn-interval 0) () (pair (lit send) (+ now %pn-interval)))
        ; approximately twice the longest trip, in seconds, or -W
        (let ((expire (if (= %pn-nrx 0) %pn-timeout (let ((e (%pn-div %pn-tmax 524288))) (if (= e 0) 1 e)))))
          (if (= expire 0) () (pair (lit stats) (+ now (* expire 1000000)))))))))

; --- receiving -------------------------------------------------------------------------

(def %pn-dup? (fn (_ k) (not (= (& (%pn-byte (cu-str->ptr %pn-dups) (>> k 3)) (<< 1 (& k 7))) 0))))
(def %pn-dup!
  (fn (_ k on)
    (let ((b (%pn-byte (cu-str->ptr %pn-dups) (>> k 3))) (m (<< 1 (& k 7))))
      (cu-ptr-set! (cu-str->ptr %pn-dups) (>> k 3) (if on (| b m) (& b (^ m 255))) 1))))

(def %pn-icmp-names
  (list (pair 0 "Echo Reply") (pair 3 "Destination Unreachable") (pair 4 "Source Quench")
        (pair 5 "Redirect (change route)") (pair 8 "Echo Request") (pair 11 "Time Exceeded")
        (pair 12 "Parameter Problem") (pair 13 "Timestamp Request") (pair 14 "Timestamp Reply")
        (pair 15 "Information Request") (pair 16 "Information Reply") (pair 17 "Address Mask Request")
        (pair 18 "Address Mask Reply")))
(def %pn-icmp6-names
  (list (pair 1 "Destination Unreachable") (pair 2 "Packet too big") (pair 3 "Time Exceeded")
        (pair 4 "Parameter Problem") (pair 129 "Echo Reply") (pair 128 "Echo Request")
        (pair 130 "Listener Query") (pair 131 "Listener Report") (pair 132 "Listener Reduction")))

(def %pn-warn
  (fn (_ type names)
    (let ((n (List find (fn (_ e) (= (first e) type)) names)))
      (%pn-say (string-concat (list "warning: got ICMP " (cu-int->str type) " (" (if (null? n) "unknown ICMP type" (rest n)) ")"))))))

; unpack_tail
(def %pn-tail!
  (fn (_ sz p from seq ttl now)
    (def trip (if (null? p) () (& (- now (cu-ptr-ref p 0 4)) 4294967295)))
    (unless (null? trip)
      (do (set! %pn-tsum (+ %pn-tsum trip))
          (when (if (null? %pn-tmin) #t (< trip %pn-tmin)) (set! %pn-tmin trip))
          (when (> trip %pn-tmax) (set! %pn-tmax trip))))
    (def k (& seq 1023))
    (def dup (%pn-dup? k))
    (if dup (set! %pn-nrep (+ %pn-nrep 1)) (do (%pn-dup! k #t) (set! %pn-nrx (+ %pn-nrx 1))))
    (unless %pn-quiet
      (file-write 1 (string-concat
        (list (cu-int->str sz) " bytes from " from ": seq=" (cu-int->str seq) " ttl=" (cu-int->str ttl)
              (if (null? trip) "" (string-concat (list " time=" (%pn-ms trip) " ms")))
              (if dup " (DUP!)" "") "\n"))))))

; unpack4: #t for a reply to us
(def %pn-unpack4
  (fn (_ buf c from now)
    (def p (cu-str->ptr buf))
    (def hlen (* 4 (& (%pn-byte p 0) 15)))
    (def sz (- c hlen))
    (def type (%pn-byte p hlen))
    (match
      ((< c (+ %pn-datalen 8)) #f)
      ((not (= (%pn-be16 p (+ hlen 4)) %pn-id)) #f)
      ((= type 0)
        (do (%pn-tail! sz (if (>= sz 12) (%pn-at p (+ hlen 8)) ())
                       (Str8 join "." (List map (fn (_ k) (cu-int->str (%pn-byte (cu-str->ptr from) (+ 4 k))))
                                                (list 0 1 2 3)))
                       (%pn-be16 p (+ hlen 6)) (%pn-byte p 8) now)
            #t))
      (#t (do (unless (= type 8) (%pn-warn type %pn-icmp-names)) #f)))))

; unpack6: #t for a reply to us
(def %pn-unpack6
  (fn (_ buf sz from hop now)
    (def p (cu-str->ptr buf))
    (def type (%pn-byte p 0))
    (match
      ((< sz (+ %pn-datalen 8)) #f)
      ((not (= (%pn-be16 p 4) %pn-id)) #f)
      ((= type 129) (do (%pn-tail! sz (if (>= sz 12) (%pn-at p 8) ()) (pn-dotted from) (%pn-be16 p 6) hop now) #t))
      (#t (do (unless (= type 128) (%pn-warn type %pn-icmp6-names)) #f)))))

; the receive buffers, made once a run: the datagram, its sender, and for
; recvmsg the iovec, the ancillary data and the msghdr that point at them
(def %pn-rbuf ())
(def %pn-rfrom ())
(def %pn-rlen ())
(def %pn-iov ())
(def %pn-control ())
(def %pn-msg ())

(def %pn-buffers!
  (fn (_)
    (def n (+ %pn-datalen 136))
    (set! %pn-rbuf (inet-zeros n))
    (set! %pn-rfrom (inet-zeros 128))
    (set! %pn-rlen (inet-zeros 4))
    (set! %pn-iov (inet-zeros 16))
    (set! %pn-control (inet-zeros 64))
    (set! %pn-msg (inet-zeros 56))
    (cu-ptr-set! (cu-str->ptr %pn-iov) 0 (td-ptr->int (cu-str->ptr %pn-rbuf)) 8)
    (inet-set! %pn-iov 8 n 8)
    (cu-ptr-set! (cu-str->ptr %pn-msg) 0 (td-ptr->int (cu-str->ptr %pn-rfrom)) 8)
    (cu-ptr-set! (cu-str->ptr %pn-msg) 16 (td-ptr->int (cu-str->ptr %pn-iov)) 8)
    (inet-set! %pn-msg 24 1 4)
    (cu-ptr-set! (cu-str->ptr %pn-msg) 32 (td-ptr->int (cu-str->ptr %pn-control)) 8)))

; a datagram waiting, as (BUFFER COUNT SOCKADDR HOPLIMIT CLOCK), the clock
; read as it came; nil where none is; recvfrom's errors other than EINTR and
; EAGAIN said.  An echo request -- our own, on loopback, ahead of its reply
; is passed over at once, as unpack passes over it in silence.
(def %pn-recv
  (fn (self)
    (def said (fn (_ r) (do (unless (if (= (Err errno-of r) 4) #t (= (Err errno-of r) (if os-darwin? 35 11)))
                              (%pn-say (string-append "recvfrom: " (libc-strerror (Err errno-of r)))))
                            ())))
    (def p (cu-str->ptr %pn-rbuf))
    (if (not %pn-v6)
      (do (inet-set! %pn-rlen 0 128 4)
          (let ((r (in-call (cu-ptr-call (in-c "recvfrom") %pn-fd p (+ %pn-datalen 136) in-dontwait
                                         (cu-str->ptr %pn-rfrom) (cu-str->ptr %pn-rlen)))))
            (match ((< r 0) (said r))
                   ((= (%pn-byte p (* 4 (& (%pn-byte p 0) 15))) 8) (self))
                   (#t (list %pn-rbuf r %pn-rfrom -1 (%pn-now))))))
      ; recvmsg, the hop limit in the ancillary data
      (do (inet-set! %pn-msg 8 128 4)
          (inet-set! %pn-msg 40 64 4)
          (let ((r (in-call (cu-ptr-call (in-c "recvmsg") %pn-fd (cu-str->ptr %pn-msg) in-dontwait))))
            (match ((< r 0) (said r))
                   ((= (%pn-byte p 0) 128) (self))
                   (#t (let ((now (%pn-now)))
                         (list %pn-rbuf r %pn-rfrom (%pn-hoplimit %pn-control (cu-ptr-ref (cu-str->ptr %pn-msg) 40 4)) now)))))))))

; the IPV6_HOPLIMIT among the cmsghdrs in END bytes of CONTROL, or -1:
; (len, level, type, data) of 8, 4, 4 bytes aligned to 8 on Linux, of 4 each
; aligned to 4 on Darwin
(def %pn-hoplimit
  (fn (_ control end)
    (def p (cu-str->ptr control))
    (def hdr (if os-darwin? 12 16))
    (def align (fn (_ n) (if os-darwin? (& (+ n 3) -4) (& (+ n 7) -8))))
    (let go ((at 0) (hop -1))
      (if (> (+ at hdr) end) hop
        (let ((len (cu-ptr-ref p at 4))
              (level (cu-ptr-ref p (+ at (if os-darwin? 4 8)) 4))
              (type (cu-ptr-ref p (+ at (if os-darwin? 8 12)) 4)))
          (if (< len hdr) hop
            (go (+ at (align len))
                (if (if (= level 41) (if os-darwin? (if (= type 20) #t (= type 47)) (= type 8)) #f)
                  (cu-ptr-ref p (+ at hdr) 4) hop))))))))

; --- the loop ----------------------------------------------------------------------------

; the replies taken until the run ends
(def %pn-loop
  (fn (self)
    (when (Sys take-signal 2) (%pn-stats))
    (def now (%pn-now))
    (if (if (null? %pn-timer) #f (>= now (rest %pn-timer)))
      (if (eq? (first %pn-timer) (lit send)) (%pn-send!) (%pn-stats))
      (let ((wait (if (null? %pn-timer) 250
                    (let ((ms (%pn-div (+ (- (rest %pn-timer) now) 999) 1000))) (if (> ms 250) 250 ms)))))
        (unless (null? (sys-poll (list (pair %pn-fd (list (lit in)))) wait))
          (let ((got (%pn-recv)))
            (unless (null? got)
              (let ((ours (if %pn-v6 (%pn-unpack6 (first got) (List ref 1 got) (List ref 2 got) (List ref 3 got) (List ref 4 got))
                            (%pn-unpack4 (first got) (List ref 1 got) (List ref 2 got) (List ref 4 got)))))
                (do (when (if (> %pn-count 0) (>= %pn-nrx %pn-count) #f) (%pn-stats))
                    (when (if ours %pn-again #f) (%pn-send!)))))))))
    (self)))

; create_icmp_socket
(def %pn-socket
  (fn (_)
    (let ((fd (in-call (cu-ptr-call (in-c "socket") (if %pn-v6 %pn-af6 2) 3 (if %pn-v6 58 1)))))
      (match ((>= fd 0) fd)
             ((= (Err errno-of fd) 1) (%pn-die "permission denied (are you root?)"))
             (#t (%pn-errno-die "can't create raw socket" fd))))))

; xbind
(def %pn-bind
  (fn (_ src)
    (let ((r (in-call (cu-ptr-call (in-c "bind") %pn-fd (cu-str->ptr (first src)) (rest src)))))
      (when (< r 0) (%pn-errno-die "bind" r)))))

; setsockopt_bindtodevice
(def %pn-bind-device
  (fn (_ iface)
    (if os-darwin? (%pn-say "SO_BINDTODEVICE is not supported on this system")
      (let ((ifr (inet-zeros 40)))
        (do (let copy ((i 0)) (when (if (< i (byte-len iface)) (< i 15) #f)
                                (do (inet-set! ifr i (byte-at iface i) 1) (copy (+ i 1)))))
            (let ((r (in-call (cu-ptr-call (in-c "setsockopt") %pn-fd 1 25 (cu-str->ptr ifr) 40))))
              (when (< r 0)
                (%pn-say (string-concat (list "can't bind to interface " iface ": " (libc-strerror (Err errno-of r))))))))))))

; the ICMP6_FILTER: echo replies alone, or all with -v; Linux's bits block,
; Darwin's pass
(def %pn-filter
  (fn (_)
    (let ((filt (inet-zeros 32)) (all (if os-darwin? 255 0)))
      (do (let fill ((i 0)) (when (< i 32) (do (inet-set! filt i (if %pn-verbose all (^ all 255)) 1) (fill (+ i 1)))))
          (unless %pn-verbose (inet-set! filt 16 (if os-darwin? 2 253) 1))
          filt))))

; ping4 and ping6: the socket's options, then the first request
(def %pn-setup!
  (fn (_ src if-index)
    (if (not %pn-v6)
      (do (unless (null? src)
            (do (when (< (in-call (cu-ptr-call (in-c "setsockopt") %pn-fd 0 (if os-darwin? 9 32) (cu-str->ptr (first src)) (rest src))) 0)
                  (%pn-die "can't set multicast source interface"))
                (%pn-bind src)))
          (%pn-setopt %pn-fd %pn-sol-socket (if os-darwin? 32 6) 1)
          (%pn-setopt %pn-fd %pn-sol-socket (if os-darwin? 4098 8) (+ (* %pn-datalen 2) 7168))
          (unless (= %pn-ttl 0)
            (do (%pn-setopt %pn-fd 0 (if os-darwin? 4 2) %pn-ttl)
                (%pn-setopt %pn-fd 0 (if os-darwin? 10 33) %pn-ttl))))
      (do (unless (null? src) (%pn-bind src))
          (when (< (in-call (cu-ptr-call (in-c "setsockopt") %pn-fd 58 (if os-darwin? 18 1) (cu-str->ptr (%pn-filter)) 32)) 0)
            (%pn-die "setsockopt(ICMP6_FILTER)"))
          (%pn-setopt %pn-fd %pn-sol-socket (if os-darwin? 32 6) 1)
          (%pn-setopt %pn-fd %pn-sol-socket (if os-darwin? 4098 8) (+ (* %pn-datalen 2) 7168))
          (%pn-setopt %pn-fd 255 (if os-darwin? 26 7) 2)
          (%pn-setopt %pn-fd 41 (if os-darwin? 20 8) 1)
          (unless (= if-index 0) (inet-set! %pn-sa 24 if-index 4))))))

(def %pn-main
  (fn (_ applet argv)
    (def o (cu-opts applet argv))
    (def ops (Opts operands o))
    (def num (fn (_ f) (let ((v (Opts value o f))) (if (null? v) 0 (%pn-number v 0 2147483647)))))
    (set! %pn-count (num "-c"))
    (set! %pn-ttl (num "-t"))
    (def deadline (num "-w"))
    (set! %pn-timeout (let ((v (Opts value o "-W"))) (if (null? v) 10 (%pn-number v 0 2147483647))))
    (unless (if (pair? ops) (null? (rest ops)) #f) (%pn-usage))
    ; -q and -v undo each other, the later standing
    (def qv (List find (fn (_ w) (if (string=? w "-q") #t (string=? w "-v"))) (List reverse (rest (Assoc entry (lit on) o)))))
    (set! %pn-quiet (if (null? qv) #f (string=? qv "-q")))
    (set! %pn-verbose (if (null? qv) #f (string=? qv "-v")))
    (set! %pn-again (Opts on? o "-A"))
    (set! %pn-datalen (let ((v (Opts value o "-s"))) (if (null? v) 56 (%pn-number v 0 65535))))
    (def str-i (Opts value o "-I"))
    (def if-index (if (null? str-i) 0 (cu-ptr-call (in-c "if_nametoindex") str-i)))
    (def src (if (if (null? str-i) #t (> if-index 0)) () (pn-resolve str-i 0 4)))
    (set! %pn-pattern (let ((v (Opts value o "-p"))) (if (null? v) 0 (%pn-hex-byte v))))
    (set! %pn-deadline (if (= deadline 0) 0 (+ (%pn-now) (* (if (> deadline 2147) 2147 deadline) 1000000))))
    (set! %pn-interval (%pn-duration (let ((v (Opts value o "-i"))) (if (null? v) "1" v))))
    (set! %pn-id (& (sys-getpid) 65535))
    (set! %pn-host (first ops))
    (def fams (cu-families applet argv))
    (def af (match ((if (string=? applet "ping6") #t (List any? (fn (_ c) (= c #\6)) fams)) %pn-af6)
                   ((pair? fams) 2)
                   (#t 0)))
    (def lsa (pn-resolve %pn-host af 0))
    (set! %pn-sa (first lsa))
    (set! %pn-salen (rest lsa))
    (set! %pn-v6 (= (%pn-family %pn-sa) %pn-af6))
    (def source (if (null? src) () (if (= (%pn-family (first src)) (%pn-family %pn-sa)) src ())))
    (file-write 1 (string-concat (list "PING " %pn-host " (" (pn-dotted %pn-sa) ")"
                                       (if (null? source) "" (string-append " from " (pn-dotted (first source))))
                                       ": " (cu-int->str %pn-datalen) " data bytes\n")))
    (set! %pn-fd (%pn-socket))
    (when (if (null? str-i) #f (> if-index 0)) (%pn-bind-device str-i))
    (set! %pn-pkt (%pn-filled (+ %pn-datalen 12) %pn-pattern))
    (%pn-buffers!)
    (%pn-header!)
    (%pn-setup! source if-index)
    (Sys catch-signal 2)
    (%pn-send!)
    (%pn-loop)))

(def %pn-run
  (fn (_ applet argv)
    (set! %pn-applet applet)
    (set! %pn-ntx 0) (set! %pn-nrx 0) (set! %pn-nrep 0)
    (set! %pn-tmin ()) (set! %pn-tmax 0) (set! %pn-tsum 0)
    (set! %pn-timer ()) (set! %pn-fd -1) (set! %pn-status 0)
    (set! %pn-dups (inet-zeros 128))
    (def status
      (guard (e (match ((eq? (cu-err-label e) (lit ping-usage)) (cu-usage applet))
                       ((eq? (cu-err-label e) (lit ping)) 1)
                       ((eq? (cu-err-label e) (lit ping-done)) %pn-status)
                       (#t (do (sys-signal 2 0) (unless (< %pn-fd 0) (cu-ptr-call (in-c "close") %pn-fd)) (error e)))))
        (%pn-main applet argv)))
    (sys-signal 2 0)
    (unless (< %pn-fd 0) (cu-ptr-call (in-c "close") %pn-fd))
    status))

(def cu-ping (fn (_ argv stdin-thunk) (%pn-run "ping" argv)))
(def cu-ping6 (fn (_ argv stdin-thunk) (%pn-run "ping6" argv)))

(provide cu/ping cu-ping cu-ping6)

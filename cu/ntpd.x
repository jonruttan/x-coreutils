; # x-coreutils -- the small tools, as applets
;
; ## cu/ntpd.x -- ntpd: an NTP client and server
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; networking/ntpd.c: each -p PEER (HOST[:PORT], [keyno:N:] for a key of -k's
; file), else each "server HOST [key N]" line of /etc/ntp.conf, is queried
; over UDP -- at first a burst, then every 2^poll seconds.  A reply goes
; through busybox's clock filter, selection and clustering; the peer chosen
; steps the clock (settimeofday) past a second's offset, else slews it
; through the kernel's PLL (adjtimex, ntp_adjtime on Darwin).  -w only asks
; and says each reply; -q ends after the first setting, or by SIGALRM ten
; seconds without a reply (fifty after one).  -l answers queries on port
; 123 too, stratum 1 with no peers; -I binds that to an interface.  -S PROG
; runs after a step, a stratum change, the peers' loss, and every 11
; minutes, $stratum $freq_drift_ppm $poll_interval and $offset set.
; Without -n (or -w) the daemon goes to the background, its output nowhere.
; SIGTERM, SIGINT and SIGALRM end the run by that signal.  -N -x -4 -6 -a
; -A -b -g and -L are taken; -N alone does something, the priority -15.
; busybox's SQRT is a fast approximation; this is the platform's sqrt.

(module cu/ntpd)

(import cu/cli cu-opts cu-usage)
(import cu/date cu-date-fmt cu-date-split)
(import cu/hash cu-md5-bytes cu-sha1-bytes)
(import cu/inetd in-c in-call in-dontwait in-errtext in-exec in-lines
  in-reuse! in-sockaddr6 in-strtou in-tokens-max in-zeroed)
(import cu/mime mm-ci=)
(import cu/nc nc-count)
(import cu/prims append byte-at byte-len cu-hexs cu-int->ptr cu-int->str
  cu-nth cu-ptr->str cu-ptr-call cu-ptr-ref cu-ptr-set! cu-sig-ign cu-str->ptr
  cu-sweep-lines cu-sweep-tick! file-open-or-err file-open-read file-read-all
  file-unlink file-write file-write-all filter in-index-of length map
  net-resolve net-sockaddr reverse str-make-raw string-append string-concat
  string=? substring sys-close sys-dup2 sys-exit sys-fork sys-getpid sys-kill
  sys-poll sys-setenv sys-signal sys-usleep vec-build vec-ref vec-set!
  wget-div wget-err-text wget-index wget-memv)
(import cu/signal ts-signal-number)
(import cu/sysinfo si-now)
(import cu/tar tar-why)
(import cu/telnet tn-str-bytes)
(import cu/telnetd td-ptr->int)
(import cu/text cu-pad-zero)
(import cu/vmstat vm-fixed)

(def %nt-server-port 123)
(def %nt-conf-file "/etc/ntp.conf")

(def %nt-1900 2208988800)               ; OFFSET_1900_1970
(def %nt-tol (Float from "0.000015"))   ; FREQ_TOLERANCE
(def %nt-mindisp (Float from "0.01"))
(def %nt-prec (Float from "0.002"))     ; G_precision_sec
(def %nt-prec-exp -9)
(def %nt-maxdist 3)
(def %nt-maxstrat 16)
(def %nt-minpoll 5)
(def %nt-bigpoll 9)
(def %nt-maxpoll 12)
(def %nt-polladj-limit 40)

; --- the state ----------------------------------------------------------------------

(def %nt-cur ())                  ; G.cur_time, seconds since 1900, a Float
(def %nt-rootdelay ())
(def %nt-reftime ())
(def %nt-rootdisp ())
(def %nt-last-script ())
(def %nt-script ())
(def %nt-listen -1)
(def %nt-verbose 0)
(def %nt-peers ())
(def %nt-peer-cnt 0)
(def %nt-refid (list 0 0 0 0))
(def %nt-status 0)
(def %nt-stratum 16)
(def %nt-poll 0)
(def %nt-polladj 0)
(def %nt-freqhold -1)
(def %nt-drift 0)                 ; kernel_freq_drift
(def %nt-last-peer ())
(def %nt-last-offset ())
(def %nt-last-recv ())
(def %nt-djitter ())              ; discipline_jitter
(def %nt-ratio 0)                 ; offset_to_jitter_ratio
(def %nt-q? #f)
(def %nt-w? #f)
(def %nt-alarm-at ())             ; -q's alarm, a time since 1900
(def %nt-alarm-long? #f)          ; it was moved to fifty seconds
(def %nt-rand 1)
(def %nt-sigs ())
(def %nt-got-sig ())             ; a signal taken, not acted on yet

(def %nt-say (fn (_ msg) (file-write 2 (string-concat (list "ntpd: " msg "\n")))))
(def %nt-die (fn (_ msg) (Err raise (lit net) msg ())))
(def %nt-why (fn (_ op) (tar-why op "")))

; --- numbers ------------------------------------------------------------------------

(def %nt+ (fn (_ a b) (Float + a b)))
(def %nt- (fn (_ a b) (Float - a b)))
(def %nt* (fn (_ a b) (Float * a b)))
(def %nt/ (fn (_ a b) (Float / a b)))
(def %nt< (fn (_ a b) (Float < a b)))
(def %nt-abs (fn (_ x) (Float abs (Float from x))))
(def %nt-max (fn (_ a b) (if (Float < b a) (Float from a) (Float from b))))
(def %nt-sq (fn (_ x) (Float * x x)))
(def %nt-sqrt (fn (_ x) (Float sqrt (Float from x))))
(def %nt-trunc (fn (_ x) (Float ->int (Float from x))))
(def %nt-pow2 (fn (_ e) (if (< e 0) (Float / 1 (<< 1 (- 0 e))) (Float from (<< 1 e)))))

; printf's %f, %+f and %.3f
(def %nt-f (fn (_ x) (vm-fixed (Float from x) 6)))
(def %nt-sf (fn (_ x) (let ((s (%nt-f x))) (if (Str8 starts? "-" s) s (string-append "+" s)))))
(def %nt-sf3 (fn (_ x) (let ((s (vm-fixed (Float from x) 3))) (if (Str8 starts? "-" s) s (string-append "+" s)))))
(def %nt-hex (fn (_ n w) (cu-pad-zero (cu-hexs n) w)))
(def %nt-u (fn (_ n) (cu-int->str n)))
(def %nt-imax (fn (_ a b) (if (> a b) a b)))
(def nt-imin (fn (_ a b) (if (< a b) a b)))
(def %nt-iabs (fn (_ a) (if (< a 0) (- 0 a) a)))

; rand(): an LCG seeded with the pid, as srand(getpid()) seeds it
(def %nt-random
  (fn (_)
    (set! %nt-rand (% (+ (* %nt-rand 1103515245) 12345) 2147483648))
    %nt-rand))

; gettime1900d: the time now, G.cur_time set to it
(def %nt-now!
  (fn (_)
    (let ((t (si-now)))
      (set! %nt-cur (%nt+ (%nt+ (Float from (first t)) (%nt* (Float from "0.000001") (rest t))) %nt-1900))
      %nt-cur)))

; --- packets ------------------------------------------------------------------------

; a packet's bytes: a vector of N bytes from BUF
(def %nt-bytes (fn (_ buf n) (vec-build n (fn (_ i) (cu-ptr-ref (cu-str->ptr buf) i 1)))))
(def %nt-be (fn (_ v i k) (let go ((j 0) (acc 0)) (if (= j k) acc (go (+ j 1) (+ (* acc 256) (vec-ref v (+ i j))))))))
; a uint32 read in the host's order, as %08x prints a raw field
(def %nt-le32 (fn (_ v i) (+ (vec-ref v i) (* 256 (vec-ref v (+ i 1))) (* 65536 (vec-ref v (+ i 2))) (* 16777216 (vec-ref v (+ i 3))))))
(def nt-be-bytes (fn (_ n k) (let go ((j 0) (n n) (acc ())) (if (= j k) acc (go (+ j 1) (wget-div n 256) (pair (% n 256) acc))))))

(def %nt-lfp->d
  (fn (_ v i)
    (def int (%nt-be v i 4))
    (def d (%nt+ int (%nt/ (%nt-be v (+ i 4) 4) 4294967296)))
    (if (< int %nt-1900) (%nt+ d 4294967296) d)))

(def %nt-sfp->d (fn (_ v i) (%nt+ (%nt-be v i 2) (%nt/ (%nt-be v (+ i 2) 2) 65536))))

; d_to_lfp and d_to_sfp, as bytes
(def %nt-d->lfp
  (fn (_ d)
    (def whole (%nt-trunc d))
    (append (nt-be-bytes (% whole 4294967296) 4)
            (nt-be-bytes (% (%nt-trunc (%nt* (%nt- d whole) 4294967295)) 4294967296) 4))))

(def %nt-d->sfp
  (fn (_ d)
    (def whole (% (%nt-trunc d) 65536))
    (append (nt-be-bytes whole 2) (nt-be-bytes (% (%nt-trunc (%nt* (%nt- d whole) 65535)) 65536) 2))))

; a raw buffer holding the bytes of list L
(def nt-raw
  (fn (_ l)
    (def b (str-make-raw (%nt-imax 1 (length l))))
    (let go ((i 0) (l l)) (unless (null? l) (do (cu-ptr-set! (cu-str->ptr b) i (first l) 1) (go (+ i 1) (rest l)))))
    b))

(def nt-zeros (fn (_ n) (let go ((n n) (acc ())) (if (= n 0) acc (go (- n 1) (pair 0 acc))))))
(def %nt-vec->list (fn (_ v a b) (let go ((i (- b 1)) (acc ())) (if (< i a) acc (go (- i 1) (pair (vec-ref v i) acc))))))

; --- digests over bytes ---------------------------------------------------------------

; hash(): the key's bytes then the packet's first 48, MD5 or SHA1
(def %nt-hash
  (fn (_ key msg48)
    (if (eq? (cu-nth 1 key) (lit md5))
      (cu-md5-bytes (append (cu-nth 3 key) msg48))
      (cu-sha1-bytes (append (cu-nth 3 key) msg48)))))

; --- addresses -------------------------------------------------------------------------

(def %nt-af6 (if os-darwin? 30 10))
(def %nt-family (fn (_ sa) (cu-ptr-ref (cu-str->ptr sa) (if os-darwin? 1 0) 1)))

; xmalloc_sockaddr2dotted_noport: IPv4 dotted, IPv6 as inet_ntop writes it --
; an IPv4-mapped one too, ::ffff:a.b.c.d
(def %nt-dotted
  (fn (_ sa)
    (def p (cu-str->ptr sa))
    (def out (str-make-raw 64))
    (if (= (%nt-family sa) 2)
      (cu-ptr-call (in-c "inet_ntop") 2 (cu-int->ptr (+ (td-ptr->int p) 4)) (cu-str->ptr out) 64)
      (cu-ptr-call (in-c "inet_ntop") %nt-af6 (cu-int->ptr (+ (td-ptr->int p) 8)) (cu-str->ptr out) 64))
    (cu-ptr->str (cu-str->ptr out))))

; host2sockaddr(HOST, 123): (SOCKADDR LEN), or nil said as busybox says it
(def %nt-resolve
  (fn (_ org)
    (def bracket? (Str8 starts? "[" org))
    (def close (if bracket? (wget-index org #\] 0) ()))
    (def last (in-index-of org #\:))
    (def colon (match (bracket? (if (null? close) () (if (< (+ close 1) (byte-len org)) (+ close 1) ())))
                      ((null? last) ())
                      ((= (wget-index org #\: 0) last) last)
                      (#t ())))
    (def host (match (bracket? (if (null? close) "" (substring org 1 close)))
                     ((null? colon) org)
                     (#t (substring org 0 colon))))
    (def ptext (if (null? colon) () (substring org (+ colon 1) (byte-len org))))
    (def port (if (null? ptext) 123 (let ((n (in-strtou ptext))) (if (if (null? n) #f (<= n 65535)) n -1))))
    (match
      ((if bracket? (if (null? close) #t (if (< (+ close 1) (byte-len org)) (not (= (byte-at org (+ close 1)) #\:)) #f)) #f)
        (do (%nt-say (string-concat (list "bad address '" org "'"))) ()))
      ((< port 0) (do (%nt-say (string-concat (list "bad port '" ptext "'"))) ()))
      (#t (let ((a4 (str-make-raw 4)) (a6 (in-zeroed 16)))
            (match
              ((not (= (in-call (cu-ptr-call (in-c "inet_aton") host (cu-str->ptr a4))) 0))
                (list (net-sockaddr (%nt-dotted-of a4) port) 16))
              ((= (in-call (cu-ptr-call (in-c "inet_pton") %nt-af6 host (cu-str->ptr a6))) 1)
                (let ((s (in-sockaddr6 a6 port))) (list (first s) (rest s))))
              (#t (let ((q (guard (_ ()) (net-resolve host))))
                    (if (null? q) (do (%nt-say (string-concat (list "bad address '" org "'"))) ())
                      (list (net-sockaddr q port) 16))))))))))

(def %nt-dotted-of (fn (_ a4) (let ((p (cu-str->ptr a4))) (string-concat (list (%nt-u (cu-ptr-ref p 0 1)) "." (%nt-u (cu-ptr-ref p 1 1)) "." (%nt-u (cu-ptr-ref p 2 1)) "." (%nt-u (cu-ptr-ref p 3 1)))))))

; calculate_refid: an IPv4 address's bytes, an IPv6 one's MD5's first four
(def %nt-refid-of
  (fn (_ sa)
    (def p (cu-str->ptr sa))
    (if (= (%nt-family sa) 2) (map (fn (_ i) (cu-ptr-ref p i 1)) (list 4 5 6 7))
      (List take 4 (cu-md5-bytes (map (fn (_ i) (cu-ptr-ref p i 1)) (list 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23)))))))

; --- peers --------------------------------------------------------------------------------

(def %np-host 0)
(def %np-sa 1)            ; (SOCKADDR LEN), or nil
(def %np-dotted 2)
(def %np-key 3)
(def %np-fd 4)
(def %np-idx 5)
(def %np-refid 6)
(def %np-pkt-refid 7)
(def %np-pkt-status 8)
(def %np-pkt-stratum 9)
(def %np-reach 10)
(def %np-dns 11)
(def %np-next 12)
(def %np-xmttime 13)
(def %np-raw-delay 14)
(def %np-pkt-recv 15)
(def %np-pkt-delay 16)
(def %np-pkt-rootdelay 17)
(def %np-pkt-rootdisp 18)
(def %np-foffset 19)
(def %np-fdisp 20)
(def %np-fjitter 21)
(def %np-dps 22)          ; eight (OFFSET RECV DISPERSION) vectors
(def %np-xmt 23)          ; the transmit stamp sent, eight bytes

(def %np (fn (_ p k) (vec-ref p k)))
(def %np! (fn (_ p k v) (vec-set! p k v)))
(def %nt-dp (fn (_ p i k) (vec-ref (vec-ref (%np p %np-dps) i) k)))
(def %nt-dp! (fn (_ p i k v) (vec-set! (vec-ref (%np p %np-dps) i) k v)))

(def %nt-dispersion (fn (_ p i) (%nt+ (%nt-dp p i 2) (%nt* %nt-tol (%nt- %nt-cur (%nt-dp p i 1))))))

(def %nt-root-distance
  (fn (_ p)
    (%nt+ (%nt+ (%nt+ (%nt+ (%nt/ (%nt-max %nt-mindisp (%nt+ (%np p %np-pkt-rootdelay) (%np p %np-pkt-delay))) 2)
                              (%np p %np-pkt-rootdisp))
                       (%np p %np-fdisp))
                (%nt* %nt-tol (%nt- %nt-cur (%np p %np-pkt-recv))))
          (%np p %np-fjitter))))

(def %nt-set-next! (fn (_ p t) (%np! p %np-next (%nt+ %nt-cur t))))

; filter_datapoints
(def %nt-filter!
  (fn (_ p)
    (def idx (%np p %np-idx))
    (%np! p %np-foffset (%nt-dp p idx 0))
    (def sums
      (let go ((i 0) (idx idx) (sum (Float from 0)) (wavg (Float from 0)))
        (if (= i 8) (pair sum wavg)
          (go (+ i 1) (& (- idx 1) 7)
              (%nt+ sum (%nt/ (%nt-dispersion p idx) (<< 2 i)))
              (%nt+ wavg (%nt-dp p idx 0))))))
    (def wavg (%nt/ (rest sums) 8))
    (%np! p %np-fdisp (first sums))
    (def j (%nt-sqrt (%nt/ (let go ((i 0) (s (Float from 0))) (if (= i 8) s (go (+ i 1) (%nt+ s (%nt-sq (%nt- wavg (%nt-dp p i 0))))))) 8)))
    (%np! p %np-fjitter (if (%nt< %nt-prec j) j %nt-prec))
    (when (>= %nt-verbose 4)
      (%nt-say (string-concat (list "filter offset:" (%nt-sf (%np p %np-foffset)) " disp:" (%nt-f (%np p %np-fdisp))
                                    " jitter:" (%nt-f (%np p %np-fjitter))))))))

; reset_peer_stats
(def %nt-reset-stats!
  (fn (_ p offset)
    (def small? (%nt< (%nt-abs offset) 1))
    (let go ((i 0))
      (when (< i 8)
        (do (if small?
              (do (%nt-dp! p i 1 (%nt+ (%nt-dp p i 1) offset))
                  (unless (Float = (%nt-dp p i 0) 0) (%nt-dp! p i 0 (%nt- (%nt-dp p i 0) offset))))
              (do (%nt-dp! p i 1 %nt-cur) (%nt-dp! p i 0 (Float from 0))))
            (go (+ i 1)))))
    (%np! p %np-pkt-recv (if small? (%nt+ (%np p %np-pkt-recv) offset) %nt-cur))
    (%nt-filter! p)))

(def %nt-new-peer
  (fn (_ host key)
    (def p (vec-build 24 (fn (_ i) ())))
    (map (fn (_ k) (%np! p k (Float from 0)))
         (list %np-xmttime %np-raw-delay %np-pkt-recv %np-pkt-delay %np-pkt-rootdelay %np-pkt-rootdisp
               %np-foffset %np-fdisp %np-fjitter))
    (%np! p %np-host host)
    (%np! p %np-key key)
    (%np! p %np-fd -1)
    (%np! p %np-idx 0)
    (%np! p %np-refid (list 0 0 0 0))
    (map (fn (_ k) (%np! p k 0)) (list %np-pkt-refid %np-pkt-status %np-pkt-stratum %np-reach %np-dns))
    (%np! p %np-dps (vec-build 8 (fn (_ i) (vec-build 3 (fn (_ k) (Float from 0))))))
    (%np! p %np-xmt (nt-zeros 8))
    (%np! p %np-next %nt-cur)
    (%nt-reset-stats! p 1)
    p))

; resolve_peer_hostname: the address, or nil and the next try further off
(def %nt-resolve-peer!
  (fn (_ p)
    (def a (%nt-resolve (%np p %np-host)))
    (if (null? a) (do (%np! p %np-dns (& (+ (* (%np p %np-dns) 2) 1) 63)) ())
      (do (%np! p %np-sa a)
          (%np! p %np-dotted (%nt-dotted (first a)))
          (when (if (>= %nt-verbose 1) (not (string=? (%np p %np-host) (%np p %np-dotted))) #f)
            (%nt-say (string-concat (list "'" (%np p %np-host) "' is " (%np p %np-dotted)))))
          (%np! p %np-refid (%nt-refid-of (first a)))
          (%np! p %np-dns 0)
          a))))

; add_peers: a peer for HOST, unless one has its address already
(def %nt-add-peer!
  (fn (_ host key)
    (def p (%nt-new-peer host key))
    (def dup (if (null? (%nt-resolve-peer! p)) ()
               (List find (fn (_ q) (if (null? (%np q %np-dotted)) #f (string=? (%np q %np-dotted) (%np p %np-dotted)))) %nt-peers)))
    (if (not (null? dup))
      (%nt-say (string-concat (list "duplicate peer " host " (" (%np p %np-dotted) ")")))
      (do (set! %nt-peers (pair p %nt-peers))
          (set! %nt-peer-cnt (+ %nt-peer-cnt 1))))))

; --- the exchange with a peer ---------------------------------------------------------

; the bytes of PROG's send to a peer: client mode, version 4, the transmit
; stamp random; with a key, its id and the digest
(def %nt-query
  (fn (_ p)
    (def head (append (list 35) (nt-zeros 39) (%np p %np-xmt)))
    (def key (%np p %np-key))
    (if (null? key) head
      (append head (nt-be-bytes (first key) 4) (%nt-hash key head)))))

(def %nt-sendto
  (fn (_ fd bytes sa)
    (def b (nt-raw bytes))
    (def r (in-call (cu-ptr-call (in-c "sendto") fd (cu-str->ptr b) (length bytes) in-dontwait
                                   (cu-str->ptr (first sa)) (cu-nth 1 sa))))
    (if (= r (length bytes)) 0
      (do (%nt-say (string-append "send failed: " (%nt-why (lit sendto)))) -1))))

; send_query_to_peer
(def %nt-send-query!
  (fn (_ p)
    (unless (null? (%np p %np-sa))
      (do (when (< (%np p %np-fd) 0)
            (let ((fam (%nt-family (first (%np p %np-sa)))))
              (let ((fd (in-call (cu-ptr-call (in-c "socket") fam 2 0))))
                (do (if (= fam 2)
                      (do (cu-ptr-call (in-c "bind") fd (cu-str->ptr (net-sockaddr "0.0.0.0" 0)) 16)
                          (let ((tos (str-make-raw 4)))
                            (do (cu-ptr-set! (cu-str->ptr tos) 0 72 4)
                                (cu-ptr-call (in-c "setsockopt") fd 0 3 (cu-str->ptr tos) 4))))
                      (let ((any (in-sockaddr6 () 0))) (cu-ptr-call (in-c "bind") fd (cu-str->ptr (first any)) (rest any))))
                    (%np! p %np-fd fd)))))
          (when (>= %nt-verbose 1) (%nt-say (string-append "sending query to " (%np p %np-dotted))))
          (%np! p %np-xmt (append (nt-be-bytes (%nt-random) 4) (nt-be-bytes (%nt-random) 4)))
          (%np! p %np-xmttime (%nt-now!))
          (%np! p %np-reach (& (* (%np p %np-reach) 2) 255))
          (if (< (%nt-sendto (%np p %np-fd) (%nt-query p) (%np p %np-sa)) 0)
            (do (sys-close (%np p %np-fd)) (%np! p %np-fd -1) (%nt-set-next! p 32))
            (%nt-set-next! p 16))))))

; run_script: -S PROG ACTION, not waited for
(def %nt-run-script
  (fn (_ action offset)
    (set! %nt-last-script %nt-cur)
    (unless (null? %nt-script)
      (do (when (>= %nt-verbose 1) (%nt-say (string-concat (list "executing '" %nt-script " " action "'"))))
          (when (= (sys-fork) 0)
            (do (sys-setenv "stratum" (%nt-u %nt-stratum))
                (sys-setenv "freq_drift_ppm" (%nt-u %nt-drift))
                (sys-setenv "poll_interval" (%nt-u (<< 1 %nt-poll)))
                (sys-setenv "offset" (%nt-f offset))
                (map (fn (_ n) (sys-signal n 0)) (list 13 (ts-signal-number "CHLD")))
                (let ((r (in-exec %nt-script (list %nt-script action))))
                  (do (%nt-say (string-concat (list "can't execute '" %nt-script "': " (in-errtext r))))
                      (sys-exit 111)))))))))

; strftime_YYYYMMDDHHMMSS
(def %nt-stamp (fn (_ secs) (cu-date-fmt "%Y-%m-%d %H:%M:%S" (cu-date-split secs #f) secs)))

(def %nt-timeval
  (fn (_ secs usecs)
    (def tv (in-zeroed 16))
    (cu-ptr-set! (cu-str->ptr tv) 0 secs 8)
    (cu-ptr-set! (cu-str->ptr tv) 8 usecs 4)
    tv))

; step_time
(def %nt-step!
  (fn (_ offset)
    (def tvc (si-now))
    (def dtime (%nt+ (%nt+ (first tvc) (%nt* (Float from "0.000001") (rest tvc))) offset))
    (def sec (%nt-trunc dtime))
    (def usec (%nt-trunc (%nt* (%nt- dtime sec) 1000000)))
    (when (< (in-call (cu-ptr-call (in-c "settimeofday") (cu-str->ptr (%nt-timeval sec usec)) 0)) 0)
      (%nt-die (string-append "settimeofday: " (%nt-why (lit settimeofday)))))
    (when (>= %nt-verbose 2)
      (%nt-say (string-concat (list "current time is " (%nt-stamp (first tvc)) "." (cu-pad-zero (%nt-u (rest tvc)) 6)))))
    (%nt-say (string-concat (list "setting time to " (%nt-stamp sec) "." (cu-pad-zero (%nt-u usec) 6) " (offset " (%nt-sf offset) "s)")))
    (set! %nt-cur (%nt+ %nt-cur offset))
    (set! %nt-last-recv (%nt+ %nt-last-recv offset))
    (set! %nt-last-script (%nt+ %nt-last-script offset))
    (map (fn (_ q)
           (do (%nt-reset-stats! q offset)
               (%np! q %np-next (%nt+ (%np q %np-next) offset))
               (when (>= (%np q %np-fd) 0)
                 (do (sys-close (%np q %np-fd)) (%np! q %np-fd -1) (%nt-set-next! q 32)))))
         %nt-peers)))

(def %nt-clamp!
  (fn (_)
    (when (< %nt-poll %nt-minpoll) (set! %nt-poll %nt-minpoll))
    (when (> %nt-poll %nt-bigpoll) (set! %nt-poll %nt-bigpoll))
    (set! %nt-polladj 0)
    (set! %nt-stratum %nt-maxstrat)))

; --- selection and clustering ----------------------------------------------------------

(def %nt-fit?
  (fn (_ p rd)
    (def reach (%np p %np-reach))
    (match
      ((= (& reach (- reach 1)) 0)
        (do (when (>= %nt-verbose 4) (%nt-say (string-concat (list "peer " (%np p %np-dotted) " unfit for selection: unreachable")))) #f))
      ((%nt< (%nt+ %nt-maxdist (%nt* %nt-tol (<< 1 %nt-poll))) rd)
        (do (when (>= %nt-verbose 3)
              (%nt-say (string-concat (list "peer " (%np p %np-dotted) " unfit for selection: root distance " (%nt-f rd)
                                            " too high, jitter:" (%nt-f (%np p %np-fjitter))))))
            #f))
      (#t #t))))

; select_and_cluster: the peer to take time from, or nil
(def %nt-select
  (fn (_)
    (def points
      (List sort (fn (_ a b) (%nt< (cu-nth 2 a) (cu-nth 2 b)))
        (List fold
          (fn (_ acc p)
            (let ((rd (%nt-root-distance p)) (off (%np p %np-foffset)))
              (if (not (%nt-fit? p rd)) acc
                (do (when (>= %nt-verbose 5)
                      (%nt-say (string-concat (list "interval: [" (%nt-f (%nt- off rd)) " " (%nt-f off) " " (%nt-f (%nt+ off rd)) "] " (%np p %np-dotted)))))
                    (append acc (list (list p -1 (%nt- off rd) rd) (list p 0 off rd) (list p 1 (%nt+ off rd) rd)))))))
          () %nt-peers)))
    (def pv (vec-build (length points) (fn (_ i) (cu-nth i points))))
    (def n (length points))
    (def cands (wget-div n 3))
    (if (= cands 0)
      (do (when (>= %nt-verbose 3) (%nt-say "no valid datapoints, no peer selected")) ())
      (%nt-intersect pv n cands 0))))

; the selection's intersection with FALSE falsetickers assumed, then the
; clustering of its survivors
(def %nt-intersect
  (fn (self pv n cands false)
    (def type (fn (_ i) (cu-nth 1 (vec-ref pv i))))
    (def edge (fn (_ i) (cu-nth 2 (vec-ref pv i))))
    (def need (- cands false))
    (def lo (let go ((i 0) (c 0) (mid 0))
              (if (>= i n) (pair (Float from -512) mid)
                (let ((c (- c (type i))))
                  (if (>= c need) (pair (edge i) mid) (go (+ i 1) c (if (= (type i) 0) (+ mid 1) mid)))))))
    (def hi (let go ((i (- n 1)) (c 0) (mid (rest lo)))
              (if (< i 0) (pair (Float from 512) mid)
                (let ((c (+ c (type i))))
                  (if (>= c need) (pair (edge i) mid) (go (- i 1) c (if (= (type i) 0) (+ mid 1) mid)))))))
    (match
      ((if (<= (rest hi) false) (%nt< (first lo) (first hi)) #f)
        (do (when (>= %nt-verbose 4)
              (%nt-say (string-concat (list "selected interval: [" (%nt-f (first lo)) ", " (%nt-f (first hi)) "]; candidates:"
                                            (%nt-u cands) " falsetickers:" (%nt-u false)))))
            (%nt-cluster pv n (first lo) (first hi))))
      ((>= (* (+ false 1) 2) cands)
        (do (when (>= %nt-verbose 3)
              (%nt-say (string-concat (list "falsetickers:" (%nt-u (+ false 1)) ", candidates:" (%nt-u cands) ", no peer selected"))))
            ()))
      (#t (self pv n cands (+ false 1))))))

(def %nt-cluster
  (fn (_ pv n low high)
    (def survivors
      (List sort (fn (_ a b) (%nt< (rest a) (rest b)))
        (let go ((i 0) (acc ()) (k 0))
          (if (>= i n) (reverse acc)
            (let ((pt (vec-ref pv i)))
              (if (if (%nt< (cu-nth 2 pt) low) #t (%nt< high (cu-nth 2 pt))) (go (+ i 1) acc k)
                (let ((s (pair (first pt) (%nt+ (* %nt-maxdist (%np (first pt) %np-pkt-stratum)) (cu-nth 3 pt)))))
                  (do (when (>= %nt-verbose 5)
                        (%nt-say (string-concat (list "survivor[" (%nt-u k) "] metric:" (%nt-f (rest s)) " peer:" (%np (first pt) %np-dotted)))))
                      (go (+ i 1) (pair s acc) (+ k 1))))))))))
    (if (null? survivors)
      (do (when (>= %nt-verbose 3) (%nt-say "survivors:0, no peer selected")) ())
      (%nt-pick (%nt-prune survivors)))))

; survivors dropped by most selection jitter while more than three are left
; and that jitter is not below the least peer jitter
(def %nt-prune
  (fn (self ss)
    (def k (length ss))
    (if (<= k 3)
      (do (when (>= %nt-verbose 4) (%nt-say (string-concat (list "num_survivors " (%nt-u k) " <= 3, not discarding more")))) ss)
      (let ((js (map (fn (_ s) (List fold (fn (_ acc q) (%nt+ acc (%nt-sq (%nt- (%np (first s) %np-foffset) (%np (first q) %np-foffset))))) (Float from 0) ss)) ss)))
        (def min-j (List fold (fn (_ acc s) (if (%nt< (%np (first s) %np-fjitter) acc) (%np (first s) %np-fjitter) acc))
                     (%np (first (first ss)) %np-fjitter) (rest ss)))
        (def max-at (let go ((i 1) (l (rest js)) (best 0) (bv (first js)))
                      (if (null? l) best (if (%nt< bv (first l)) (go (+ i 1) (rest l) i (first l)) (go (+ i 1) (rest l) best bv)))))
        (def max-j (%nt-sqrt (%nt/ (cu-nth max-at js) k)))
        (when (>= %nt-verbose 5)
          (%nt-say (string-concat (list "max_selection_jitter (at " (%nt-u max-at) "):" (%nt-f max-j) " min_jitter:" (%nt-f min-j)))))
        (if (%nt< max-j min-j)
          (do (when (>= %nt-verbose 4)
                (%nt-say (string-concat (list "max_selection_jitter:" (%nt-f max-j) " < min_jitter:" (%nt-f min-j)
                                              ", num_survivors:" (%nt-u k) ", not discarding more"))))
              ss)
          (self (let go ((i 0) (l ss) (acc ())) (if (null? l) (reverse acc) (go (+ i 1) (rest l) (if (= i max-at) acc (pair (first l) acc)))))))))))

; the first survivor, or the peer last taken when it is among them at no
; worse a stratum
(def %nt-pick
  (fn (_ ss)
    (def p (first (first ss)))
    (def keep? (if (null? %nt-last-peer) #f
                 (if (<= (%np %nt-last-peer %np-pkt-stratum) (%np p %np-pkt-stratum))
                   (List any? (fn (_ s) (eq? (first s) %nt-last-peer)) (rest ss)) #f)))
    (def q (if keep? (do (when (>= %nt-verbose 5) (%nt-say "keeping old synced peer")) %nt-last-peer)
             (do (set! %nt-last-peer p) p)))
    (when (>= %nt-verbose 4)
      (%nt-say (string-concat (list "selected peer " (%np q %np-dotted) " filter_offset:" (%nt-sf (%np q %np-foffset))
                                    " age:" (%nt-f (%nt- %nt-cur (%np q %np-pkt-recv)))))))
    q))

; --- the local clock -------------------------------------------------------------------

(def %nt-set-values!
  (fn (_ offset recv)
    (when (>= %nt-verbose 4) (%nt-say (string-concat (list "last update offset=" (%nt-f offset) " recv_time=" (%nt-f recv)))))
    (set! %nt-last-offset offset)
    (set! %nt-last-recv recv)))

; adjtimex, ntp_adjtime on Darwin, on a struct timex of BUF
(def %nt-adjtimex
  (fn (_ buf)
    (in-call (cu-ptr-call (in-c (if os-darwin? "ntp_adjtime" "adjtimex")) (cu-str->ptr buf)))))

(def %nt-s64 (fn (_ v) (if (>= v 9223372036854775807) (- v 18446744073709551616) v)))
(def %nt-tx (fn (_ buf off) (%nt-s64 (cu-ptr-ref (cu-str->ptr buf) off 8))))

; update_local_clock: 1 when the poll interval may grow, 0 to leave it
(def %nt-update-clock
  (fn (_ p)
    (def offset (%np p %np-foffset))
    (def recv (%np p %np-pkt-recv))
    (if (not (%nt< %nt-last-recv recv))
      (do (when (>= %nt-verbose 3) (%nt-say (string-concat (list "update from " (%np p %np-dotted) ": same or older datapoint, not using it")))) 0)
      (%nt-discipline p offset recv))))

(def %nt-discipline
  (fn (_ p offset0 recv0)
    (def big? (%nt< 1 (%nt-abs offset0)))
    (when big?
      (do (when (>= %nt-verbose 4) (%nt-say (string-concat (list "stepping time by " (%nt-sf offset0) "; poll_exp=MINPOLL"))))
          (%nt-step! offset0)
          (when %nt-q? (sys-exit 0))
          (%nt-clamp!)
          (%nt-run-script "step" offset0)
          (%nt-set-values! (Float from 0) (%nt+ recv0 offset0))))
    (def offset (if big? (Float from 0) offset0))
    (def abs-off (%nt-abs offset))
    (unless big?
      (do (when %nt-q? (sys-exit 0))
          (set! %nt-ratio (%nt-trunc (%nt/ abs-off %nt-djitter)))
          (let ((etemp (%nt-sq %nt-djitter)) (dtemp (%nt-sq (%nt- offset %nt-last-offset))))
            (set! %nt-djitter (%nt-sqrt (%nt+ etemp (%nt/ (%nt- dtemp etemp) 4)))))
          (when (%nt< %nt-djitter %nt-prec) (set! %nt-djitter %nt-prec))
          (%nt-set-values! offset recv0)
          (unless (= %nt-stratum (+ (%np p %np-pkt-stratum) 1))
            (do (set! %nt-stratum (+ (%np p %np-pkt-stratum) 1))
                (%nt-run-script "stratum" offset)))))
    (set! %nt-reftime %nt-cur)
    (set! %nt-status (%np p %np-pkt-status))
    (set! %nt-refid (%np p %np-refid))
    (set! %nt-rootdelay (%nt+ (%np p %np-pkt-rootdelay) (%np p %np-pkt-delay)))
    (set! %nt-rootdisp
      (%nt+ (%np p %np-pkt-rootdisp)
            (%nt+ (%np p %np-fjitter)
                  (%nt-max (%nt+ (%nt+ (%np p %np-fdisp) (%nt* %nt-tol (%nt- %nt-cur (%np p %np-pkt-recv)))) abs-off) %nt-mindisp))))
    (when (>= %nt-verbose 4) (%nt-say (string-append "updating leap/refid/reftime/rootdisp from peer " (%np p %np-dotted))))
    (when (>= %nt-verbose 4)
      (let ((t (in-zeroed 256)))
        (do (when (< (%nt-adjtimex t) 0) (%nt-die (string-append "adjtimex: " (%nt-why (lit adjtimex)))))
            (%nt-say (string-concat (list "p adjtimex freq:" (%nt-dec (%nt-tx t 16)) " offset:" (%nt-sdec (%nt-tx t 8))
                                          " status:0x" (cu-hexs (cu-ptr-ref (cu-str->ptr t) 40 4)) " tc:" (%nt-dec (%nt-tx t 48))))))))
    (%nt-kernel! p offset)))

(def %nt-dec (fn (_ n) (if (< n 0) (string-append "-" (%nt-u (- 0 n))) (%nt-u n))))
(def %nt-sdec (fn (_ n) (if (< n 0) (%nt-dec n) (string-append "+" (%nt-u n)))))

; the adjtimex call: the offset slewed (at most half a second), the PLL's
; time constant, the error estimates; the kernel's drift kept
(def %nt-kernel!
  (fn (_ p offset)
    (def t (in-zeroed 256))
    (def tp (cu-str->ptr t))
    (def us (%nt-imax -500000 (nt-imin 500000 (%nt-trunc (%nt* offset 1000000)))))
    (def freqhold
      (match ((= %nt-freqhold 0) 0)
            (#t (do (when (< %nt-freqhold 0) (set! %nt-freqhold (+ 11 (%nt-iabs (wget-div (if (< us 0) (- us 32767) us) 32768)))))
                    (set! %nt-freqhold (- %nt-freqhold 1))
                    128))))
    (def status (+ 1 freqhold (if (= (& %nt-status 64) 0) 0 16) (if (= (& %nt-status 128) 0) 0 32)))
    (def tc (%nt-imax 0 (- (- %nt-poll 4) (if (>= %nt-ratio 2) 1 0))))
    (cu-ptr-set! tp 0 (+ 1 16 32 4 8) 4)
    (cu-ptr-set! tp 8 us 8)
    (cu-ptr-set! tp 40 status 4)
    (cu-ptr-set! tp 48 tc 8)
    (cu-ptr-set! tp 24 (%nt-trunc (%nt* (%nt+ (%nt/ %nt-rootdelay 2) %nt-rootdisp) 1000000)) 8)
    (cu-ptr-set! tp 32 (%nt-trunc (%nt* %nt-djitter 1000000)) 8)
    (def rc (%nt-adjtimex t))
    (when (< rc 0) (%nt-die (string-append "adjtimex: " (%nt-why (lit adjtimex)))))
    (def freq (%nt-tx t 16))
    (when (>= %nt-verbose 4)
      (%nt-say (string-concat (list "adjtimex:" (%nt-dec rc) " freq:" (%nt-dec freq) " offset:" (%nt-sdec (%nt-tx t 8))
                                    " esterror:" (%nt-dec (%nt-tx t 32)) " maxerror:" (%nt-dec (%nt-tx t 24))
                                    " status:0x" (cu-hexs (cu-ptr-ref tp 40 4))))))
    (set! %nt-drift (if (< freq 0) (- 0 (wget-div (- 0 freq) 65536)) (wget-div freq 65536)))
    (when (>= %nt-verbose 2)
      (%nt-say (string-concat (list "update from:" (%np p %np-dotted) " offset:" (%nt-sf offset) " delay:" (%nt-f (%np p %np-raw-delay))
                                    " jitter:" (%nt-f %nt-djitter) " clock drift:" (%nt-sf3 (%nt/ freq 65536)) "ppm tc:"
                                    (%nt-dec (%nt-tx t 48))))))
    1))

; --- the poll interval ---------------------------------------------------------------------

(def %nt-poll-interval
  (fn (_ upper)
    (def interval (nt-imin (<< 1 %nt-poll) upper))
    (def r (+ interval (& (%nt-random) (| (>> (- interval 1) 4) 1))))
    (when (>= %nt-verbose 4) (%nt-say (string-concat (list "chose poll interval:" (%nt-u r) " (poll_exp:" (%nt-u %nt-poll) ")"))))
    r))

(def %nt-adjust-poll!
  (fn (_ count)
    (set! %nt-polladj (+ %nt-polladj count))
    (match
      ((> %nt-polladj %nt-polladj-limit)
        (do (set! %nt-polladj 0)
            (when (< %nt-poll %nt-maxpoll)
              (do (set! %nt-poll (+ %nt-poll 1))
                  (when (>= %nt-verbose 4)
                    (%nt-say (string-concat (list "polladj: discipline_jitter:" (%nt-f %nt-djitter) " ++poll_exp=" (%nt-u %nt-poll)))))))))
      ((if (< %nt-polladj (- 0 %nt-polladj-limit)) #t (if (< count 0) (> %nt-poll %nt-bigpoll) #f))
        (do (set! %nt-polladj 0)
            (when (> %nt-poll %nt-minpoll)
              (do (set! %nt-poll (- %nt-poll 1))
                  (map (fn (_ q) (when (< (%np q %np-fd) 0) (%np! q %np-next (%nt- (%np q %np-next) (<< 1 %nt-poll))))) %nt-peers)
                  (when (>= %nt-verbose 4)
                    (%nt-say (string-concat (list "polladj: discipline_jitter:" (%nt-f %nt-djitter) " --poll_exp=" (%nt-u %nt-poll)))))))))
      (#t (when (>= %nt-verbose 4) (%nt-say (string-append "polladj: count:" (%nt-dec %nt-polladj))))))))

; --- a peer's reply ------------------------------------------------------------------------

(def %nt-recv
  (fn (_ fd)
    (def buf (str-make-raw 72))
    (def r (in-call (cu-ptr-call (in-c "recv") fd (cu-str->ptr buf) 72 in-dontwait)))
    (if (< r 0) (pair () r) (pair (%nt-bytes buf r) r))))

; recv_and_process_peer_pkt
(def %nt-peer-reply!
  (fn (_ p)
    (unless (< (%np p %np-fd) 0)
      (let ((got (%nt-recv (%np p %np-fd))))
        (def size (rest got))
        (def m (first got))
        (match
          ((< size 0)
            (unless (= (Err errno-of -1) (if os-darwin? 35 11))
              (%nt-die (string-concat (list "recv(" (%np p %np-dotted) ") error: " (%nt-why (lit recv)))))))
          ((not (wget-memv size (list 48 68 72)))
            (%nt-say (string-concat (list "malformed packet received from " (%np p %np-dotted) ": size " (%nt-u size)))))
          ((if (null? (%np p %np-key)) #f
             (not (equal? (%nt-hash (%np p %np-key) (%nt-vec->list m 0 48))
                          (%nt-vec->list m 52 (nt-imin size (+ 52 (length (%nt-hash (%np p %np-key) ()))))))))
            (%nt-say (string-append "invalid cryptographic hash received from " (%np p %np-dotted))))
          ((not (equal? (%nt-vec->list m 24 32) (%np p %np-xmt))) ())
          (#t (do (sys-close (%np p %np-fd)) (%np! p %np-fd -1) (%nt-reply! p m))))))))

(def %nt-reply!
  (fn (_ p m)
    (def status (vec-ref m 0))
    (def stratum (vec-ref m 1))
    (if (match ((= (& status 192) 192) #t) ((= stratum 0) #t) (#t (> stratum 15)))
      (do (%nt-say (string-concat (list "reply from " (%np p %np-dotted) ": peer is unsynced")))
          (when (< %nt-poll %nt-bigpoll) (%nt-adjust-poll! %nt-minpoll))
          (%nt-next-query! p (Float from 0)))
      (%nt-take-reply! p m))))

(def %nt-take-reply!
  (fn (_ p m)
    (def t1 (%np p %np-xmttime))
    (def t2 (%nt-lfp->d m 32))
    (def t3 (%nt-lfp->d m 40))
    (def t4 %nt-cur)
    (def delay0 (%nt- (%nt- t4 t1) (%nt- t3 t2)))
    (def prev (%np p %np-raw-delay))
    (%np! p %np-raw-delay (if (%nt< delay0 0) (Float from 0) delay0))
    (if (match ((= (%np p %np-reach) 0) #f) ((not (%nt< (%nt* prev 4) delay0)) #f) (#t (%nt< (%nt/ 1 8192) delay0)))
      (do (%nt-say (string-concat (list "reply from " (%np p %np-dotted) ": delay " (%nt-f delay0) " is too high, ignoring")))
          (%nt-next-query! p (Float from 0)))
      (%nt-datapoint! p m t1 t2 t3 t4 (if (%nt< delay0 %nt-prec) %nt-prec delay0)))))

(def %nt-datapoint!
  (fn (_ p m t1 t2 t3 t4 delay)
    (%np! p %np-pkt-delay delay)
    (%np! p %np-pkt-recv t4)
    (%np! p %np-pkt-status (vec-ref m 0))
    (%np! p %np-pkt-stratum (vec-ref m 1))
    (%np! p %np-pkt-rootdelay (%nt-sfp->d m 4))
    (%np! p %np-pkt-rootdisp (%nt-sfp->d m 8))
    (%np! p %np-pkt-refid (%nt-le32 m 12))
    (%np! p %np-idx (if (= (%np p %np-reach) 0) 0 (% (+ (%np p %np-idx) 1) 8)))
    (def offset (%nt/ (%nt+ (%nt- t2 t1) (%nt- t3 t4)) 2))
    (def i (%np p %np-idx))
    (def pexp (vec-ref m 3))
    (%nt-dp! p i 1 t4)
    (%nt-dp! p i 0 offset)
    (%nt-dp! p i 2 (%nt+ (%nt-pow2 (if (> pexp 127) (- pexp 256) pexp)) %nt-prec))
    (when (= (%np p %np-reach) 0)
      (let go ((k 0)) (when (< k 8) (do (%nt-dp! p k 0 offset) (go (+ k 1))))))
    (%np! p %np-reach (| (%np p %np-reach) 1))
    (when (if (>= %nt-verbose 1) #t %nt-w?)
      (%nt-say (string-concat (list "reply from " (%np p %np-dotted) ": offset:" (%nt-sf offset) " delay:" (%nt-f (%np p %np-raw-delay))
                                    " status:0x" (%nt-hex (%np p %np-pkt-status) 2) " strat:" (%nt-u (%np p %np-pkt-stratum))
                                    " refid:0x" (%nt-hex (%np p %np-pkt-refid) 8) " rootdelay:" (%nt-f (%np p %np-pkt-rootdelay))
                                    " reach:0x" (%nt-hex (%np p %np-reach) 2)))))
    (%nt-filter! p)
    (def q (%nt-select))
    (def rc (if (if (null? q) #t %nt-w?) 0 (%nt-update-clock q)))
    (match
      ((if (null? q) (< %nt-poll %nt-bigpoll) #f) (%nt-adjust-poll! %nt-minpoll))
      ((= rc 0) ())
      ((if (> rc 0) (<= %nt-ratio 4) #f) (%nt-adjust-poll! %nt-minpoll))
      (#t (do (when (if (>= %nt-verbose 3) (> rc 0) #f)
                (%nt-say (string-append "want smaller interval: offset/jitter = " (%nt-u %nt-ratio))))
              (%nt-adjust-poll! (- 0 (* %nt-poll 2))))))
    (%nt-next-query! p offset)))

; pick_normal_interval
(def %nt-next-query!
  (fn (_ p offset)
    (def interval (%nt-poll-interval 2147483647))
    (%nt-set-next! p (if (if (%nt< (%nt-abs offset) 1) #f (> interval 128)) 128 interval))))

; --- the server ----------------------------------------------------------------------------

; recv_and_process_client_pkt
(def %nt-client-query!
  (fn (_)
    (def buf (str-make-raw 72))
    (def sa (in-zeroed 128))
    (def len (str-make-raw 4))
    (cu-ptr-set! (cu-str->ptr len) 0 128 4)
    (def size (in-call (cu-ptr-call (in-c "recvfrom") %nt-listen (cu-str->ptr buf) 72 in-dontwait (cu-str->ptr sa) (cu-str->ptr len))))
    (def salen (cu-ptr-ref (cu-str->ptr len) 0 4))
    (match
      ((< size 0)
        (unless (= (Err errno-of -1) (if os-darwin? 35 11)) (%nt-die (string-append "recv: " (%nt-why (lit recv))))))
      ((not (wget-memv size (list 48 68 72)))
        (%nt-say (string-concat (list "malformed packet received from " (%nt-dotted sa) ": size " (%nt-u size)))))
      (#t (let ((m (%nt-bytes buf size)))
            (let ((mode (& (vec-ref m 0) 7)))
              (when (if (= mode 3) #t (= mode 1))
                (do (%nt-sendto %nt-listen (%nt-server-reply m size) (list sa salen))
                    (when (>= %nt-verbose 3) (%nt-say (string-append "responded to query from " (%nt-dotted sa))))))))))))

(def %nt-server-reply
  (fn (_ m size)
    (def q-status (vec-ref m 0))
    (def rectime %nt-cur)
    (when (= %nt-peer-cnt 0) (set! %nt-reftime %nt-cur))
    (def status (+ (if (< %nt-stratum %nt-maxstrat) (& %nt-status 192) 192)
                   (& q-status 56)
                   (if (= (& q-status 7) 3) 4 2)))
    (append (list status %nt-stratum %nt-poll (+ 256 %nt-prec-exp))
            (%nt-d->sfp %nt-rootdelay) (%nt-d->sfp %nt-rootdisp) %nt-refid
            (%nt-d->lfp %nt-reftime) (%nt-vec->list m 40 48) (%nt-d->lfp rectime) (%nt-d->lfp (%nt-now!))
            (nt-zeros (- size 48)))))

; create_and_bind_dgram_or_die(NULL, 123): IPv6's any address, else IPv4's
(def %nt-listen!
  (fn (_ iface)
    (def fd6 (in-call (cu-ptr-call (in-c "socket") %nt-af6 2 0)))
    (def fd (if (>= fd6 0) fd6 (in-call (cu-ptr-call (in-c "socket") 2 2 0))))
    (when (< fd 0) (%nt-die (string-append "socket: " (%nt-why (lit socket)))))
    (in-reuse! fd)
    (def sa (if (>= fd6 0) (in-sockaddr6 () %nt-server-port) (pair (net-sockaddr "0.0.0.0" %nt-server-port) 16)))
    (when (< (in-call (cu-ptr-call (in-c "bind") fd (cu-str->ptr (first sa)) (rest sa))) 0)
      (%nt-die (string-append "bind: " (%nt-why (lit bind)))))
    (unless (null? iface) (%nt-bind-iface! fd iface (>= fd6 0)))
    (set! %nt-listen fd)))

; setsockopt_bindtodevice: SO_BINDTODEVICE, on Darwin IP_BOUND_IF (IPV6_BOUND_IF)
(def %nt-bind-iface!
  (fn (_ fd iface v6?)
    (def r
      (if os-darwin?
        (let ((idx (in-call (cu-ptr-call (in-c "if_nametoindex") iface))) (v (str-make-raw 4)))
          (do (cu-ptr-set! (cu-str->ptr v) 0 idx 4)
              (if (= idx 0) -1 (in-call (cu-ptr-call (in-c "setsockopt") fd (if v6? 41 0) (if v6? 125 25) (cu-str->ptr v) 4)))))
        (let ((name (nt-raw (append (tn-str-bytes iface) (list 0)))))
          (in-call (cu-ptr-call (in-c "setsockopt") fd 1 25 (cu-str->ptr name) (+ (byte-len iface) 1))))))
    (when (< r 0) (%nt-die (string-concat (list "can't bind to interface " iface ": " (%nt-why (lit setsockopt))))))))

; --- the configuration ---------------------------------------------------------------------

; config_open: the lines of FILE, or nil said as a warning
(def %nt-config-lines
  (fn (_ file shown)
    (def text (guard (e e) (if (string=? file "-") (file-read-all 0) (file-read-all file))))
    (match ((Err err? text) (do (%nt-say (string-concat (list shown ": " (wget-err-text text)))) ()))
           ((null? text) (do (%nt-say (string-concat (list shown ": " (tar-why (lit open) shown)))) ()))
           (#t (in-lines text)))))

; the keys of -k's FILE: (ID TYPE MSGSIZE KEYBYTES), the last read first
(def %nt-keys
  (fn (_ file)
    (List fold
      (fn (_ acc l)
        (let ((t (in-tokens-max (rest l) 4)))
          (match
            ((null? t) acc)
            ((< (length t) 3)
              (%nt-die (string-concat (list "bad line " (%nt-u (first l)) ": " (%nt-u (length t)) " tokens found, 3 needed"))))
            (#t (pair (%nt-key (first l) t) acc)))))
      () (%nt-config-lines file file))))

(def %nt-key
  (fn (_ lineno t)
    (def type (cu-nth 1 t))
    (def md5? (string=? (Str8 downcase (substring type 0 1)) "m"))
    (unless (if md5? #t (if (>= (byte-len type) 3) (mm-ci= (substring type 0 3) "sha") #f))
      (%nt-die "only MD5 and SHA1 keys supported"))
    (def key (cu-nth 2 t))
    (def bad (fn (_) (%nt-die (string-append "malformed key at line " (%nt-u lineno)))))
    (when (>= (byte-len key) 41) (bad))
    (def bytes
      (match (md5? (tn-str-bytes key))
             ((= (& (byte-len key) 1) 1) (bad))
             (#t (let ((b (nt-unhex key))) (if (null? b) (bad) b)))))
    (list (%nt-range (first t) 1 65535) (if md5? (lit md5) (lit sha1)) (if md5? 68 72) bytes)))

; hex2bin: the bytes of hex text S, or nil
(def nt-unhex
  (fn (_ s)
    (def v (fn (_ c) (match ((if (>= c #\0) (<= c #\9) #f) (- c #\0)) ((if (>= c #\a) (<= c #\f) #f) (+ 10 (- c #\a)))
                            ((if (>= c #\A) (<= c #\F) #f) (+ 10 (- c #\A))) (#t ()))))
    (let go ((i 0) (acc ()))
      (if (>= i (byte-len s)) (reverse acc)
        (let ((a (v (byte-at s i))) (b (v (byte-at s (+ i 1)))))
          (if (if (null? a) #t (null? b)) () (go (+ i 2) (pair (+ (* a 16) b) acc))))))))

; xatou_range
(def %nt-range
  (fn (_ s lo hi)
    (def n (in-strtou s))
    (match ((null? n) (%nt-die (string-concat (list "invalid number '" s "'"))))
           ((if (< n lo) #t (> n hi)) (%nt-die (string-concat (list "number " s " is not in " (%nt-u lo) ".." (%nt-u hi) " range"))))
           (#t n))))

(def %nt-find-key
  (fn (_ keys id)
    (let ((k (List find (fn (_ k) (= (first k) id)) keys)))
      (if (null? k) (%nt-die (string-concat (list "key " (%nt-u id) " is not defined"))) k))))

; -p's peers, a keyno:N: prefix naming a key
(def %nt-peer-arg!
  (fn (_ arg keys)
    (if (Str8 starts? "keyno:" arg)
      (let ((rest (substring arg 6 (byte-len arg))))
        (let ((c (wget-index rest #\: 0)))
          (if (null? c) (Err raise (lit usage) "" ())
            (%nt-add-peer! (substring rest (+ c 1) (byte-len rest))
                           (%nt-find-key keys (%nt-range (substring rest 0 c) 1 65535))))))
      (%nt-add-peer! arg ()))))

; /etc/ntp.conf's server lines
(def %nt-conf-peers!
  (fn (_ keys)
    (map (fn (_ l)
           (let ((t (in-tokens-max (rest l) 5)))
             (match
               ((null? t) ())
               ((if (string=? (first t) "server") (> (length t) 1) #f)
                 (%nt-add-peer! (cu-nth 1 t)
                   (if (if (> (length t) 3) (string=? (cu-nth 2 t) "key") #f)
                     (%nt-find-key keys (%nt-range (cu-nth 3 t) 1 65535)) ())))
               (#t (%nt-say (string-concat (list "skipping /etc/ntp.conf:" (%nt-u (first l)) ": unimplemented command '" (first t) "'")))))))
         (%nt-config-lines %nt-conf-file "/etc/ntp.conf"))))

; --- the applet ------------------------------------------------------------------------------

(def cu-ntpd
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "ntpd" argv))
    (if (not (null? (Opts operands o))) (cu-usage "ntpd")
      (guard (e (match ((eq? (Err label e) (lit net)) (do (%nt-say (e msg)) 1))
                       ((eq? (Err label e) (lit usage)) (cu-usage "ntpd"))
                       (#t (error e))))
        (%nt-main o argv)))))

(def %nt-init!
  (fn (_ o)
    (set! %nt-rand (sys-getpid))
    (set! %nt-peers ())
    (set! %nt-peer-cnt 0)
    (set! %nt-refid (list 0 0 0 0))
    (set! %nt-status 0)
    (set! %nt-poll 0)
    (set! %nt-polladj 0)
    (set! %nt-drift 0)
    (set! %nt-last-peer ())
    (set! %nt-listen -1)
    (set! %nt-djitter %nt-prec)
    (set! %nt-stratum %nt-maxstrat)
    (%nt-now!)
    (set! %nt-last-script %nt-cur)
    (set! %nt-reftime %nt-cur)
    (set! %nt-last-recv %nt-cur)
    (set! %nt-last-offset (Float from 0))
    (set! %nt-rootdelay (Float from 0))
    (set! %nt-rootdisp (Float from 0))
    (set! %nt-freqhold -1)
    (set! %nt-ratio 0)
    (set! %nt-verbose (nc-count o "-d"))
    (set! %nt-w? (Opts on? o "-w"))
    (set! %nt-q? (Opts on? o "-q"))
    (set! %nt-alarm-at ())
    (set! %nt-alarm-long? #f)
    (set! %nt-got-sig ())
    (set! %nt-script (Opts value o "-S"))))

(def %nt-main
  (fn (_ o argv)
    (%nt-init! o)
    (def n? (if (Opts on? o "-n") #t %nt-w?))
    (def iface (Opts value o "-I"))
    (when (if (Opts on? o "-l") #t (not (null? iface))) (%nt-listen! iface))
    (when (Opts on? o "-N") (cu-ptr-call (in-c "setpriority") 0 0 -15))
    (unless n? (%nt-daemonize!))
    (def keys (if (Opts on? o "-k") (%nt-keys (Opts value o "-k")) ()))
    (if (null? (Opts values o "-p")) (%nt-conf-peers! keys)
      (map (fn (_ a) (%nt-peer-arg! a keys)) (Opts values o "-p")))
    (when (= %nt-peer-cnt 0)
      (if (< %nt-listen 0) (Err raise (lit usage) "" ()) (set! %nt-stratum 1)))
    (unless n? (guard (_ ()) (file-write-all "/var/run/ntpd.pid" (string-append (%nt-u (sys-getpid)) "\n"))))
    (when %nt-q? (set! %nt-alarm-at (%nt+ %nt-cur 10)))
    (set! %nt-sigs (map ts-signal-number (list "TERM" "INT" "ALRM")))
    (map (fn (_ n) (Sys catch-signal n)) %nt-sigs)
    (sys-signal 13 cu-sig-ign)
    (sys-signal (ts-signal-number "CHLD") cu-sig-ign)
    (def sig (%nt-loop (* %nt-peer-cnt 4)))
    (unless n? (guard (_ ()) (file-unlink "/var/run/ntpd.pid")))
    (sys-signal sig 0)
    (sys-kill (sys-getpid) sig)
    (+ 128 sig)))

; bb_daemonize: the parent gone, the child its own session, stdio on /dev/null
(def %nt-daemonize!
  (fn (_)
    (unless (= (sys-fork) 0) (sys-exit 0))
    (cu-ptr-call (in-c "setsid"))
    (let ((null (file-open-or-err file-open-read "/dev/null")))
      (unless (Err err? null)
        (do (sys-dup2 null 0) (sys-dup2 null 1) (sys-dup2 null 2))))))

; the signal that ends the run, when one has come; -q's alarm as SIGALRM
(def %nt-signal
  (fn (_)
    (when (null? %nt-got-sig) (set! %nt-got-sig (List find (fn (_ n) (Sys take-signal n)) %nt-sigs)))
    (match ((not (null? %nt-got-sig)) %nt-got-sig)
           ((if (null? %nt-alarm-at) #f (not (%nt< (%nt-now!) %nt-alarm-at))) (cu-nth 2 %nt-sigs))
           (#t ()))))

; the main loop: COUNT queries until the burst ends; the signal it ends by
(def %nt-loop
  (fn (self count)
    (cu-sweep-tick! cu-sweep-lines)
    (def sig (%nt-signal))
    (if (not (null? sig)) sig
      (let ((count (%nt-pass count)))
        (self count)))))

; one pass: queries sent and timed out, a poll, what came in
(def %nt-pass
  (fn (_ count0)
    (def next0 (%nt+ %nt-last-script 660))
    (def nextaction (if (%nt< next0 (%nt+ %nt-cur 1)) (%nt+ %nt-cur 1) next0))
    (def state
      (List fold
        (fn (_ st p)
          (let ((count (first st)) (na (rest st)))
            (def count2
              (if (%nt< %nt-cur (%np p %np-next)) count
                (if (< (%np p %np-fd) 0)
                  (let ((c (- count 1)))
                    (do (when (= c 0)
                          (do (when (>= %nt-verbose 4) (%nt-say "disabling burst mode"))
                              (set! %nt-polladj 0) (set! %nt-poll %nt-minpoll)))
                        (%nt-send-query! p)
                        c))
                  (do (%nt-timed-out! p) count))))
            (pair count2 (if (%nt< (%np p %np-next) na) (%np p %np-next) na))))
        (pair count0 nextaction) %nt-peers))
    (def waiting (filter (fn (_ p) (>= (%np p %np-fd) 0)) %nt-peers))
    (def fds (append (if (< %nt-listen 0) () (list %nt-listen)) (map (fn (_ p) (%np p %np-fd)) waiting)))
    (def timeout (+ 1 (%nt-imax 0 (%nt-trunc (%nt- (rest state) %nt-cur)))))
    (def say-poll
      (fn (_ t) (when (>= %nt-verbose 3)
                  (%nt-say (string-concat (list "poll:" (%nt-u t) "s sockets:" (%nt-u (length fds)) " interval:" (%nt-u (<< 1 %nt-poll)) "s"))))))
    ; -ddd with a reply awaited: a second's poll first, unsaid, as replies
    ; mostly come within one
    (def ready
      (if (if (>= %nt-verbose 3) (not (null? waiting)) #f)
        (let ((soon (%nt-poll-for fds 1000)))
          (match ((not (null? soon)) soon)
                 ((<= (- timeout 1) 0) ())
                 (#t (do (say-poll (- timeout 1)) (%nt-poll-for fds (* (- timeout 1) 1000))))))
        (do (say-poll timeout) (%nt-poll-for fds (* timeout 1000)))))
    (%nt-now!)
    (if (null? ready) (when (null? (%nt-signal)) (%nt-idle!))
      (do (when (if (>= %nt-listen 0) (wget-memv %nt-listen ready) #f)
            (do (%nt-client-query!) (%nt-now!)))
          (map (fn (_ p)
                 (when (if (>= (%np p %np-fd) 0) (wget-memv (%np p %np-fd) ready) #f)
                   (do (when (if %nt-q? (not %nt-alarm-long?) #f)
                         (do (set! %nt-alarm-long? #t) (set! %nt-alarm-at (%nt+ %nt-cur 50))))
                       (%nt-peer-reply! p)
                       (%nt-now!))))
               waiting)))
    (%nt-check-unsync!)
    (first state)))

; poll() in slices short enough to see a signal: the descriptors ready, or nil
(def %nt-poll-for
  (fn (self fds ms)
    (def slice (nt-imin ms 250))
    ; poll() with nothing to watch still waits out its time
    (def ready (if (null? fds) (do (sys-usleep (* slice 1000)) ())
                 (sys-poll (map (fn (_ fd) (pair fd (list (lit in)))) fds) slice)))
    (match ((not (null? ready)) (map first ready))
           ((<= ms slice) ())
           ((not (null? (%nt-signal))) ())
           (#t (self fds (- ms slice))))))

(def %nt-timed-out!
  (fn (_ p)
    (sys-close (%np p %np-fd))
    (%np! p %np-fd -1)
    (when (< %nt-poll %nt-bigpoll) (%nt-adjust-poll! %nt-minpoll))
    (def t (%nt-poll-interval 512))
    (%nt-say (string-concat (list "timed out waiting for " (%np p %np-dotted) ", reach 0x" (%nt-hex (%np p %np-reach) 2)
                                  ", next query in " (%nt-u t) "s")))
    (when (= (%np p %np-reach) 0) (%nt-resolve-peer! p))
    (%nt-set-next! p t)))

; the poll timed out: the periodic script, the names not resolved yet
(def %nt-idle!
  (fn (_)
    (when (%nt< 660 (%nt- %nt-cur %nt-last-script))
      (do (%nt-run-script "periodic" %nt-last-offset) (%nt-now!)))
    (def ct %nt-cur)
    (def due (filter (fn (_ p) (if (%nt< ct (%np p %np-next)) #f (null? (%np p %np-sa)))) %nt-peers))
    (def failed (filter (fn (_ p) (null? (%nt-resolve-peer! p))) due))
    (unless (null? failed)
      (do (%nt-now!)
          (map (fn (_ p) (%nt-set-next! p (* 4 (%np p %np-dns)))) failed)))))

(def %nt-check-unsync!
  (fn (_)
    (when (if (null? %nt-peers) #f (not (= %nt-stratum %nt-maxstrat)))
      (unless (List any? (fn (_ p) (> (%np p %np-reach) 0)) %nt-peers)
        (do (%nt-clamp!) (%nt-run-script "unsync" (Float from 0)))))))

(provide cu/ntpd cu-ntpd nt-be-bytes nt-imin nt-raw nt-unhex nt-zeros)

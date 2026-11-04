; # x-coreutils -- the small tools, as applets
;
; ## cu/rdate.x -- rdate: the time asked of a server by RFC 868, set and shown
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; util-linux/rdate.c: HOST, port 37 unless HOST:PORT names one, sends four
; bytes, the seconds since 1900 in network order.  They are the low 32 bits of
; the time, read as the one nearest the clock here.  With no option the clock
; is set to it and it is shown, ctime's way; -s only sets it, -p only shows it,
; and -sp shows it.  A clock already at that second is not set:
; "current time matches remote time" says so.  No connection and no answer in
; ten seconds ends the run, as busybox's alarm does.

(module cu/rdate)

(import cu/cli cu-opts cu-usage)
(import cu/date cu-date-fmt cu-date-split)
(import cu/inetd in-call in-errtext in-now in-zeroed)
(import cu/net cu-dial)
(import cu/prims byte-at cu-libc-sym cu-ptr-call cu-ptr-set! cu-str->ptr
  file-read-run file-write)

(def %rd-bias 2208988800)                ; RFC 868's 1970-01-01 00:00 GMT
(def %rd-wrap 4294967296)

(def %rd-die (fn (_ msg) (Err raise (lit net) msg ())))

; the run's end when the alarm is what interrupted it
(def %rd-timed-out!
  (fn (_)
    (when (Sys take-signal 14) (%rd-die "timeout connecting to time server"))))

; the four bytes' seconds since 1970 as the time within 2^31 seconds of NOW
(def %rd-near
  (fn (_ buf now)
    (def n (+ (* (byte-at buf 0) 16777216) (* (byte-at buf 1) 65536)
              (* (byte-at buf 2) 256) (byte-at buf 3)))
    (let go ((d (- (- n %rd-bias) now)))
      (match ((>= d 2147483648) (go (- d %rd-wrap)))
             ((< d -2147483648) (go (+ d %rd-wrap)))
             (#t (+ now d))))))

; askremotedate
(def %rd-ask
  (fn (_ host)
    (Sys catch-signal 14)
    (cu-ptr-call (cu-libc-sym "alarm") 10)
    (def fd (guard (e (do (%rd-timed-out!) (error e))) (cu-dial host 37)))
    (def r (file-read-run fd 4))
    (%rd-timed-out!)
    (when (< (rest r) 4) (%rd-die (string-append host ": short read")))
    (%rd-near (first r) (in-now))))

; xsettimeofday
(def %rd-set!
  (fn (_ secs)
    (def tv (in-zeroed 16))
    (cu-ptr-set! (cu-str->ptr tv) 0 secs 8)
    (let ((r (cu-ptr-call (cu-libc-sym "settimeofday") (cu-str->ptr tv) 0)))
      (when (< (in-call r) 0) (%rd-die (string-append "settimeofday: " (in-errtext r)))))))

(def %rd-main
  (fn (_ o host)
    (def s? (Opts on? o "-s"))
    (def p? (Opts on? o "-p"))
    (def remote (%rd-ask host))
    (unless p?
      (if (= (in-now) remote)
        (file-write 2 "rdate: current time matches remote time\n")
        (%rd-set! remote)))
    (unless (if s? (not p?) #f)
      (file-write 1 (string-append (cu-date-fmt "%a %b %e %H:%M:%S %Y" (cu-date-split remote #f) remote) "\n")))
    0))

(def cu-rdate
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "rdate" argv))
    (def ops (Opts operands o))
    (if (null? ops) (cu-usage "rdate")
      (guard (e (match ((if (eq? (Err label e) (lit net)) #t (eq? (Err label e) (lit io)))
                         (do (file-write 2 (string-append "rdate: " (e msg) "\n")) 1))
                       (#t (error e))))
        (%rd-main o (first ops))))))

(provide cu/rdate cu-rdate)

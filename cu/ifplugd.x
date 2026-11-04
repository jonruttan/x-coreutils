; # x-coreutils -- the small tools, as applets
;
; ## cu/ifplugd.x -- ifplugd: a script run as an interface's link comes and goes
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's ifplugd (networking/ifplugd.c).  IFACE (-i, eth0) is brought up
; and its link read every -t seconds (1): through SIOCETHTOOL, the MII
; registers, SIOCDEVPRIVATE, the wireless access point or IFF_RUNNING, -m
; naming one, or the first that answers.  A change of link that holds for
; -u seconds (0) up, -d (5) down, runs "SCRIPT IFACE up" or "SCRIPT IFACE
; down" (-r, /etc/ifplugd/ifplugd.action; -x adds a word), with
; IFPLUGD_PREVIOUS and IFPLUGD_CURRENT the link before and now.  A link up
; at the start runs the script too (-p: not; -l: whatever the link); a
; script that ends other than 0 ends the run (-I: not).  SIGINT and SIGTERM
; end it, running "down" first where the link is up (-q: not); SIGQUIT ends
; it at once.  -M waits for the interface to appear, through netlink, and
; follows it as it comes and goes.
;
; The pid is kept in /var/run/ifplugd.IFACE.pid, and -k sends that run a
; SIGINT.  Without -n the run goes to the background at once; it says what
; it does to syslog as ifplugd(IFACE), and to stderr while it has one (-s:
; stderr only).  The run always ends with status 1, saying "exiting".  The
; ioctls and netlink are Linux's; elsewhere the interface cannot be read.

(module cu/ifplugd)

(import cu/cli cu-opts)
(import cu/inet inet-set! inet-zeros)
(import cu/inetd in-call in-dontwait)
(import cu/prims byte-at byte-len char->integer cu-err-label cu-int->ptr
  cu-int->str cu-libc-sym cu-ptr-call cu-ptr-ref cu-ptr-set! cu-str->ptr
  file-close file-read-all file-write libc-strerror string-append string=?
  substring sys-exec sys-exit sys-fork sys-getenv sys-kill sys-pipe sys-setenv
  sys-wait-status)
(import cu/telnetd td-ptr->int)
(import cu/udhcp ud-child? ud-daemonize! ud-die ud-end ud-error ud-info
  ud-logging! ud-process-reset! ud-remove-pidfile ud-status ud-strtou
  ud-write-pidfile)
(import cu/vi vi-bundle-version)

; --- the run's settings and state -------------------------------------------------------

(def %pd-iface "eth0")
(def %pd-script "/etc/ifplugd/ifplugd.action")
(def %pd-extra ())
(def %pd-mode "a")
(def %pd-poll 1000)              ; milliseconds
(def %pd-delay-up 0)
(def %pd-delay-down 5)
(def %pd-no-auto #f)             ; -a
(def %pd-fail ())                ; -f: down, -F: up, else nil
(def %pd-ignore-retval #f)       ; -I
(def %pd-monitor #f)             ; -M
(def %pd-no-up-new #f)           ; -A
(def %pd-pidfile "")
(def %pd-stdio #t)
(def %pd-syslog #f)

(def %pd-err -1)
(def %pd-down 0)
(def %pd-up 1)

(def %pd-last -1)
(def %pd-prev 0)
(def %pd-exists #t)
(def %pd-method 5)               ; an index into %pd-methods; 5 is auto
(def %pd-fd -1)                  ; the ioctl socket
(def %pd-nl -1)                  ; the netlink socket, with -M
(def %pd-quiet #f)               ; auto mode trying methods says nothing

(def %pd-status-text
  (fn (_ s) (match ((= s %pd-down) "down") ((= s %pd-up) "up") (#t "error"))))

(def %pd-set-last!
  (fn (_ s) (unless (= s %pd-last) (do (set! %pd-prev %pd-last) (set! %pd-last s)))))

; --- the ioctls -------------------------------------------------------------------------

; an ifreq naming the interface, the rest zeros
(def %pd-req
  (fn (_)
    (let ((r (inet-zeros 40)))
      (do (map (fn (_ k) (inet-set! r k (char->integer (byte-at %pd-iface k)) 1))
               (List range 0 (if (> (byte-len %pd-iface) 15) 15 (byte-len %pd-iface))))
          r))))

(def %pd-ref (fn (_ r at n) (cu-ptr-ref (cu-str->ptr r) at n)))

; network_ioctl: what the call answers, "WHAT failed: REASON" said where WHAT
; is given and it fails
(def %pd-ioctl
  (fn (_ req r what)
    (let ((n (in-call (cu-ptr-call (cu-libc-sym "ioctl") %pd-fd req (cu-str->ptr r)))))
      (do (when (if (< n 0) (if (null? what) #f (not %pd-quiet)) #f)
            (ud-error (%str-concat (list what " failed: " (libc-strerror (Err errno-of n))))))
          n))))

; the MII status register's link bit, read through GET and READ
(def %pd-mii
  (fn (_ get get-name read read-name)
    (def r (%pd-req))
    (match ((< (%pd-ioctl get r get-name) 0) %pd-err)
           (#t (do (inet-set! r 18 1 2)
                   (if (< (%pd-ioctl read r read-name) 0) %pd-err
                     (if (= (& (%pd-ref r 22 2) 4) 0) %pd-down %pd-up)))))))

(def %pd-link-mii (fn (_) (%pd-mii 35143 "SIOCGMIIPHY" 35144 "SIOCGMIIREG")))
(def %pd-link-priv (fn (_) (%pd-mii 35312 "SIOCDEVPRIVATE" 35313 "SIOCDEVPRIVATE+1")))

; ETHTOOL_GLINK, the request pointing at its ethtool_value
(def %pd-link-ethtool
  (fn (_)
    (def r (%pd-req))
    (def edata (inet-zeros 8))
    (inet-set! edata 0 10 4)
    (cu-ptr-set! (cu-str->ptr r) 16 (td-ptr->int (cu-str->ptr edata)) 8)
    (match ((< (%pd-ioctl 35142 r "ETHTOOL_GLINK") 0) %pd-err)
           ((= (%pd-ref edata 4 4) 0) %pd-down)
           (#t %pd-up))))

; IFF_RUNNING; an interface not up keeps the status it had
(def %pd-link-iff
  (fn (_)
    (def r (%pd-req))
    (if (< (%pd-ioctl 35091 r "SIOCGIFFLAGS") 0) %pd-err
      (let ((flags (%pd-ref r 16 2)))
        (match ((if (= (& flags 1) 0) (not (= %pd-last %pd-err)) #f) %pd-last)
               ((= (& flags 64) 0) %pd-down)
               (#t %pd-up))))))

; SIOCGIWAP: an access point of all one byte, 0xff, 0x44 or 0, is none
(def %pd-link-wlan
  (fn (_)
    (def r (%pd-req))
    (if (< (%pd-ioctl 35605 r "SIOCGIWAP") 0) %pd-err
      (let ((mac (map (fn (_ k) (%pd-ref r (+ 18 k) 1)) (List range 0 6))))
        (match ((null? (List find (fn (_ b) (= b (first mac))) (list 255 68 0))) %pd-up)
               ((null? (List find (fn (_ b) (not (= b (first mac)))) (rest mac))) %pd-down)
               (#t %pd-up))))))

; method_table, in api_modes' order: e m p w i, then a for auto
(def %pd-modes "empwia")
(def %pd-methods
  (list (pair "SIOCETHTOOL" %pd-link-ethtool)
        (pair "SIOCGMIIPHY" %pd-link-mii)
        (pair "SIOCDEVPRIVATE" %pd-link-priv)
        (pair "wireless extension" %pd-link-wlan)
        (pair "IFF_RUNNING" %pd-link-iff)))

; up_iface: IFF_UP set where it is not; an interface gone is no longer there
(def %pd-up-iface
  (fn (_)
    (when %pd-exists
      (let ((r (%pd-req)))
        (if (< (%pd-ioctl 35091 r "getting interface flags") 0) (set! %pd-exists #f)
          (let ((flags (%pd-ref r 16 2)))
            (unless (= (& flags 1) 1)
              (do (inet-set! r 16 (| flags 1) 2)
                  (ud-info "upping interface")
                  (let ((n (%pd-ioctl 35092 r "setting interface flags")))
                    (when (< n 0)
                      (let ((e (Err errno-of n)))
                        (if (if (= e 19) #t (= e 99)) (set! %pd-exists #f) (%pd-die-quietly)))))))))))))

; xfunc_die: the run ends at 1, nothing more said
(def %pd-die-quietly (fn (_) (ud-end 1)))

; -m's first letter a: the methods tried again for an interface new
(def %pd-auto-mode? (fn (_) (= (byte-at %pd-mode 0) #\a)))

(def %pd-up-new
  (fn (_)
    (do (unless %pd-no-up-new (%pd-up-iface))
        (when (%pd-auto-mode?) (set! %pd-method 5)))))

; detect_link: the status read, the last and previous kept
(def %pd-detect
  (fn (_)
    (if (not %pd-exists) (if %pd-monitor %pd-down %pd-err)
      (do (unless %pd-no-auto (%pd-up-iface))
          (let ((final (%pd-fallback (if (= %pd-method 5) (%pd-auto) ((rest (List ref %pd-method %pd-methods)))))))
            (do (%pd-set-last! final) final))))))

; the methods tried in turn, quietly; the first to answer is kept
(def %pd-auto
  (fn (_)
    (let go ((ms %pd-methods) (i 0))
      (if (null? ms) %pd-err
        (let ((s (do (set! %pd-quiet #t) (let ((s ((rest (first ms))))) (do (set! %pd-quiet #f) s)))))
          (if (= s %pd-err) (go (rest ms) (+ i 1))
            (do (set! %pd-method i)
                (ud-info (%str-concat (list "using " (first (first ms)) " detection mode")))
                s)))))))

; an error read as -f or -F say
(def %pd-fallback
  (fn (_ status)
    (match ((not (= status %pd-err)) status)
           ((not (null? %pd-fail)) %pd-fail)
           (#t (do (when (%pd-auto-mode?) (ud-error "can't detect link status")) status)))))

; --- netlink ----------------------------------------------------------------------------

(def %pd-align (fn (_ n) (& (+ n 3) (^ 3 4294967295))))

; strncmp (IFACE, the name at P, LEN) = 0, IFACE no longer than LEN
(def %pd-name-is?
  (fn (_ p len)
    (if (> (byte-len %pd-iface) len) #f
      (let go ((i 0))
        (if (>= i len) #t
          (let ((a (if (< i (byte-len %pd-iface)) (char->integer (byte-at %pd-iface i)) 0))
                (b (cu-ptr-ref p i 1)))
            (match ((not (= a b)) #f) ((= a 0) #t) (#t (go (+ i 1))))))))))

; the IFLA_IFNAME attributes of a link message at P of LEN bytes
(def %pd-link-message!
  (fn (_ p len exists)
    (let go ((a 32) (left (- len 32)) (exists exists))
      (if (if (< left 4) #t (let ((rl (cu-ptr-ref p a 2))) (if (< rl 4) #t (> rl left)))) exists
        (let ((rl (cu-ptr-ref p a 2)))
          (go (+ a (%pd-align rl)) (- left (%pd-align rl))
              (if (if (= (cu-ptr-ref p (+ a 2) 2) 3)
                    (%pd-name-is? (cu-int->ptr (+ (td-ptr->int p) a 4)) (let ((l (- rl 4))) (if (> l 16) 16 l)))
                    #f)
                (= (cu-ptr-ref p 4 2) 16)
                exists)))))))

; check_existence_through_netlink: the messages waiting read; whether the
; interface is there, or -1 where netlink failed
(def %pd-netlink
  (fn (_)
    (def buf (inet-zeros 8192))
    (def base (cu-str->ptr buf))
    (let more ((exists %pd-exists))
      (let ((n (in-call (cu-ptr-call (cu-libc-sym "recv") %pd-nl base 8192 in-dontwait))))
        (match
          ((if (< n 0) (= (Err errno-of n) 4) #f) (more exists))
          ((if (< n 0) (if (= (Err errno-of n) 11) #t (= (Err errno-of n) 35)) #f) exists)
          ((< n 0) (do (ud-error (string-append "netlink: recv: " (libc-strerror (Err errno-of n)))) -1))
          (#t
            (let go ((o 0) (left n) (exists exists))
              (if (<= left 0) (more exists)
                (let ((len (if (< left 16) 0 (cu-ptr-ref base o 4))))
                  (if (if (< len 16) #t (> len left))
                    (do (ud-error "netlink packet too small or truncated") -1)
                    (let ((type (cu-ptr-ref base (+ o 4) 2)) (p (cu-int->ptr (+ (td-ptr->int base) o))))
                      (match
                        ((not (if (= type 16) #t (= type 17)))
                          (go (+ o (%pd-align len)) (- left (%pd-align len)) exists))
                        ((< len 32) (do (ud-error "netlink packet too small or truncated") -1))
                        (#t (go (+ o (%pd-align len)) (- left (%pd-align len))
                                (%pd-link-message! p len exists))))))))))))))))

; create_and_bind_to_netlink (NETLINK_ROUTE, RTMGRP_LINK)
(def %pd-netlink-open
  (fn (_)
    (def fd (in-call (cu-ptr-call (cu-libc-sym "socket") 16 2 0)))
    (when (< fd 0) (ud-die (string-append "socket: " (libc-strerror (Err errno-of fd)))))
    (def sa (inet-zeros 12))
    (inet-set! sa 0 16 2)
    (inet-set! sa 8 1 4)
    (let ((r (in-call (cu-ptr-call (cu-libc-sym "bind") fd (cu-str->ptr sa) 12))))
      (when (< r 0) (ud-die (string-append "bind: " (libc-strerror (Err errno-of r))))))
    fd))

; --- the script -------------------------------------------------------------------------

; spawn_and_wait: the exit status, 0x180 and the signal where one ended it,
; -1 where it could not be run; a close-on-exec pipe says the exec failed
(def %pd-spawn
  (fn (_ argv env)
    (def p (sys-pipe))
    (cu-ptr-call (cu-libc-sym "fcntl") (rest p) 2 1)
    (def pid (sys-fork))
    (when (= pid 0)
      (do (guard (_ ())
            (do (file-close (first p))
                (map (fn (_ e) (sys-setenv (first e) (rest e))) env)
                (cu-stdin-to-command!)
                (sys-exec (first argv) (rest argv))))
          (file-write (rest p) "x")
          (sys-exit 111)))
    (file-close (rest p))
    (def b (inet-zeros 4))
    (def got (let go () (let ((n (in-call (cu-ptr-call (cu-libc-sym "read") (first p) (cu-str->ptr b) 1))))
                          (if (if (< n 0) (= (Err errno-of n) 4) #f) (go) n))))
    (file-close (first p))
    (def failed (= got 1))
    (let ((w (sys-wait-status pid)))
      (match (failed -1)
             ((> (rest w) 0) (+ 384 (rest w)))
             (#t (first w))))))

(def %pd-run-script
  (fn (_ action)
    (ud-info (%str-concat (list "executing '" %pd-script " " %pd-iface " " action "'")))
    (def r (%pd-spawn (if (null? %pd-extra) (list %pd-script %pd-iface action)
                        (list %pd-script %pd-iface action %pd-extra))
                      (list (pair "IFPLUGD_PREVIOUS" (%pd-status-text %pd-prev))
                            (pair "IFPLUGD_CURRENT" (%pd-status-text %pd-last)))))
    (ud-info (string-append "exit code: " (cu-int->str (& r 255))))
    (if %pd-ignore-retval 0 r)))

; --- the clock and the pidfile ----------------------------------------------------------

; monotonic_sec, CLOCK_MONOTONIC
(def %pd-now
  (fn (_)
    (def ts (inet-zeros 16))
    (cu-ptr-call (cu-libc-sym "clock_gettime") (if os-darwin? 6 1) (cu-str->ptr ts))
    (%pd-ref ts 0 8)))

; read_pid: the number at the head of the file, as bb_strtoul reads it,
; truncated to a pid_t; 0 where there is no file
(def %pd-read-pid
  (fn (_ path)
    (def text (let ((t (guard (_ ()) (file-read-all path)))) (if (null? t) "" t)))
    (def head (if (> (byte-len text) 127) (substring text 0 127) text))
    (def digits (let go ((i 0)) (if (if (< i (byte-len head)) (%pd-digit? (byte-at head i)) #f) (go (+ i 1)) i)))
    (def r (ud-strtou (substring head 0 digits) 10))
    (match ((= (byte-len head) 0) 0)
           ((not (rest r)) -1)
           ((if (< digits (byte-len head)) (%pd-alnum? (byte-at head digits)) #f) -1)
           (#t (let ((v (& (first r) 4294967295))) (if (>= v 2147483648) (- v 4294967296) v))))))

(def %pd-digit? (fn (_ c) (if (>= c #\0) (<= c #\9) #f)))
(def %pd-alnum?
  (fn (_ c) (if (%pd-digit? c) #t (if (>= (| c 32) #\a) (<= (| c 32) #\z) #f))))

; --- the options ------------------------------------------------------------------------

; xatoi_positive
(def %pd-number
  (fn (_ s)
    (let ((r (ud-strtou s 10)))
      (match ((not (rest r)) (ud-die (%str-concat (list "invalid number '" s "'"))))
             ((> (first r) 2147483647) (ud-die (%str-concat (list "number " s " is not in 0..2147483647 range"))))
             (#t (first r))))))

(def %pd-setup!
  (fn (_ o)
    (set! %pd-iface (Opts value o "-i" "eth0"))
    (set! %pd-script (Opts value o "-r" "/etc/ifplugd/ifplugd.action"))
    (set! %pd-poll (* 1000 (%pd-number (Opts value o "-t" "1"))))
    (set! %pd-delay-up (%pd-number (Opts value o "-u" "0")))
    (set! %pd-delay-down (%pd-number (Opts value o "-d" "5")))
    (set! %pd-mode (Opts value o "-m" "a"))
    (set! %pd-extra (Opts value o "-x"))
    (set! %pd-no-auto (Opts on? o "-a"))
    (set! %pd-fail (match ((Opts on? o "-f") %pd-down) ((Opts on? o "-F") %pd-up) (#t ())))
    (set! %pd-ignore-retval (Opts on? o "-I"))
    (set! %pd-monitor (Opts on? o "-M"))
    (set! %pd-no-up-new (Opts on? o "-A"))
    (set! %pd-last -1)
    (set! %pd-prev 0)
    (set! %pd-exists #t)
    (set! %pd-fd -1)
    (set! %pd-nl -1)
    (set! %pd-quiet #f)))

; --- the run ----------------------------------------------------------------------------

(def %pd-signals (list 2 15 3 1))

; the signal taken between polls: (lit cleanup), (lit exit) or nil
(def %pd-signalled
  (fn (_)
    (def got (List find (fn (_ n) (Sys take-signal n)) %pd-signals))
    (match ((null? got) ())
           ((if (= got 2) #t (= got 15)) (lit cleanup))
           ((= got 3) (lit exit))
           (#t ()))))

; poll on the netlink socket with -M, else on nothing: whether it is readable,
; or (lit eintr)
(def %pd-poll-wait
  (fn (_)
    (def pfd (inet-zeros 8))
    (inet-set! pfd 0 %pd-nl 4)
    (inet-set! pfd 4 1 2)
    (let ((n (in-call (cu-ptr-call (cu-libc-sym "poll") (cu-str->ptr pfd) (if %pd-monitor 1 0) %pd-poll))))
      (match ((if (< n 0) (= (Err errno-of n) 4) #f) (lit eintr))
             ((< n 0) (do (ud-error (string-append "poll: " (libc-strerror (Err errno-of n)))) (lit fail)))
             (#t (if %pd-monitor (not (= (& (%pd-ref pfd 6 2) 1) 0)) #f))))))

; the interface's comings and goings read from netlink; #f where netlink failed
(def %pd-follow!
  (fn (_)
    (let ((old %pd-exists) (now (%pd-netlink)))
      (if (eq? now -1) #f
        (do (set! %pd-exists now)
            (unless (eq? old now)
              (do (ud-info (if now "interface appeared" "interface disappeared"))
                  (when now (%pd-up-new))))
            #t)))))

; when the script runs for a change to NEW: 0 where a change pending is undone
(def %pd-delay-for
  (fn (_ new delay)
    (match ((> delay 0) 0)
           ((= new %pd-up) (+ (%pd-now) %pd-delay-up))
           ((= new %pd-down) (+ (%pd-now) %pd-delay-down))
           (#t (%pd-now)))))

; one pass after the poll: (NEXT STATUS . DELAY), NEXT (lit go) or (lit exit)
(def %pd-pass
  (fn (_ status delay)
    (let ((s (%pd-detect)))
      (if (if (= s %pd-err) (not %pd-monitor) #f) (pair (lit exit) (pair status delay))
        (let ((new (if (= s %pd-err) %pd-down s)))
          (let ((at (if (= new status) delay
                      (do (ud-info (string-append "link is " (%pd-status-text new)))
                          (%pd-delay-for new delay)))))
            (match ((if (> at 0) (< (- (%pd-now) at) 0) #t) (pair (lit go) (pair new at)))
                   ((= (%pd-run-script (%pd-status-text new)) 0) (pair (lit go) (pair new 0)))
                   (#t (pair (lit exit) (pair new 0))))))))))

; the main loop: (END STATUS . DELAY), END (lit cleanup) where SIGINT or
; SIGTERM ends it, else (lit exit)
(def %pd-loop
  (fn (_ status)
    (let go ((status status) (delay 0))
      (let ((sig (%pd-signalled)))
        (if (not (null? sig)) (pair sig (pair status delay))
          (let ((polled (%pd-poll-wait)))
            (match
              ((eq? polled (lit eintr)) (go status delay))
              ((eq? polled (lit fail)) (pair (lit exit) (pair status delay)))
              ((if polled (not (%pd-follow!)) #f) (pair (lit exit) (pair status delay)))
              (#t (let ((r (%pd-pass status delay)))
                    (if (eq? (first r) (lit go)) (go (first (rest r)) (rest (rest r))) r))))))))))

; whether the script runs at the start: a link up without -p, or -l
(def %pd-startup?
  (fn (_ o status)
    (match ((Opts on? o "-l") #t)
           ((Opts on? o "-p") #f)
           (#t (= status %pd-up)))))

; whether "down" runs at the end: a link up, or a down not yet run, without -q
(def %pd-shutdown?
  (fn (_ o status delay)
    (match ((Opts on? o "-q") #f)
           ((= status %pd-up) #t)
           ((= status %pd-down) (> delay 0))
           (#t #f))))

(def %pd-main
  (fn (_ argv)
    (def o (cu-opts "ifplugd" argv))
    (ud-logging! "ifplugd" 0 #t #f)
    (%pd-setup! o)
    (def name (%str-concat (list "ifplugd(" %pd-iface ")")))
    (ud-logging! name 0 #t #f)
    (set! %pd-pidfile (%str-concat (list "/var/run/ifplugd." %pd-iface ".pid")))
    (def pid (%pd-read-pid %pd-pidfile))
    (when (Opts on? o "-k")
      (do (when (> pid 0) (sys-kill pid 2)) (ud-end 0)))
    (when (if (> pid 0) (= (in-call (cu-ptr-call (cu-libc-sym "kill") pid 0)) 0) #f)
      (ud-die "daemon already running"))
    (def at (let go ((i 0))
              (match ((>= i (byte-len %pd-modes)) -1)
                     ((= (byte-len %pd-mode) 0) -1)
                     ((= (byte-at %pd-modes i) (byte-at %pd-mode 0)) i)
                     (#t (go (+ i 1))))))
    (when (< at 0) (ud-die (%str-concat (list "unknown API mode '" %pd-mode "'"))))
    (set! %pd-method at)
    (unless (Opts on? o "-n")
      (do (cu-ptr-call (cu-libc-sym "chdir") "/")
          (ud-daemonize!)))
    (set! %pd-fd (in-call (cu-ptr-call (cu-libc-sym "socket") 2 2 0)))
    (when (< %pd-fd 0) (ud-die (string-append "socket: " (libc-strerror (Err errno-of %pd-fd)))))
    (when %pd-monitor (set! %pd-nl (%pd-netlink-open)))
    (ud-write-pidfile %pd-pidfile)
    (unless (Opts on? o "-s")
      (do (cu-ptr-call (cu-libc-sym "openlog") name 0 24)
          (ud-logging! name 0 #t #t)))
    (map (fn (_ n) (Sys catch-signal n)) %pd-signals)
    (ud-info (string-append "started: x-coreutils v" (vi-bundle-version)))
    (when %pd-monitor
      (set! %pd-exists (>= (%pd-ioctl 35123 (%pd-req) ()) 0)))
    (when %pd-exists (%pd-up-new))
    (def status (%pd-detect))
    (def ended
      (if (= status %pd-err) (lit exit)
        (do (when %pd-monitor
              (ud-info (if %pd-exists "interface exists" "interface doesn't exist, waiting")))
            (when %pd-exists (ud-info (string-append "link is " (%pd-status-text status))))
            (if (%pd-startup? o status)
              (if (= (%pd-run-script (%pd-status-text status)) 0) (%pd-loop status) (lit exit))
              (%pd-loop status)))))
    (when (if (pair? ended) (eq? (first ended) (lit cleanup)) #f)
      (let ((s (first (rest ended))) (delay (rest (rest ended))))
        (when (%pd-shutdown? o s delay)
          (%pd-run-script "down"))))
    (ud-remove-pidfile %pd-pidfile)
    (ud-die "exiting")))

(def cu-ifplugd
  (fn (_ argv stdin-thunk)
    (ud-process-reset!)
    (def status
      (guard (e (match ((eq? (cu-err-label e) (lit udhcp)) (ud-status))
                       (#t (do (when (ud-child?) (sys-exit 1)) (error e)))))
        (%pd-main argv)))
    (when (ud-child?) (sys-exit status))
    status))

(provide cu/ifplugd cu-ifplugd)

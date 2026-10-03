; # x-coreutils -- the small tools, as applets
;
; ## cu/ftp.x -- FTP: busybox's ftpget and ftpput, and wget's ftp:// urls
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Both clients are busybox's: a control connection to the server's port (21
; unless given), a login, binary mode, and a passive data connection to the
; port the server's EPSV reply names -- or its PASV reply, when it does not
; answer EPSV -- at the address the control connection reached.  A reply is
; read a line at a time until a line of three digits and a space: its number
; is the reply's.  ftpgetput.c and wget.c each read and report replies in
; their own words, and each is followed here.

; --- the control connection ------------------------------------------------------

(def %ftp-fd -1)   ; the control connection
(def %ftp-buf "")  ; what has arrived on it past the last line handed out
(def %ftp-reply "") ; the last reply line, as read

(def %ftp-open!
  (fn (_ fd) (do (set! %ftp-fd fd) (set! %ftp-buf "") (set! %ftp-reply ""))))

; the next line from the server without its newline, or nil when the
; connection ends with nothing more; a last line with no newline is a line
(def %ftp-line
  (fn (self)
    (def nl (%wget-index %ftp-buf #\newline 0))
    (if (null? nl)
      (let ((r (net-recv-run %ftp-fd 4096)))
        (if (null? r)
          (if (= (byte-len %ftp-buf) 0) ()
            (let ((l %ftp-buf)) (do (set! %ftp-buf "") l)))
          (do (set! %ftp-buf (string-append %ftp-buf (substring (first r) 0 (rest r))))
              (self))))
      (let ((l (substring %ftp-buf 0 nl)))
        (do (set! %ftp-buf (substring %ftp-buf (+ nl 1) (byte-len %ftp-buf)))
            l)))))

; a reply's last line: three digits and a space
(def %ftp-final?
  (fn (_ l)
    (if (>= (byte-len l) 4)
      (if (if (>= (byte-at l 0) #\0) (<= (byte-at l 0) #\9) #f) (= (byte-at l 3) #\space) #f)
      #f)))

(def %ftp-code (fn (_ l) (%wget-digits (substring l 0 3))))

(def %ftp-send
  (fn (_ line) (net-send %ftp-fd (string-append line "\r\n"))))

; busybox's parse_pasv_epsv: the data port a 227 reply's last two numbers make,
; or the one between an EPSV reply's last two |s; nil when there is none
(def %ftp-data-port
  (fn (_ l)
    (if (= (byte-at l 2) #\7)
      (let ((close (%wget-last-index l #\))))
        (let ((s (if (null? close)
                   (let ((cr (%wget-last-index l #\return))) (if (null? cr) l (substring l 0 cr)))
                   (substring l 0 close))))
          (let ((c2 (%wget-last-index s #\,)))
            (if (null? c2) ()
              (let ((c1 (%wget-last-index (substring s 0 c2) #\,)))
                (if (null? c1) ()
                  (let ((hi (%wget-digits (substring s (+ c1 1) c2)))
                        (lo (%wget-digits (substring s (+ c2 1) (byte-len s)))))
                    (if (if (null? hi) #t (null? lo)) ()
                      (if (if (> hi 255) #t (> lo 255)) () (+ (* hi 256) lo))))))))))
      (let ((b2 (%wget-last-index l #\|)))
        (if (null? b2) ()
          (let ((b1 (%wget-last-index (substring l 0 b2) #\|)))
            (if (null? b1) ()
              (let ((p (%wget-digits (substring l (+ b1 1) b2))))
                (if (null? p) () (if (> p 65535) () p))))))))))

; a TCP connection to IP's PORT, or the run ends as busybox's
; xconnect_stream ends it
(def %ftp-connect
  (fn (_ ip port)
    (guard (e (if (eq? (%wget-err-op e) (lit connect))
                (%net-die (string-concat
                  (list "can't connect to remote host (" ip "): " (%wget-err-text e))))
                (error e)))
      (net-connect ip port))))

; a run's bytes to FD, all of them
(def %ftp-pump-out
  (fn (_ fd r) (file-write-run fd r)))

; --- ftpget and ftpput -------------------------------------------------------------

(def %ftp-verbose 0)
(def %ftp-ip "")

; one exchange as ftpgetput.c's ftpcmd has it: with -v, "cmd S1 S2" first,
; (null) for one not given; S1 and S2 sent joined by a space, S1 alone when
; there is no S2; then lines read to the reply's last, whose number answers.
; The connection ending first is "unexpected server response: EOF"
(def %ftpgp-cmd
  (fn (_ s1 s2)
    (when (> %ftp-verbose 0)
      (file-write 2 (string-concat (list %ftp-applet ": cmd " (if (null? s1) "(null)" s1) " "
                                         (if (null? s2) "(null)" s2) "\n"))))
    (unless (null? s1)
      (%ftp-send (if (null? s2) s1 (string-concat (list s1 " " s2)))))
    (let go ()
      (let ((l (%ftp-line)))
        (if (null? l)
          (do (set! %ftp-reply "EOF") (%ftpgp-die ()))
          (do (set! %ftp-reply l)
              (if (%ftp-final? l) (%ftp-code l) (go))))))))

(def %ftp-applet "ftpget")

; ftp_die: the reply printed up to its first byte that is not plain text
(def %ftpgp-die
  (fn (_ msg)
    (def l %ftp-reply)
    (def end
      (let go ((i 0))
        (if (if (< i (byte-len l)) (if (>= (byte-at l i) 32) (< (byte-at l i) 127) #f) #f)
          (go (+ i 1)) i)))
    (%net-die (string-concat
      (list "unexpected server response" (if (null? msg) "" (string-append " to " msg))
            ": " (substring l 0 end))))))

(def %ftpgp-login
  (fn (_ user pass)
    (unless (= (%ftpgp-cmd () ()) 220) (%ftpgp-die ()))
    (match
      ((= (%ftpgp-cmd "USER" user) 230) ())
      ((= (%ftp-code %ftp-reply) 331)
        (unless (= (%ftpgp-cmd "PASS" pass) 230) (%ftpgp-die "PASS")))
      (#t (%ftpgp-die "USER")))
    (%ftpgp-cmd "TYPE I" ())))

; xconnect_ftpdata: EPSV, or PASV when EPSV is not answered 229
(def %ftpgp-data
  (fn (_)
    (unless (= (%ftpgp-cmd "EPSV" ()) 229)
      (unless (= (%ftpgp-cmd "PASV" ()) 227) (%ftpgp-die "PASV")))
    (def port (%ftp-data-port %ftp-reply))
    (when (null? port) (%ftpgp-die "PASV"))
    (%ftp-connect %ftp-ip port)))

; pump_data_and_QUIT, after the copy: the server's 226, then QUIT
(def %ftpgp-finish
  (fn (_)
    (unless (= (%ftpgp-cmd () ()) 226) (%ftpgp-die ()))
    (%ftpgp-cmd "QUIT" ())
    0))

(def %ftpgp-receive
  (fn (_ local remote continue?)
    (def data (%ftpgp-data))
    (def sized? (= (%ftpgp-cmd "SIZE" remote) 213))
    (def to-stdout? (string=? local "-"))
    (def beg
      (if (if continue? (if sized? (not to-stdout?) #f) #f)
        (do (unless (file-exists? local) (%net-die "stat: No such file or directory"))
            (Assoc get (lit size) (file-stat local)))
        0))
    (def resumed? (if (> beg 0) (= (%ftpgp-cmd (string-append "REST " (%cu-int->str beg)) ()) 350) #f))
    (when (> (%ftpgp-cmd "RETR" remote) 150) (%ftpgp-die "RETR"))
    (def out
      (if to-stdout? 1
        (let ((fd (file-open-or-err (if resumed? file-open-append file-open-write) local)))
          (if (Err err? fd)
            (%net-die (string-concat (list "can't open '" local "': " (file-err-text fd))))
            fd))))
    (let go ()
      (let ((r (net-recv-run data 65536)))
        (unless (null? r)
          (do (%ftp-pump-out out r) (%cu-sweep! 1) (go)))))
    (net-close data)
    (unless to-stdout? (file-close out))
    (%ftpgp-finish)))

(def %ftpgp-send
  (fn (_ remote local stdin-thunk)
    (def data (%ftpgp-data))
    (def in
      (if (string=? local "-") ()
        (let ((fd (file-open-or-err file-open-read local)))
          (if (Err err? fd)
            (%net-die (string-concat (list "can't open '" local "': " (file-err-text fd))))
            fd))))
    (unless (%wget-memv (%ftpgp-cmd "STOR" remote) (list 125 150)) (%ftpgp-die "STOR"))
    (if (null? in)
      (let go ()
        (let ((p (stdin-thunk (lit chunk))))
          (let ((r (if (pair? p) p (pair p (byte-len p)))))
            (when (> (rest r) 0)
              (do (%ftp-pump-out data r) (%cu-sweep! 1) (go))))))
      (let go ()
        (let ((r (file-read-run in 65536)))
          (when (> (rest r) 0)
            (do (%ftp-pump-out data r) (%cu-sweep! 1) (go))))))
    (unless (null? in) (file-close in))
    (net-close data)
    (%ftpgp-finish)))

; busybox's bb_lookup_port: a number, or the run ends with "bad port"
(def %ftp-port
  (fn (_ v dflt)
    (if (null? v) dflt
      (let ((n (%wget-digits v)))
        (if (if (null? n) #t (> n 65535))
          (%net-die (string-concat (list "bad port '" v "'")))
          n)))))

; ftpget HOST [LOCAL] REMOTE and ftpput HOST [REMOTE] LOCAL
(def %cu-ftpgetput
  (fn (_ applet argv stdin-thunk)
    (def o (%cu-opts applet argv))
    (def ops (Opts operands o))
    (if (if (< (length ops) 2) #t (> (length ops) 3)) (%cu-usage applet)
      (do (set! %ftp-applet applet)
          (set! %ftp-verbose (if (if (Opts on? o "-v") #t (Opts on? o "--verbose")) 1 0))
          (guard (e (if (eq? (Err label e) (lit net))
                      (do (file-write 2 (string-concat (list applet ": " (e msg) "\n"))) 1)
                      (error e)))
            (%ftpgp-run applet o ops stdin-thunk))))))

(def %ftp-opt
  (fn (_ o short long dflt)
    (let ((v (Opts value o short)))
      (if (null? v) (let ((w (Opts value o long))) (if (null? w) dflt w)) v))))

(def %ftpgp-run
  (fn (_ applet o ops stdin-thunk)
    (def host (first ops))
    (def a1 (first (rest ops)))
    (def a2 (if (null? (rest (rest ops))) a1 (first (rest (rest ops)))))
    (def port (%ftp-port (%ftp-opt o "-P" "--port" ()) 21))
    (def ip (guard (_ ()) (net-resolve host)))
    (when (null? ip) (%net-die (string-concat (list "bad address '" host "'"))))
    (set! %ftp-ip ip)
    (when (> %ftp-verbose 0)
      (file-write 1 (string-concat (list "Connecting to " host " (" ip ":" (%cu-int->str port) ")\n"))))
    (%ftp-open! (%ftp-connect ip port))
    (def st
      (do (%ftpgp-login (%ftp-opt o "-u" "--username" "anonymous")
                        (%ftp-opt o "-p" "--password" "busybox"))
          (if (string=? applet "ftpget")
            (%ftpgp-receive a1 a2 (if (Opts on? o "-c") #t (not (null? (Opts value o "--continue")))))
            (%ftpgp-send a1 a2 stdin-thunk))))
    (net-close %ftp-fd)
    st))

(def %cu-ftpget (fn (_ argv stdin-thunk) (%cu-ftpgetput "ftpget" argv stdin-thunk)))
(def %cu-ftpput (fn (_ argv stdin-thunk) (%cu-ftpgetput "ftpput" argv stdin-thunk)))

; --- wget's ftp:// ------------------------------------------------------------------

; one exchange as wget.c's ftpcmd has it: S1 and S2 sent joined, shown with -S
; as "--> S1S2" and a blank line; each line read shown with -S, cut at its first
; control byte; the connection ending is "error getting response"
(def %wget-ftpcmd
  (fn (_ s1 s2)
    (unless (null? s1)
      (let ((line (string-append s1 (if (null? s2) "" s2))))
        (do (%ftp-send line)
            (when (%wget-show?) (%wget-say (string-concat (list "--> " line "\n\n")))))))
    (let go ()
      (let ((l (%ftp-line)))
        (when (null? l) (%wget-die "error getting response"))
        (let ((s (%wget-sanitize l)))
          (do (set! %ftp-reply s)
              (when (%wget-show?) (%wget-say (string-append s "\n")))
              (if (%ftp-final? s) (%ftp-code s) (go))))))))

; prepare_ftp_session: logged in, the size asked, the data connection open and
; RETR asked.  Answers (DATA . CLEN), CLEN nil when SIZE is not answered 213
(def %wget-ftp-session
  (fn (_ t ip)
    (def np (%wget-name-port t))
    (%ftp-open! (%ftp-connect ip (rest np)))
    (unless (= (%wget-ftpcmd () ()) 220) (%wget-die %ftp-reply))
    (def u (%wget-user t))
    (def colon (if (null? u) () (%wget-index u #\: 0)))
    (def user (match ((null? u) "anonymous") ((null? colon) u) (#t (substring u 0 colon))))
    (def pass (match ((null? u) "busybox") ((null? colon) "") (#t (substring u (+ colon 1) (byte-len u)))))
    (match
      ((= (%wget-ftpcmd "USER " user) 230) ())
      ((if (= (%ftp-code %ftp-reply) 331) (= (%wget-ftpcmd "PASS " pass) 230) #f) ())
      (#t (%wget-die (string-append "ftp login: " %ftp-reply))))
    (%wget-ftpcmd "TYPE I" ())
    (def clen
      (if (= (%wget-ftpcmd "SIZE " (%wget-path t)) 213)
        (let ((n (%wget-digits (substring %ftp-reply 4 (byte-len %ftp-reply)))))
          (if (null? n)
            (%wget-die (string-concat (list "bad SIZE value '" (substring %ftp-reply 4 (byte-len %ftp-reply)) "'")))
            n))
        ()))
    (unless (= (%wget-ftpcmd "EPSV" ()) 229)
      (unless (= (%wget-ftpcmd "PASV" ()) 227)
        (%wget-die (string-append "bad response to PASV: " %ftp-reply))))
    (def port (%ftp-data-port %ftp-reply))
    (when (null? port) (%wget-die (string-append "bad response to PASV: " %ftp-reply)))
    (def data (%ftp-connect ip port))
    (def len
      (if (> %wget-beg 0)
        (if (= (%wget-ftpcmd (string-append "REST " (%cu-int->str %wget-beg)) ()) 350)
          (if (null? clen) () (- clen %wget-beg))
          (do (%wget-restart-failed!) clen))
        clen))
    (when (> (%wget-ftpcmd "RETR " (%wget-path t)) 150)
      (%wget-die (string-append "bad response to RETR: " %ftp-reply)))
    (pair data len)))

; one try at an ftp:// url: the session, the file (or --spider's answer), then
; the server's 226.  Answers done, or the bytes a partial download got
(def %wget-ftp-hop
  (fn (_ t ip fname)
    (def dl (%wget-ftp-session t ip))
    (def data (first dl))
    (def outcome
      (if (%wget-on? "--spider" "--spider")
        (do (unless (%wget-quiet?) (%wget-say "remote file exists\n"))
            (lit done))
        (do (if (string=? fname "-") (set! %wget-out-fd 1) (%wget-out! fname))
            (let ((r (%wget-retrieve (fn (_ n) (net-recv-run data n)) fname (rest dl) #f)))
              (if (rest r) (lit done) (first r))))))
    (net-close data)
    (unless (= (%wget-ftpcmd () ()) 226) (%wget-die (string-append "ftp error: " %ftp-reply)))
    (net-close %ftp-fd)
    outcome))

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

(module cu/ftp)

(import cu/cli cu-opts cu-usage)
(import cu/net ftp-code ftp-connect ftp-data-port ftp-fd ftp-final? ftp-line
  ftp-open! ftp-reply ftp-send)
(import cu/prims byte-at byte-len cu-int->str cu-sweep! file-close
  file-err-text file-exists? file-open-append file-open-or-err file-open-read
  file-open-write file-read-run file-stat file-write file-write-run length
  net-close net-die net-recv-run net-resolve string-append string=? substring
  wget-digits wget-memv)

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
      (file-write 2 (%str-concat (list %ftp-applet ": cmd " (if (null? s1) "(null)" s1) " "
                                         (if (null? s2) "(null)" s2) "\n"))))
    (unless (null? s1)
      (ftp-send (if (null? s2) s1 (%str-concat (list s1 " " s2)))))
    (let go ()
      (let ((l (ftp-line)))
        (if (null? l)
          (do (set! ftp-reply "EOF") (%ftpgp-die ()))
          (do (set! ftp-reply l)
              (if (ftp-final? l) (ftp-code l) (go))))))))

(def %ftp-applet "ftpget")

; ftp_die: the reply printed up to its first byte that is not plain text
(def %ftpgp-die
  (fn (_ msg)
    (def l ftp-reply)
    (def end
      (let go ((i 0))
        (if (if (< i (byte-len l)) (if (>= (byte-at l i) 32) (< (byte-at l i) 127) #f) #f)
          (go (+ i 1)) i)))
    (net-die (%str-concat
      (list "unexpected server response" (if (null? msg) "" (string-append " to " msg))
            ": " (substring l 0 end))))))

(def %ftpgp-login
  (fn (_ user pass)
    (unless (= (%ftpgp-cmd () ()) 220) (%ftpgp-die ()))
    (match
      ((= (%ftpgp-cmd "USER" user) 230) ())
      ((= (ftp-code ftp-reply) 331)
        (unless (= (%ftpgp-cmd "PASS" pass) 230) (%ftpgp-die "PASS")))
      (#t (%ftpgp-die "USER")))
    (%ftpgp-cmd "TYPE I" ())))

; xconnect_ftpdata: EPSV, or PASV when EPSV is not answered 229
(def %ftpgp-data
  (fn (_)
    (unless (= (%ftpgp-cmd "EPSV" ()) 229)
      (unless (= (%ftpgp-cmd "PASV" ()) 227) (%ftpgp-die "PASV")))
    (def port (ftp-data-port ftp-reply))
    (when (null? port) (%ftpgp-die "PASV"))
    (ftp-connect %ftp-ip port)))

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
        (do (unless (file-exists? local) (net-die "stat: No such file or directory"))
            (Assoc get (lit size) (file-stat local)))
        0))
    (def resumed? (if (> beg 0) (= (%ftpgp-cmd (string-append "REST " (cu-int->str beg)) ()) 350) #f))
    (when (> (%ftpgp-cmd "RETR" remote) 150) (%ftpgp-die "RETR"))
    (def out
      (if to-stdout? 1
        (let ((fd (file-open-or-err (if resumed? file-open-append file-open-write) local)))
          (if (Err err? fd)
            (net-die (%str-concat (list "can't open '" local "': " (file-err-text fd))))
            fd))))
    (let go ()
      (let ((r (net-recv-run data 65536)))
        (unless (null? r)
          (do (%ftp-pump-out out r) (cu-sweep! 1) (go)))))
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
            (net-die (%str-concat (list "can't open '" local "': " (file-err-text fd))))
            fd))))
    (unless (wget-memv (%ftpgp-cmd "STOR" remote) (list 125 150)) (%ftpgp-die "STOR"))
    (if (null? in)
      (let go ()
        (let ((p (stdin-thunk (lit chunk))))
          (let ((r (if (pair? p) p (pair p (byte-len p)))))
            (when (> (rest r) 0)
              (do (%ftp-pump-out data r) (cu-sweep! 1) (go))))))
      (let go ()
        (let ((r (file-read-run in 65536)))
          (when (> (rest r) 0)
            (do (%ftp-pump-out data r) (cu-sweep! 1) (go))))))
    (unless (null? in) (file-close in))
    (net-close data)
    (%ftpgp-finish)))

; busybox's bb_lookup_port: a number, or the run ends with "bad port"
(def %ftp-port
  (fn (_ v dflt)
    (if (null? v) dflt
      (let ((n (wget-digits v)))
        (if (if (null? n) #t (> n 65535))
          (net-die (%str-concat (list "bad port '" v "'")))
          n)))))

; ftpget HOST [LOCAL] REMOTE and ftpput HOST [REMOTE] LOCAL
(def %cu-ftpgetput
  (fn (_ applet argv stdin-thunk)
    (def o (cu-opts applet argv))
    (def ops (Opts operands o))
    (if (if (< (length ops) 2) #t (> (length ops) 3)) (cu-usage applet)
      (do (set! %ftp-applet applet)
          (set! %ftp-verbose (if (if (Opts on? o "-v") #t (Opts on? o "--verbose")) 1 0))
          (guard (e (if (eq? (Err label e) (lit net))
                      (do (file-write 2 (%str-concat (list applet ": " (e msg) "\n"))) 1)
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
    (when (null? ip) (net-die (%str-concat (list "bad address '" host "'"))))
    (set! %ftp-ip ip)
    (when (> %ftp-verbose 0)
      (file-write 1 (%str-concat (list "Connecting to " host " (" ip ":" (cu-int->str port) ")\n"))))
    (ftp-open! (ftp-connect ip port))
    (def st
      (do (%ftpgp-login (%ftp-opt o "-u" "--username" "anonymous")
                        (%ftp-opt o "-p" "--password" "busybox"))
          (if (string=? applet "ftpget")
            (%ftpgp-receive a1 a2 (if (Opts on? o "-c") #t (not (null? (Opts value o "--continue")))))
            (%ftpgp-send a1 a2 stdin-thunk))))
    (net-close ftp-fd)
    st))

(def cu-ftpget (fn (_ argv stdin-thunk) (%cu-ftpgetput "ftpget" argv stdin-thunk)))
(def cu-ftpput (fn (_ argv stdin-thunk) (%cu-ftpgetput "ftpput" argv stdin-thunk)))

; --- wget's ftp:// ------------------------------------------------------------------

(provide cu/ftp cu-ftpget cu-ftpput)

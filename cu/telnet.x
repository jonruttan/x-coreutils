; # x-coreutils -- the small tools, as applets
;
; ## cu/telnet.x -- telnet: a terminal on a TELNET connection
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; networking/telnet.c: stdin to the connection and the connection to stdout.
; Bytes from the server are read through the TELNET state machine -- IAC IAC
; is a 0xff, CR NUL a CR, a subnegotiation and an unknown command skipped, and
; WILL/WONT/DO/DONT noted.  Nothing is said to a server until it says one of
; the options telnet knows: then DO or DONT ECHO and DO SGA answer it, and
; WILL NAWS, WILL TTYPE ($TERM set) and WILL NEW_ENVIRON (-a or -l) go out
; once; a DO for one of those is answered with its subnegotiation.  Bytes from
; stdin go out with 0xff doubled and each CR or LF as CR LF; ^] (or SIGINT)
; opens the console escape menu.  WILL ECHO puts a terminal stdin into raw
; mode, WONT ECHO back.
;
; busybox prints "Connected to" and the mode banners with stdio, which musl
; line-buffers until its first flush finds stdout is no terminal, then fully
; buffers: the first line goes out at once, the banners at exit.  The rest is
; written straight to the descriptors.

(module cu/telnet)

(import cu/cli cu-opts cu-usage)
(import cu/prims append byte-at byte-len cu-ptr-ref cu-ptr-set! cu-sig-ign
  cu-stdin-to-command! cu-str->ptr cu-sweep-lines cu-sweep-tick! file-read-run
  file-write filter length net-connect net-resolve net-send-run reverse
  str-make-raw string-concat sys-getenv sys-isatty sys-poll sys-signal)

(def %tn-iac 255)
(def %tn-dont 254)
(def %tn-do 253)
(def %tn-wont 252)
(def %tn-will 251)
(def %tn-sb 250)
(def %tn-se 240)
(def %tn-echo 1)
(def %tn-sga 3)
(def %tn-ttype 24)
(def %tn-naws 31)
(def %tn-environ 39)

(def %tn-net -1)
(def %tn-ttype-name ())         ; $TERM, until its subnegotiation goes
(def %tn-login ())              ; -a's $USER or -l's USER, likewise
(def %tn-echo-state 255)        ; 255 unknown, 0 off, 1 on (raw mode)
(def %tn-initial? #f)           ; the WILLs sent
(def %tn-sga-seen? #f)
(def %tn-naws-on? #f)
(def %tn-changes ())            ; what the next write to the server answers
(def %tn-state 0)               ; 0 normal, 1 IAC, 2 option, 3 sub, 4 sub IAC, 5 CR
(def %tn-verb 0)
(def %tn-sub-left 0)
(def %tn-out ())                ; queued for the server, newest byte first
(def %tn-stdin-open? #t)
(def %tn-later ())              ; stdio's output, held for exit
(def %tn-tty-out? #f)
(def %tn-saved ())              ; the terminal's settings, for cooked mode

; --- the terminal --------------------------------------------------------------

(def %tn-raw! (fn (_) (when (sys-isatty 0) (let ((s (Term raw! 0))) (unless (null? s) (set! %tn-saved s))))))
(def %tn-cook! (fn (_) (unless (null? %tn-saved) (Term restore! 0 %tn-saved))))

; printf: at once on a terminal, otherwise held for exit
(def %tn-printf
  (fn (_ s) (if %tn-tty-out? (file-write 1 s) (set! %tn-later (pair s %tn-later)))))

(def %tn-exit
  (fn (_ n)
    (%tn-cook!)
    (file-write 1 (string-concat (reverse %tn-later)))
    (set! %tn-later ())
    n))

; atoi: the leading decimal digits, 0 for none
(def %tn-atoi
  (fn (_ s)
    (let go ((i 0) (n 0))
      (if (if (< i (byte-len s)) (if (>= (byte-at s i) #\0) (<= (byte-at s i) #\9) #f) #f)
        (go (+ i 1) (+ (* n 10) (- (byte-at s i) #\0)))
        n))))

; get_terminal_width_height on stdin: $COLUMNS and $LINES over TIOCGWINSZ, a
; value of 1 or less, or 30000 or more, taken as 80 and 24
(def %tn-window
  (fn (_)
    (def m (Term measure 0))
    (def pick (fn (_ env measured dflt)
      (let ((v (let ((e (sys-getenv env))) (if (null? e) measured (%tn-atoi e)))))
        (if (if (<= v 1) #t (>= v 30000)) dflt v))))
    (pair (pick "COLUMNS" (if (null? m) 0 (first m)) 80)
          (pick "LINES" (if (null? m) 0 (rest m)) 24))))

; --- to the server ---------------------------------------------------------------

(def %tn-put (fn (_ bytes) (set! %tn-out (append (reverse bytes) %tn-out))))

; BYTES as a run, (BUFFER . COUNT): a string's byte-len stops at a zero byte,
; and a subnegotiation has them
(def tn-run
  (fn (_ bytes)
    (def n (length bytes))
    (def buf (str-make-raw (+ n 1)))
    (let go ((i 0) (l bytes))
      (unless (null? l) (do (cu-ptr-set! (cu-str->ptr buf) i (first l) 1) (go (+ i 1) (rest l)))))
    (pair buf n)))

; a subnegotiation's bytes, each 0xff doubled
(def %tn-escaped
  (fn (_ bytes)
    (let go ((l bytes) (acc ()))
      (if (null? l) (reverse acc)
        (go (rest l) (if (= (first l) %tn-iac) (pair (first l) (pair (first l) acc)) (pair (first l) acc)))))))

(def tn-str-bytes
  (fn (_ s) (let go ((i (- (byte-len s) 1)) (acc ())) (if (< i 0) acc (go (- i 1) (pair (byte-at s i) acc))))))

(def %tn-change? (fn (_ c) (List any? (fn (_ x) (eq? x c)) %tn-changes)))
(def %tn-unchange! (fn (_ c) (set! %tn-changes (filter (fn (_ x) (not (eq? x c))) %tn-changes))))
(def %tn-note! (fn (_ c) (unless (%tn-change? c) (set! %tn-changes (pair c %tn-changes)))))

; handle_changes_in_options: the answers, and once the WILLs; then the
; subnegotiations asked for
(def %tn-answer!
  (fn (_)
    (unless (null? %tn-changes)
      (do (when (%tn-change? (lit echo))
            (%tn-put (list %tn-iac (if (= %tn-echo-state 1) %tn-do %tn-dont) %tn-echo)))
          (when (%tn-change? (lit sga))
            (do (%tn-put (list %tn-iac %tn-do %tn-sga)) (set! %tn-sga-seen? #t)))
          (%tn-unchange! (lit echo))
          (%tn-unchange! (lit sga))
          (unless %tn-initial?
            (do (set! %tn-initial? #t)
                (%tn-put (list %tn-iac %tn-will %tn-naws))
                (unless (null? %tn-ttype-name) (%tn-put (list %tn-iac %tn-will %tn-ttype)))
                (unless (null? %tn-login) (%tn-put (list %tn-iac %tn-will %tn-environ)))))))
    (when (%tn-change? (lit naws))
      (let ((w (%tn-window)))
        (do (set! %tn-naws-on? #t)
            (%tn-unchange! (lit naws))
            (%tn-put (append (list %tn-iac %tn-sb %tn-naws)
                             (%tn-escaped (list (/ (- (first w) (% (first w) 256)) 256) (% (first w) 256)
                                                (/ (- (rest w) (% (rest w) 256)) 256) (% (rest w) 256)))
                             (list %tn-iac %tn-se))))))
    (when (%tn-change? (lit ttype))
      (do (%tn-put (append (list %tn-iac %tn-sb %tn-ttype 0) (%tn-escaped (tn-str-bytes %tn-ttype-name))
                           (list %tn-iac %tn-se)))
          (set! %tn-ttype-name ())
          (%tn-unchange! (lit ttype))))
    (when (%tn-change? (lit environ))
      (do (%tn-put (append (list %tn-iac %tn-sb %tn-environ 0 0 #\U #\S #\E #\R 1)
                           (%tn-escaped (tn-str-bytes %tn-login)) (list %tn-iac %tn-se)))
          (set! %tn-login ())
          (%tn-unchange! (lit environ))))))

; what is queued, to the server
(def %tn-flush!
  (fn (_)
    (%tn-answer!)
    (unless (null? %tn-out)
      (let ((ok (guard (_ #f) (do (net-send-run %tn-net (tn-run (reverse %tn-out))) #t))))
        (do (set! %tn-out ())
            (unless ok
              (do (file-write 1 "Error writing to foreign host\r\n")
                  (set! %tn-stdin-open? #f))))))))

; --- from the server ---------------------------------------------------------------

(def %tn-banner
  (fn (_ mode key) (%tn-printf (string-concat (list "\r\nEntering " mode " mode\r\nEscape character is '^" key "'.\r\n")))))

; one option verb's effect
(def %tn-option!
  (fn (_ c)
    (def will? (= %tn-verb %tn-will))
    (match
      ((if will? #t (= %tn-verb %tn-wont))
        (match ((= c %tn-echo) (set! %tn-echo-state (if will? 1 0)))
               ((if (= c %tn-sga) (if will? (not %tn-sga-seen?) #f) #f) (%tn-note! (lit sga)))
               (#t ())))
      ((= %tn-verb %tn-do)
        (match ((= c %tn-ttype) (unless (null? %tn-ttype-name) (%tn-note! (lit ttype))))
               ((= c %tn-environ) (unless (null? %tn-login) (%tn-note! (lit environ))))
               ((= c %tn-naws) (unless %tn-naws-on? (%tn-note! (lit naws))))
               (#t ())))
      (#t ()))))

; read_from_net's state machine over a run of BYTES: the bytes stdout gets
(def %tn-decode
  (fn (_ buf n)
    (let go ((i 0) (acc ()))
      (if (>= i n) (reverse acc)
        (let ((c (cu-ptr-ref (cu-str->ptr buf) i 1)))
          (match
            ((= %tn-state 0)
              (match ((= c %tn-iac) (do (set! %tn-state 1) (go (+ i 1) acc)))
                     ((= c #\return) (do (set! %tn-state 5) (go (+ i 1) (pair c acc))))
                     (#t (go (+ i 1) (pair c acc)))))
            ((= %tn-state 5)
              (do (set! %tn-state 0)
                  (if (= c 0) (go (+ i 1) acc) (go i acc))))
            ((= %tn-state 1)
              (do (match ((= c %tn-iac) (set! %tn-state 0))
                         ((= c %tn-sb) (do (set! %tn-sub-left 255) (set! %tn-state 3)))
                         ((if (>= c %tn-will) (<= c %tn-dont) #f) (do (set! %tn-verb c) (set! %tn-state 2)))
                         (#t (set! %tn-state 0)))
                  (go (+ i 1) (if (= c %tn-iac) (pair c acc) acc))))
            ((= %tn-state 2) (do (%tn-option! c) (set! %tn-state 0) (go (+ i 1) acc)))
            ((= %tn-state 3)
              (do (set! %tn-sub-left (- %tn-sub-left 1))
                  (match ((= %tn-sub-left 0) (set! %tn-state 0))
                         ((= c %tn-iac) (set! %tn-state 4))
                         (#t ()))
                  (go (+ i 1) acc)))
            (#t (do (set! %tn-state (if (= c %tn-se) 0 3)) (go (+ i 1) acc)))))))))

; a read from the server: #f at its end
(def %tn-from-net!
  (fn (_)
    (def r (guard (_ ()) (Socket recv-run %tn-net 1024)))
    (if (null? r)
      (do (file-write 1 "EOF on read from foreign host\r\n")
          (set! %tn-stdin-open? #f)
          #f)
      (let ((was %tn-echo-state))
        (def out (%tn-decode (first r) (rest r)))
        (unless (null? out) (let ((run (tn-run out))) (File write 1 (first run) (rest run))))
        (unless (= was %tn-echo-state)
          (do (%tn-note! (lit echo))
              (if (= %tn-echo-state 1)
                (do (%tn-banner "character" "]") (%tn-raw!))
                (do (%tn-banner "line" "C") (%tn-cook!)))))
        #t))))

; --- from stdin ------------------------------------------------------------------

(def %tn-menu-text
  "\r\nConsole escape. Commands are:\r\nl\tgo to line mode\r\nc\tgo to character mode\r\nz\tsuspend telnet\r\ne\texit\r\n")

; show_menu: one byte from stdin chooses; nil when the run ends
(def %tn-menu!
  (fn (_)
    (%tn-raw!)
    (file-write 1 %tn-menu-text)
    (def r (file-read-run 0 1))
    (def b (if (= (rest r) 0) () (byte-at (first r) 0)))
    (def changed (fn (_ state banner)
      (do (set! %tn-echo-state state)
          (banner)
          (when %tn-initial? (%tn-note! (lit echo)))
          #t)))
    (match
      ((if (null? b) #t (= b #\e)) ())
      ((if (= b #\l) (= %tn-echo-state 1) #f)
        (changed 0 (fn (_) (do (%tn-banner "line" "C") (%tn-cook!)))))
      ((if (= b #\c) (not (= %tn-echo-state 1)) #f)
        (changed 1 (fn (_) (do (%tn-banner "character" "]") (%tn-raw!)))))
      (#t
        (do (when (= b #\z)
              (do (%tn-cook!) (sys-kill 0 (ts-signal-number "TSTP")) (%tn-raw!)))
            (file-write 1 "continuing...\r\n")
            (unless (= %tn-echo-state 1) (%tn-cook!))
            #t)))))

; read_from_stdin: the bytes before any ^], 0xff doubled and CR or LF made
; CR LF, queued; a ^] drops the rest of the read and opens the menu.  #f
; when the run ends there.
(def %tn-from-stdin!
  (fn (_)
    (def r (file-read-run 0 512))
    (if (= (rest r) 0) (do (set! %tn-stdin-open? #f) #t)
      (let go ((i 0) (acc ()))
        (if (>= i (rest r)) (do (%tn-put (reverse acc)) #t)
          (let ((c (byte-at (first r) i)))
            (match
              ((= c 29) (do (%tn-put (reverse acc)) (not (null? (%tn-menu!)))))
              ((= c %tn-iac) (go (+ i 1) (pair c (pair c acc))))
              ((if (= c #\return) #t (= c #\newline)) (go (+ i 1) (pair #\newline (pair #\return acc))))
              (#t (go (+ i 1) (pair c acc))))))))))

; --- the loop ----------------------------------------------------------------------

(def %tn-sigint 2)

(def %tn-loop
  (fn (self shut?)
    (cu-sweep-tick! cu-sweep-lines)
    (if (Sys take-signal %tn-sigint)
      (if (null? (%tn-menu!)) (%tn-exit 1) (self shut?))
      (let ((ready (sys-poll (append (list (pair %tn-net (list (lit in))))
                                     (if %tn-stdin-open? (list (pair 0 (list (lit in)))) ()))
                             -1)))
        (def ready? (fn (_ fd) (List any? (fn (_ e) (= (first e) fd)) ready)))
        (match
          ((null? ready) (self shut?))
          ((if (ready? %tn-net) (not (%tn-from-net!)) #f)
            (do (%tn-flush!) (%tn-exit 0)))
          ((if (if %tn-stdin-open? (ready? 0) #f) (not (%tn-from-stdin!)) #f) (%tn-exit 1))
          (#t
            (do (%tn-flush!)
                (if (if (not %tn-stdin-open?) (not shut?) #f)
                  (do (Socket shutdown %tn-net) (self #t))
                  (self shut?)))))))))

; --- the applet -------------------------------------------------------------------

(def cu-telnet
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "telnet" argv))
    (def ops (Opts operands o))
    (if (if (null? ops) #t (> (length ops) 2)) (cu-usage "telnet")
      (guard (e (if (eq? (Err label e) (lit net))
                  (do (file-write 2 (string-concat (list "telnet: " (e msg) "\n"))) 1)
                  (error e)))
        (%tn-main o (first ops) (if (null? (rest ops)) () (first (rest ops))))))))

; bb_lookup_port: digits up to 65535, else /etc/services
(def tn-port
  (fn (_ s)
    (if (null? s) 23
      (let ((n (in-strtou s)))
        (if (if (null? n) #f (<= n 65535)) n
          (let ((p (in-servport s "tcp")))
            (if (null? p) (%net-die (string-concat (list "bad port '" s "'"))) p)))))))

(def %tn-main
  (fn (_ o host port-arg)
    (set! %tn-ttype-name (sys-getenv "TERM"))
    (set! %tn-login (let ((l (Opts value o "-l")))
                      (if (null? l) (if (Opts on? o "-a") (sys-getenv "USER") ()) l)))
    (def port (tn-port port-arg))
    (def ip (let ((q (guard (_ ()) (net-resolve host))))
              (if (null? q) (%net-die (string-concat (list "bad address '" host "'"))) q)))
    (set! %tn-net (guard (e (if (eq? (Err label e) (lit io))
                              (%net-die (string-concat (list "can't connect to remote host (" ip "): " (%wget-err-text e))))
                              (error e)))
                    (net-connect ip port)))
    (cu-stdin-to-command!)
    (set! %tn-tty-out? (sys-isatty 1))
    (file-write 1 (string-concat (list "Connected to " host "\n")))
    (sys-signal 13 cu-sig-ign)
    (Sys catch-signal %tn-sigint)
    (%tn-loop #f)))

(provide cu/telnet cu-telnet tn-port tn-run tn-str-bytes)

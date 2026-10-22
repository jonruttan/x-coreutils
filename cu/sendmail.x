; # x-coreutils -- the small tools, as applets
;
; ## cu/sendmail.x -- sendmail: a message on stdin sent by SMTP
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; mailutils/sendmail.c: the message on stdin to the server -S HOST[:PORT]
; ($SMTPHOST, else 127.0.0.1, port 25), or through -H 'PROG ARGS' run by sh
; on a pair of pipes.  EHLO (HELO if it is refused), AUTH LOGIN or PLAIN with
; -a, MAIL FROM, a RCPT TO for each recipient -- those named, and with -t
; those of the To, Cc and Bcc headers and their continuation lines -- then
; DATA: the headers (Bcc dropped, To added for the named recipients when
; there is none), the body with each leading dot doubled, and a dot.  A reply
; with the wrong code ends the run, "COMMAND failed"; a refused recipient is
; said and passed over, and a DATA no recipient was taken for ends the
; exchange with QUIT.

(def %sm-rd -1)                 ; the server, read
(def %sm-wr -1)                 ; the server, written
(def %sm-verbose 0)
(def %sm-timeout 0)
(def %sm-helper -1)
(def %sm-buf "")                ; the server's bytes read and not yet a line
(def %sm-eof? #f)

(def %sm-say (fn (_ msg) (file-write 2 (string-concat (list "sendmail: " msg "\n")))))
(def %sm-die (fn (_ msg) (Err raise (lit net) msg ())))

; --- the server's side ------------------------------------------------------------

; xmalloc_fgetline from the server: a line without its newline, or nil; -w's
; seconds without one end the run
(def %sm-getline
  (fn (self)
    (let ((nl (%wget-index %sm-buf #\newline 0)))
      (match
        ((not (null? nl))
          (let ((line (substring %sm-buf 0 nl)))
            (do (set! %sm-buf (substring %sm-buf (+ nl 1) (byte-len %sm-buf))) line)))
        (%sm-eof? (if (= (byte-len %sm-buf) 0) () (let ((l %sm-buf)) (do (set! %sm-buf "") l))))
        (#t (do (when (> %sm-timeout 0)
                  (when (null? (sys-poll (list (pair %sm-rd (list (lit in)))) (* 1000 %sm-timeout)))
                    (%sm-die "timed out")))
                (let ((r (file-read-run %sm-rd 4096)))
                  (if (= (rest r) 0) (set! %sm-eof? #t)
                    (set! %sm-buf (string-append %sm-buf (substring (first r) 0 (rest r))))))
                (self)))))))

(def %sm-cr-cut (fn (_ s) (let ((cr (%wget-index s #\return 0))) (if (null? cr) s (substring s 0 cr)))))

; send_r_n
(def %sm-send
  (fn (_ s)
    (when (> %sm-verbose 0) (%sm-say (string-concat (list "send:'" s "'"))))
    (guard (_ ()) (file-write %sm-wr (string-append s "\r\n")))))

(def %sm-atoi
  (fn (_ s)
    (let go ((i 0) (n 0))
      (if (if (< i (byte-len s)) (if (>= (byte-at s i) #\0) (<= (byte-at s i) #\9) #f) #f)
        (go (+ i 1) (+ (* n 10) (- (byte-at s i) #\0))) n))))

; smtp_checkp: MSG sent (nil sends nothing), the reply read past its NNN-
; lines, its code -- CODE, or any for -1 -- or the run ends "MSG failed"
(def %sm-check
  (fn (_ msg code)
    (unless (null? msg) (%sm-send msg))
    (def answer
      (let go ()
        (let ((a (%sm-getline)))
          (do (when (if (null? a) #f (> %sm-verbose 0)) (%sm-say (string-concat (list "recv:'" (%sm-cr-cut a) "'"))))
              (if (if (null? a) #f (if (> (byte-len a) 3) (= (byte-at a 3) #\-) #f)) (go) a)))))
    (def n (if (null? answer) () (%sm-atoi answer)))
    (if (if (null? n) #f (if (= code -1) #t (= n code))) n
      (do (%sm-helper-check)
          (%sm-die (string-append (if (null? msg) "(null)" msg) " failed"))))))

; the helper's own end, said as busybox's SIGCHLD handler says it
(def %sm-helper-check
  (fn (_)
    (when (> %sm-helper 0)
      (let ((st (str-make-raw 4)))
        (when (> (in-call (cu-ptr-call (in-c "waitpid") %sm-helper (cu-str->ptr st) 1)) 0)
          (let ((raw (cu-ptr-ref (cu-str->ptr st) 0 4)))
            (match ((> (% raw 128) 0) (%sm-die (string-append "helper killed by signal " (cu-int->str (% raw 128)))))
                   ((> (% (%wget-div raw 256) 256) 0)
                     (%sm-die (string-concat (list "helper exited (" (cu-int->str (% (%wget-div raw 256) 256)) ")"))))
                   (#t ()))))))))

; --- addresses ------------------------------------------------------------------

(def %sm-space? (fn (_ c) (match ((= c #\space) #t) ((= c #\tab) #t) ((= c #\newline) #t) ((= c #\return) #t) ((= c 11) #t) (#t (= c 12)))))

(def %sm-trim
  (fn (_ s)
    (def n (byte-len s))
    (def a (let go ((i 0)) (if (if (< i n) (%sm-space? (byte-at s i)) #f) (go (+ i 1)) i)))
    (def b (let go ((e n)) (if (if (> e a) (%sm-space? (byte-at s (- e 1))) #f) (go (- e 1)) e)))
    (substring s a b)))

(def %sm-safe? (fn (_ c) (match ((if (>= c #\a) (<= c #\z) #f) #t) ((if (>= c #\A) (<= c #\Z) #f) #t)
                                ((if (>= c #\0) (<= c #\9) #f) #t) (#t (%wget-memv c (list #\= #\+ #\_ #\- #\. #\@))))))

; sane_address: S trimmed, or "" said as a bad address
(def %sm-sane
  (fn (_ s)
    (def t (%sm-trim s))
    (if (List all? %sm-safe? (tn-str-bytes t)) t
      (do (%sm-say (string-concat (list "bad address '" t "'"))) ""))))

; angle_address: the address inside a trailing <...>, else all of S
(def %sm-angle
  (fn (_ s)
    (def t (%sm-trim s))
    (def lt (in-index-of t #\<))
    (%sm-sane (if (if (> (byte-len t) 0) (if (= (byte-at t (- (byte-len t) 1)) #\>) (not (null? lt)) #f) #f)
                (substring t (+ lt 1) (- (byte-len t) 1)) t))))

(def %sm-rcpt
  (fn (_ s)
    (unless (= (byte-len s) 0)
      (unless (= (%sm-check (string-concat (list "RCPT TO:<" s ">")) -1) 250)
        (%sm-say (string-concat (list "Bad recipient: <" s ">")))))))

; rcptto_list: each address of a comma-separated LIST, commas in quotes kept
(def %sm-rcpt-list
  (fn (_ list)
    (def n (byte-len list))
    (let go ((i 0) (from 0) (q? #f) (prev 0))
      (if (>= i n)
        (unless (= prev #\,) (%sm-rcpt (%sm-angle (substring list from n))))
        (let ((c (byte-at list i)))
          (match ((if (= c #\") (not (= prev #\\)) #f) (go (+ i 1) from (not q?) c))
                 ((if (not q?) (= c #\,) #f) (do (%sm-rcpt (%sm-angle (substring list from i))) (go (+ i 1) (+ i 1) q? c)))
                 (#t (go (+ i 1) from q? c))))))))

; --- the message ---------------------------------------------------------------

(def %sm-ci-prefix? (fn (_ s p) (if (< (byte-len s) (byte-len p)) #f (%mm-ci= (substring s 0 (byte-len p)) p))))

; the recipients named on the command line, each a RCPT TO, and the To header
; they make when the message has none
(def %sm-named
  (fn (_ argv has-to? headers)
    (let go ((l argv) (first? #t) (hs headers))
      (if (null? l) hs
        (let ((t (%sm-sane (first l))))
          (do (%sm-rcpt t)
              (go (rest l) #f
                  (if has-to? hs
                    (append hs (list (string-concat (list (if first? "To: " " ") t (if (null? (rest l)) "" ",")))))))))))))

; DATA and what follows: #f when DATA was refused
(def %sm-data!
  (fn (_ headers)
    (if (not (= (%sm-check "DATA" -1) 354)) #f
      (do (map %sm-send headers) #t))))

(def %sm-body-line (fn (_ s) (do (when (if (> (byte-len s) 0) (= (byte-at s 0) #\.) #f) (guard (_ ()) (file-write %sm-wr "."))) (%sm-send s))))

; the headers read, then the body: (SENT? . DONE?) -- SENT? nil when DATA
; was refused
(def %sm-message
  (fn (_ argv t?)
    (let go ((headers ()) (has-to? #f) (last (lit other)) (n 0))
      (let ((s (%mm-gets)))
        (def line (if (null? s) () (if (Str8 ends? "\n" s) (substring s 0 (- (byte-len s) 1)) s)))
        (def to? (if (null? line) #f (%sm-ci-prefix? line "To:")))
        (def cc? (if (null? line) #f (%sm-ci-prefix? line "cc:")))
        (def bcc? (if (null? line) #f (%sm-ci-prefix? line "Bcc:")))
        (def cont? (match ((null? line) #f) ((null? headers) #f) ((= (byte-len line) 0) #f) (#t (%sm-space? (byte-at line 0)))))
        (match
          ((if (not (null? line)) (if t? (if to? #t cc?) #f) #f)
            (do (%sm-rcpt-list (substring line 3 (byte-len line)))
                (if (>= (+ n 1) 256) (%sm-bail) (go (append headers (list line)) (if has-to? #t to?) (lit tocc) (+ n 1)))))
          ((if (not (null? line)) (if t? bcc? #f) #f)
            (do (%sm-rcpt-list (substring line 4 (byte-len line))) (go headers (if has-to? #t to?) (lit bcc) n)))
          ((if (null? line) #f (if (not (null? (%wget-index line #\: 0))) #t cont?))
            (let ((has2 (if has-to? #t to?)))
              (if (if cont? (not (eq? last (lit other))) #f)
                (do (%sm-rcpt-list (substring line 1 (byte-len line)))
                    (if (eq? last (lit bcc)) (go headers has2 last n)
                      (if (>= (+ n 1) 256) (%sm-bail) (go (append headers (list line)) has2 last (+ n 1)))))
                (if (>= (+ n 1) 256) (%sm-bail) (go (append headers (list line)) has2 (lit other) (+ n 1))))))
          (#t
            (let ((hs (%sm-named argv (if has-to? #t to?) headers)))
              (if (not (%sm-data! hs)) (%sm-bail)
                (do (if (null? line) (%sm-send "")
                      (do (%sm-body-line line)
                          (let body () (let ((b (%mm-gets))) (unless (null? b) (do (%sm-body-line (if (Str8 ends? "\n" b) (substring b 0 (- (byte-len b) 1)) b)) (body)))))))
                    (%sm-check "." 250)
                    (%sm-bail))))))))))

(def %sm-bail (fn (_) (%sm-check "QUIT" 221)))

; --- the connection --------------------------------------------------------------

; the server HOST[:PORT], port 25 by default
(def %sm-connect!
  (fn (_ spec)
    (def fd (%cu-dial spec 25))
    (set! %sm-rd fd)
    (set! %sm-wr fd)))

; launch_helper: sh -c CMD on a pair of pipes, its stdout ours to read
(def %sm-helper!
  (fn (_ cmd)
    (def to (sys-pipe))
    (def from (sys-pipe))
    (def pid (sys-fork))
    (when (= pid 0)
      (do (sys-close (rest to)) (sys-close (first from))
          (sys-dup2 (first to) 0) (sys-dup2 (rest from) 1)
          (sys-close (first to)) (sys-close (rest from)) (sys-close 3)
          (let ((r (in-exec "sh" (list "sh" "-c" cmd))))
            (do (%sm-say (string-concat (list "can't execute 'sh': " (in-errtext r)))) (sys-exit 127)))))
    (sys-close (first to))
    (sys-close (rest from))
    (set! %sm-helper pid)
    (set! %sm-rd (first from))
    (set! %sm-wr (rest to))))

; --- the applet ----------------------------------------------------------------------

(def %cu-sendmail
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "sendmail" argv))
    (if (if (Opts on? o "-H") (not (null? (Opts value o "-S"))) #f) (cu-usage "sendmail")
      (guard (e (if (eq? (Err label e) (lit net))
                  (do (%sm-say (e msg)) 1)
                  (error e)))
        (do (set! %mm-thunk stdin-thunk)
            (set-first! %mm-in ())
            (%sm-main o))))))

(def %sm-main
  (fn (_ o)
    (set! %sm-verbose (nc-count o "-v"))
    (set! %sm-timeout (let ((w (Opts value o "-w"))) (if (null? w) 0 (in-count w))))
    (set! %sm-buf "")
    (set! %sm-eof? #f)
    (set! %sm-helper -1)
    (def user (List fold (fn (_ acc a) (if (Str8 starts? "u" a) (substring a 1 (byte-len a)) acc)) () (Opts values o "-a")))
    (def pass (List fold (fn (_ acc a) (if (Str8 starts? "p" a) (substring a 1 (byte-len a)) acc)) () (Opts values o "-a")))
    (def plain? (List fold (fn (_ acc a)
                             (if (Str8 starts? "m" a)
                               (match ((Str8 starts? "p" (Str8 downcase (substring a 1 (byte-len a)))) #t)
                                      ((Str8 starts? "l" (Str8 downcase (substring a 1 (byte-len a)))) acc)
                                      (#t (%sm-die (string-append "unsupported AUTH method " (substring a 1 (byte-len a))))))
                               acc))
                           #f (Opts values o "-a")))
    (def auth? (not (null? (Opts values o "-a"))))
    (def host (%sm-sane (cu-uname-field (sys-uname) (lit nodename))))
    (sys-signal 13 cu-sig-ign)
    (if (Opts on? o "-H")
      (do (%sm-helper! (Opts value o "-H"))
          (let ((delay (sys-getenv "SMTP_ANTISPAM_DELAY"))) (unless (null? delay) (sys-sleep (%sm-atoi delay))))
          (let ((code (%sm-check "NOOP" -1)))
            (match ((= code 220) (%sm-check () 250))
                   ((not (= code 250)) (%sm-die "SMTP init failed"))
                   (#t ()))))
      (do (%sm-connect! (let ((s (Opts value o "-S"))) (if (null? s) (let ((e (sys-getenv "SMTPHOST"))) (if (null? e) "127.0.0.1" e)) s)))
          (%sm-check () 220)))
    (unless (= (%sm-check (string-append "EHLO " host) -1) 250)
      (%sm-check (string-append "HELO " host) 250))
    (when auth? (%sm-auth! user pass plain?))
    (def from (let ((f (Opts value o "-f")))
                (if (not (null? f)) f
                  (string-concat (list (if (null? user) (sys-user-name (sys-getuid)) user) "@" (%sm-canonical host))))))
    (%sm-check (string-concat (list "MAIL FROM:<" from ">")) 250)
    (%sm-message (Opts operands o) (Opts on? o "-t"))
    0))

; xgethostbyname's h_name for HOST
(def %sm-canonical
  (fn (_ host)
    (def h (cu-ptr-call (in-c "gethostbyname") host))
    (if (= (td-ptr->int h) 0) (%sm-die (string-concat (list "bad address '" host "'")))
      (cu-ptr->str (cu-int->ptr (cu-ptr-word h 0))))))

; AUTH LOGIN or PLAIN; without -au and -ap, the user and password are fd 4's
; first two lines
(def %sm-auth!
  (fn (_ user pass plain?)
    (def cred (if (if (null? user) #t (null? pass)) (%sm-fd4-cred) (pair user pass)))
    (def u (first cred))
    (def p (rest cred))
    (if plain?
      (do (%sm-check "AUTH PLAIN" 334)
          (guard (_ ()) (file-write %sm-wr (%mm-b64 (append (list 0) (tn-str-bytes u) (list 0) (tn-str-bytes p))))))
      (do (%sm-check "AUTH LOGIN" 334)
          (guard (_ ()) (file-write %sm-wr (%mm-b64 (tn-str-bytes u))))
          (%sm-check "" 334)
          (guard (_ ()) (file-write %sm-wr (%mm-b64 (tn-str-bytes p))))))
    (%sm-check "" 235)))

(def %sm-fd4-cred
  (fn (_)
    (def line (fn (_) (let go ((acc ()))
                        (let ((r (file-read-run 4 1)))
                          (if (if (= (rest r) 0) #t (= (byte-at (first r) 0) #\newline))
                            (if (if (null? acc) (= (rest r) 0) #f) () (bytes->str (reverse acc)))
                            (go (pair (byte-at (first r) 0) acc)))))))
    (def u (line))
    (def p (line))
    (if (if (null? u) #t (if (= (byte-len u) 0) #t (null? p))) (%sm-die "no username or password") (pair u p))))

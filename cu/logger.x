; # x-coreutils -- the small tools, as applets
;
; ## cu/logger.x -- logger: a message, or standard input's lines, to the system log
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; sysklogd/logger.c: the MESSAGE words joined by spaces go to syslog(3) as one
; message; with none, each line of standard input does, its newline kept, a
; line longer than the read buffer in pieces, and an empty line not at all.
; The tag is -t TAG, else the effective user's name; -s copies each message to
; standard error (LOG_PERROR).  -p takes a number or FACILITY.LEVEL, the names
; the C library's facilitynames and prioritynames hold; user.notice by
; default.

(module cu/logger)

(import cu/cli cu-opts)
(import cu/inetd in-percent)
(import cu/mime mm-ci=)
(import cu/prims bit-and byte-at byte-len cu-int->str cu-libc-sym cu-ptr-call
  file-write string-append string=? substring sys-geteuid sys-user-name)

(def %lg-facilities
  (list (pair "auth" 32) (pair "authpriv" 80) (pair "cron" 72) (pair "daemon" 24)
        (pair "ftp" 88) (pair "kern" 0) (pair "lpr" 48) (pair "mail" 16)
        (pair "mark" 192) (pair "news" 56) (pair "security" 32) (pair "syslog" 40)
        (pair "user" 8) (pair "uucp" 64)
        (pair "local0" 128) (pair "local1" 136) (pair "local2" 144) (pair "local3" 152)
        (pair "local4" 160) (pair "local5" 168) (pair "local6" 176) (pair "local7" 184)))

(def %lg-priorities
  (list (pair "alert" 1) (pair "crit" 2) (pair "debug" 7) (pair "emerg" 0)
        (pair "err" 3) (pair "error" 3) (pair "info" 6) (pair "none" 16)
        (pair "notice" 5) (pair "panic" 0) (pair "warn" 4) (pair "warning" 4)))

(def %lg-buf 1024)                    ; fgets' buffer: a piece is at most 1023 bytes
(def %lg-ident "")                    ; openlog keeps the pointer: held for the run

(def %lg-die (fn (_ msg) (Err raise (lit logger) msg ())))

(def %lg-digit? (fn (_ c) (if (>= c #\0) (<= c #\9) #f)))

; atoi of a NAME that starts with a digit
(def %lg-atoi
  (fn (_ s)
    (let go ((i 0) (n 0))
      (if (if (< i (byte-len s)) (%lg-digit? (byte-at s i)) #f)
        (go (+ i 1) (+ (* n 10) (- (byte-at s i) #\0)))
        n))))

; decode: the number, the value of the name TABLE holds ignoring case, or -1
(def %lg-decode
  (fn (_ name table)
    (if (if (> (byte-len name) 0) (%lg-digit? (byte-at name 0)) #f)
      (%lg-atoi name)
      (let ((hit (List find (fn (_ e) (mm-ci= (first e) name)) table)))
        (if (null? hit) -1 (rest hit))))))

; pencode: FACILITY.LEVEL, or LEVEL alone as a user's
(def %lg-pencode
  (fn (_ s)
    (def dot (Str8 index-of "." s))
    (def fac (if (null? dot) 8 (%lg-decode (substring s 0 dot) %lg-facilities)))
    (when (< fac 0) (%lg-die (string-append "unknown facility name: " (substring s 0 dot))))
    (def lev (%lg-decode (if (null? dot) s (substring s (+ dot 1) (byte-len s))) %lg-priorities))
    (when (< lev 0) (%lg-die (string-append "unknown priority name: " s)))
    (+ (bit-and lev 7) (bit-and fac 1016))))

(def %lg-send (fn (_ pri msg) (cu-ptr-call (cu-libc-sym "syslog") pri (in-percent msg))))

; the next piece fgets would read from TEXT: through its newline or of BUF-1
; bytes, or nil when more is needed and AT-END? is false
(def %lg-piece
  (fn (_ text at-end?)
    (def nl (Str8 index-of "\n" text))
    (def most (- %lg-buf 1))
    (match ((if (null? nl) #f (< nl most)) (substring text 0 (+ nl 1)))
           ((>= (byte-len text) most) (substring text 0 most))
           ((if at-end? (> (byte-len text) 0) #f) text)
           (#t ()))))

; each line of standard input, as fgets reads them, but "" and "\n"
(def %lg-lines
  (fn (_ pri stdin-thunk)
    (let go ((acc "") (at-end? #f))
      (let ((p (%lg-piece acc at-end?)))
        (match ((not (null? p)) (do (unless (string=? p "\n") (%lg-send pri p))
                              (go (substring acc (byte-len p) (byte-len acc)) at-end?)))
               (at-end? ())
               (#t (let ((r (stdin-thunk (lit chunk))))
                     (let ((s (if (pair? r) (substring (first r) 0 (rest r)) r)))
                       (go (string-append acc s) (= (byte-len s) 0))))))))))

(def %lg-main
  (fn (_ o stdin-thunk)
    (def tag (Opts value o "-t"))
    (set! %lg-ident
      (if (null? tag)
        (let ((name (sys-user-name (sys-geteuid))))
          (if (null? name) (cu-int->str (sys-geteuid)) name))
        tag))
    (cu-ptr-call (cu-libc-sym "openlog") %lg-ident (if (Opts on? o "-s") 32 0) 0)
    (def p (Opts value o "-p"))
    (def pri (if (null? p) 13 (%lg-pencode p)))
    (def words (Opts operands o))
    (if (null? words)
      (%lg-lines pri stdin-thunk)
      (%lg-send pri (Str8 join " " words)))
    (cu-ptr-call (cu-libc-sym "closelog"))
    0))

(def cu-logger
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "logger" argv))
    (guard (e (if (eq? (Err label e) (lit logger))
                (do (file-write 2 (string-append "logger: " (e msg) "\n")) 1)
                (error e)))
      (%lg-main o stdin-thunk))))

(provide cu/logger cu-logger)

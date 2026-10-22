; # x-coreutils -- the small tools, as applets
;
; ## cu/watch.x -- watch
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's watch (procps/watch.c): PROG run every period until a signal ends
; watch, the screen cleared before each run and a header line above it -- the
; period, the command, and the local time at the right edge of the width
; standard error's terminal has, or $COLUMNS, or 80.  The command is its words
; joined by spaces and run by `/bin/sh -c`, as system(3) runs it, SIGINT and
; SIGQUIT ignored while it runs, so a ^C then ends the command and not watch,
; and at any other time ends watch; with -x its words are run as they are, and
; a command that will not run says nothing.  -d is taken and does nothing, as
; busybox's.

(module cu/watch)

(import cu/cli cu-opts cu-refuse-option cu-usage)
(import cu/prims byte-at byte-len cu-stdin-to-command! cu-sweep-at file-write
  string-append string-concat substring sys-exec-or-err sys-exit sys-fork
  sys-getenv sys-signal sys-usleep sys-wait)
(import cu/procps ps-boot-line)
(import cu/text cu-pad-right)

(def %watch-esc (bytes->str (list 27)))
(def %watch-most 9007199254740992)      ; 2^53: the microseconds a period may be

; the wait between runs, in microseconds, and the clock; the spec rebinds both
(def %watch-wait (fn (_ us) (sys-usleep us)))
(def %watch-now (fn (_) (date-now-unix)))

; --- cu-watch ----------------------------------------------------------------

(def cu-watch
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "watch" argv))
    (def words (Opts operands o))
    (def n (Opts value o "-n"))
    (def period (if (null? n) (Float from 2) (%watch-period n)))
    (match
      ((not (null? (Opts unknown o))) (cu-refuse-option "watch" (Opts unknown o)))
      ((null? words) (cu-usage "watch"))
      ((eq? period (lit usage)) (cu-usage "watch"))
      ((str? period) (do (file-write 2 (string-concat (list "watch: invalid number '" period "'\n"))) 1))
      ; the engine keeps SIGINT to itself; busybox's watch dies of it
      (#t (do (%watch-signals! (Sys sig-dfl))
              (%watch-loop 0 words (Str8 join " " words) (Opts on? o "-x") (not (Opts on? o "-t")) period))))))

; parse_duration_str, as busybox builds it with FLOAT_DURATION: the seconds
; as a Float, the text xatoul_sfx calls no number, or usage where strtod
; leaves part of its number unread.  Without a dot the whole is xatoul_sfx's:
; digits, then s m h or d, or nothing.  With one, the digits and dots in front
; are strtod's, and what follows them, after a 1, xatoul_sfx's.  Past 2^53
; microseconds, 285 years, a period is no number here, where busybox takes
; up to 2^64 - 1 seconds.
(def %watch-period
  (fn (_ s)
    (def len (%watch-span s 0))
    (def head (substring s 0 len))
    (def tail (substring s len (byte-len s)))
    (def mult (%watch-suffix tail))
    (def dots (%watch-count head #\.))
    (match
      ((= (%watch-count s #\.) 0)
        (let ((n (if (> len 0) (%watch-digits head) ())))
          (if (if (null? n) #t (null? mult)) s
            (%watch-capped (Float * (Float from n) (Float from mult)) s))))
      ; strtod reads digits, a dot and digits: with more dots, or no digits, it
      ; leaves part of the front unread, and musl's counts an empty front so
      ((if (> dots 1) #t (= dots len)) (lit usage))
      ((null? mult) (string-append "1" tail))
      (#t (%watch-capped (Float * (Float from (%watch-decimal head)) (Float from mult)) s)))))

; the digits and dots at the front of S from I, as strspn counts them
(def %watch-span
  (fn (self s i)
    (if (>= i (byte-len s)) i
      (let ((b (byte-at s i)))
        (if (if (= b #\.) #t (if (>= b #\0) (<= b #\9) #f)) (self s (+ i 1)) i)))))

(def %watch-count
  (fn (_ s c)
    (def go (fn (self i acc) (if (>= i (byte-len s)) acc (self (+ i 1) (if (= (byte-at s i) c) (+ acc 1) acc)))))
    (go 0 0)))

; a duration suffix's seconds: 1 for none or s, then m h d; nil for any other
(def %watch-suffix
  (fn (_ t)
    (def c (if (= (byte-len t) 1) (byte-at t 0) 0))
    (match
      ((= (byte-len t) 0) 1)
      ((= c #\s) 1)
      ((= c #\m) 60)
      ((= c #\h) 3600)
      ((= c #\d) 86400)
      (#t ()))))

; the digits of S as a number, nil past 2^53
(def %watch-digits
  (fn (_ s)
    (def go (fn (self i acc)
              (match
                ((> acc %watch-most) ())
                ((>= i (byte-len s)) acc)
                (#t (self (+ i 1) (+ (* acc 10) (- (byte-at s i) #\0)))))))
    (go 0 0)))

; a number strtod reads, written so Float from reads it too: a digit on each
; side of the dot
(def %watch-decimal
  (fn (_ s)
    (def l (byte-len s))
    (string-concat (list (if (= (byte-at s 0) #\.) "0" "") s (if (= (byte-at s (- l 1)) #\.) "0" "")))))

; the Float SECS, or S as no number when SECS is past 2^53 microseconds
(def %watch-capped
  (fn (_ secs s) (if (Float < (Float from %watch-most) (Float * secs (Float from 1000000))) s secs)))

; --- the loop -----------------------------------------------------------------

; Each round: home and clear, the header and an empty line unless -t, the
; command, the wait; the rounds' garbage collected every 16th
(def %watch-loop
  (fn (self round words cmd exec? header? period)
    (cu-sweep-at round 15)
    (file-write 1 (string-concat (list %watch-esc "[H" %watch-esc "[J")))
    (when header?
      (file-write 1 (string-append (%watch-header period cmd (%watch-width) (%watch-now)) "\n\n")))
    (if exec? (%watch-spawn words) (%watch-system cmd))
    (%watch-wait (Float ->int (Float * period (Float from 1000000))))
    (self (+ round 1) words cmd exec? header? period)))

; "Every 2.0s: CMD", CMD padded to WIDTH; past 20 columns cut to WIDTH less
; one, the last 19 the local time
(def %watch-header
  (fn (_ period cmd width now)
    (def line (string-concat (list "Every " (vm-fixed period 1) "s: " (cu-pad-right cmd width))))
    (if (> width 20)
      (string-append (substring line 0 (- width 20)) (substring (ps-boot-line now) 0 19))
      line)))

; get_terminal_width on standard error: $COLUMNS over the terminal's, 80 for
; one under 2 or past 29999
(def %watch-width
  (fn (_)
    (def m (Term measure 2))
    (%vi-dim (if (pair? m) (first m) 0) (sys-getenv "COLUMNS") 80)))

; busybox's spawn_and_wait: the words run, a child that cannot exec them
; ending 111 without a word
(def %watch-spawn
  (fn (_ words)
    (def pid (sys-fork))
    (if (= pid 0)
      (do (cu-stdin-to-command!)
          (sys-exec-or-err (first words) (rest words))
          (sys-exit 111))
      (sys-wait pid))))

; SIGINT's and SIGQUIT's disposition: HOW, (Sys sig-ign) or (Sys sig-dfl)
(def %watch-signals! (fn (_ how) (do (sys-signal 2 how) (sys-signal 3 how))))

; system(3): /bin/sh -c CMD, SIGINT and SIGQUIT ignored from before the fork
; until it ends, and their defaults the shell's
(def %watch-system
  (fn (_ cmd)
    (%watch-signals! (Sys sig-ign))
    (def pid (sys-fork))
    (if (= pid 0)
      (do (%watch-signals! (Sys sig-dfl))
          (cu-stdin-to-command!)
          (sys-exec-or-err "/bin/sh" (list "-c" cmd))
          (sys-exit 127))
      (let ((st (sys-wait pid)))
        (do (%watch-signals! (Sys sig-dfl)) st)))))

(provide cu/watch cu-watch)

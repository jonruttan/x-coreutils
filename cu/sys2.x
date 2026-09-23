; # x-coreutils -- the small tools, as applets
;
; ## cu/sys2.x -- the busybox expansion, system half
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; true false env printenv sleep date which xargs test.

(def %cu-true (fn (_ argv stdin-thunk) 0))
(def %cu-false (fn (_ argv stdin-thunk) 1))

; Is "NAME=VALUE" one of NAMES?
(def %cu-env-named?
  (fn (_ entry names)
    (def end (byte-len entry))
    (def eq
      (let ((go (fn (self i)
                  (if (>= i end) (- 0 1)
                    (if (= (byte-at entry i) 61) i (self (+ i 1)))))))
        (go 0)))
    (if (< eq 0) #f
      (let ((nm (substring entry 0 eq)))
        (let ((go (fn (self l)
                    (if (null? l) #f
                      (if (string=? (first l) nm) #t (self (rest l)))))))
          (go names))))))

; env [-i] [-0] [-u NAME]... [-] [NAME=VALUE]... [COMMAND [ARG]...]
;
; -i starts from an empty environment, and so does a - before the operands; -u
; drops a name; each NAME=VALUE replaces its name where it stands, or is added
; at the end, as setenv places it.  The options end at the first operand, so a
; command's own options stay its own.  With no command the environment is
; printed, one entry to a line or, under -0, each ended with a NUL -- which is
; what lets a value hold a newline.  A command runs in a child given those
; changes and the caller's standard input, and env answers how it ended: its
; status, 127 when there is no such command, 126 when it cannot be run.

; the NAME of a NAME=VALUE entry, and its VALUE
(def %cu-env-name
  (fn (_ e) (first (%cu-env-cut e))))
(def %cu-env-value
  (fn (_ e) (rest (%cu-env-cut e))))
(def %cu-env-cut
  (fn (_ e)
    (let ((at (%cu-env-eq-at e 0)))
      (if (< at 0) (pair e "")
        (pair (substring e 0 at) (substring e (+ at 1) (byte-len e)))))))
(def %cu-env-eq-at
  (fn (self e i)
    (match
      ((>= i (byte-len e)) (- 0 1))
      ((= (byte-at e i) 61) i)                                    ; =
      (#t (self e (+ i 1))))))

; env's arguments with each -0 before the operands taken out, and whether there
; was one: (ZERO? . ARGUMENTS).  Opts reads -0 as a number, which would end the
; options early.  -u takes the argument after it.
(def %cu-env-zero
  (fn (self as acc zero?)
    (match
      ((null? as) (pair zero? (reverse acc)))
      ((string=? (first as) "-0") (self (rest as) acc #t))
      ((if (string=? (first as) "-u") (pair? (rest as)) #f)
        (self (rest (rest as)) (pair (first (rest as)) (pair "-u" acc)) zero?))
      ((if (> (byte-len (first as)) 1)
         (if (= (byte-at (first as) 0) 45) (not (string=? (first as) "--")) #f)
         #f)
        (self (rest as) (pair (first as) acc) zero?))
      (#t (pair zero? (append (reverse acc) as))))))

; the leading NAME=VALUE operands, and what follows them: (SETS . COMMAND)
(def %cu-env-sets
  (fn (self ops sets)
    (if (if (pair? ops) (>= (%cu-env-eq-at (first ops) 0) 0) #f)
      (self (rest ops) (pair (first ops) sets))
      (pair (reverse sets) ops))))

; ENTRIES with SET's name holding SET's value: in its place, or at the end
(def %cu-env-put
  (fn (_ entries set)
    (let ((name (%cu-env-name set)))
      (if (%cu-env-named? set (map %cu-env-name entries))
        (map (fn (_ e) (if (string=? (%cu-env-name e) name) set e)) entries)
        (append entries (list set))))))

(def %cu-env-apply
  (fn (self entries sets)
    (if (null? sets) entries (self (%cu-env-put entries (first sets)) (rest sets)))))

; The child that becomes COMMAND: its own environment changed, the caller's
; standard input put back, then exec.  A command exec refuses is named with the
; reason.  Every path ends in an exit, so nothing returns into the applet.
(def %cu-env-child
  (fn (_ clear? drop sets cmd)
    (do (guard (_ (sys-exit 125))
          (do (if clear?
                (map (fn (_ e) (sys-unsetenv (%cu-env-name e))) (sys-environ))
                ())
              (map sys-unsetenv drop)
              (map (fn (_ s) (sys-setenv (%cu-env-name s) (%cu-env-value s))) sets)
              (cu-stdin-to-command!)
              (let ((e (sys-exec-or-err (first cmd) (rest cmd))))
                (do (file-write 2
                      (string-concat
                        (list "env: '" (first cmd) "': " (file-err-text e) "\n")))
                    (sys-exit (if (eq? (file-err-sym e) (lit enoent)) 127 126))))))
        (sys-exit 125))))

(def %cu-env
  (fn (_ argv stdin-thunk)
    (let ((z (%cu-env-zero argv () #f)))
      (let ((o (%cu-opts "env" (rest z))))
        (let ((ops (Opts operands o)))
          (let ((dash? (if (pair? ops) (string=? (first ops) "-") #f)))
            (let ((clear? (if dash? #t (Opts on? o "-i")))
                  (drop (Opts values o "-u"))
                  (split (%cu-env-sets (if dash? (rest ops) ops) ())))
              (match
                ((null? (rest split))
                  (let ((env (%cu-env-apply
                               (filter (fn (_ e) (not (%cu-env-named? e drop)))
                                 (if clear? () (sys-environ)))
                               (first split))))
                    (do (if (first z) (%cu-print-fields env 0) (%cu-print-lines env))
                        0)))
                ((first z)
                  (do (file-write 2 "env: cannot specify --null (-0) with command\n")
                      125))
                (#t
                  (let ((pid (sys-fork)))
                    (if (= pid 0)
                      (%cu-env-child clear? drop (first split) (rest split))
                      (sys-wait pid))))))))))))

(def %cu-printenv
  (fn (_ argv stdin-thunk)
    (if (null? argv)
      (%cu-env argv stdin-thunk)
      (let ((v (sys-getenv (first argv))))
        (if (null? v) 1
          (do (display (string-append v "\n")) 0))))))

(def %cu-sleep
  (fn (_ argv stdin-thunk)
    (if (null? argv) (%cu-missing-operand "sleep" argv)
      (do (sys-sleep (%cu-num-prefix (first argv))) 0))))

; date: ISO-8601 UTC by default (a recorded divergence from the locale
; format), +%s for unix seconds
; date moved to cu/date.x, which is where its strftime lives.

; which: the PATH walk; existence is the test (there is no access(X_OK)
; door -- the recorded divergence).  -a lists every directory that has
; the name, in PATH order, rather than stopping at the first.
(def %cu-which
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "which" argv))
    (def all? (Opts on? o "-a"))
    (def path (sys-getenv "PATH"))
    (def dirs (if (null? path) () (%cu-split-byte path 58)))  ; :
    (def hits
      (fn (self ds name)
        (if (null? ds) ()
          (let ((cand (string-append (first ds)
                        (string-append "/" name))))
            (match
              ((not (file-exists? cand)) (self (rest ds) name))
              (all? (pair cand (self (rest ds) name)))
              (#t (list cand)))))))
    (def each
      (fn (self os st)
        (if (null? os) st
          (let ((found (hits dirs (first os))))
            (if (null? found)
              (self (rest os) 1)
              (do (%cu-print-lines found)
                  (self (rest os) st)))))))
    (each (Opts operands o) 0)))

; xargs: stdin words append to the command (default echo); -n N batches.
; --- xargs -------------------------------------------------------------------
;
; -0 takes the items NUL-separated rather than on whitespace, which is what
; makes a name holding a space or a newline safe to pass on.  Its input is
; read as bytes (cu/prims.x), since the one string the applet protocol hands
; over would stop at the first NUL.
;
; -p is the one flag still not declared: it prompts before each command, and
; a prompt wants a tty, which the protocol has no way to offer.  An option
; the guard accepts and the applet does not read is how option bugs get in.

; Items up to the logical EOF marker (-E), which ends the input early.
(def %cu-xargs-until
  (fn (self ws marker)
    (if (null? ws) ()
      (if (string=? (first ws) marker) ()
        (pair (first ws) (self (rest ws) marker))))))

; Every occurrence of MARK in S replaced by VAL -- -I's substitution.
(def %cu-xargs-subst
  (fn (_ s mark val)
    (def n (byte-len mark))
    (def end (byte-len s))
    (def go
      (fn (self i start acc)
        (if (> (+ i n) end)
          (string-append acc (substring s start end))
          (if (string=? (substring s i (+ i n)) mark)
            (self (+ i n) (+ i n)
              (string-append acc
                (string-append (substring s start i) val)))
            (self (+ i 1) start acc)))))
    (if (= n 0) s (go 0 0 ""))))

; ONE BATCH: as many items as -n and -s allow, and never fewer than one.
; Taking zero would not shorten the line, it would loop forever.
(def %cu-xargs-batch
  (fn (_ cmd ws n maxs)
    (def base (byte-len (%cu-join-with cmd " ")))
    (def go
      (fn (self l k len acc)
        (if (null? l)
          (pair (reverse acc) ())
          (if (if (> n 0) (>= k n) #f)
            (pair (reverse acc) l)
            (let ((len2 (+ len (+ 1 (byte-len (first l))))))
              (if (if (> maxs 0) (if (> len2 maxs) (> k 0) #f) #f)
                (pair (reverse acc) l)
                (self (rest l) (+ k 1) len2 (pair (first l) acc))))))))
    (go ws 0 base ())))

(def %cu-xargs-loop
  (fn (self cmd ws n maxs run! st)
    (if (null? ws) st
      (let ((b (%cu-xargs-batch cmd ws n maxs)))
        (let ((st2 (run! (first b))))
          (self cmd (rest b) n maxs run! (if (> st2 st) st2 st)))))))

; -I: one item per command, substituted INTO the arguments rather than
; appended after them, so nothing is added at the end.
(def %cu-xargs-each
  (fn (self cmd repl ws trace? st)
    (if (null? ws) st
      (let ((argv (map (fn (_ a) (%cu-xargs-subst a repl (first ws))) cmd)))
        (do
          (if trace?
            (file-write 2 (string-append (%cu-join-with argv " ") "\n"))
            ())
          (let ((st2 (proc-run argv)))
            (self cmd repl (rest ws) trace?
              (if (> st2 st) st2 st))))))))

(def %cu-xargs
  (fn (_ argv stdin-thunk)
    ; -0 reads as a negative NUMBER to Opts before the declaration is
    ; consulted (x-lang#650, what ls's -1 works around).  Here that also
    ; ENDS the parse, since this row stops at its first operand, so a -a
    ; after it would never be read: the token is taken off the line
    ; first, and what is left parses as it should.
    (def zero? (%cu-member-s? "-0" argv))
    (def o (%cu-opts "xargs"
             (filter (fn (_ a) (not (string=? a "-0"))) argv)))
    (def cmd0 (Opts operands o))
    (def cmd (if (null? cmd0) (list "echo") cmd0))
    (def n (let ((v (Opts value o "-n"))) (if (null? v) 0 (%cu-num-prefix v))))
    (def maxs (let ((v (Opts value o "-s"))) (if (null? v) 0 (%cu-num-prefix v))))
    (def repl (Opts value o "-I"))
    (def eof (Opts value o "-E"))
    (def trace? (Opts on? o "-t"))
    (def src (let ((a (Opts value o "-a"))) (if (null? a) () (list a))))
    ; -0 splits on the NUL and nothing else: a space or a newline inside an
    ; item is part of it, which is the whole reason for the flag.
    ; an -a file xargs cannot read is said, and nothing is run
    (def zread
      (if zero? (%cu-delim-fields-said src stdin-thunk 0 (%cu-says "xargs") #t)
        (pair () 0)))
    (def input
      (if (if zero? #t (null? src)) ()
        (%cu-read-said (%cu-says "xargs") (first src))))
    (def failed? (if (Err err? input) #t (> (rest zread) 0)))
    (def words0
      (match
        (zero? (first zread))
        (failed? ())
        (#t (let ((text (if (null? src) (stdin-thunk) input)))
              (%cu-words-line (%cu-join-with (%cu-lines text) " "))))))
    (def words (if (null? eof) words0 (%cu-xargs-until words0 eof)))
    (def run!
      (fn (_ ws)
        (do
          ; -t traces to STDERR, so a traced run's stdout stays the
          ; command's own output and nothing else.
          (if trace?
            (file-write 2
              (string-append (%cu-join-with (append cmd ws) " ") "\n"))
            ())
          (proc-run (append cmd ws)))))
    (match
      (failed? 1)
      ((null? words) (if (Opts on? o "-r") 0 (run! ())))
      ((not (null? repl)) (%cu-xargs-each cmd repl words trace? 0))
      ((if (Opts on? o "-x")
              (if (> maxs 0)
                (> (+ (byte-len (%cu-join-with cmd " "))
                      (+ 1 (byte-len (first words)))) maxs)
                #f)
              #f)
        (do (file-write 2 "xargs: argument line too long\n") 1))
      (#t (%cu-xargs-loop cmd words n maxs run! 0)))))

; test, [ and [[ moved to cu/test.x, which parses the whole grammar.

(def %cu-last
  (fn (self l) (if (null? (rest l)) (first l) (self (rest l)))))
(def %cu-drop-last
  (fn (self l)
    (if (null? (rest l)) ()
      (pair (first l) (self (rest l))))))

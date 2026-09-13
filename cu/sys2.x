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

(def %cu-env
  (fn (_ argv stdin-thunk)
    (do (%cu-print-lines (sys-environ)) 0)))

(def %cu-printenv
  (fn (_ argv stdin-thunk)
    (if (null? argv)
      (%cu-env argv stdin-thunk)
      (let ((v (sys-getenv (first argv))))
        (if (null? v) 1
          (do (display (string-append v "\n")) 0))))))

(def %cu-sleep
  (fn (_ argv stdin-thunk)
    (do (sys-sleep (%cu-num-prefix (first argv))) 0)))

; date: ISO-8601 UTC by default (a recorded divergence from the locale
; format), +%s for unix seconds
(def %cu-date
  (fn (_ argv stdin-thunk)
    (if (if (pair? argv) (string=? (first argv) "+%s") #f)
      (do (display (string-append (%cu-int->str (date-now-unix)) "\n"))
          0)
      (do (display (string-append (date-now-iso) "\n")) 0))))

; which: the PATH walk; existence is the test (there is no access(X_OK)
; door -- the recorded divergence)
(def %cu-which
  (fn (_ argv stdin-thunk)
    (def path (sys-getenv "PATH"))
    (def dirs (if (null? path) () (%cu-split-byte path 58)))  ; :
    (def go
      (fn (self ds name)
        (if (null? ds) ()
          (let ((cand (string-append (first ds)
                        (string-append "/" name))))
            (if (file-exists? cand) cand (self (rest ds) name))))))
    (def each
      (fn (self os st)
        (if (null? os) st
          (let ((hit (go dirs (first os))))
            (if (null? hit)
              (self (rest os) 1)
              (do (display (string-append hit "\n"))
                  (self (rest os) st)))))))
    (each argv 0)))

; xargs: stdin words append to the command (default echo); -n N batches
; --- xargs -------------------------------------------------------------------
;
; TWO OF BUSYBOX'S NINE ARE NOT DECLARED, and the reason is the rule this
; bundle keeps: an option the guard accepts and the applet does not read
; is how every option bug here got in.
;
;   -0  input items separated by NUL.  The input cannot REACH the applet:
;       a NUL truncates an x string at every door -- file-read-all on a
;       six-byte file with NULs answers 2, and a raw file-read-fd answers
;       2 as well.  Declaring -0 would accept a flag whose input is
;       unrepresentable.
;   -p  prompt before each command.  A prompt wants a tty, and the applet
;       protocol hands an applet one string of stdin and nothing else.
;
; The other seven are here.

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
    (def o (%cu-opts "xargs" argv))
    (def cmd0 (Opts operands o))
    (def cmd (if (null? cmd0) (list "echo") cmd0))
    (def n (let ((v (Opts value o "-n"))) (if (null? v) 0 (%cu-num-prefix v))))
    (def maxs (let ((v (Opts value o "-s"))) (if (null? v) 0 (%cu-num-prefix v))))
    (def repl (Opts value o "-I"))
    (def eof (Opts value o "-E"))
    (def trace? (Opts on? o "-t"))
    (def text
      (let ((a (Opts value o "-a")))
        (if (null? a) (stdin-thunk) (file-read-all a))))
    (def words0 (%cu-words-line (%cu-join-with (%cu-lines text) " ")))
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
    (if (null? words)
      ; POSIX runs the command once over empty input; -r is the flag that
      ; asks for the other answer.
      (if (Opts on? o "-r") 0 (run! ()))
      (if (not (null? repl))
        (%cu-xargs-each cmd repl words trace? 0)
        ; -x: an item that cannot fit the -s budget at all is refused
        ; rather than run anyway, which is what the batcher would do.
        (if (if (Opts on? o "-x")
              (if (> maxs 0)
                (> (+ (byte-len (%cu-join-with cmd " "))
                      (+ 1 (byte-len (first words)))) maxs)
                #f)
              #f)
          (do (file-write 2 "xargs: argument line too long\n") 1)
          (%cu-xargs-loop cmd words n maxs run! 0))))))

; test, [ and [[ moved to cu/test.x, which parses the whole grammar.

(def %cu-last
  (fn (self l) (if (null? (rest l)) (first l) (self (rest l)))))
(def %cu-drop-last
  (fn (self l)
    (if (null? (rest l)) ()
      (pair (first l) (self (rest l))))))

; # x-coreutils -- the small tools, as applets
;
; ## cu/cli.x -- the command line: an applet found, its options read, its run
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;   x -l coreutils -- APPLET [args]...
;
; cu-run is the pure-ish core the specs drive: (cu-run ARGV INPUT) with
; INPUT standing for stdin.  cu-main reads the real stdin lazily and
; caches it, so an applet that never asks never blocks.

(module cu/cli)

(import cu/prims append byte-at byte-len cu-nth cu-stdin! cu-stdin-chunk!
  file-write filter length map net-stdin-socket reverse set-first!
  string-append string-concat string=? substring sys-exit)
(import cu/text cu-member-s?)

; the applet NAME names, a static of Applets, or nil
(def cu-find-applet
  (fn (_ name) (class-static-ref Applets (Str8 ->sym name))))

; An applet's row in cu/options.x: (DECLARATION) or (DECLARATION LABEL), or
; nil for an applet with no row.
(def %cu-row-of
  (fn (_ applet)
    (def go (fn (self es)
              (if (null? es) ()
                (if (string=? (first (first es)) applet) (rest (first es))
                  (self (rest es))))))
    (go cu-option-spec)))

; The row as the parse reads it: (FLAGS VALUES) or (FLAGS VALUES LABEL), the
; spellings its declaration lists, hidden or not.
(def cu-spec-of
  (fn (_ applet)
    (let ((row (%cu-row-of applet)))
      (if (null? row) ()
        (pair (Opts flags (first row))
          (pair (Opts valued (first row)) (rest row)))))))

; An applet's help, when its first argument asks for it: busybox's text on
; standard output, and 0.  nil when it does not ask, or the applet has no help
; of its own -- test, true, false and echo take --help as an operand, as POSIX
; has it.  An applet busybox has no text for says so.
(def %cu-help
  (fn (_ applet args)
    (let ((row (%cu-row-of applet)))
      (match
        ((null? row) ())
        ((Opts help? (first row) args)
          (do (file-write 1 (Opts usage (first row))) 0))
        ((if (pair? args) (if (string=? (first args) "--help")
                            (cu-member-s? applet %cu-no-help) #f) #f)
          (do (file-write 1 "No help available\n") 0))
        (#t ())))))

; The applets busybox prints no help text for.
(def %cu-no-help (list "ascii" "tree" "pipe_progress" "dnsdomainname"))

; An applet's usage text, for the refusals that print it: busybox's, to
; standard error, and 1.
(def cu-usage
  (fn (_ applet)
    (do (file-write 2 (Opts usage (first (%cu-row-of applet)))) 1)))

; THE ONE PARSE.  Every applet and the guard reach their options
; through this, so both read the row that was declared for the applet.
(def cu-opts
  (fn (_ applet argv)
    (def spec (cu-spec-of applet))
    (def flags (if (null? spec) () (first spec)))
    (def values (if (null? spec) () (first (rest spec))))
    (def label (if (null? spec) ()
                (if (null? (rest (rest spec))) () (first (rest (rest spec))))))
    (match
      ((eq? label (lit leading)) (Opts parse-leading flags values argv))
      ; a first word that is -SIGNAL is the applet's own, read before getopt
      ; as busybox's pkill reads it
      ((eq? label (lit signal))
        (Opts parse flags values (if (null? (pg-signal-word argv)) argv (rest argv))))
      ; the first -SIGNAL before a --, wherever it stands, and -4 and -6, as
      ; busybox's fuser reads them
      ((eq? label (lit signal-any))
        (Opts parse flags values (first (rest (rest (fu-args argv))))))
      ; options up to the first word that is not a cluster of the flags; each
      ; letter reaches the parse as a word of its own, so the flags are listed
      ; in the order given (the parse reverses a cluster's), and the rest come
      ; behind a -- of its own
      ((eq? label (lit known))
        (let ((split (%cu-known-flags flags argv ())))
          (Opts parse flags values (append (first split) (pair "--" (rest split))))))
      ; no options at all: a first -- goes, as getopt's would, and the rest
      ; reach the parse behind a -- of its own, so each is an operand
      ((eq? label (lit none))
        (Opts parse () ()
          (pair "--" (if (if (pair? argv) (string=? (first argv) "--") #f)
                       (rest argv) argv))))
      (#t (Opts parse flags values argv)))))

; The leading words of ARGV that are clusters of FLAGS, and the words from the
; first that is not one: (LETTERS . REST), each letter a flag word of its own,
; in the order given.  A --, a lone - or a -x ends the run and is kept.
(def %cu-known-flags
  (fn (self flags argv acc)
    (def ls (if (null? argv) () (%cu-flag-letters flags (first argv))))
    (if (null? ls)
      (pair (reverse acc) argv)
      (self flags (rest argv) (append (reverse ls) acc)))))

; WORD's letters as the flags they spell, in order, where WORD is a - and one
; or more letters, each one of FLAGS; nil where it is anything else
(def %cu-flag-letters
  (fn (_ flags word)
    (def n (byte-len word))
    (def go
      (fn (self i acc)
        (if (= i n) (reverse acc)
          (let ((f (bytes->str (list 45 (byte-at word i)))))
            (if (cu-member-s? f flags) (self (+ i 1) (pair f acc)) ())))))
    (if (= (byte-at word 0) 45) (go 1 ()) ())))

; An applet that declares no flags reads no options, only operands: the parse
; hands it those, so the -- that ends the options is gone before it looks.
(def %cu-flagless?
  (fn (_ applet)
    (let ((spec (cu-spec-of applet)))
      (if (null? spec) #t
        (if (null? (first spec)) (null? (first (rest spec))) #f)))))

; Of FLAGS, the one given last, or nil: for flags where a later one overrides an
; earlier, as chmod's -v overrides -c.  The parse lists the flags it saw in the
; order given, except that it reverses the letters of one cluster, so -cv reads
; as -vc.
(def cu-last-given
  (fn (_ o flags)
    (%cu-last-given-in (Assoc get (lit on) o) flags ())))

(def %cu-last-given-in
  (fn (self on flags found)
    (if (null? on) found
      (self (rest on) flags
        (if (cu-member-s? (first on) flags) (first on) found)))))

; Of the value-taking FLAGS, the one given last, or nil: head's -n and -c, where
; the later one says what is counted.  The parse keeps each value with its flag,
; in the order given.
(def cu-last-valued
  (fn (_ o flags)
    (%cu-last-given-in (map (fn (_ v) (first v)) (Assoc get (lit values) o))
      flags ())))

; An option TOK that APPLET does not take, refused as busybox refuses it: musl
; getopt's line, then the applet's usage text, on standard error; 2 for sort and
; tty, whose busybox exits with 2 on a usage error, and 1 for the rest
(def cu-refuse-option
  (fn (_ applet tok)
    (do (unless (if (cu-member-s? applet %cu-usage-only) #t
                  ; chmod reads a dash word as a mode before getopt sees it
                  (if (string=? applet "chmod")
                    (not (if (> (byte-len tok) 1) (= (byte-at tok 1) #\-) #f)) #f))
          (file-write 2 (string-concat (list applet ": " (%cu-refusal applet tok) "\n"))))
        ; an applet busybox has no usage text for says so instead
        (file-write 2 (if (cu-member-s? applet %cu-no-help) "No help available\n"
                        (Opts usage (first (%cu-row-of applet)))))
        (if (cu-member-s? applet (list "sort" "tty")) 2 1))))

; The applets busybox reads without getopt, refusing what they do not take with
; the usage text alone.
(def %cu-usage-only (list "factor" "dd" "whoami" "logname" "nice" "free"))

; The applets busybox reads with getopt and no long options: `--NAME` is the
; option `-`, refused as that.
(def %cu-short-only (list "head" "hexdump" "hd" "unzip" "dc"))

; What is wrong with TOK, in musl getopt's words, which busybox's are.  A value
; option with nothing after it is `option requires an argument: C`; in a short
; cluster, read left to right as getopt reads one, the first letter APPLET does
; not declare is `unrecognized option: C`; a long option is named without its
; dashes.
(def %cu-refusal
  (fn (_ applet tok)
    (def spec (cu-spec-of applet))
    (def flags (if (null? spec) () (first spec)))
    (def values (if (null? spec) () (first (rest spec))))
    (def end (byte-len tok))
    (def go
      (fn (self i)
        (let ((opt (string-append "-" (substring tok i (+ i 1)))))
          (match
            ((>= i end) (string-append "unrecognized option: " (substring tok 1 end)))
            ((cu-member-s? opt values)
              (string-append "option requires an argument: " (substring tok i (+ i 1))))
            ((cu-member-s? opt flags) (self (+ i 1)))
            (#t (string-append "unrecognized option: " (substring tok i (+ i 1))))))))
    (match
      ; find reads its expression itself, and names the word whole
      ((string=? applet "find") (string-append "unrecognized: " tok))
      ((not (if (> end 2) (= (byte-at tok 1) 45) #f)) (go 1))
      ((cu-member-s? applet %cu-short-only) "unrecognized option: -")
      ((cu-member-s? tok values)
        (string-append "option requires an argument: " (substring tok 2 end)))
      (#t (string-append "unrecognized option: " (substring tok 2 end))))))

; Too few operands, in GNU's words: none at all is `missing operand`, and some
; is `missing operand after 'LAST'`, LAST the last of them.  GNU follows either
; with a line pointing at --help, which no applet here has.  Answers 1.  An
; applet asks before it takes an operand: the first of an empty list is a crash,
; not an error a guard could catch.
(def cu-missing-operand
  (fn (_ applet ops)
    (do (file-write 2
          (string-concat
            (if (null? ops) (list applet ": missing operand\n")
              (list applet ": missing operand after '" (cu-last ops) "'\n"))))
        1)))

; Too few file operands for an applet that copies or moves them, in GNU's
; words: `missing file operand` with none, and `missing destination file
; operand after 'OP'` with the one.  Answers 1.
(def cu-missing-file-operand
  (fn (_ applet ops)
    (do (file-write 2
          (string-concat
            (if (null? ops) (list applet ": missing file operand\n")
              (list applet ": missing destination file operand after '"
                    (first ops) "'\n"))))
        1)))

; An operand past the last an applet takes, in GNU's words: `extra operand
; 'OP'`, OP the first of them.  Answers 1.
(def cu-extra-operand
  (fn (_ applet op)
    (do (file-write 2 (string-concat (list applet ": extra operand '" op "'\n")))
        1)))

; THUNK's answer where OPS number LO to HI, HI nil for no limit; otherwise the
; refusal, in GNU's words: too few is cu-missing-operand's, and too many
; names the first past HI.
(def cu-operands
  (fn (_ applet ops lo hi thunk)
    (let ((n (length ops)))
      (match
        ((< n lo) (cu-missing-operand applet ops))
        ((if (null? hi) #f (> n hi)) (cu-extra-operand applet (cu-nth hi ops)))
        (#t (thunk))))))

(def cu-run
  (fn (_ argv input)
    (if (null? argv)
      (do (file-write 2 "usage: coreutils APPLET [args]...\n") 2)
      (let ((h (cu-find-applet (first argv))))
        (if (null? h)
          (do (file-write 2
                (string-append "coreutils: no such applet: "
                  (string-append (first argv) "\n")))
              2)
          (cu-dispatch h (first argv) (rest argv) (cu-string-stdin input)))))))

; An applet's stdin is a thunk.  Called bare it answers the whole text; called
; with (lit chunk) it answers the next piece not yet handed out, empty at the
; end, for an applet that reads as it goes: a run (cu/prims.x), which carries
; its NULs, or a string, which holds none.  An applet takes one or the other.
; From a string, the one piece is the string.
(def cu-string-stdin
  (fn (_ input)
    (def given (list #f))
    (fn (_ . how)
      (if (null? how) input
        (if (first given) ""
          (do (set-first! given #t) input))))))

; One applet run, for cu-run and cu-main alike: its arguments checked against
; its row, and the applet handed them -- only its operands where it declares no
; flags -- or the first option it does not know refused.
(def cu-dispatch
  (fn (_ h applet args stdin-thunk)
    (let ((help (%cu-help applet args)))
      (match
        ((not (null? help)) help)
        ((%cu-inetd-idle? applet) (cu-usage applet))
        (#t (let ((o (cu-opts applet args)))
              (if (null? (Opts unknown o))
                (h Applets (if (%cu-flagless? applet) (Opts operands o) args) stdin-thunk)
                (cu-refuse-option applet (Opts unknown o)))))))))

; An inetd service whose row says so (`inetd`) and whose stdin is not a socket:
; busybox's tftpd asks before it reads its options, and shows its usage
(def %cu-inetd-idle?
  (fn (_ applet)
    (let ((spec (cu-spec-of applet)))
      (if (if (null? spec) #t (null? (rest (rest spec)))) #f
        (if (eq? (first (rest (rest spec))) (lit inetd)) (null? (net-stdin-socket)) #f)))))

(def %cu-cli-engine-flag?
  (fn (_ s)
    (match
      ((string=? s "--quiet")    #t)
      ((string=? s "--batch")    #t)
      ((string=? s "--no-color") #t)
      (#t (string=? s "--verbose")))))

(def cu-argv
  (fn (_ raw)
    (def ops
      (filter (fn (_ a) (not (%cu-cli-engine-flag? a)))
        (if (pair? raw) (rest raw) ())))
    (if (if (pair? ops) (string=? (first ops) "--") #f)
      (rest ops)
      ops)))

(def cu-main
  (fn (_ raw-args)
    (def argv (cu-argv raw-args))
    (def cache (list ()))
    (def stdin-thunk
      (fn (_ . how)
        (match
          ((not (null? how)) (cu-stdin-chunk!))
          ((null? (first cache))
            (do (set-first! cache (list (cu-stdin!)))
                (first (first cache))))
          (#t (first (first cache))))))
    (if (null? argv)
      (sys-exit (cu-run argv ""))
      (let ((h (cu-find-applet (first argv))))
        (if (null? h)
          (sys-exit (cu-run argv ""))
          (sys-exit (cu-dispatch h (first argv) (rest argv) stdin-thunk)))))))

(provide cu/cli cu-argv cu-dispatch cu-extra-operand cu-find-applet
  cu-last-given cu-last-valued cu-main cu-missing-file-operand
  cu-missing-operand cu-operands cu-opts cu-refuse-option cu-run cu-spec-of
  cu-string-stdin cu-usage)

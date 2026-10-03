; # x-coreutils -- the small tools, as applets
;
; ## cu/getopt.x -- getopt
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's getopt (util-linux/getopt.c): PARAMS parsed against OPTSTRING (-o,
; or the first operand) and the long options of -l, and put out again in a
; form a shell can take apart with `eval set --`: each option on its own,
; each argument quoted, then `--` and the operands.  The parse is libc's
; getopt_long, and the one busybox is measured against is musl's, so this is
; musl's: operands moved after the options unless OPTSTRING starts with + (stop
; at the first) or - (each in its place), a long option by any unique prefix,
; -a's long options after a single dash, and musl's words for what it will
; not take.  An error is said under -n's name and the status is 1, the rest
; still put out.
;
; Where a short option's argument is missing, musl reads past the end of the
; arguments and busybox puts out the environment as operands; here the
; operands end there.

; --- quoting ---------------------------------------------------------------------

; ARG quoted for the shell: in single quotes, a quote as '\''; for tcsh a
; newline as \n and a ! or blank backslashed outside the quotes too
(def %go-quote
  (fn (_ arg tcsh)
    (def n (byte-len arg))
    (def go
      (fn (self i acc)
        (if (>= i n) (string-concat (reverse (pair "'" acc)))
          (let ((c (byte-at arg i)))
            (self (+ i 1)
              (pair (match
                      ((if tcsh (= c #\newline) #f) "\\n")
                      ((if (= c #\') #t (if tcsh (if (= c #\!) #t (%ts-space? c)) #f))
                        (string-concat (list "'\\" (bytes->str (list c)) "'")))
                      (#t (bytes->str (list c))))
                    acc))))))
    (go 0 (list "'"))))

; --- the parse -----------------------------------------------------------------------

; The run's settings, in a vector: OPTSTRING's options (its + or - gone), the
; mode (+, - or permute), whether a leading : silences the messages, the long
; options as (NAME . HAS-ARG) -- 0 none, 1 required, 2 optional -- -a, the
; name errors are said under, whether they are said, and the quoting.
(def %go-body (fn (_ g) (vec-ref g 0)))
(def %go-mode (fn (_ g) (vec-ref g 1)))
(def %go-colon (fn (_ g) (vec-ref g 2)))
(def %go-longs (fn (_ g) (vec-ref g 3)))
(def %go-alt (fn (_ g) (vec-ref g 4)))
(def %go-name (fn (_ g) (vec-ref g 5)))
(def %go-say? (fn (_ g) (vec-ref g 6)))
(def %go-quoting (fn (_ g) (vec-ref g 7)))

; ARG as the output gives it: quoted, unless -u
(def %go-norm
  (fn (_ g arg)
    (match
      ((eq? (%go-quoting g) (lit none)) arg)
      (#t (%go-quote arg (eq? (%go-quoting g) (lit tcsh)))))))

; a word of musl's to stderr under the run's name, unless it is quiet
(def %go-say
  (fn (_ g msg what)
    (if (%go-say? g)
      (file-write 2 (string-concat (list (%go-name g) msg what "\n")))
      ())))

; C's place in the short options: (TAKES . OPTIONAL?), or nil where it is
; not one of them -- a : never is
(def %go-short
  (fn (_ g c)
    (def body (%go-body g))
    (def n (byte-len body))
    (def at (%dp-find body 0 c))
    (if (if (< at 0) #t (= c #\:)) ()
      (let ((takes (if (< (+ at 1) n) (= (byte-at body (+ at 1)) #\:) #f)))
        (pair takes (if takes (if (< (+ at 2) n) (= (byte-at body (+ at 2)) #\:) #f) #f))))))

; A cluster TOKEN of short options, its later ones MORE: answers (OUT CODE .
; MORE-AFTER), or (OUT CODE . stop) where a missing argument ends the parse.
(def %go-cluster
  (fn (_ g token more)
    (def n (byte-len token))
    (def go
      (fn (self i out code)
        (if (>= i n) (list out code more)
          (let ((c (byte-at token i)))
            (let ((s (%go-short g c)) (opt (string-append " -" (bytes->str (list c)))))
              (match
                ((null? s)
                  (do (if (%go-colon g) () (%go-say g ": unrecognized option: " (bytes->str (list c))))
                      (self (+ i 1) out 1)))
                ((not (first s)) (self (+ i 1) (pair opt out) code))
                ; an argument: what is left of the cluster, else the next word
                ; unless it is only optional
                ((< (+ i 1) n)
                  (list (pair (string-append opt (string-append " " (%go-norm g (substring token (+ i 1) n)))) out)
                        code more))
                ((rest s) (list (pair (string-append opt " ''") out) code more))
                ((null? more)
                  (do (if (%go-colon g) () (%go-say g ": option requires an argument: " (bytes->str (list c))))
                      (list out 1 (lit stop))))
                (#t (list (pair (string-append opt (string-append " " (%go-norm g (first more)))) out)
                          code (rest more)))))))))
    (go 1 () 0)))

; The long option TOKEN names, from START, by musl's getopt_long: (I . AT),
; I the option, AT where its name ended in TOKEN -- or (COUNT . nil), how many
; it was a prefix of where none was it.
(def %go-long-match
  (fn (_ g token start)
    (def n (byte-len token))
    (def scan
      (fn (self longs i cnt found)
        (if (null? longs) (if (= cnt 1) found (pair cnt ()))
          (let ((name (first (first longs))))
            (def walk
              (fn (self2 p q)
                (if (if (< p n) (if (not (= (byte-at token p) #\=))
                                  (if (< q (byte-len name)) (= (byte-at token p) (byte-at name q)) #f) #f) #f)
                  (self2 (+ p 1) (+ q 1))
                  (pair p q))))
            (let ((w (walk start 0)))
              (match
                ((if (< (first w) n) (not (= (byte-at token (first w)) #\=)) #f)
                  (self (rest longs) (+ i 1) cnt found))
                ((= (rest w) (byte-len name)) (pair i (first w)))
                (#t (self (rest longs) (+ i 1) (+ cnt 1) (pair i (first w))))))))))
    (scan (%go-longs g) 0 0 ())))

; A long option in TOKEN: (OUT CODE . MORE-AFTER), or nil where it is to be
; read as short options instead (-a's single dash, and no one long option)
(def %go-long
  (fn (_ g token more)
    (def dashes (if (if (> (byte-len token) 1) (= (byte-at token 1) #\-) #f) 2 1))
    (def m (%go-long-match g token dashes))
    (def one (if (pair? m) (if (null? (rest m)) #f #t) #f))
    ; under -a, a name of one character that is also a short option is that
    (def short-too
      (if (if one (= dashes 1) #f)
        (if (= (- (rest m) dashes) 1) (not (null? (%go-short g (byte-at token 1)))) #f) #f))
    (match
      ((if one (not short-too) #f)
        (let ((opt (%cu-nth (first m) (%go-longs g))) (at (rest m)))
          (let ((name (first opt)) (has (rest opt)) (eq (< at (byte-len token))))
            (match
              ((if eq (= has 0) #f)
                (do (if (%go-colon g) () (%go-say g ": option does not take an argument: " name))
                    (list () 1 more)))
              (eq (list (list (string-concat (list " --" name " " (%go-norm g (substring token (+ at 1) (byte-len token))))))
                        0 more))
              ((= has 1)
                (if (null? more)
                  (do (if (%go-colon g) () (%go-say g ": option requires an argument: " name))
                      (list () 1 more))
                  (list (list (string-concat (list " --" name " " (%go-norm g (first more))))) 0 (rest more))))
              ((= has 2) (list (list (string-concat (list " --" name " ''"))) 0 more))
              (#t (list (list (string-append " --" name)) 0 more))))))
      ((= dashes 2)
        (do (if (%go-colon g) ()
              (%go-say g (if (if (pair? m) (> (first m) 0) #f) ": option is ambiguous: " ": unrecognized option: ")
                (substring token 2 (byte-len token))))
            (list () 1 more)))
      (#t ()))))

; is TOKEN an option: a dash and something after it
(def %go-option? (fn (_ t) (if (> (byte-len t) 1) (= (byte-at t 0) #\-) #f)))

; PARAMS parsed: (OUT CODE OPERANDS), OUT newest first
(def %go-parse
  (fn (_ g params)
    (def longs? (pair? (%go-longs g)))
    (def go
      (fn (self args skipped out code)
        (if (null? args) (list out code (reverse skipped))
          (let ((a (first args)))
            (match
              ((not (%go-option? a))
                (match
                  ((eq? (%go-mode g) (lit stop)) (list out code (append (reverse skipped) args)))
                  ((eq? (%go-mode g) (lit inorder))
                    (self (rest args) skipped (pair (string-append " " (%go-norm g a)) out) code))
                  (#t (self (rest args) (pair a skipped) out code))))
              ((string=? a "--") (list out code (append (reverse skipped) (rest args))))
              (#t
                (let ((r (if (if longs? (if (%go-alt g) #t (if (> (byte-len a) 2) (= (byte-at a 1) #\-) #f)) #f)
                           (%go-long g a (rest args)) ())))
                  (let ((r2 (if (null? r) (%go-cluster g a (rest args)) r)))
                    (if (eq? (%cu-nth 2 r2) (lit stop))
                      (list (append (first r2) out) 1 ())
                      (self (%cu-nth 2 r2) skipped (append (first r2) out)
                        (if (= (%cu-nth 1 r2) 0) code 1)))))))))))
    (go params () () 0)))

; --- the applet -------------------------------------------------------------------

; -l's words: names split on commas and blanks, a trailing : for a required
; argument and :: for an optional one; answers the list, or nil once a name
; is empty
(def %go-add-longs
  (fn (_ text acc)
    (def words (filter (fn (_ w) (> (byte-len w) 0))
                 (%cu-split-on-any text ", \t\n")))
    (def one
      (fn (_ w)
        (def n (byte-len w))
        (match
          ((if (> n 1) (string=? (substring w (- n 2) n) "::") #f) (pair (substring w 0 (- n 2)) 2))
          ((= (byte-at w (- n 1)) #\:) (pair (substring w 0 (- n 1)) 1))
          (#t (pair w 0)))))
    (let ((longs (map one words)))
      (if (pair? (filter (fn (_ l) (= (byte-len (first l)) 0)) longs)) ()
        (append acc longs)))))

; S split at each byte of SEPS, the empty pieces kept
(def %cu-split-on-any
  (fn (_ s seps)
    (def n (byte-len s))
    (def go
      (fn (self i start acc)
        (match
          ((>= i n) (reverse (pair (substring s start n) acc)))
          ((%dp-in? (byte-at s i) seps) (self (+ i 1) (+ i 1) (pair (substring s start i) acc)))
          (#t (self (+ i 1) start acc)))))
    (go 0 0 ())))

; the settings for OPTSTRING with the rest given
(def %go-settings
  (fn (_ optstr longs alt name say quoting)
    (def lead (if (> (byte-len optstr) 0) (byte-at optstr 0) 0))
    (def body (if (if (= lead #\+) #t (= lead #\-)) (substring optstr 1 (byte-len optstr)) optstr))
    (vec-build 8
      (fn (_ i)
        (match
          ((= i 0) body)
          ((= i 1) (match ((= lead #\+) (lit stop)) ((= lead #\-) (lit inorder)) (#t (lit permute))))
          ((= i 2) (if (> (byte-len body) 0) (= (byte-at body 0) #\:) #f))
          ((= i 3) longs)
          ((= i 4) alt)
          ((= i 5) name)
          ((= i 6) say)
          (#t quoting))))))

; the parse put out: the options, `--` and the operands; answers its code
(def %go-output
  (fn (_ g params quiet)
    (let ((r (%go-parse g params)))
      (do (if quiet ()
            (file-write 1
              (string-concat
                (append (reverse (first r))
                  (pair " --"
                    (append (map (fn (_ a) (string-append " " (%go-norm g a))) (%cu-nth 2 r))
                            (list "\n")))))))
          (%cu-nth 1 r)))))

; getopt [OPTIONS] [--] OPTSTRING PARAMS
(def %cu-getopt
  (fn (_ argv stdin-thunk)
    (def compatible (not (null? (sys-getenv "GETOPT_COMPATIBLE"))))
    (match
      ((null? argv)
        (if compatible (do (file-write 1 " --\n") 0)
          (do (file-write 2 "getopt: missing optstring argument\n") 1)))
      ; the old form: OPTSTRING first, no quoting
      ((if compatible #t (not (if (> (byte-len (first argv)) 0) (= (byte-at (first argv) 0) #\-) #f)))
        (let ((s (first argv)))
          (%go-output
            (%go-settings (substring s (%dp-skip-in s 0 "-+") (byte-len s)) () #f "getopt" #t (lit none))
            (rest argv) #f)))
      (#t (%go-main argv)))))

(def %go-main
  (fn (_ argv)
    (def o (%cu-opts "getopt" argv))
    (def on (fn (_ a b) (if (Opts on? o a) #t (Opts on? o b))))
    (def val (fn (_ a b) (let ((v (Opts value o a))) (if (null? v) (Opts value o b) v))))
    (def ops (Opts operands o))
    (def shell (val "-s" "--shell"))
    (def tcsh (if (null? shell) #f (%cu-member-s? shell (list "tcsh" "csh"))))
    (def longs
      (let ((go (fn (self ls acc)
                  (if (null? ls) acc
                    (let ((r (%go-add-longs (first ls) acc)))
                      (if (null? r) (lit empty) (self (rest ls) r)))))))
        (go (append (Opts values o "-l") (Opts values o "--longoptions")) ())))
    (def optstr (val "-o" "--options"))
    (do (if (if (null? shell) #f (not (%cu-member-s? shell (list "bash" "sh" "tcsh" "csh"))))
          (file-write 2 (string-concat (list "getopt: unknown shell '" shell "', assuming bash\n")))
          ())
        (match
          ((eq? longs (lit empty)) (do (file-write 2 "getopt: empty long option specified\n") 1))
          ((on "-T" "--test") 4)
          ((if (null? optstr) (null? ops) #f)
            (do (file-write 2 "getopt: missing optstring argument\n") 1))
          (#t
            (%go-output
              (%go-settings (if (null? optstr) (first ops) optstr) longs (on "-a" "--alternative")
                (let ((n (val "-n" "--name"))) (if (null? n) "getopt" n))
                (not (on "-q" "--quiet"))
                (match ((on "-u" "--unquoted") (lit none)) (tcsh (lit tcsh)) (#t (lit sh))))
              (if (null? optstr) (rest ops) ops)
              (on "-Q" "--quiet-output")))))))

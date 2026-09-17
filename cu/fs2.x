; # x-coreutils -- the small tools, as applets
;
; ## cu/fs2.x -- the busybox expansion, filesystem half
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; touch ls pwd mv rmdir install mktemp cmp.

; touch: utimes(2) on a path that exists, an empty file when it does not. It
; bumps the stamp through the door x-lang PR #607 opened, rather than rewriting
; the bytes.
; touch: every operand gets the time asked for, created first unless -c.  That
; time is now; or -d's date, read the way date reads one (so as UTC, the
; timezone divergence cu/date.x records); or -t's [[CC]YY]MMDDhhmm[.ss]; or the
; two times of -r's file.  -t names a time of its own, so it conflicts with
; -d and with -r.  -r with -d takes -d's time: only an absolute -d is read
; here, and an absolute date has no base to be relative to.

; -t's stamp as unix seconds, or nil when it does not read as one.  Two year
; digits pivot at 69 as POSIX has it (69-99 are 19xx, 00-68 20xx), no year
; means this one, and every field must name a real moment: February 30th is
; refused, and a second of 60 is taken and rolls into the next minute.
(def %cu-touch-stamp
  (fn (_ s)
    (def end (byte-len s))
    (def digit? (fn (_ i) (let ((b (byte-at s i))) (if (>= b 48) (<= b 57) #f))))
    (def digits?
      (fn (_ from to)
        (let ((go (fn (self i) (if (>= i to) #t (if (digit? i) (self (+ i 1)) #f)))))
          (if (< from to) (go from) #f))))
    (def num
      (fn (_ from to)
        (let ((go (fn (self i n)
                    (if (>= i to) n (self (+ i 1) (+ (* n 10) (- (byte-at s i) 48)))))))
          (go from 0))))
    (def dot
      (let ((go (fn (self i) (match ((>= i end) end) ((= (byte-at s i) 46) i) (#t (self (+ i 1)))))))
        (go 0)))
    (def shaped?
      (match
        ((not (digits? 0 dot)) #f)
        ((not (match ((= dot 8) #t) ((= dot 10) #t) (#t (= dot 12)))) #f)
        ((= dot end) #t)
        (#t (if (= (- end dot) 3) (digits? (+ dot 1) end) #f))))
    (if (not shaped?) ()
      (let ((lead (- dot 8)))
        (def year
          (match
            ((= lead 4) (num 0 4))
            ((= lead 2) (let ((yy (num 0 2))) (if (>= yy 69) (+ 1900 yy) (+ 2000 yy))))
            (#t (Assoc get (lit year) (Date now)))))
        (def month (num lead (+ lead 2)))
        (def day (num (+ lead 2) (+ lead 4)))
        (def hour (num (+ lead 4) (+ lead 6)))
        (def minute (num (+ lead 6) (+ lead 8)))
        (def second (if (= dot end) 0 (num (+ dot 1) end)))
        (%cu-date-moment year month day hour minute second 60)))))

(def %cu-touch
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "touch" argv))
    (def c? (Opts on? o "-c"))
    (def ops (Opts operands o))
    (def rfile (Opts value o "-r"))
    (def dspec (Opts value o "-d"))
    (def tspec (Opts value o "-t"))
    (def ref-st (if (null? rfile) () (file-stat-full rfile)))
    (def dsecs (if (null? dspec) () (%cu-date-of dspec ())))
    (def tsecs (if (null? tspec) () (%cu-touch-stamp tspec)))
    (def refused
      (match
        ((if (null? tspec) #f (if (null? dspec) (not (null? rfile)) #t))
          "touch: cannot specify times from more than one source\n")
        ((if (null? rfile) #f (null? ref-st))
          (string-concat
            (list "touch: failed to get attributes of '" rfile "': "
                  (if (file-exists? rfile) "Permission denied" "No such file or directory")
                  "\n")))
        ((if (null? dspec) #f (null? dsecs))
          (string-concat (list "touch: invalid date format '" dspec "'\n")))
        ((if (null? tspec) #f (null? tsecs))
          (string-concat (list "touch: invalid date format '" tspec "'\n")))
        (#t ())))
    ; (ATIME . MTIME), or nil for the clock
    (def times
      (match
        ((not (null? dsecs)) (pair dsecs dsecs))
        ((not (null? tsecs)) (pair tsecs tsecs))
        ((not (null? ref-st))
          (pair (%cu-stat-get ref-st (lit atime)) (%cu-stat-get ref-st (lit mtime))))
        (#t ())))
    (def stamp
      (fn (_ path)
        (if (null? times) (do (file-utimes path) 0)
          (if (< (file-set-times path (first times) (rest times)) 0)
            (do (file-write 2 (string-concat (list "touch: setting times of '" path "' failed\n")))
                1)
            0))))
    (def go
      (fn (self os st)
        (if (null? os) st
          (let ((path (first os)))
            (match
              ((file-exists? path) (self (rest os) (%cu-max-status st (stamp path))))
              (c? (self (rest os) st))
              (#t (do (file-write-all path "")
                      (self (rest os)
                        (%cu-max-status st (if (null? times) 0 (stamp path)))))))))))
    (match
      ((not (null? refused)) (do (file-write 2 refused) 1))
      ((null? ops) (do (file-write 2 "touch: missing operand\n") 1))
      (#t (go ops 0)))))

(def %cu-max-status (fn (_ a b) (if (> a b) a b)))

; ls lives in cu/ls.x: the busybox option set is a module's worth.

; pwd: the physical directory, as getcwd has it, by default and under -P.
; -L answers $PWD when that still names the working directory -- the path
; a shell reached it by, links unresolved -- and the physical one when it
; does not.  busybox defaults to -L; the physical default here is GNU's,
; and what this applet always printed.
(def %cu-pwd
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "pwd" argv))
    (def here (sys-getcwd))
    (def shown
      (let ((p (sys-getenv "PWD")))
        (match
          ((not (Opts on? o "-L")) here)
          ((null? p) here)
          ((= (byte-len p) 0) here)
          ((not (= (byte-at p 0) 47)) here)
          ((string=? (%cu-realpath-of p) here) p)
          (#t here))))
    (do (display (string-append shown "\n")) 0)))

; mv moved to cu/fs.x with busybox's option set (-f -i -n -T).

; rmdir moved to cu/fs.x, which gives it -p.

; install: -d makes directories (parents included); the copy form
; accepts and IGNORES -c and -m MODE -- there is no chmod door yet,
; the recorded divergence
; install: -d makes directories; otherwise it copies, with -D creating
; the destination's parents, -m the mode, -o/-g the ownership, -p the
; timestamps, and -t naming a directory to install into.  -s would
; strip a binary and there is no strip to call, so it is not claimed.
(def %cu-install
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "install" argv))
    (def ops (Opts operands o))
    (def mode (let ((m (Opts value o "-m")))
                (if (null? m) () (%cu-octal->int m))))
    (def owner (Opts value o "-o"))
    (def group (Opts value o "-g"))
    (def into (Opts value o "-t"))
    (def finish!
      (fn (_ target src)
        (do (if (null? mode) () (file-chmod target mode))
            (if (if (null? owner) (null? group) #f) ()
              (file-chown target
                (if (null? owner) (- 0 1) (%cu-num-prefix owner))
                (if (null? group) (- 0 1) (%cu-num-prefix group))))
            (if (Opts on? o "-p") (file-utimes target) ()))))
    (if (Opts on? o "-d")
      (let ((go (fn (self ds)
                  (if (null? ds) 0
                    (do (%cu-mkdir-p! (first ds))
                        (finish! (first ds) ())
                        (self (rest ds)))))))
        (go ops))
      (let ((dst (if (null? into)
                   (if (null? ops) () (%cu-last ops))
                   into)))
        (def srcs (if (null? into)
                    (if (null? ops) () (%cu-drop-last ops))
                    ops))
        (if (null? srcs)
          (do (file-write 2
                "install: usage: install [-cDp] [-m M] [-o U] [-g G] SRC... DST | -t DIR SRC... | -d DIR...\n")
              1)
          (let ((go (fn (self ss st)
                      (if (null? ss) st
                        (let ((target
                                (if (file-dir? dst)
                                  (%cu-path-join dst (%cu-base-of (first ss)))
                                  dst)))
                          (do (if (Opts on? o "-D")
                                (%cu-mkdir-p! (%cu-dirname-of target)) ())
                              (file-copy (first ss) target)
                              (finish! target (first ss))
                              (self (rest ss) st)))))))
            (go srcs 0)))))))

(def %cu-base-of
  (fn (_ p)
    (def slash
      (let ((go (fn (self i last)
                  (if (>= i (byte-len p)) last
                    (self (+ i 1) (if (= (byte-at p i) 47) i last))))))
        (go 0 (- 0 1))))
    (if (< slash 0) p (substring p (+ slash 1) (byte-len p)))))

; shared with mkdir -p
(def %cu-mkdir-p!
  (fn (_ path)
    (def end (byte-len path))
    (def go
      (fn (self i)
        (if (>= i end)
          (if (file-exists? path) () (file-mkdir path))
          (if (if (= (byte-at path i) 47) (> i 0) #f)
            (do (let ((pre (substring path 0 i)))
                  (if (file-exists? pre) () (file-mkdir pre)))
                (self (+ i 1)))
            (self (+ i 1))))))
    (go 0)))

; mktemp: TEMPLATE with trailing Xs (default /tmp/tmp.XXXXXX), O_EXCL
; loop, alnum from the PRNG seeded by the clock
; -d makes a directory, -p DIR / -t place the template under a
; directory, -u prints a name without creating it, -q keeps quiet
(def %cu-mktemp
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "mktemp" argv))
    (def ops (Opts operands o))
    (def dir? (Opts on? o "-d"))
    (def dry? (Opts on? o "-u"))
    (def quiet? (Opts on? o "-q"))
    (def base (if (null? ops) "tmp.XXXXXX" (first ops)))
    (def into
      (let ((p (Opts value o "-p")))
        (if (not (null? p)) p
          (if (Opts on? o "-t")
            (let ((e (sys-getenv "TMPDIR"))) (if (null? e) "/tmp" e))
            ()))))
    (def template
      (if (null? into) (if (null? ops) "/tmp/tmp.XXXXXX" base)
        (%cu-path-join into (%cu-basename-of base))))
    (def end (byte-len template))
    (def xs
      (let ((go (fn (self i)
                  (if (<= i 0) 0
                    (if (= (byte-at template (- i 1)) 88)   ; X
                      (+ 1 (self (- i 1)))
                      0)))))
        (go end)))
    (if (= xs 0)
      (do (if quiet? () (file-write 2 "mktemp: template needs trailing Xs\n")) 1)
      (let ((stem (substring template 0 (- end xs))))
        (def rng (rng-make (date-now-unix)))
        (def alnum
          (fn (_ k)
            (if (< k 10) (+ 48 k)
              (if (< k 36) (+ 87 (- k 10)) (+ 29 k)))))
        (def try
          (fn (self n)
            (if (= n 0)
              (do (if quiet? () (file-write 2 "mktemp: exhausted attempts\n")) 1)
              (let ((suffix
                      (let ((go (fn (self2 k acc)
                                  (if (= k 0) (list->string acc)
                                    (self2 (- k 1)
                                      (pair (integer->char
                                              (alnum (rng-int rng 62)))
                                        acc))))))
                        (go xs ()))))
                (def path (string-append stem suffix))
                (if dry?
                  (do (display (string-append path "\n")) 0)
                  (if dir?
                    (if (file-exists? path) (self (- n 1))
                      (do (file-mkdir path)
                          (display (string-append path "\n")) 0))
                    (let ((fd (file-open-excl path)))
                      (if (if (number? fd) (>= fd 0) #f)
                        (do (file-close fd)
                            (display (string-append path "\n"))
                            0)
                        (self (- n 1))))))))))
        (try 16)))))

; cmp: first differing byte, 1-based, with its line; -s is silent
; -l lists every differing byte and keeps going; without it cmp stops at the
; first difference and names where it was. -n bounds how far either is read.
(def %cu-cmp
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "cmp" argv))
    (def s? (Opts on? o "-s"))
    (def list? (Opts on? o "-l"))
    (def ops (Opts operands o))
    (def a (if (string=? (first ops) "-") (stdin-thunk)
             (file-read-all (first ops))))
    (def b (if (string=? (first (rest ops)) "-") (stdin-thunk)
             (file-read-all (first (rest ops)))))
    (def cap
      (let ((v (Opts value o "-n")))
        (if (null? v) (- 0 1) (%cu-num-prefix v))))
    (def clamp
      (fn (_ n)
        (match ((< cap 0) n) ((> n cap) cap) (#t n))))
    (def la (clamp (byte-len a)))
    (def lb (clamp (byte-len b)))
    (def eof
      (fn (_ i)
        (do (if s? ()
              (file-write 2
                (string-append "cmp: EOF on "
                  (string-append
                    (if (>= i la) (first ops) (first (rest ops))) "\n"))))
            1)))
    ; -l reports the byte values in octal, which is what cmp prints.
    (def listing
      (fn (self i st)
        (match
          ((if (>= i la) (>= i lb) #f) st)
          ((if (>= i la) #t (>= i lb)) (eof i))
          ((= (byte-at a i) (byte-at b i)) (self (+ i 1) st))
          (#t
            (do (if s? ()
                  (display
                    (string-concat
                      ; width 6, which is what the system cmp prints
                      (list (%cu-pad-left (%cu-int->str (+ i 1)) 6) " "
                            (%cu-oct->str (byte-at a i)) " "
                            (%cu-oct->str (byte-at b i)) "\n"))))
                (self (+ i 1) 1))))))
    (def go
      (fn (self i line)
        (match
          ((if (>= i la) (>= i lb) #f) 0)
          ((if (>= i la) #t (>= i lb)) (eof i))
          ((= (byte-at a i) (byte-at b i))
            (self (+ i 1) (if (= (byte-at a i) 10) (+ line 1) line)))
          (#t
            (do (if s? ()
                  (display
                    (string-concat
                      (list (first ops) " " (first (rest ops))
                            " differ: char " (%cu-int->str (+ i 1))
                            ", line " (%cu-int->str line) "\n"))))
                1)))))
    (if list? (listing 0 0) (go 0 1))))


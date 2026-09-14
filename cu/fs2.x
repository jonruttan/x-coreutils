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
(def %cu-touch
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "touch" argv))
    (def c? (Opts on? o "-c"))
    (def ops (Opts operands o))
    (def go
      (fn (self os)
        (if (null? os) 0
          (do (if (file-exists? (first os))
                (file-utimes (first os))
                (if c? () (file-write-all (first os) "")))
              (self (rest os))))))
    (if (null? ops)
      (do (file-write 2 "touch: missing operand\n") 1)
      (go ops))))

; ls lives in cu/ls.x: the busybox option set is a module's worth.

(def %cu-pwd
  (fn (_ argv stdin-thunk)
    (do (display (string-append (sys-getcwd) "\n")) 0)))

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
    (def clamp (fn (_ n) (if (< cap 0) n (if (> n cap) cap n))))
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
        (if (if (>= i la) (>= i lb) #f) st
          (if (if (>= i la) #t (>= i lb)) (eof i)
            (if (= (byte-at a i) (byte-at b i))
              (self (+ i 1) st)
              (do (if s? ()
                    (display
                      (string-concat
                        ; width 6, which is what the system cmp prints
                        (list (%cu-pad-left (%cu-int->str (+ i 1)) 6) " "
                              (%cu-oct->str (byte-at a i)) " "
                              (%cu-oct->str (byte-at b i)) "\n"))))
                  (self (+ i 1) 1)))))))
    (def go
      (fn (self i line)
        (if (if (>= i la) (>= i lb) #f) 0
          (if (if (>= i la) #t (>= i lb)) (eof i)
            (if (= (byte-at a i) (byte-at b i))
              (self (+ i 1) (if (= (byte-at a i) 10) (+ line 1) line))
              (do (if s? ()
                    (display
                      (string-concat
                        (list (first ops) " " (first (rest ops))
                              " differ: char " (%cu-int->str (+ i 1))
                              ", line " (%cu-int->str line) "\n"))))
                  1))))))
    (if list? (listing 0 0) (go 0 1))))


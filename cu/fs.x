; # x-coreutils -- the small tools, as applets
;
; ## cu/fs.x -- cat cp mv rm mkdir rmdir ln, with busybox's option sets
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The tools that MOVE bytes and names around, and the options busybox
; gives them.  Two rules hold across all of them.
;
; Bytes go through file-copy, never read-all + write-all: a string's
; observable bytes end at its first NUL, so the old spelling silently
; truncated anything that was not text.
;
; An overwrite is a QUESTION when -i asks it.  There is no terminal in
; a pipeline, and GNU cp reads EOF as "no" there, so -i declines unless
; a tty answers y -- the safe reading, and the one a script gets.

; THE ONE PARSE, taken by the applet and passed down.  Every helper
; below reads `o`, the record cu/cli.x's declaration produced -- not
; argv, which it would have to re-interpret.  A value flag's argument
; is not an operand, and remembering that was what each hand-rolled
; operand filter here got to be wrong about separately.

; -i: ask, and take silence for no
(def %fs-may-clobber?
  (fn (_ o path what)
    (if (not (Opts on? o "-i")) #t
      (if (not (file-exists? path)) #t
        (do (file-write 2
              (string-concat (list what ": overwrite '" path "'? ")))
            (if (not (sys-isatty 0))
              (do (file-write 2 "\n") #f)
              (let ((answer (file-read-fd 0 8)))
                (if (= (byte-len answer) 0) #f
                  (= (byte-at answer 0) 121)))))))))            ; y

; -u: only when the source is newer than the target
(def %fs-newer?
  (fn (_ src dst)
    (if (not (file-exists? dst)) #t
      (let ((s (file-lstat-full src)) (d (file-lstat-full dst)))
        (if (null? s) #t
          (if (null? d) #t
            (> (%cu-stat-get s (lit mtime)) (%cu-stat-get d (lit mtime)))))))))

; --- cat ----------------------------------------------------------------------

; -v spells the unprintables: control as ^X, DEL as ^?, and a high byte
; as M- followed by the same rendering of its low seven bits.  -e and -t
; add the line and tab markers, and -A is all three.
(def %cat-visible
  (fn (_ b)
    (if (< b 32) (string-append "^" (%cu-b->s (+ b 64)))
      (if (= b 127) "^?"
        (if (< b 128) (%cu-b->s b)
          (string-append "M-"
            (let ((low (- b 128)))
              (if (< low 32) (string-append "^" (%cu-b->s (+ low 64)))
                (if (= low 127) "^?" (%cu-b->s low))))))))))

(def %cat-render
  (fn (_ s o)
    (def v? (if (Opts on? o "-A") #t (Opts on? o "-v")))
    (def e? (if (Opts on? o "-A") #t (Opts on? o "-e")))
    (def t? (if (Opts on? o "-A") #t (Opts on? o "-t")))
    (if (if v? #f (if e? #f (not t?))) s
      (let ((end (byte-len s)))
        (def go
          (fn (self i acc)
            (if (>= i end) (string-concat (reverse acc))
              (let ((b (byte-at s i)))
                (self (+ i 1)
                  (pair
                    (if (= b 10) (if e? "$\n" "\n")
                      (if (= b 9) (if t? "^I" "\t")
                        (if v? (%cat-visible b) (%cu-b->s b))))
                    acc))))))
        (go 0 ())))))

; -n numbers every line, -b only the non-empty ones (and -b wins)
(def %cat-number
  (fn (_ text o)
    (def b? (Opts on? o "-b"))
    (if (if b? #f (not (Opts on? o "-n"))) text
      (let ((ls (%cu-lines text)))
        (def go
          (fn (self xs n acc)
            (if (null? xs) (string-concat (reverse acc))
              (let ((blank? (= (byte-len (first xs)) 0)))
                (if (if b? blank? #f)
                  (self (rest xs) n (pair "\n" acc))
                  (self (rest xs) (+ n 1)
                    (pair (string-concat
                            (list (%cu-pad-left (%cu-int->str n) 6) "\t"
                                  (first xs) "\n"))
                      acc)))))))
        (go ls 1 ())))))

(def %cu-cat
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "cat" argv))
    (def text (%cu-gather (Opts operands o) stdin-thunk))
    ; numbering counts the SOURCE lines, so it runs before the rendering
    ; that may add a $ to each of them
    (do (display (%cat-render (%cat-number text o) o)) 0)))

; --- cp -----------------------------------------------------------------------

(def %cp-recursive? (fn (_ o)
  (if (Opts on? o "-r") #t (if (Opts on? o "-R") #t (Opts on? o "-a")))))
(def %cp-preserve? (fn (_ o)
  (if (Opts on? o "-p") #t (Opts on? o "-a"))))
; -a and -P keep a link a link; -L and -H follow one
(def %cp-deref? (fn (_ o)
  (if (Opts on? o "-L") #t
    (if (Opts on? o "-P") #f (if (Opts on? o "-a") #f #t)))))

(def %cp-preserve!
  (fn (_ src dst o)
    (if (not (%cp-preserve? o)) ()
      (let ((st (file-lstat-full src)))
        (if (null? st) ()
          (do (file-chmod dst (bit-and (%cu-stat-get st (lit mode)) 4095))
              (file-utimes dst)))))))

; one source to one full destination path
(def %cp-one
  (fn (self src dst o)
    (def st (if (%cp-deref? o) (file-stat-full src) (file-lstat-full src)))
    (if (null? st)
      (do (file-write 2
            (string-concat (list "cp: cannot stat '" src "'\n")))
          1)
      (let ((kind (%cu-stat-get st (lit kind))))
        (if (eq? kind (lit dir))
          (if (not (%cp-recursive? o))
            (do (file-write 2
                  (string-concat (list "cp: omitting directory '" src "'\n")))
                1)
            (do (if (file-exists? dst) () (file-mkdir dst))
                (let ((go (fn (self2 ns st2)
                            (if (null? ns) st2
                              (let ((r (self (%cu-path-join src (first ns))
                                         (%cu-path-join dst (first ns)) o)))
                                (self2 (rest ns) (if (> r st2) r st2)))))))
                  (let ((r (go (filter (fn (_ n) (not (%cu-dot? n)))
                                 (file-list-dir src)) 0)))
                    (do (%cp-preserve! src dst o) r)))))
          ; a file onto an existing DIRECTORY is a refusal, not a raise:
          ; -T names the destination outright, and cp will not unmake a
          ; directory to honour it
          (if (file-dir? dst)
            (do (file-write 2
                  (string-concat
                    (list "cp: cannot overwrite directory '" dst
                          "' with non-directory\n")))
                1)
          (if (not (%fs-may-clobber? o dst "cp")) 0
            (do (if (if (file-exists? dst) (Opts on? o "-f") #f)
                  (file-unlink dst) ())
                (if (eq? kind (lit link))
                  (file-symlink (file-readlink src) dst)
                  (if (Opts on? o "-l") (file-link src dst)
                    (if (Opts on? o "-s") (file-symlink src dst)
                      (file-copy src dst))))
                (%cp-preserve! src dst o)
                0))))))))

; SRC... DST: DST is a directory to copy into, unless -T says it is the
; name to write
(def %cp-target
  (fn (_ dst name o)
    (if (Opts on? o "-T") dst
      (if (file-dir? dst) (%cu-path-join dst (%cu-basename-of name)) dst))))

(def %cu-cp
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "cp" argv))
    (def ops (Opts operands o))
    (if (< (length ops) 2)
      (do (file-write 2 "cp: usage: cp [-arRPLHpfilsTu] SRC... DST\n") 1)
      (let ((dst (%cu-last ops)) (srcs (%cu-drop-last ops)))
        (if (if (> (length srcs) 1) (not (file-dir? dst)) #f)
          (do (file-write 2
                (string-concat
                  (list "cp: target '" dst "' is not a directory\n")))
              1)
          (let ((go (fn (self ss st)
                      (if (null? ss) st
                        (let ((target (%cp-target dst (first ss) o)))
                          (if (if (Opts on? o "-u")
                                (not (%fs-newer? (first ss) target)) #f)
                            (self (rest ss) st)
                            (let ((r (%cp-one (first ss) target o)))
                              (self (rest ss) (if (> r st) r st)))))))))
            (go srcs 0)))))))

; --- mv -----------------------------------------------------------------------

(def %mv-one
  (fn (_ src dst o)
    (if (if (Opts on? o "-n") (file-exists? dst) #f) 0
      (if (not (%fs-may-clobber? o dst "mv")) 0
        (let ((r (file-rename src dst)))
          (if (if (number? r) (>= r 0) #t) 0
            ; across devices rename refuses: copy, then drop the original
            (do (file-copy src dst) (file-unlink src) 0)))))))

(def %cu-mv
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "mv" argv))
    (def ops (Opts operands o))
    (if (< (length ops) 2)
      (do (file-write 2 "mv: usage: mv [-finT] SRC... DST\n") 1)
      (let ((dst (%cu-last ops)) (srcs (%cu-drop-last ops)))
        (let ((go (fn (self ss st)
                    (if (null? ss) st
                      (let ((target (%cp-target dst (first ss) o)))
                        (let ((r (%mv-one (first ss) target o)))
                          (self (rest ss) (if (> r st) r st))))))))
          (go srcs 0))))))

; --- rm -----------------------------------------------------------------------

; -r ONCE ACCEPTED AND DID NOTHING: the guard listed it, %cu-rm ignored
; it, and unlink on a directory simply failed.  It recurses now.
(def %rm-one
  (fn (self path o)
    (def kind (file-lstat-kind path))
    (if (eq? kind (lit none))
      (if (Opts on? o "-f") 0
        (do (file-write 2
              (string-concat
                (list "rm: cannot remove '" path
                      "': No such file or directory\n")))
            1))
      (if (eq? kind (lit dir))
        (if (not (%rm-recursive? o))
          (do (file-write 2
                (string-concat
                  (list "rm: cannot remove '" path "': Is a directory\n")))
              1)
          (let ((go (fn (self2 ns st)
                      (if (null? ns) st
                        (let ((r (self (%cu-path-join path (first ns)) o)))
                          (self2 (rest ns) (if (> r st) r st)))))))
            (let ((r (go (filter (fn (_ n) (not (%cu-dot? n)))
                           (file-list-dir path)) 0)))
              (do (file-rmdir path) (%rm-say path o) r))))
        (if (not (%fs-may-clobber? o path "rm")) 0
          (do (file-unlink path) (%rm-say path o) 0))))))

(def %rm-recursive? (fn (_ o)
  (if (Opts on? o "-r") #t (Opts on? o "-R"))))

(def %rm-say
  (fn (_ path o)
    (if (Opts on? o "-v")
      (display (string-concat (list "removed '" path "'\n"))) ())))

(def %cu-rm
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "rm" argv))
    (def go
      (fn (self os st)
        (if (null? os) st
          (let ((r (%rm-one (first os) o)))
            (self (rest os) (if (> r st) r st))))))
    (go (Opts operands o) 0)))

; --- mkdir, rmdir -------------------------------------------------------------

(def %cu-mkdir
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "mkdir" argv))
    (def p? (Opts on? o "-p"))
    ; -m TAKES A VALUE, so it lives in the record's values and not among
    ; the flags: asking (Opts on? o "-m") is always false.  Its presence
    ; is its value being there.
    (def m (Opts value o "-m"))
    (def mode (if (null? m) () (%cu-octal->int m)))
    (def stamp! (fn (_ path) (if (null? mode) () (file-chmod path mode))))
    (def go
      (fn (self os st)
        (if (null? os) st
          (if p?
            (do (%cu-mkdir-p! (first os)) (stamp! (first os))
                (self (rest os) st))
            (if (file-exists? (first os))
              (do (file-write 2
                    (string-concat
                      (list "mkdir: cannot create directory '" (first os)
                            "': File exists\n")))
                  (self (rest os) 1))
              (do (file-mkdir (first os)) (stamp! (first os))
                  (self (rest os) st)))))))
    (go (Opts operands o) 0)))

; -p removes each parent too, while they keep coming up empty.  File
; rmdir RAISES on a non-empty directory rather than answering a
; negative, and stopping there is the whole point of the walk.
(def %rmdir-try
  (fn (_ path) (guard (e #f) (do (file-rmdir path) #t))))

(def %rmdir-parents!
  (fn (self path)
    (let ((parent (%cu-dirname-of path)))
      (if (if (string=? parent "/") #t (string=? parent ".")) ()
        (if (%rmdir-try parent) (self parent) ())))))

(def %cu-rmdir
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "rmdir" argv))
    (def p? (Opts on? o "-p"))
    (def go
      (fn (self os st)
        (if (null? os) st
          (if (%rmdir-try (first os))
            (do (if p? (%rmdir-parents! (first os)) ())
                (self (rest os) st))
            (do (file-write 2
                  (string-concat
                    (list "rmdir: failed to remove '" (first os) "'\n")))
                (self (rest os) 1))))))
    (go (Opts operands o) 0)))

; --- ln -----------------------------------------------------------------------

(def %cu-ln
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "ln" argv))
    (def s? (Opts on? o "-s"))
    (def f? (Opts on? o "-f"))
    (def ops0 (Opts operands o))
    ; -t DIR names the directory the links go in, and then every
    ; operand is a target
    (def dir (Opts value o "-t"))
    (def ops (if (null? dir) ops0 ops0))
    (if (null? ops)
      (do (file-write 2 "ln: usage: ln [-sfnbtv] TARGET... [NAME]\n") 1)
      (let ((targets (if (null? dir)
                       (if (null? (rest ops)) ops (%cu-drop-last ops))
                       ops))
            (into (if (null? dir)
                    (if (null? (rest ops)) "." (%cu-last ops))
                    dir)))
        (def go
          (fn (self ts st)
            (if (null? ts) st
              (let ((name (if (if (null? dir) (null? (rest ops)) #f)
                            (%cu-basename-of (first ts))
                            (if (file-dir? into)
                              (%cu-path-join into (%cu-basename-of (first ts)))
                              into))))
                (do
                  ; -b keeps what it displaces, as NAME~
                  (if (if (Opts on? o "-b") (file-exists? name) #f)
                    (do (file-rename name (string-append name "~")) ()) ())
                  (if (if f? (not (eq? (file-lstat-kind name) (lit none))) #f)
                    (file-unlink name) ())
                  (if s? (file-symlink (first ts) name)
                    (file-link (first ts) name))
                  (if (Opts on? o "-v")
                    (display (string-concat
                               (list "'" name "' -> '" (first ts) "'\n"))) ())
                  (self (rest ts) st))))))
        (go targets 0)))))

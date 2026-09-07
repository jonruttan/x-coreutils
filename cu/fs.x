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

(def %fs-flag? (fn (_ argv f) (%cu-has-flag? argv f)))
(def %fs-ops (fn (_ argv) (filter (fn (_ x) (not (%cu-option-token? x))) argv)))

; -i: ask, and take silence for no
(def %fs-may-clobber?
  (fn (_ argv path what)
    (if (not (%fs-flag? argv "-i")) #t
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
  (fn (_ s argv)
    (def v? (if (%fs-flag? argv "-A") #t (%fs-flag? argv "-v")))
    (def e? (if (%fs-flag? argv "-A") #t (%fs-flag? argv "-e")))
    (def t? (if (%fs-flag? argv "-A") #t (%fs-flag? argv "-t")))
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
  (fn (_ text argv)
    (def b? (%fs-flag? argv "-b"))
    (if (if b? #f (not (%fs-flag? argv "-n"))) text
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
    (def text (%cu-gather (%fs-ops argv) stdin-thunk))
    ; numbering counts the SOURCE lines, so it runs before the rendering
    ; that may add a $ to each of them
    (do (display (%cat-render (%cat-number text argv) argv)) 0)))

; --- cp -----------------------------------------------------------------------

(def %cp-recursive? (fn (_ argv)
  (if (%fs-flag? argv "-r") #t (if (%fs-flag? argv "-R") #t (%fs-flag? argv "-a")))))
(def %cp-preserve? (fn (_ argv)
  (if (%fs-flag? argv "-p") #t (%fs-flag? argv "-a"))))
; -a and -P keep a link a link; -L and -H follow one
(def %cp-deref? (fn (_ argv)
  (if (%fs-flag? argv "-L") #t
    (if (%fs-flag? argv "-P") #f (if (%fs-flag? argv "-a") #f #t)))))

(def %cp-preserve!
  (fn (_ src dst argv)
    (if (not (%cp-preserve? argv)) ()
      (let ((st (file-lstat-full src)))
        (if (null? st) ()
          (do (file-chmod dst (bit-and (%cu-stat-get st (lit mode)) 4095))
              (file-utimes dst)))))))

; one source to one full destination path
(def %cp-one
  (fn (self src dst argv)
    (def st (if (%cp-deref? argv) (file-stat-full src) (file-lstat-full src)))
    (if (null? st)
      (do (file-write 2
            (string-concat (list "cp: cannot stat '" src "'\n")))
          1)
      (let ((kind (%cu-stat-get st (lit kind))))
        (if (eq? kind (lit dir))
          (if (not (%cp-recursive? argv))
            (do (file-write 2
                  (string-concat (list "cp: omitting directory '" src "'\n")))
                1)
            (do (if (file-exists? dst) () (file-mkdir dst))
                (let ((go (fn (self2 ns st2)
                            (if (null? ns) st2
                              (let ((r (self (%cu-path-join src (first ns))
                                         (%cu-path-join dst (first ns)) argv)))
                                (self2 (rest ns) (if (> r st2) r st2)))))))
                  (let ((r (go (filter (fn (_ n) (not (%cu-dot? n)))
                                 (file-list-dir src)) 0)))
                    (do (%cp-preserve! src dst argv) r)))))
          ; a file onto an existing DIRECTORY is a refusal, not a raise:
          ; -T names the destination outright, and cp will not unmake a
          ; directory to honour it
          (if (file-dir? dst)
            (do (file-write 2
                  (string-concat
                    (list "cp: cannot overwrite directory '" dst
                          "' with non-directory\n")))
                1)
          (if (not (%fs-may-clobber? argv dst "cp")) 0
            (do (if (if (file-exists? dst) (%fs-flag? argv "-f") #f)
                  (file-unlink dst) ())
                (if (eq? kind (lit link))
                  (file-symlink (file-readlink src) dst)
                  (if (%fs-flag? argv "-l") (file-link src dst)
                    (if (%fs-flag? argv "-s") (file-symlink src dst)
                      (file-copy src dst))))
                (%cp-preserve! src dst argv)
                0))))))))

; SRC... DST: DST is a directory to copy into, unless -T says it is the
; name to write
(def %cp-target
  (fn (_ dst name argv)
    (if (%fs-flag? argv "-T") dst
      (if (file-dir? dst) (%cu-path-join dst (%cu-basename-of name)) dst))))

(def %cu-cp
  (fn (_ argv stdin-thunk)
    (def ops (%fs-ops argv))
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
                        (let ((target (%cp-target dst (first ss) argv)))
                          (if (if (%fs-flag? argv "-u")
                                (not (%fs-newer? (first ss) target)) #f)
                            (self (rest ss) st)
                            (let ((r (%cp-one (first ss) target argv)))
                              (self (rest ss) (if (> r st) r st)))))))))
            (go srcs 0)))))))

; --- mv -----------------------------------------------------------------------

(def %mv-one
  (fn (_ src dst argv)
    (if (if (%fs-flag? argv "-n") (file-exists? dst) #f) 0
      (if (not (%fs-may-clobber? argv dst "mv")) 0
        (let ((r (file-rename src dst)))
          (if (if (number? r) (>= r 0) #t) 0
            ; across devices rename refuses: copy, then drop the original
            (do (file-copy src dst) (file-unlink src) 0)))))))

(def %cu-mv
  (fn (_ argv stdin-thunk)
    (def ops (%fs-ops argv))
    (if (< (length ops) 2)
      (do (file-write 2 "mv: usage: mv [-finT] SRC... DST\n") 1)
      (let ((dst (%cu-last ops)) (srcs (%cu-drop-last ops)))
        (let ((go (fn (self ss st)
                    (if (null? ss) st
                      (let ((target (%cp-target dst (first ss) argv)))
                        (let ((r (%mv-one (first ss) target argv)))
                          (self (rest ss) (if (> r st) r st))))))))
          (go srcs 0))))))

; --- rm -----------------------------------------------------------------------

; -r ONCE ACCEPTED AND DID NOTHING: the guard listed it, %cu-rm ignored
; it, and unlink on a directory simply failed.  It recurses now.
(def %rm-one
  (fn (self path argv)
    (def kind (file-lstat-kind path))
    (if (eq? kind (lit none))
      (if (%fs-flag? argv "-f") 0
        (do (file-write 2
              (string-concat
                (list "rm: cannot remove '" path
                      "': No such file or directory\n")))
            1))
      (if (eq? kind (lit dir))
        (if (not (%rm-recursive? argv))
          (do (file-write 2
                (string-concat
                  (list "rm: cannot remove '" path "': Is a directory\n")))
              1)
          (let ((go (fn (self2 ns st)
                      (if (null? ns) st
                        (let ((r (self (%cu-path-join path (first ns)) argv)))
                          (self2 (rest ns) (if (> r st) r st)))))))
            (let ((r (go (filter (fn (_ n) (not (%cu-dot? n)))
                           (file-list-dir path)) 0)))
              (do (file-rmdir path) (%rm-say path argv) r))))
        (if (not (%fs-may-clobber? argv path "rm")) 0
          (do (file-unlink path) (%rm-say path argv) 0))))))

(def %rm-recursive? (fn (_ argv)
  (if (%fs-flag? argv "-r") #t (%fs-flag? argv "-R"))))

(def %rm-say
  (fn (_ path argv)
    (if (%fs-flag? argv "-v")
      (display (string-concat (list "removed '" path "'\n"))) ())))

(def %cu-rm
  (fn (_ argv stdin-thunk)
    (def go
      (fn (self os st)
        (if (null? os) st
          (let ((r (%rm-one (first os) argv)))
            (self (rest os) (if (> r st) r st))))))
    (go (%fs-ops argv) 0)))

; --- mkdir, rmdir -------------------------------------------------------------

(def %cu-mkdir
  (fn (_ argv stdin-thunk)
    (def p? (%fs-flag? argv "-p"))
    (def mode (if (%fs-flag? argv "-m")
                (%cu-octal->int (%cu-flag-value argv "-m")) ()))
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
    (go (%fs-ops argv) 0)))

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
    (def p? (%fs-flag? argv "-p"))
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
    (go (%fs-ops argv) 0)))

; --- ln -----------------------------------------------------------------------

(def %cu-ln
  (fn (_ argv stdin-thunk)
    (def s? (%fs-flag? argv "-s"))
    (def f? (%fs-flag? argv "-f"))
    (def ops0 (%fs-ops argv))
    ; -t DIR names the directory the links go in, and then every
    ; operand is a target
    (def dir (if (%fs-flag? argv "-t") (%cu-flag-value argv "-t") ()))
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
                  (if (if (%fs-flag? argv "-b") (file-exists? name) #f)
                    (do (file-rename name (string-append name "~")) ()) ())
                  (if (if f? (not (eq? (file-lstat-kind name) (lit none))) #f)
                    (file-unlink name) ())
                  (if s? (file-symlink (first ts) name)
                    (file-link (first ts) name))
                  (if (%fs-flag? argv "-v")
                    (display (string-concat
                               (list "'" name "' -> '" (first ts) "'\n"))) ())
                  (self (rest ts) st))))))
        (go targets 0)))))

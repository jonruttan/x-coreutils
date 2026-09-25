; # x-coreutils -- the small tools, as applets
;
; ## cu/fs.x -- cat cp mv rm mkdir rmdir ln, with busybox's option sets
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The tools that move bytes and names around, with busybox's option sets. Two
; rules hold across all of them. Bytes go through file-copy, never
; read-all + write-all: a string's observable bytes end at its first NUL, so
; read-all would truncate anything that is not text. An overwrite is a question
; when -i asks it, and there is no terminal in a pipeline, so -i declines unless
; a tty answers y (the safe reading, and the one a script gets).

; THE ONE PARSE, taken by the applet and passed down.  Every helper
; below reads `o`, the record cu/cli.x's declaration produced -- not
; argv, which it would have to re-interpret.  A value flag's argument
; is not an operand, and remembering that was what each hand-rolled
; operand filter here got to be wrong about separately.

; A question on stderr, answered yes or no.  With no terminal to answer it the
; answer is no and the question is left standing, unended, as the tools leave
; it when their input ends.
(def %fs-ask
  (fn (_ question)
    (do (file-write 2 question)
        (if (not (sys-isatty 0)) #f
          (let ((answer (file-read-fd 0 8)))
            (if (= (byte-len answer) 0) #f
              (= (byte-at answer 0) 121)))))))                  ; y

; -i: whether an existing PATH may be written over, asked in cp's and mv's words
(def %fs-may-clobber?
  (fn (_ o path what)
    (if (not (Opts on? o "-i")) #t
      (if (not (file-exists? path)) #t
        (%fs-ask (string-concat (list what ": overwrite '" path "'? ")))))))

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
; as M- followed by the same rendering of its low seven bits.  -e adds the
; line marker and -t the tab marker, each of them spelling the unprintables
; as well -- cat's -e is -vE and its -t is -vT -- and -A is all three.
(def %cat-visible
  (fn (_ b)
    (match
      ((< b 32) (string-append "^" (%cu-b->s (+ b 64))))
      ((= b 127) "^?")
      ((< b 128) (%cu-b->s b))
      (#t
        (string-append "M-"
          (let ((low (- b 128)))
            (if (< low 32) (string-append "^" (%cu-b->s (+ low 64)))
              (if (= low 127) "^?" (%cu-b->s low)))))))))

; What -v, -e, -t and -A make of a text, from the options read once: a
; function of the text, or nil where none of them is given.  It maps each byte
; on its own, so a text rendered a piece at a time comes out the same.
(def %cat-renderer
  (fn (_ o)
    (def v? (match
              ((Opts on? o "-A") #t)
              ((Opts on? o "-v") #t)
              ((Opts on? o "-e") #t)
              (#t (Opts on? o "-t"))))
    (def e? (if (Opts on? o "-A") #t (Opts on? o "-e")))
    (def t? (if (Opts on? o "-A") #t (Opts on? o "-t")))
    ; LEFT counts down the bytes until the next sweep, across pieces: a piece
    ; as short as a line never reaches a step of its own that sweeps
    (if (if v? #f (if e? #f (not t?))) ()
      (let ((left (list (+ %cu-sweep-bytes 1))))
        (fn (_ s)
          (let ((end (byte-len s)))
            (def go
              (fn (self i acc)
                (if (>= i end) (string-concat (reverse acc))
                  (let ((b (byte-at s i)))
                    (do (if (= (& i %cu-sweep-bytes) 0) (%cu-sweep! i) ())
                      (self (+ i 1)
                        (pair
                          (match
                            ((= b 10) (if e? "$\n" "\n"))
                            ((= b 9) (if t? "^I" "\t"))
                            (v? (%cat-visible b))
                            (#t (%cu-b->s b)))
                          acc)))))))
            (let ((r (go 0 ())))
              (do (set-first! left (- (first left) end))
                  (if (> (first left) 0) ()
                    (do (set-first! left (+ %cu-sweep-bytes 1)) (%cu-sweep! 1)))
                  r))))))))

; TEXT from START on, in pieces of 4,096 bytes
(def %cat-chunks
  (fn (self text start acc)
    (let ((end (byte-len text)))
      (if (>= start end) (reverse acc)
        (let ((stop (if (> (+ start 4096) end) end (+ start 4096))))
          (self text stop (pair (substring text start stop) acc)))))))

; -n numbers every line, -b only the non-empty ones (and -b wins): the pieces
; that go out, a numbered line to a piece, made in a pass that sweeps as it
; goes.  Without either, the text goes out in pieces of 4,096 bytes, so a
; rendering holds one piece's bytes at a time rather than the whole text's.
(def %cat-number
  (fn (_ text o)
    (def b? (Opts on? o "-b"))
    (if (if b? #f (not (Opts on? o "-n"))) (%cat-chunks text 0 ())
      (let ((ls (%cu-lines text)))
        (def go
          (fn (self xs n acc)
            (if (null? xs) (reverse acc)
              (do (%cu-sweep-tick! %cu-sweep-lines)
                (if (if b? (= (byte-len (first xs)) 0) #f)
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
    (def g (%cu-gather-said (Opts operands o) stdin-thunk (%cu-says "cat") #f))
    (def render (%cat-renderer o))
    ; numbering counts the SOURCE lines, so it runs before the rendering
    ; that may add a $ to each of them.  Each is a pass of its own, and the
    ; pieces go out in a third: a pass that did all three by turns would
    ; alternate between methods, and pay for it in dispatch.
    (def pieces (%cat-number (first g) o))
    (do (%cu-put-each (if (null? render) pieces (%cu-map-swept render pieces)))
        (rest g))))

; --- cp -----------------------------------------------------------------------

(def %cp-recursive? (fn (_ o)
  (if (Opts on? o "-r") #t (if (Opts on? o "-R") #t (Opts on? o "-a")))))
(def %cp-preserve? (fn (_ o)
  (if (Opts on? o "-p") #t (Opts on? o "-a"))))
; What cp does with a symlink, from the last of -P, -H and -L given -- -a
; says -P, and takes its turn in that order too:
;
;   none   the link is copied AS a link         -P, -a
;   args   a link NAMED on the command line is followed   -H
;   all    every link is followed                         -L
;   unsaid a link named on the command line is followed, one met on a walk
;          is copied as a link -- what cp does when told nothing else
(def %cp-links
  (fn (_ o)
    (let ((v (%cu-last-given o (list "-H" "-L" "-P" "-a"))))
      (if (null? v) (lit unsaid)
        (match
          ((string=? v "-H") (lit args))
          ((string=? v "-L") (lit all))
          (#t (lit none)))))))

; TOP? says the path was named on the command line rather than met on a walk
(def %cp-deref?
  (fn (_ o top?)
    (let ((links (%cp-links o)))
      (match
        ((eq? links (lit all)) #t)
        ((eq? links (lit none)) #f)
        ((eq? links (lit args)) top?)
        ((%cp-recursive? o) #f)
        (#t top?)))))

; -p keeps the mode and the times; a link is never handed to this, since it
; has no mode of its own to set and no lutimes door to set its times through
; -- chmod and utimes would both reach THROUGH it, and through a link
; pointing nowhere they reach nothing at all
(def %cp-preserve!
  (fn (_ src dst o)
    (if (not (%cp-preserve? o)) ()
      (let ((st (file-lstat-full src)))
        (if (null? st) ()
          (do (file-chmod dst (bit-and (%cu-stat-get st (lit mode)) 4095))
              (file-utimes dst)))))))

; a name a link is about to be written to: symlink refuses one that is taken,
; where a copy would truncate it, so the old name goes first -- as cp drops it
(def %cp-clear!
  (fn (_ dst)
    (if (eq? (file-lstat-kind dst) (lit none)) () (file-unlink dst))))

; a link cp writes itself, for -s and -l: the refusal is cp's to report, in
; cp's words, rather than an error nothing catches
(def %cp-made
  (fn (_ r what src dst)
    (if (not (Err err? r)) 0
      (do (file-write 2
            (string-concat
              (list "cp: cannot create " what " '" dst "' to '" src "': "
                    (file-err-text r) "\n")))
          1))))

; one source to one full destination path; TOP? says it was named on the
; command line, which is what -H and a plain cp ask about
(def %cp-one
  (fn (self src dst o top?)
    (let ((st (file-or-err
                (fn (_) (if (%cp-deref? o top?)
                          (file-stat-wide src)
                          (file-lstat-wide src))))))
      (if (Err err? st)
        (do (file-write 2
              (string-concat
                (list "cp: cannot stat '" src "': " (file-err-text st) "\n")))
            1)
        (let ((kind (%cu-stat-get st (lit kind))))
          (match
            ((eq? kind (lit dir))
              (if (not (%cp-recursive? o))
                (do (file-write 2
                      (string-concat
                        (list "cp: omitting directory '" src "'\n")))
                    1)
                (do (if (file-exists? dst) () (file-mkdir dst))
                    (let ((r (%cu-walk-status src
                               (fn (_ n) (self (%cu-path-join src n)
                                           (%cu-path-join dst n) o #f)))))
                      (do (%cp-preserve! src dst o) r)))))
            ((file-dir? dst)
              (do (file-write 2
                    (string-concat
                      (list "cp: cannot overwrite directory '" dst
                            "' with non-directory\n")))
                  1))
            ; a question answered no is a copy not made, and cp says so in its status
            ((not (%fs-may-clobber? o dst "cp")) 1)
            (#t
              (do (if (if (file-exists? dst) (Opts on? o "-f") #f)
                    (file-unlink dst) ())
                  (%cp-write src dst o kind)))))))))

; The write itself: a link copied as a link, a link cp is asked to make with
; -s or -l, or the bytes.  Answers the status.
(def %cp-write
  (fn (_ src dst o kind)
    (match
      ; the link is written and left at that: -p has nothing it can keep of a
      ; link, and would reach through this one
      ((eq? kind (lit link))
        (let ((target (file-readlink src)))
          (do (%cp-clear! dst)
              (%cp-made (file-or-err (fn (_) (file-symlink target dst)))
                "symbolic link" target dst))))
      ((Opts on? o "-l")
        (%cp-made (file-or-err (fn (_) (file-link src dst)))
          "hard link" src dst))
      ((Opts on? o "-s")
        (%cp-made (file-or-err (fn (_) (file-symlink src dst)))
          "symbolic link" src dst))
      (#t (do (file-copy src dst) (%cp-preserve! src dst o) 0)))))

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
                            (let ((r (%cp-one (first ss) target o #t)))
                              (self (rest ss) (if (> r st) r st)))))))))
            (go srcs 0)))))))

; --- mv -----------------------------------------------------------------------

; What mv does to a destination that is there already is the last of -f, -i
; and -n given: -f moves over it, -i asks first, -n leaves it -- each taking
; over from any given before it, so `mv -i -f` moves without asking.  Told
; nothing, mv moves over it.  A question answered no leaves both names as they
; were, and mv says so in its status; -n passing one over is no failure.
(def %mv-one
  (fn (_ src dst o)
    (let ((told (%cu-last-given o (list "-f" "-i" "-n"))))
      (match
        ((not (file-exists? dst)) (%mv-move src dst))
        ((null? told) (%mv-move src dst))
        ((string=? told "-n") 0)
        ((string=? told "-i")
          (if (%fs-ask (string-concat (list "mv: overwrite '" dst "'? ")))
            (%mv-move src dst)
            1))
        (#t (%mv-move src dst))))))

(def %mv-move
  (fn (_ src dst)
    (let ((r (file-rename src dst)))
      (if (if (number? r) (>= r 0) #t) 0
        ; across devices rename refuses: copy, then drop the original
        (do (file-copy src dst) (file-unlink src) 0)))))

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

; What rm asks is the last of -f and -i given: -f asks nothing and passes
; over a path that is not there, -i asks before each removal -- and a path
; that is not there is a failure again.  A question answered no leaves the
; path where it is, and is no failure.
(def %rm-told?
  (fn (_ o flag)
    (let ((v (%cu-last-given o (list "-f" "-i"))))
      (if (null? v) #f (string=? v flag)))))

(def %rm-one
  (fn (self path o)
    (let ((st (file-or-err (fn (_) (file-lstat-wide path)))))
      (match
        ((Err err? st)
          (if (if (%rm-told? o "-f") (eq? (file-err-sym st) (lit enoent)) #f)
            0
            (%rm-cannot path (file-err-text st))))
        ((eq? (%cu-stat-get st (lit kind)) (lit dir))
          (if (%rm-recursive? o) (%rm-dir self path o st)
            (%rm-cannot path "Is a directory")))
        ((not (%rm-may? o path st)) 0)
        (#t (%rm-gone path o (file-or-err (fn (_) (file-unlink path)))
              "removed '"))))))

; A directory under -r.  -i asks first whether to go into one that holds
; anything; its entries go before it, and then it is asked about and removed.
; One whose entries could not all be removed -- or not read -- is left without
; another word, as rm leaves it; one whose entry was only declined is asked
; about, and its removal fails as not empty.
(def %rm-dir
  (fn (_ one path o st)
    (let ((names (file-or-err (fn (_) (%cu-walk-names path)))))
      (match
        ((Err err? names) (%rm-cannot path (file-err-text names)))
        ((not (%rm-may-enter? o path names)) 0)
        (#t
          (let ((r (%cu-walk-worst names
                     (fn (_ n) (one (%cu-path-join path n) o)) 0)))
            (match
              ((> r 0) r)
              ((not (%rm-may? o path st)) 0)
              (#t (%rm-gone path o (file-or-err (fn (_) (file-rmdir path)))
                    "removed directory '")))))))))

(def %rm-recursive? (fn (_ o)
  (if (Opts on? o "-r") #t (Opts on? o "-R"))))

; under -i, whether to remove PATH, asked in rm's words for what it is
(def %rm-may?
  (fn (_ o path st)
    (if (not (%rm-told? o "-i")) #t
      (%fs-ask
        (string-concat
          (list "rm: remove " (%rm-kind-words st) " '" path "'? "))))))

; and whether to go into a directory that holds anything
(def %rm-may-enter?
  (fn (_ o path names)
    (if (if (%rm-told? o "-i") (not (null? names)) #f)
      (%fs-ask
        (string-concat (list "rm: descend into directory '" path "'? ")))
      #t)))

; what rm calls a path, in the file-type words the coreutils share
(def %rm-kind-words
  (fn (_ st)
    (let ((kind (%cu-stat-get st (lit kind))))
      (match
        ((eq? kind (lit dir)) "directory")
        ((eq? kind (lit link)) "symbolic link")
        ((eq? kind (lit fifo)) "fifo")
        ((eq? kind (lit socket)) "socket")
        ((eq? kind (lit char)) "character special file")
        ((eq? kind (lit block)) "block special file")
        ((= (%cu-stat-get st (lit size)) 0) "regular empty file")
        (#t "regular file")))))

; the removal made, and said under -v -- SAID is how -v begins the line -- or
; refused, with the reason
(def %rm-gone
  (fn (_ path o r said)
    (if (Err err? r) (%rm-cannot path (file-err-text r))
      (do (if (Opts on? o "-v")
            (display (string-concat (list said path "'\n")))
            ())
          0))))

(def %rm-cannot
  (fn (_ path why)
    (do (file-write 2
          (string-concat (list "rm: cannot remove '" path "': " why "\n")))
        1)))

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
        (match
          ((null? os) st)
          (p?
            (do (%cu-mkdir-p! (first os)) (stamp! (first os))
                (self (rest os) st)))
          ((file-exists? (first os))
            (do (file-write 2
                  (string-concat
                    (list "mkdir: cannot create directory '" (first os)
                          "': File exists\n")))
                (self (rest os) 1)))
          (#t
            (do (file-mkdir (first os)) (stamp! (first os))
                (self (rest os) st))))))
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

; TARGET... [NAME]: one target and no name makes the link here; several, or
; -t DIR, make them in a directory, which a NAME that is not one refuses.
(def %cu-ln
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "ln" argv))
    (def ops (Opts operands o))
    ; -t DIR names the directory the links go in, and then every
    ; operand is a target
    (def dir (Opts value o "-t"))
    (if (null? ops)
      (do (file-write 2 "ln: usage: ln [-sfnbtv] TARGET... [NAME]\n") 1)
      (let ((targets (if (null? dir)
                       (if (null? (rest ops)) ops (%cu-drop-last ops))
                       ops))
            (into (if (null? dir)
                    (if (null? (rest ops)) "." (%cu-last ops))
                    dir))
            (here? (if (null? dir) (null? (rest ops)) #f)))
        (if (if (if (null? dir) (> (length ops) 2) #t)
              (not (%ln-dir? into o)) #f)
          (%ln-fails (list (%ln-not-dir into o (not (null? dir)))))
          (%cu-walk-worst targets
            (fn (_ t) (%ln-one t (%ln-name t into here? o) o))
            0))))))

; Why a name is no directory to make links in, in ln's words, which turn on
; -t and on what is there: a link, under -n, is "Not a directory"; a name
; with nothing behind it gives the reason; anything else under -t "is not a
; directory".
(def %ln-not-dir
  (fn (_ into o t?)
    (if (if (Opts on? o "-n") (eq? (file-lstat-kind into) (lit link)) #f)
      (%ln-target into ": Not a directory")
      (let ((st (file-or-err (fn (_) (file-stat-wide into)))))
        (match
          ((not (Err err? st))
            (%ln-target into (if t? " is not a directory" ": Not a directory")))
          (t? (string-concat
                (list "ln: failed to access '" into "': " (file-err-text st))))
          (#t (%ln-target into (string-append ": " (file-err-text st)))))))))

(def %ln-target
  (fn (_ into why) (string-concat (list "ln: target '" into "'" why))))

; Whether a NAME is a directory to make the links in.  -n takes a link to a
; directory as the link it is, so it names a file rather than the directory
; it points at; a directory itself is one either way.
(def %ln-dir?
  (fn (_ path o)
    (if (Opts on? o "-n") (eq? (file-lstat-kind path) (lit dir))
      (file-dir? path))))

(def %ln-name
  (fn (_ t into here? o)
    (match
      (here? (%cu-basename-of t))
      ((%ln-dir? into o) (%cu-path-join into (%cu-basename-of t)))
      (#t into))))

; One link, NAME to T: a symbolic one under -s, a hard one otherwise -- which
; needs T to be there.  What is at NAME already is kept as NAME~ under -b and
; dropped under -f; a link refused is said in ln's words, and fails.
(def %ln-one
  (fn (_ t name o)
    (let ((there (if (Opts on? o "-s") 0
                   (file-or-err (fn (_) (file-lstat-wide t))))))
      (if (Err err? there)
        (%ln-fails (list "ln: failed to access '" t "': " (file-err-text there)))
        (do (%ln-displace! name o)
            (let ((r (file-or-err
                       (fn (_) (if (Opts on? o "-s") (file-symlink t name)
                                 (file-link t name))))))
              (if (Err err? r)
                (%ln-fails
                  (list "ln: failed to create "
                        (if (Opts on? o "-s") "symbolic link" "hard link")
                        " '" name "': " (file-err-text r)))
                (do (if (Opts on? o "-v")
                      (display (string-concat (list "'" name "' -> '" t "'\n")))
                      ())
                    0))))))))

; -b keeps what is at NAME as NAME~, -f drops it; one that cannot be moved is
; left for the link itself to be refused by
(def %ln-displace!
  (fn (_ name o)
    (if (eq? (file-lstat-kind name) (lit none)) ()
      (file-or-err
        (fn (_)
          (match
            ((Opts on? o "-b") (file-rename name (string-append name "~")))
            ((Opts on? o "-f") (file-unlink name))
            (#t ())))))))

(def %ln-fails
  (fn (_ line)
    (do (file-write 2 (string-concat (append line (list "\n")))) 1)))

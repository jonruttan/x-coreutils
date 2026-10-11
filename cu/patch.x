; # x-coreutils -- the small tools, as applets
;
; ## cu/patch.x -- patch
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's patch (editors/patch.c, from toybox's): a unified diff applied in
; one pass over each file.  A hunk is found by its context and removed lines,
; not by its line numbers, so hunks are applied in order; a file whose hunk is
; not found is left as it was, the hunk said on stderr, and its later hunks
; passed over.  The file is written to NAMEXXXXXX beside it and renamed over
; it at the end.  -p strips leading parts of the names, all but the last
; without it; -R applies the patch backwards; -N passes over a hunk already
; applied; -E removes a file the patch empties; --dry-run writes nothing.

(def %pt-die (fn (_ msg) (Err raise (lit patch) (string-append "patch: " msg) ())))

(def %pt-why
  (fn (_ op name) (file-err-text (Err from-errno (Err errno-of -1) op name))))

(def %pt-open
  (fn (_ name flags)
    (let ((fd (File open name flags 438)))
      (if (< fd 0)
        (%pt-die (string-concat (list "can't open '" name "': " (file-err-text (file-open-err fd name)))))
        fd))))

; --- lines --------------------------------------------------------------------

; A reader of SRC's lines, in a vector: the source, the piece being read and
; its text, where in it, and a line put back.
(def %pt-reader
  (fn (_ src) (vec-build 5 (fn (_ i) (match ((= i 0) src) ((= i 3) 0) (#t ()))))))

; the next line, its newline gone, or nil at the end; a last line without
; one is a line
(def %pt-line!
  (fn (_ rd)
    (def go
      (fn (self acc)
        (let ((text (vec-ref rd 2)) (pos (vec-ref rd 3)))
          (if (if (null? text) #t (>= pos (byte-len text)))
            (let ((p ((vec-ref rd 0))))
              (if (if (Err err? p) #t (= (rest p) 0))
                (do (vec-set! rd 1 ()) (vec-set! rd 2 ())
                    (if (null? acc) () (string-concat (reverse acc))))
                (do (vec-set! rd 1 p) (vec-set! rd 2 (%cu-run-text p)) (vec-set! rd 3 0) (self acc))))
            (let ((nl (%dp-find text pos #\newline)))
              (if (< nl 0)
                (do (vec-set! rd 3 (byte-len text)) (self (pair (substring text pos (byte-len text)) acc)))
                (do (vec-set! rd 3 (+ nl 1))
                    (string-concat (reverse (pair (substring text pos nl) acc))))))))))
    (let ((back (vec-ref rd 4)))
      (if (null? back) (go ()) (do (vec-set! rd 4 ()) back)))))

(def %pt-unread! (fn (_ rd line) (vec-set! rd 4 line)))

; what is left of RD's source written to FD as it is
(def %pt-copy-rest!
  (fn (_ rd fd)
    (def go
      (fn (self)
        (let ((p ((vec-ref rd 0))))
          (if (if (Err err? p) #t (= (rest p) 0)) ()
            (do (file-write-run fd p) (%cu-sweep-tick! %cu-sweep-lines) (self))))))
    (do (let ((p (vec-ref rd 1)) (pos (vec-ref rd 3)))
          (if (if (null? p) #f (< pos (rest p))) (file-write-run fd (%cu-run-from p pos)) ()))
        (go))))

(def %pt-starts? (fn (_ s p) (if (>= (byte-len s) (byte-len p)) (string=? (substring s 0 (byte-len p)) p) #f)))

; --- the run's state ------------------------------------------------------------

; In a vector: the file read (a reader, or nil), the file written, the
; temporary file's name ("" under --dry-run, nil where none is open), the
; status, the line read, the hunk's number, the hunk's old and new start,
; its context lines, its old and new lengths, the hunk (its lines newest
; first, each a vector of TEXT and NO-NEWLINE), -R, -N, --dry-run.
(def %pt-g ())
(def %pg (fn (_ i) (vec-ref %pt-g i)))
(def %pg! (fn (_ i v) (vec-set! %pt-g i v)))

; the file being patched finished: the rest of it copied, and the copy
; renamed over it
(def %pt-finish!
  (fn (_)
    (do (if (null? (%pg 2)) ()
          (do (if (null? (%pg 0)) ()
                (do (%pt-copy-rest! (%pg 0) (%pg 1)) ((vec-ref (%pg 0) 0) (lit close))))
              (file-close (%pg 1))
              (if (= (byte-len (%pg 2)) 0) ()
                (guard (e ()) (file-rename (%pg 2) (substring (%pg 2) 0 (- (byte-len (%pg 2)) 6)))))
              (%pg! 2 ())))
        (%pg! 0 ()))))

; the hunk held not found: said, with its lines, on stderr, and the file
; left as it was
(def %pt-fail!
  (fn (_)
    (if (null? (%pg 11)) ()
      (do (file-write 2 (string-concat (list "Hunk " (%cu-int->str (%pg 5)) " FAILED "
                                             (%cu-int->str (%pg 6)) "/" (%cu-int->str (%pg 7)) ".\n")))
          (%pg! 3 1)
          (map (fn (_ l) (file-write 2 (string-append (vec-ref l 0) "\n"))) (reverse (%pg 11)))
          (%pg! 11 ())
          (if (null? (%pg 0)) () ((vec-ref (%pg 0) 0) (lit close)))
          (if (null? (%pg 1)) () (file-close (%pg 1)))
          (if (if (null? (%pg 2)) #f (> (byte-len (%pg 2)) 0)) (guard (e ()) (file-unlink (%pg 2))) ())
          (%pg! 2 ())
          (%pg! 0 ())))))

; a hunk's line written out, its first byte gone
(def %pt-put!
  (fn (_ l)
    (let ((t (vec-ref l 0)))
      (file-write (%pg 1) (string-append (substring t 1 (byte-len t)) (if (vec-ref l 1) "" "\n"))))))

(def %pt-ch (fn (_ l) (byte-at (vec-ref l 0) 0)))
(def %pt-body (fn (_ l) (let ((t (vec-ref l 0))) (substring t 1 (byte-len t)))))

; --- a hunk ------------------------------------------------------------------------

; busybox's apply_one_hunk: the file copied until the hunk's context and
; removed lines are met, then the hunk's new lines written in their place.
; Answers 1, or 0 where the file ended first.
(def %pt-apply!
  (fn (_)
    (def hunk (reverse (%pg 11)))
    (def tail (let ((go (fn (self ls n) (if (null? ls) n (self (rest ls) (if (= (%pt-ch (first ls)) #\space) (+ n 1) 0))))))
                (go hunk 0)))
    (def s (vec-build 6 (fn (_ i) (match ((= i 0) hunk) ((= i 1) hunk) ((= i 2) 0) ((= i 3) #f)
                                         ((= i 4) (if (= tail 0) #t (< tail (%pg 8)))) (#t (%pg 12))))))
    (def how (if (= (if (= (%pg 12) 1) (%pg 9) (%pg 10)) 0) (lit out) (%pt-read s ())))
    (if (eq? how (lit failed)) 0
      (let ((st (if (= (bit-xor (vec-ref s 5) (if (vec-ref s 3) 1 0)) 1) #\+ #\-)))
        (do (map (fn (_ l) (if (= (%pt-ch l) st) () (%pt-put! l))) hunk)
            (%pg! 11 ())
            1)))))

; A hunk's matching state, in a vector: what is left of it to match, the
; hunk, the line warned of as already there, whether -N turned it round,
; whether it must match the file's end, and which way it runs (1 under -R).
(def %pt-add-ch (fn (_ s) (if (= (vec-ref s 5) 1) #\- #\+)))

; past the lines the hunk adds, the first of them found already there noted;
; under -N that turns the hunk round, and, where STAY, DATA is looked at
; again the other way
(def %pt-skip!
  (fn (self s data stay)
    (let ((pl (vec-ref s 0)))
      (if (if (null? pl) #t (not (= (%pt-ch (first pl)) (%pt-add-ch s)))) ()
        (let ((seen (if (null? data) #f (if (= (vec-ref s 2) 0) (string=? data (%pt-body (first pl))) #f))))
          (do (if seen (vec-set! s 2 (%pg 4)) ())
              (if (if seen (%pg 13) #f) (do (vec-set! s 3 #t) (vec-set! s 5 (- 1 (vec-ref s 5)))) ())
              (if (if seen (if (%pg 13) stay #f) #f) () (vec-set! s 0 (rest pl)))
              (self s data stay)))))))

; the held lines BUF from I against the hunk: (lit read) and the lines still
; held where more are wanted, (lit out) where it matched; a line that cannot
; start a match is written out
(def %pt-check
  (fn (self s buf i)
    (do (%pt-skip! s (List ref i buf) #f)
        (let ((pl (vec-ref s 0)))
          (if (if (null? pl) #t (not (string=? (List ref i buf) (%pt-body (first pl)))))
            (do (file-write (%pg 1) (string-append (first buf) "\n"))
                (vec-set! s 0 (vec-ref s 1))
                (if (null? (rest buf)) (pair (lit read) ()) (self s (rest buf) 0)))
            (do (vec-set! s 0 (rest pl))
                (match
                  ((if (null? (rest pl)) (not (vec-ref s 4)) #f) (pair (lit out) buf))
                  ((= (+ i 1) (length buf)) (pair (lit read) buf))
                  (#t (self s buf (+ i 1))))))))))

; the file's lines read until the hunk is found, (lit out), or the file ends
; first, (lit failed)
(def %pt-read
  (fn (self s buf)
    (let ((data (if (null? (%pg 0)) () (%pt-line! (%pg 0)))))
      (do (%pg! 4 (+ (%pg 4) 1))
          (%pt-skip! s data #t)
          (if (null? data) (%pt-ended s)
            (let ((r (%pt-check s (append buf (list data)) (length buf))))
              (if (eq? (first r) (lit out)) (lit out)
                (do (%cu-sweep-tick! %cu-sweep-lines) (self s (rest r))))))))))

; the file ended: the hunk matched where it was to end there, else failed
(def %pt-ended
  (fn (_ s)
    (if (if (null? (vec-ref s 0)) (vec-ref s 4) #f) (lit out)
      (do (if (= (vec-ref s 2) 0) ()
            (file-write 2 (string-concat (list "Possibly reversed hunk " (%cu-int->str (%pg 5))
                                               " at " (%cu-int->str (%pg 4)) "\n"))))
          (%pt-fail!)
          (lit failed)))))

; --- the diff ------------------------------------------------------------------------

; a number at I of S, as strtol reads one: (VALUE . WHERE IT ENDS)
(def %pt-num
  (fn (_ s i)
    (def n (byte-len s))
    (def neg (if (< i n) (= (byte-at s i) #\-) #f))
    (def go
      (fn (self j v)
        (if (if (< j n) (if (>= (byte-at s j) #\0) (<= (byte-at s j) #\9) #f) #f)
          (self (+ j 1) (+ (* v 10) (- (byte-at s j) #\0)))
          (pair (if neg (- 0 v) v) j))))
    (go (if (if neg #t (if (< i n) (= (byte-at s i) #\+) #f)) (+ i 1) i) 0)))

; the name on a --- or +++ line: up to a tab, a backslash taking the byte
; after it along; /dev/null where the date after it is the epoch's
(def %pt-name-of
  (fn (_ line)
    (def n (byte-len line))
    (def end
      (let ((go (fn (self i) (match ((>= i n) i) ((= (byte-at line i) #\tab) i)
                                    ((if (= (byte-at line i) #\\) (< (+ i 1) n) #f) (self (+ i 2)))
                                    (#t (self (+ i 1)))))))
        (go 4)))
    (def year
      (let ((go (fn (self i) (if (if (< i n) (if (= (byte-at line i) #\tab) #t (= (byte-at line i) #\space)) #f) (self (+ i 1)) i))))
        (first (%pt-num line (go end)))))
    (if (if (> year 1900) (<= year 1970) #f) "/dev/null" (substring line 4 end))))

; NAME with its leading parts stripped, as -p N strips them, every one
; without it: (NAME . PARTS STRIPPED)
(def %pt-strip
  (fn (_ name p)
    (def n (byte-len name))
    (def go
      (fn (self s i from)
        (match
          ((if (null? p) #f (= p i)) (pair (substring name from n) i))
          ((>= s n) (pair (substring name from n) i))
          ((not (= (byte-at name s) #\/)) (self (+ s 1) i from))
          (#t (let ((past (let ((k (fn (self j) (if (if (< j n) (= (byte-at name j) #\/) #f) (self (+ j 1)) j)))) (k (+ s 1)))))
                (self past (+ i 1) past))))))
    (go 0 0 0)))

; mkstemp's NAMEXXXXXX: (FD . NAME)
(def %pt-mkstemp
  (fn (_ name)
    (def t (string-append name "XXXXXX"))
    (def n (byte-len t))
    (def buf (%str-make-raw (+ n 1)))
    (def p (%cu-str->ptr buf))
    (do (map (fn (_ i) (%cu-ptr-set! p i (byte-at t i) 1)) (List range 0 n))
        (%cu-ptr-set! p n 0 1)
        (let ((fd (Sys %sign-fold (%cu-ptr-call (%cu-dlsym (%cu-dlopen () 1) "mkstemp") p))))
          (if (< fd 0) (%pt-die (string-concat (list "can't create '" t "': " (%pt-why (lit mkstemp) t))))
            (pair fd (%cu-ptr->str p)))))))

; the file a hunk's header names, opened at its first hunk: emptied,
; removed, made, or read, with its copy made to write
(def %pt-open-file!
  (fn (_ o argv oldname newname)
    (def rev (= (%pg 12) 1))
    (def dry (%pg 14))
    (def oldsum (+ (%pg 6) (%pg 9)))
    (def newsum (+ (%pg 7) (%pg 10)))
    (def named (if rev oldname newname))
    (def empty (if (string=? named "/dev/null") #t (= (if rev oldsum newsum) 0)))
    (def p (let ((v (Opts value o "-p"))) (if (null? v) (Opts value o "--strip") v)))
    (def cut (%pt-strip (if empty (if rev newname oldname) named) (if (null? p) () (%cu-num-prefix p))))
    (def name (if (null? argv) (first cut) (first argv)))
    (def say (fn (_ s) (file-write 1 (string-concat (list s " " name "\n")))))
    (match
      (empty
        (do (if (if (Opts on? o "-E") #t (Opts on? o "--remove-empty-files"))
              (do (say "removing")
                  (if dry () (if (guard (e #f) (do (file-unlink name) #t)) ()
                               (%pt-die (string-concat (list "can't remove file '" name "': " (%pt-why (lit unlink) name)))))))
              (do (say "patching file")
                  (if dry () (file-close (%pt-open name (list (lit wronly) (lit trunc)))))))
            0))
      (#t
        (do (if (if (string=? oldname "/dev/null") #t (= oldsum 0))
              (do (say "creating")
                  (%pg! 0 (%pt-reader (%cu-fd-chunks
                    (if dry (%pt-open "/dev/null" (lit rdonly))
                      (do (let ((sl (%tar-last-slash name))) (if (> sl 0) (%cu-mkdir-p! (substring name 0 sl)) ()))
                          (%pt-open name (list (lit rdwr) (lit creat) (lit excl)))))
                    name))))
              (do (say "patching file")
                  (%pg! 0 (%pt-reader (%cu-fd-chunks (%pt-open name (lit rdonly)) name)))))
            (if dry
              (do (%pg! 2 "") (%pg! 1 (%pt-open "/dev/null" (lit wronly))))
              (let ((t (%pt-mkstemp name)))
                (do (%pg! 1 (first t)) (%pg! 2 (rest t))
                    (let ((st (file-stat-full name)))
                      (if (null? st) () (guard (e ()) (file-chmod (rest t) (& (%cu-stat-get st (lit mode)) 4095))))))))
            (%pg! 4 0)
            (%pg! 5 0)
            1)))))

; patch [-RNE] [-p N] [-i DIFF] [ORIGFILE [PATCHFILE]]
(def %cu-patch
  (fn (_ argv stdin-thunk)
    (guard (e (if (eq? (%cu-err-label e) (lit patch))
                (do (file-write 2 (string-append (e msg) "\n")) 1)
                (error e)))
      (%pt-run argv stdin-thunk))))

(def %pt-run
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "patch" argv))
    (def on (fn (_ a b) (if (Opts on? o a) #t (Opts on? o b))))
    (def ops (Opts operands o))
    (def input (let ((i (Opts value o "-i"))) (if (null? i) (Opts value o "--input") i)))
    (def diff (if (null? input) (if (if (pair? ops) (pair? (rest ops)) #f) (first (rest ops)) "-") input))
    (def src (%cu-pieces diff stdin-thunk))
    (def rev (on "-R" "--reverse"))
    (do (set! %pt-g (vec-build 15 (fn (_ i) (match ((= i 3) 0) ((= i 12) (if rev 1 0)) ((= i 13) (on "-N" "--forward"))
                                                    ((= i 14) (Opts on? o "--dry-run")) (#t ())))))
        (if (Err err? src) (%pt-die (string-concat (list "can't open '" diff "': " (file-err-text src))))
          (%pt-lines o ops (%pt-reader src) rev)))))

; busybox's patch_main loop over the diff's lines: STATE 0 looks for +++, 1
; for @@, 2 counts a hunk's first context lines, 3 reads the rest of it
(def %pt-lines
  (fn (_ o ops rd rev)
    (def names (vec-make 2 ()))
    (def lens (vec-make 2 0))
    (def mark! (fn (_) (if (null? (%pg 11)) () (vec-set! (first (%pg 11)) 1 #t))))
    (def go
      (fn (self state)
        (let ((raw (%pt-line! rd)))
          (if (null? raw) ()
            (let ((line (if (= (byte-len raw) 0) " " raw)))
              (do (%cu-sweep-tick! %cu-sweep-lines)
                  (self (%pt-line o ops rd rev line state names lens mark!))))))))
    (do (go 0)
        (%pt-finish!)
        (%pg 3))))

; one line of the diff in STATE: the state after it
(def %pt-line
  (fn (_ o ops rd rev line state names lens mark!)
    (def c (byte-at line 0))
    (match
      ((if (>= state 2) (= c #\\) #f) (do (mark!) state))
      ((if (>= state 2) (if (= c #\space) #t (if (= c #\+) #t (= c #\-))) #f)
        (do (%pg! 11 (pair (vec-build 2 (fn (_ i) (if (= i 0) line #f))) (%pg 11)))
            (if (= c #\+) () (vec-set! lens 0 (- (vec-ref lens 0) 1)))
            (if (= c #\-) () (vec-set! lens 1 (- (vec-ref lens 1) 1)))
            (let ((st (if (if (= c #\space) (= state 2) #f) (do (%pg! 8 (+ (%pg 8) 1)) 2) 3)))
              (if (if (= (vec-ref lens 0) 0) (= (vec-ref lens 1) 0) #f)
                ; a '\ No newline' after the hunk's last line belongs to it
                (do (let ((next (%pt-line! rd)))
                      (if (null? next) ()
                        (if (if (> (byte-len next) 0) (= (byte-at next 0) #\\) #f) (mark!) (%pt-unread! rd next))))
                    (%pt-apply!))
                st))))
      ((>= state 2) (do (%pt-fail!) 0))
      ((if (%pt-starts? line "--- ") #t (%pt-starts? line "+++ "))
        (do (%pt-finish!)
            (if (null? ops)
              (vec-set! names (if (= c #\+) (if rev 0 1) (if rev 1 0)) (%pt-name-of line))
              ())
            (if (= c #\+) 1 state)))
      ((if (= state 1) (%pt-starts? line "@@ -") #f) (%pt-hunk-head! o ops line names lens))
      (#t state))))

; a hunk's @@ line: its starts and lengths read, and its file opened at the
; first; the state after it
(def %pt-hunk-head!
  (fn (_ o ops line names lens)
    (def a (%pt-num line 4))
    (def al (if (if (< (rest a) (byte-len line)) (= (byte-at line (rest a)) #\,) #f) (%pt-num line (+ (rest a) 1)) (pair 1 (rest a))))
    (def b (%pt-num line (+ (rest al) 2)))
    (def bl (if (if (< (rest b) (byte-len line)) (= (byte-at line (rest b)) #\,) #f) (%pt-num line (+ (rest b) 1)) (pair 1 (rest b))))
    (do (%pg! 6 (first a)) (%pg! 9 (first al)) (%pg! 7 (first b)) (%pg! 10 (first bl))
        (vec-set! lens 0 (first al)) (vec-set! lens 1 (first bl))
        (if (if (< (first al) 1) (< (first bl) 1) #f) (%pt-die (string-append "Really? " line)) ())
        (%pg! 8 0)
        (%pg! 11 ())
        (if (null? (vec-ref names 0)) (vec-set! names 0 "MISSING_FILENAME") ())
        (if (null? (vec-ref names 1)) (vec-set! names 1 "MISSING_FILENAME") ())
        (let ((st (if (null? (%pg 0))
                    (%pt-open-file! o ops (vec-ref names 0) (vec-ref names 1))
                    2)))
          (do (%pg! 5 (+ (if (null? (%pg 5)) 0 (%pg 5)) 1))
              (if (= st 0) 0 2))))))

; # x-coreutils -- the small tools, as applets
;
; ## cu/ed.x -- ed
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's ed (editors/ed.c, "much simplified"): the line editor, its
; commands read from standard input.  Addresses are numbers, `.`, `$`, a
; mark, or a string searched for between slashes, summed and differenced;
; a search and s's old text are strings, not patterns.  The commands are a
; c d f i k l p q r s w z = . and -, an empty one stepping on.  A file read
; or written has its bytes said, unless -s; -p's prompt, and q's question
; when the buffer is changed, go to stderr, as busybox's line reader writes
; them there when standard input is not a terminal.  Every error is said
; under ed's name and the run goes on; the status is 0.

; The editor's state, in a vector: the lines (each with its newline, but a
; last line read without one), how many, the current line, changed?, the
; marks, the file's name, the string last searched for, the prompt, -s, the
; command lines' reader.
(def %ed ())
(def %eg (fn (_ i) (vec-ref %ed i)))
(def %eg! (fn (_ i v) (vec-set! %ed i v)))
(def %ed-last (fn (_) (%eg 1)))
(def %ed-cur (fn (_) (%eg 2)))

(def %ed-err (fn (_ msg) (do (file-write 2 (string-concat (list "ed: " msg "\n"))) #f)))

(def %ed-why
  (fn (_ op name) (file-err-text (Err from-errno (Err errno-of -1) op name))))

; --- input -----------------------------------------------------------------------

; the next line of standard input as fgets reads it into MAX bytes: its
; newline kept, at most MAX - 1 bytes, nil at the end
(def %ed-gets
  (fn (_ max)
    (def rd (%eg 9))
    (def go
      (fn (self acc n)
        (let ((text (vec-ref rd 1)) (pos (vec-ref rd 2)))
          (if (if (null? text) #t (>= pos (byte-len text)))
            (let ((p ((vec-ref rd 0))))
              (if (if (Err err? p) #t (= (rest p) 0))
                (do (vec-set! rd 1 ()) (if (null? acc) () (string-concat (reverse acc))))
                (do (vec-set! rd 1 (%cu-run-text p)) (vec-set! rd 2 0) (self acc n))))
            (let ((nl (%dp-find text pos #\newline)))
              (let ((end (%ed-min (if (< nl 0) (byte-len text) (+ nl 1)) (+ pos (- (- max 1) n)))))
                (do (vec-set! rd 2 end)
                    (let ((acc2 (pair (substring text pos end) acc)) (n2 (+ n (- end pos))))
                      (if (if (= n2 (- max 1)) #t (if (> nl -1) (= end (+ nl 1)) #f))
                        (string-concat (reverse acc2))
                        (self acc2 n2))))))))))
    (go () 0)))

(def %ed-min (fn (_ a b) (if (< a b) a b)))

(def %ed-space? (fn (_ c) (if (= c #\space) #t (if (>= c 9) (<= c 13) #f))))

; S from I past its blanks
(def %ed-skip
  (fn (_ s i) (if (if (< i (byte-len s)) (%ed-space? (byte-at s i)) #f) (%ed-skip s (+ i 1)) i)))

(def %ed-at (fn (_ s i) (if (< i (byte-len s)) (byte-at s i) 0)))

; --- the lines -------------------------------------------------------------------

(def %ed-bad-nums?
  (fn (_ n1 n2 what)
    (if (if (< n1 1) #t (if (> n2 (%ed-last)) #t (> n1 n2)))
      (do (%ed-err (string-append "bad line range for " what)) #t)
      #f)))

; line NUM's text, or #f said where there is none
(def %ed-line
  (fn (_ num)
    (if (if (< num 1) #t (> num (%ed-last)))
      (%ed-err (string-concat (list "line number " (%cu-int->str num) " does not exist")))
      (List ref (- num 1) (%eg 0)))))

(def %ed-set-cur!
  (fn (_ num) (if (eq? (%ed-line num) #f) #f (do (%eg! 2 num) #t))))

; LINES put in to become line NUM on, the last of them current
(def %ed-insert!
  (fn (_ num lines)
    (if (null? lines) #t
      (do (%eg! 0 (append (%cu-take (%eg 0) (- num 1)) lines (%cu-nthrest (- num 1) (%eg 0))))
          (%eg! 1 (+ (%eg 1) (length lines)))
          (%eg! 3 #t)
          (%ed-set-cur! (+ num (- (length lines) 1)))))))

(def %ed-delete!
  (fn (_ n1 n2)
    (if (%ed-bad-nums? n1 n2 "delete") ()
      (let ((count (+ (- n2 n1) 1)))
        (do (if (if (>= (%ed-cur) n1) (<= (%ed-cur) n2) #f)
              (match ((< n2 (%ed-last)) (%ed-set-cur! (+ n2 1)))
                     ((> n1 1) (%ed-set-cur! (- n1 1)))
                     (#t (%eg! 2 0)))
              ())
            (if (> (%ed-cur) n2) (%eg! 2 (- (%ed-cur) count)) ())
            (%eg! 0 (append (%cu-take (%eg 0) (- n1 1)) (%cu-nthrest n2 (%eg 0))))
            (%eg! 1 (- (%eg 1) count))
            (%eg! 3 #t))))))

; where STR is in LINE from OFF, or -1
(def %ed-find
  (fn (_ line str off)
    (def n (byte-len str))
    (def go
      (fn (self i)
        (if (> (+ i n) (byte-len line)) -1
          (if (string=? (substring line i (+ i n)) str) i (self (+ i 1))))))
    (go off)))

; the first line from N1 to N2 holding STR, the last string searched for
; where it is empty; 0 said where none does
(def %ed-search
  (fn (_ str n1 n2)
    (match
      ((%ed-bad-nums? n1 n2 "search") 0)
      ((if (= (byte-len str) 0) (= (byte-len (%eg 6)) 0) #f) (do (%ed-err "no previous search string") 0))
      (#t (let ((s (if (= (byte-len str) 0) (%eg 6) str)))
            (do (%eg! 6 s)
                (let ((go (fn (self n ls)
                            (match ((> n n2) (do (%ed-err (string-concat (list "can't find string \"" s "\""))) 0))
                                   ((>= (%ed-find (first ls) s 0) 0) n)
                                   (#t (self (+ n 1) (rest ls)))))))
                  (go n1 (%cu-nthrest (- n1 1) (%eg 0))))))))))

; LINE as l shows it: control bytes as ^X, high ones as M-, then $
(def %ed-shown
  (fn (_ line)
    (def n (if (if (> (byte-len line) 0) (= (byte-at line (- (byte-len line) 1)) #\newline) #f)
             (- (byte-len line) 1) (byte-len line)))
    (def one
      (fn (_ c)
        (let ((meta (>= c 128)) (b (& c 127)))
          (string-append (if meta "M-" "")
            (match ((< b 32) (bytes->str (list #\^ (+ b 64))))
                   ((= b 127) "^?")
                   (#t (bytes->str (list b))))))))
    (string-concat (append (map (fn (_ i) (one (byte-at line i))) (List range 0 n)) (list "$\n")))))

; lines N1 to N2 printed, each current in turn; L shows them as l does
(def %ed-print
  (fn (_ n1 n2 l)
    (if (if (%ed-bad-nums? n1 n2 "print") #t (eq? (%ed-line n1) #f)) #f
      (do (map (fn (_ n) (do (file-write 1 (if l (%ed-shown (%ed-line n)) (%ed-line n))) (%ed-set-cur! n)))
               (List range n1 (+ n2 1)))
          #t))))

; --- files -----------------------------------------------------------------------

; FILE read in to become line NUM on, its bytes said: #t, or #f said
(def %ed-read-file
  (fn (_ file num)
    (if (if (< num 1) #t (> num (+ (%ed-last) 1))) (%ed-err "bad line for read")
      (let ((src (%cu-pieces file ())))
        (if (Err err? src) (%ed-err (string-concat (list file ": " (file-err-text src))))
          (let ((text (string-concat (map %cu-run-text (%tar-all-pieces src)))))
            (let ((lines (%ed-split text)))
              (do (%ed-insert! num lines)
                  (if (%eg 8) () (file-write 1 (string-append (%cu-int->str (byte-len text)) "\n")))
                  #t))))))))

; TEXT's lines, each with its newline, the last without where it has none
(def %ed-split
  (fn (_ text)
    (def go
      (fn (self i acc)
        (if (>= i (byte-len text)) (reverse acc)
          (let ((nl (%dp-find text i #\newline)))
            (if (< nl 0) (reverse (pair (substring text i (byte-len text)) acc))
              (self (+ nl 1) (pair (substring text i (+ nl 1)) acc)))))))
    (go 0 ())))

(def %ed-write-file
  (fn (_ file n1 n2)
    (if (%ed-bad-nums? n1 n2 "write") #f
      (let ((fd (File open file (list (lit wronly) (lit creat) (lit trunc)) 438)))
        (if (< fd 0) (%ed-err (string-concat (list file ": " (file-err-text (file-open-err fd file)))))
          (let ((ls (%cu-take (%cu-nthrest (- n1 1) (%eg 0)) (+ (- n2 n1) 1))))
            (do (map (fn (_ l) (file-write fd l)) ls)
                (file-close fd)
                (if (%eg 8) ()
                  (file-write 1 (string-append (%cu-int->str (List fold (fn (_ a l) (+ a (byte-len l))) 0 ls)) "\n")))
                #t)))))))

; --- s ---------------------------------------------------------------------------

; s/OLD/NEW/[gp] over lines N1 to N2: (OLD NEW GLOBAL PRINT), or #f said
(def %ed-sub-parts
  (fn (_ cmd)
    (def d (%ed-at cmd 0))
    (def mid (if (= d 0) -1 (%dp-find cmd 1 d)))
    (def end (if (< mid 0) -1 (%dp-find cmd (+ mid 1) d)))
    (def flags (if (< end 0) "" (substring cmd (+ end 1) (byte-len cmd))))
    (def bad (filter (fn (_ c) (not (if (= c #\g) #t (= c #\p)))) (%tar-str-bytes flags)))
    (match
      ((if (= d 0) #t (if (= d #\space) #t (= d #\tab))) (%ed-err "bad delimiter for substitute"))
      ((< mid 0) (%ed-err "missing 2nd delimiter for substitute"))
      ((pair? bad) (%ed-err "unknown option for substitute"))
      (#t (list (substring cmd 1 mid)
                (substring cmd (+ mid 1) (if (< end 0) (byte-len cmd) end))
                (pair? (filter (fn (_ c) (= c #\g)) (%tar-str-bytes flags)))
                (pair? (filter (fn (_ c) (= c #\p)) (%tar-str-bytes flags))))))))

; LINE with OLD at OFF replaced by NEW
(def %ed-splice
  (fn (_ line off old new)
    (string-concat (list (substring line 0 off) new (substring line (+ off (byte-len old)) (byte-len line))))))

(def %ed-sub
  (fn (_ cmd n1 n2)
    (def parts (if (%ed-bad-nums? n1 n2 "substitute") #f (%ed-sub-parts cmd)))
    (match
      ((eq? parts #f) ())
      ((if (= (byte-len (first parts)) 0) (= (byte-len (%eg 6)) 0) #f) (%ed-err "no previous search string"))
      ((eq? (%ed-line n1) #f) ())
      (#t (let ((old (if (= (byte-len (first parts)) 0) (%eg 6) (first parts))))
            (do (%eg! 6 old)
                (if (%ed-sub-lines old (%cu-nth 1 parts) (%cu-nth 2 parts) (%cu-nth 3 parts) n1 n2 0) ()
                  (%ed-err (string-concat (list "no substitutions found for \"" old "\""))))))))))

; each line from N to N2 with OLD replaced, the first from OFF or, under G,
; all; under P each line changed printed; #t where any was.  As busybox's
; does, a line changed without G leaves the search of the next starting
; where its own stopped.
(def %ed-sub-lines
  (fn (self old new g p n n2 off)
    (if (> n n2) #f
      (let ((r (%ed-sub-line (%ed-line n) old new g off ())))
        (do (if (null? (rest r)) ()
              (do (%eg! 0 (append (%cu-take (%eg 0) (- n 1)) (list (first r)) (%cu-nthrest n (%eg 0))))
                  (%eg! 3 #t)
                  (if p (%ed-print n n #f) ())))
            (let ((next (if (if g #t (null? (rest r))) 0 (rest r))))
              (if (self old new g p (+ n 1) n2 next) #t (not (null? (rest r))))))))))

; (LINE AFTER . WHERE THE LAST REPLACEMENT ENDS), nil there where none was
(def %ed-sub-line
  (fn (self line old new g off done)
    (let ((at (%ed-find line old off)))
      (if (< at 0) (pair line done)
        (let ((l2 (%ed-splice line at old new)) (end (+ at (byte-len new))))
          (if g (self l2 old new g end end) (pair l2 end)))))))

; --- the commands ----------------------------------------------------------------

; busybox's getNum: an address at I of S, a sum or difference of terms:
; (I-AFTER HAVE VALUE), or #f said
(def %ed-num
  (fn (_ s i)
    (def go
      (fn (self i have value minus)
        (let ((j (%ed-skip s i)))
          (let ((t (%ed-term s j)))
            (match
              ((eq? t #f) #f)
              ((null? t) (list j have value))
              (#t (let ((v (+ value (if minus (- 0 (first (rest t))) (first (rest t)))))
                        (k (%ed-skip s (first t))))
                    (match
                      ((= (%ed-at s k) #\-) (self (+ k 1) #t v #t))
                      ((= (%ed-at s k) #\+) (self (+ k 1) #t v #f))
                      (#t (list k #t v))))))))))
    (go i #f 0 #f)))

; a term at J: (J-AFTER VALUE), nil where there is none, #f said
(def %ed-term
  (fn (_ s j)
    (def c (%ed-at s j))
    (match
      ((= c #\.) (list (+ j 1) (%ed-cur)))
      ((= c #\$) (list (+ j 1) (%ed-last)))
      ((= c #\')
        (let ((m (- (%ed-at s (+ j 1)) #\a)))
          (if (if (< m 0) #t (>= m 26)) (%ed-err "bad mark name")
            (list (+ j 2) (vec-ref (%eg 4) m)))))
      ((= c #\/)
        (let ((end (%dp-find s (+ j 1) #\/)))
          (let ((n (%ed-search (substring s (+ j 1) (if (< end 0) (byte-len s) end)) (%ed-cur) (%ed-last))))
            (if (= n 0) #f (list (if (< end 0) (byte-len s) (+ end 1)) n)))))
      ((if (>= c #\0) (<= c #\9) #f)
        (let ((go (fn (self k v) (let ((d (%ed-at s k))) (if (if (>= d #\0) (<= d #\9) #f) (self (+ k 1) (+ (* v 10) (- d #\0))) (list k v))))))
          (go j 0)))
      (#t ()))))

; the line typed with its trailing blanks gone
(def %ed-trim
  (fn (_ s)
    (def go (fn (self n) (if (if (> n 0) (%ed-space? (byte-at s (- n 1))) #f) (self (- n 1)) n)))
    (substring s 0 (go (byte-len s)))))

; the lines typed for a, c and i, put in to become line NUM on, up to a
; line of . or the end of input
(def %ed-add
  (fn (_ num)
    (def go
      (fn (self acc)
        (let ((l (%ed-gets 1025)))
          (if (if (null? l) #t (string=? l ".\n")) (reverse acc) (self (pair l acc))))))
    (if (if (< num 1) #t (> num (+ (%ed-last) 1)))
      (let ((l (%ed-gets 1025)))
        (if (if (null? l) #t (string=? l ".\n")) () (%ed-err "inserting at bad line number")))
      (%ed-insert! num (go ())))))

; the word after a f, r or w command letter at I: "" for none, #f where
; the letter is not followed by a blank
(def %ed-word
  (fn (_ s i what)
    (if (if (< i (byte-len s)) (not (= (byte-at s i) #\space)) #f)
      (%ed-err (string-concat (list "bad " what " command")))
      (substring s (%ed-skip s i) (byte-len s)))))

; one command line; #f where ed is to end
(def %ed-command
  (fn (_ line)
    (do (if (if (= (%ed-cur) 0) (> (%ed-last) 0) #f) (%eg! 2 1) ())
        (let ((a (%ed-num line (%ed-skip line 0))))
          (if (eq? a #f) #t
            (let ((k (%ed-skip line (first a))))
              (if (= (%ed-at line k) #\,)
                (let ((b (%ed-num line (+ k 1))))
                  (if (eq? b #f) #t
                    (%ed-do line (first b) #t (if (first (rest a)) (first (rest (rest a))) 1) #t
                            (if (first (rest b)) (first (rest (rest b))) (%ed-last)))))
                (let ((n1 (if (first (rest a)) (first (rest (rest a))) (%ed-cur))))
                  (%ed-do line k (first (rest a)) n1 #f n1)))))))))

(def %ed-do
  (fn (_ line k have1 n1 have2 n2)
    (def c (%ed-at line k))
    (def i (+ k 1))
    (match
      ((= c #\a) (do (%ed-add (+ n1 1)) #t))
      ((= c #\c) (do (%ed-delete! n1 n2) (%ed-add n1) #t))
      ((= c #\d) (do (%ed-delete! n1 n2) #t))
      ((= c #\f) (do (%ed-f line i) #t))
      ((= c #\i) (do (%ed-add (if (if (not have1) (= (%ed-last) 0) #f) 1 n1)) #t))
      ((= c #\k) (do (%ed-k line i n2) #t))
      ((= c #\l) (do (%ed-print n1 n2 #t) #t))
      ((= c #\p) (do (%ed-print n1 n2 #f) #t))
      ((= c #\q) (%ed-q line i have1))
      ((= c #\r) (do (%ed-r line i have1 n1) #t))
      ((= c #\s) (do (%ed-sub (substring line i (byte-len line)) n1 n2) #t))
      ((= c #\w) (do (%ed-w line i have1 n1 n2) #t))
      ((= c #\z) (do (%ed-z (%ed-at line i)) #t))
      ((= c #\.) (do (if have1 (%ed-err "no arguments allowed") (%ed-print (%ed-cur) (%ed-cur) #f)) #t))
      ((= c #\-) (do (if (%ed-set-cur! (- (%ed-cur) 1)) (%ed-print (%ed-cur) (%ed-cur) #f) ()) #t))
      ((= c #\=) (do (file-write 1 (string-append (%cu-int->str n1) "\n")) #t))
      ((= c 0) (do (if have1 (%ed-print n2 n2 #f)
                     (if (%ed-set-cur! (+ (%ed-cur) 1)) (%ed-print (%ed-cur) (%ed-cur) #f) ())) #t))
      (#t (do (%ed-err "unimplemented command") #t)))))

(def %ed-f
  (fn (_ line i)
    (let ((w (%ed-word line i "file")))
      (match
        ((eq? w #f) ())
        ((> (byte-len w) 0) (%eg! 5 w))
        ((null? (%eg 5)) (file-write 1 "No file name\n"))
        (#t (file-write 1 (string-concat (list "\"" (%eg 5) "\"\n"))))))))

(def %ed-k
  (fn (_ line i n2)
    (let ((j (%ed-skip line i)))
      (let ((m (- (%ed-at line j) #\a)))
        (if (if (< m 0) #t (if (>= m 26) #t (< (+ j 1) (byte-len line)))) (%ed-err "bad mark name")
          (vec-set! (%eg 4) m n2))))))

; q: #f to end, or #t where it was refused or the question answered no
(def %ed-q
  (fn (_ line i have1)
    (match
      ((if have1 #t (< (%ed-skip line i) (byte-len line))) (do (%ed-err "bad quit command") #t))
      ((not (%eg 3)) #f)
      (#t (do (file-write 2 "Really quit? ")
              (let ((a (%ed-gets 16)))
                (if (null? a) #f
                  (not (= (| (%ed-at a (%ed-skip a 0)) 32) #\y)))))))))

(def %ed-r
  (fn (_ line i have1 n1)
    (let ((w (%ed-word line i "read")))
      (match
        ((eq? w #f) ())
        ((= (byte-len w) 0) (%ed-err "no file name"))
        ((%ed-read-file w (+ (if have1 n1 (%ed-last)) 1)) ())
        ((null? (%eg 5)) (%eg! 5 w))
        (#t ())))))

(def %ed-w
  (fn (_ line i have1 n1 n2)
    (let ((w (%ed-word line i "write")))
      (match
        ((eq? w #f) ())
        ((if (= (byte-len w) 0) (null? (%eg 5)) #f) (%ed-err "no file name specified"))
        (#t (let ((file (if (= (byte-len w) 0) (%eg 5) w)))
              (if have1 (%ed-write-file file n1 n2)
                (do (%eg! 3 #f) (%ed-write-file file 1 (%ed-last))))))))))

(def %ed-z
  (fn (_ c)
    (match
      ((= c #\-) (%ed-print (- (%ed-cur) 21) (%ed-cur) #f))
      ((= c #\.) (%ed-print (- (%ed-cur) 11) (+ (%ed-cur) 10) #f))
      (#t (%ed-print (%ed-cur) (+ (%ed-cur) 21) #f)))))

; --- the applet ------------------------------------------------------------------

; ed [-p PROMPT] [-s] [FILE]
(def %cu-ed
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "ed" argv))
    (def p (Opts value o "-p"))
    (def file (let ((ops (Opts operands o))) (if (null? ops) () (first ops))))
    (do (set! %ed (vec-build 10 (fn (_ i) (match ((= i 0) ()) ((= i 1) 0) ((= i 2) 0) ((= i 3) #f)
                                                 ((= i 4) (vec-make 26 0)) ((= i 6) "") ((= i 7) (if (null? p) "" p))
                                                 ((= i 8) (Opts on? o "-s"))
                                                 ((= i 9) (vec-build 3 (fn (_ k) (match ((= k 0) (%cu-pieces "-" stdin-thunk)) ((= k 2) 0) (#t ())))))
                                                 (#t ())))))
        (if (null? file) (%ed-loop)
          (do (%eg! 5 file)
              (if (%ed-read-file file 1) (do (%eg! 3 #f) (%ed-loop)) ())))
        0)))

(def %ed-loop
  (fn (self)
    (do (if (= (byte-len (%eg 7)) 0) () (file-write 2 (%eg 7)))
        (let ((l (%ed-gets 1024)))
          (if (null? l) ()
            (if (%ed-command (%ed-trim l)) (do (%cu-sweep-tick! %cu-sweep-lines) (self)) ()))))))

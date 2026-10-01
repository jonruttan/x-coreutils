; # x-coreutils -- the small tools, as applets
;
; ## cu/vi-ex.x -- vi's searches and colon commands
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; / ? n N, and the colon commands with their addresses, each busybox's
; (editors/vi.c).  A search is for text, not a regular expression, as
; busybox's is with FEATURE_VI_REGEX_SEARCH off: libc's memmem finds it.  The
; last search is kept as busybox keeps it, its direction's byte first.

; --- searching --------------------------------------------------------------

(def %vi-last-search-pattern "")

; busybox's char_search: where PAT next starts from P going DIR (1 or -1),
; through the whole text or, when LIMITED?, the next line only; -1 when it
; does not.  Going back, a match must end before P.
(def %vi-char-search
  (fn (_ p pat dir limited?)
    (if (%vi< 0 dir)
      (%vi-search-on p (if limited? (%vi-next-line p) (%vi- %vi-end 1)) pat)
      (%vi-search-back (if limited? (%vi-prev-line p) 0) p pat))))

; the first PAT starting in [P, STOP)
(def %vi-search-on
  (fn (_ p stop pat)
    (def len (byte-len pat))
    (def room (%vi-min (%vi- (%vi+ stop len) (%vi+ p 1)) (%vi- %vi-end p)))
    (if (if (%vi< p stop) (%vi< (%vi- len 1) room) #f)
      (%vi-find-text p room pat len)
      -1)))
(def %vi-found (fn (_ r) (if (= r 0) -1 (%vi- r %vi-taddr))))

; the first PAT wholly in the ROOM bytes from FROM, or -1; with ignorecase,
; as busybox's strncasecmp, else byte for byte
(def %vi-find-text
  (fn (_ from room pat len)
    (if (%vi-opt? %vi-ic)
      (%vi-find-text-ic from room pat len)
      (%vi-found (%cu-ptr-call %vi-c-memmem (%vi+ %vi-taddr from) room pat len)))))

; the last PAT starting at or after STOP and ending before P
(def %vi-search-back
  (fn (_ stop p pat)
    (%vi-last-match stop (%vi- p stop) pat (byte-len pat) -1)))

(def %vi-last-match
  (fn (self from room pat len best)
    (def at (if (%vi< (%vi- len 1) room) (%vi-find-text from room pat len) -1))
    (if (= at -1) best
      (self (%vi+ at 1) (%vi- room (%vi+ (%vi- at from) 1)) pat len at))))

; / and ?: a pattern typed on the bottom line, or the last one again the new
; way; then as n
(def %vi-cmd-search
  (fn (_ c)
    (def q (%vi-get-input-line (bytes->str (list c))))
    (match
      ((= (byte-len q) 0) ())
      ((= (byte-len q) 1)
        (do (if (= (byte-len %vi-last-search-pattern) 0) ()
              (set! %vi-last-search-pattern
                (string-append q (%vi-bsub %vi-last-search-pattern 1
                                    (%vi- (byte-len %vi-last-search-pattern) 1)))))
            (%vi-search-again 1)))
      (#t (do (set! %vi-last-search-pattern q) (%vi-search-again 1))))))

; n and N: the last search again, the same way or the other; COUNT times, and
; round from the far end of the text when it runs off one end
(def %vi-search-again
  (fn (_ same)
    (def fwd (= (%vi-byte-of %vi-last-search-pattern 0) #\/))
    (def dir (if (= same 1) (if fwd 1 -1) (if fwd -1 1)))
    (if (%vi< (byte-len %vi-last-search-pattern) 2)
      (%vi-status-line-bold! "No previous search")
      (%vi-search-count dir (%vi-pattern-text)))))

; the last search's text, without its direction
(def %vi-pattern-text
  (fn (_)
    (def n (byte-len %vi-last-search-pattern))
    (if (%vi< n 2) "" (%vi-bsub %vi-last-search-pattern 1 (%vi- n 1)))))

; the Nth of a colon command's parts
(def %vi-part
  (fn (self l n) (if (= n 0) (first l) (self (rest l) (%vi- n 1)))))

(def %vi-byte-of
  (fn (_ s i) (if (%vi< i (byte-len s)) (%vi& (byte-at s i) 255) 0)))

(def %vi-search-count
  (fn (self dir pat)
    (def q (%vi-char-search (%vi+ %vi-dot dir) pat dir #f))
    (if (%vi< q 0) (%vi-search-round dir pat) (set! %vi-dot q))
    (set! %vi-cmdcnt (%vi- %vi-cmdcnt 1))
    (if (%vi< 0 %vi-cmdcnt) (self dir pat) ())))

(def %vi-search-round
  (fn (_ dir pat)
    (def q (%vi-char-search (if (%vi< 0 dir) 0 (%vi- %vi-end 1)) pat dir #f))
    (if (%vi< q 0)
      (do (set! %vi-cmdcnt 0) (%vi-status-line-bold! "Pattern not found"))
      (do (set! %vi-dot q)
          (%vi-status-line-bold!
            (if (%vi< 0 dir) "search hit BOTTOM, continuing at TOP"
              "search hit TOP, continuing at BOTTOM"))))))

; --- addresses --------------------------------------------------------------

; busybox's get_one_address: a line number from BUF at I -- . $ 'x /pat/
; ?pat? or digits, with + and - offsets -- the current line by default.
; Answers (I ADDR . GOT?), or nil when a mark or a pattern failed.
(def %vi-get-one-address
  (fn (_ buf i)
    (%vi-address-from buf i #f (%vi-count-lines 0 %vi-dot) 0)))

(def %vi-address-from
  (fn (self buf i got addr sign)
    (def c (%vi-byte-of buf i))
    (match
      ((%vi-blank? c)
        (self buf (%vi+ i 1) got (if got (%vi+ addr sign) addr) (if got 0 sign)))
      ((if got #f (= c #\.)) (self buf (%vi+ i 1) #t addr sign))
      ((if got #f (= c #\$)) (self buf (%vi+ i 1) #t (%vi-count-lines 0 (%vi- %vi-end 1)) sign))
      ((if got #f (= c #\')) (%vi-address-mark self buf i sign))
      ((if got #f (if (= c #\/) #t (= c #\?))) (%vi-address-search self buf i c sign))
      ((%vi-digit? c) (%vi-address-number self buf i got addr sign))
      ((if (= c #\-) #t (= c #\+))
        (self buf (%vi+ i 1) #t (if got (%vi+ addr sign) addr) (if (= c #\-) -1 1)))
      (#t (pair i (pair (%vi+ addr sign) got))))))

(def %vi-address-number
  (fn (_ walk buf i got addr sign)
    (def j (%vi-digits-end i buf))
    (def num (%vi-num-from buf i j 0))
    (walk buf j #t (if got (%vi+ addr (if (%vi< sign 0) (%vi- 0 num) num)) num) 0)))

(def %vi-address-mark
  (fn (_ walk buf i sign)
    (def c (%vi| (%vi-byte-of buf (%vi+ i 1)) 32))
    (def q (if (%vi-in? c #\a #\z) (%vi-mark (%vi- c #\a)) -1))
    (if (%vi< q 0)
      (do (%vi-status-line-bold! "Mark not set") ())
      (walk buf (%vi+ i 2) #t (%vi-count-lines 0 q) sign))))

; /pat/ and ?pat?: the next line holding the pattern, round from the far end
; of the text; an empty pattern is the last one
(def %vi-address-search
  (fn (_ walk buf i c sign)
    (def q (%vi-char-at buf (%vi+ i 1) c))
    (if (= q (%vi+ i 1)) ()
      (set! %vi-last-search-pattern (%vi-bsub buf i (%vi- q i))))
    (def next (if (= (%vi-byte-of buf q) c) (%vi+ q 1) q))
    (def dir (if (= c #\/) 1 -1))
    (def pat (%vi-pattern-text))
    (def from (if (= c #\/) (%vi-next-line %vi-dot) (%vi-begin-line %vi-dot)))
    (def found (%vi-address-find from pat dir))
    (if (%vi< found 0)
      (do (%vi-status-line-bold! "Pattern not found") ())
      (walk buf next #t (%vi-count-lines 0 found) sign))))

(def %vi-address-find
  (fn (_ from pat dir)
    (def q (%vi-char-search from pat dir #f))
    (if (%vi< q 0) (%vi-char-search (if (%vi< 0 dir) 0 (%vi- %vi-end 1)) pat dir #f) q)))

; where C next is in BUF from I, or the end of BUF
(def %vi-char-at
  (fn (self buf i c)
    (if (if (%vi< i (byte-len buf)) (if (= (%vi-byte-of buf i) c) #f #t) #f)
      (self buf (%vi+ i 1) c)
      i)))

; busybox's get_address: the addresses before a colon command, as many as
; typed, the last two kept -- % for them all, , between two and ; to move to
; the first before reading the second.  Answers (I B E . GOT), GOT's bit 0 an
; address given and bit 1 two, or nil on an error.
(def %vi-get-address
  (fn (_ buf i)
    (def save %vi-dot)
    (def r (%vi-addresses buf i #t -1 -1 0))
    (set! %vi-dot save)
    r))

(def %vi-addresses
  (fn (self buf i want-addr? b e got)
    (def c (%vi-byte-of buf i))
    (match
      ((%vi-blank? c) (self buf (%vi+ i 1) want-addr? b e got))
      ((if want-addr? (= c #\%) #f)
        (self buf (%vi+ i 1) #f 1 (%vi-count-lines 0 (%vi- %vi-end 1)) 3))
      (want-addr? (%vi-address-next self buf i b e got))
      ((if (= c #\,) #t (= c #\;))
        (do (if (= c #\;) (set! %vi-dot (%vi-find-line e)) ())
            (self buf (%vi+ i 1) #t b e got)))
      (#t (list i b e got)))))

(def %vi-address-next
  (fn (_ walk buf i b e got)
    (def a (%vi-get-one-address buf i))
    (if (null? a) ()
      (%vi-address-took walk buf (first a) (first (rest a)) (rest (rest a)) b e got))))

(def %vi-address-took
  (fn (_ walk buf j addr valid? b e got)
    (def c (%vi-byte-of buf j))
    (if (match (valid? #t) ((= c #\,) #t) ((= c #\;) #t) (#t (= (%vi& got 1) 1)))
      (walk buf j #f e addr (%vi| (%vi* got 2) 1))
      (list j b e got))))

; --- the colon commands -----------------------------------------------------

; busybox's colon: addresses, a command of up to nine bytes with a ! to force
; it, and its argument
(def %vi-colon
  (fn (_ buf)
    (def s (%vi-skip-blanks (%vi-skip-colons 0 buf) buf))
    (if (if (%vi< s (byte-len buf)) (if (= (byte-at buf s) #\") #f #t) #f)
      (%vi-colon-addressed buf (%vi-get-address buf s))
      ())
    (set! %vi-dot (%vi-bound-dot %vi-dot))))

(def %vi-colon-addressed
  (fn (_ buf a)
    (if (null? a) ()
      (%vi-colon-parts buf (first a) (first (rest a)) (first (rest (rest a)))
        (first (rest (rest (rest a))))))))

(def %vi-colon-parts
  (fn (_ buf i b e got)
    (def w (%vi-skip-word i buf))
    (def word (%vi-bsub buf i (%vi-min 9 (%vi- w i))))
    (def n (byte-len word))
    (def force? (if (%vi< 0 n) (= (byte-at word (%vi- n 1)) #\!) #f))
    (def cmd (if (if force? (%vi< 1 n) #f) (%vi-bsub word 0 (%vi- n 1)) word))
    (def a (%vi-skip-blanks w buf))
    (def args (%vi-bsub buf a (%vi- (byte-len buf) a)))
    (%vi-colon-range (list buf cmd args force? (%vi< 0 (%vi& got 1)) (= (%vi& got 3) 3) i) b e)))

; the range the addresses name, checked: the whole text when none was given
(def %vi-colon-range
  (fn (_ parts b e)
    (def got? (first (rest (rest (rest (rest parts))))))
    (def range? (first (rest (rest (rest (rest (rest parts)))))))
    (def lines (%vi-count-lines 0 (%vi- %vi-end 1)))
    (match
      ((if got? #f #t) (%vi-colon-cmd parts b e 0 (%vi- %vi-end 1)))
      ((if (%vi< e 0) #t (%vi< lines e)) (%vi-status-line-bold! "Invalid range"))
      ((if range? #f #t)
        (%vi-colon-cmd parts b e (%vi-find-line e) (%vi-end-line (%vi-find-line e))))
      ((match ((%vi< b 0) #t) ((%vi< lines b) #t) (#t (%vi< e b)))
        (%vi-status-line-bold! "Invalid range"))
      (#t (%vi-colon-cmd parts b e (%vi-find-line b) (%vi-end-line (%vi-find-line e)))))))

(def %vi-colon-cmd
  (fn (_ parts b e q r)
    (def buf (first parts))
    (def cmd (first (rest parts)))
    (def args (first (rest (rest parts))))
    (def force? (first (rest (rest (rest parts)))))
    (def got? (first (rest (rest (rest (rest parts))))))
    (def c0 (%vi-byte-of cmd 0))
    (match
      ((= (byte-len cmd) 0)
        (if (%vi< e 0) () (do (set! %vi-dot (%vi-find-line e)) (%vi-dot-skip-over-ws!))))
      ((= c0 #\!) (%vi-colon-shell buf (%vi-part parts 6) got?))
      ((if (= c0 #\=) (= (byte-len cmd) 1) #f)
        (%vi-status-line! (%cu-int->str (if got? e (%vi-count-lines 0 %vi-dot)))))
      ((%vi-prefix? cmd "delete") (%vi-colon-delete got? q r))
      ((%vi-prefix? cmd "edit") (%vi-colon-edit cmd args force?))
      ((%vi-prefix? cmd "file") (%vi-colon-file args e))
      ((%vi-prefix? cmd "features") (%vi-colon-features))
      ((%vi-prefix? cmd "list") (%vi-colon-list got? q r))
      ((%vi-one-of-prefix? cmd (list "quit" "next" "prev")) (%vi-colon-quit cmd force?))
      ((%vi-prefix? cmd "read") (%vi-colon-read args e got?))
      ((%vi-prefix? cmd "rewind") (%vi-colon-rewind cmd force?))
      ((if (%vi-prefix? cmd "set") (%vi< 1 (byte-len cmd)) #f) (%vi-colon-set args))
      ((= c0 #\s) (%vi-colon-substitute buf (%vi-part parts 6) got? (%vi-part parts 5) b e q))
      ((%vi-prefix? cmd "version") (%vi-status-line! (%vi-bundle-version)))
      ((%vi-write-cmd? cmd) (%vi-colon-write cmd args force? q r))
      ((%vi-prefix? cmd "yank") (%vi-colon-yank got? q r))
      (#t (%vi-not-implemented cmd)))))

(def %vi-one-of-prefix?
  (fn (self cmd names)
    (match
      ((null? names) #f)
      ((%vi-prefix? cmd (first names)) #t)
      (#t (self cmd (rest names))))))

; CMD a prefix of NAME, as busybox's strncmp over CMD's length
(def %vi-prefix?
  (fn (_ cmd name)
    (if (%vi< (byte-len name) (byte-len cmd)) #f
      (string=? cmd (%vi-bsub name 0 (byte-len cmd))))))

; :w and what abbreviates it, :wq, :wn and :x
(def %vi-write-cmd?
  (fn (_ cmd)
    (match
      ((%vi-prefix? cmd "write") #t)
      ((string=? cmd "wq") #t)
      ((string=? cmd "wn") #t)
      (#t (string=? cmd "x")))))

; the line Q through R as the current line when no address was given
(def %vi-or-this-line
  (fn (_ got? q r)
    (if got? (pair q r) (pair (%vi-begin-line %vi-dot) (%vi-end-line %vi-dot)))))

; :d -- the lines into the register and out
(def %vi-colon-delete
  (fn (_ got? q r)
    (def qr (%vi-or-this-line got? q r))
    (set! %vi-dot (%vi-yank-delete (first qr) (rest qr) 1 #t %vi-allow-undo))
    (%vi-dot-skip-over-ws!)))

; :ya -- the lines into the register, counted on the status line
(def %vi-colon-yank
  (fn (_ got? q r)
    (def qr (%vi-or-this-line got? q r))
    (%vi-text-yank! (first qr) (rest qr) %vi-ydreg 1)
    (%vi-status-line!
      (string-concat
        (list "Yank " (%cu-int->str (%vi-count-lines (first qr) (rest qr)))
              " lines (" (%cu-int->str (byte-len (first (%vi-reg %vi-ydreg))))
              " chars) into [" (bytes->str (list (%vi-what-reg))) "]")))))

; :l -- the first line of the range spelled out, a newline as $
(def %vi-colon-list
  (fn (_ got? q r)
    (def qr (%vi-or-this-line got? q r))
    (%vi-status-line! (string-concat (reverse (%vi-listed (first qr) (rest qr) ()))))))

(def %vi-listed
  (fn (self q r acc)
    (def c (%vi-byte q))
    (match
      ((if (%vi< r q) #t (%vi< 188 (%vi-list-len acc 0))) acc)
      ((= c #\newline) (pair "$" acc))
      ((%vi< #\delete c) (self (%vi+ q 1) r (pair (string-append %vi-bold "." %vi-norm) acc)))
      (#t (self (%vi+ q 1) r (pair (%vi-literal-byte c) acc))))))

(def %vi-list-len
  (fn (self l n) (if (null? l) n (self (rest l) (%vi+ n (byte-len (first l)))))))

; :q :n :prev -- the end of this file's editing, the next or the one before;
; refused while it is changed, unless forced
(def %vi-colon-quit
  (fn (_ cmd force?)
    (def c (%vi-byte-of cmd 0))
    (def more (%vi- (%vi- (length %vi-files) %vi-optind) 1))
    (match
      (force? (do (if (= c #\q) (set! %vi-optind (length %vi-files)) ()) (set! %vi-editing 0)))
      ((%vi< 0 %vi-modified)
        (%vi-status-line-bold! (string-append "No write since last change (:" cmd "! overrides)")))
      ((if (= c #\q) (%vi< 0 more) #f)
        (%vi-status-line-bold! (string-append (%cu-int->str more) " more file(s) to edit")))
      ((if (= c #\n) (%vi< more 1) #f) (%vi-status-line-bold! "No more files to edit"))
      ((if (= c #\p) (%vi< %vi-optind 1) #f) (%vi-status-line-bold! "No previous files to edit"))
      (#t (do (if (= c #\p) (set! %vi-optind (%vi- %vi-optind 2)) ()) (set! %vi-editing 0))))))

; :rew -- back to the first file
(def %vi-colon-rewind
  (fn (_ cmd force?)
    (if (if (%vi< 0 %vi-modified) (if force? #f #t) #f)
      (%vi-status-line-bold! (string-append "No write since last change (:" cmd "! overrides)"))
      (do (set! %vi-optind -1) (set! %vi-editing 0)))))

; :f -- the file's status again, or a new name for it
(def %vi-colon-file
  (fn (_ args e)
    (match
      ((%vi< -1 e) (%vi-status-line-bold! "No address allowed on this command"))
      ((%vi< 0 (byte-len args)) (%vi-expanded args %vi-update-filename!))
      (#t (set! %vi-last-status ())))))

; busybox's expand_args: % the file's name, # the one before, \ the next byte
; as itself -- and the byte after that as itself too, since busybox's loop
; steps past it; then THEN with the name, or nothing when % or # has none
(def %vi-expanded
  (fn (_ args then)
    (def x (%vi-expand-from args 0 ()))
    (if (null? x) (%vi-status-line-bold! "No previous filename") (then x))))

(def %vi-expand-from
  (fn (self s i acc)
    (def c (%vi-byte-of s i))
    (match
      ((if (%vi< i (byte-len s)) #f #t) (string-concat (reverse acc)))
      ((= c #\%) (%vi-expand-name self s i acc %vi-filename))
      ((= c #\#) (%vi-expand-name self s i acc %vi-alt-filename))
      ((if (= c #\\) (%vi< (%vi+ i 1) (byte-len s)) #f)
        (self s (%vi+ i 3)
          (pair (%vi-bsub s (%vi+ i 1) (%vi-min 2 (%vi- (byte-len s) (%vi+ i 1)))) acc)))
      (#t (self s (%vi+ i 1) (pair (%vi-bsub s i 1) acc))))))

(def %vi-expand-name
  (fn (_ walk s i acc name)
    (if (null? name) () (walk s (%vi+ i 1) (pair name acc)))))

; the file names: the one edited and the one before it
(def %vi-alt-filename ())

; busybox's update_filename: a new name for the file, the old one kept as #
(def %vi-update-filename!
  (fn (_ name)
    (if (null? name) ()
      (if (if (null? %vi-filename) #t (if (string=? name %vi-filename) #f #t))
        (do (set! %vi-alt-filename %vi-filename) (set! %vi-filename name))
        ()))))

; busybox's init_filename: a name given to :w or :r names the file when it had
; none, and is # otherwise
(def %vi-init-filename!
  (fn (_ name)
    (if (null? %vi-filename) (set! %vi-filename name) (set! %vi-alt-filename name))))

; :e -- another file, or this one read again
(def %vi-colon-edit
  (fn (_ cmd args force?)
    (match
      ((if (%vi< 0 %vi-modified) (if force? #f #t) #f)
        (%vi-status-line-bold! (string-append "No write since last change (:" cmd "! overrides)")))
      ((%vi< 0 (byte-len args)) (%vi-expanded args %vi-edit-name))
      ((null? %vi-filename) (%vi-status-line-bold! "No current filename"))
      (#t (%vi-edit-name %vi-filename)))))

(def %vi-edit-name
  (fn (_ name)
    (def size (%vi-init-text-buffer! name))
    (Vector set! 27 () %vi-regs)
    (Vector set! %vi-ydreg () %vi-regs)
    (set! %vi-cur-line -1)
    (%vi-status-line!
      (string-concat
        (list "'" name "'" (if (%vi< size 0) " [New file]" "")
              (if (= %vi-readonly 0) "" " [Readonly]")
              " " (%cu-int->str (%vi-count-lines 0 (%vi- %vi-end 1))) "L, "
              (%cu-int->str %vi-end) "C")))))

; :r -- a file's bytes after the addressed line, or the current one
(def %vi-colon-read
  (fn (_ args e got?)
    (match
      ((%vi< 0 (byte-len args))
        (%vi-expanded args (fn (_ name) (%vi-init-filename! name) (%vi-read-name name e got?))))
      ((null? %vi-filename) (%vi-status-line-bold! "No current filename"))
      (#t (%vi-read-name %vi-filename e got?)))))

(def %vi-read-name
  (fn (_ name e got?)
    (def q0 (if (= e 0) 0 (%vi-next-line (if got? (%vi-find-line e) %vi-dot))))
    (def q (if (if (= e 0) #f (= q0 (%vi- %vi-end 1))) (%vi+ q0 1) q0))
    (def num (%vi+ (%vi-count-lines 0 q) (if (= q %vi-end) 1 0)))
    (def size (%vi-file-insert name q #f))
    (if (%vi< size 0) ()
      (do (%vi-status-line!
            (string-concat
              (list "'" name "'" (if (= %vi-readonly 0) "" " [Readonly]")
                    " " (%cu-int->str (%vi-count-lines q (%vi+ q (%vi- size 1)))) "L, "
                    (%cu-int->str size) "C")))
          (set! %vi-dot (%vi-find-line num))))))

; :w :wq :wn :x -- the range into a file.  A name given must not be another
; file already there unless forced; a read-only file is written only when
; forced; :x writes only a changed text.
(def %vi-colon-write
  (fn (_ cmd args force? q r)
    (match
      ((%vi< 0 (byte-len args))
        (%vi-expanded args (fn (_ name) (%vi-write-named cmd name force? q r))))
      ((match ((= %vi-readonly 0) #f) (force? #f) (#t (if (null? %vi-filename) #f #t)))
        (%vi-status-line-bold! (string-append "'" %vi-filename "' is read only")))
      (#t (%vi-write-to cmd %vi-filename force? q r)))))

(def %vi-write-named
  (fn (_ cmd name force? q r)
    (if (if force? #f (%vi-other-file? name))
      (%vi-status-line-bold! "File exists (:w! overrides)")
      (do (%vi-init-filename! name) (%vi-write-to cmd name force? q r)))))

(def %vi-other-file?
  (fn (_ name)
    (if (if (null? %vi-filename) #f (string=? %vi-filename name)) #f
      (file-exists? name))))

(def %vi-write-to
  (fn (_ cmd name force? q r)
    (def write? (if (= %vi-modified 0) (if (= (%vi-byte-of cmd 0) #\x) #f #t) #t))
    (def size (if write? (%vi+ (%vi- r q) 1) 0))
    (def l (if write? (if (null? name) -2 (%vi-file-write name q (%vi+ r 1))) 0))
    (match
      ((Err err? l) (%vi-status-line-bold! (string-append "'" name "' " (file-err-text l))))
      ((= l -2) (%vi-status-line-bold! "No current filename"))
      (#t (%vi-written cmd name force? q l size)))))

(def %vi-written
  (fn (_ cmd name force? q l size)
    (%vi-status-line!
      (string-concat
        (list "'" name "' "
              (%cu-int->str (%vi-count-lines q (%vi-max q (%vi- (%vi+ q l) 1)))) "L, "
              (%cu-int->str l) "C")))
    (if (= l size)
      (do (if (if (= q 0) (= (%vi+ q l) %vi-end) #f) (set! %vi-modified 0) ())
          (%vi-written-ends cmd force?))
      ())))

; :wn goes on to the next file; :wq and :x end, unless files are left to edit
(def %vi-written-ends
  (fn (_ cmd force?)
    (def c1 (%vi-byte-of cmd 1))
    (def more (%vi- (%vi- (length %vi-files) %vi-optind) 1))
    (match
      ((= c1 #\n) (set! %vi-editing 0))
      ((if (= (%vi-byte-of cmd 0) #\x) #t (= c1 #\q))
        (match
          ((if (%vi< 0 more) (if force? #f #t) #f)
            (%vi-status-line-bold! (string-append (%cu-int->str more) " more file(s) to edit")))
          (#t (do (if (%vi< 0 more) (set! %vi-optind (length %vi-files)) ())
                  (set! %vi-editing 0)))))
      (#t ()))))

; :s/find/replace/g -- the pattern replaced on each line of the range, the
; first on a line or, with g, each; an empty pattern is the last search
(def %vi-colon-substitute
  (fn (_ buf start got? range? b e q)
    (def s (%vi-skip-blanks (%vi+ start 1) buf))
    (def delim (%vi-byte-of buf s))
    (def mid (%vi-char-at buf (%vi+ s 1) delim))
    (if (%vi< mid (byte-len buf))
      (%vi-substitute-parts buf got? range? b e q (%vi+ s 1) mid delim)
      (%vi-status-line! ":s expression missing delimiters"))))

(def %vi-substitute-parts
  (fn (_ buf got? range? b e q f mid delim)
    (def fl (%vi-char-at buf (%vi+ mid 1) delim))
    (def find (%vi-bsub buf f (%vi- mid f)))
    (def repl (%vi-bsub buf (%vi+ mid 1) (%vi- fl (%vi+ mid 1))))
    (def g? (if (%vi< fl (byte-len buf)) (= (%vi-byte-of buf (%vi+ fl 1)) #\g) #f))
    (match
      ((%vi< 0 (byte-len find))
        (do (set! %vi-last-search-pattern (string-append "/" find))
            (%vi-substitute-lines got? range? b e q find repl g?)))
      ((%vi< (byte-len %vi-last-search-pattern) 2) (%vi-status-line-bold! "No previous search"))
      (#t (%vi-substitute-lines got? range? b e q
            (%vi-pattern-text)
            repl g?)))))

(def %vi-substitute-lines
  (fn (_ got? range? b e q find repl g?)
    (def here (%vi-begin-line %vi-dot))
    (def from (if got? q here))
    (def first-line (if got? (if range? b e) (%vi-count-lines 0 here)))
    (def last-line (if got? e first-line))
    (def res (%vi-sub-line from first-line last-line find repl g? 0 0 -1))
    (match
      ((= (first res) 0) (%vi-status-line-bold! "No match"))
      (#t (do (%vi-dot-skip-over-ws!)
              (if (%vi< 1 (first res))
                (%vi-status-line!
                  (string-concat
                    (list (%cu-int->str (first res)) " substitutions on "
                          (%cu-int->str (rest res)) " lines")))
                ()))))))

; line I of the range starting at Q; answers (SUBS . LINES)
(def %vi-sub-line
  (fn (self q i e find repl g? subs lines last)
    (if (%vi< e i) (pair subs lines)
      (%vi-sub-in-line self q q i e find repl g? subs lines last))))

(def %vi-sub-in-line
  (fn (_ walk ls q i e find repl g? subs lines last)
    (def found (%vi-char-search q find 1 #t))
    (if (%vi< found 0)
      (walk (%vi-next-line ls) (%vi+ i 1) e find repl g? subs lines last)
      (%vi-sub-at walk ls found i e find repl g? subs lines last))))

(def %vi-sub-at
  (fn (_ walk ls found i e find repl g? subs lines last)
    (%vi-hole-delete! found (%vi- (%vi+ found (byte-len find)) 1)
      (if (= subs 0) %vi-allow-undo %vi-allow-undo-chain))
    (if (%vi< 0 (byte-len repl)) (%vi-string-insert! found repl %vi-allow-undo-chain) ())
    (set! %vi-dot ls)
    (def lines2 (if (= last i) lines (%vi+ lines 1)))
    (def after (%vi+ found (byte-len repl)))
    (if (if g? (%vi< after (%vi-end-line ls)) #f)
      (%vi-sub-in-line walk ls after i e find repl g? (%vi+ subs 1) lines2 i)
      (walk (%vi-next-line ls) (%vi+ i 1) e find repl g? (%vi+ subs 1) lines2 i))))

; :features -- the list -H gives, with the terminal cooked, and a Return
; waited for after
(def %vi-colon-features
  (fn (_)
    (%vi-bottom-clear)
    (%vi-flush!)
    (%vi-cooked!)
    (%vi-show-help)
    (%vi-raw!)
    (%vi-hit-return "")))

; :version's answer, where busybox gives its own: the version x-coreutils was
; installed as, from the file make install writes into the bundle; a
; checkout has none, and is dev, as make's own fallback says.  x.sh defines
; %lang-root, the bundle's directory, before the entry runs; where it is
; not defined, there is no version file to find.
; lint-known: %lang-root
(def %vi-bundle-version
  (fn (_)
    (def root (guard (_ ()) %lang-root))
    (def path (if (null? root) () (%vi-path-join root "version")))
    (if (if (null? path) #f (file-exists? path))
      (%vi-first-line (file-read-all path))
      "dev")))

(def %vi-first-line
  (fn (_ s)
    (def nl (%vi-byte-index s #\newline 0))
    (if (%vi< nl 0) s (%vi-bsub s 0 nl))))

; --- the commands run at the start -------------------------------------------

(def %vi-initial-cmds ())   ; -c's commands, until the first file is in

; busybox's vi_main: $EXINIT's commands, or when it is not set ~/.exrc's --
; a .exrc of the user's own that no one else may write -- run on an empty
; text before the first file is read
(def %vi-startup-cmds!
  (fn (_)
    (def exinit (%vi-getenv "EXINIT"))
    (def cmds (if (null? exinit) (%vi-exrc-cmds) exinit))
    (if (null? cmds) () (do (%vi-init-text-buffer! ()) (%vi-run-cmds cmds)))))

(def %vi-exrc-cmds
  (fn (_)
    (def home (%vi-getenv "HOME"))
    (if (if (null? home) #t (= (byte-len home) 0)) ()
      (%vi-exrc-read (%vi-path-join home ".exrc")))))

(def %vi-exrc-read
  (fn (_ path)
    (def st (file-stat-full path))
    (match
      ((null? st) ())
      ((if (= (%vi& (Assoc get (lit mode) st) 18) 0) (= (%cu-stat-get st (lit uid)) (sys-getuid)) #f)
        (file-read-all path))
      (#t (do (%vi-status-line-bold! ".exrc: permission denied") ())))))

; busybox's concat_path_file: one / between, none added after a trailing one
(def %vi-path-join
  (fn (_ dir name)
    (if (= (byte-at dir (%vi- (byte-len dir) 1)) #\/) (string-append dir name)
      (string-concat (list dir "/" name)))))

; busybox's run_cmds: each line of S a colon command, a run of newlines one
; break
(def %vi-run-cmds
  (fn (self s)
    (def nl (%vi-byte-index s #\newline 0))
    (if (%vi< nl 0) (%vi-colon s)
      (do (%vi-colon (%vi-bsub s 0 nl))
          (self (%vi-bsub s (%vi-past-newlines s nl) (%vi- (byte-len s) (%vi-past-newlines s nl))))))))

(def %vi-past-newlines
  (fn (self s i)
    (if (if (%vi< i (byte-len s)) (= (byte-at s i) #\newline) #f) (self s (%vi+ i 1)) i)))

(def %vi-byte-index
  (fn (self s b i)
    (match
      ((if (%vi< i (byte-len s)) #f #t) -1)
      ((= (byte-at s i) b) i)
      (#t (self s b (%vi+ i 1))))))

; busybox's edit_file: -c's commands, as the first file is in
(def %vi-initial-cmds-run!
  (fn (self)
    (if (null? %vi-initial-cmds) () (%vi-initial-cmd-pop! self (first %vi-initial-cmds)))))
(def %vi-initial-cmd-pop!
  (fn (_ again c)
    (set! %vi-initial-cmds (rest %vi-initial-cmds))
    (%vi-run-cmds c)
    (again)))

; --- :! ---------------------------------------------------------------------

; :!CMD -- the rest of the line after the ! run by the shell, % and # in it
; named and its backslashes taken off, as busybox's expand_args does; the
; terminal cooked while it runs, a status other than 0 told, and a Return
; waited for after
(def %vi-colon-shell
  (fn (_ buf i got?)
    (if got? (%vi-status-line-bold! "Range not allowed")
      (%vi-expanded (%vi-bsub buf (%vi+ i 1) (%vi- (byte-len buf) (%vi+ i 1))) %vi-shell-run))))

(def %vi-shell-run
  (fn (_ cmd)
    (%vi-bottom-clear)
    (%vi-flush!)
    (%vi-cooked!)
    (%vi-shell-ran (%vi-shell cmd))))

(def %vi-shell-ran
  (fn (_ st)
    (if (= st 0) ()
      (%vi-put (string-concat (list "\nshell returned " (%cu-int->str st) "\n\n"))))
    (%vi-raw!)
    (%vi-hit-return "")))

; the command run as busybox runs it, by libc's system: /bin/sh -c CMD, with
; this process waiting and SIGINT and SIGQUIT ignored the while; the status
; as system answers it, an exit status times 256
(def %vi-tty-shell
  (fn (_ cmd) (Sys %sign-fold (%cu-ptr-call %vi-c-system cmd))))

; in a spec, the command's output is drawn where vi draws, so the case sees
; it: fds 1 and 2 go to a file while it runs, stdin comes from /dev/null, and
; the file's bytes go to the sink after
(def %vi-typed-shell
  (fn (_ cmd)
    (def out (string-append "/tmp/x-cu-vi-shell." (%cu-int->str (Sys getpid))))
    (%vi-fds-aside! out)
    (def st (%vi-tty-shell cmd))
    (%vi-fds-back!)
    (%vi-sink (file-read-all out))
    (file-unlink out)
    st))

; fds 0, 1 and 2 kept on 60 to 62, and the command's put in their place
(def %vi-fds-aside!
  (fn (_ out)
    (Sys dup2 0 60)
    (Sys dup2 1 61)
    (Sys dup2 2 62)
    (def fd (File open out (list (lit wronly) (lit creat) (lit trunc)) 384))
    (Sys dup2 fd 1)
    (Sys dup2 fd 2)
    (Sys close fd)
    (def nul (File open "/dev/null" (lit rdonly)))
    (Sys dup2 nul 0)
    (Sys close nul)))

(def %vi-fds-back!
  (fn (_)
    (Sys dup2 60 0)
    (Sys dup2 61 1)
    (Sys dup2 62 2)
    (Sys close 60)
    (Sys close 61)
    (Sys close 62)))

; --- small readers ----------------------------------------------------------

(def %vi-skip-colons
  (fn (self i buf)
    (if (if (%vi< i (byte-len buf)) (= (byte-at buf i) #\:) #f) (self (%vi+ i 1) buf) i)))
(def %vi-skip-blanks
  (fn (self i buf)
    (if (if (%vi< i (byte-len buf)) (%vi-space? (byte-at buf i)) #f) (self (%vi+ i 1) buf) i)))
(def %vi-skip-word
  (fn (self i buf)
    (if (if (%vi< i (byte-len buf)) (if (%vi-space? (byte-at buf i)) #f #t) #f)
      (self (%vi+ i 1) buf)
      i)))
(def %vi-digits-end
  (fn (self i buf)
    (if (if (%vi< i (byte-len buf)) (%vi-digit? (byte-at buf i)) #f) (self (%vi+ i 1) buf) i)))
(def %vi-num-from
  (fn (self s i j n)
    (if (%vi< i j)
      (self s (%vi+ i 1) j (%vi+ (%vi* n 10) (%vi- (byte-at s i) #\0)))
      n)))

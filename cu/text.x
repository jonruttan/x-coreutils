; # x-coreutils -- the small tools, as applets
;
; ## cu/text.x -- the line tools
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; sort uniq head tail cat wc comm join basename dirname.  An applet is
; (fn (_ argv stdin-thunk) -> status); output goes to stdout, and the
; shared %cu-gather answers the operands' concatenated text (stdin when
; none, - meaning stdin among them).

; --- shared helpers ----------------------------------------------------------

; the byte B as a one-byte string.  bytes->str packs the byte itself; a
; character of that code would be written in UTF-8, as two bytes above 0x7F.
(def %cu-b->s
  (fn (_ b) (bytes->str (list b))))

(def %cu-lines-go
  (fn (self s end i start acc)
    (if (>= i end)
      (if (> i start)
        (reverse (pair (substring s start i) acc))
        (reverse acc))
      (if (= (byte-at s i) 10)
        (self s end (+ i 1) (+ i 1) (pair (substring s start i) acc))
        (self s end (+ i 1) start acc)))))
(def %cu-lines
  (fn (_ s) (%cu-lines-go s (byte-len s) 0 0 ())))

; --- the inputs head and tail read --------------------------------------------
;
; Each operand is read whole and handed to SHOW as (NAME TEXT FILE?), in order;
; `-`, and no operand at all, is standard input, shown under that name.  Under
; HEAD? a header comes first, with a blank line before every header but the
; first one printed.  A file that cannot be opened is named on stderr with the
; reason and gets no header; one that opens and cannot be read -- a directory --
; gets its header, then the reason.  Answers 1 when an operand failed, else 0.
(def %cu-each-input
  (fn (_ applet ops stdin-thunk head? show)
    (if (null? ops)
      (do (%cu-input-header head? "standard input" #t)
          (show "standard input" (stdin-thunk) #f)
          0)
      (%cu-each-input-from applet ops stdin-thunk head? show #t 0))))

(def %cu-each-input-from
  (fn (self applet ops stdin-thunk head? show first? st)
    (if (null? ops) st
      (let ((name (first ops)))
        (if (string=? name "-")
          (do (%cu-input-header head? "standard input" first?)
              (show "standard input" (stdin-thunk) #f)
              (self applet (rest ops) stdin-thunk head? show #f st))
          (let ((text (file-or-err (fn (_) (file-read-all name)))))
            (match
              ((not (Err err? text))
                (do (%cu-input-header head? name first?)
                    (show name text #t)
                    (self applet (rest ops) stdin-thunk head? show #f st)))
              ((eq? (file-err-op text) (lit read))
                (do (%cu-input-header head? name first?)
                    (file-write 2
                      (string-concat
                        (list applet ": error reading '" name "': "
                              (file-err-text text) "\n")))
                    (self applet (rest ops) stdin-thunk head? show #f 1)))
              (#t
                (do (file-write 2
                      (string-concat
                        (list applet ": cannot open '" name "' for reading: "
                              (file-err-text text) "\n")))
                    (self applet (rest ops) stdin-thunk head? show first? 1))))))))))

(def %cu-input-header
  (fn (_ head? name first?)
    (if head?
      (display (string-concat (list (if first? "" "\n") "==> " name " <==\n")))
      ())))

(def %cu-print-lines
  (fn (self ls)
    (if (null? ls) ()
      (do (display (string-append (first ls) "\n"))
          (self (rest ls))))))

(def %cu-str<
  (fn (_ a b)
    (def la (byte-len a))
    (def lb (byte-len b))
    (def go
      (fn (self i)
        (if (>= i la) (< la lb)
          (if (>= i lb) #f
            (let ((ca (byte-at a i)) (cb (byte-at b i)))
              (if (< ca cb) #t
                (if (> ca cb) #f (self (+ i 1)))))))))
    (go 0)))

; merge sort: n log n, shallow recursion
(def %cu-merge
  (fn (self a b less?)
    (match
      ((null? a) b)
      ((null? b) a)
      ((less? (first b) (first a)) (pair (first b) (self a (rest b) less?)))
      (#t (pair (first a) (self (rest a) b less?))))))
(def %cu-msort
  (fn (self l less?)
    (if (null? l) ()
      (if (null? (rest l)) l
        (let ((split (let ((go (fn (self2 slow fast acc)
                                 (if (if (pair? fast) (pair? (rest fast)) #f)
                                   (self2 (rest slow) (rest (rest fast))
                                     (pair (first slow) acc))
                                   (pair (reverse acc) slow)))))
                       (go l l ()))))
          (%cu-merge (self (first split) less?)
            (self (rest split) less?) less?))))))

; a leading number for sort -n: optional blanks, sign, digits[.digits]
(def %cu-num-prefix
  (fn (_ s)
    (def end (byte-len s))
    (def i0 (let ((go (fn (self i)
                        (if (>= i end) i
                          (let ((b (byte-at s i)))
                            (if (if (= b 32) #t (= b 9)) (self (+ i 1)) i))))))
              (go 0)))
    (def neg (if (< i0 end) (= (byte-at s i0) 45) #f))
    (def i1 (if neg (+ i0 1) i0))
    (def ir (let ((go (fn (self i acc any)
                        (if (>= i end) (pair acc any)
                          (let ((b (byte-at s i)))
                            (if (if (>= b 48) (<= b 57) #f)
                              (self (+ i 1) (+ (* acc 10) (- b 48)) #t)
                              (pair acc any)))))))
              (go i1 0 #f)))
    (if (not (rest ir)) 0
      (if neg (- 0 (first ir)) (first ir)))))

; N in decimal.  Its digits are packed as bytes by bytes->str, at a third of
; what the list->string conversion costs; the tower's % and / keep a bignum
; right.
(def %cu-int->str
  (fn (_ n)
    (if (= n 0) "0"
      (let ((go (fn (self t acc)
                  (if (= t 0) acc
                    (self (/ (- t (% t 10)) 10) (pair (+ 48 (% t 10)) acc))))))
        (if (< n 0)
          (bytes->str (pair 45 (go (- 0 n) ())))
          (bytes->str (go n ())))))))

; S padded to W columns with spaces, before it or after it.  %str-make-raw
; answers a run of spaces in one allocation, where a space at a time was one
; string-append each.
(def %cu-pad-left
  (fn (_ s w)
    (def gap (- w (byte-len s)))
    (if (<= gap 0) s (string-append (%str-make-raw gap) s))))

(def %cu-pad-right
  (fn (_ s w)
    (def gap (- w (byte-len s)))
    (if (<= gap 0) s (string-append s (%str-make-raw gap)))))

; S padded to W columns with zeros before it
(def %cu-pad-zero
  (fn (_ s w)
    (def gap (- w (byte-len s)))
    (def zeros (fn (self k acc) (if (<= k 0) (bytes->str acc) (self (- k 1) (pair 48 acc)))))
    (if (<= gap 0) s (string-append (zeros gap ()) s))))

; operands to one text: files in order, - or none meaning stdin
(def %cu-gather
  (fn (_ operands stdin-thunk)
    (if (null? operands)
      (stdin-thunk)
      (let ((go (fn (self ops acc)
                  (if (null? ops)
                    (string-concat (reverse acc))
                    (self (rest ops)
                      (pair
                        (if (string=? (first ops) "-")
                          (stdin-thunk)
                          (file-read-all (first ops)))
                        acc))))))
        (go operands ())))))

; %cu-gather for an applet that says what it could not read.  A file that
; would not open, or opened and would not read -- a directory -- is said on
; stderr in the line SAYS answers for its name and io Err, and the rest are
; still read; under STOP? the first failure ends the reading, as it does for
; sort.  Answers (TEXT . STATUS), STATUS 1 when anything failed.
(def %cu-gather-said
  (fn (_ operands stdin-thunk says stop?)
    (if (null? operands) (pair (stdin-thunk) 0)
      (%cu-gather-said-go operands stdin-thunk says stop? () 0))))

(def %cu-gather-said-go
  (fn (self ops stdin-thunk says stop? acc st)
    (if (if (null? ops) #t (if stop? (> st 0) #f))
      (pair (string-concat (reverse acc)) st)
      (if (string=? (first ops) "-")
        (self (rest ops) stdin-thunk says stop? (pair (stdin-thunk) acc) st)
        (let ((text (file-or-err (fn (_) (file-read-all (first ops))))))
          (if (Err err? text)
            (do (file-write 2 (string-append (says (first ops) text) "\n"))
                (self (rest ops) stdin-thunk says stop? acc 1))
            (self (rest ops) stdin-thunk says stop? (pair text acc) st)))))))

; One file read whole -- or, once SAYS has said on stderr why it could not be,
; the io Err it failed with, for the caller to tell a file that would not open
; from one that would not read.
(def %cu-read-said
  (fn (_ says name)
    (let ((text (file-or-err (fn (_) (file-read-all name)))))
      (if (Err err? text) (do (%cu-say says name text) text) text))))

; the line SAYS gives for NAME and its io Err, on stderr -- or nothing, where
; SAYS answers nil, as cmp -s does
(def %cu-say
  (fn (_ says name err)
    (let ((line (says name err)))
      (if (null? line) () (file-write 2 (string-append line "\n"))))))

; The operands' texts as a tool reads them that opens every file before it
; reads any: the first that will not open is said and nothing is read; then
; each is read in turn, and the first that will not read is said and ends the
; reading.  Answers the list of texts, or the io Err that stopped it.
(def %cu-read-all-said
  (fn (_ ops stdin-thunk says)
    (let ((shut (%cu-first-unopened ops says)))
      (if (Err err? shut) shut
        (%cu-read-each-said ops stdin-thunk says ())))))

; the first operand that will not open, said, or 0 when every one opens
(def %cu-first-unopened
  (fn (self ops says)
    (if (null? ops) 0
      (if (string=? (first ops) "-") (self (rest ops) says)
        (let ((fd (file-open-or-err file-open-read (first ops))))
          (if (Err err? fd) (do (%cu-say says (first ops) fd) fd)
            (do (file-close fd) (self (rest ops) says))))))))

(def %cu-read-each-said
  (fn (self ops stdin-thunk says acc)
    (if (null? ops) (reverse acc)
      (let ((t (if (string=? (first ops) "-") (stdin-thunk)
                 (%cu-read-said says (first ops)))))
        (if (Err err? t) t
          (self (rest ops) stdin-thunk says (pair t acc)))))))

; Each operand read whole and handed to ONE as NAME and TEXT, in order; `-`
; is standard input.  A file that cannot be read is said by SAYS and passed
; over.  Answers ST, or 1 once any operand failed.
(def %cu-each-said
  (fn (self ops stdin-thunk says one st)
    (if (null? ops) st
      (let ((text (if (string=? (first ops) "-") (stdin-thunk)
                    (%cu-read-said says (first ops)))))
        (if (Err err? text)
          (self (rest ops) stdin-thunk says one 1)
          (do (one (first ops) text)
              (self (rest ops) stdin-thunk says one st)))))))

; the words most applets say it in, whichever way the file failed:
; "APPLET: NAME: REASON"
(def %cu-says
  (fn (_ applet)
    (fn (_ name err)
      (string-concat (list applet ": " name ": " (file-err-text err))))))

; and for an applet with words of its own for a file that opened and would
; not read: READ-SAYS answers that line, and a file that would not open is
; said the common way
(def %cu-says-read
  (fn (_ applet read-says)
    (fn (_ name err)
      (if (eq? (file-err-op err) (lit read)) (read-says name err)
        (string-concat (list applet ": " name ": " (file-err-text err)))))))

; the words of shuf and base64, which name no file for one that opened and
; would not read: "APPLET: read error: REASON"
(def %cu-read-error
  (fn (_ applet)
    (%cu-says-read applet
      (fn (_ name err)
        (string-concat (list applet ": read error: " (file-err-text err)))))))

; The -z and -0 reading shape: operands (or standard input) as fields
; split on a byte, which is %cu-lines over %cu-gather when the delimiter
; is a newline and the bytes are a string.  A NUL is neither, so the
; operands are read as bytes and the leftover of one file opens the
; next, the way the tools read their inputs as one stream.
(def %cu-delim-fields
  (fn (_ ops stdin-thunk delim)
    (first (%cu-delim-fields-said ops stdin-thunk delim (fn (_ name err) ()) #f))))

; %cu-delim-fields for an applet that says what it could not read: a file that
; will not open, or is a directory that will not read, is said by SAYS and
; passed over -- or, under STOP?, ends the reading -- as %cu-gather-said does
; it.  Answers (FIELDS . STATUS).
(def %cu-delim-fields-said
  (fn (_ ops stdin-thunk delim says stop?)
    (if (null? ops) (pair (cu-stdin-fields! delim) 0)
      (%cu-delim-fields-go ops stdin-thunk delim says stop? "" () 0))))

(def %cu-delim-fields-go
  (fn (self os stdin-thunk delim says stop? partial acc st)
    (if (if (null? os) #t (if stop? (> st 0) #f))
      (pair (append acc (if (= (byte-len partial) 0) () (list partial))) st)
      (if (string=? (first os) "-")
        (self (rest os) stdin-thunk delim says stop? ""
          (append acc (cu-stdin-fields! delim)) st)
        (let ((fd (file-open-or-err file-open-read (first os))))
          (match
            ((Err err? fd)
              (do (%cu-say says (first os) fd)
                  (self (rest os) stdin-thunk delim says stop? partial acc 1)))
            ; a directory opens, and its read is the failure to say
            ((file-dir? (first os))
              (do (file-close fd)
                  (%cu-say says (first os)
                    (file-or-err (fn (_) (file-read-all (first os)))))
                  (self (rest os) stdin-thunk delim says stop? partial acc 1)))
            (#t
              (let ((r (%cu-fd-fields fd delim partial)))
                (do (file-close fd)
                    (self (rest os) stdin-thunk delim says stop? (rest r)
                      (append acc (first r)) st))))))))))

; each field, then its delimiter -- %cu-print-lines for a -z output
(def %cu-print-fields
  (fn (self ls delim)
    (if (null? ls) ()
      (do (file-write-field 1 (first ls) delim)
          (self (rest ls) delim)))))

; The last hand-rolled option read: everything reads its options off cu/cli.x's
; declaration except comm, whose flags are digits -- v0.13.0's Opts decides
; `-12` is a negative number before consulting the declaration, so the cluster
; never reaches the parse. x-lang#650 makes the declaration win, and these two
; go when it ships.
(def %cu-option-token-ish?
  (fn (_ s) (if (< (byte-len s) 2) #f (= (byte-at s 0) 45))))

(def %cu-token-has?
  (fn (_ tok d)
    (let ((go (fn (self i)
                (if (>= i (byte-len tok)) #f
                  (if (= (byte-at tok i) d) #t (self (+ i 1)))))))
      (go 1))))

; --- the counts head and tail take ---------------------------------------------
;
; -n and -c take a count the way GNU's head and tail read one, once a leading -
; is taken off: blanks, an optional +, digits, then an optional multiplier and
; nothing after it.  b is 512; k K m M G T P E Z Y R Q are powers of 1024, or of
; 1000 with a B after them (kB MB) and of 1024 again with iB (KiB).  A multiplier
; with no digits before it counts one of itself.  A count too large to hold is
; %cu-count-all, which no input reaches.

(def %cu-count-all 4611686018427387904)                        ; 2^62

; the power a multiplier letter raises its base to, or nil
(def %cu-count-power
  (fn (_ c)
    (match
      ((= c 107) 1) ((= c 75) 1)                                ; k K
      ((= c 109) 2) ((= c 77) 2)                                ; m M
      ((= c 71) 3) ((= c 84) 4) ((= c 80) 5) ((= c 69) 6)       ; G T P E
      ((= c 90) 7) ((= c 89) 8) ((= c 82) 9) ((= c 81) 10)      ; Z Y R Q
      (#t ()))))

; S's digits from I onto ACC: (ACC . NEXT)
(def %cu-count-digits
  (fn (self s i acc)
    (if (if (< i (byte-len s))
          (if (>= (byte-at s i) 48) (<= (byte-at s i) 57) #f)
          #f)
      (self s (+ i 1)
        (if (> acc 100000000000000000) %cu-count-all
          (+ (* acc 10) (- (byte-at s i) 48))))
      (pair acc i))))

; V times BASE, POWER times over
(def %cu-count-scale
  (fn (self v base power)
    (match
      ((<= power 0) v)
      ((> v 1000000000000000) %cu-count-all)
      (#t (self (* v base) base (- power 1))))))

; V under the multiplier at I, and its B or iB: the count, or nil when what is
; there is not a multiplier or something follows it
(def %cu-count-suffix
  (fn (_ s i v)
    (let ((end (byte-len s)))
      (if (>= i end) v
        (let ((c (byte-at s i)))
          (let ((p (if (= c 98) 1 (%cu-count-power c))))       ; b
            (if (null? p) ()
              (let ((base (match
                            ((= (+ i 1) end) 1024)
                            ((if (= (+ i 2) end) (= (byte-at s (+ i 1)) 66) #f)
                              1000)                                  ; B
                            ((if (= (+ i 3) end)
                               (if (= (byte-at s (+ i 1)) 105)
                                 (= (byte-at s (+ i 2)) 66) #f)
                               #f)
                              1024)                                  ; iB
                            (#t ()))))
                (match
                  ((null? base) ())
                  ((= c 98) (%cu-count-scale v 512 1))
                  (#t (%cu-count-scale v base p)))))))))))

; the count S holds, or nil when it holds none
(def %cu-count-of
  (fn (_ s)
    (let ((i (%cu-count-blanks s 0)))
      (if (if (< i (byte-len s)) (= (byte-at s i) 45) #f) ()      ; -
        (let ((j (if (if (< i (byte-len s)) (= (byte-at s i) 43) #f)
                   (+ i 1) i)))                                   ; +
          (let ((d (%cu-count-digits s j 0)))
            (match
              ((> (rest d) j) (%cu-count-suffix s (rest d) (first d)))
              ((= (byte-len s) 0) ())
              (#t (%cu-count-suffix s 0 1)))))))))

(def %cu-count-blanks
  (fn (self s i)
    (if (if (< i (byte-len s))
          (let ((b (byte-at s i))) (if (= b 32) #t (if (>= b 9) (<= b 13) #f)))
          #f)
      (self s (+ i 1))
      i)))

; the -n or -c value past a leading -, which both applets take off first
(def %cu-count-body
  (fn (_ spec)
    (if (if (> (byte-len spec) 0) (= (byte-at spec 0) 45) #f)
      (substring spec 1 (byte-len spec))
      spec)))

; a value that is not a count, refused in GNU's words
(def %cu-count-refused
  (fn (_ applet lines? spec)
    (do (file-write 2
          (string-concat
            (list applet ": invalid number of " (if lines? "lines" "bytes") ": '"
                  (%cu-count-body spec) "'\n")))
        1)))

; What an applet counts, as (LINES? . SPEC): the later of -n and -c, else ten
; lines.
(def %cu-count-given
  (fn (_ o)
    (let ((flag (%cu-last-valued o (list "-n" "-c"))))
      (match
        ((null? flag) (pair #t "10"))
        ((string=? flag "-c") (pair #f (Opts value o "-c")))
        (#t (pair #t (Opts value o "-n")))))))

; whether a header comes before each operand: as the later of -q and -v says,
; else when there is more than one operand
(def %cu-headers?
  (fn (_ o ops)
    (let ((flag (%cu-last-given o (list "-q" "-v"))))
      (if (null? flag) (> (length ops) 1) (string=? flag "-v")))))

; --- the old spellings of a count ----------------------------------------------
;
; head and tail also take a count spelled as an option of digits, -NUM.  head
; reads one as its first argument, with letters after the digits: c counts
; bytes; b, k and m count bytes in 512s, 1024s and 1048576s; l counts lines; q
; and v set the headers.  tail reads one only as -NUM[bcl][f] with at most one
; operand after it, or -- and one: b counts bytes in 512s, c bytes, l lines, and
; f follows.  Each is rewritten as the -n or -c it means, ahead of the rest.  A
; -NUM anywhere else is refused.

; is TOK a dash and a digit: a number to Opts, a count or a misplaced one here
(def %cu-dash-digit?
  (fn (_ tok)
    (if (< (byte-len tok) 2) #f
      (if (= (byte-at tok 0) 45)
        (let ((c (byte-at tok 1))) (if (>= c 48) (<= c 57) #f))
        #f))))

; the index past the digits in TOK from I
(def %cu-digits-end
  (fn (self tok i)
    (if (if (< i (byte-len tok))
          (let ((c (byte-at tok i))) (if (>= c 48) (<= c 57) #f))
          #f)
      (self tok (+ i 1))
      i)))

; head's arguments with its first read as -NUM[cbkmlqv]*: (ok . ARGUMENTS), the
; count rewritten, or (bad . LETTER) for a letter that is not one of those
(def %cu-head-old
  (fn (_ argv)
    (if (if (pair? argv) (%cu-dash-digit? (first argv)) #f)
      (let ((tok (first argv)))
        (let ((e (%cu-digits-end tok 1)))
          (%cu-head-old-letters tok e (substring tok 1 e) #t "" () (rest argv))))
      (pair (lit ok) argv))))

; the letters of head's old count from I: LINES? and the multiplier MULT so far,
; and HEADER, the -q or -v the last q or v asked for
(def %cu-head-old-letters
  (fn (self tok i digits lines? mult header more)
    (if (>= i (byte-len tok))
      (pair (lit ok)
        (append (list (if lines? "-n" "-c") (string-append digits mult))
          (append header more)))
      (let ((c (byte-at tok i)))
        (match
          ((= c 99) (self tok (+ i 1) digits #f "" header more))           ; c
          ((if (= c 98) #t (if (= c 107) #t (= c 109)))                    ; b k m
            (self tok (+ i 1) digits #f (substring tok i (+ i 1)) header more))
          ((= c 108) (self tok (+ i 1) digits #t mult header more))        ; l
          ((= c 113) (self tok (+ i 1) digits lines? mult (list "-q") more)) ; q
          ((= c 118) (self tok (+ i 1) digits lines? mult (list "-v") more)) ; v
          (#t (pair (lit bad) (substring tok i (+ i 1)))))))))

; tail's arguments with an old count rewritten, when they have its shape: the
; count and at most one operand that does not look like an option, or -- and one
(def %cu-tail-old
  (fn (_ argv)
    (let ((n (length argv)))
      (let ((count (if (if (> n 0) (%cu-dash-digit? (first argv)) #f)
                     (%cu-tail-old-count (first argv))
                     ())))
        (if (if (null? count) #t
              (not (match
                     ((= n 1) #t)
                     ((if (<= n 3) (string=? (%cu-nth 1 argv) "--") #f) #t)
                     ((= n 2) (not (if (> (byte-len (%cu-nth 1 argv)) 1)
                                     (= (byte-at (%cu-nth 1 argv) 0) 45) #f)))
                     (#t #f))))
          argv
          (append count (rest argv)))))))

; TOK as tail's old count, -NUM[bcl][f]: the -n or -c it means, and -f; or nil
(def %cu-tail-old-count
  (fn (_ tok)
    (let ((e (%cu-digits-end tok 1)))
      (let ((unit (if (< e (byte-len tok)) (byte-at tok e) 0)))
        (let ((after (if (if (= unit 98) #t (if (= unit 99) #t (= unit 108)))
                       (+ e 1) e))
              (count (list (if (if (= unit 98) #t (= unit 99)) "-c" "-n")
                           (string-append (substring tok 1 e)
                             (if (= unit 98) "b" "")))))
          (match
            ((= after (byte-len tok)) count)
            ((if (= (+ after 1) (byte-len tok)) (= (byte-at tok after) 102) #f)
              (append count (list "-f")))                               ; f
            (#t ())))))))

; The first -NUM among ARGV where no count can be: before a --, and not the value
; of an option before it whose last letter is one of VALUED.  Answers its first
; digit, as a string, or nil.
(def %cu-misplaced-count
  (fn (self argv valued prev)
    (match
      ((null? argv) ())
      ((string=? (first argv) "--") ())
      ((if (%cu-dash-digit? (first argv)) (not (%cu-takes-value? prev valued)) #f)
        (substring (first argv) 1 2))
      (#t (self (rest argv) valued (first argv))))))

; does TOK, an option, take the argument after it: one dash, then letters, the
; last of them one of the bytes of VALUED
(def %cu-takes-value?
  (fn (_ tok valued)
    (if (if (> (byte-len tok) 1) (= (byte-at tok 0) 45) #f)
      (if (= (byte-at tok 1) 45) #f
        (%cu-byte-in? valued (byte-at tok (- (byte-len tok) 1)) 0))
      #f)))

(def %cu-byte-in?
  (fn (self s b i)
    (if (>= i (byte-len s)) #f
      (if (= (byte-at s i) b) #t (self s b (+ i 1))))))

; where each line of TEXT starts: 0, then one past each newline that has more
; text after it.  An empty text has no lines.
(def %cu-line-starts
  (fn (_ text)
    (if (= (byte-len text) 0) ()
      (%cu-line-starts-at text (byte-len text) 0 (list 0)))))

(def %cu-line-starts-at
  (fn (self text end i acc)
    (match
      ((>= (+ i 1) end) (reverse acc))
      ((= (byte-at text i) 10) (self text end (+ i 1) (pair (+ i 1) acc)))
      (#t (self text end (+ i 1) acc)))))

; where line K starts, counting from 0, or END when there are not that many
(def %cu-line-at
  (fn (self starts k end)
    (match
      ((null? starts) end)
      ((<= k 0) (first starts))
      (#t (self (rest starts) (- k 1) end)))))

; What head prints of TEXT: its first N lines or bytes, or under ELIDE? all but
; its last N.  The bytes are the input's, so a last line keeps having no
; newline when it had none.
(def %cu-head-part
  (fn (_ text lines? elide? n)
    (let ((end (byte-len text)))
      (if lines?
        (let ((starts (%cu-line-starts text)))
          (substring text 0
            (%cu-line-at starts (if elide? (- (length starts) n) n) end)))
        (substring text 0
          (match
            ((> n end) (if elide? 0 end))
            (elide? (- end n))
            (#t n)))))))

; head -n and -c: a leading - prints all but the last COUNT, and a leading + is
; the count itself; the later of the two options says what is counted.  A header
; comes before each operand when there is more than one; -v asks for them always
; and -q never, and the later of those wins too.
(def %cu-head
  (fn (_ argv stdin-thunk)
    (let ((old (%cu-head-old argv)))
      (let ((misplaced (if (eq? (first old) (lit ok))
                         (%cu-misplaced-count (rest old) "nc" "")
                         ())))
        (match
          ((eq? (first old) (lit bad))
            (%cu-head-trailing (rest old)))
          ((not (null? misplaced)) (%cu-head-trailing misplaced))
          (#t (%cu-head-run (%cu-opts "head" (rest old)) stdin-thunk)))))))

(def %cu-head-trailing
  (fn (_ c)
    (do (file-write 2
          (string-concat (list "head: invalid trailing option -- " c "\n")))
        1)))

(def %cu-head-run
  (fn (_ o stdin-thunk)
    (let ((given (%cu-count-given o)) (ops (Opts operands o)))
      (let ((lines? (first given)) (spec (rest given)))
        (let ((n (%cu-count-of (%cu-count-body spec)))
              (elide? (if (> (byte-len spec) 0) (= (byte-at spec 0) 45) #f)))
          (if (null? n) (%cu-count-refused "head" lines? spec)
            (%cu-each-input "head" ops stdin-thunk (%cu-headers? o ops)
              (fn (_ name text file?)
                (display (%cu-head-part text lines? elide? n))))))))))

(def %cu-member-s?
  (fn (_ s l)
    (def go
      (fn (self es)
        (if (null? es) #f
          (if (string=? (first es) s) #t (self (rest es))))))
    (go l)))

; LINES to FD, one per line -- stderr's %cu-print-lines
(def %cu-print-lines-to
  (fn (self fd ls)
    (if (null? ls) ()
      (do (file-write fd (string-append (first ls) "\n"))
          (self fd (rest ls))))))

; -s's interval: "2", "0.5", "1.25" -- whole seconds through sleep and
; the fraction, to the microsecond, through usleep, which on Darwin
; takes less than a second.
(def %cu-tail-sleep
  (fn (_ spec)
    (def parts (%cu-split-byte spec 46))                          ; .
    (def secs
      (if (= (byte-len (first parts)) 0) 0 (%cu-num-prefix (first parts))))
    (def us
      (if (null? (rest parts)) 0
        (%cu-num-prefix
          (substring (string-append (first (rest parts)) "000000") 0 6))))
    (do (if (> secs 0) (sys-sleep secs) ())
        (if (> us 0) (sys-usleep us) ())
        ())))

; the bytes of NAME from FROM up to TO
(def %cu-read-range
  (fn (_ name from to)
    (let ((fd (file-open-read name)))
      (do (file-seek fd from)
          (let ((s (file-read-fd fd (- to from))))
            (do (file-close fd) s))))))

; One round of -f over NAMES, each followed from its entry in OFFS: what
; grew is printed, under a header when headers are on and the file is
; not the one printed last, and a file that shrank was truncated -- said
; on stderr, then read again from its start.  A file that cannot be
; read this round keeps its offset for the next.  Answers the new
; offsets paired with the name printed last, which the next round takes.
(def %cu-tail-round
  (fn (_ names offs head? last)
    (def go
      (fn (self ns os last acc)
        (if (null? ns) (pair (reverse acc) last)
          (let ((st (file-stat-full (first ns))))
            (if (null? st)
              (self (rest ns) (rest os) last (pair (first os) acc))
              (let ((size (%cu-stat-get st (lit size))))
                (def from
                  (if (< size (first os))
                    (do (file-write 2
                          (string-concat
                            (list "tail: " (first ns) ": file truncated\n")))
                        0)
                    (first os)))
                (if (> size from)
                  (do (if (if head? (not (string=? last (first ns))) #f)
                        (display
                          (string-concat (list "\n==> " (first ns) " <==\n")))
                        ())
                      (display (%cu-read-range (first ns) from size))
                      (self (rest ns) (rest os) (first ns) (pair size acc)))
                  (self (rest ns) (rest os) last (pair from acc)))))))))
    (go names offs last ())))

; rounds forever (ROUNDS below zero) or for a count, sleeping INTERVAL
; between them; "0" does not sleep.  OFFS is where each file's initial
; read ENDED, not its size now: a line appended between that read and
; the first round belongs to the follow, and sizing the file again here
; would skip it.
(def %cu-tail-follow
  (fn (_ names offs head? last interval rounds)
    (def go
      (fn (self offs last k)
        (if (= k 0) 0
          (do (if (string=? interval "0") () (%cu-tail-sleep interval))
              (let ((r (%cu-tail-round names offs head? last)))
                (self (first r) (rest r) (if (< k 0) k (- k 1))))))))
    (go offs last rounds)))

; What tail prints of TEXT: its last N lines or bytes, or under FROM-START?
; everything from line or byte N on, where +0 is +1.  The bytes are the
; input's, so a last line keeps having no newline when it had none.
(def %cu-tail-part
  (fn (_ text lines? from-start? n)
    (let ((end (byte-len text)))
      (if lines?
        (let ((starts (%cu-line-starts text)))
          (substring text
            (%cu-line-at starts (if from-start? (- n 1) (- (length starts) n)) end)
            end))
        (substring text
          (match
            (from-start? (if (> n end) end (if (< n 1) 0 (- n 1))))
            ((> n end) 0)
            (#t (- end n)))
          end)))))

; tail -n and -c: a leading + counts from the start, and a leading - is the
; count itself; the later of the two options says what is counted, and the later
; of -q and -v decides the headers.  -f follows by NAME the files that were read,
; polled every -s
; seconds (1 by default), each from where its read ended.  Standard input has
; been read whole by the time an applet runs, so it has nothing to follow: -f
; with only stdin prints the tail and returns, and -f with operands none of
; which could be read says so.
(def %cu-tail
  (fn (_ argv stdin-thunk)
    (let ((args (%cu-tail-old argv)))
      (let ((misplaced (%cu-misplaced-count args "ncs" "")))
        (if (null? misplaced)
          (%cu-tail-run (%cu-opts "tail" args) stdin-thunk)
          (do (file-write 2
                (string-concat
                  (list "tail: option used in invalid context -- " misplaced "\n")))
              1))))))

(def %cu-tail-run
  (fn (_ o stdin-thunk)
    (let ((ops (Opts operands o)) (given (%cu-count-given o))
          ; each input shown, newest first: (NAME SIZE FILE?)
          (shown (list ())))
      (let ((lines? (first given)) (spec (rest given))
            (head? (%cu-headers? o ops)))
        (let ((n (%cu-count-of (%cu-count-body spec)))
              (from-start? (if (> (byte-len spec) 0) (= (byte-at spec 0) 43) #f)))
          (if (null? n) (%cu-count-refused "tail" lines? spec)
            (let ((st (%cu-each-input "tail" ops stdin-thunk head?
                        (fn (_ name text file?)
                          (do (%set-first! shown
                                (pair (list name (byte-len text) file?)
                                  (first shown)))
                              (display (%cu-tail-part text lines? from-start? n)))))))
              (let ((files (filter (fn (_ e) (%cu-nth 2 e)) (reverse (first shown)))))
                (match
                  ((not (Opts on? o "-f")) st)
                  ((pair? files)
                    (do (%cu-tail-follow (map (fn (_ e) (first e)) files)
                          (map (fn (_ e) (%cu-nth 1 e)) files) head?
                          (first (first (first shown)))
                          (Opts value o "-s" "1") (- 0 1))
                        st))
                  ((pair? ops) (do (file-write 2 "tail: no files remaining\n") 1))
                  (#t st))))))))))

; counts for one text: (lines words bytes)
; (LINES WORDS BYTES LONGEST). LONGEST is the longest line without its
; newline, which is what -L reports.
(def %cu-wc-counts
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i nl nw in-word col longest)
        (if (>= i end)
          (list nl (if in-word (+ nw 1) nw) end
            (if (> col longest) col longest))
          (let ((b (byte-at s i)))
            (def ws (match ((= b 32) #t) ((= b 9) #t) (#t (= b 10))))
            (self (+ i 1)
              (if (= b 10) (+ nl 1) nl)
              (if (if in-word ws #f) (+ nw 1) nw)
              (not ws)
              (if (= b 10) 0 (+ col 1))
              (if (= b 10) (if (> col longest) col longest) longest))))))
    (go 0 0 0 #f 0 0)))

; wc reads every input before it prints a row, because the rows share one
; column width: the digits of what the regular files hold between them, and at
; least seven where any input is not a regular file -- a pipe, a terminal, a
; directory -- as wc sizes them.  One count of one input is not padded at all.
; More than one input ends with their total, where the longest line is the
; longest of them.  A file wc cannot read is said and fails; a directory, which
; opens and will not read, still gets its row, of nothing.  What is said about
; an input is said in its turn among the rows -- after a directory's row -- as
; wc says it, though every input was read before the first row.
(def %cu-wc
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "wc" argv))
    (def any?
      (match
        ((Opts on? o "-l") #t) ((Opts on? o "-w") #t) ((Opts on? o "-c") #t)
        ((Opts on? o "-m") #t) ((Opts on? o "-L") #t)
        (#t #f)))
    ; With no flag at all wc shows lines, words and bytes -- not -m or -L,
    ; which are asked for or not shown.  -m and -c report the same number
    ; here, because this wc counts bytes and a character is a byte -- asking
    ; for both prints it twice, which is what asking for both means.
    (def cols
      (filter
        (fn (_ f)
          (if any? (Opts on? o f)
            (match ((string=? f "-m") #f) ((string=? f "-L") #f) (#t #t))))
        (list "-l" "-w" "-m" "-c" "-L")))
    (def ops (Opts operands o))
    (def ins
      (if (null? ops) (list (%cu-wc-stdin stdin-thunk ()))
        (map (fn (_ op) (%cu-wc-input op stdin-thunk)) ops)))
    (def rows (filter (fn (_ i) (%cu-nth 5 i)) ins))
    (def width (%cu-wc-width rows (length cols) (length ins)))
    (def row
      (fn (_ counts name)
        (display
          (string-append
            (%cu-join-with
              (map (fn (_ f)
                     (%cu-pad-left (%cu-int->str (%cu-wc-count counts f)) width))
                cols)
              " ")
            (if (null? name) "\n" (string-concat (list " " name "\n")))))))
    (def each
      (fn (self is)
        (if (null? is) ()
          (do (if (%cu-nth 5 (first is))
                (row (%cu-nth 1 (first is)) (first (first is))) ())
              (if (null? (%cu-nth 4 (first is))) ()
                (file-write 2 (string-append (%cu-nth 4 (first is)) "\n")))
              (self (rest is))))))
    (do (each ins)
        (if (> (length ins) 1) (row (%cu-wc-total rows) "total") ())
        (if (%cu-wc-failed? ins) 1 0))))

; One operand read: (NAME COUNTS REGULAR? SIZE SAID ROW?) -- SAID the line wc
; says about it, or nil, and ROW? whether it gets a row: a file that would not
; open gets none.
(def %cu-wc-input
  (fn (_ op stdin-thunk)
    (if (string=? op "-") (%cu-wc-stdin stdin-thunk op)
      (let ((text (file-or-err (fn (_) (file-read-all op)))))
        (match
          ((not (Err err? text))
            (let ((st (file-stat-full op)))
              (list op (%cu-wc-counts text)
                (eq? (%cu-stat-get st (lit kind)) (lit file))
                (%cu-stat-get st (lit size)) () #t)))
          ((eq? (file-err-op text) (lit read))
            (list op (%cu-wc-counts "") #f 0 ((%cu-says "wc") op text) #t))
          (#t (list op () #f 0 ((%cu-says "wc") op text) #f)))))))

; Standard input read, and then asked what it is: after the read it is fd 0,
; whatever it came in as -- a file, a pipe, a terminal.
(def %cu-wc-stdin
  (fn (_ stdin-thunk name)
    (let ((text (stdin-thunk)))
      (let ((st (file-stat-full "/dev/fd/0")))
        (list name (%cu-wc-counts text)
          (eq? (%cu-stat-get st (lit kind)) (lit file))
          (%cu-stat-get st (lit size)) () #t)))))

(def %cu-wc-width
  (fn (_ rows ncols nins)
    (if (if (= ncols 1) (= nins 1) #f) 1
      (let ((digits (byte-len (%cu-int->str (%cu-wc-regular-bytes rows 0)))))
        (if (if (%cu-wc-other? rows) (< digits 7) #f) 7 digits)))))

(def %cu-wc-regular-bytes
  (fn (self rows n)
    (if (null? rows) n
      (self (rest rows)
        (if (%cu-nth 2 (first rows)) (+ n (%cu-nth 3 (first rows))) n)))))

(def %cu-wc-other?
  (fn (self rows)
    (if (null? rows) #f
      (if (%cu-nth 2 (first rows)) (self (rest rows)) #t))))

(def %cu-wc-failed?
  (fn (self ins)
    (if (null? ins) #f
      (if (null? (%cu-nth 4 (first ins))) (self (rest ins)) #t))))

; the count a column shows, from (LINES WORDS BYTES LONGEST)
(def %cu-wc-count
  (fn (_ counts f)
    (%cu-nth
      (match ((string=? f "-l") 0) ((string=? f "-w") 1) ((string=? f "-L") 3)
        (#t 2))
      counts)))

; the rows summed, the longest line the longest of them
(def %cu-wc-total
  (fn (self rows)
    (if (null? rows) (list 0 0 0 0)
      (let ((c (%cu-nth 1 (first rows))) (t (self (rest rows))))
        (list (+ (first c) (first t)) (+ (%cu-nth 1 c) (%cu-nth 1 t))
              (+ (%cu-nth 2 c) (%cu-nth 2 t))
              (if (> (%cu-nth 3 c) (%cu-nth 3 t)) (%cu-nth 3 c) (%cu-nth 3 t)))))))

; comm: three columns over two sorted inputs; -1 -2 -3 suppress
(def %cu-comm
  (fn (_ argv stdin-thunk)
    ; comm's flags are digits, and v0.13.0's Opts decides `-12` is a negative
    ; number before consulting the declaration, so comm reads its three digits
    ; itself until x-lang#650 ships. Everything else comes off the one parse.
    (def o (%cu-opts "comm" argv))
    (def digit?
      (fn (_ d)
        (let ((go (fn (self as)
                    (if (null? as) #f
                      (if (%cu-option-token-ish? (first as))
                        (if (%cu-token-has? (first as) d) #t (self (rest as)))
                        (self (rest as)))))))
          (go argv))))
    (def s1 (not (digit? 49)))
    (def s2 (not (digit? 50)))
    (def s3 (not (digit? 51)))
    (def ops (filter (fn (_ a) (not (%cu-option-token-ish? a))) argv))
    ; each file is opened and read in turn -- comm reads the first before it
    ; opens the second -- and the first that fails is said and ends it: comm
    ; prints nothing without its two inputs
    (def texts (%cu-read-each-said (list (first ops) (first (rest ops)))
                 stdin-thunk (%cu-says "comm") ()))
    (def failed? (Err err? texts))
    (def a (if failed? () (%cu-lines (first texts))))
    (def b (if failed? () (%cu-lines (first (rest texts)))))
    (def ind2 (if s1 "\t" ""))
    (def ind3 (string-append (if s1 "\t" "") (if s2 "\t" "")))
    (def go
      (fn (self la lb)
        (match
          ((null? la)
            (if (null? lb) ()
              (do (if s2 (display (string-append ind2
                                    (string-append (first lb) "\n"))) ())
                  (self la (rest lb)))))
          ((null? lb)
            (do (if s1 (display (string-append (first la) "\n")) ())
                (self (rest la) lb)))
          ((string=? (first la) (first lb))
            (do (if s3 (display (string-append ind3
                                  (string-append (first la) "\n"))) ())
                (self (rest la) (rest lb))))
          ((%cu-str< (first la) (first lb))
            (do (if s1 (display (string-append (first la) "\n")) ())
                (self (rest la) lb)))
          (#t
            (do (if s2 (display (string-append ind2
                                  (string-append (first lb) "\n"))) ())
                (self la (rest lb)))))))
    (if failed? 1 (do (go a b) 0))))

; join on field 1 of two sorted inputs; -t CHAR sets the delimiter
(def %cu-split-line
  (fn (_ line delim)
    (if (null? delim)
      (%cu-words-line line)
      (%cu-split-byte line (byte-at delim 0)))))

(def %cu-words-line
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i start acc in)
        (if (>= i end)
          (reverse (if in (pair (substring s start i) acc) acc))
          (let ((ws (let ((b (byte-at s i)))
                      (if (= b 32) #t (= b 9)))))
            (if ws
              (self (+ i 1) (+ i 1) (if in (pair (substring s start i) acc) acc) #f)
              (self (+ i 1) (if in start i) acc #t))))))
    (go 0 0 () #f)))

(def %cu-split-byte
  (fn (_ s b)
    (def end (byte-len s))
    (def go
      (fn (self i start acc)
        (if (>= i end)
          (reverse (pair (substring s start end) acc))
          (if (= (byte-at s i) b)
            (self (+ i 1) (+ i 1) (pair (substring s start i) acc))
            (self (+ i 1) start acc)))))
    (go 0 0 ())))

(def %cu-join
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "join" argv))
    (def delim (Opts value o "-t"))
    (def ops (Opts operands o))
    (def sep (if (null? delim) " " delim))
    ; both files are opened before either is read, the first that fails is
    ; said -- a read that fails as "read error", naming no file -- and join
    ; prints nothing without its two inputs
    (def texts (%cu-read-all-said (list (first ops) (first (rest ops)))
                 stdin-thunk (%cu-read-error "join")))
    (def failed? (Err err? texts))
    (def a (if failed? () (%cu-lines (first texts))))
    (def b (if failed? () (%cu-lines (first (rest texts)))))
    (def key (fn (_ line)
               (let ((fs (%cu-split-line line delim)))
                 (if (null? fs) "" (first fs)))))
    (def rest-fields
      (fn (_ line)
        (let ((fs (%cu-split-line line delim)))
          (if (null? fs) () (rest fs)))))
    (def emit
      (fn (_ la lb)
        (display
          (string-append
            (%cu-join-with
              (pair (key la)
                (append (rest-fields la) (rest-fields lb)))
              sep)
            "\n"))))
    ; runs of equal keys pair cartesianly
    (def take-run
      (fn (_ ls k)
        (let ((go (fn (self l acc)
                    (if (if (pair? l) (string=? (key (first l)) k) #f)
                      (self (rest l) (pair (first l) acc))
                      (pair (reverse acc) l)))))
          (go ls ()))))
    (def go
      (fn (self la lb)
        (if (null? la) ()
          (if (null? lb) ()
            (let ((ka (key (first la))) (kb (key (first lb))))
              (if (string=? ka kb)
                (let ((ra (take-run la ka)))
                  (def rb (take-run lb ka))
                  ; equal-key runs pair cartesianly
                  (def outer
                    (fn (self2 xs)
                      (if (null? xs) ()
                        (do (let ((inner (fn (self3 ys)
                                           (if (null? ys) ()
                                             (do (emit (first xs) (first ys))
                                                 (self3 (rest ys)))))))
                              (inner (first rb)))
                            (self2 (rest xs))))))
                  (do (outer (first ra))
                      (self (rest ra) (rest rb))))
                (if (%cu-str< ka kb)
                  (self (rest la) lb)
                  (self la (rest lb)))))))))
    (if failed? 1 (do (go a b) 0))))

(def %cu-join-with
  (fn (self ws sep)
    (if (null? ws) ""
      (if (null? (rest ws)) (first ws)
        (string-append (first ws)
          (string-append sep (self (rest ws) sep)))))))

; The suffix is either -s SUFFIX or a second operand; busybox takes both
; spellings and they mean the same thing.
(def %cu-basename
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "basename" argv))
    (def ops (Opts operands o))
    (def p (first ops))
    (def stripped
      (let ((go (fn (self e)
                  (if (if (> e 1) (= (byte-at p (- e 1)) 47) #f)
                    (self (- e 1))
                    e))))
        (substring p 0 (go (byte-len p)))))
    (def slash
      (let ((go (fn (self i last)
                  (if (>= i (byte-len stripped)) last
                    (self (+ i 1)
                      (if (= (byte-at stripped i) 47) i last))))))
        (go 0 (- 0 1))))
    (def base (if (< slash 0) stripped
                (substring stripped (+ slash 1) (byte-len stripped))))
    (def suf
      (let ((v (Opts value o "-s")))
        (match
          ((not (null? v)) v)
          ((null? (rest ops)) ())
          (#t (first (rest ops))))))
    (def final
      (if (null? suf) base
        (let ((lb (byte-len base)) (ls (byte-len suf)))
          (if (if (> lb ls)
                (string=? (substring base (- lb ls) lb) suf)
                #f)
            (substring base 0 (- lb ls))
            base))))
    (do (display (string-append final "\n")) 0)))

(def %cu-dirname
  (fn (_ argv stdin-thunk)
    (def p (first argv))
    (def stripped
      (let ((go (fn (self e)
                  (if (if (> e 1) (= (byte-at p (- e 1)) 47) #f)
                    (self (- e 1))
                    e))))
        (substring p 0 (go (byte-len p)))))
    (def slash
      (let ((go (fn (self i last)
                  (if (>= i (byte-len stripped)) last
                    (self (+ i 1)
                      (if (= (byte-at stripped i) 47) i last))))))
        (go 0 (- 0 1))))
    (def d
      (if (< slash 0) "."
        (if (= slash 0) "/"
          (substring stripped 0 slash))))
    (do (display (string-append d "\n")) 0)))

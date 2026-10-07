; # x-coreutils -- the small tools, as applets
;
; ## cu/encode.x -- od, uuencode, uudecode
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The dump and the two historical transfer encodings.  od follows the
; GNU/busybox layout, NOT the BSD one macOS ships: no trailing pad to a
; fixed line width, and `*` for a repeated line.

; --- od ------------------------------------------------------------------------

; the escapes od -c spells; everything printable is itself, everything
; else is three octal digits
(def %cu-od-char
  (fn (_ b)
    (match
      ((= b 0)  "\\0")
      ((= b 7)  "\\a")
      ((= b 8)  "\\b")
      ((= b 9)  "\\t")
      ((= b 10) "\\n")
      ((= b 11) "\\v")
      ((= b 12) "\\f")
      ((= b 13) "\\r")
      ((if (>= b 32) (<= b 126) #f) (%cu-b->s b))
      (#t (%cu-pad-zero (%cu-oct->str b) 3)))))

; a word of `size` bytes, LITTLE-endian, from position i, the bytes from END
; on read as 0
(def %cu-od-word
  (fn (_ s i size end)
    (def go
      (fn (self k acc)
        (if (%cu< k size)
          (self (%cu+ k 1)
            (%cu+ acc
              (%cu<< (if (%cu< (%cu+ i k) end) (byte-at s (%cu+ i k)) 0)
                (%cu* 8 k))))
          acc)))
    (go 0 0)))

; the signed reading of the same word
(def %cu-od-signed
  (fn (_ v size)
    (def top (bit-shl 1 (- (* 8 size) 1)))
    (if (< v top) v (- v (* top 2)))))

; one field, padded to the width its type prints, from a line that ends at END
(def %cu-od-field
  (fn (_ s i end od-type size)
    (def w (fn (_ one two four)
             (match ((= size 1) one) ((= size 2) two) (#t four))))
    (if (eq? od-type (lit c)) (%cu-pad-left (%cu-od-char (byte-at s i)) 4)
      (let ((v (%cu-od-word s i size end)))
        (match
          ((eq? od-type (lit o))
            (string-append " " (%cu-pad-zero (%cu-oct->str v) (w 3 6 11))))
          ((eq? od-type (lit x))
            (string-append " " (%cu-pad-zero (%cu-hexs v) (w 2 4 8))))
          ((eq? od-type (lit u))
            (%cu-pad-left (%cu-int->str v) (w 4 6 11)))
          (#t (%cu-pad-left (%cu-int->str (%cu-od-signed v size))
                (w 5 7 12))))))))

(def %cu-od-address
  (fn (_ n radix)
    (match
      ((eq? radix (lit n)) "")
      ((eq? radix (lit d)) (%cu-pad-zero (%cu-int->str n) 7))
      ((eq? radix (lit x)) (%cu-pad-zero (%cu-hexs n) 7))
      (#t (%cu-pad-zero (%cu-oct->str n) 7)))))

; -t's argument is a letter and an optional size: o2, x1, c, d4
(def %cu-od-type
  (fn (_ spec)
    (def c (byte-at spec 0))
    (def size
      (match
        ((> (byte-len spec) 1)
          (%cu-num-prefix (substring spec 1 (byte-len spec))))
        ((= c 99) 1)
        ((= c 97) 1)
        (#t 2)))
    (pair
      (match
        ((= c 111) (lit o))
        ((= c 120) (lit x))
        ((= c 100) (lit d))
        ((= c 117) (lit u))
        (#t (lit c)))
      size)))

; the fields of the bytes FROM to STOP of S.  A field of one byte is read from
; a table made the first time its type is asked for, so a line costs a lookup
; a byte rather than the making of a field.
(def %cu-od-line
  (fn (_ s from stop od-type size)
    (if (= size 1)
      (let ((t (%cu-od-table od-type)))
        (let go ((i (%cu- stop 1)) (acc ()))
          (if (%cu< i from) (string-concat acc)
            (go (%cu- i 1) (pair (t (byte-at s i)) acc)))))
      (let go ((i from) (acc ()))
        (if (%cu< i stop)
          (go (%cu+ i size) (pair (%cu-od-field s i stop od-type size) acc))
          (string-concat (reverse acc)))))))

; the one-byte fields of each type asked for so far: (TYPE . VECTOR), the
; vector holding byte B's field at B
(def %cu-od-tables (list ()))

(def %cu-od-table
  (fn (_ od-type)
    (let ((e (Assoc entry od-type (first %cu-od-tables))))
      (if (null? e)
        (let ((t (vec-build 256
                   (fn (_ b) (%cu-od-field (bytes->str (list b)) 0 1 od-type 1)))))
          (do (set-first! %cu-od-tables (pair (pair od-type t) (first %cu-od-tables)))
              t))
        (rest e)))))

(def %cu-od-radix
  (fn (_ s)
    (let ((c (byte-at s 0)))
      (match
        ((= c 110) (lit n))
        ((= c 100) (lit d))
        ((= c 120) (lit x))
        (#t (lit o))))))

; the settings a scan collects, read back with a default
(def %cu-od-opt
  (fn (_ st key dflt)
    (let ((e (Assoc entry key st)))
      (if (null? e) dflt (rest e)))))

; -A -t -N take an argument; -c -b -x -d -o are shorthands for a -t;
; anything else is an operand.  The scan RETURNS its settings rather
; than writing cells, which keeps the walk one level deep -- the
; nested-cell version of this was the file's one misnesting.
(def %cu-od-scan
  (fn (self as st)
    (if (null? as) st
      (let ((a (first as)))
        (match
          ((string=? a "-A")
            (self (rest (rest as))
              (pair (pair (lit radix) (%cu-od-radix (first (rest as)))) st)))
          ((string=? a "-t")
            (self (rest (rest as))
              (pair (pair (lit type) (%cu-od-type (first (rest as)))) st)))
          ((string=? a "-N")
            (self (rest (rest as))
              (pair (pair (lit limit) (%cu-num-prefix (first (rest as)))) st)))
          ((string=? a "-j")
            (self (rest (rest as))
              (pair (pair (lit skip) (%cu-num-prefix (first (rest as)))) st)))
          ((string=? a "-v")
            (self (rest as) (pair (pair (lit verbose) #t) st)))
          (#t (self (rest as) (pair (%cu-od-short a) st))))))))

; a shorthand letter, or the operand it turns out to be
(def %cu-od-short
  (fn (_ a)
    (match
      ((string=? a "-c") (pair (lit type) (pair (lit c) 1)))
      ((string=? a "-b") (pair (lit type) (pair (lit o) 1)))
      ((string=? a "-x") (pair (lit type) (pair (lit x) 2)))
      ((string=? a "-d") (pair (lit type) (pair (lit u) 2)))
      ((string=? a "-o") (pair (lit type) (pair (lit o) 2)))
      (#t (pair (lit op) a)))))

; What puts the lines of a run out, sixteen bytes to a line: (RUN AT PREV
; STARRED LAST?) puts every whole line of RUN, and under LAST? the short one
; at its end too.  AT is the address of RUN's first byte -- the addresses
; count from what -j skipped, the way od numbers the bytes of the input rather
; than of what it printed.  A line repeated from the one before, PREV,
; collapses to `*`, unless -v, and STARRED says the `*` is out already.
; Answers (NEXT PREV STARRED), NEXT where the lines stopped.
(def %cu-od-dump
  (fn (_ od-type size rad v?)
    (fn (_ run at prev starred last?)
      (def text (first run))
      (def end (rest run))
      ; a line costs tens of thousands of objects, so the walk sweeps every
      ; 512 bytes, 32 lines, on the byte index it already keeps
      (def go
        (fn (self i prior starred?)
          (let ((stop (if (> (+ i 16) end) end (+ i 16))))
            (if (if (>= i end) #t (if (< (- stop i) 16) (not last?) #f))
              (list i prior starred?)
              (do (%cu-sweep-at i %cu-sweep-steps)
                (let ((body (%cu-od-line text i stop od-type size)))
                  (if (%cu-od-repeat? v? body prior (- stop i))
                    (do (if starred? () (display "*\n"))
                        (self stop body #t))
                    (do (display
                          (string-append (%cu-od-address (+ at i) rad)
                            (string-append body "\n")))
                        (self stop body #f)))))))))
      (go 0 prev starred))))

; od's TAKE: the state is (SKIP LEFT PART AT PREV STARRED) -- the bytes -j has
; still to skip, the bytes -N still takes (-1 for every one), the start of a
; line that waits for the rest of its sixteen bytes, as a run, its address,
; and the line before and whether it was starred.  Once -N has its bytes
; nothing more is read.
(def %cu-od-take
  (fn (_ dump)
    (fn (_ r s)
      (let ((skip (first s)) (left (%cu-nth 1 s)) (end (rest r))
            (part (%cu-nth 2 s)))
        (def from (if (> skip end) end skip))
        (def upto
          (if (if (>= left 0) (< (+ from left) end) #f) (+ from left) end))
        (def text
          (if (= (rest part) 0) (%cu-run-part r from upto)
            (%cu-run-join part r from upto)))
        (def d (dump text (%cu-nth 3 s) (%cu-nth 4 s) (%cu-nth 5 s) #f))
        (def left2 (if (< left 0) left (- left (- upto from))))
        (let ((s2 (list (- skip from) left2
                    (%cu-run-part text (first d) (rest text))
                    (+ (%cu-nth 3 s) (first d)) (%cu-nth 1 d) (%cu-nth 2 d))))
          (if (if (= left2 0) (= skip from) #f) (%cu-enough s2) s2))))))

(def %cu-od-repeat?
  (fn (_ v? body prev width)
    (match
      (v? #f)
      ((null? prev) #f)
      ((string=? body prev) (= width 16))
      (#t #f))))

; -An, -tx1, -N10, -j4: the argument may ride the flag.  Splitting it
; off first keeps the scan a plain token walk.
(def %cu-od-attached?
  (fn (_ a)
    (if (< (byte-len a) 3) #f
      (let ((h (substring a 0 2)))
        (match
          ((string=? h "-A") #t)
          ((string=? h "-t") #t)
          ((string=? h "-N") #t)
          (#t (string=? h "-j")))))))

(def %cu-od-normalize
  (fn (self as acc)
    (if (null? as) (reverse acc)
      (let ((a (first as)))
        (if (%cu-od-attached? a)
          (self (rest as)
            (pair (substring a 2 (byte-len a))
              (pair (substring a 0 2) acc)))
          (self (rest as) (pair a acc)))))))

(def %cu-od
  (fn (_ argv stdin-thunk)
    (def st (%cu-od-scan (%cu-od-normalize argv ()) ()))
    (def ops
      (reverse
        (map (fn (_ e) (rest e))
          (filter (fn (_ e) (eq? (first e) (lit op))) st))))
    (def od-type (%cu-od-opt st (lit type) (pair (lit o) 2)))
    (def lim (%cu-od-opt st (lit limit) (- 0 1)))
    (def rad (%cu-od-opt st (lit radix) (lit o)))
    (def dump (%cu-od-dump (first od-type) (rest od-type) rad (%cu-od-opt st (lit verbose) #f)))
    ; -j skips its bytes first and -N counts from what is left, as od does,
    ; and the lines go out as the input is read.  A file od cannot read is
    ; said, and what the others hold is still dumped.
    (def skip (%cu-od-opt st (lit skip) 0))
    (def g (%cu-fold-said ops stdin-thunk (%cu-says "od") (%cu-od-take dump)
             (list skip lim (pair "" 0) skip () #f)))
    (def s (first g))
    ; a skip past the end is refused the way od refuses it: there is nothing
    ; to number from there.  Otherwise the short line at the end goes out,
    ; and the address past the last byte.
    (if (> (first s) 0)
      (do (file-write 2 "od: cannot skip past end of combined input\n") 1)
      (let ((part (%cu-nth 2 s)))
        (do (dump part (%cu-nth 3 s) (%cu-nth 4 s) (%cu-nth 5 s) #t)
            (if (eq? rad (lit n)) ()
              (display
                (string-append
                  (%cu-od-address (+ (%cu-nth 3 s) (rest part)) rad) "\n")))
            (rest g))))))
; --- uuencode / uudecode --------------------------------------------------------

; the historical alphabet: six bits plus 32, with 0 written as a
; backtick rather than a space (the busybox table)
(def %cu-uu-char
  (fn (_ v) (if (= v 0) 96 (%cu+ v 32))))

(def %cu-uu-value
  (fn (_ b) (if (= b 96) 0 (%cu& (%cu- b 32) 63))))

; the line of the historical encoding that bytes FROM to STOP of S make: its
; length character, then four characters a step of three bytes, the bytes past
; STOP read as 0
(def %cu-uu-line
  (fn (_ s from stop)
    (def at (fn (_ i) (if (%cu< i stop) (byte-at s i) 0)))
    (def go
      (fn (self i acc)
        (if (%cu< i stop)
          (do (def w (%cu+ (%cu<< (byte-at s i) 16)
                           (%cu+ (%cu<< (at (%cu+ i 1)) 8) (at (%cu+ i 2)))))
              (self (%cu+ i 3)
                (pair (%cu-uu-char (%cu& w 63))
                  (pair (%cu-uu-char (%cu& (%cu>> w 6) 63))
                    (pair (%cu-uu-char (%cu& (%cu>> w 12) 63))
                      (pair (%cu-uu-char (%cu>> w 18)) acc))))))
          (bytes->str (reverse acc)))))
    (go from (list (%cu-uu-char (%cu- stop from))))))

; uuencode [FILE] NAME: one operand or two.  There is no GNU build here to
; measure; BSD's refuses any other count with a usage line and 1, and so does
; this one, naming its own options.
(def %cu-uuencode
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "uuencode" argv))
    (def n (length (Opts operands o)))
    (if (if (> n 0) (<= n 2) #f)
      (%cu-uuencode-run o stdin-thunk)
      (do (file-write 2 "uuencode: usage: uuencode [-m] [FILE] NAME\n") 1))))

(def %cu-uuencode-run
  (fn (_ o stdin-thunk)
    (def m? (Opts on? o "-m"))
    (def ops (Opts operands o))
    ; uuencode NAME, or uuencode FILE NAME
    (def name (if (null? ops) "-" (%cu-last ops)))
    (def src (if (pair? (rest ops)) (list (first ops)) ()))
    ; the begin line names the FILE's permissions, as busybox's and the system's
    ; uuencode do, or what the umask leaves of 0666 for standard input
    (def mode
      (let ((st (if (if (null? src) #t (string=? (first src) "-")) ()
                  (file-stat-full (first src)))))
        (if (null? st) (bit-and 438 (bit-xor (sys-umask) 511))
          (bit-and (%cu-stat-get st (lit mode)) 511))))
    ; the input is encoded as it is read, and the begin line goes out with its
    ; first piece, so a FILE that could not be read puts out nothing
    (def begin
      (string-concat
        (list (if m? "begin-base64 " "begin ") (%cu-oct->str mode) " " name
              "\n")))
    (def g (%cu-fold-said src stdin-thunk (%cu-says "uuencode")
             (%cu-uu-take begin m?) (list #f (pair "" 0) () 0)))
    (def s (first g))
    (if (> (rest g) 0) 1
      (do (if (first s) () (display begin))
          (%cu-uu-end m? (%cu-nth 1 s) (%cu-nth 2 s) (%cu-nth 3 s))
          0))))

; uuencode's TAKE: the state is (BEGUN LEFT LINE COL) -- whether the begin line
; is out; the bytes the pieces before left for the next line or step, as a
; run; and under -m the base64 line so far.  The historical encoding puts out
; each whole line of 45 bytes, -m each whole step of three.
(def %cu-uu-take
  (fn (_ begin m?)
    (fn (_ r s)
      (do (if (first s) () (display begin))
          (let ((text (if (= (rest (%cu-nth 1 s)) 0) r
                        (%cu-run-join (%cu-nth 1 s) r 0 (rest r)))))
            (if m?
              (let ((b (%cu-b64-put-from text 76 (%cu-nth 2 s) (%cu-nth 3 s)
                         #f)))
                (list #t (%cu-run-part text (first b) (rest text))
                      (%cu-nth 1 b) (%cu-nth 2 b)))
              (list #t (%cu-run-part text (%cu-uu-lines text) (rest text))
                    () 0)))))))

; the whole lines of 45 bytes run R holds, put out; answers where they stop
(def %cu-uu-lines
  (fn (_ r)
    (def end (rest r))
    (def go
      (fn (self i k)
        (if (> (+ i 45) end) i
          (do (%cu-sweep-at k %cu-sweep-lines)
              (display (string-append (%cu-uu-line (first r) i (+ i 45)) "\n"))
              (self (+ i 45) (+ k 1))))))
    (go 0 0)))

; the end of the encoding: what the pieces left, as the last short line or
; step with its padding, and the terminator
(def %cu-uu-end
  (fn (_ m? left line col)
    (if m?
      (let ((b (%cu-b64-put-from left 76 line col #t)))
        (do (%cu-b64-put-end 76 (%cu-nth 1 b) (%cu-nth 2 b))
            (display "====\n")))
      (do (if (> (rest left) 0)
            (display
              (string-append (%cu-uu-line (first left) 0 (rest left)) "\n"))
            ())
          (display "`\nend\n")))))

; the bytes a line of the historical encoding spells, a list, as many as its
; first character says
(def %cu-uu-decode-line
  (fn (_ line)
    (def n (%cu-uu-value (byte-at line 0)))
    (def end (byte-len line))
    (def at (fn (_ i) (if (%cu< i end) (%cu-uu-value (byte-at line i)) 0)))
    ; a step: four characters, the three bytes they spell, as many of those as
    ; the line still owes kept
    (def go
      (fn (self i out acc)
        (if (if (%cu< i end) (%cu< out n) #f)
          (do (def w (%cu+ (%cu<< (at i) 18)
                           (%cu+ (%cu<< (at (%cu+ i 1)) 12)
                                 (%cu+ (%cu<< (at (%cu+ i 2)) 6) (at (%cu+ i 3))))))
              (def left (%cu- n out))
              (def one (pair (%cu& (%cu>> w 16) 255) acc))
              (def two (if (%cu< 1 left) (pair (%cu& (%cu>> w 8) 255) one) one))
              (self (%cu+ i 4) (%cu+ out 3)
                (if (%cu< 2 left) (pair (%cu& w 255) two) two)))
          (reverse acc))))
    (if (= n 0) () (go 1 0 ()))))

; the list BS, in order, onto the front of ACC, which is newest first
(def %cu-onto
  (fn (self bs acc) (if (null? bs) acc (self (rest bs) (pair (first bs) acc)))))

; uudecode reads either encoding, choosing on the begin line.  -o names
; the output, and `-o -` is stdout -- which is also what the plain form
; writes, where busybox writes the file the begin line names; that
; default predates -o and stays, since the applet protocol is a
; standard-output one and the begin line's name is rarely meant here.
(def %cu-uudecode
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "uudecode" argv))
    (def out (let ((v (Opts value o "-o"))) (if (null? v) "-" v)))
    (def g (%cu-gather-said (Opts operands o) stdin-thunk (%cu-says "uudecode")
             #f))
    (def ls (%cu-lines (first g)))
    (def b64?
      (let ((go (fn (self xs)
                  (if (null? xs) #f
                    (if (if (> (byte-len (first xs)) 12)
                          (string=? (substring (first xs) 0 12) "begin-base64")
                          #f)
                      #t (self (rest xs)))))))
        (go ls)))
    ; the body is what lies between the begin line and the terminator
    (def body
      (let ((skip (fn (self xs)
                    (if (null? xs) ()
                      (if (if (> (byte-len (first xs)) 5)
                            (string=? (substring (first xs) 0 5) "begin") #f)
                        (rest xs)
                        (self (rest xs)))))))
        (let ((stop (fn (self xs acc)
                      (if (null? xs) (reverse acc)
                        (if (if (string=? (first xs) "`") #t
                              (if (string=? (first xs) "end") #t
                                (string=? (first xs) "====")))
                          (reverse acc)
                          (self (rest xs) (pair (first xs) acc)))))))
          (stop (skip ls) ()))))
    ; an input that could not be read has nothing to decode; an -o file that
    ; cannot be written is said as uudecode says it, naming the input first --
    ; stdin when it was read from there.  What decodes is written a run at a
    ; time, by its count, so a NUL goes out with the rest.
    (def fd
      (match
        ((> (rest g) 0) ())
        ((string=? out "-") 1)
        (#t (file-open-or-err file-open-write out))))
    (def from
      (let ((ops (Opts operands o))) (if (null? ops) "stdin" (first ops))))
    (match
      ((> (rest g) 0) 1)
      ((Err err? fd)
        (do (file-write 2
              (string-concat
                (list "uudecode: " from ": " out ": " (file-err-text fd) "\n")))
            1))
      (#t (do (%cu-uu-put-body b64? body (fn (_ r) (file-write-run fd r)))
              (if (= fd 1) () (file-close fd))
              0)))))

; BODY, the lines between the begin line and the terminator, decoded and
; handed to PUT a run of up to 4,096 bytes at a time: base64 under B64?,
; passing over what is not base64, else the historical encoding, a line at a
; time, sweeping every 64 of them
(def %cu-uu-put-body
  (fn (_ b64? body put)
    (def go
      (fn (self ls out n k)
        (match
          ((null? ls) (if (> n 0) (put (%cu-run-bytes (reverse out) n)) ()))
          ((>= n 4096)
            (do (put (%cu-run-bytes (reverse out) n)) (self ls () 0 k)))
          (#t (let ((bs (%cu-uu-decode-line (first ls))))
                (do (%cu-sweep-at k %cu-sweep-lines)
                    (self (rest ls) (%cu-onto bs out) (+ n (length bs))
                      (+ k 1))))))))
    (if b64? (%cu-b64-decode-to (%cu-join-with body "\n") put #t)
      (go (filter (fn (_ l) (> (byte-len l) 0)) body) () 0 0))))

; # x-coreutils -- the small tools, as applets
;
; ## cu/mime.x -- makemime and reformime: MIME messages made and taken apart
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; mailutils/makemime.c: a multipart/mixed message with each FILE (stdin for
; none, or -) a base64 part of its own, 57 bytes to a line, under a boundary
; of three random numbers; -a headers go first, -c and -C set each part's
; content type and charset, -o names the output.
;
; mailutils/reformime.c: a message on stdin taken apart.  Each part's header
; is read to its blank line, and only from its last Content-Type line on --
; so an encoding named before it is not seen; a multipart/mixed part is read
; for its own parts, and each other part, 7bit, 8bit or base64, is written to
; -x PREFIX's file named for it, or given to -X PROG ARGS on its stdin with
; CONTENT_TYPE, CHARSET, ENCODING and FILENAME set.  stdin is read a byte at a
; time, as busybox's stdio reads it: a base64 part ends at a -, and the rest of
; that boundary line is the start of the next part's header.

(module cu/mime)

(import cu/cli cu-opts cu-usage)
(import cu/inetd in-call in-errtext in-exec)
(import cu/perm cu-basename-of)
(import cu/prims append byte-at byte-len cu-int->str cu-libc-sym cu-nth
  cu-ptr-call cu-ptr-ref cu-sig-ign cu-str->ptr file-close file-err-text
  file-open-or-err file-open-read file-read-run file-write length map reverse
  set-first! string-append string=? substring sys-close sys-dup2 sys-exit
  sys-fork sys-getpid sys-pipe sys-setenv sys-signal sys-time-ms sys-wait
  wget-index)
(import cu/telnet tn-run)

(def %mm-charset "us-ascii")

; P without its trailing slashes -- bb_get_last_path_component_strip takes them
; off the argument itself, so the file opened is the stripped one
(def %mm-strip
  (fn (_ p)
    (substring p 0 (let back ((e (byte-len p))) (if (if (> e 1) (= (byte-at p (- e 1)) #\/) #f) (back (- e 1)) e)))))

; bb_get_last_path_component_strip: the last component, trailing slashes gone
(def %mm-last-component
  (fn (_ p)
    (def s (%mm-strip p))
    (if (string=? s "/") s (cu-basename-of s))))

; --- base64 -------------------------------------------------------------------

(def %mm-alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

(def %mm-b64-char (fn (_ v) (substring %mm-alphabet v (+ v 1))))

; bb_uuencode's base64 of BYTES, padded
(def mm-b64
  (fn (_ bytes)
    (let go ((l bytes) (acc ()))
      (if (null? l) (%str-concat (reverse acc))
        (let ((b0 (first l))
              (b1 (if (null? (rest l)) () (first (rest l))))
              (b2 (if (if (null? (rest l)) #t (null? (rest (rest l)))) () (first (rest (rest l))))))
          (def n (+ (* b0 65536) (* (if (null? b1) 0 b1) 256) (if (null? b2) 0 b2)))
          (def c (fn (_ shift) (%mm-b64-char (% (/ (- n (% n shift)) shift) 64))))
          (go (if (null? b2) () (rest (rest (rest l))))
              (pair (%str-concat (list (c 262144) (c 4096) (if (null? b1) "=" (c 64)) (if (null? b2) "=" (%mm-b64-char (% n 64)))))
                    acc)))))))

; the value of base64 character T, 64 for a padding =, or nil
(def %mm-b64-value
  (fn (_ t)
    (match ((if (>= t #\A) (<= t #\Z) #f) (- t #\A))
           ((if (>= t #\a) (<= t #\z) #f) (+ 26 (- t #\a)))
           ((if (>= t #\0) (<= t #\9) #f) (+ 52 (- t #\0)))
           ((= t #\+) 62)
           ((= t #\/) 63)
           (#t ()))))

; --- stdin, a byte at a time --------------------------------------------------------

; the bytes of stdin not yet taken: (BUFFER . POS . COUNT) in a cell
(def mm-in (list ()))
(def %mm-thunk ())
; sendmail and popmaildir hand the message source over with this
(def mm-source! (fn (_ thunk) (set! %mm-thunk thunk)))

(def mm-getc
  (fn (_)
    (def s (first mm-in))
    (if (if (null? s) #f (< (cu-nth 1 s) (cu-nth 2 s)))
      (let ((b (cu-ptr-ref (cu-str->ptr (first s)) (cu-nth 1 s) 1)))
        (do (set-first! mm-in (list (first s) (+ (cu-nth 1 s) 1) (cu-nth 2 s))) b))
      (let ((r (%mm-thunk (lit chunk))))
        (def run (if (pair? r) r (pair r (byte-len r))))
        (if (= (rest run) 0) ()
          (do (set-first! mm-in (list (first run) 0 (rest run))) (mm-getc)))))))

; xmalloc_fgets: the next line with its newline, or nil at the end
(def mm-gets
  (fn (_)
    (let go ((acc ()))
      (let ((c (mm-getc)))
        (match ((null? c) (if (null? acc) () (bytes->str (reverse acc))))
               ((= c #\newline) (bytes->str (reverse (pair c acc))))
               (#t (go (pair c acc))))))))

; --- makemime ----------------------------------------------------------------------

(def cu-makemime
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "makemime" argv))
    (def out (let ((f (Opts value o "-o"))) (if (null? f) 1 (guard (_ -1) (File open f (list (lit wronly) (lit creat) (lit trunc)) 438)))))
    (def say (fn (_ s) (when (>= out 0) (file-write out s))))
    (def type (let ((c (Opts value o "-c"))) (if (null? c) "application/octet-stream" c)))
    (def charset (let ((c (Opts value o "-C"))) (if (null? c) %mm-charset c)))
    (def files (let ((ops (Opts operands o))) (if (null? ops) (list "-") ops)))
    (set! %mm-thunk stdin-thunk)
    (set-first! mm-in ())
    (map (fn (_ h) (say (string-append h "\n"))) (Opts values o "-a"))
    (def r (fn (_) (in-call (cu-ptr-call (cu-libc-sym "random")))))
    (def boundary (%str-concat (list (cu-int->str (r)) "-" (cu-int->str (r)) "-" (cu-int->str (r)))))
    (say (%str-concat (list "Mime-Version: 1.0\nContent-Type: multipart/mixed; boundary=\"" boundary "\"\n")))
    (let go ((fs files))
      (if (null? fs) (do (say (%str-concat (list "\n--" boundary "--\n\n"))) 0)
        (do (say (%str-concat (list "\n--" boundary "\nContent-Type: " type "; charset=" charset
                                      "\nContent-Disposition: inline; filename=\"" (%mm-last-component (first fs))
                                      "\"\nContent-Transfer-Encoding: base64\n")))
            (let ((err (%mm-put-file (%mm-strip (first fs)) say)))
              (if (null? err) (go (rest fs))
                (do (file-write 2 (%str-concat (list "makemime: can't open '" (%mm-strip (first fs)) "': " err "\n")))
                    1))))))))

; a file's bytes, 57 at a time, each piece a base64 line after a newline: nil,
; or why it could not be opened
(def %mm-put-file
  (fn (_ name say)
    (def fd (if (string=? name "-") (lit stdin) (file-open-or-err file-open-read name)))
    (if (Err err? fd) (file-err-text fd)
      (do (set! %mm-fd-buf (list () 0 0))
          (let go ()
            (let ((piece (%mm-read57 fd)))
              (if (null? piece) (do (unless (eq? fd (lit stdin)) (file-close fd)) ())
                (do (say "\n") (say (mm-b64 piece)) (go)))))))))

; up to 57 bytes of FD (or stdin), nil at its end
(def %mm-read57
  (fn (_ fd)
    (let go ((n 0) (acc ()))
      (if (= n 57) (reverse acc)
        (let ((c (if (eq? fd (lit stdin)) (mm-getc) (%mm-fd-getc fd))))
          (if (null? c) (if (null? acc) () (reverse acc)) (go (+ n 1) (pair c acc))))))))

; a file read a piece at a time, a byte handed out at a time
(def %mm-fd-buf (list () 0 0))
(def %mm-fd-getc
  (fn (_ fd)
    (if (< (cu-nth 1 %mm-fd-buf) (cu-nth 2 %mm-fd-buf))
      (let ((b (cu-ptr-ref (cu-str->ptr (first %mm-fd-buf)) (cu-nth 1 %mm-fd-buf) 1)))
        (do (set! %mm-fd-buf (list (first %mm-fd-buf) (+ (cu-nth 1 %mm-fd-buf) 1) (cu-nth 2 %mm-fd-buf))) b))
      (let ((r (file-read-run fd 16384)))
        (if (= (rest r) 0) () (do (set! %mm-fd-buf (list (first r) 0 (rest r))) (%mm-fd-getc fd)))))))

; --- reformime ---------------------------------------------------------------------

(def cu-reformime
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "reformime" argv))
    (if (if (Opts on? o "-X") (not (null? (Opts value o "-x"))) #f) (cu-usage "reformime")
      (do (set! %mm-thunk stdin-thunk)
          (set-first! mm-in ())
          (sys-signal 13 0)
          (guard (e (if (eq? (Err label e) (lit net))
                      (do (file-write 2 (%str-concat (list "reformime: " (e msg) "\n"))) 1)
                      (error e)))
            (%mm-parse ""
              (if (Opts on? o "-X") (Opts operands o) ())
              (let ((x (Opts value o "-x"))) (if (null? x) "" x))))))))

(def %mm-die (fn (_ msg) (Err raise (lit net) msg ())))

; a part's header: everything to the first blank line, CRs dropped; nil at
; the end of the input
(def %mm-header
  (fn (_)
    (let go ((acc ()) (last 0))
      (let ((c (mm-getc)))
        (match ((null? c) (if (null? acc) () (bytes->str (reverse acc))))
               ((= c #\return) (go acc last))
               ((if (= c #\newline) (= last #\newline) #f) (bytes->str (reverse acc)))
               (#t (go (pair c acc) c)))))))

; the header's words from its last Content-Type line on, split at ;="
; space, tab and newline
(def %mm-tokens
  (fn (_ header)
    (def n (byte-len header))
    (def start
      (let go ((i 0) (s 0))
        (let ((nl (wget-index header #\newline i)))
          (if (null? nl) s
            (let ((p (+ nl 1)))
              (go p (if (%mm-ci-prefix? header p "Content-Type:") p s)))))))
    (def delim? (fn (_ c) (match ((= c #\;) #t) ((= c #\=) #t) ((= c #\") #t) ((= c #\space) #t)
                                 ((= c #\tab) #t) (#t (= c #\newline)))))
    (let go ((i start) (from ()) (acc ()))
      (match ((>= i n) (reverse (if (null? from) acc (pair (substring header from n) acc))))
             ((delim? (byte-at header i)) (go (+ i 1) () (if (null? from) acc (pair (substring header from i) acc))))
             (#t (go (+ i 1) (if (null? from) i from) acc))))))

(def mm-ci=
  (fn (_ a b)
    (if (not (= (byte-len a) (byte-len b))) #f
      (let go ((i 0)) (if (>= i (byte-len a)) #t (if (= (Char downcase (byte-at a i)) (Char downcase (byte-at b i))) (go (+ i 1)) #f))))))

(def %mm-ci-prefix?
  (fn (_ s at prefix)
    (if (> (+ at (byte-len prefix)) (byte-len s)) #f (mm-ci= (substring s at (+ at (byte-len prefix))) prefix))))

; find_token: the word after KEY, or DEFAULT
(def %mm-token
  (fn (_ tokens key dflt)
    (let go ((l tokens))
      (match ((null? l) dflt)
             ((mm-ci= (first l) key) (if (null? (rest l)) dflt (first (rest l))))
             (#t (go (rest l)))))))

; parse: the parts under BOUNDARY, each written to PREFIX + its filename or
; given to PROG; the status, PROG's own plus 20 when it fails
(def %mm-parse
  (fn (self boundary prog prefix)
    (let ((header (%mm-header)))
      (if (null? header) 0
        (let ((tokens (%mm-tokens header)))
          (if (null? tokens) 0
            (let ((type (%mm-token tokens "Content-Type:" "text/plain")))
              (if (if (>= (byte-len type) 10) (mm-ci= (substring type 0 10) "multipart/") #f)
                (do (unless (mm-ci= (substring type 10 (byte-len type)) "mixed")
                      (%mm-die (%str-concat (list "no support of content type '" type "'"))))
                    (let ((b (%mm-token tokens "boundary" ())))
                      (when (null? b) (%mm-die "not found: 'boundary'"))
                      (self b prog prefix))
                    (self boundary prog prefix))
                (let ((r (%mm-part boundary prog prefix tokens type)))
                  (match ((> (first r) 0) (first r))
                         ((rest r) 0)
                         (#t (self boundary prog prefix))))))))))))

; one part: (STATUS . ENDED?) -- ENDED? when its boundary closed the multipart
(def %mm-part
  (fn (_ boundary prog prefix tokens type)
    (def charset (%mm-token tokens "charset" %mm-charset))
    (def encoding (%mm-token tokens "Content-Transfer-Encoding:" "7bit"))
    (def named (%mm-token tokens "filename" ()))
    (def filename (if (null? named)
                    (%str-concat (list (cu-int->str (* 1000 (sys-time-ms))) "." (cu-int->str (sys-getpid))))
                    (%mm-last-component named)))
    (def sink (if (null? prog) (%mm-file-sink (string-append prefix filename))
                (%mm-prog-sink prog type charset encoding filename)))
    (def end
      (match
        ((mm-ci= encoding "base64") (do (%mm-read-base64 (first sink)) ()))
        ((if (mm-ci= encoding "7bit") #f (not (mm-ci= encoding "8bit")))
          (do ((rest sink) #f)
              (%mm-die (%str-concat (list "encoding '" encoding "' not supported")))))
        (#t (let go ()
              (let ((line (mm-gets)))
                (match ((null? line) ())
                       ((%mm-boundary? line boundary) line)
                       (#t (do (%mm-write (first sink) line) (go)))))))))
    (def st ((rest sink) #t))
    (pair st (if (null? end) #f
               (let ((at (+ 2 (byte-len boundary))))
                 (if (< (+ at 1) (byte-len end)) (if (= (byte-at end at) #\-) (= (byte-at end (+ at 1)) #\-) #f) #f))))))

(def %mm-boundary?
  (fn (_ line boundary)
    (if (< (byte-len line) (+ 2 (byte-len boundary))) #f
      (if (= (byte-at line 0) #\-) (if (= (byte-at line 1) #\-) (string=? (substring line 2 (+ 2 (byte-len boundary))) boundary) #f) #f))))

(def %mm-write (fn (_ fd s) (guard (_ ()) (file-write fd s))))

; -x: (FD . CLOSE), CLOSE answering the status, 0
(def %mm-file-sink
  (fn (_ name)
    (def fd (file-open-or-err (fn (_ p) (File open p (list (lit wronly) (lit creat) (lit trunc)) 438)) name))
    (when (Err err? fd) (%mm-die (%str-concat (list "can't open '" name "': " (file-err-text fd)))))
    (pair fd (fn (_ ok?) (do (file-close fd) 0)))))

; -X: PROG ARGS on a pipe, its environment set; CLOSE waits for it and answers
; its status
(def %mm-prog-sink
  (fn (_ prog type charset encoding filename)
    (def p (sys-pipe))
    (def pid (sys-fork))
    (when (= pid 0)
      (do (sys-close (rest p))
          (sys-dup2 (first p) 0)
          (sys-close (first p))
          (sys-close 3)
          (sys-setenv "CONTENT_TYPE" type)
          (sys-setenv "CHARSET" charset)
          (sys-setenv "ENCODING" encoding)
          (sys-setenv "FILENAME" filename)
          (sys-signal 13 0)
          (let ((r (in-exec (first prog) prog)))
            (do (file-write 2 (%str-concat (list "reformime: can't execute '" (first prog) "': " (in-errtext r) "\n")))
                (sys-exit 127)))))
    (sys-close (first p))
    (sys-signal 13 cu-sig-ign)
    (pair (rest p)
          (fn (_ ok?)
            (do (sys-close (rest p))
                (sys-signal 13 0)
                (let ((st (% (sys-wait pid) 256)))
                  (if (= st 0) 0 (+ st 20))))))))

; read_base64 with '-' as the end: the input decoded to FD a buffer at a time,
; a buffer ending at a space or control character, the -, or the end, and
; what a buffer leaves undecoded carried to the next
(def %mm-read-base64
  (fn (_ fd)
    (let fill ((carry ()))
      (def got
        (let read ((acc carry) (n (length carry)))
          (if (>= n 80) (pair (reverse acc) #f)
            (let ((ch (mm-getc)))
              (match ((if (null? ch) #t (= ch #\-)) (pair (reverse acc) (if (null? acc) (lit done) #t)))
                     ((<= ch 32) (pair (reverse acc) #f))
                     (#t (read (pair ch acc) (+ n 1))))))))
      (unless (eq? (rest got) (lit done))
        (let ((d (%mm-decode (first got))))
          (do (unless (null? (first d)) (let ((r (tn-run (first d)))) (guard (_ ()) (File write fd (first r) (rest r)))))
              (if (rest got)
                (unless (null? (rest d)) (%mm-die "truncated input"))
                (fill (rest d)))))))))

; decode_base64 over CHARS: (BYTES . LEFT), LEFT the characters of an
; unfinished group; a = in the third or fourth place ends the decoding
(def %mm-decode
  (fn (_ chars)
    (let go ((l chars) (group ()) (out ()))
      (if (null? l) (pair (reverse out) (reverse (map rest group)))
        (let ((t (first l)))
          (def v (%mm-b64-value t))
          (def i (length group))
          (def pad? (if (= t #\=) (if (= i 3) #t (if (= i 2) (if (null? (rest l)) #f (= (first (rest l)) #\=)) #f)) #f))
          (match
            ((if (null? v) (not pad?) #f) (go (rest l) group out))
            ((< i 3) (go (rest l) (append group (list (pair (if pad? 0 v) t))) out))
            (#t (let ((vals (append (map first group) (list (if pad? 0 v)))))
                  (def n (+ (* (first vals) 262144) (* (cu-nth 1 vals) 4096) (* (cu-nth 2 vals) 64) (cu-nth 3 vals)))
                  (def b (list (% (/ (- n (% n 65536)) 65536) 256) (% (/ (- n (% n 256)) 256) 256) (% n 256)))
                  (def pads (+ (if pad? 1 0) (if (= (rest (cu-nth 2 group)) #\=) 1 0)))
                  (def kept (List take (- 3 pads) b))
                  (if (> pads 0) (pair (append (reverse out) kept) (rest l))
                    (go (rest l) () (append (reverse b) out)))))))))))

(provide cu/mime cu-makemime cu-reformime mm-b64 mm-ci= mm-getc mm-gets mm-in
  mm-source!)

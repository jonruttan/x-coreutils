; # x-coreutils -- the small tools, as applets
;
; ## cu/gzip.x -- gzip, gunzip, zcat
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's gzip family (archival/gzip.c, bbunzip.c and libarchive's
; unpack_gz_stream).  gzip writes busybox's header -- no name, mtime 0, OS 3
; -- then the data deflated, then its CRC and length; gunzip
; reads every member in turn, passing over a header's extra field, name,
; comment and CRC, and leaves whatever follows the last member when it is not
; another.  A FILE is replaced by FILE.gz, or FILE.gz (or .tgz) by FILE (or
; .tar), the new file made with the old one's mode and, after gunzip, a
; header's nonzero mtime; -c writes to standard output and keeps the input,
; -k keeps it, -f replaces an output already there, -t only checks.  zcat is
; gunzip -c, and refuses what is not gzip data.
;
; The data goes a piece at a time through x-lang's Deflate and Inflate
; streams, in x, so no C library is wanted (x-os has none): no file is read
; whole.  busybox deflates with code of its own, so a compressed file holds
; the same data but not always the same bytes.

(import x/codec/deflate)
(import x/codec/inflate)
(import x/codec/crc32)

(def %gz-room 32768)

(def %gz-copy (prim-ref (lit mem) (lit copy)))
(def %gz-at (fn (_ p off) (cu-int->ptr (+ ((prim-ref (lit ptr) (lit ->int)) p) off))))

; the run ends: MSG said under the applet's NAME, and the status 1
(def %gz-die
  (fn (_ name msg) (Err raise (lit gzip) (string-concat (list name ": " msg)) ())))

(def %gz-say (fn (_ name msg) (file-write 2 (string-concat (list name ": " msg "\n")))))

; N bytes of BUF written to FD
(def %gz-write!
  (fn (_ fd buf n) (if (> n 0) (File write fd buf n) 0)))

; I as four bytes, low first
(def %gz-le32
  (fn (_ i)
    (bytes->str (list (& i 255) (& (>> i 8) 255) (& (>> i 16) 255) (& (>> i 24) 255)))))

; --- compressing -----------------------------------------------------------------

; A writer of gzip data to FD, in a vector: the deflate stream, the fd, the
; CRC and length of what it has been given, and the piece held back.  busybox's
; header goes out when it is made -- no name, mtime 0, OS 3 (Unix).  A piece is
; held until the next comes or the sink is closed, so the last goes out as the
; stream's final block, as zlib writes it, not an empty final block after it;
; the writer may fill its buffer again, so what is held is a copy.
(def %gz-sink
  (fn (_ fd)
    (def head (str-make-raw 10))
    (do (%gz-fill! head (list 31 139 8 0 0 0 0 0 0 3))
        (%gz-write! fd head 10)
        (vec-build 5
          (fn (_ i)
            (match
              ((= i 0) (Deflate stream))
              ((= i 1) fd)
              ((= i 4) (pair "" 0))
              (#t 0)))))))

; N bytes of BUF deflated, FINAL for the last; what comes out written
(def %gz-sink-step!
  (fn (_ k buf n final)
    (let ((r (Deflate feed (vec-ref k 0) buf 0 n final)))
      (%gz-write! (vec-ref k 1) (first r) (first (rest r))))))

; the piece held before deflated, and N bytes of BUF held in its place;
; counted into the CRC and length
(def %gz-sink-write!
  (fn (_ k buf n)
    (let ((held (vec-ref k 4)))
      (do (%gz-sink-step! k (first held) (rest held) #f)
          (vec-set! k 4 (%gz-held buf n))
          (vec-set! k 2 (Crc32 update (vec-ref k 2) buf 0 n))
          (vec-set! k 3 (& (+ (vec-ref k 3) n) 4294967295))))))

(def %gz-held
  (fn (_ buf n)
    (let ((r (str-make-raw (if (= n 0) 1 n))))
      (do (if (> n 0) (%gz-copy (cu-str->ptr r) (cu-str->ptr buf) n) ()) (pair r n)))))

; the held piece as the stream's end, then the CRC and length
(def %gz-sink-close!
  (fn (_ k)
    (let ((held (vec-ref k 4)))
      (do (%gz-sink-step! k (first held) (rest held) #t)
          (%gz-write! (vec-ref k 1) (%gz-le32 (vec-ref k 2)) 4)
          (%gz-write! (vec-ref k 1) (%gz-le32 (vec-ref k 3)) 4)))))

; SRC's pieces deflated to FD as busybox's gzip writes them
(def %gz-pack!
  (fn (_ src fd)
    (def k (%gz-sink fd))
    (def feed
      (fn (self)
        (let ((p (src)))
          (match
            ((Err err? p) (error p))
            ((= (rest p) 0) ())
            (#t (do (%gz-sink-write! k (first p) (rest p)) (cu-sweep-tick! 0) (self)))))))
    (do (feed)
        (%gz-sink-close! k))))

(def %gz-fill!
  (fn (_ buf bytes)
    (def p (cu-str->ptr buf))
    (def go (fn (self i l) (if (null? l) () (do (cu-ptr-set! p i (first l) 1) (self (+ i 1) (rest l))))))
    (go 0 bytes)))

; --- decompressing -----------------------------------------------------------------

; A reader of a piece source, in a vector: the source, the piece, where in it.
(def %gz-reader (fn (_ src) (vec-build 3 (fn (_ i) (if (= i 0) src ())))))

; the piece being read, a fresh one fetched once it is used up; nil at the end
(def %gz-piece
  (fn (self rd)
    (let ((p (vec-ref rd 1)))
      (if (if (null? p) #f (< (vec-ref rd 2) (rest p))) p
        (let ((q ((vec-ref rd 0))))
          (match
            ((Err err? q) (error q))
            ((= (rest q) 0) ())
            (#t (do (vec-set! rd 1 q) (vec-set! rd 2 0) q))))))))

; the next byte, or nil at the end
(def %gz-byte!
  (fn (_ rd)
    (let ((p (%gz-piece rd)))
      (if (null? p) ()
        (let ((at (vec-ref rd 2)))
          (do (vec-set! rd 2 (+ at 1))
              (& (char->integer (byte-at (first p) at)) 255)))))))

; N bytes as a list, or nil when the data ends first
(def %gz-bytes!
  (fn (_ rd n)
    (def go
      (fn (self k acc)
        (if (= k 0) (reverse acc)
          (let ((b (%gz-byte! rd)))
            (if (null? b) () (self (- k 1) (pair b acc)))))))
    (go n ())))

; bytes up to and past a NUL; #f when the data ends first
(def %gz-past-nul!
  (fn (self rd)
    (let ((b (%gz-byte! rd)))
      (match ((null? b) #f) ((= b 0) #t) (#t (self rd))))))

; the four bytes as a number, low first
(def %gz-u32
  (fn (_ l)
    (+ (first l) (* 256 (+ (first (rest l)) (* 256 (+ (first (rest (rest l)))
                                                       (* 256 (first (rest (rest (rest l))))))))))))

; A member's header after its magic, as check_header_gzip reads it: its mtime,
; or #f where it is cut short or names another method.
(def %gz-header!
  (fn (_ rd)
    (def h (%gz-bytes! rd 8))
    (match
      ((null? h) #f)
      ((not (= (first h) 8)) #f)
      (#t
        (let ((flags (first (rest h))))
          (if (%gz-header-rest! rd flags) (%gz-u32 (rest (rest h))) #f))))))

(def %gz-header-rest!
  (fn (_ rd flags)
    (def extra
      (if (= (& flags 4) 0) #t
        (let ((n (%gz-bytes! rd 2)))
          (if (null? n) #f
            (not (null? (%gz-bytes! rd (+ (first n) (* 256 (first (rest n)))))))))))
    (def name (if (if extra (> (& flags 8) 0) #f) (%gz-past-nul! rd) extra))
    (def note (if (if name (> (& flags 16) 0) #f) (%gz-past-nul! rd) name))
    (if (if note (> (& flags 2) 0) #f) (not (null? (%gz-bytes! rd 2))) note)))

; The inflated pieces of SRC's gzip members, as a piece source answers them,
; (TEXT . COUNT) and (TEXT . 0) at the end.  Bad data raises, with busybox's
; words, under NAME.  MTIME holds the last header's mtime.
(def %gz-inflate-pieces
  (fn (_ name src mtime)
    (def st
      (vec-build 10
        (fn (_ i)
          (match
            ((= i 0) (lit start)) ((= i 1) ())
            ((= i 5) (%gz-reader src)) ((= i 6) (str-make-raw %gz-room))
            ((= i 7) name) ((= i 8) mtime) ((= i 9) ())
            (#t 0)))))
    (fn (_) (%gz-next st))))

; An inflation's state, in a vector: the phase (start, body, trailer, next,
; done), the inflate stream, the CRC and length so far, how much of the
; buffer is filled, the reader, the buffer, the name errors go under, the
; mtime cell, and the full buffers ready to hand out.  As busybox's inflate
; does, data goes out a full buffer at a time or at a member's end, so data
; cut short gives none past its last full buffer.
(def %gz-next
  (fn (self st)
    (def phase (vec-ref st 0))
    (def rd (vec-ref st 5))
    (match
      ((not (null? (vec-ref st 9)))
        (let ((p (first (vec-ref st 9)))) (do (vec-set! st 9 (rest (vec-ref st 9))) p)))
      ((eq? phase (lit done)) (pair (vec-ref st 6) 0))
      ((eq? phase (lit body)) (do (%gz-body! st) (self st)))
      ((eq? phase (lit trailer)) (do (%gz-trailer! st) (self st)))
      ((eq? phase (lit start))
        (if (equal? (%gz-bytes! rd 2) (list 31 139)) (do (%gz-member! st) (self st))
          (%gz-bad st "invalid magic")))
      ; after a member: another, or the end, whatever follows left
      (#t
        (if (equal? (%gz-bytes! rd 2) (list 31 139)) (do (%gz-member! st) (self st))
          (do (vec-set! st 0 (lit done)) (self st)))))))

(def %gz-bad (fn (_ st msg) (%gz-die (vec-ref st 7) msg)))

(def %gz-member!
  (fn (_ st)
    (let ((m (%gz-header! (vec-ref st 5))))
      (if (eq? m #f) (%gz-bad st "corrupted data")
        (do (%set-first! (vec-ref st 8) m)
            (vec-set! st 1 (Inflate stream))
            (vec-set! st 2 0) (vec-set! st 3 0)
            (vec-set! st 0 (lit body)))))))

(def %gz-trailer!
  (fn (_ st)
    (let ((t (%gz-bytes! (vec-ref st 5) 8)))
      (match
        ((null? t) (%gz-bad st "corrupted data"))
        ((not (= (%gz-u32 t) (vec-ref st 2))) (%gz-bad st "crc error"))
        ((not (= (%gz-u32 (rest (rest (rest (rest t))))) (vec-ref st 3)))
          (%gz-bad st "incorrect length"))
        (#t (vec-set! st 0 (lit next)))))))

; the buffer's filled bytes queued to hand out, a copy, counted into the CRC
; and length
(def %gz-emit!
  (fn (_ st)
    (let ((n (vec-ref st 4)) (out (vec-ref st 6)))
      (unless (= n 0)
        (let ((copy (str-make-raw n)))
          (do (%gz-copy (cu-str->ptr copy) (cu-str->ptr out) n)
              (vec-set! st 2 (Crc32 update (vec-ref st 2) out 0 n))
              (vec-set! st 3 (& (+ (vec-ref st 3) n) 4294967295))
              (vec-set! st 4 0)
              (vec-set! st 9 (append (vec-ref st 9) (list (pair copy n))))))))))

; N bytes of OUT from AT into the buffer, each buffer filled queued
(def %gz-take!
  (fn (self st out at n)
    (unless (= n 0)
      (let ((filled (vec-ref st 4)))
        (let ((k (if (< (- %gz-room filled) n) (- %gz-room filled) n)))
          (do (%gz-copy (%gz-at (cu-str->ptr (vec-ref st 6)) filled)
                            (%gz-at (cu-str->ptr out) at) k)
              (vec-set! st 4 (+ filled k))
              (when (= (vec-ref st 4) %gz-room) (%gz-emit! st))
              (self st out (+ at k) (- n k))))))))

; the reader's next piece through the inflate stream; at the member's end
; the bytes after it go back to the reader, the trailer next
(def %gz-body!
  (fn (_ st)
    (let ((rd (vec-ref st 5)))
      (let ((p (%gz-piece rd)))
        (if (null? p) (%gz-bad st "unexpected end of file")
          (let ((at (vec-ref rd 2)) (z (vec-ref st 1)))
            (let ((r (guard (e (if (eq? (cu-err-label e) (lit value)) (%gz-bad st "corrupted data") (error e)))
                       (Inflate feed z (first p) at (- (rest p) at)))))
              (do (vec-set! rd 2 (rest p))
                  (%gz-take! st (first r) 0 (first (rest r)))
                  (when (Inflate done? z)
                    (let ((left (Inflate rest z)))
                      (do (vec-set! rd 1 (pair (first left) (first (rest left))))
                          (vec-set! rd 2 0)
                          (%gz-emit! st)
                          (vec-set! st 0 (lit trailer)))))))))))))
; SRC's members inflated to FD
(def %gz-unpack!
  (fn (_ name src fd mtime)
    (def pieces (%gz-inflate-pieces name src mtime))
    (def go
      (fn (self)
        (let ((p (pieces)))
          (if (= (rest p) 0) () (do (%gz-write! fd (first p) (rest p)) (cu-sweep-tick! 0) (self))))))
    (go)))

; --- the applets -------------------------------------------------------------------

; How a run goes, in a vector: the applet's name, unpacking?, -c, -f, -k, -t,
; zcat's check of the magic.
(def %gz-name (fn (_ t) (vec-ref t 0)))

(def %gz-run-guarded
  (fn (_ thunk)
    (guard (e (if (eq? (cu-err-label e) (lit gzip))
                (do (file-write 2 (string-append (e msg) "\n")) 1)
                (error e)))
      (thunk))))

(def %cu-gzip
  (fn (_ argv stdin-thunk)
    (%gz-run-guarded
      (fn (_)
        (let ((o (cu-opts "gzip" (%gz-levels-gone argv))))
          (%gz-files (%gz-settings "gzip" o (if (%gz-on? o "-d" "--decompress") #t
                                              (if (%gz-on? o "--uncompress" "-t") #t
                                                (Opts on? o "--test"))) #f)
            (Opts operands o) stdin-thunk))))))

(def %cu-gunzip
  (fn (_ argv stdin-thunk)
    (%gz-run-guarded
      (fn (_)
        (let ((o (cu-opts "gunzip" argv)))
          (%gz-files (%gz-settings "gunzip" o #t #f) (Opts operands o) stdin-thunk))))))

(def %cu-zcat
  (fn (_ argv stdin-thunk)
    (%gz-run-guarded
      (fn (_)
        (let ((o (cu-opts "zcat" argv)))
          (%gz-files (%gz-settings "zcat" o #t #t) (Opts operands o) stdin-thunk))))))

(def %gz-on? (fn (_ o a b) (if (Opts on? o a) #t (Opts on? o b))))

(def %gz-settings
  (fn (_ name o unpack zcat)
    (vec-build 7
      (fn (_ i)
        (match
          ((= i 0) name) ((= i 1) unpack)
          ((= i 2) (if zcat #t (if (%gz-on? o "-c" "--stdout") #t (Opts on? o "--to-stdout"))))
          ((= i 3) (%gz-on? o "-f" "--force"))
          ((= i 4) (Opts on? o "-k"))
          ((= i 5) (%gz-on? o "-t" "--test"))
          (#t zcat))))))

; bbunpack: each name, or standard input; the status
(def %gz-files
  (fn (_ t names stdin-thunk)
    (def go
      (fn (self l status)
        (if (null? l) status
          (self (rest l) (if (= (%gz-one t (first l) stdin-thunk) 0) status 1)))))
    (go (if (null? names) (list "-") names) 0)))

; FILE.gz for FILE, or FILE for FILE.gz and FILE.tar for FILE.tgz; nil for
; another suffix
(def %gz-new-name
  (fn (_ t file)
    (if (not (vec-ref t 1)) (string-append file ".gz")
      (let ((n (byte-len file)))
        (match
          ((%gz-ends? file ".gz") (substring file 0 (- n 3)))
          ((%gz-ends? file ".tgz") (string-append (substring file 0 (- n 4)) ".tar"))
          (#t ()))))))

(def %gz-ends?
  (fn (_ s e)
    (if (< (byte-len s) (byte-len e)) #f
      (string=? (substring s (- (byte-len s) (byte-len e)) (byte-len s)) e))))

; One name, as bbunpack takes it; 0, or 1 where it failed.
(def %gz-one
  (fn (_ t file stdin-thunk)
    (def name (%gz-name t))
    (def stdin? (string=? file "-"))
    (def st (if stdin? () (file-stat-full file)))
    (match
      ((if (not stdin?) (null? st) #f)
        (do (%gz-say name (string-concat (list file ": " (%gz-why (lit stat) file)))) 1))
      (#t
        (let ((src (cu-pieces file stdin-thunk)))
          (if (Err err? src)
            (do (%gz-say name (string-concat (list file ": " (file-err-text src)))) 1)
            (%gz-to t file stdin? st (%gz-checked t src))))))))

(def %gz-why
  (fn (_ op name) (file-err-text (Err from-errno (Err errno-of -1) op name))))

; zcat refuses what does not begin with gzip's magic; the source, its first
; piece put back
(def %gz-checked
  (fn (_ t src)
    (if (not (vec-ref t 6)) src
      (let ((p (src)))
        (if (Err err? p) (error p)
          (if (if (>= (rest p) 2)
                (if (= (char->integer (byte-at (first p) 0)) 31)
                  (= (char->integer (byte-at (first p) 1)) 139) #f) #f)
            (let ((first? (list #t)))
              (fn (_ . how)
                (if (pair? how) (src (first how))
                  (if (first first?) (do (%set-first! first? #f) p) (src)))))
            (%gz-die (%gz-name t) "no gzip/bzip2/xz magic")))))))

; where the run's output goes, and what is removed after
(def %gz-to
  (fn (_ t file stdin? st src)
    (def name (%gz-name t))
    (def to-file (not (if stdin? #t (if (vec-ref t 2) #t (vec-ref t 5)))))
    (def new (if to-file (%gz-new-name t file) ()))
    (match
      ((if to-file (null? new) #f)
        (do (%gz-close-src src) (%gz-say name (string-append file ": unknown suffix - ignored")) 1))
      ((not to-file)
        (let ((fd (if (vec-ref t 5) (file-open-wronly "/dev/null") 1)))
          (let ((r (%gz-work t src fd (list 0))))
            (do (%gz-close-src src) (if (vec-ref t 5) (file-close fd) ()) r))))
      (#t (%gz-to-file t file st src new)))))

(def %gz-close-src (fn (_ src) (src (lit close))))

(def %gz-to-file
  (fn (_ t file st src new)
    (def name (%gz-name t))
    (def mode (& (%cu-stat-get st (lit mode)) 4095))
    (if (vec-ref t 3) (guard (e ()) (file-unlink new)) ())
    (let ((fd (File open new (list (lit wronly) (lit creat) (lit excl)) mode)))
      (if (< fd 0)
        (do (%gz-close-src src)
            (%gz-say name (string-concat (list "can't open '" new "': " (file-err-text (file-open-err fd new)))))
            1)
        (let ((mtime (list 0)))
          ; an error gzip does not say itself still takes the new file away
          (let ((r (guard (e (do (%gz-close-src src) (file-close fd) (guard (_ ()) (file-unlink new)) (error e)))
                     (%gz-work t src fd mtime))))
            (do (%gz-close-src src)
                (file-close fd)
                (if (= r 0)
                  (do (if (= (first mtime) 0) () (guard (e ()) (file-set-times new (first mtime) (first mtime))))
                      (if (vec-ref t 4) () (guard (e ()) (file-unlink file))))
                  (guard (e ()) (file-unlink new)))
                r)))))))

; the data packed or unpacked to FD; 0, or 1 where it was bad (said)
(def %gz-work
  (fn (_ t src fd mtime)
    (guard (e (if (eq? (cu-err-label e) (lit gzip))
                (do (file-write 2 (string-append (e msg) "\n")) 1)
                (error e)))
      (do (if (vec-ref t 1) (%gz-unpack! (%gz-name t) src fd mtime) (%gz-pack! src fd))
          0))))

; ARGV with gzip's levels taken out of the options before --: busybox reads
; and ignores -1 to -9, and a word that begins with a dash and a digit is
; otherwise an operand.  Its other letters stay, so -9c is -c.
(def %gz-levels-gone
  (fn (self argv)
    (match
      ((null? argv) ())
      ((string=? (first argv) "--") argv)
      ((%gz-level-word? (first argv))
        (let ((letters (filter (fn (_ c) (not (%gz-digit? c))) (rest (%gz-word-bytes (first argv))))))
          (if (null? letters) (self (rest argv))
            (pair (bytes->str (pair 45 letters)) (self (rest argv))))))
      (#t (pair (first argv) (self (rest argv)))))))

(def %gz-digit? (fn (_ c) (if (>= c 49) (<= c 57) #f)))

(def %gz-level-word?
  (fn (_ w)
    (if (> (byte-len w) 1)
      (if (= (char->integer (byte-at w 0)) 45) (%gz-digit? (char->integer (byte-at w 1))) #f)
      #f)))

(def %gz-word-bytes
  (fn (_ w)
    (def go (fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (char->integer (byte-at w i)) acc)))))
    (go (- (byte-len w) 1) ())))

; --- tar's z ------------------------------------------------------------------------

; SRC's pieces inflated for tar, as busybox's child gunzip hands them over: an
; error is said, under tar's name, and the data ends there, for tar to say
; what it makes of that.
(def %gz-tar-pieces
  (fn (_ src)
    (def pieces (%gz-inflate-pieces "tar" src (list 0)))
    (def over (list #f))
    (def none (str-make-raw 1))
    (fn (_ . how)
      (match
        ((pair? how) (src (first how)))
        ((first over) (pair none 0))
        (#t (guard (e (if (eq? (cu-err-label e) (lit gzip))
                        (do (file-write 2 (string-append (e msg) "\n"))
                            (%set-first! over #t)
                            (pair none 0))
                        (error e)))
              (pieces)))))))

; SRC with its first piece looked at: (GZIP? . SOURCE), the source handing
; that piece out again first
(def %gz-sniff
  (fn (_ src)
    (let ((p (src)))
      (if (Err err? p) (pair #f (fn (_ . how) (if (pair? how) (src (first how)) p)))
        (let ((again (list #t)))
          (pair (if (>= (rest p) 2)
                  (if (= (char->integer (byte-at (first p) 0)) 31)
                    (= (char->integer (byte-at (first p) 1)) 139) #f) #f)
                (fn (_ . how)
                  (if (pair? how) (src (first how))
                    (if (first again) (do (%set-first! again #f) p) (src))))))))))

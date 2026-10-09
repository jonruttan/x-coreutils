; # x-coreutils -- the small tools, as applets
;
; ## cu/unzip.x -- unzip
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's unzip (archival/unzip.c).  The members of a ZIP archive are
; listed (-l, -v for the methods and CRCs), written to standard output (-p),
; read and checked (-t), or made: directories, files with the modes a Unix
; archive gives them, symbolic links.  Names choose members, as globs, and -x
; leaves some out; -j drops their paths and -d makes them under a directory.
; A file already there is kept (-n), replaced (-o), or asked about.
;
; As busybox reads it: the central directory, found by the end record in the
; last 64 KB, says where each member's local header is; where there is none,
; the headers are read one after another from where the search left the file
; -- its end, so the read comes up short.  Standard input will not seek here,
; so `-` is always read that way, from its start, as busybox reads a pipe.
; Members are stored or deflated: deflate goes through Zlib's streams (as
; gzip's does, cu/gzip.x), and a busybox built without bzip2, lzma and xz
; refuses the rest as an unsupported method.
;
; The archive is read a piece at a time through tar's reader (cu/tar.x),
; which a seek starts afresh.

(import x/codec/zlib)

(def %uz-room 32768)

; the run ends: MSG said under unzip's name, and the status 1
(def %uz-die (fn (_ msg) (Err raise (lit unzip) (string-append "unzip: " msg) ())))

(def %uz-say (fn (_ msg) (file-write 2 (string-concat (list "unzip: " msg "\n")))))

; --- the run --------------------------------------------------------------------

; A run, in a vector: where its own lines go (standard output, or /dev/null
; under -t), how quiet, how verbose, the overwrite answer (prompt, never or
; always), the names to take and to leave, -l, -j, -K, where members' data
; goes under -p or -t (nil when they are made as files), the archive's reader,
; its descriptor (nil for standard input), where the reader's count began,
; standard input's unread answer text, the links held back, and whether a
; name has been cut.
(def %uz-out (fn (_ u) (vec-ref u 0)))
(def %uz-quiet (fn (_ u) (vec-ref u 1)))
(def %uz-verbose (fn (_ u) (vec-ref u 2)))
(def %uz-overwrite (fn (_ u) (vec-ref u 3)))
(def %uz-data-fd (fn (_ u) (vec-ref u 9)))
(def %uz-rd (fn (_ u) (vec-ref u 10)))
(def %uz-fd (fn (_ u) (vec-ref u 11)))

(def %uz-print (fn (_ u s) (file-write (%uz-out u) s)))

; --- the archive's bytes ----------------------------------------------------------

; the reader moved to OFF in the archive
(def %uz-seek!
  (fn (_ u off)
    (def rd (%uz-rd u))
    (do (File seek (%uz-fd u) off)
        (vec-set! rd 1 ())
        (vec-set! rd 2 ())
        (vec-set! rd 3 0)
        (vec-set! u 12 off))))

; where the reader is in the archive
(def %uz-pos (fn (_ u) (+ (vec-ref u 12) (vec-ref (%uz-rd u) 3))))

; N bytes into a buffer of their own; short, the run ends
(def %uz-read!
  (fn (_ u n)
    (def buf (%str-make-raw (+ n 1)))
    (if (< (%tar-fill! (%uz-rd u) buf 0 n) n) (%uz-die "short read") buf)))

; past N bytes: sought over in a file, read through on standard input
(def %uz-skip!
  (fn (_ u n)
    (match
      ((= n 0) ())
      ((null? (%uz-fd u)) (if (< (%tar-skip! (%uz-rd u) n) n) (%uz-die "short read") ()))
      (#t (%uz-seek! u (+ (%uz-pos u) n))))))

(def %uz-u16 (fn (_ b i) (+ (& (byte-at b i) 255) (* 256 (& (byte-at b (+ i 1)) 255)))))
(def %uz-u32 (fn (_ b i) (+ (%uz-u16 b i) (* 65536 (%uz-u16 b (+ i 2))))))

(def %uz-local-magic 67324752)
(def %uz-cdf-magic 33639248)
(def %uz-end-magic 101010256)
(def %uz-end64-magic 101075792)
(def %uz-dd-magic 134695760)

; --- the central directory ------------------------------------------------------

; busybox's find_cdf_offset: the central directory's offset from the last end
; record in the archive's last 64 KB that points before itself, or #f.  The
; archive is left at its end, or where it was when it will not seek.
(def %uz-find-cdf
  (fn (_ u)
    (def fd (%uz-fd u))
    (def size (if (null? fd) -1 (File seek fd 0 (lit end))))
    (if (< size 0) #f
      (let ((end (if (> size 65536) (- size 65536) 0)))
        (do (%uz-seek! u end)
            (let ((buf (%str-make-raw 65537)))
              (let ((n (%tar-fill! (%uz-rd u) buf 0 65536)))
                (%uz-scan-end buf n end))))))))

(def %uz-scan-end
  (fn (_ buf n end)
    (def at (fn (_ i) (if (< i n) (& (byte-at buf i) 255) 0)))
    (def go
      (fn (self i found)
        (if (if (> i (- n 4)) #t (> i 65516)) found
          (if (if (= (at i) #\P) (if (= (at (+ i 1)) #\K) (if (= (at (+ i 2)) 5) (= (at (+ i 3)) 6) #f) #f) #f)
            (let ((off (+ (+ (at (+ i 16)) (* 256 (at (+ i 17)))) (+ (* 65536 (at (+ i 18))) (* 16777216 (at (+ i 19)))))))
              (self (+ i 4) (if (< off (+ end (+ i 3))) off found)))
            (self (+ i 1) found)))))
    (go 0 #f)))

; busybox's read_next_cdf: the entry at OFF, as (NEXT . ENTRY), or nil where
; the directory ends there
(def %uz-next-cdf
  (fn (_ u off)
    (do (%uz-seek! u off)
        (let ((magic (%uz-u32 (%uz-read! u 4) 0)))
          (if (if (= magic %uz-end-magic) #t (= magic %uz-end64-magic)) ()
            (let ((c (%uz-read! u 42)))
              (pair (+ (+ off 46) (+ (%uz-u16 c 24) (+ (%uz-u16 c 26) (%uz-u16 c 28)))) c)))))))

; --- the members ------------------------------------------------------------------

; A local header's fields after its magic, in a vector: flags, method, time,
; date, CRC, compressed size, size, the name's length, the extra field's.
(def %uz-header
  (fn (_ h)
    (vec-build 9
      (fn (_ i)
        (match
          ((= i 0) (%uz-u16 h 2)) ((= i 1) (%uz-u16 h 4)) ((= i 2) (%uz-u16 h 6))
          ((= i 3) (%uz-u16 h 8)) ((= i 4) (%uz-u32 h 10)) ((= i 5) (%uz-u32 h 14))
          ((= i 6) (%uz-u32 h 18)) ((= i 7) (%uz-u16 h 22)) (#t (%uz-u16 h 24)))))))

(def %uz-flags (fn (_ z) (vec-ref z 0)))
(def %uz-method (fn (_ z) (vec-ref z 1)))
(def %uz-crc (fn (_ z) (vec-ref z 4)))
(def %uz-csize (fn (_ z) (vec-ref z 5)))
(def %uz-size (fn (_ z) (vec-ref z 6)))

; The next member's header and the modes it is made with, as (Z FILE-MODE .
; DIR-MODE); nil at the end of the archive.  CDF holds the central
; directory's next offset, #f where there is none.
(def %uz-next-member
  (fn (self u cdf)
    (if (eq? (first cdf) #f) (%uz-next-local self u cdf)
      (let ((e (%uz-next-cdf u (first cdf))))
        (if (null? e) ()
          (do (%set-first! cdf (first e))
              (%uz-seek! u (+ (%uz-u32 (rest e) 38) 4))
              (let ((z (%uz-header (%uz-read! u 26))) (c (rest e)))
                (do (if (= (& (%uz-flags z) 8) 0) ()
                      (do (vec-set! z 4 (%uz-u32 c 12)) (vec-set! z 5 (%uz-u32 c 16)) (vec-set! z 6 (%uz-u32 c 20))))
                    (if (= (>> (%uz-u16 c 0) 8) 3)
                      (let ((m (>> (%uz-u32 c 34) 16)))
                        (let ((mode (if (vec-ref u 8) m (& m (- 65535 3072)))))
                          (pair z (pair mode mode))))
                      (pair z (pair 438 511)))))))))))

; the next local header read where the archive is, as busybox reads one with
; no central directory: a data descriptor is passed over, and the central
; directory ends it
(def %uz-next-local
  (fn (_ again u cdf)
    (let ((magic (%uz-u32 (%uz-read! u 4) 0)))
      (match
        ((= magic %uz-cdf-magic) ())
        ((= magic %uz-dd-magic) (do (%uz-skip! u 12) (again u cdf)))
        ((not (= magic %uz-local-magic))
          (%uz-die (string-append "invalid zip magic " (%cu-pad-zero (%dp-udigits magic 16 #t) 8))))
        (#t (let ((z (%uz-header (%uz-read! u 26))))
              (if (= (& (%uz-flags z) 8) 0) (pair z (pair 438 511))
                (%uz-die "zip flag 8 (streaming) is not supported"))))))))

; --- names --------------------------------------------------------------------------

; NAME with busybox's skip_unsafe_prefix taken off (cu/tar.x); the first time a
; run takes something off, it says so
(def %uz-safe
  (fn (_ u name)
    (def cut (%cu-unsafe-prefix name))
    (do (if (if (> cut 0) (not (vec-ref u 14)) #f)
          (do (vec-set! u 14 #t)
              (%uz-say (string-concat (list "removing leading '" (substring name 0 cut) "' from member names"))))
          ())
        (substring name cut (byte-len name)))))

; NAME is one the run takes: in no -x glob, and in a FILE glob where any are given
(def %uz-wanted?
  (fn (_ u name)
    (def any (fn (self pats) (if (null? pats) #f (if (%cu-glob? (first pats) name) #t (self (rest pats))))))
    (match
      ((any (vec-ref u 5)) #f)
      ((null? (vec-ref u 4)) #t)
      (#t (any (vec-ref u 4))))))

(def %uz-ends-slash? (fn (_ s) (if (> (byte-len s) 0) (= (byte-at s (- (byte-len s) 1)) #\/) #f)))

; --- listing ------------------------------------------------------------------------

(def %uz-2 (fn (_ n) (%cu-pad-zero (%cu-int->str n) 2)))

; the member's date and time, mm-dd-yyyy hh:mm
(def %uz-when
  (fn (_ z)
    (def d (vec-ref z 3))
    (def t (vec-ref z 2))
    (string-concat
      (list (%uz-2 (& (>> d 5) 15)) "-" (%uz-2 (& d 31)) "-" (%cu-pad-zero (%cu-int->str (+ (>> d 9) 1980)) 4) " "
            (%uz-2 (>> t 11)) ":" (%uz-2 (& (>> t 5) 63))))))

; how much of USIZE compression saved, in percent; nothing where it grew
(def %uz-ratio
  (fn (_ usize csize)
    (if (if (= usize 0) #t (< usize csize)) 0 (%cal/ (* (- usize csize) 100) usize))))

(def %uz-method-name
  (fn (_ z)
    (match
      ((= (%uz-method z) 0) "Stored")
      ((= (%uz-method z) 8)
        (string-append "Defl:" (substring "NXFS" (& (>> (%uz-flags z) 1) 3) (+ (& (>> (%uz-flags z) 1) 3) 1))))
      (#t (%cu-pad-left (%cu-int->str (%uz-method z)) 6)))))

; member Z's line, NAME its name; its sizes counted into the totals
(def %uz-list!
  (fn (_ u z name tot)
    (do (%uz-print u
          (if (= (%uz-verbose u) 0)
            (string-concat (list (%cu-pad-left (%cu-int->str (%uz-size z)) 9) "  " (%uz-when z) "   "
                                 (%tar-printable name) "\n"))
            (string-concat (list (%cu-pad-left (%cu-int->str (%uz-size z)) 8) "  " (%uz-method-name z)
                                 (%cu-pad-left (%cu-int->str (%uz-csize z)) 9)
                                 (%cu-pad-left (%cu-int->str (%uz-ratio (%uz-size z) (%uz-csize z))) 4) "% "
                                 (%uz-when z) " " (%cu-pad-zero (%dp-udigits (%uz-crc z) 16 #f) 8) "  "
                                 (%tar-printable name) "\n"))))
        (vec-set! tot 0 (+ (vec-ref tot 0) (%uz-size z)))
        (vec-set! tot 1 (+ (vec-ref tot 1) (%uz-csize z))))))

(def %uz-totals!
  (fn (_ u tot)
    (def files (string-append (%cu-int->str (vec-ref tot 2)) " files\n"))
    (%uz-print u
      (if (= (%uz-verbose u) 0)
        (string-concat (list " --------" (%cu-pad-left "" 21) "-------\n"
                             (%cu-pad-left (%cu-int->str (vec-ref tot 0)) 9) (%cu-pad-left "" 21) files))
        (string-concat (list "--------          ------- ----" (%cu-pad-left "" 28) "----\n"
                             (%cu-pad-left (%cu-int->str (vec-ref tot 0)) 8)
                             (%cu-pad-left (%cu-int->str (vec-ref tot 1)) 17)
                             (%cu-pad-left (%cu-int->str (%uz-ratio (vec-ref tot 0) (vec-ref tot 1))) 4) "%"
                             (%cu-pad-left "" 28) files))))))

; --- the data -----------------------------------------------------------------------

; busybox's unzip_extract: member Z's data written to FD -- stored, copied;
; deflated, inflated and its CRC checked
(def %uz-extract!
  (fn (_ u z fd)
    (match
      ((= (%uz-method z) 0)
        (if (< (%tar-copy-out! (%uz-rd u) fd (%uz-size z)) (%uz-size z)) (%uz-die "short read") ()))
      ((= (%uz-method z) 8)
        (let ((r (%uz-inflate! u z fd)))
          (match
            ((not (= (first r) (%uz-crc z))) (%uz-die "crc error"))
            ((if (= (%uz-size z) 4294967295) #f (not (= (rest r) (%uz-size z)))) (%uz-say "bad length"))
            (#t ()))))
      (#t (%uz-die (string-append "unsupported method " (%cu-int->str (%uz-method z))))))))

; Z's compressed bytes inflated to FD a buffer at a time; (CRC . LENGTH).
; Bad data is said in busybox's words, and the run ends.
(def %uz-inflate!
  (fn (_ u z fd)
    (def rd (%uz-rd u))
    (def s (Zlib inflater (lit raw)))
    (def out (%str-make-raw %uz-room))
    ; the CRC, the length, how much of OUT is filled, the input left
    (def st (vec-build 4 (fn (_ i) (if (= i 3) (%uz-csize z) 0))))
    (def emit!
      (fn (_)
        (let ((n (vec-ref st 2)))
          (do (if (> n 0) (File write fd out n) ())
              (vec-set! st 0 (Zlib crc32 (vec-ref st 0) out n))
              (vec-set! st 1 (+ (vec-ref st 1) n))
              (vec-set! st 2 0)))))
    (def bad
      (fn (_ msg) (do (Zlib end s) (%uz-say msg) (%uz-die "inflate error"))))
    ; with the input used up, inflate is called with none, for what it holds
    (def go
      (fn (self)
        (let ((p (if (> (vec-ref st 3) 0) (%uz-piece rd) ())))
          (let ((at (if (null? p) 0 (vec-ref rd 2))) (filled (vec-ref st 2)))
            (let ((r (guard (e (if (eq? (%cu-err-label e) (lit value)) (bad "corrupted data") (error e)))
                       (Zlib step s (if (null? p) "" (first p)) at
                         (if (null? p) 0 (%tar-min (- (rest p) at) (vec-ref st 3)))
                         out filled (- %uz-room filled) #f))))
              (do (if (null? p) ()
                    (do (vec-set! rd 2 (+ at (first r)))
                        (vec-set! rd 3 (+ (vec-ref rd 3) (first r)))
                        (vec-set! st 3 (- (vec-ref st 3) (first r)))))
                  (vec-set! st 2 (+ filled (first (rest r))))
                  (match
                    ((eq? (first (rest (rest r))) (lit end)) (emit!))
                    ((= (vec-ref st 2) %uz-room) (do (emit!) (self)))
                    ((if (null? p) (= (first (rest r)) 0) #f) (bad "unexpected end of file"))
                    (#t (self)))))))))
    (do (go)
        (Zlib end s)
        (%uz-skip! u (vec-ref st 3))
        (pair (vec-ref st 0) (vec-ref st 1)))))

; the piece the reader is in, a fresh one fetched once it is used up; nil at
; the end
(def %uz-piece
  (fn (_ rd)
    (let ((p (vec-ref rd 1)) (at (vec-ref rd 2)))
      (if (if (null? p) #f (< (if (null? at) 0 at) (rest p))) (do (if (null? at) (vec-set! rd 2 0) ()) p)
        (let ((q ((vec-ref rd 0))))
          (if (if (Err err? q) #t (= (rest q) 0)) ()
            (do (vec-set! rd 1 q) (vec-set! rd 2 0) q)))))))

; busybox's unzip_extract_symlink: the target, stored, is the data; the link
; is made at once, or last where it points at an absolute path or through ..
(def %uz-symlink!
  (fn (_ u z name)
    (if (> (%uz-size z) 4095) (%uz-die "bad archive")
      (if (not (= (%uz-method z) 0)) (%uz-die "compressed symlink is not supported")
        (let ((target (%tar-field (%uz-read! u (%uz-size z)) 0 (%uz-size z))))
          (if (if (if (> (byte-len target) 0) (= (byte-at target 0) #\/) #f) #t (>= (%tar-find-str target "..") 0))
            (vec-set! u 13 (pair (pair name target) (vec-ref u 13)))
            (if (guard (e #f) (do (file-symlink target name) #t)) ()
              (%uz-die (string-concat (list "can't create symlink '" name "' to '" target "': "
                                            (%tar-why (lit symlink) name)))))))))))

(def %uz-make-links!
  (fn (_ u)
    (map (fn (_ l)
           (if (guard (e #f) (do (file-symlink (rest l) (first l)) #t)) ()
             (%uz-die (string-concat (list "can't create symlink '" (first l) "' to '" (rest l) "'")))))
         (reverse (vec-ref u 13)))))

; --- making the members ---------------------------------------------------------------

; MODE's file type bits
(def %uz-type (fn (_ mode) (& mode 61440)))

; the mode of what is at NAME, not followed; nil where nothing is, and the
; run ends where it cannot be asked
(def %uz-lstat-mode
  (fn (_ name)
    (let ((st (file-lstat-full name)))
      (match
        ((not (null? st)) (%cu-stat-get st (lit mode)))
        ((= (Err errno-of -1) 2) ())
        (#t (%uz-die (string-concat (list "can't stat '" name "': " (%tar-why (lit lstat) name)))))))))

; PATH made, its parents first, as busybox's bb_make_directory does with
; FILEUTILS_RECUR: one already there is passed over
(def %uz-mkdirs!
  (fn (_ path)
    (def n (byte-len path))
    (def one
      (fn (_ p)
        (if (>= (Sys %sign-fold (%cu-ptr-call %tar-c-mkdir p 511)) 0) ()
          (let ((why (%tar-why (lit mkdir) p)))
            (if (eq? (%uz-type-of p) 16384) ()
              (%uz-die (string-concat (list "can't create directory '" p "': " why))))))))
    (def go
      (fn (self i)
        (match
          ((>= i n) (one path))
          ((if (= (byte-at path i) #\/) (> i 0) #f)
            (do (one (substring path 0 i))
                (self (%uz-past-slashes path (+ i 1)))))
          (#t (self (+ i 1))))))
    (if (if (= n 0) #t (if (string=? path ".") #t (string=? path "/"))) () (go 0))))

(def %uz-type-of
  (fn (_ p) (let ((st (file-stat-full p))) (if (null? st) () (%uz-type (%cu-stat-get st (lit mode)))))))

(def %uz-past-slashes
  (fn (self s i) (if (if (< i (byte-len s)) (= (byte-at s i) #\/) #f) (self s (+ i 1)) i)))

; the directories NAME is made in
(def %uz-leading-dirs!
  (fn (_ name)
    (let ((sl (%tar-last-slash (%uz-unslash name))))
      (if (> sl 0) (%uz-mkdirs! (%uz-unslash (substring name 0 sl))) ()))))

(def %uz-unslash
  (fn (self s) (if (if (> (byte-len s) 1) (%uz-ends-slash? s) #f) (self (substring s 0 (- (byte-len s) 1))) s)))

; a directory member NAME, made with MODE unless something is there already
(def %uz-directory!
  (fn (_ u name mode)
    (let ((there (%uz-lstat-mode name)))
      (match
        ((null? there)
          (do (if (= (%uz-quiet u) 0) (%uz-print u (string-append "   creating: " (%tar-printable name) "\n")) ())
              (%uz-leading-dirs! name)
              (if (< (Sys %sign-fold (%cu-ptr-call %tar-c-mkdir name 511)) 0)
                (%uz-die (string-concat (list "can't create directory '" name "': " (%tar-why (lit mkdir) name))))
                (if (guard (e #f) (do (file-chmod name (& mode 4095)) #t)) ()
                  (%uz-say (string-concat (list "can't set permissions of directory '" name "': "
                                                (%tar-why (lit chmod) name))))))))
        ((= (%uz-type there) 16384) ())
        (#t (%uz-die (string-concat (list "'" (%tar-printable name) "' exists but is not a directory"))))))))

(def %uz-not-file
  (fn (_ name) (%uz-die (string-concat (list "'" (%tar-printable name) "' exists but is not a regular file")))))

; Member Z, a file or link to be made at NAME, as busybox's check_file goes:
; made where nothing is there, passed over under -n, made over under -o, and
; otherwise asked about.  #t where it was made.
(def %uz-place!
  (fn (self u z name mode)
    (let ((there (%uz-lstat-mode name)))
      (match
        ((null? there) (%uz-make! u z name mode))
        ((eq? (%uz-overwrite u) (lit never)) #f)
        ((not (= (%uz-type there) 32768)) (%uz-not-file name))
        ((eq? (%uz-overwrite u) (lit always)) (%uz-make! u z name mode))
        (#t
          (do (%uz-print u (string-concat (list "replace " (%tar-printable name)
                                                "? [y]es, [n]o, [A]ll, [N]one, [r]ename: ")))
              (let ((key (%uz-answer u)))
                (let ((now (%uz-lstat-mode name)))
                  (if (if (null? now) #t (not (= (%uz-type now) 32768))) (%uz-not-file name)
                    (%uz-answered self u z name mode key))))))))))

(def %uz-answered
  (fn (_ again u z name mode key)
    (def c (if (> (byte-len key) 0) (byte-at key 0) 0))
    (match
      ((= c #\A) (do (vec-set! u 3 (lit always)) (%uz-make! u z name mode)))
      ((= c #\y) (%uz-make! u z name mode))
      ((= c #\N) (do (vec-set! u 3 (lit never)) #f))
      ((= c #\n) #f)
      ((= c #\r)
        (do (%uz-print u "new name: ")
            (again u z (%uz-chomp (%uz-answer u)) mode)))
      (#t (do (%uz-print u (string-concat (list "error: invalid response [" (bytes->str (list c)) "]\n")))
              (again u z name mode))))))

(def %uz-chomp
  (fn (_ s) (if (if (> (byte-len s) 0) (= (byte-at s (- (byte-len s) 1)) #\newline) #f) (substring s 0 (- (byte-len s) 1)) s)))

; the next answer on standard input, as fgets reads one into 80 bytes: up to
; and with its newline, at most 79 bytes; none, and the run ends
(def %uz-answer
  (fn (_ u)
    (def stdin-thunk (vec-ref u 15))
    (def go
      (fn (self text)
        (let ((nl (%dp-find text 0 #\newline)))
          (match
            ((if (>= nl 0) (< nl 79) #f)
              (do (vec-set! u 16 (substring text (+ nl 1) (byte-len text))) (substring text 0 (+ nl 1))))
            ((>= (byte-len text) 79)
              (do (vec-set! u 16 (substring text 79 (byte-len text))) (substring text 0 79)))
            (#t
              (let ((p (stdin-thunk (lit chunk))))
                (let ((more (if (pair? p) (%cu-run-text p) p)))
                  (if (= (byte-len more) 0)
                    (if (= (byte-len text) 0) (%uz-die "can't read standard input")
                      (do (vec-set! u 16 "") text))
                    (self (string-append text more))))))))))
    (go (vec-ref u 16))))

; member Z made at NAME: a file opened with MODE and its data written, or a
; link; #t
(def %uz-make!
  (fn (_ u z name mode)
    (def link? (= (%uz-type mode) 40960))
    (do (%uz-leading-dirs! name)
        (let ((fd (if link? -1
                    (File open name (list (lit wronly) (lit creat) (lit trunc) (lit nofollow)) (& mode 4095)))))
          (if (if (not link?) (< fd 0) #f)
            (%uz-die (string-concat (list "can't open '" name "': " (file-err-text (file-open-err fd name)))))
            (do (if (= (%uz-quiet u) 0) (%uz-print u (string-append "  inflating: " (%tar-printable name) "\n")) ())
                (if link? (%uz-symlink! u z name)
                  (do (%uz-extract! u z fd) (file-close fd)))
                #t))))))

; One member, as busybox's loop takes it: listed, written out, made, or
; passed over.  TOT holds the totals.
(def %uz-member!
  (fn (_ u z modes tot)
    (def name0
      (if (= (& (%uz-flags z) 1) 0) (%tar-field (%uz-read! u (%uz-name-len z)) 0 (%uz-name-len z))
        (%uz-die "zip flag 1 (encryption) is not supported")))
    (def name (do (%uz-skip! u (vec-ref z 8)) (%uz-safe u name0)))
    (def file-mode (first modes))
    (do (match
          ((not (%uz-wanted? u name)) (%uz-skip! u (%uz-csize z)))
          ((vec-ref u 6) (do (%uz-list! u z name tot) (%uz-skip! u (%uz-csize z))))
          ((not (null? (%uz-data-fd u)))
            (if (= (%uz-type file-mode) 40960) () (%uz-extract! u z (%uz-data-fd u))))
          (#t
            (let ((dst (if (vec-ref u 7) (%cu-base-of name) name)))
              (match
                ((= (byte-len dst) 0) (%uz-skip! u (%uz-csize z)))
                ((%uz-ends-slash? dst) (do (%uz-directory! u dst (rest modes)) (%uz-skip! u (%uz-csize z))))
                ((%uz-place! u z dst file-mode) ())
                (#t (%uz-skip! u (%uz-csize z)))))))
        (vec-set! tot 2 (+ (vec-ref tot 2) 1)))))

(def %uz-name-len
  (fn (_ z) (if (> (vec-ref z 7) 4095) (%uz-die "bad archive") (vec-ref z 7))))

; --- the applet ------------------------------------------------------------------------

; busybox's getopt over "-d:lnotpqxjvK": options and operands in order, the
; first operand the archive, the rest names to take -- or, after -x, to leave.
; A -- or a lone - ends the options, and the words from there are the archive
; and names to take.  (SRC ACCEPT REJECT . SETTINGS), SETTINGS an alist.
(def %uz-args
  (fn (_ argv)
    (def flags (list ()))
    (def on (fn (_ f) (%set-first! flags (pair f (first flags)))))
    (def go
      (fn (self ws src acc rej x? dir)
        (if (null? ws) (list src acc rej dir)
          (let ((w (first ws)))
            (match
              ((string=? w "--") (self (list) (%uz-tail src (rest ws)) (%uz-tail-acc acc (rest ws)) rej x? dir))
              ((string=? w "-") (self (list) (%uz-tail src ws) (%uz-tail-acc acc ws) rej x? dir))
              ((if (> (byte-len w) 1) (= (byte-at w 0) #\-) #f)
                (let ((d (%dp-find w 1 #\d)))
                  (let ((letters (substring w 1 (if (< d 0) (byte-len w) d))))
                    (do (map (fn (_ i) (on (byte-at letters i))) (List range 0 (byte-len letters)))
                        (match
                          ((< d 0) (self (rest ws) src acc rej (if x? #t (%uz-has? letters #\x)) dir))
                          ((< (+ d 1) (byte-len w))
                            (self (rest ws) src acc rej (if x? #t (%uz-has? letters #\x)) (substring w (+ d 1) (byte-len w))))
                          (#t (self (if (pair? (rest ws)) (rest (rest ws)) ()) src acc rej
                                (if x? #t (%uz-has? letters #\x)) (if (pair? (rest ws)) (first (rest ws)) dir))))))))
              ((null? src) (self (rest ws) w acc rej x? dir))
              (x? (self (rest ws) src acc (pair w rej) x? dir))
              (#t (self (rest ws) src (pair w acc) rej x? dir)))))))
    (let ((r (go argv () () () #f ())))
      (pair (reverse (first flags)) r))))

; after a -- or a lone -, the first word is the archive and the rest are names
(def %uz-tail (fn (_ src ws) (if (null? ws) src (first ws))))
(def %uz-tail-acc (fn (_ acc ws) (if (null? ws) acc (append (reverse (rest ws)) acc))))

(def %uz-has? (fn (_ s c) (>= (%dp-find s 0 c) 0)))

(def %uz-in? (fn (self x l) (if (null? l) #f (if (= (first l) x) #t (self x (rest l))))))

; FLAGS, the option letters in order, as a count of those among CS
(def %uz-count (fn (_ flags cs) (length (filter (fn (_ f) (%uz-in? f cs)) flags))))

; unzip [-lnojpqK] FILE[.zip] [FILE]... [-x FILE]... [-d DIR]
(def %cu-unzip
  (fn (_ argv stdin-thunk)
    (guard (e (if (eq? (%cu-err-label e) (lit unzip))
                (do (file-write 2 (string-append (e msg) "\n")) 1)
                (error e)))
      (%uz-run argv stdin-thunk))))

(def %uz-run
  (fn (_ argv stdin-thunk)
    (def a (%uz-args argv))
    (def flags (first a))
    (def src (first (rest a)))
    (do (%tar-resolve!)
        (if (null? src) (%cu-usage "unzip")
          (%uz-open src stdin-thunk
            (fn (_ name fd reader)
              (%uz-go flags name fd reader stdin-thunk
                (reverse (first (rest (rest a)))) (first (rest (rest (rest a))))
                (first (rest (rest (rest (rest a))))))))))))

; SRC opened -- `-` standard input, or the file, or it with .zip or .ZIP after
; it -- and handed to K as its name, descriptor and reader
(def %uz-open
  (fn (_ src stdin-thunk k)
    (if (string=? src "-") (k src () (%tar-reader (%cu-stdin-pieces stdin-thunk)))
      (let ((try (fn (self names)
                   (if (null? names) (%uz-die (string-append "can't open " (string-append src "[.zip]")))
                     (let ((fd (file-open-read (first names))))
                       (if (< fd 0) (self (rest names))
                         (k (first names) fd (%tar-reader (%cu-fd-chunks fd (first names))))))))))
        (try (list src (string-append src ".zip") (string-append src ".ZIP")))))))

(def %uz-go
  (fn (_ flags name fd reader stdin-thunk accept reject dir)
    (def t? (%uz-in? #\t flags))
    (def out (if t? (file-open-wronly "/dev/null") 1))
    (def l? (> (%uz-count flags (list #\l #\v)) 0))
    (def last-ow (filter (fn (_ f) (if (= f #\n) #t (= f #\o))) flags))
    (def u
      (vec-build 17
        (fn (_ i)
          (match
            ((= i 0) out)
            ((= i 1) (%uz-count flags (list #\q #\p #\t)))
            ((= i 2) (%uz-count flags (list #\v)))
            ((= i 3) (match ((null? fd) (if (null? last-ow) (lit never) (if (= (first (reverse last-ow)) #\o) (lit always) (lit never))))
                            ((null? last-ow) (lit prompt))
                            ((= (first (reverse last-ow)) #\o) (lit always))
                            (#t (lit never))))
            ((= i 4) accept) ((= i 5) reject)
            ((= i 6) l?) ((= i 7) (%uz-in? #\j flags)) ((= i 8) (%uz-in? #\K flags))
            ((= i 9) (if (if t? #t (%uz-in? #\p flags)) out ()))
            ((= i 10) reader) ((= i 11) fd) ((= i 12) 0)
            ((= i 15) stdin-thunk) ((= i 16) "")
            (#t (if (= i 14) #f ()))))))
    (def r
      (guard (e (do (%uz-close u) (error e)))
        (%uz-in-dir dir (fn (_) (%uz-all u name)))))
    (do (%uz-close u) r)))

(def %uz-close
  (fn (_ u)
    (do (if (null? (%uz-fd u)) () (file-close (%uz-fd u)))
        (if (= (%uz-out u) 1) () (file-close (%uz-out u))))))

; -d's directory, made if it can be: the run goes there, and comes back when
; it ends
(def %uz-in-dir
  (fn (_ dir thunk)
    (if (null? dir) (thunk)
      (let ((home (sys-getcwd)))
        (do (%cu-ptr-call %tar-c-mkdir dir 511)
            (if (< (Sys chdir dir) 0)
              (%uz-die (string-concat (list "can't change directory to '" dir "': " (%tar-why (lit chdir) dir))))
              (let ((r (guard (e (do (Sys chdir home) (error e))) (thunk))))
                (do (Sys chdir home) r))))))))

; the archive's members, listed or made, then the links held back and the totals
(def %uz-all
  (fn (_ u name)
    (def quiet (%uz-quiet u))
    (def tot (vec-build 3 (fn (_ i) 0)))
    (do (if (<= quiet 1)
          (do (if (= quiet 0) (%uz-print u (string-concat (list "Archive:  " (%tar-printable name) "\n"))) ())
              (if (vec-ref u 6)
                (%uz-print u (if (> (%uz-verbose u) 0)
                               " Length   Method    Size  Cmpr    Date    Time   CRC-32   Name\n--------  ------  ------- ---- ---------- ----- --------  ----\n"
                               "  Length      Date    Time    Name\n---------  ---------- -----   ----\n"))
                ()))
          ())
        (let ((cdf (list (%uz-find-cdf u))))
          (let ((go (fn (self)
                      (let ((m (%uz-next-member u cdf)))
                        (if (null? m) ()
                          (do (%uz-member! u (first m) (rest m) tot)
                              (%cu-sweep-tick! %cu-sweep-lines)
                              (self)))))))
            (go)))
        (%uz-make-links! u)
        (if (if (vec-ref u 6) (<= quiet 1) #f) (%uz-totals! u tot) ())
        0)))

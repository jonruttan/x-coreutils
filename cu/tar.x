; # x-coreutils -- the small tools, as applets
;
; ## cu/tar.x -- tar
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's tar (archival/tar.c, libarchive's get_header_tar, data_extract_all
; and the listers).  t lists an archive's members, x makes them, c makes an
; archive; -f names it (standard input or output without), -C changes to a
; directory first, v names what is done (twice, or with t, in ls -l's form),
; O writes the members' contents to standard output.  The archive is ustar
; with GNU's long names (an L or K block before the header) and busybox reads
; pax headers' path and linkpath too.  z reads and writes it through gzip
; (cu/gzip.x), as does a with a name ending gz; data beginning with gzip's
; magic is read through it without z, as busybox finds it.
;
; Members are matched against the names given as busybox's find_list_entry2
; does: a glob against as many leading parts of the path as the glob has
; parts.  --exclude and -X leave members out; on c they match as fnmatch's
; FNM_PATHNAME and FNM_LEADING_DIR do, against each tail of the path.
;
; Links are made last where their targets may not be there yet: every hard
; link, and a symbolic one pointing at an absolute path or through `..`.
; Running as anyone but root, a member's permissions are those it is opened
; or made with, as busybox leaves them.
;
; The archive is read and written a piece at a time.  A piece's bytes go to a
; header's buffer, or to the file being made, through libc's memcpy and write
; by address, so a NUL among them is a byte like any other.

(def %tar-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %tar-c-memcpy ())
(def %tar-c-write ())
(def %tar-c-mkdir ())
(def %tar-c-mknod ())
(def %tar-c-getuid ())

(def %tar-resolve!
  (fn (_)
    (def lib (%cu-dlopen () 1))
    (set! %tar-c-memcpy (%cu-dlsym lib "memcpy"))
    (set! %tar-c-write (%cu-dlsym lib "write"))
    (set! %tar-c-mkdir (%cu-dlsym lib "mkdir"))
    (set! %tar-c-mknod (%cu-dlsym lib "mknod"))
    (set! %tar-c-getuid (%cu-dlsym lib "getuid"))))

(def %tar-addr (fn (_ s) (%tar-ptr->int (%cu-str->ptr s))))
(def %tar-min (fn (_ a b) (if (< a b) a b)))

; the run ends: MSG said under tar's name, and the status 1
(def %tar-die (fn (_ msg) (Err raise (lit tar) (string-append "tar: " msg) ())))

(def %tar-say (fn (_ msg) (file-write 2 (string-concat (list "tar: " msg "\n")))))

; the reason an io Err gives, after a failed call named OP on NAME
(def %tar-why
  (fn (_ op name) (file-err-text (Err from-errno (Err errno-of -1) op name))))

; --- the archive's bytes ---------------------------------------------------------

; A reader of SRC's pieces, in a vector: the source, the piece being read,
; where in it, and the bytes read in all.
(def %tar-reader
  (fn (_ src) (vec-build 4 (fn (_ i) (match ((= i 0) src) ((= i 3) 0) (#t ()))))))

; Up to N of the reader's bytes, each run of them handed to EACH as (ADDRESS
; COUNT): how many there were, short only at the end of the archive.
(def %tar-take!
  (fn (_ rd n each)
    (def go
      (fn (self k)
        (if (>= k n) k
          (let ((p (vec-ref rd 1)) (pos (if (null? (vec-ref rd 2)) 0 (vec-ref rd 2))))
            (if (if (null? p) #t (>= pos (rest p)))
              (let ((q ((vec-ref rd 0))))
                (if (if (Err err? q) #t (= (rest q) 0)) k
                  (do (vec-set! rd 1 q) (vec-set! rd 2 0) (self k))))
              (let ((m (%tar-min (- (rest p) pos) (- n k))))
                (do (each (+ (%tar-addr (first p)) pos) m)
                    (vec-set! rd 2 (+ pos m))
                    (vec-set! rd 3 (+ (vec-ref rd 3) m))
                    (self (+ k m)))))))))
    (go 0)))

; N bytes into BUF from OFF; how many came
(def %tar-fill!
  (fn (_ rd buf off n)
    (def at (+ (%tar-addr buf) off))
    (def put (list 0))
    (%tar-take! rd n
      (fn (_ a m)
        (do (%cu-ptr-call %tar-c-memcpy (+ at (first put)) a m)
            (%set-first! put (+ (first put) m)))))))

(def %tar-skip! (fn (_ rd n) (%tar-take! rd n (fn (_ a m) ()))))

; N bytes written to FD as they are read
(def %tar-copy-out!
  (fn (_ rd fd n) (%tar-take! rd n (fn (_ a m) (%cu-ptr-call %tar-c-write fd a m)))))

; past the padding to the next 512-byte block
(def %tar-align!
  (fn (_ rd)
    (let ((r (% (vec-ref rd 3) 512))) (if (= r 0) () (%tar-skip! rd (- 512 r))))))

; --- a header's fields ------------------------------------------------------------

; LEN bytes of H from OFF, up to a NUL, as a string
(def %tar-field
  (fn (_ h off len)
    (def go
      (fn (self i acc)
        (if (if (>= i (+ off len)) #t (= (byte-at h i) 0)) (bytes->str (reverse acc))
          (self (+ i 1) (pair (byte-at h i) acc)))))
    (go off ())))

; busybox's getOctal: blanks, octal digits, then a NUL or a blank -- or, a
; first byte with its top bit set, GNU's base-256, sign in the next bit
(def %tar-octal
  (fn (_ h off len)
    (def end (+ off len))
    (def i0 (let ((go (fn (self i) (if (if (< i end) (= (byte-at h i) #\space) #f) (self (+ i 1)) i))))
              (go off)))
    (def digits
      (fn (self i v)
        (let ((c (if (< i end) (byte-at h i) 0)))
          (if (if (>= c #\0) (<= c #\7) #f) (self (+ i 1) (+ (* v 8) (- c #\0))) (pair v c)))))
    (def r (digits i0 0))
    (def b256
      (fn (self i v) (if (>= i end) v (self (+ i 1) (+ (* v 256) (byte-at h i))))))
    (match
      ((if (= (rest r) 0) #t (= (rest r) #\space)) (first r))
      ((< (byte-at h off) 128) (%tar-die "corrupted octal value in tar header"))
      (#t (let ((f (& (byte-at h off) 127)))
            (b256 (+ off 1) (if (>= f 64) (- f 128) f)))))))

; the header's checksum is right, summed as unsigned bytes or, as Sun's tar
; wrote it, as signed ones
(def %tar-sum-ok?
  (fn (_ h)
    (def go
      (fn (self i u s)
        (match
          ((= i 512) (pair u s))
          ((if (>= i 148) (< i 156) #f) (self (+ i 1) u s))
          (#t (let ((b (byte-at h i)))
                (self (+ i 1) (+ u b) (+ s (if (>= b 128) (- b 256) b))))))))
    (def sums (go 0 256 256))
    (def want (%tar-octal h 148 8))
    (if (= (first sums) want) #t (= (rest sums) want))))

; the magic of a ustar header, or the five NULs of an old GNU one
(def %tar-magic-ok?
  (fn (_ h)
    (if (string=? (%tar-field h 257 5) "ustar") #t
      (if (= (byte-at h 257) 0)
        (if (= (byte-at h 258) 0) (if (= (byte-at h 259) 0) (= (byte-at h 260) 0) #f) #f) #f))))

; How much of NAME busybox's skip_unsafe_prefix takes off: leading slashes
; and ../, and everything up to the last /../; a trailing /.. leaves nothing.
(def %cu-unsafe-prefix
  (fn (_ name)
    (def n (byte-len name))
    (def find-dotdot
      (fn (self from)
        (match
          ((> (+ from 3) n) -1)
          ((if (= (byte-at name from) #\/) (if (= (byte-at name (+ from 1)) #\.) (= (byte-at name (+ from 2)) #\.) #f) #f)
            (let ((after (+ from 3)))
              (match
                ((= after n) (lit tail))
                ((= (byte-at name after) #\/) (+ after 1))
                (#t (self after)))))
          (#t (self (+ from 1))))))
    (def go
      (fn (self cp)
        (match
          ((if (< cp n) (= (byte-at name cp) #\/) #f) (self (+ cp 1)))
          ((if (<= (+ cp 3) n)
             (if (= (byte-at name cp) #\.) (if (= (byte-at name (+ cp 1)) #\.) (= (byte-at name (+ cp 2)) #\/) #f) #f) #f)
            (self (+ cp 3)))
          (#t (let ((d (find-dotdot cp)))
                (match
                  ((eq? d (lit tail)) n)
                  ((< d 0) cp)
                  (#t (self d))))))))
    (go 0)))

; NAME with that prefix taken off.  The first time a run takes something
; off, it says so.
(def %tar-warned #f)

(def %tar-safe
  (fn (_ name)
    (def cut (%cu-unsafe-prefix name))
    (do (if (if (> cut 0) (not %tar-warned) #f)
          (do (set! %tar-warned #t)
              (%tar-say (string-concat (list "removing leading '" (substring name 0 cut)
                                             "' from member names"))))
          ())
        (substring name cut (byte-len name)))))

; S with each byte that will not print shown as ?, as busybox's
; printable_string does without Unicode
(def %tar-printable
  (fn (_ s)
    (def go
      (fn (self i acc)
        (if (>= i (byte-len s)) (bytes->str (reverse acc))
          (let ((c (byte-at s i)))
            (self (+ i 1) (pair (if (if (< c 32) #t (>= c 127)) #\? c) acc))))))
    (go 0 ())))

; --- reading the members -------------------------------------------------------

; A member, in a vector: NAME MODE UID GID SIZE MTIME LINK UNAME GNAME DEVICE
(def %tm-name (fn (_ m) (vec-ref m 0)))
(def %tm-mode (fn (_ m) (vec-ref m 1)))
(def %tm-size (fn (_ m) (vec-ref m 4)))
(def %tm-link (fn (_ m) (vec-ref m 6)))

; S_IFMT's type bits for a typeflag; nil for one tar does not make
(def %tar-type-bits
  (fn (_ flag name)
    (match
      ((= flag #\1) 32768)
      ((if (= flag #\0) #t (= flag #\7))
        (if (if (> (byte-len name) 0) (= (byte-at name (- (byte-len name) 1)) #\/) #f)
          16384 32768))
      ((= flag #\2) 40960)
      ((= flag #\3) 8192)
      ((= flag #\4) 24576)
      ((= flag #\5) 16384)
      ((= flag #\6) 4096)
      (#t ()))))

; the records of a pax header of SIZE bytes: (PATH . LINKPATH) where it names
; them, for a header of the next member -- not a global one
(def %tar-pax
  (fn (_ rd size global)
    (def blk (* 512 (%cal/ (+ size 511) 512)))
    (def buf (%str-make-raw (+ blk 1)))
    (def text (do (%tar-fill! rd buf 0 blk) (substring buf 0 size)))
    (def go
      (fn (self s path link)
        (if (= (byte-len s) 0) (pair path link)
          (let ((sp (%dp-find s 0 #\space)))
            (let ((len (if (> sp 0) (%cu-num-prefix (substring s 0 sp)) 0)))
              (if (if (< sp 1) #t (if (= len 0) #t (> len (byte-len s))))
                (do (%tar-say "malformed extended header, skipped") (pair path link))
                (let ((rec (substring s (+ sp 1) (- len 1))))
                  (self (substring s len (byte-len s))
                    (if (if global #f (%tar-prefix? rec "path=")) (substring rec 5 (byte-len rec)) path)
                    (if (if global #f (%tar-prefix? rec "linkpath=")) (substring rec 9 (byte-len rec)) link)))))))))
    (go text () ())))

(def %tar-prefix?
  (fn (_ s p) (if (>= (byte-len s) (byte-len p)) (string=? (substring s 0 (byte-len p)) p) #f)))

; the bytes a GNU long name or link block holds, up to its NUL
(def %tar-long
  (fn (_ rd size)
    (if (> size 4095) (%tar-die "bad archive")
      (let ((buf (%str-make-raw (+ size 1))))
        (do (%tar-fill! rd buf 0 size)
            (%tar-field buf 0 size))))))

; The next member, as busybox's get_header_tar reads it: (lit end) at the
; end of the archive, (lit empty) for the first of the two empty blocks that
; end it, or the member.  ST holds the long name and link a GNU or pax block
; gave for the member after it, and whether the last block was empty.
(def %tar-header
  (fn (self rd st)
    (def h (%str-make-raw 512))
    (do (%tar-align! rd)
        (let ((got (%tar-fill! rd h 0 512)))
          (match
            ((= got 0)
              (do (if (= (vec-ref rd 3) 0) (%tar-say "short read") ()) (lit end)))
            ((< got 512) (%tar-die "invalid tar magic"))
            ((if (= (byte-at h 0) 0) (if (= (byte-at h 345) 0) (null? (vec-ref st 0)) #f) #f)
              (if (vec-ref st 2) (lit end) (do (vec-set! st 2 #t) (lit empty))))
            ((not (%tar-magic-ok? h)) (%tar-die "invalid tar magic"))
            ((not (%tar-sum-ok? h)) (%tar-die "invalid tar header checksum"))
            (#t (do (vec-set! st 2 #f) (%tar-member self rd st h))))))))

(def %tar-member
  (fn (_ again rd st h)
    (def flag (let ((f (byte-at h 156))) (if (= f 0) #\0 f)))
    (def names? (if (>= flag #\0) (<= flag #\7) #f))
    (def size (%tar-octal h 124 12))
    ; the header's own name, read only where no long name stands in for it
    (def raw-name
      (if (if names? (null? (vec-ref st 0)) #f)
        (let ((pre (%tar-field h 345 155)) (nm (%tar-field h 0 100)))
          (if (= (byte-len pre) 0) nm
            (string-append pre (if (= (byte-at pre (- (byte-len pre) 1)) #\/) nm (string-append "/" nm)))))
        ()))
    (def bits (%tar-type-bits flag (if (null? raw-name) "" raw-name)))
    (match
      ((if (= flag #\x) #t (= flag #\g))
        (if (> size 1048575) (%tar-skip-header again rd st flag size)
          (let ((r (%tar-pax rd size (= flag #\g))))
            (do (if (null? (first r)) () (vec-set! st 0 (first r)))
                (if (null? (rest r)) () (vec-set! st 1 (rest r)))
                (again rd st)))))
      ((= flag #\L) (do (vec-set! st 0 (%tar-long rd size)) (again rd st)))
      ((= flag #\K) (do (vec-set! st 1 (%tar-long rd size)) (again rd st)))
      ((= flag #\V) (%tar-skip-header again rd st flag size))
      ((null? bits)
        (%tar-die (string-append "unknown typeflag: 0x" (%dp-udigits flag 16 #f))))
      (#t
        (let ((name (if (null? (vec-ref st 0)) raw-name (vec-ref st 0)))
              (link (match ((not (null? (vec-ref st 1))) (vec-ref st 1))
                           ((if names? (> (byte-at h 157) 0) #f) (%tar-field h 157 100))
                           (#t ())))
              (sized (if (if (= bits 32768) (not (= flag #\1)) #f) size 0)))
          (do (vec-set! st 0 ())
              (vec-set! st 1 ())
              (%tar-new-member h (%tar-safe name) link bits sized)))))))

; the member vector for header H, its NAME made safe
(def %tar-new-member
  (fn (_ h name link bits size)
    (vec-build 10
      (fn (_ i)
        (match
          ((= i 0) name)
          ((= i 1) (| bits (& (%tar-octal h 100 8) 4095)))
          ((= i 2) (%tar-octal h 108 8))
          ((= i 3) (%tar-octal h 116 8))
          ((= i 4) size)
          ((= i 5) (%tar-octal h 136 12))
          ((= i 6) (if (if (null? link) #f (not (= bits 40960))) (%tar-safe link) link))
          ((= i 7) (%tar-field-or-nil h 265 32))
          ((= i 8) (%tar-field-or-nil h 297 32))
          (#t (if (> (byte-at h 329) 0)
                (pair (%tar-octal h 329 8) (%tar-octal h 337 8)) ())))))))

(def %tar-field-or-nil
  (fn (_ h off len)
    (let ((s (%tar-field h off len))) (if (= (byte-len s) 0) () s))))

; a header tar passes over, its blocks with it
(def %tar-skip-header
  (fn (_ again rd st flag size)
    (do (%tar-say (string-concat (list "warning: skipping header '" (bytes->str (list flag)) "'")))
        (%tar-skip! rd (* 512 (%cal/ (+ size 511) 512)))
        (again rd st))))

; --- listing -----------------------------------------------------------------------

; MODE as ls -l shows it: the type, then the permissions
(def %tar-mode-string
  (fn (_ mode)
    (%cu-perm-string (%cu-mode-file-type mode) (& mode 4095))))

(def %tar-2 (fn (_ n) (%cu-pad-zero (%cu-int->str n) 2)))

; busybox's header_verbose_list line for member M
(def %tar-verbose-line
  (fn (_ m)
    (def d (Date local (vec-ref m 5)))
    (def at (fn (_ k) (Assoc get k d)))
    (string-concat
      (list (%tar-mode-string (%tm-mode m)) " "
            (if (null? (vec-ref m 7)) (%cu-int->str (vec-ref m 2)) (vec-ref m 7)) "/"
            (if (null? (vec-ref m 8)) (%cu-int->str (vec-ref m 3)) (vec-ref m 8)) " "
            (%cu-pad-left (%cu-int->str (%tm-size m)) 9) " "
            (%cu-pad-left (%cu-int->str (at (lit year))) 4) "-" (%tar-2 (at (lit month))) "-"
            (%tar-2 (at (lit day))) " " (%tar-2 (at (lit hour))) ":" (%tar-2 (at (lit minute))) ":"
            (%tar-2 (at (lit second))) " "
            (%tar-printable (%tm-name m))
            (if (null? (%tm-link m)) "" (string-append " -> " (%tar-printable (%tm-link m))))
            "\n"))))

; --- making the members --------------------------------------------------------------

; The run's settings, in a vector: the action (list, extract or stdout), how
; verbose, the names to take and to leave, the components to strip, -k,
; --overwrite, -o, --numeric-owner, whether permissions are restored, -m.
(def %ts-action (fn (_ t) (vec-ref t 0)))
(def %ts-verbose (fn (_ t) (vec-ref t 1)))
(def %ts-accept (fn (_ t) (vec-ref t 2)))
(def %ts-reject (fn (_ t) (vec-ref t 3)))

; busybox's find_list_entry2: a glob against as many of NAME's leading parts
; as the glob has
(def %tar-list-match?
  (fn (self pats name)
    (if (null? pats) #f
      (let ((p (first pats)))
        (let ((slashes (length (filter (fn (_ b) (= b #\/)) (%tar-str-bytes p)))))
          (let ((cut (%tar-nth-slash name (+ slashes 1))))
            (if (%cu-glob? p (if (< cut 0) name (substring name 0 cut))) #t
              (self (rest pats) name))))))))

; the place of NAME's Kth slash, or -1
(def %tar-nth-slash
  (fn (_ name k)
    (def go
      (fn (self i seen)
        (match
          ((>= i (byte-len name)) -1)
          ((= (byte-at name i) #\/) (if (= (+ seen 1) k) i (self (+ i 1) (+ seen 1))))
          (#t (self (+ i 1) seen)))))
    (go 0 0)))

(def %tar-str-bytes
  (fn (_ s)
    (def go (fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (byte-at s i) acc)))))
    (go (- (byte-len s) 1) ())))

; member M is one the run takes
(def %tar-wanted?
  (fn (_ t m)
    (match
      ((%tar-list-match? (%ts-reject t) (%tm-name m)) #f)
      ((null? (%ts-accept t)) #t)
      (#t (%tar-list-match? (%ts-accept t) (%tm-name m))))))

; NAME with N leading components gone, as --strip-components takes them; nil
; where it has no more
(def %tar-strip
  (fn (self name n)
    (if (= n 0) name
      (let ((sl (%dp-find name 0 #\/)))
        (if (if (< sl 0) #t (= (+ sl 1) (byte-len name))) ()
          (self (substring name (+ sl 1) (byte-len name)) (- n 1)))))))

; the links to make once the members are made: (HARD? NAME . TARGET), newest first
(def %tar-pending ())

; member M made, its data read from RD, as busybox's data_extract_all makes it
(def %tar-extract!
  (fn (_ t rd m)
    (def mode (%tm-mode m))
    (def type (& mode 61440))
    (def hard (if (if (= type 32768) (= (%tm-size m) 0) #f) (%tm-link m) ()))
    (def strip (vec-ref t 4))
    (def dst (%tar-strip (%tm-name m) strip))
    (def target (if (null? hard) () (%tar-strip hard strip)))
    (match
      ((if (null? dst) #t (if (null? hard) #f (null? target))) (%tar-skip! rd (%tm-size m)))
      (#t
        (do (let ((sl (%tar-last-slash dst)))
              (if (> sl 0) (%cu-mkdir-p! (substring dst 0 sl)) ()))
            (if (if (vec-ref t 5) #t (vec-ref t 6)) ()
              (if (= type 16384) () (%tar-unlink-old! dst target)))
            (if (if (null? target) #f (string=? target dst)) ()
              (%tar-make! t rd m dst target type mode)))))))

(def %tar-last-slash
  (fn (_ s)
    (def go (fn (self i) (if (< i 0) -1 (if (= (byte-at s i) #\/) i (self (- i 1))))))
    (go (- (byte-len s) 1))))

; DST removed if it is there, a hard link to itself left alone
(def %tar-unlink-old!
  (fn (_ dst target)
    (match
      ((if (null? target) #f (string=? target dst)) ())
      ((eq? (file-lstat-file-type dst) (lit none)) ())
      ((guard (e #f) (do (file-unlink dst) #t)) ())
      (#t (%tar-die (string-concat (list "can't remove old file " dst ": "
                                         (%tar-why (lit unlink) dst))))))))

(def %tar-make!
  (fn (_ t rd m dst target type mode)
    (do
      (match
        ((not (null? target)) (set! %tar-pending (pair (pair #t (pair dst target)) %tar-pending)))
        ((= type 32768)
          (let ((fd (File open dst (if (vec-ref t 6) (list (lit wronly) (lit creat) (lit trunc))
                                     (list (lit wronly) (lit creat) (lit excl)))
                      (& mode 4095))))
            (if (< fd 0)
              (%tar-die (string-concat (list "can't open '" dst "': " (file-err-text (file-open-err fd dst)))))
              (do (%tar-copy-out! rd fd (%tm-size m)) (file-close fd)))))
        ((= type 16384)
          (if (< (Sys %sign-fold (%cu-ptr-call %tar-c-mkdir dst (& mode 4095))) 0)
            (let ((why (%tar-why (lit mkdir) dst)))
              (if (string=? why "File exists") ()
                (%tar-say (string-concat (list "can't make dir " dst ": " why)))))
            ()))
        ((= type 40960)
          (let ((l (%tm-link m)))
            (if (if (= (byte-at l 0) #\/) #t (>= (%tar-find-str l "..") 0))
              (set! %tar-pending (pair (pair #f (pair dst l)) %tar-pending))
              (if (guard (e #f) (do (file-symlink l dst) #t)) ()
                (%tar-die (string-concat (list "can't create symlink '" dst "' to '" l "': "
                                               (%tar-why (lit symlink) dst))))))))
        (#t
          (let ((dev (vec-ref m 9)))
            (if (< (Sys %sign-fold (%cu-ptr-call %tar-c-mknod dst mode (%tar-makedev dev))) 0)
              (%tar-say (string-concat (list "can't create node " dst ": " (%tar-why (lit mknod) dst))))
              ()))))
      (if (if (= type 40960) #t (not (null? target))) () (%tar-restore! t m dst mode)))))

; a device number from (MAJOR . MINOR), as the platform packs one
(def %tar-makedev
  (fn (_ dev)
    (match
      ((null? dev) 0)
      (os-darwin? (| (<< (first dev) 24) (rest dev)))
      (#t (| (| (<< (& (first dev) 4095) 8) (& (rest dev) 255))
             (| (<< (& (rest dev) 1048320) 12) (<< (& (first dev) 4294963200) 32)))))))

(def %tar-find-str
  (fn (_ s sub)
    (def n (byte-len sub))
    (def go
      (fn (self i)
        (if (> (+ i n) (byte-len s)) -1
          (if (string=? (substring s i (+ i n)) sub) i (self (+ i 1))))))
    (go 0)))

; the owner, the permissions and the time a member made is given, as -o, -p
; and -m leave them
(def %tar-restore!
  (fn (_ t m dst mode)
    (do (if (vec-ref t 7) ()
          (let ((uid (if (if (vec-ref t 8) #t (null? (vec-ref m 7))) (vec-ref m 2)
                       (let ((u (sys-user-id (vec-ref m 7)))) (if (null? u) (vec-ref m 2) u))))
                (gid (if (if (vec-ref t 8) #t (null? (vec-ref m 8))) (vec-ref m 3)
                       (let ((g (sys-group-id (vec-ref m 8)))) (if (null? g) (vec-ref m 3) g)))))
            (guard (e ()) (file-chown dst uid gid))))
        (if (vec-ref t 9) (guard (e ()) (file-chmod dst (& mode 4095))) ())
        (if (vec-ref t 10) (guard (e ()) (file-set-times dst (vec-ref m 5) (vec-ref m 5))) ()))))

; the links held back, made in the order they were met
(def %tar-make-links!
  (fn (_)
    (map (fn (_ l)
           (let ((name (first (rest l))) (target (rest (rest l))))
             (if (guard (e #f) (do (if (first l) (file-link target name) (file-symlink target name)) #t)) ()
               (%tar-die (string-concat (list "can't create " (if (first l) "hard" "sym") "link '"
                                              name "' to '" target "'"))))))
         (reverse %tar-pending))))

; --- the read side's run -------------------------------------------------------------

; The members of RD, each taken or passed over, listed and made as T asks.
; Answers the names taken.
(def %tar-read-all
  (fn (_ t rd)
    (def st (vec-build 3 (fn (_ i) (if (= i 2) #f ()))))
    (def listing (if (eq? (%ts-action t) (lit stdout)) 2 1))
    (def go
      (fn (self passed seen)
        (let ((m (%tar-header rd st)))
          (match
            ((eq? m (lit end)) (pair passed seen))
            ((eq? m (lit empty)) (self passed #t))
            ((not (%tar-wanted? t m))
              (do (%tar-skip! rd (%tm-size m)) (self passed #t)))
            (#t
              (do (match
                    ((= (%ts-verbose t) 1) (file-write listing (string-append (%tar-printable (%tm-name m)) "\n")))
                    ((> (%ts-verbose t) 1) (file-write listing (%tar-verbose-line m)))
                    (#t ()))
                  (let ((m2 (%tar-trim m)))
                    (do (match
                          ((eq? (%ts-action t) (lit extract)) (%tar-extract! t rd m2))
                          ((eq? (%ts-action t) (lit stdout))
                            (if (= (& (%tm-mode m2) 61440) 32768) (%tar-copy-out! rd 1 (%tm-size m2))
                              (%tar-skip! rd (%tm-size m2))))
                          (#t (%tar-skip! rd (%tm-size m2))))
                        (%cu-sweep-tick! %cu-sweep-lines)
                        (self (pair (%tm-name m2) passed) #t)))))))))
    (go () #f)))

; M with the trailing / of its name gone, as busybox takes it off once the
; name is listed
(def %tar-trim
  (fn (_ m)
    (let ((n (%tm-name m)))
      (if (if (> (byte-len n) 1) (= (byte-at n (- (byte-len n) 1)) #\/) #f)
        (vec-build 10 (fn (_ i) (if (= i 0) (substring n 0 (- (byte-len n) 1)) (vec-ref m i))))
        m))))

; --- writing an archive ---------------------------------------------------------------

; the archive's gzip writer, under z; nil when it is written as it is
(def %tc-sink ())

; the run R written to the archive on FD
(def %tc-emit!
  (fn (_ fd r)
    (if (null? %tc-sink) (file-write-run fd r)
      (%gz-sink-write! %tc-sink (first r) (rest r)))))

; S into the header H at OFF, at most MAX bytes, as strncpy puts it: no NUL
; where it fills the field
(def %tc-put!
  (fn (_ h off s max)
    (def p (%cu-str->ptr h))
    (def n (%tar-min (byte-len s) max))
    (def go (fn (self i) (if (< i n) (do (%cu-ptr-set! p (+ off i) (byte-at s i) 1) (self (+ i 1))) ())))
    (go 0)))

; V into a field of LEN at OFF, as busybox's putOctal: LEN-1 digits and a NUL
; where they are enough, else LEN digits -- the low ones where even they are not
(def %tc-octal!
  (fn (_ h off len v)
    (def d (%dp-udigits v 8 #f))
    (def full (%cu-pad-zero d len))
    (def last (substring full (- (byte-len full) len) (byte-len full)))
    (%tc-put! h off (if (= (byte-at last 0) #\0) (substring last 1 len) last) len)))

; a block of 512 NUL bytes
(def %tc-block
  (fn (_)
    (def h (%str-make-raw 512))
    (def p (%cu-str->ptr h))
    (def go (fn (self i) (if (< i 512) (do (%cu-ptr-set! p i 0 1) (self (+ i 1))) ())))
    (do (go 0) h)))

; the header H written to FD, its magic and checksum put in first: GNU's
; "ustar  ", and the sum of the bytes with the checksum field as blanks, in six
; octal digits and a NUL
(def %tc-write-header!
  (fn (_ fd h)
    (def p (%cu-str->ptr h))
    (do (%tc-put! h 257 "ustar  " 8)
        (%tc-put! h 148 "        " 8)
        (let ((sum (let ((go (fn (self i acc) (if (= i 512) acc (self (+ i 1) (+ acc (byte-at h i)))))))
                     (go 0 0))))
          (do (%tc-put! h 148 (%cu-pad-zero (%dp-udigits sum 8 #f) 6) 6)
              (%cu-ptr-set! p 154 0 1)))
        (%tc-emit! fd (pair h 512)))))

; a GNU long name or link block, TYPE L or K, before the header it belongs to
(def %tc-longname!
  (fn (_ fd type name dir?)
    (def h (%tc-block))
    (def size (+ (byte-len name) (if dir? 2 1)))
    (do (%tc-put! h 0 "././@LongLink" 100)
        (%tc-put! h 100 "0000000" 8)
        (%tc-put! h 108 "0000000" 8)
        (%tc-put! h 116 "0000000" 8)
        (%tc-put! h 124 "00000000000" 12)
        (%tc-put! h 136 "00000000000" 12)
        (%tc-octal! h 124 12 size)
        (%cu-ptr-set! (%cu-str->ptr h) 156 type 1)
        (%tc-write-header! fd h)
        (let ((blocks (%cal/ (+ size 511) 512)))
          (let ((buf (%str-make-raw (* 512 blocks))))
            (do (map (fn (_ i) (%cu-ptr-set! (%cu-str->ptr buf) i 0 1)) (List range 0 (* 512 blocks)))
                (%tc-put! buf 0 (if dir? (string-append name "/") name) (* 512 blocks))
                (%tc-emit! fd (pair buf (* 512 blocks)))))))))

; The run's create settings, in a vector: the archive's descriptor, verbose,
; the excludes, the hard links met as (DEV INO . NAME), the archive's own
; (DEV . INO), -h, recursion.
(def %tc-fd (fn (_ c) (vec-ref c 0)))

; an owner's or group's name for the header, or its number
(def %tc-uname (fn (_ uid) (let ((n (sys-user-name uid))) (if (null? n) (%cu-int->str uid) n))))
(def %tc-gname (fn (_ gid) (let ((n (sys-group-name gid))) (if (null? n) (%cu-int->str gid) n))))

; busybox's writeTarHeader: the header for PATH, named NAME, from its stat ST,
; HL the name of the file it is a hard link to.  #f where it is not written.
(def %tc-header!
  (fn (_ c name path st hl)
    (def h (%tc-block))
    (def get (fn (_ k) (%cu-stat-get st k)))
    (def mode (get (lit mode)))
    (def type (& mode 61440))
    (def link (match ((not (null? hl)) hl) ((= type 40960) (guard (e ()) (file-readlink path))) (#t ())))
    (def fd (%tc-fd c))
    (def flag
      (match
        ((not (null? hl)) #\1) ((= type 40960) #\2) ((= type 16384) #\5) ((= type 8192) #\3)
        ((= type 24576) #\4) ((= type 4096) #\6) ((= type 32768) #\0) (#t ())))
    (if (null? flag)
      (do (%tar-say (string-append path ": unknown file type")) #f)
      (do (%tc-put! h 0 name 100)
          (%tc-octal! h 100 8 (& mode 4095))
          (%tc-octal! h 108 8 (get (lit uid)))
          (%tc-octal! h 116 8 (get (lit gid)))
          (%tc-put! h 124 "00000000000" 11)
          (%tc-octal! h 136 12 (let ((t (get (lit mtime)))) (if (< t 0) 0 t)))
          (%tc-put! h 265 (%tc-uname (get (lit uid))) 31)
          (%tc-put! h 297 (%tc-gname (get (lit gid))) 31)
          (%cu-ptr-set! (%cu-str->ptr h) 156 flag 1)
          (if (null? link) () (%tc-put! h 157 link 100))
          (match
            ((if (= flag #\5) (< (byte-len name) 100) #f) (%tc-put! h (byte-len name) "/" 1))
            ((if (= flag #\3) #t (= flag #\4) )
              (do (%tc-octal! h 329 8 (%cu-dev-major (get (lit rdev))))
                  (%tc-octal! h 337 8 (%cu-dev-minor (get (lit rdev))))))
            ((= flag #\0) (%tc-octal! h 124 12 (get (lit size))))
            (#t ()))
          (if (if (null? link) #f (>= (byte-len link) 100)) (%tc-longname! fd #\K link #f) ())
          (if (>= (byte-len name) 100) (%tc-longname! fd #\L name (= flag #\5)) ())
          (%tc-write-header! fd h)
          (if (vec-ref c 1)
            (file-write (if (= fd 1) 2 1) (string-append (%tar-printable name) (if (= flag #\5) "/\n" "\n")))
            ())
          #t))))

; fnmatch with FNM_PATHNAME and FNM_LEADING_DIR: a * ? or [] never crosses a
; slash, and PAT need match only up to one
(def %tc-fnmatch?
  (fn (_ pat s)
    (def pn (byte-len pat))
    (def sn (byte-len s))
    (def go
      (fn (self pi si)
        (if (>= pi pn) (if (>= si sn) #t (= (byte-at s si) #\/))
          (let ((p (byte-at pat pi)) (c (if (< si sn) (byte-at s si) -1)))
            (match
              ((= p #\*) (if (self (+ pi 1) si) #t (if (if (< si sn) (not (= c #\/)) #f) (self pi (+ si 1)) #f)))
              ((= p #\?) (if (if (< si sn) (not (= c #\/)) #f) (self (+ pi 1) (+ si 1)) #f))
              ((= p #\[)
                (if (if (< si sn) (not (= c #\/)) #f)
                  (let ((r (%cu-glob-class pat (+ pi 1) c)))
                    (if (null? r) (if (= p c) (self (+ pi 1) (+ si 1)) #f)
                      (if (first r) (self (rest r) (+ si 1)) #f)))
                  #f))
              ((if (= p #\\) (< (+ pi 1) pn) #f)
                (if (= (byte-at pat (+ pi 1)) c) (self (+ pi 2) (+ si 1)) #f))
              (#t (if (= p c) (self (+ pi 1) (+ si 1)) #f)))))))
    (go 0 0)))

; busybox's exclude_file: a pattern with a leading / against the whole name,
; any other against the name from each of its parts on
(def %tc-excluded?
  (fn (_ pats name)
    (def tails
      (fn (self i acc)
        (if (>= i (byte-len name)) acc
          (self (+ i 1)
            (if (if (if (= i 0) #t (= (byte-at name (- i 1)) #\/)) (not (= (byte-at name i) #\/)) #f)
              (pair (substring name i (byte-len name)) acc) acc)))))
    (def any
      (fn (self ps)
        (if (null? ps) #f
          (let ((p (first ps)))
            (if (if (if (> (byte-len p) 0) (= (byte-at p 0) #\/) #f)
                  (%tc-fnmatch? p name)
                  (pair? (filter (fn (_ t) (%tc-fnmatch? p t)) (tails 0 ()))))
              #t (self (rest ps)))))))
    (any pats)))

; busybox's writeFileToTarball for PATH and its stat ST: answers #t, #f
; where it failed, or (lit skip) where a directory is not to be gone into
(def %tc-file!
  (fn (_ c path st)
    (def name (%tar-safe path))
    (def get (fn (_ k) (%cu-stat-get st k)))
    (def type (& (get (lit mode)) 61440))
    (def hl
      (if (if (= type 16384) #f (> (get (lit nlink)) 1))
        (let ((seen (filter (fn (_ e) (if (= (first e) (get (lit dev))) (= (first (rest e)) (get (lit ino))) #f))
                            (vec-ref c 3))))
          (if (pair? seen) (rest (rest (first seen)))
            (do (vec-set! c 3 (pair (pair (get (lit dev)) (pair (get (lit ino)) name)) (vec-ref c 3))) ())))
        ()))
    (def self-dev (vec-ref c 4))
    (match
      ((= (byte-len name) 0) #t)
      ((%tc-excluded? (vec-ref c 2) name) (lit skip))
      ((= type 49152) (do (%tar-say (string-append path ": socket ignored")) #t))
      ((if (null? self-dev) #f (if (= (first self-dev) (get (lit dev))) (= (rest self-dev) (get (lit ino))) #f))
        (do (%tar-say (string-append path ": file is the archive; skipping")) #t))
      ((if (null? hl) (= type 32768) #f)
        (let ((src (%cu-pieces path ())))
          (if (Err err? src) (do (%tar-say (string-append path ": " (file-err-text src))) #f)
            (do (%tc-header! c name path st hl)
                (%tc-body! c src (get (lit size)))
                #t))))
      (#t (%tc-header! c name path st hl)))))

; a file's SIZE bytes into the archive, padded to the block
(def %tc-body!
  (fn (_ c src size)
    (def fd (%tc-fd c))
    (def go
      (fn (self left)
        (if (<= left 0) ()
          (let ((p (src)))
            (if (if (Err err? p) #t (= (rest p) 0)) (%tar-die "short read")
              (let ((k (%tar-min (rest p) left)))
                (do (%tc-emit! fd (if (= k (rest p)) p (pair (%tc-sub-run p k) k)))
                    (%cu-sweep-tick! %cu-sweep-lines)
                    (self (- left k)))))))))
    (do (go size)
        (src (lit close))
        (let ((pad (% (- 512 (% size 512)) 512)))
          (if (= pad 0) () (%tc-emit! fd (pair (%tc-block) pad)))))))

; the first K bytes of run P, as a string of its own
(def %tc-sub-run
  (fn (_ p k)
    (def buf (%str-make-raw (+ k 1)))
    (do (%cu-ptr-call %tar-c-memcpy (%tar-addr buf) (%tar-addr (first p)) k) buf)))

; busybox's recursive_action for PATH: the path itself, then -- a directory,
; unless --no-recursion or it was left out -- each entry in it.  #f where
; anything failed.
(def %tc-walk
  (fn (self c path)
    (def st (if (vec-ref c 5) (file-stat-full path) (file-lstat-full path)))
    (if (null? st)
      (do (%tar-say (string-concat (list path ": " (%tar-why (lit stat) path)))) #f)
      (let ((r (%tc-file! c path st)))
        (if (if (eq? r (lit skip)) #t
              (if (vec-ref c 6) (not (= (& (%cu-stat-get st (lit mode)) 61440) 16384)) #t))
          (not (eq? r #f))
          (let ((names (guard (e ()) (file-list-dir path))))
            (let ((base (if (= (byte-at path (- (byte-len path) 1)) #\/) path (string-append path "/"))))
              (let ((oks (map (fn (_ n) (self c (string-append base n))) names)))
                (if (eq? r #f) #f (not (%tar-member? #f oks)))))))))))

(def %tar-member?
  (fn (self x l) (if (null? l) #f (if (eq? (first l) x) #t (self x (rest l))))))

; --- the applet ------------------------------------------------------------------------

; busybox's first-argument compatibility: a first word with no dash is a run
; of option letters, its f moved last so the next word is f's
(def %tar-compat-argv
  (fn (_ argv)
    (if (if (pair? argv) (if (> (byte-len (first argv)) 0) (not (= (byte-at (first argv) 0) #\-)) #f) #f)
      (let ((w (first argv)))
        (let ((f (%dp-find w 0 #\f)))
          (pair (string-append "-" (if (< f 0) w
                                     (string-concat (list (substring w 0 f) (substring w (+ f 1) (byte-len w)) "f"))))
                (rest argv))))
      argv)))

; a name as busybox takes it: a trailing / gone, unless it is all there is
(def %tar-unslash
  (fn (_ s) (if (if (> (byte-len s) 1) (= (byte-at s (- (byte-len s) 1)) #\/) #f) (substring s 0 (- (byte-len s) 1)) s)))

; the lines of the files NAMES, each a name, as -T and -X read them
(def %tar-file-lines
  (fn (_ names)
    (def one
      (fn (_ f)
        (let ((src (%cu-pieces f ())))
          (if (Err err? src) (%tar-die (string-concat (list "can't open '" f "': " (file-err-text src))))
            (let ((text (string-concat (map %cu-run-text (%tar-all-pieces src)))))
              (map %tar-unslash (%cu-lines text)))))))
    (%tar-flatten (map one names))))

(def %tar-all-pieces
  (fn (_ src)
    (def go (fn (self acc) (let ((p (src))) (if (if (Err err? p) #t (= (rest p) 0)) (do (src (lit close)) (reverse acc)) (self (pair p acc))))))
    (go ())))

(def %tar-flatten (fn (self ls) (if (null? ls) () (append (first ls) (self (rest ls))))))

(def %tar-count
  (fn (_ o flags) (length (filter (fn (_ f) (%cu-member-s? f flags)) (Assoc get (lit on) o)))))

; tar c|x|t [-hmvokO] [-f TARFILE] [-C DIR] [-T FILE] [-X FILE] [LONGOPT]... [FILE]...
(def %cu-tar
  (fn (_ argv stdin-thunk)
    (guard (e (if (eq? (%cu-err-label e) (lit tar))
                (do (file-write 2 (string-append (e msg) "\n")) 1)
                (error e)))
      (%tar-run (%tar-compat-argv argv) stdin-thunk))))

(def %tar-run
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "tar" argv))
    (def on (fn (_ a b) (if (Opts on? o a) #t (Opts on? o b))))
    (def val (fn (_ a b) (let ((v (Opts value o a))) (if (null? v) (Opts value o b) v))))
    (def modes (filter (fn (_ x) x) (list (on "-c" "--create") (on "-x" "--extract") (on "-t" "--list"))))
    (def verbose (%tar-count o (list "-t" "--list" "-v" "--verbose")))
    (def file (let ((f (val "-f" "--file"))) (if (null? f) "-" f)))
    (def accept
      (append (%tar-file-lines (append (Opts values o "-T") (Opts values o "--files-from")))
              (map %tar-unslash (Opts operands o))))
    (def reject
      (append (%tar-file-lines (append (Opts values o "-X") (Opts values o "--exclude-from")))
              (Opts values o "--exclude")))
    (def strip (let ((s (Opts value o "--strip-components")))
                 (if (null? s) 0 (%cu-range-number "tar" s 0 2147483647))))
    (do (set! %tar-warned #f)
        (set! %tc-sink ())
        (set! %tar-pending ())
        (%tar-resolve!)
        (match
          ((not (= (length modes) 1)) (%cu-usage "tar"))
          ((null? strip) 1)
          ((on "-c" "--create") (%tar-create o file verbose accept reject))
          (#t (%tar-extract-run o on file verbose accept reject strip stdin-thunk))))))

; -C's directory: the run goes there, and comes back when it ends
(def %tar-in-dir
  (fn (_ dir thunk)
    (if (null? dir) (thunk)
      (let ((home (sys-getcwd)))
        (if (< (Sys chdir dir) 0)
          (%tar-die (string-concat (list "can't change directory to '" dir "': " (%tar-why (lit chdir) dir))))
          (let ((r (guard (e (do (Sys chdir home) (error e))) (thunk))))
            (do (Sys chdir home) r)))))))

(def %tar-extract-run
  (fn (_ o on file verbose accept reject strip stdin-thunk)
    (def root (= (%cu-ptr-call %tar-c-getuid) 0))
    (def t
      (vec-build 11
        (fn (_ i)
          (match
            ((= i 0) (match ((on "-O" "--to-stdout") (lit stdout)) ((on "-x" "--extract") (lit extract)) (#t (lit list))))
            ((= i 1) verbose) ((= i 2) accept) ((= i 3) reject) ((= i 4) strip)
            ((= i 5) (on "-k" "--keep-old")) ((= i 6) (Opts on? o "--overwrite"))
            ((= i 7) (on "-o" "--no-same-owner")) ((= i 8) (Opts on? o "--numeric-owner"))
            ((= i 9) (if root (not (Opts on? o "--no-same-permissions")) #f))
            (#t (not (on "-m" "--touch")))))))
    (def raw (%cu-pieces file stdin-thunk))
    ; z, or data that begins with gzip's magic, is read through gunzip
    (def src (if (Err err? raw) raw
               (if (on "-z" "--gzip") (%gz-tar-pieces raw)
                 (let ((s (%gz-sniff raw))) (if (first s) (%gz-tar-pieces (rest s)) (rest s))))))
    (if (Err err? src) (%tar-die (string-concat (list "can't open '" file "': " (file-err-text src))))
      (%tar-in-dir (let ((d (Opts value o "-C"))) (if (null? d) (Opts value o "--directory") d))
        (fn (_)
          (let ((r (%tar-read-all t (%tar-reader src))))
            (do (src (lit close))
                (%tar-make-links!)
                (map (fn (_ a)
                       (if (if (%tar-list-match? reject a) #t (pair? (filter (fn (_ p) (%cu-glob? p a)) (first r)))) ()
                         (%tar-die (string-append a ": not found in archive"))))
                     accept)
                (if (rest r) 0 1))))))))

(def %tar-create
  (fn (_ o file verbose accept reject)
    (def fd (if (string=? file "-") 1
              (let ((f (File open file (list (lit wronly) (lit creat) (lit trunc)) 438)))
                (if (< f 0) (%tar-die (string-concat (list "can't open '" file "': " (file-err-text (file-open-err f file)))))
                  f))))
    (def self (if (= fd 1) ()
                (let ((st (file-stat-full file)))
                  (if (null? st) () (pair (%cu-stat-get st (lit dev)) (%cu-stat-get st (lit ino)))))))
    (def c
      (vec-build 7
        (fn (_ i)
          (match
            ((= i 0) fd) ((= i 1) (> verbose 0)) ((= i 2) reject) ((= i 3) ()) ((= i 4) self)
            ((= i 5) (if (Opts on? o "-h") #t (Opts on? o "--dereference")))
            (#t (not (Opts on? o "--no-recursion")))))))
    (if (null? accept) (%tar-die "empty archive")
      (%tar-in-dir (let ((d (Opts value o "-C"))) (if (null? d) (Opts value o "--directory") d))
        (fn (_)
          (let ((oks (do (set! %tc-sink (if (%tar-gzip? o file) (%gz-sink fd) ()))
                         (map (fn (_ n) (%tc-walk c n)) accept))))
            (do (%tc-emit! fd (pair (%tc-block) 512))
                (%tc-emit! fd (pair (%tc-block) 512))
                (if (null? %tc-sink) () (do (%gz-sink-close! %tc-sink) (set! %tc-sink ())))
                (if (= fd 1) () (file-close fd))
                (if (%tar-member? #f oks)
                  (do (%tar-say "error exit delayed from previous errors") 1)
                  0))))))))

; c writes through gzip under z, or a with an archive named *gz
(def %tar-gzip?
  (fn (_ o file)
    (match
      ((Opts on? o "-z") #t)
      ((Opts on? o "--gzip") #t)
      ((Opts on? o "-a") (%gz-ends? file "gz"))
      (#t #f))))

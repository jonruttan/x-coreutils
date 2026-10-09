; # x-coreutils -- the small tools, as applets
;
; ## cu/cpio.x -- cpio
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's cpio (archival/cpio.c, libarchive's get_header_cpio and
; data_extract_all).  -t lists an archive read from standard input, -i
; extracts it, -o writes one of the names read from standard input, and -p
; DIR copies those names into DIR through an archive, written by a child
; process into a pipe the parent extracts from.  The archive is newc (070701)
; or crc (070702, whose checksum is not checked); -o writes newc only, and
; wants -H newc said.
;
; Names after the options choose members, each a glob as fnmatch without
; flags matches it.  A member is made only where nothing as new is there
; already, unless -u; a name with a leading / loses it, and nothing else
; is taken off it -- busybox's FEATURE_PATH_TRAVERSAL_PROTECTION is off by
; default, as GNU cpio has no such check.  A file of several names is in the
; archive once with its data, under its last name, and under the others with
; none; those are made as hard links once the archive is read, and are not
; listed.  The archive's size in 512-byte blocks is said on stderr at its
; end, unless --quiet.

; the run ends: MSG said under cpio's name, and the status 1
(def %cp-die (fn (_ msg) (Err raise (lit cpio) (string-append "cpio: " msg) ())))

(def %cp-say (fn (_ msg) (file-write 2 (string-concat (list "cpio: " msg "\n")))))

; --- reading the archive -------------------------------------------------------

; past the padding to the next 4-byte boundary
(def %cp-align!
  (fn (_ rd)
    (let ((r (% (vec-ref rd 3) 4))) (if (= r 0) () (%tar-skip! rd (- 4 r))))))

; the 8 hex digits of H at OFF, or nil where they are not all hex
(def %cp-hex
  (fn (_ h off)
    (def go
      (fn (self i v)
        (if (= i (+ off 8)) v
          (let ((c (byte-at h i)))
            (match
              ((if (>= c #\0) (<= c #\9) #f) (self (+ i 1) (+ (* v 16) (- c #\0))))
              ((if (>= c #\a) (<= c #\f) #f) (self (+ i 1) (+ (* v 16) (- c 87))))
              ((if (>= c #\A) (<= c #\F) #f) (self (+ i 1) (+ (* v 16) (- c 55))))
              (#t ()))))))
    (go off 0)))

; N bytes of the archive as a string, up to a NUL among them; dies short
(def %cp-text
  (fn (_ rd n)
    (def buf (%str-make-raw (+ n 1)))
    (if (< (%tar-fill! rd buf 0 n) n) (%cp-die "short read")
      (%tar-field buf 0 n))))

; NAME with its leading slashes gone
(def %cp-unroot
  (fn (_ name)
    (def go (fn (self i) (if (if (< i (byte-len name)) (= (byte-at name i) #\/) #f) (self (+ i 1)) i)))
    (let ((i (go 0))) (if (= i 0) name (substring name i (byte-len name))))))

; The run's reading state, in a vector: the hard links still to make, as
; (INODE . MEMBER); those made, the same; the archive's blocks, nil until its
; trailer is read.
(def %cs-pending (fn (_ s) (vec-ref s 0)))
(def %cs-made (fn (_ s) (vec-ref s 1)))

; The next member, as get_header_cpio reads it: (lit end) at the end of the
; archive, (lit later) for a hard link held back, or the member, a vector as
; cu/tar.x's: NAME MODE UID GID SIZE MTIME LINK UNAME GNAME DEVICE.  OWNER
; is -R's (UID . GID), -1 where it gives none.
(def %cp-header
  (fn (_ rd s owner)
    (def h (%str-make-raw 111))
    (do (%cp-align! rd)
        (let ((got (%tar-fill! rd h 0 110)))
          (match
            ((= got 0) (lit end))
            ((< got 110) (%cp-die "short read"))
            ((not (if (string=? (substring h 0 5) "07070")
                    (if (= (byte-at h 5) #\1) #t (= (byte-at h 5) #\2)) #f))
              (%cp-die "unsupported cpio format, use newc or crc"))
            (#t (let ((fs (map (fn (_ off) (%cp-hex h off)) (list 6 14 22 30 38 46 54 78 86 94))))
                  (if (%tar-member? () fs) (%cp-die "damaged cpio file")
                    (%cp-member rd s owner fs)))))))))

(def %cp-member
  (fn (_ rd s owner fs)
    (def at (fn (_ k) (%cu-nth k fs)))
    (def mode (& (at 1) 4294967295))
    (def type (& mode 61440))
    (def name (%cp-unroot (%cp-text rd (& (at 9) 8191))))
    (def size (at 6))
    (def link (if (= type 40960) (do (%cp-align! rd) (%cp-text rd (& size 8191))) ()))
    (def m
      (vec-build 10
        (fn (_ i)
          (match
            ((= i 0) name)
            ((= i 1) mode)
            ((= i 2) (if (< (first owner) 0) (at 2) (first owner)))
            ((= i 3) (if (< (rest owner) 0) (at 3) (rest owner)))
            ((= i 4) (if (null? link) size 0))
            ((= i 5) (at 5))
            ((= i 6) link)
            ((= i 9) (pair (at 7) (at 8)))
            (#t ())))))
    (do (if (null? link) (%cp-align! rd) ())
        (match
          ((string=? name "TRAILER!!!")
            (do (vec-set! s 2 (%cal/ (+ (vec-ref rd 3) 511) 512)) (lit end)))
          ((if (> (at 4) 1) (= type 32768) #f)
            (if (= size 0)
              (do (vec-set! s 0 (pair (pair (at 0) m) (%cs-pending s))) (lit later))
              (do (vec-set! s 1 (pair (pair (at 0) m) (%cs-made s))) m)))
          (#t m)))))

; --- making the members -------------------------------------------------------

; The run's settings, in a vector: the action (list, extract or stdout),
; verbose, the names to take, -u, -d, -m.
(def %ct-action (fn (_ t) (vec-ref t 0)))

; member M is one the run takes
(def %cp-wanted?
  (fn (_ t m)
    (let ((pats (vec-ref t 2)))
      (if (null? pats) #t
        (pair? (filter (fn (_ p) (%cu-glob? p (%tm-name m))) pats))))))

; the links to make once the archive is read: (HARD? NAME . TARGET), newest first
(def %cp-links ())

; member M made, its data read from RD, as data_extract_all makes it
(def %cp-extract!
  (fn (_ t rd m)
    (def dst (%tm-name m))
    (def mode (%tm-mode m))
    (def type (& mode 61440))
    (def hard (if (if (= type 32768) (= (%tm-size m) 0) #f) (%tm-link m) ()))
    (do (if (vec-ref t 4)
          (let ((sl (%tar-last-slash dst))) (if (> sl 0) (%cu-mkdir-p! (substring dst 0 sl)) ()))
          ())
        (if (if (vec-ref t 3) (%cp-unlink-old! dst type hard) (%cp-newer-there? m dst type))
          (%tar-skip! rd (%tm-size m))
          (if (null? hard) (%cp-make! t rd m dst type mode)
            (set! %cp-links (pair (pair #t (pair dst hard)) %cp-links)))))))

; -u: DST removed if it is there, a directory left; #t where nothing is to be
; made, a hard link to itself
(def %cp-unlink-old!
  (fn (_ dst type hard)
    (match
      ((= type 16384) #f)
      ((if (null? hard) #f (string=? hard dst)) #t)
      ((eq? (file-lstat-file-type dst) (lit none)) #f)
      ((guard (e #f) (do (file-unlink dst) #t)) #f)
      (#t (%cp-die (string-concat (list "can't remove old file " dst ": " (%tar-why (lit unlink) dst))))))))

; without -u: #t where DST is there and as new as M, said unless it is a
; directory; an older one is removed
(def %cp-newer-there?
  (fn (_ m dst type)
    (def st (file-lstat-full dst))
    (match
      ((null? st) #f)
      ((>= (%cu-stat-get st (lit mtime)) (vec-ref m 5))
        (do (if (= type 16384) ()
              (%cp-say (string-append dst " not created: newer or same age file exists")))
            #t))
      ((= (& (%cu-stat-get st (lit mode)) 61440) 16384) #f)
      ((guard (e #f) (do (file-unlink dst) #t)) #f)
      (#t (%cp-die (string-concat (list "can't remove old file " dst ": " (%tar-why (lit unlink) dst))))))))

(def %cp-make!
  (fn (_ t rd m dst type mode)
    (do
      (match
        ((= type 32768)
          (let ((fd (File open dst (list (lit wronly) (lit creat) (lit excl)) (& mode 4095))))
            (if (< fd 0)
              (%cp-die (string-concat (list "can't open '" dst "': " (file-err-text (file-open-err fd dst)))))
              (let ((got (%tar-copy-out! rd fd (%tm-size m))))
                (do (file-close fd)
                    (if (< got (%tm-size m)) (%cp-die "short read") ()))))))
        ((= type 16384)
          (if (< (Sys %sign-fold (%cu-ptr-call %tar-c-mkdir dst (& mode 4095))) 0)
            (let ((why (%tar-why (lit mkdir) dst)))
              (if (string=? why "File exists") ()
                (%cp-say (string-concat (list "can't make dir " dst ": " why)))))
            ()))
        ((= type 40960)
          (let ((l (%tm-link m)))
            (if (if (= (byte-at l 0) #\/) #t (>= (%tar-find-str l "..") 0))
              (set! %cp-links (pair (pair #f (pair dst l)) %cp-links))
              (if (guard (e #f) (do (file-symlink l dst) #t)) ()
                (%cp-die (string-concat (list "can't create symlink '" dst "' to '" l "': "
                                              (%tar-why (lit symlink) dst))))))))
        ((if (= type 8192) #t (if (= type 24576) #t (if (= type 4096) #t (= type 49152))))
          (if (< (Sys %sign-fold (%cu-ptr-call %tar-c-mknod dst mode (%tar-makedev (vec-ref m 9)))) 0)
            (%cp-say (string-concat (list "can't create node " dst ": " (%tar-why (lit mknod) dst))))
            ()))
        (#t (%cp-die "unrecognized file type")))
      (if (= type 40960) ()
        (do (guard (e ()) (file-chown dst (vec-ref m 2) (vec-ref m 3)))
            (guard (e ()) (file-chmod dst (& mode 4095)))
            (if (vec-ref t 5) (guard (e ()) (file-set-times dst (vec-ref m 5) (vec-ref m 5))) ()))))))

; the links held back, made in the order they were met
(def %cp-make-links!
  (fn (_)
    (map (fn (_ l)
           (let ((name (first (rest l))) (target (rest (rest l))))
             (if (guard (e #f) (do (if (first l) (file-link target name) (file-symlink target name)) #t)) ()
               (%cp-die (string-concat (list "can't create " (if (first l) "hard" "sym") "link '"
                                             name "' to '" target "'"))))))
         (reverse %cp-links))))

; member M's data: made, written out, or passed over
(def %cp-data!
  (fn (_ t rd m)
    (match
      ((eq? (%ct-action t) (lit extract)) (%cp-extract! t rd m))
      ((eq? (%ct-action t) (lit stdout))
        (if (< (%tar-copy-out! rd 1 (%tm-size m)) (%tm-size m)) (%cp-die "short read") ()))
      (#t (%tar-skip! rd (%tm-size m))))))

; member M named, as -t and -v name it
(def %cp-name!
  (fn (_ t m)
    (match
      ((eq? (%ct-action t) (lit list))
        (file-write 1 (if (vec-ref t 1) (%tar-verbose-line m)
                        (string-append (%tar-printable (%tm-name m)) "\n"))))
      ((vec-ref t 1)
        (file-write (if (eq? (%ct-action t) (lit stdout)) 2 1)
          (string-append (%tar-printable (%tm-name m)) "\n")))
      (#t ()))))

; The members of RD, each taken or passed over; then the hard links held
; back, each made as a link to the member with its inode, or empty where none
; has it.  Answers the archive's blocks, nil where it had no trailer.
(def %cp-read-all
  (fn (_ t rd owner)
    (def s (vec-make 3 ()))
    (def go
      (fn (self)
        (let ((m (%cp-header rd s owner)))
          (match
            ((eq? m (lit end)) ())
            ((eq? m (lit later)) (self))
            ((%cp-wanted? t m)
              (do (%cp-data! t rd m) (%cp-name! t m) (%cu-sweep-tick! %cu-sweep-lines) (self)))
            (#t (do (%tar-skip! rd (%tm-size m)) (self)))))))
    (def held
      (fn (self)
        (let ((ps (%cs-pending s)))
          (if (null? ps) ()
            (let ((ino (first (first ps))) (m (rest (first ps))))
              (let ((to (filter (fn (_ e) (= (first e) ino)) (%cs-made s))))
                (do (vec-set! s 0 (rest ps))
                    (if (pair? to)
                      (let ((l (vec-build 10 (fn (_ i) (if (= i 6) (%tm-name (rest (first to))) (vec-ref m i))))))
                        (if (%cp-wanted? t l) (%cp-data! t rd l) ()))
                      (do (if (%cp-wanted? t m) (%cp-data! t rd m) ())
                          (vec-set! s 1 (pair (first ps) (%cs-made s)))))
                    (self))))))))
    (do (go) (held) (vec-ref s 2))))

; --- writing an archive --------------------------------------------------------

; The run's create settings, in a vector: the archive's descriptor, -L,
; -R's owner, --ignore-devno, --renumber-inodes, the inodes numbered so far,
; the bytes written, the hard links met as vectors of INODE STAT NAMES, newest
; first and their names newest first.
(def %co-fd (fn (_ c) (vec-ref c 0)))

; a stat as -o writes it: INO MODE UID GID NLINK MTIME SIZE DEV RDEV
(def %co-stat
  (fn (_ c st)
    (def get (fn (_ k) (%cu-stat-get st k)))
    (def owner (vec-ref c 2))
    (def type (& (get (lit mode)) 61440))
    (list (get (lit ino)) (get (lit mode))
          (if (< (first owner) 0) (get (lit uid)) (first owner))
          (if (< (rest owner) 0) (get (lit gid)) (rest owner))
          (get (lit nlink)) (get (lit mtime))
          (if (if (= type 40960) #t (= type 32768)) (get (lit size)) 0)
          (get (lit dev)) (get (lit rdev)))))

(def %co-hex8
  (fn (_ v) (%cu-pad-zero (%dp-udigits (& v 4294967295) 16 #t) 8)))

; N NUL bytes into the archive
(def %co-nuls!
  (fn (_ c n)
    (if (= n 0) ()
      (do (file-write-run (%co-fd c) (pair (%tc-block) n))
          (vec-set! c 6 (+ (vec-ref c 6) n))))))

(def %co-text!
  (fn (_ c s)
    (do (file-write (%co-fd c) s) (vec-set! c 6 (+ (vec-ref c 6) (byte-len s))))))

; the header for NAME and its stat ST, then its data: a link's target, or a
; file's SIZE bytes
(def %co-entry!
  (fn (_ c name st)
    (def at (fn (_ k) (%cu-nth k st)))
    (def devno (fn (_ k) (if (vec-ref c 3) 0 (at k))))
    (def type (& (at 1) 61440))
    (do (if (> (at 6) 4294967295)
          (%cp-die (string-concat (list "error: file '" name "' is larger than 4GB"))) ())
        (%co-text! c (string-concat
                       (list "070701"
                             (string-concat (map (fn (_ k) (%co-hex8 (at k))) (list 0 1 2 3 4 5 6)))
                             (%co-hex8 (%cu-dev-major (devno 7))) (%co-hex8 (%cu-dev-minor (devno 7)))
                             (%co-hex8 (%cu-dev-major (devno 8))) (%co-hex8 (%cu-dev-minor (devno 8)))
                             (%co-hex8 (+ (byte-len name) 1)) "00000000" name)))
        (%co-nuls! c (+ 1 (& (- 0 (+ (vec-ref c 6) 1)) 3)))
        (if (= (at 6) 0) ()
          (do (if (= type 40960)
                (let ((l (guard (e ()) (file-readlink name))))
                  (if (null? l) (%cp-die (string-concat (list name ": " (%tar-why (lit readlink) name))))
                    (%co-text! c l)))
                (%co-body! c name (at 6)))
              (%co-nuls! c (& (- 0 (vec-ref c 6)) 3)))))))

; a file's SIZE bytes into the archive
(def %co-body!
  (fn (_ c name size)
    (def src (%cu-pieces name ()))
    (def go
      (fn (self left)
        (if (<= left 0) ()
          (let ((p (src)))
            (if (if (Err err? p) #t (= (rest p) 0)) (%cp-die "short read")
              (let ((k (%tar-min (rest p) left)))
                (do (file-write-run (%co-fd c) (if (= k (rest p)) p (pair (%tc-sub-run p k) k)))
                    (vec-set! c 6 (+ (vec-ref c 6) k))
                    (%cu-sweep-tick! %cu-sweep-lines)
                    (self (- left k)))))))))
    (if (Err err? src) (%cp-die (string-concat (list "can't open '" name "': " (file-err-text src))))
      (do (go size) (src (lit close))))))

; NAME as -o takes it: each leading ./ gone, with the slashes after it
(def %co-undot
  (fn (_ name)
    (def n (byte-len name))
    (def go
      (fn (self i)
        (if (if (< (+ i 1) n) (if (= (byte-at name i) #\.) (= (byte-at name (+ i 1)) #\/) #f) #f)
          (let ((past (fn (self j) (if (if (< j n) (= (byte-at name j) #\/) #f) (self (+ j 1)) j))))
            (self (past (+ i 1))))
          i)))
    (let ((i (go 0))) (if (= i 0) name (substring name i n)))))

; the next name -o reads from SRC, cut at SEP, or nil at the end; BUF holds
; the piece being read and where in it
(def %co-next-name
  (fn (_ src buf sep)
    (def take
      (fn (self acc)
        (let ((p (vec-ref buf 0)))
          (if (if (null? p) #t (>= (vec-ref buf 1) (rest p)))
            (let ((q (src)))
              (if (if (Err err? q) #t (= (rest q) 0))
                (if (null? acc) () (string-concat (reverse acc)))
                (do (vec-set! buf 0 q) (vec-set! buf 1 0) (self acc))))
            (let ((from (vec-ref buf 1)))
              (let ((at (let ((f (fn (self i) (if (if (< i (rest p)) (not (= (byte-at (first p) i) sep)) #f) (self (+ i 1)) i))))
                          (f from))))
                (do (vec-set! buf 1 (+ at 1))
                    ; byte by byte: a string's length stops at its first NUL
                    (let ((piece (bytes->str (map (fn (_ i) (byte-at (first p) i)) (List range from at)))))
                      (if (< at (rest p)) (string-concat (reverse (pair piece acc)))
                        (self (pair piece acc)))))))))))
    (take ())))

; busybox's cpio_o: the archive of the names on SRC, written to FD
(def %cp-create
  (fn (_ o fd src owner nul)
    (def c (vec-build 8 (fn (_ i) (match ((= i 0) fd) ((= i 1) (Opts on? o "-L")) ((= i 2) owner)
                                          ((= i 3) (Opts on? o "--ignore-devno"))
                                          ((= i 4) (Opts on? o "--renumber-inodes"))
                                          ((= i 5) 0) ((= i 6) 0) (#t ())))))
    (def renumber (fn (_) (do (vec-set! c 5 (+ (vec-ref c 5) 1)) (vec-ref c 5))))
    (def with-ino (fn (_ st ino) (pair ino (rest st))))
    (def buf (vec-make 2 ()))
    (def sep (if nul 0 #\newline))
    (def names
      (fn (self)
        (let ((line (%co-next-name src buf sep)))
          (if (null? line) ()
            (let ((name (%co-undot line)))
              (if (= (byte-len name) 0) (self)
                (let ((raw (if (vec-ref c 1) (file-stat-full name) (file-lstat-full name))))
                  (if (null? raw) (%cp-die (string-concat (list name ": " (%tar-why (lit stat) name))))
                    (let ((st (%co-stat c raw)))
                      (do (if (if (= (& (%cu-nth 1 st) 61440) 16384) #f (> (%cu-nth 4 st) 1))
                            (let ((l (filter (fn (_ e) (= (vec-ref e 0) (first st))) (vec-ref c 7))))
                              (if (pair? l) (vec-set! (first l) 2 (pair name (vec-ref (first l) 2)))
                                (vec-set! c 7 (pair (vec-build 3 (fn (_ i) (match ((= i 0) (first st))
                                                                              ((= i 1) (if (vec-ref c 4) (with-ino st (renumber)) st))
                                                                              (#t (list name)))))
                                                    (vec-ref c 7)))))
                            (%co-entry! c name (if (vec-ref c 4) (with-ino st (renumber)) st)))
                          (%cu-sweep-tick! %cu-sweep-lines)
                          (self)))))))))))
    ; each file of several names, its last name with the data, the rest without
    (def links
      (fn (self ls)
        (if (null? ls) ()
          (let ((st (vec-ref (first ls) 1)))
            (let ((ns (vec-ref (first ls) 2)))
              (do (map (fn (_ n) (%co-entry! c n (if (eq? n (first (reverse ns))) st
                                                   (append (%cu-take st 6) (pair 0 (%cu-nthrest 7 st))))))
                       ns)
                  (self (rest ls))))))))
    (do (names)
        (links (vec-ref c 7))
        (%co-entry! c "TRAILER!!!" (list 0 0 0 0 0 0 0 0 0))
        0)))

; --- the applet ----------------------------------------------------------------

; -R's USER[:GRP], as parse_chown_usergroup_or_die reads it: (UID . GID), -1
; where it gives none
(def %cp-owner
  (fn (_ spec)
    (def colon (%dp-find spec 0 #\:))
    (def num (fn (_ s) (if (%si-digits? s) (%cu-num-prefix s) ())))
    (def user
      (fn (_ s) (let ((n (num s))) (if (null? n) (let ((u (sys-user-id s))) (if (null? u) (%cp-die (string-append "unknown user " s)) u)) n))))
    (def group
      (fn (_ s) (let ((n (num s))) (if (null? n) (let ((g (sys-group-id s))) (if (null? g) (%cp-die (string-append "unknown group " s)) g)) n))))
    (match
      ((< colon 0) (pair (user spec) -1))
      ((= colon 0) (pair -1 (group (substring spec 1 (byte-len spec)))))
      (#t
        (let ((u (substring spec 0 colon)) (g (substring spec (+ colon 1) (byte-len spec))))
          (let ((uid (let ((n (num u))) (if (null? n) (sys-user-id u) n))))
            (if (null? uid) (%cp-die (string-append "unknown user/group " spec))
              (let ((ug (let ((who (sys-user-name uid)))
                          (let ((pg (if (null? who) () (sys-user-group who)))) (if (null? pg) uid pg)))))
                (if (= (byte-len g) 0) (pair uid ug)
                  (let ((gid (let ((n (num g))) (if (null? n) (sys-group-id g) n))))
                    (if (null? gid) (%cp-die (string-append "unknown user/group " spec))
                      (pair uid gid))))))))))))

; cpio [-dmvu] [-F FILE] [-R USER[:GRP]] [-H newc] [-tio] [-p DIR] [EXTR_FILE]...
(def %cu-cpio
  (fn (_ argv stdin-thunk)
    (guard (e (if (eq? (%cu-err-label e) (lit cpio))
                (do (file-write 2 (string-append (e msg) "\n")) 1)
                (error e)))
      (%cp-run argv stdin-thunk))))

(def %cp-run
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "cpio" argv))
    (def on (fn (_ a b) (if (Opts on? o a) #t (Opts on? o b))))
    (def val (fn (_ a b) (let ((v (Opts value o a))) (if (null? v) (Opts value o b) v))))
    (def owner (let ((r (val "-R" "--owner"))) (if (null? r) (pair -1 -1) (%cp-owner r))))
    (def file (val "-F" "--file"))
    (def create (on "-o" "--create"))
    ; -F names the archive read, or with -o the archive written
    (def src
      (if (if (null? file) #f (not create))
        (let ((s (%cu-pieces file ())))
          (if (Err err? s) (%cp-die (string-concat (list "can't open '" file "': " (file-err-text s)))) s))
        (%cu-pieces "-" stdin-thunk)))
    ; a bare -0 reads to Opts as a number, an operand; it is the flag
    (def nul (if (on "-0" "--null") #t (pair? (filter (fn (_ w) (string=? w "-0")) (Opts operands o)))))
    (def operands (filter (fn (_ w) (not (string=? w "-0"))) (Opts operands o)))
    (do (set! %cp-links ())
        (%tar-resolve!)
        (match
          ((on "-p" "--pass-through")
            (if (null? operands) (%cu-usage "cpio") (%cp-pass o on owner src operands nul)))
          (create
            (let ((fmt (val "-H" "--format")))
              (if (if (null? fmt) #t (if (= (byte-len fmt) 0) #t (not (= (byte-at fmt 0) #\n))))
                (%cu-usage "cpio")
                (let ((fd (if (null? file) 1 (%cp-open-out file))))
                  (let ((r (%cp-create o fd src owner nul)))
                    (do (if (= fd 1) () (file-close fd)) r))))))
          ((not (if (on "-t" "--list") #t (on "-i" "--extract"))) (%cu-usage "cpio"))
          (#t (%cp-extract-run o on owner src operands
                (match ((on "-t" "--list") (lit list)) ((Opts on? o "--to-stdout") (lit stdout))
                       (#t (lit extract)))))))))

(def %cp-open-out
  (fn (_ file)
    (let ((f (File open file (list (lit wronly) (lit creat) (lit trunc)) 438)))
      (if (< f 0) (%cp-die (string-concat (list "can't open '" file "': " (file-err-text (file-open-err f file)))))
        f))))

(def %cp-extract-run
  (fn (_ o on owner src accept action)
    (def t
      (vec-build 6
        (fn (_ i)
          (match
            ((= i 0) action) ((= i 1) (on "-v" "--verbose")) ((= i 2) accept)
            ((= i 3) (Opts on? o "-u")) ((= i 4) (Opts on? o "-d")) (#t (Opts on? o "-m"))))))
    (let ((blocks (%cp-read-all t (%tar-reader src) owner)))
      (do (src (lit close))
          (%cp-make-links!)
          (if (if (null? blocks) #t (Opts on? o "--quiet")) ()
            (file-write 2 (string-append (%cu-int->str blocks) " blocks\n")))
          0))))

; -p DIR: a child writes the archive of the names into a pipe, and the run
; extracts it in DIR
(def %cp-pass
  (fn (_ o on owner src operands nul)
    (def dir (first operands))
    (do (if (Opts on? o "-d") (guard (e ()) (%cu-mkdir-p! dir)) ())
        (let ((p (sys-pipe)))
          (let ((pid (sys-fork)))
            (if (= pid 0)
              (do (sys-close (first p))
                  (sys-exit (guard (e (if (eq? (%cu-err-label e) (lit cpio))
                                        (do (file-write 2 (string-append (e msg) "\n")) 1) 1))
                              (%cp-create o (rest p) src owner nul))))
              (do (sys-close (rest p))
                  (let ((home (sys-getcwd)))
                    (if (< (Sys chdir dir) 0)
                      (let ((why (%tar-why (lit chdir) dir)))
                        (do (sys-close (first p)) (sys-wait pid)
                            (%cp-die (string-concat (list "can't change directory to '" dir "': " why)))))
                      (let ((r (guard (e (do (Sys chdir home) (sys-close (first p)) (sys-wait pid) (error e)))
                                 (%cp-extract-run o on owner (%cu-fd-chunks (first p) "-") (rest operands)
                                   (lit extract)))))
                        (do (Sys chdir home) (sys-wait pid) r)))))))))))

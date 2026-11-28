; # x-coreutils -- the small tools, as applets
;
; ## lib/coreutils/ar.x -- ar
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's ar (archival/ar.c, libarchive's unpack_ar_archive and
; get_header_ar), with FEATURE_AR_LONG_FILENAMES and FEATURE_AR_CREATE on.
; t lists an archive's members, x makes them, p writes their data to
; standard output, and r writes the archive again with the FILEs named at
; its end; -v lists each member as it is taken, and -o gives a member made
; its time.  A first word without a dash is read as if it had one.
;
; A member is 60 bytes of header, its fields text padded with spaces, then
; its data, a header starting on an even byte.  A name of / is the symbol
; table, passed over; // is GNU's table of long names, and /N names the one
; at N in it.  A name ends at its first space or /.  FILEs after the archive
; choose members, each a glob as fnmatch without flags matches it.
;
; r keeps the members no FILE names, then adds each FILE: its name the
; first 15 bytes of its last part and a /, and its time, owner, mode and size
; as stat answers them.  A kept member is written under the name it was read
; as, and an archive is not padded at its end.

(module coreutils/ar)

(import coreutils/cli cu-opts cu-refuse-option cu-usage)
(import coreutils/date cu-date-mon-abbr)
(import coreutils/dump dp-udigits)
(import coreutils/find cu-glob?)
(import coreutils/fs3 cu-perm-places)
(import coreutils/perm cu-basename-of)
(import coreutils/prims byte-at byte-len cu-err-label cu-int->str cu-stat-get
  file-chmod file-chown file-close file-err-text file-fstat-full file-open-err
  file-set-times file-stat-full file-unlink file-write filter hx-strtoul map str-make-raw
  string-append string=? substring vec-build vec-ref vec-set!)
(import coreutils/tar tar-copy-out! tar-fill! tar-reader tar-resolve! tar-skip! tar-why)
(import coreutils/text cu-fd-chunks cu-pad-left cu-pad-right)

; the run ends: MSG said under ar's name, and the status 1
(def %arc-die (fn (_ msg) (Err raise (lit ar) (string-append "ar: " msg) ())))

; FD opened on NAME with FLAGS, or the run ends as xopen ends it
(def %arc-open
  (fn (_ name flags)
    (let ((fd (File open name flags 438)))
      (if (< fd 0)
        (%arc-die (%str-concat (list "can't open '" name "': " (file-err-text (file-open-err fd name)))))
        fd))))

; --- a member's header ------------------------------------------------------------

; The field of H at OFF, LEN bytes, read as bb_strtou reads it in BASE: its
; first byte a letter or digit, its digits ended by its end, a NUL or a byte
; that is neither, and its value under 2^32 - 1.  Any other ends the run.
(def %arc-num
  (fn (_ h off len base)
    (def f (substring h off (+ off len)))
    (def alnum?
      (fn (_ c)
        (match ((if (>= c #\0) (<= c #\9) #f) #t) ((if (>= (| c 32) #\a) (<= (| c 32) #\z) #f) #t)
               (#t #f))))
    (def r (hx-strtoul f 0 base 4294967294))
    (match
      ((not (alnum? (byte-at f 0))) (%arc-die "invalid ar header"))
      ((null? (first r)) (%arc-die "invalid ar header"))
      ((if (< (rest r) len) (alnum? (byte-at f (rest r))) #f) (%arc-die "invalid ar header"))
      (#t (first r)))))

; the bytes of S from I up to LIMIT, a NUL, a space or a /, as a string
(def %arc-name-at
  (fn (_ s i limit)
    (def go
      (fn (self k)
        (if (if (< k limit) (let ((c (byte-at s k))) (not (if (= c 0) #t (if (= c 32) #t (= c 47))))) #f)
          (self (+ k 1)) k)))
    (substring s i (go i))))

; N bytes of RD as a string, or the run ends as xread ends it
(def %arc-read
  (fn (_ rd n)
    (let ((s (str-make-raw n)))
      (if (< (tar-fill! rd s 0 n) n) (%arc-die "short read") s))))

; The state of a read, in a vector: the long names (nil until //), and their
; size.  The next member of RD, a vector of NAME MODE UID GID SIZE MTIME, or
; nil at the end of the archive.
(def %arc-header
  (fn (self rd st)
    (def h (str-make-raw 61))
    (if (< (tar-fill! rd h 0 60) 60) ()
      (let ((b (if (= (byte-at h 0) 10)
                 (if (< (tar-fill! rd h 60 1) 1) (%arc-die "short read") 1)
                 0)))
        (if (if (= (byte-at h (+ b 58)) 96) (= (byte-at h (+ b 59)) 10) #f)
          (let ((size (%arc-num h (+ b 48) 10 10)))
            (match
              ((if (= (byte-at h b) 47) (= (byte-at h (+ b 1)) 32) #f)
                (do (tar-skip! rd size) (self rd st)))
              ((if (= (byte-at h b) 47) (= (byte-at h (+ b 1)) 47) #f)
                (do (vec-set! st 0 (%arc-read rd size)) (vec-set! st 1 size) (self rd st)))
              (#t (%arc-member h b size st))))
          (%arc-die "invalid ar header"))))))

(def %arc-member
  (fn (_ h b size st)
    (def mode (| (%arc-num h (+ b 40) 8 8) 32768))
    (def gid (%arc-num h (+ b 34) 6 10))
    (def uid (%arc-num h (+ b 28) 6 10))
    (def mtime (%arc-num h (+ b 16) 12 10))
    (def name
      (if (= (byte-at h b) 47)
        (let ((at (%arc-num h (+ b 1) 15 10)))
          (if (>= at (vec-ref st 1)) (%arc-die "can't resolve long filename")
            (%arc-name-at (vec-ref st 0) at (vec-ref st 1))))
        (%arc-name-at h b (+ b 16))))
    (vec-build 6
      (fn (_ i) (match ((= i 0) name) ((= i 1) mode) ((= i 2) uid) ((= i 3) gid) ((= i 4) size)
                       (#t mtime))))))

(def %am-name (fn (_ m) (vec-ref m 0)))
(def %am-mode (fn (_ m) (vec-ref m 1)))
(def %am-size (fn (_ m) (vec-ref m 4)))
(def %am-mtime (fn (_ m) (vec-ref m 5)))

; --- taking the members -------------------------------------------------------------

; member M as -v lists it: header_verbose_list_ar's line, its time as ctime
; writes it less the weekday and seconds
(def %arc-verbose-line
  (fn (_ m)
    (def d (Date local (%am-mtime m)))
    (def at (fn (_ k) (Assoc get k d)))
    (def two (fn (_ n) (if (< n 10) (string-append "0" (cu-int->str n)) (cu-int->str n))))
    (%str-concat
      (list (cu-perm-places (%am-mode m)) " "
            (cu-int->str (vec-ref m 2)) "/" (cu-int->str (vec-ref m 3))
            (cu-pad-left (cu-int->str (%am-size m)) 7) " "
            (List ref (- (at (lit month)) 1) cu-date-mon-abbr)
            (cu-pad-left (cu-int->str (at (lit day))) 3) " "
            (two (at (lit hour))) ":" (two (at (lit minute))) " "
            (cu-int->str (at (lit year))) " " (%am-name m) "\n"))))

; the FILEs name M, or there are none
(def %arc-named?
  (fn (_ files m) (pair? (filter (fn (_ p) (cu-glob? p (%am-name m))) files))))

; member M made from RD's bytes, as data_extract_all makes a regular file
(def %arc-extract!
  (fn (_ rd m restore)
    (def name (%am-name m))
    (def fd (%arc-open name (list (lit wronly) (lit creat) (lit excl))))
    (do (if (< (tar-copy-out! rd fd (%am-size m)) (%am-size m))
          (do (file-close fd) (%arc-die "short read"))
          (file-close fd))
        (guard (e ()) (file-chown name (vec-ref m 2) (vec-ref m 3)))
        (guard (e ()) (file-chmod name (& (%am-mode m) 4095)))
        (if restore (guard (e ()) (file-set-times name (%am-mtime m) (%am-mtime m))) ()))))

; The members of RD, each the FILEs take listed and its data acted on; the
; others passed over.  ACT is list, extract or stdout.
(def %arc-read-all
  (fn (_ rd act verbose restore files)
    (def st (vec-build 2 (fn (_ i) (if (= i 0) () 0))))
    (def go
      (fn (self)
        (let ((m (%arc-header rd st)))
          (if (null? m) 0
            (do (if (if (null? files) #t (%arc-named? files m))
                  (do (match (verbose (file-write 1 (%arc-verbose-line m)))
                             ((eq? act (lit list)) (file-write 1 (string-append (%am-name m) "\n")))
                             (#t ()))
                      (match
                        ((eq? act (lit extract)) (%arc-extract! rd m restore))
                        ((eq? act (lit stdout))
                          (if (< (tar-copy-out! rd 1 (%am-size m)) (%am-size m)) (%arc-die "short read") ()))
                        (#t (tar-skip! rd (%am-size m)))))
                  (tar-skip! rd (%am-size m)))
                (self))))))
    (go)))

; RD past the archive's magic, or the run ends
(def %arc-magic!
  (fn (_ rd)
    (if (string=? (%arc-read rd 7) "!<arch>") () (%arc-die "invalid ar magic"))))

; --- writing an archive ---------------------------------------------------------------

; Where an archive is written, in a vector: its descriptor, and the bytes
; written.  S written, and counted.
(def %arc-put!
  (fn (_ out s)
    (do (file-write (vec-ref out 0) s) (vec-set! out 1 (+ (vec-ref out 1) (byte-len s))))))

; output_ar_header: a member's header, a newline before it where the last
; data ended on an odd byte
(def %arc-put-header!
  (fn (_ out name mtime uid gid mode size)
    (do (if (= (& (vec-ref out 1) 1) 1) (%arc-put! out "\n") ())
        (if (> size 9999999999) (%arc-die (%str-concat (list "'" name "' is bigger than ar can handle"))) ())
        (%arc-put! out
          (%str-concat
            (list (cu-pad-right (if (> (byte-len name) 16) (substring name 0 16) name) 16)
                  (cu-pad-right (cu-int->str (if (> mtime 99999999999) 0 mtime)) 12)
                  (cu-pad-right (cu-int->str (if (> uid 99999) 0 uid)) 6)
                  (cu-pad-right (cu-int->str (if (> gid 99999) 0 gid)) 6)
                  (cu-pad-right (dp-udigits (& mode 2097151) 8 #f) 8)
                  (cu-pad-right (cu-int->str size) 10)
                  "`\n"))))))

; N bytes copied from RD to the archive, or the run ends
(def %arc-copy!
  (fn (_ out rd n)
    (if (< (tar-copy-out! rd (vec-ref out 0) n) n) (%arc-die "short read")
      (vec-set! out 1 (+ (vec-ref out 1) n)))))

; write_ar_header: FILE added, as stat finds it
(def %arc-add!
  (fn (_ out file)
    (def st (file-stat-full file))
    (def base (cu-basename-of file))
    (def name (string-append (if (> (byte-len base) 15) (substring base 0 15) base) "/"))
    (if (null? st) (%arc-die (%str-concat (list "can't stat '" file "': " (tar-why (lit stat) file))))
      (let ((size (cu-stat-get st (lit size))))
        (do (%arc-put-header! out name (cu-stat-get st (lit mtime)) (cu-stat-get st (lit uid))
              (cu-stat-get st (lit gid)) (cu-stat-get st (lit mode)) size)
            (let ((fd (%arc-open file (list (lit rdonly)))))
              (do (%arc-copy! out (tar-reader (cu-fd-chunks fd file)) size) (file-close fd))))))))

; write_ar_archive: ARCHIVE, open on FD, written again as the members it
; holds that no FILE names, then the FILEs.  One that held anything is
; removed and made afresh, its members read from FD.
(def %arc-write
  (fn (_ archive fd verbose files)
    (def st (file-fstat-full fd))
    (def old (if (null? st) (%arc-die (%str-concat (list "can't stat '" archive "': " (tar-why (lit stat) archive))))
               (> (cu-stat-get st (lit size)) 0)))
    (def out-fd
      (if old
        (do (if (guard (e #f) (do (file-unlink archive) #t)) ()
              (%arc-die (%str-concat (list "can't remove file '" archive "': " (tar-why (lit unlink) archive)))))
            (%arc-open archive (list (lit wronly) (lit creat) (lit trunc))))
        fd))
    (def out (vec-build 2 (fn (_ i) (if (= i 0) out-fd 0))))
    (def rd (tar-reader (cu-fd-chunks fd archive)))
    (def rst (vec-build 2 (fn (_ i) (if (= i 0) () 0))))
    (def keep
      (fn (self)
        (let ((m (%arc-header rd rst)))
          (if (null? m) ()
            (do (if (%arc-named? files m) (tar-skip! rd (%am-size m))
                  (do (if verbose (file-write 1 (%arc-verbose-line m)) ())
                      (%arc-put-header! out (%am-name m) (%am-mtime m) (vec-ref m 2) (vec-ref m 3)
                        (%am-mode m) (%am-size m))
                      (%arc-copy! out rd (%am-size m))))
                (self))))))
    (do (%arc-put! out "!<arch>\n")
        (if old (do (%arc-magic! rd) (keep)) ())
        (map (fn (_ f) (%arc-add! out f)) files)
        (if old (file-close out-fd) ())
        0)))

; --- the run ------------------------------------------------------------------------------

(def cu-ar
  (fn (_ argv stdin-thunk)
    (guard (e (if (eq? (cu-err-label e) (lit ar))
                (do (file-write 2 (string-append (e msg) "\n")) 1)
                (error e)))
      (%arc-run argv))))

(def %arc-run
  (fn (_ argv)
    ; a first word without a dash has one put before it
    (def args
      (if (if (pair? argv) (if (> (byte-len (first argv)) 0) (not (= (byte-at (first argv) 0) #\-)) #f) #f)
        (pair (string-append "-" (first argv)) (rest argv))
        argv))
    (def o (cu-opts "ar" args))
    (def on (fn (_ f) (Opts on? o f)))
    (def cmds (filter on (list "-p" "-t" "-x" "-r")))
    (def ops (Opts operands o))
    (match
      ((not (null? (Opts unknown o))) (cu-refuse-option "ar" (Opts unknown o)))
      ((match ((null? ops) #t) ((null? cmds) #t) (#t (pair? (rest cmds)))) (cu-usage "ar"))
      (#t (%arc-act (first ops) (rest ops) on)))))

; the command ON names, on ARCHIVE and the FILEs
(def %arc-act
  (fn (_ archive files on)
    (do (tar-resolve!)
        (if (on "-r")
          (%arc-write archive (%arc-open archive (list (lit rdwr) (lit creat))) (on "-v") files)
          (let ((fd (%arc-open archive (list (lit rdonly)))))
            (let ((rd (tar-reader (cu-fd-chunks fd archive))))
              (do (%arc-magic! rd)
                  (%arc-read-all rd
                    (match ((on "-p") (lit stdout)) ((on "-t") (lit list)) (#t (lit extract)))
                    (on "-v") (on "-o") files)
                  (file-close fd)
                  0)))))))

(provide coreutils/ar cu-ar)

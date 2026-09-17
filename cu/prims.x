; # x-coreutils -- the small tools, as applets
;
; ## cu/prims.x -- the platform layer
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The arc's rules: byte doors for anything per-character, the raw
; allocation door for read buffers, no defs at depth in anything hot.

(import x/sys/file)
(import x/sys/proc)
(import x/sys/date)
(import x/type/vector)
(import x/num/random)
(import x/type/struct)
(import x/sys/opts)

(provide cu/prims
  char->integer integer->char byte-at byte-len
  string-length substring string-append string-concat string=?
  list->string length reverse append map filter set-first!
  bit-and bit-or bit-xor bit-shl bit-shr
  file-read-all file-write-all file-exists? file-unlink file-mkdir
  file-open-write file-open-append file-close file-write file-read-fd
  file-list-dir file-rename file-rmdir file-open-excl file-dir?
  file-open-update
  file-stat file-chmod file-chown file-link file-symlink file-readlink
  file-or-err file-err-text file-err-sym file-err-op
  file-utimes file-set-times file-mkfifo file-statfs file-statfs-full file-mounts file-lstat-kind file-copy
  file-write-nuls file-write-field cu-stdin-fields!
  file-seek file-truncate file-open-read file-stat-full file-lstat-full
  vec-make vec-ref vec-set!
  proc-run sys-exit sys-dup2 sys-close
  sys-fork sys-wait sys-exec sys-kill sys-signal sys-isatty sys-usleep
  cu-sigterm cu-sigkill cu-sigint cu-sighup cu-sig-ign
  sys-getcwd sys-environ sys-getenv sys-sleep
  date-now-iso date-now-unix rng-make rng-int
  sys-getuid sys-geteuid sys-getgid sys-getegid sys-getgroups
  sys-uname sys-cpu-count sys-sync sys-fsync sys-nice sys-chroot
  cu-stdin!)

(def char->integer (prim-ref (lit char) (lit ->int)))
(def integer->char (prim-ref (lit int) (lit ->char)))
(def byte-at (prim-ref (lit str) (lit byte-ref)))
(def byte-len (prim-ref (lit str) (lit byte-len)))
(def %str-make-raw (prim-ref (lit str) (lit make)))

(def string-length (fn (_ s) (Str8 length s)))
(def substring (fn (_ s a b) (Str8 sub a (- b a) s)))
(def string=? (fn (_ a b) (str=? a b)))

(def %cvt (prim-ref (lit convert) (lit to)))
(def list->string (fn (_ l) (if (null? l) "" (%cvt l %string))))

(def string-append (fn (_ . ss) (string-concat ss)))
(def string-concat
  (fn (self ss)
    (if (null? ss)
      ""
      (if (null? (rest ss)) (first ss) (Str8 append (first ss) (self (rest ss)))))))

(def length (fn (_ l) (List length l)))
(def reverse (fn (_ l) (%cu-rev l ())))
(def %cu-rev
  (fn (self l acc)
    (if (null? l) acc (self (rest l) (pair (first l) acc)))))
(def append (fn (_ a b) (List append a b)))
(def map (fn (_ f l) (List map f l)))
(def filter (fn (_ p l) (List filter p l)))
(def set-first! %set-first!)

; the machine word ops sha256 rides; & | ^ << >> are engine prims
; (x/num/random.x is the precedent)
(def bit-and (fn (_ a b) (& a b)))
(def bit-or (fn (_ a b) (| a b)))
(def bit-xor (fn (_ a b) (^ a b)))
(def bit-shl (fn (_ a n) (<< a n)))
(def bit-shr (fn (_ a n) (>> a n)))

(def file-read-all (fn (_ path) (File read-all path)))
(def file-write-all (fn (_ path text) (File write-all path text)))
(def file-exists? (fn (_ path) (File exists? path)))
(def file-unlink (fn (_ path) (File unlink path)))
(def file-mkdir (fn (_ path) (File mkdir path)))
(def file-open-write
  (fn (_ path) (File open path (list (lit wronly) (lit creat) (lit trunc)))))
(def file-open-append
  (fn (_ path) (File open path (list (lit wronly) (lit creat) (lit append)))))
(def file-close (fn (_ fd) (File close fd)))
(def file-write
  (fn (_ fd s) (File write fd s (string-length s))))
(def file-read-fd
  (fn (_ fd n)
    (def buf (%str-make-raw n))
    (def r (File read fd buf n))
    (if (if (number? r) (> r 0) #f) (substring buf 0 r) "")))

(def file-list-dir (fn (_ path) (File list-dir path)))
(def file-rename (fn (_ a b) (File rename a b)))
(def file-rmdir (fn (_ path) (File rmdir path)))
; O_EXCL creation for mktemp: fails when the path exists
(def file-open-update
  (fn (_ path) (File open path (list (lit wronly) (lit creat)))))
(def file-open-excl
  (fn (_ path)
    (File open path (list (lit wronly) (lit creat) (lit excl)))))
(def file-dir?
  (fn (_ path)
    (if (file-exists? path)
      (let ((go (fn (self es)
                  (if (null? es) #f
                    (if (eq? (first (first es)) (lit kind))
                      (eq? (rest (first es)) (lit dir))
                      (self (rest es)))))))
        (go (File stat path)))
      #f)))

(def file-seek (fn (_ fd off) (File seek fd off)))
(def file-truncate (fn (_ fd n) (File truncate fd n)))
(def file-open-read (fn (_ path) (File open path (lit rdonly))))

; THE WIDE STAT.  File stat answers four fields (size mode kind mtime);
; stat(1), du(1) and id(1) want the rest of the struct, so this decodes
; the same buffer against the full per-OS layout.  Darwin is stat64
; (mode u16@4, uid@16, size@96); Linux x86_64 is stat (mode u32@24,
; uid@28, size@48) -- the two orders differ, so each gets its own spec
; and the alist is assembled by name.  Answers () when the path is gone.
(def %cu-stat-spec-darwin
  (list (list (lit dev) (lit u32)) (list (lit mode) (lit u16))
        (list (lit nlink) (lit u16)) (list (lit ino) (lit u64))
        (list (lit uid) (lit u32)) (list (lit gid) (lit u32))
        (list (lit rdev) (lit u32)) (list (lit pad) 4)
        (list (lit atime) (lit i64)) (list (lit pad) 8)
        (list (lit mtime) (lit i64)) (list (lit pad) 8)
        (list (lit ctime) (lit i64)) (list (lit pad) 8)
        (list (lit btime) (lit i64)) (list (lit pad) 8)
        (list (lit size) (lit i64)) (list (lit blocks) (lit i64))
        (list (lit blksize) (lit u32))))

(def %cu-stat-spec-linux
  (list (list (lit dev) (lit u64)) (list (lit ino) (lit u64))
        (list (lit nlink) (lit u64)) (list (lit mode) (lit u32))
        (list (lit uid) (lit u32)) (list (lit gid) (lit u32))
        (list (lit pad) 4) (list (lit rdev) (lit u64))
        (list (lit size) (lit i64)) (list (lit blksize) (lit i64))
        (list (lit blocks) (lit i64)) (list (lit atime) (lit i64))
        (list (lit pad) 8) (list (lit mtime) (lit i64)) (list (lit pad) 8)
        (list (lit ctime) (lit i64))))

(def %cu-mode-kind
  (fn (_ mode)
    (let ((fmt (& mode 61440)))
      (match
        ((= fmt 32768) (lit file))
        ((= fmt 16384) (lit dir))
        ((= fmt 40960) (lit link))
        ((= fmt 8192)  (lit char))
        ((= fmt 24576) (lit block))
        ((= fmt 4096)  (lit fifo))
        ((= fmt 49152) (lit socket))
        (#t (lit unknown))))))

(def file-stat-full
  (fn (_ path)
    (def buf (%str-make-raw 160))
    (def r (if os-darwin?
             (syscall (syscall-id (lit stat64)) path buf)
             (syscall (syscall-id (lit stat)) path buf)))
    (if (< r 0) ()
      (let ((d (Struct unpack
                 (if os-darwin? %cu-stat-spec-darwin %cu-stat-spec-linux)
                 buf)))
        (pair (pair (lit kind)
                (%cu-mode-kind (rest (Assoc entry (lit mode) d))))
          d)))))

(def vec-make (fn (_ n fill) (Vector make n fill)))
(def vec-ref (fn (_ v i) (Vector ref i v)))
(def vec-set! (fn (_ v i x) (Vector set! i x v)))

(def sys-getcwd (fn (_) (Sys getcwd)))
(def sys-environ (fn (_) (Sys environ)))
(def sys-getenv (fn (_ n) (Sys getenv n)))
(def sys-sleep (fn (_ n) (Sys sleep n)))

(def date-now-iso (fn (_) (Date ->iso (Date now))))
(def date-now-unix (fn (_) (Date to-unix (Date now))))
(def rng-make (fn (_ seed) (Random sw seed)))
(def rng-int (fn (_ r n) (r int n)))

(def proc-run (fn (_ argv) (Proc run! argv)))
(def sys-fork (fn (_) (Sys fork)))
(def sys-wait (fn (_ pid) (Sys wait pid)))
(def sys-exec (fn (_ name argv) (Sys exec name argv)))
(def sys-kill (fn (_ pid sig) (Sys kill pid sig)))
(def sys-signal (fn (_ sig how) (Sys signal sig how)))
(def sys-isatty (fn (_ fd) (Sys isatty fd)))
(def sys-usleep (fn (_ us) (Sys usleep us)))
(def cu-sigterm 15)
(def cu-sigkill 9)
(def cu-sigint 2)
(def cu-sighup 1)
(def cu-sig-ign 1)
(def sys-exit (fn (_ n) (Sys exit n)))
(def sys-dup2 (fn (_ a b) (Sys dup2 a b)))
(def sys-close (fn (_ fd) (Sys close fd)))

; stdin, read once from fd 3 (the platform's arrangement; see x-awk)
(def cu-stdin!
  (fn (_)
    (sys-dup2 3 0)
    (sys-close 3)
    (def slurp
      (fn (self acc)
        (let ((chunk (file-read-fd 0 65536)))
          (if (> (byte-len chunk) 0)
            (self (pair chunk acc))
            (string-concat (reverse acc))))))
    (slurp ())))

; --- NUL bytes ----------------------------------------------------------------
;
; A NUL is reachable, and only the length-computing helpers say otherwise:
; (File read fd buf n) fills a buffer with every byte and answers the true
; count, byte-at reads past as many NULs as there are, and (File write fd
; buf n) writes n bytes whatever they hold.  What truncates is anything
; that asks a C string its length -- byte-len, string-length, substring,
; list->string -- so file-write, file-read-all and cu-stdin! all stop at the
; first one.  The rule below: carry the buffer and its length, index it with
; byte-at, write with an explicit count.
;
; %str-make-raw answers a SPACE-filled buffer, so the zero bytes come from
; /dev/zero, read once and kept.

(def %cu-zeros-cell (list ()))

(def %cu-zeros
  (fn (_)
    (if (not (null? (first %cu-zeros-cell))) (first (first %cu-zeros-cell))
      (let ((fd (file-open-read "/dev/zero")))
        (def b (%str-make-raw 65536))
        (do (File read fd b 65536)
            (file-close fd)
            (set-first! %cu-zeros-cell (list b))
            b)))))

(def file-write-nuls
  (fn (_ fd n)
    (def go
      (fn (self left)
        (if (<= left 0) ()
          (let ((k (if (> left 65536) 65536 left)))
            (do (File write fd (%cu-zeros) k) (self (- left k)))))))
    (go n)))

; S then one DELIM byte, which is the -z and -0 output shape.  Both go
; through File write: display would reach fd 1 by another road, and the
; two orders are not guaranteed to agree.
(def file-write-field
  (fn (_ fd s delim)
    (do (File write fd s (string-length s))
        (if (= delim 0) (file-write-nuls fd 1)
          (File write fd (%cu-b->s delim) 1)))))

; FD's bytes as fields split on the byte DELIM, continuing a field left
; over from an earlier descriptor: answers (FIELDS . PARTIAL), so a
; caller reading several files sees one stream.  A field holds no DELIM
; by construction, so each is an ordinary string once cut -- substring
; would stop at a NUL, so a slice is built byte by byte.
(def %cu-fd-fields
  (fn (_ fd delim partial)
    (def buf (%str-make-raw 65536))
    (def slice
      (fn (_ from to)
        (let ((go (fn (self k acc)
                    (if (>= k to) (bytes->str (reverse acc))
                      (self (+ k 1) (pair (byte-at buf k) acc))))))
          (go from ()))))
    (def go
      (fn (self part acc)
        (let ((n (File read fd buf 65536)))
          (if (if (number? n) (> n 0) #f)
            (let ((scan
                    (fn (self2 i start p acc2)
                      (if (>= i n) (pair (string-append p (slice start i)) acc2)
                        (if (= (byte-at buf i) delim)
                          (self2 (+ i 1) (+ i 1) ""
                            (pair (string-append p (slice start i)) acc2))
                          (self2 (+ i 1) start p acc2))))))
              (let ((r (scan 0 0 part acc)))
                (self (first r) (rest r))))
            (pair (reverse acc) part)))))
    (go partial ())))

; stdin as fields, through the platform's fd 3 arrangement.  The applet
; protocol hands over one STRING, which a NUL would have cut short, so a
; -z applet reads its standard input here instead.
(def cu-stdin-fields!
  (fn (_ delim)
    (sys-dup2 3 0)
    (sys-close 3)
    ; A terminal is not a stream of NUL-separated items, and reading one
    ; waits for a writer that is not coming.  Nothing, rather.
    (if (sys-isatty 0) ()
      (let ((r (%cu-fd-fields 0 delim "")))
        (append (first r)
          (if (= (byte-len (rest r)) 0) () (list (rest r))))))))

; --- what a failed call says --------------------------------------------------
;
; A File call that fails raises the platform's io Err.  Its message is the
; operation and the errno's text, "chmod: Operation not permitted", and its data
; names the errno, (sym . eperm).  A tool prints the text after the path it was
; working on, so file-err-text answers it without the operation.

; THUNK's value, or the io Err it raised; any other raise goes on up
(def file-or-err
  (fn (_ thunk)
    (guard (e (if (eq? (Err tag e) (lit io)) e (error e)))
      (thunk))))

(def file-err-text
  (fn (_ e) (%cu-after-colon (e msg) 0)))

; the errno an io Err names, as a symbol: enoent, eacces
(def file-err-sym
  (fn (_ e) (Assoc get (lit sym) (e data))))

; the call an io Err came from, as a symbol: stat, open, read
(def file-err-op
  (fn (_ e) (Assoc get (lit op) (e data))))

; what follows the first ": " in M, or M when there is none
(def %cu-after-colon
  (fn (self m i)
    (match
      ((>= (+ i 1) (byte-len m)) m)
      ((if (= (byte-at m i) 58) (= (byte-at m (+ i 1)) 32) #f)
        (substring m (+ i 2) (byte-len m)))
      (#t (self m (+ i 1))))))

; --- the metadata doors (x-lang PR #607) --------------------------------------

(def file-stat (fn (_ path) (File stat path)))
(def file-chmod (fn (_ path mode) (File chmod path mode)))
(def file-chown (fn (_ path uid gid) (File chown path uid gid)))
(def file-link (fn (_ target path) (File link target path)))
(def file-symlink (fn (_ target path) (File symlink target path)))
(def file-readlink (fn (_ path) (File readlink path)))
(def file-utimes (fn (_ path) (File utimes path)))

; A path's access and modification times set to ATIME and MTIME, seconds since
; the epoch; the utimes syscall's result, negative on failure.  File utimes
; only ever sets the clock, so the pair of timevals is built here.  Both
; platforms lay a timeval out as 16 bytes with the seconds a little-endian i64
; at offset 0, so all 32 bytes are written, the microseconds and padding as
; zeros -- a raw string starts out filled with spaces, not zeros.
(def %cu-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %cu-ptr-set! (prim-ref (lit ptr) (lit set!)))
(def file-set-times
  (fn (_ path atime mtime)
    (def buf (%str-make-raw 32))
    (def at (%cu-str->ptr buf))
    (def zero
      (fn (self i) (if (< i 32) (do (%cu-ptr-set! at i 0 1) (self (+ i 1))) ())))
    ; A time before 1970 is negative, and its bytes are the complements of the
    ; bytes of -v-1 -- two's complement without a 64-bit bigint.
    (def put
      (fn (_ off v)
        (let ((neg? (< v 0)))
          (let ((go (fn (self i m)
                      (if (< i 8)
                        (let ((b (% m 256)))
                          (do (%cu-ptr-set! at (+ off i) (if neg? (- 255 b) b) 1)
                              (self (+ i 1) (/ (- m b) 256))))
                        ()))))
            (go 0 (if neg? (- (- 0 v) 1) v))))))
    (do (zero 0) (put 0 atime) (put 16 mtime)
        (syscall (syscall-id (lit utimes)) path buf))))

(def file-mkfifo (fn (_ path mode) (File mkfifo path mode)))
(def file-statfs (fn (_ path) (File statfs path)))

; the C string of at most N bytes at OFF in BUF -- a name a syscall wrote
(def %cu-cstr-at
  (fn (_ buf off n)
    (def go
      (fn (self i acc)
        (if (>= i (+ off n)) (bytes->str (reverse acc))
          (let ((b (byte-at buf i)))
            (if (= b 0) (bytes->str (reverse acc))
              (self (+ i 1) (pair b acc)))))))
    (go off ())))

; Linux names a filesystem by its magic; these are the ones stat
; spells, and a magic past them prints as stat prints it.  Unmeasured
; here: this host is Darwin, which carries the name in the struct.
(def %cu-fs-magic-names
  (list (pair 61267 "ext2/ext3") (pair 2435016766 "btrfs")
        (pair 1481003842 "xfs") (pair 16914836 "tmpfs")
        (pair 2035054128 "overlayfs") (pair 26985 "nfs")
        (pair 19780 "msdos") (pair 40864 "proc") (pair 1650812274 "sysfs")
        (pair 7377 "devpts") (pair 1936814952 "squashfs")
        (pair 801189825 "zfs") (pair 1397118030 "ntfs")
        (pair 2240043254 "ramfs") (pair 684539205 "cramfs")
        (pair 1684170528 "debugfs") (pair 2613483 "cgroupfs")
        (pair 1667723888 "cgroup2fs") (pair 2508478710 "hugetlbfs")
        (pair 1702057286 "fuseblk") (pair 38496 "iso9660")))

; The filesystem under PATH, past what (File statfs) decodes: its id,
; its type as a number and a name, and on Linux the name limit and the
; fundamental block size.  Darwin's struct has no name limit, so that
; key is absent and stat prints `?` for it, and its fundamental block
; size is the block size.  The id is the two fsid words as one number:
; on Darwin the first word high, as stat prints it here (measured); on
; Linux the second word high, as stat.c has it (unmeasured).
(def file-statfs-full
  (fn (_ path)
    (def buf (%str-make-raw 2304))
    (def r (if os-darwin?
             (syscall (syscall-id (lit statfs64)) path buf)
             (syscall (syscall-id (lit statfs)) path buf)))
    (if (< r 0) ()
      (let ((d (Struct unpack
                 (if os-darwin?
                   (list (list (lit bsize) (lit u32)) (list (lit pad) 4)
                         (list (lit blocks) (lit u64)) (list (lit bfree) (lit u64))
                         (list (lit bavail) (lit u64)) (list (lit files) (lit u64))
                         (list (lit ffree) (lit u64)) (list (lit fsid0) (lit u32))
                         (list (lit fsid1) (lit u32)) (list (lit pad) 4)
                         (list (lit type) (lit u32)))
                   (list (list (lit type) (lit i64)) (list (lit bsize) (lit i64))
                         (list (lit blocks) (lit u64)) (list (lit bfree) (lit u64))
                         (list (lit bavail) (lit u64)) (list (lit files) (lit u64))
                         (list (lit ffree) (lit u64)) (list (lit fsid0) (lit u32))
                         (list (lit fsid1) (lit u32)) (list (lit namelen) (lit i64))
                         (list (lit frsize) (lit i64))))
                 buf)))
        (def get (fn (_ k) (rest (Assoc entry k d))))
        (def hi (if os-darwin? (get (lit fsid0)) (get (lit fsid1))))
        (def lo (if os-darwin? (get (lit fsid1)) (get (lit fsid0))))
        (def typename
          (if os-darwin? (%cu-cstr-at buf 72 16)
            (let ((e (Assoc entry (get (lit type)) %cu-fs-magic-names)))
              (if (null? e)
                (string-concat (list "UNKNOWN (0x" (%cu-hexs (get (lit type))) ")"))
                (rest e)))))
        (append
          (list (pair (lit fsid) (+ (* hi 4294967296) lo))
                (pair (lit typename) typename)
                (pair (lit frsize)
                  (if os-darwin? (get (lit bsize)) (get (lit frsize)))))
          d)))))

; little-endian words at OFF in BUF, from the bytes
(def %cu-u32-at
  (fn (_ buf off)
    (+ (byte-at buf off)
       (+ (* 256 (byte-at buf (+ off 1)))
          (+ (* 65536 (byte-at buf (+ off 2)))
             (* 16777216 (byte-at buf (+ off 3))))))))

(def %cu-u64-at
  (fn (_ buf off)
    (+ (%cu-u32-at buf off) (* 4294967296 (%cu-u32-at buf (+ off 4))))))

; Darwin's getfsstat64 has no name in the platform's syscall table yet;
; 347 is its number, as statfs64's 345 is recorded there.
(def %cu-getfsstat64 347)

; a mount name from /proc/self/mounts, its \040-style octal escapes
; read back into bytes
(def %cu-mount-unescape
  (fn (_ s)
    (def end (byte-len s))
    (def oct? (fn (_ b) (if (>= b 48) (<= b 55) #f)))
    (def go
      (fn (self i acc)
        (if (>= i end) (bytes->str (reverse acc))
          (let ((b (byte-at s i)))
            (if (if (= b 92) (if (< (+ i 3) end)
                               (if (oct? (byte-at s (+ i 1)))
                                 (if (oct? (byte-at s (+ i 2))) (oct? (byte-at s (+ i 3))) #f)
                                 #f)
                               #f)
                  #f)
              (self (+ i 4)
                (pair (+ (* 64 (- (byte-at s (+ i 1)) 48))
                         (+ (* 8 (- (byte-at s (+ i 2)) 48))
                            (- (byte-at s (+ i 3)) 48)))
                  acc))
              (self (+ i 1) (pair b acc)))))))
    (go 0 ())))

; Every mounted filesystem, each an alist: what it is mounted FROM and
; ON, its type's name, and the fields file-statfs-full decodes.  Darwin
; answers getfsstat64 into one buffer of statfs64 records, 2168 bytes
; each, the names inside them; Linux lists /proc/self/mounts and asks
; statfs of each mount point.  The Linux half is unmeasured here.
(def file-mounts
  (fn (_)
    (if os-darwin?
      (let ((n (syscall %cu-getfsstat64 0 0 2)))              ; MNT_NOWAIT
        (def buf (%str-make-raw (* n 2168)))
        (def got (syscall %cu-getfsstat64 buf (* n 2168) 2))
        ; the words at their offsets, read byte by byte: a record sits
        ; kilobytes into the buffer, past what a pad should walk
        (def one
          (fn (_ i)
            (def at (* i 2168))
            (def u32 (fn (_ off) (%cu-u32-at buf (+ at off))))
            (def u64 (fn (_ off) (%cu-u64-at buf (+ at off))))
            (list (pair (lit from) (%cu-cstr-at buf (+ at 1112) 1024))
                  (pair (lit on) (%cu-cstr-at buf (+ at 88) 1024))
                  (pair (lit typename) (%cu-cstr-at buf (+ at 72) 16))
                  (pair (lit fsid) (+ (* (u32 48) 4294967296) (u32 52)))
                  (pair (lit frsize) (u32 0))
                  (pair (lit bsize) (u32 0))
                  (pair (lit blocks) (u64 8)) (pair (lit bfree) (u64 16))
                  (pair (lit bavail) (u64 24)) (pair (lit files) (u64 32))
                  (pair (lit ffree) (u64 40)) (pair (lit type) (u32 60)))))
        (def go
          (fn (self i acc)
            (if (>= i got) (reverse acc) (self (+ i 1) (pair (one i) acc)))))
        (if (< got 0) () (go 0 ())))
      (let ((text (guard (_ "") (file-read-all "/proc/self/mounts"))))
        (map (fn (_ ws)
               (let ((on (%cu-mount-unescape (%cu-nth 1 ws))))
                 (append
                   (list (pair (lit from) (%cu-mount-unescape (first ws)))
                         (pair (lit on) on)
                         (pair (lit typename) (%cu-nth 2 ws)))
                   (let ((fs (file-statfs-full on))) (if (null? fs) () fs)))))
          (filter (fn (_ ws) (>= (length ws) 3))
            (map (fn (_ l) (%cu-words-line l)) (%cu-lines text))))))))

; the kind a path has WITHOUT following it: the one question ln,
; readlink and realpath ask, and the one File stat cannot answer.  A
; DANGLING link still has a kind, so the absence is caught from lstat
; rather than pre-tested with exists? -- which follows the link, and
; would call a dangling one missing.
(def file-lstat-kind
  (fn (_ path)
    (guard (e (lit none))
      (let ((go (fn (self es)
                  (if (null? es) (lit unknown)
                    (if (eq? (first (first es)) (lit kind)) (rest (first es))
                      (self (rest es)))))))
        (go (File lstat path))))))

(def sys-getuid (fn (_) (Sys getuid)))
(def sys-geteuid (fn (_) (Sys geteuid)))
(def sys-getgid (fn (_) (Sys getgid)))
(def sys-getegid (fn (_) (Sys getegid)))
(def sys-getgroups (fn (_) (Sys getgroups)))
(def sys-uname (fn (_) (Sys uname)))
(def sys-cpu-count (fn (_) (Sys cpu-count)))
(def sys-sync (fn (_) (Sys sync)))
(def sys-fsync (fn (_ fd) (Sys fsync fd)))
(def sys-nice (fn (_ n) (Sys nice n)))
(def sys-chroot (fn (_ path) (Sys chroot path)))

; the wide stat WITHOUT following a link: ls -l shows a link as itself
(def file-lstat-full
  (fn (_ path)
    (def buf (%str-make-raw 160))
    (def r (if os-darwin?
             (syscall (syscall-id (lit lstat64)) path buf)
             (syscall (syscall-id (lit lstat)) path buf)))
    (if (< r 0) ()
      (let ((d (Struct unpack
                 (if os-darwin? %cu-stat-spec-darwin %cu-stat-spec-linux)
                 buf)))
        (pair (pair (lit kind)
                (%cu-mode-kind (rest (Assoc entry (lit mode) d))))
          d)))))

; Binary-safe copy: a 64K fd-level loop driven by raw byte counts, because a
; string's observable bytes end at its first NUL, so a read-all + write-all copy
; would truncate anything but text.
(def file-copy (fn (_ from to) (File copy from to)))

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

(provide cu/prims
  char->integer integer->char byte-at byte-len
  string-length substring string-append string-concat string=?
  list->string length reverse append map filter set-first!
  bit-and bit-or bit-xor bit-shl bit-shr
  file-read-all file-write-all file-exists? file-unlink file-mkdir
  file-open-write file-open-append file-close file-write file-read-fd
  file-list-dir file-rename file-rmdir file-open-excl file-dir?
  file-open-update
  file-seek file-truncate file-open-read file-stat-full
  vec-make vec-ref vec-set!
  proc-run sys-exit sys-dup2 sys-close
  sys-fork sys-wait sys-exec sys-kill sys-signal sys-isatty sys-usleep
  cu-sigterm cu-sighup cu-sig-ign
  sys-getcwd sys-environ sys-getenv sys-sleep
  date-now-iso date-now-unix rng-make rng-int
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
  (list (list (lit pad) 4) (list (lit mode) (lit u16))
        (list (lit nlink) (lit u16)) (list (lit ino) (lit u64))
        (list (lit uid) (lit u32)) (list (lit gid) (lit u32))
        (list (lit rdev) (lit u32)) (list (lit pad) 4)
        (list (lit atime) (lit i64)) (list (lit pad) 8)
        (list (lit mtime) (lit i64)) (list (lit pad) 8)
        (list (lit ctime) (lit i64)) (list (lit pad) 24)
        (list (lit size) (lit i64)) (list (lit blocks) (lit i64))
        (list (lit blksize) (lit u32))))

(def %cu-stat-spec-linux
  (list (list (lit pad) 8) (list (lit ino) (lit u64))
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
      (if (= fmt 32768) (lit file)
        (if (= fmt 16384) (lit dir)
          (if (= fmt 40960) (lit link)
            (if (= fmt 8192) (lit char)
              (if (= fmt 24576) (lit block)
                (if (= fmt 4096) (lit fifo)
                  (if (= fmt 49152) (lit socket) (lit unknown)))))))))))

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

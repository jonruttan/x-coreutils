; # x-coreutils -- the small tools, as applets
;
; ## cu/smemcap.x -- smemcap
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's smemcap (procps/smemcap.c): what smem reads of /proc, written to
; standard output as tar members -- meminfo and version, then for each process
; its directory and its smaps, cmdline and stat, in the order the directory
; lists them.  Each header's fields are the C library's %o, digits and a NUL
; with no padding, and the archive has no end blocks, as busybox writes it.  A
; file that will not open (a process gone between the listing and the read) is
; left out.  The /proc read is Host's proc-root, so a spec can point it at a
; tree of its own; a kernel with no /proc, Darwin's, ends the run as busybox's
; xchdir does.  Its arguments are not read.

(module cu/smemcap)

(import cu/dump dp-udigits)
(import cu/prims byte-at byte-len cu-ptr-set! cu-stat-get cu-str->ptr
  cu-sweep-lines cu-sweep-tick! file-close file-fstat-full file-list-dir
  file-open-read file-read-run file-write file-write-run filter host-proc-root
  libc-strerror map reverse string-concat sys-getcwd)
(import cu/tar tc-block tc-put! tc-write-header!)

; the header for NAME: MODE, UID, GID, SIZE and MTIME as sprintf's %o puts them
; into busybox's fields, each cut as its mask cuts it, and the flag TYPE
(def %smc-header!
  (fn (_ name mode uid gid size mtime type)
    (def h (tc-block))
    (def octal (fn (_ off len v) (tc-put! h off (dp-udigits v 8 #f) len)))
    (do (tc-put! h 0 name 100)
        (octal 100 8 (& mode 511))
        (octal 108 8 (& uid 2097151))
        (octal 116 8 (& gid 2097151))
        (octal 124 12 (& size 4294967295))
        (octal 136 12 (& mtime 8589934591))
        (cu-ptr-set! (cu-str->ptr h) 156 type 1)
        (tc-write-header! 1 h))))

; full_read's block from FD: reads until 512 bytes or one answers nothing, as
; (RUNS . COUNT), the runs last first
(def %smc-block
  (fn (_ fd)
    (let go ((runs ()) (n 0))
      (if (= n 512) (pair runs n)
        (let ((r (file-read-run fd (- 512 n))))
          (if (= (rest r) 0) (pair runs n) (go (pair r runs) (+ n (rest r)))))))))

; FD's blocks to the first short one, last first
(def %smc-blocks
  (fn (_ fd)
    (let go ((acc ()))
      (let ((b (%smc-block fd)))
        (if (= (rest b) 512) (go (pair b acc)) (if (= (rest b) 0) acc (pair b acc)))))))

; busybox's archivefile: PATH's header and its blocks, each padded to 512 with
; NULs; nothing where it does not open
(def %smc-file!
  (fn (_ path zeros)
    (let ((fd (file-open-read path)))
      (if (< fd 0) ()
        (let ((blocks (reverse (%smc-blocks fd))) (st (file-fstat-full fd)))
          (def get (fn (_ k) (if (null? st) 0 (cu-stat-get st k))))
          (do (file-close fd)
              (%smc-header! path (get (lit mode)) (get (lit uid)) (get (lit gid))
                (let sum ((bs blocks) (n 0)) (if (null? bs) n (sum (rest bs) (+ n (rest (first bs))))))
                (get (lit mtime)) #\0)
              (map (fn (_ b)
                     (do (map (fn (_ r) (file-write-run 1 r)) (reverse (first b)))
                         (if (< (rest b) 512) (file-write-run 1 (pair zeros (- 512 (rest b)))) ())))
                   blocks)
              (cu-sweep-tick! cu-sweep-lines)
              ()))))))

; a process's directory NAME, then its three files
(def %smc-process!
  (fn (_ name zeros)
    (do (%smc-header! name 365 0 0 0 0 #\5)
        (map (fn (_ f) (%smc-file! (string-concat (list name "/" f)) zeros))
             (list "smaps" "cmdline" "stat")))))

(def %smc-digit? (fn (_ s) (if (> (byte-len s) 0) (if (>= (byte-at s 0) #\0) (<= (byte-at s 0) #\9) #f) #f)))

(def cu-smemcap
  (fn (_ argv stdin-thunk)
    (def root (host-proc-root))
    (def home (sys-getcwd))
    (def r (Sys chdir root))
    (if (< r 0)
      (do (file-write 2 (string-concat (list "smemcap: can't change directory to '" root "': "
                                             (libc-strerror (Err errno-of r)) "\n")))
          1)
      (let ((zeros (tc-block)))
        (def run
          (fn (_)
            (do (%smc-file! "meminfo" zeros)
                (%smc-file! "version" zeros)
                (map (fn (_ name) (%smc-process! name zeros))
                     (filter %smc-digit? (reverse (file-list-dir "."))))
                0)))
        (let ((st (guard (e (do (Sys chdir home) (error e))) (run))))
          (do (Sys chdir home) st))))))

(provide cu/smemcap cu-smemcap)

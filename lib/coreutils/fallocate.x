; # x-coreutils -- the small tools, as applets
;
; ## lib/coreutils/fallocate.x -- fallocate: space set aside for a file
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; util-linux/fallocate.c: FILE, opened O_RDWR|O_CREAT and made 0666 under
; the umask, gets LEN bytes from OFS (0 unless -o) through posix_fallocate,
; so it is at least OFS+LEN long after.  -l is required and FILE is the one
; operand.  Both numbers are read as xatoull_sfx reads them, with
; kmg_i_suffixes.  Darwin's libc has no posix_fallocate: there the space is
; asked for with fcntl F_PREALLOCATE, past the file's end, and ftruncate
; sets the length.

(module coreutils/fallocate)

(import coreutils/cli cu-opts cu-usage)
(import coreutils/inet inet-set! inet-zeros)
(import coreutils/inetd in-call)
(import coreutils/prims cu-err-label cu-libc-sym cu-ptr-call
  cu-stat-get file-close file-err-text file-fstat-full file-open-err
  file-truncate file-write libc-strerror)
(import coreutils/xatonum cu-xatoull-kmg)

(def %fa-die
  (fn (_ msg)
    (do (file-write 2 (%str-concat (list "fallocate: " msg "\n")))
        (Err raise (lit fallocate) msg ()))))

; S as xatoull_sfx reads it, as off_t takes it; a word it refuses is said,
; as libbb says it, and the run ends
(def %fa-number
  (fn (_ s)
    (let ((n (cu-xatoull-kmg s)))
      (if (Err err? n) (%fa-die (Err text n)) n))))

; F_PREALLOCATE and its fstore_t, <sys/fcntl.h>: F_ALLOCATEALL from
; F_PEOFPOSMODE, then the length set.  A range posix_fallocate refuses is
; EINVAL, 22 on Darwin and Linux alike (x/type/err.x).
(def %fa-darwin
  (fn (_ fd ofs len)
    (def size (let ((st (file-fstat-full fd))) (if (null? st) 0 (cu-stat-get st (lit size)))))
    (def want (+ ofs len))
    (match
      ((if (< ofs 0) #t (if (<= len 0) #t (< want 0))) 22)
      ((<= want size) 0)
      (#t (let ((fst (inet-zeros 32)))
            (inet-set! fst 0 4 4)
            (inet-set! fst 4 3 4)
            (inet-set! fst 16 (- want size) 8)
            (def r (in-call ((syscall-door (lit fcntl)) fd 42 fst)))
            (if (< r 0) (Err errno-of r)
              (let ((t (in-call (file-truncate fd want))))
                (if (< t 0) (Err errno-of t) 0))))))))

; posix_fallocate's answer, which is the errno itself
(def %fa-allocate
  (fn (_ fd ofs len)
    (if os-darwin? (%fa-darwin fd ofs len)
      (in-call (cu-ptr-call (cu-libc-sym "posix_fallocate") fd ofs len)))))

(def %fa-run
  (fn (_ o path)
    (def ofs (let ((v (Opts value o "-o"))) (if (null? v) 0 (%fa-number v))))
    (def len (%fa-number (Opts value o "-l")))
    (def fd (File open path (list (lit rdwr) (lit creat)) 438))
    (when (< fd 0)
      (%fa-die (%str-concat (list "can't open '" path "': " (file-err-text (file-open-err fd path))))))
    (def e (%fa-allocate fd ofs len))
    (file-close fd)
    (if (= e 0) 0
      (%fa-die (%str-concat (list "fallocate '" path "': " (libc-strerror e)))))))

(def cu-fallocate
  (fn (_ argv stdin-thunk)
    (let ((o (cu-opts "fallocate" argv)))
      (def ops (Opts operands o))
      (if (if (null? (Opts value o "-l")) #t (if (null? ops) #t (not (null? (rest ops)))))
        (cu-usage "fallocate")
        (guard (e (if (eq? (cu-err-label e) (lit fallocate)) 1 (error e)))
          (%fa-run o (first ops)))))))

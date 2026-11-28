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
(import coreutils/prims byte-at byte-len cu-err-label cu-libc-sym cu-member-s? cu-ptr-call
  cu-stat-get cu-str->ptr file-close file-err-text file-fstat-full file-open-err
  file-truncate file-write libc-strerror substring)

(def %fa-die
  (fn (_ msg)
    (do (file-write 2 (%str-concat (list "fallocate: " msg "\n")))
        (Err raise (lit fallocate) msg ()))))

; the largest off_t; a count past it is negative to the call, as a C
; conversion makes it
(def %fa-off-max 0x7FFFFFFFFFFFFFFF)
(def %fa-div (fn (_ a b) (/ (- a (% a b)) b)))

; kmg_i_suffixes, libbb/xatonum.c
(def %fa-suffixes
  (list (pair (list "KiB" "kiB" "K" "k") 1024)
        (pair (list "MiB" "miB" "M" "m") 1048576)
        (pair (list "GiB" "giB" "G" "g") 1073741824)))

(def %fa-scale
  (fn (_ tail)
    (if (= (byte-len tail) 0) 1
      (let go ((ss %fa-suffixes))
        (match
          ((null? ss) ())
          ((cu-member-s? tail (first (first ss))) (rest (first ss)))
          (#t (go (rest ss))))))))

; digit string A against B of the same length: is A the greater?
(def %fa-above?
  (fn (_ a b)
    (let go ((i 0))
      (match
        ((>= i (byte-len a)) #f)
        ((= (byte-at a i) (byte-at b i)) (go (+ i 1)))
        (#t (> (byte-at a i) (byte-at b i)))))))

; S's digits without their leading zeros, past an off_t (lit big), or where
; strtoull would overflow nil
(def %fa-digits
  (fn (_ s end)
    (def from (let go ((i 0)) (if (if (< i (- end 1)) (= (byte-at s i) 48) #f) (go (+ i 1)) i)))
    (def d (substring s from end))
    (def n (byte-len d))
    (match
      ((> n 20) ())
      ((if (= n 20) (%fa-above? d "18446744073709551615") #f) ())
      ((if (= n 20) #t (if (= n 19) (%fa-above? d "9223372036854775807") #f)) (lit big))
      (#t (let go ((i 0) (acc 0))
            (if (< i n) (go (+ i 1) (+ (* acc 10) (- (byte-at d i) 48))) acc))))))

; S as xatoull_sfx reads it, as off_t takes it; a word it refuses is said,
; as libbb says it, and the run ends
(def %fa-number
  (fn (_ s)
    (def end
      (let go ((i 0))
        (if (if (< i (byte-len s)) (if (>= (byte-at s i) 48) (<= (byte-at s i) 57) #f) #f)
          (go (+ i 1)) i)))
    (def v (if (= end 0) () (%fa-digits s end)))
    (def scale (if (null? v) () (%fa-scale (substring s end (byte-len s)))))
    (def range (fn (_) (%fa-die (%str-concat (list "number " s " is not in 0..18446744073709551615 range")))))
    (match
      ((null? scale) (%fa-die (%str-concat (list "invalid number '" s "'"))))
      ((= scale 1) (if (eq? v (lit big)) -1 v))
      ((eq? v (lit big)) (range))
      ((> v (+ (* 2 (%fa-div %fa-off-max scale)) 1)) (range))
      ((> v (%fa-div %fa-off-max scale)) -1)
      (#t (* v scale)))))

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

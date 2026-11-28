; # x-coreutils -- the small tools, as applets
;
; ## lib/coreutils/fstrim.x -- fstrim: a file system's unused blocks discarded
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; util-linux/fstrim.c: MOUNTPOINT, opened O_RDONLY|O_NONBLOCK, is given
; the FITRIM ioctl over a struct fstrim_range of three u64s -- start (-o),
; len (-l, all of it unless given) and minlen (-m), each read as
; xatoull_sfx reads it.  The kernel writes the bytes it discarded back into
; len, which -v prints.  Darwin has no FITRIM; there the call answers
; ENOTTY, the errno a file system without discard gives on Linux.

(module coreutils/fstrim)

(import coreutils/cli cu-opts cu-usage)
(import coreutils/inet inet-set! inet-zeros)
(import coreutils/inetd in-call)
(import coreutils/prims cu-err-label cu-ptr-ref cu-str->ptr file-close file-err-text
  file-open-err file-write libc-strerror string-append)
(import coreutils/xatonum cu-ull->str cu-xatoull-kmg)

(def %ft-die
  (fn (_ msg)
    (do (file-write 2 (%str-concat (list "fstrim: " msg "\n")))
        (Err raise (lit fstrim) msg ()))))

; _IOWR('X', 121, struct fstrim_range), <linux/fs.h>
(def %ft-fitrim 0xC0185879)
; ENOTTY, 25 on Darwin and Linux alike (x/type/err.x)
(def %ft-enotty 25)

; the option's value under its letter or its long name, read as
; xatoull_sfx reads it, or DEFAULT where neither is given
(def %ft-number
  (fn (_ o short long default)
    (def s (let ((v (Opts value o long))) (if (null? v) (Opts value o short) v)))
    (if (null? s) default
      (let ((n (cu-xatoull-kmg s)))
        (if (Err err? n) (%ft-die (Err text n)) n)))))

; FITRIM on FD over RANGE: 0, or the errno it failed with
(def %ft-trim
  (fn (_ fd range)
    (if os-darwin? %ft-enotty
      (let ((r (in-call ((syscall-door (lit ioctl)) fd %ft-fitrim range))))
        (if (< r 0) (Err errno-of r) 0)))))

(def %ft-run
  (fn (_ o mp)
    (def range (inet-zeros 24))
    (inet-set! range 0 (%ft-number o "-o" "--offset" 0) 8)
    (inet-set! range 8 (%ft-number o "-l" "--length" -1) 8)
    (inet-set! range 16 (%ft-number o "-m" "--minimum" 0) 8)
    (def fd (File open mp (list (lit rdonly) (lit nonblock))))
    (when (< fd 0)
      (%ft-die (%str-concat (list "can't open '" mp "': " (file-err-text (file-open-err fd mp))))))
    (def e (%ft-trim fd range))
    (file-close fd)
    (when (not (= e 0)) (%ft-die (string-append "FITRIM: " (libc-strerror e))))
    (when (if (Opts on? o "-v") #t (Opts on? o "--verbose"))
      (file-write 1 (%str-concat (list mp ": " (cu-ull->str (cu-ptr-ref (cu-str->ptr range) 8 8))
                                       " bytes trimmed\n"))))
    0))

(def cu-fstrim
  (fn (_ argv stdin-thunk)
    (let ((o (cu-opts "fstrim" argv)))
      (def ops (Opts operands o))
      (if (if (null? ops) #t (not (null? (rest ops))))
        (cu-usage "fstrim")
        (guard (e (if (eq? (cu-err-label e) (lit fstrim)) 1 (error e)))
          (%ft-run o (first ops)))))))

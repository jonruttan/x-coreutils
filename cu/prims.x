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

(provide cu/prims
  char->integer integer->char byte-at byte-len
  string-length substring string-append string-concat string=?
  list->string length reverse append map filter set-first!
  bit-and bit-or bit-xor bit-shl bit-shr
  file-read-all file-write-all file-exists? file-unlink file-mkdir
  file-open-write file-open-append file-close file-write file-read-fd
  proc-run sys-exit sys-dup2 sys-close
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

(def proc-run (fn (_ argv) (Proc run! argv)))
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

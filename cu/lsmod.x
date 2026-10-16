; # x-coreutils -- the small tools, as applets
;
; ## cu/lsmod.x -- lsmod: the kernel's loaded modules, from /proc/modules
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's lsmod (modutils/lsmod.c), its 2.6 table: a header and whether the
; kernel is tainted, from /proc/sys/kernel/tainted, then each module's name,
; size, use count and users, the last without its trailing comma.

; a line's first four words, split at spaces and tabs
(def %lm-words
  (fn (_ line)
    (def end (byte-len line))
    (def sep? (fn (_ c) (if (= c #\space) #t (= c #\tab))))
    (let go ((i 0) (start -1) (acc ()))
      (match
        ((= (length acc) 4) (reverse acc))
        ((>= i end) (reverse (if (< start 0) acc (pair (substring line start end) acc))))
        ((sep? (byte-at line i)) (go (+ i 1) -1 (if (< start 0) acc (pair (substring line start i) acc))))
        ((< start 0) (go (+ i 1) i acc))
        (#t (go (+ i 1) start acc))))))

; check_tainted: the line after the header
(def %lm-taint
  (fn (_)
    (let ((t (guard (_ 0) (let ((s (file-read-unsized "/proc/sys/kernel/tainted"))) (%lm-atoi s)))))
      (if (= t 0) "    Not tainted\n"
        (string-concat (list "    Tainted: " (if (= (& t 1) 0) "G" "P") (if (= (& t 2) 0) " " "F")
                             (if (= (& t 4) 0) " " "S") "\n"))))))

; atoi: the leading decimal digits of S, 0 where there are none
(def %lm-atoi
  (fn (_ s)
    (let go ((i 0) (n 0))
      (if (if (< i (byte-len s)) (if (>= (byte-at s i) #\0) (<= (byte-at s i) #\9) #f) #f)
        (go (+ i 1) (+ (* n 10) (- (char->integer (byte-at s i)) 48)))
        n))))

(def %cu-lsmod
  (fn (_ argv stdin-thunk)
    (let ((text (file-or-err (fn (_) (file-read-unsized "/proc/modules")))))
      (do (file-write 1 (string-append (%cu-pad-right "Module" 24) "Size  Used by" (%lm-taint)))
          (unless (Err err? text)
            (map (fn (_ line)
                   (let ((w (%lm-words line)))
                     (when (= (length w) 4)
                       (let ((users (List ref 3 w)))
                         (file-write 1 (string-concat
                                         (list (%cu-pad-right (first w) 19) " "
                                               (%cu-pad-left (List ref 1 w) 8) " "
                                               (%cu-pad-left (List ref 2 w) 2) " "
                                               (if (= (byte-len users) 0) users (substring users 0 (- (byte-len users) 1)))
                                               "\n")))))))
                 (%cu-lines text)))
          0))))

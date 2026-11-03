; # x-coreutils -- the small tools, as applets
;
; ## cu/signal.x -- signal names and numbers, and the -SIGNAL word before the options
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; kill, pkill and fuser read a signal the way busybox's get_signum does: a
; number, a name with or without SIG, RTMIN+n and RTMAX-n.

(module cu/signal)

(import cu/prims append byte-at byte-len cu-libc-sym cu-ptr-call gz-word-bytes
  hx-strtoul length reverse set-first! string=? substring sys-signals)

(def %pg-alnum?
  (fn (_ c)
    (match
      ((if (>= c #\0) (<= c #\9) #f) #t)
      ((if (>= c #\A) (<= c #\Z) #f) #t)
      (#t (if (>= c #\a) (<= c #\z) #f)))))

; the number of the kernel's signal NAME, or nil
(def %pg-named
  (fn (_ name)
    (let ((hit (List find (fn (_ e) (str=? (first e) name)) (sys-signals))))
      (if (null? hit) () (rest hit)))))

; libc's real-time signals, (MIN . MAX), or nil where libc has none (Darwin).
; glibc and musl both answer them by function, as SIGRTMIN and SIGRTMAX do.
(def %pg-rt-cell (list ()))

; busybox's bb_strtou and bb_strtoi, base 10, from I of S (bb_strtonum.c):
; (N . END), END where the digits stop.  N is nil where busybox answers
; ERANGE: no digit to read (a - first only where LO is below 0), a digit or
; letter straight after the digits, or outside LO..HI.  Digits that stop at
; anything else are busybox's EINVAL, the value kept; the caller reads END.
(def pg-strto
  (fn (_ s i lo hi)
    (def len (byte-len s))
    (def neg (if (< lo 0) (if (< i len) (= (byte-at s i) #\-) #f) #f))
    (def j (if neg (+ i 1) i))
    (def r (hx-strtoul s j 10 (if neg (- 0 lo) hi)))
    (def k (rest r))
    (match
      ((= k j) (pair () k))
      ((if (< k len) (%pg-alnum? (byte-at s k)) #f) (pair () k))
      ((null? (first r)) (pair () k))
      (#t (pair (if neg (- 0 (first r)) (first r)) k)))))

; NSIG, one past the last signal: past RTMAX where there is one, else past
; the kernel's named signals -- 65 on Linux, 32 on Darwin
(def pg-nsig
  (fn (_)
    (let ((rt (pg-rt)))
      (if (null? rt) (+ (length (sys-signals)) 1) (+ (rest rt) 1)))))

(def pg-rt
  (fn (_)
    (do (if (null? (first %pg-rt-cell))
          (let ((lo (cu-libc-sym "__libc_current_sigrtmin"))
                (hi (cu-libc-sym "__libc_current_sigrtmax")))
            (set-first! %pg-rt-cell
              (list (if (if (null? lo) #t (null? hi)) ()
                      (pair (Sys %sign-fold (cu-ptr-call lo))
                            (Sys %sign-fold (cu-ptr-call hi)))))))
          ())
        (first (first %pg-rt-cell)))))

; the signal ARGV's first word names as -SIGNAL, or nil; the parse (cu/cli.x)
; sets that word aside for pkill
(def pg-signal-word
  (fn (_ argv signal?)
    (if (if (null? argv) #f (if (> (byte-len (first argv)) 1) (= (byte-at (first argv) 0) #\-) #f))
      (pg-signum (substring (first argv) 1 (byte-len (first argv)))) ())))

; busybox's get_signum: a number below NSIG, as bb_strtou reads it (digits a
; blank or a comma ends are read); or a name in any case, with or without SIG
; -- EXIT is 0, IO is POLL where the kernel calls it that (Linux), IOT is
; ABRT; or RTMIN, RTMIN+N, RTMAX, RTMAX-N inside libc's range.  nil for none.
(def pg-signum
  (fn (_ s)
    (def n (first (pg-strto s 0 0 4294967295)))
    (def up (Str8 upcase s))
    (def bare (if (Str8 starts? "SIG" up) (substring up 3 (byte-len up)) up))
    (def rt (pg-rt))
    ; RTMIN+N and RTMAX-N: N no further from the end than the range is long
    (def rt-off
      (fn (_ sign)
        (if (if (> (byte-len bare) 5) (= (byte-at bare 5) sign) #f)
          (let ((i (first (pg-strto bare 6 0 4294967295))))
            (if (if (null? i) #f (<= i (- (rest rt) (first rt)))) i ()))
          ())))
    (match
      ((if (null? n) #f (< n (pg-nsig))) n)
      ((str=? bare "EXIT") 0)
      ((not (null? (%pg-named bare))) (%pg-named bare))
      ((str=? bare "IO") (%pg-named "POLL"))
      ((str=? bare "IOT") (%pg-named "ABRT"))
      ((null? rt) ())
      ((str=? bare "RTMIN") (first rt))
      ((str=? bare "RTMAX") (rest rt))
      ((Str8 starts? "RTMIN" bare) (let ((i (rt-off #\+))) (if (null? i) () (+ (first rt) i))))
      ((Str8 starts? "RTMAX" bare) (let ((i (rt-off #\-))) (if (null? i) () (- (rest rt) i))))
      (#t ()))))

; ARGV as (SIGNAL FAMILIES REST): the 4s and 6s of every cluster before a --
; taken out, in order, as getopt would read -4 and -6 anywhere, and where
; SIGNAL? says so the first -SIGNAL word, as fuser reads it.  VALUED are the
; letters that take a value: the rest of a cluster after one is its value,
; and the word after one that ends a cluster.
(def fu-args
  (fn (_ argv signal? valued)
    (def digit? (fn (_ c) (if (= c #\4) #t (= c #\6))))
    (def valued? (fn (_ c) (List any? (fn (_ v) (= v c)) valued)))
    ; WORD's bytes past the dash as (KEPT DIGITS NEXT?) when it is a cluster:
    ; the bytes it keeps, its 4s and 6s before any valued letter, and whether
    ; the word after it is a value; nil when it is no cluster
    (def cluster
      (fn (_ w)
        (def bs (if (> (byte-len w) 1) (if (= (byte-at w 0) #\-) (rest (gz-word-bytes w)) ()) ()))
        (if (if (null? bs) #t (= (first bs) #\-)) ()
          (let go ((cs bs) (kept ()) (digs ()))
            (match ((null? cs) (list (reverse kept) (reverse digs) #f))
                   ((valued? (first cs)) (list (append (reverse kept) cs) (reverse digs) (null? (rest cs))))
                   ((digit? (first cs)) (go (rest cs) kept (pair (first cs) digs)))
                   (#t (go (rest cs) (pair (first cs) kept) digs)))))))
    (def go
      (fn (self ws sig fams acc)
        (if (null? ws) (list sig fams (reverse acc))
          (let ((w (first ws)) (c (cluster (first ws))))
            (match
              ((str=? w "--") (list sig fams (append (reverse acc) ws)))
              ((if (null? c) #f (not (null? (List ref 1 c))))
                (let ((acc (if (null? (first c)) acc (pair (bytes->str (pair #\- (first c))) acc))))
                  (if (if (List ref 2 c) (pair? (rest ws)) #f)
                    (self (rest (rest ws)) sig (append fams (List ref 1 c)) (pair (first (rest ws)) acc))
                    (self (rest ws) sig (append fams (List ref 1 c)) acc))))
              ((if (null? c) #f (if (List ref 2 c) (pair? (rest ws)) #f))
                (self (rest (rest ws)) sig fams (pair (first (rest ws)) (pair w acc))))
              ((if signal? (if (null? sig) (not (null? (pg-signal-word ws))) #f) #f)
                (self (rest ws) (pg-signal-word ws) fams acc))
              (#t (self (rest ws) sig fams (pair w acc))))))))
    (go argv () () ())))

(def ts-signal-number
  (fn (_ name)
    (let ((e (List find (fn (_ e) (string=? (first e) name)) (sys-signals)))) (if (null? e) () (rest e)))))

(provide cu/signal fu-args pg-nsig pg-rt pg-signal-word pg-signum pg-strto
  ts-signal-number)

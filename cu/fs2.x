; # x-coreutils -- the small tools, as applets
;
; ## cu/fs2.x -- the busybox expansion, filesystem half
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; touch ls pwd mv rmdir install mktemp cmp.

; touch: create when missing; an existing file rewrites its own bytes
; -- content-identical, mtime bumped (there is no utime door; the
; rewrite is the honest stand-in, recorded divergence: ctime moves too)
; touch: utimes(2) on a path that exists, an empty file when it does
; not.  It used to REWRITE the bytes to bump the stamp -- the door
; x-lang PR #607 opened retires that, and with it the risk of a large
; file being read and written just to be dated.
(def %cu-touch
  (fn (_ argv stdin-thunk)
    (def c? (%cu-has-flag? argv "-c"))
    (def ops (filter (fn (_ x) (not (%cu-option-token? x))) argv))
    (def go
      (fn (self os)
        (if (null? os) 0
          (do (if (file-exists? (first os))
                (file-utimes (first os))
                (if c? () (file-write-all (first os) "")))
              (self (rest os))))))
    (if (null? ops)
      (do (file-write 2 "touch: missing operand\n") 1)
      (go ops))))

(def %cu-ls-one
  (fn (_ path all?)
    (if (file-dir? path)
      (%cu-print-lines
        (%cu-msort
          (filter (fn (_ n)
                    (if all? #t
                      (if (> (byte-len n) 0)
                        (not (= (byte-at n 0) 46))
                        #f)))
            (filter (fn (_ n)
                      (if (string=? n ".") #f
                        (not (string=? n ".."))))
              (file-list-dir path)))
          (fn (_ a b) (%cu-str< a b))))
      (display (string-append path "\n")))))

(def %cu-ls
  (fn (_ argv stdin-thunk)
    (def all? (if (pair? argv) (string=? (first argv) "-a") #f))
    (def ops0 (if all? (rest argv) argv))
    (def ops (if (null? ops0) (list ".") ops0))
    (if (null? (rest ops))
      (do (%cu-ls-one (first ops) all?) 0)
      ; several operands: the dir: header form, blank line between
      (let ((go (fn (self os first?)
                  (if (null? os) 0
                    (do (if first? () (display "\n"))
                        (display (string-append (first os) ":\n"))
                        (%cu-ls-one (first os) all?)
                        (self (rest os) #f))))))
        (go ops #t)))))

(def %cu-pwd
  (fn (_ argv stdin-thunk)
    (do (display (string-append (sys-getcwd) "\n")) 0)))

; mv: rename, with copy+unlink as the cross-device fallback
(def %cu-mv
  (fn (_ argv stdin-thunk)
    (if (if (pair? argv) (pair? (rest argv)) #f)
      (let ((r (file-rename (first argv) (first (rest argv)))))
        (if (if (number? r) (< r 0) #f)
          (do (file-write-all (first (rest argv))
                (file-read-all (first argv)))
              (file-unlink (first argv))
              0)
          0))
      (do (file-write 2 "mv: usage: mv SRC DST\n") 1))))

(def %cu-rmdir
  (fn (_ argv stdin-thunk)
    (def go
      (fn (self os st)
        (if (null? os) st
          (let ((r (file-rmdir (first os))))
            (if (if (number? r) (< r 0) #f)
              (do (file-write 2
                    (string-append "rmdir: failed: "
                      (string-append (first os) "\n")))
                  (self (rest os) 1))
              (self (rest os) st))))))
    (go argv 0)))

; install: -d makes directories (parents included); the copy form
; accepts and IGNORES -c and -m MODE -- there is no chmod door yet,
; the recorded divergence
; the mode -m carries, or nil when the flag is absent
(def %cu-install-mode
  (fn (self as)
    (if (null? as) ()
      (if (string=? (first as) "-m")
        (if (null? (rest as)) () (%cu-octal->int (first (rest as))))
        (self (rest as))))))

(def %cu-install
  (fn (_ argv stdin-thunk)
    (if (if (pair? argv) (string=? (first argv) "-d") #f)
      (let ((go (fn (self os)
                  (if (null? os) 0
                    (do (%cu-mkdir-p! (first os)) (self (rest os)))))))
        (go (rest argv)))
      ; -m used to be accepted and IGNORED; File chmod now honours it
      (let ((mode (%cu-install-mode argv)))
        (def strip (fn (self as)
                     (if (null? as) ()
                       (if (string=? (first as) "-c")
                         (self (rest as))
                         (if (string=? (first as) "-m")
                           (self (rest (rest as)))
                           as)))))
        (let ((ops (strip argv)))
          (if (if (pair? ops) (pair? (rest ops)) #f)
            (let ((dst (first (rest ops))))
              ; DST may be a directory: install SRC DIR
              (def target
                (if (file-dir? dst)
                  (string-append dst
                    (string-append "/" (%cu-base-of (first ops))))
                  dst))
              (do (file-write-all target (file-read-all (first ops)))
                  (if (null? mode) () (file-chmod target mode))
                  0))
            (do (file-write 2 "install: usage: install [-c] [-m M] SRC DST | -d DIR...\n")
                1)))))))

(def %cu-base-of
  (fn (_ p)
    (def slash
      (let ((go (fn (self i last)
                  (if (>= i (byte-len p)) last
                    (self (+ i 1) (if (= (byte-at p i) 47) i last))))))
        (go 0 (- 0 1))))
    (if (< slash 0) p (substring p (+ slash 1) (byte-len p)))))

; shared with mkdir -p
(def %cu-mkdir-p!
  (fn (_ path)
    (def end (byte-len path))
    (def go
      (fn (self i)
        (if (>= i end)
          (if (file-exists? path) () (file-mkdir path))
          (if (if (= (byte-at path i) 47) (> i 0) #f)
            (do (let ((pre (substring path 0 i)))
                  (if (file-exists? pre) () (file-mkdir pre)))
                (self (+ i 1)))
            (self (+ i 1))))))
    (go 0)))

; mktemp: TEMPLATE with trailing Xs (default /tmp/tmp.XXXXXX), O_EXCL
; loop, alnum from the PRNG seeded by the clock
(def %cu-mktemp
  (fn (_ argv stdin-thunk)
    (def template
      (if (null? argv) "/tmp/tmp.XXXXXX" (first argv)))
    (def end (byte-len template))
    (def xs
      (let ((go (fn (self i)
                  (if (<= i 0) 0
                    (if (= (byte-at template (- i 1)) 88)   ; X
                      (+ 1 (self (- i 1)))
                      0)))))
        (go end)))
    (if (= xs 0)
      (do (file-write 2 "mktemp: template needs trailing Xs\n") 1)
      (let ((stem (substring template 0 (- end xs))))
        (def rng (rng-make (date-now-unix)))
        (def alnum
          (fn (_ k)
            (if (< k 10) (+ 48 k)
              (if (< k 36) (+ 87 (- k 10)) (+ 29 k)))))
        (def try
          (fn (self n)
            (if (= n 0)
              (do (file-write 2 "mktemp: exhausted attempts\n") 1)
              (let ((suffix
                      (let ((go (fn (self2 k acc)
                                  (if (= k 0) (list->string acc)
                                    (self2 (- k 1)
                                      (pair (integer->char
                                              (alnum (rng-int rng 62)))
                                        acc))))))
                        (go xs ()))))
                (def path (string-append stem suffix))
                (def fd (file-open-excl path))
                (if (if (number? fd) (>= fd 0) #f)
                  (do (file-close fd)
                      (display (string-append path "\n"))
                      0)
                  (self (- n 1)))))))
        (try 16)))))

; cmp: first differing byte, 1-based, with its line; -s is silent
(def %cu-cmp
  (fn (_ argv stdin-thunk)
    (def s? (if (pair? argv) (string=? (first argv) "-s") #f))
    (def ops (if s? (rest argv) argv))
    (def a (if (string=? (first ops) "-") (stdin-thunk)
             (file-read-all (first ops))))
    (def b (if (string=? (first (rest ops)) "-") (stdin-thunk)
             (file-read-all (first (rest ops)))))
    (def la (byte-len a))
    (def lb (byte-len b))
    (def go
      (fn (self i line)
        (if (if (>= i la) (>= i lb) #f)
          0
          (if (if (>= i la) #t (>= i lb))
            (do (if s? ()
                  (file-write 2
                    (string-append "cmp: EOF on "
                      (string-append
                        (if (>= i la) (first ops) (first (rest ops)))
                        "\n"))))
                1)
            (if (= (byte-at a i) (byte-at b i))
              (self (+ i 1)
                (if (= (byte-at a i) 10) (+ line 1) line))
              (do (if s? ()
                    (display
                      (string-append (first ops)
                        (string-append " "
                          (string-append (first (rest ops))
                            (string-append " differ: char "
                              (string-append (%cu-int->str (+ i 1))
                                (string-append ", line "
                                  (string-append (%cu-int->str line)
                                    "\n")))))))))
                  1))))))
    (go 0 1)))

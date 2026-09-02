; # x-coreutils -- the small tools, as applets
;
; ## cu/cli.x -- the applet table and the command line
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;   x -l coreutils -- APPLET [args]...
;
; cu-run is the pure-ish core the specs drive: (cu-run ARGV INPUT) with
; INPUT standing for stdin.  cu-main reads the real stdin lazily and
; caches it, so an applet that never asks never blocks.

(def %cu-applets
  (list
    (pair "cat" %cu-cat)
    (pair "sort" %cu-sort)
    (pair "uniq" %cu-uniq)
    (pair "head" %cu-head)
    (pair "tail" %cu-tail)
    (pair "wc" %cu-wc)
    (pair "comm" %cu-comm)
    (pair "join" %cu-join)
    (pair "tr" %cu-tr)
    (pair "cut" %cu-cut)
    (pair "basename" %cu-basename)
    (pair "dirname" %cu-dirname)
    (pair "cp" %cu-cp)
    (pair "rm" %cu-rm)
    (pair "mkdir" %cu-mkdir)
    (pair "sha256sum" %cu-sha256sum)
    (pair "echo" %cu-echo)
    (pair "printf" %cu-printf)
    (pair "true" %cu-true)
    (pair "false" %cu-false)
    (pair "seq" %cu-seq)
    (pair "rev" %cu-rev-applet)
    (pair "tac" %cu-tac)
    (pair "nl" %cu-nl)
    (pair "fold" %cu-fold)
    (pair "paste" %cu-paste)
    (pair "tee" %cu-tee)
    (pair "touch" %cu-touch)
    (pair "ls" %cu-ls)
    (pair "pwd" %cu-pwd)
    (pair "mv" %cu-mv)
    (pair "rmdir" %cu-rmdir)
    (pair "install" %cu-install)
    (pair "mktemp" %cu-mktemp)
    (pair "cmp" %cu-cmp)
    (pair "diff" %cu-diff)
    (pair "env" %cu-env)
    (pair "printenv" %cu-printenv)
    (pair "sleep" %cu-sleep)
    (pair "date" %cu-date)
    (pair "which" %cu-which)
    (pair "xargs" %cu-xargs)
    (pair "test" %cu-test)
    (pair "[" %cu-bracket)))

(def %cu-find-applet
  (fn (_ name)
    (def go
      (fn (self es)
        (if (null? es) ()
          (if (string=? (first (first es)) name)
            (rest (first es))
            (self (rest es))))))
    (go %cu-applets)))

; THE OPTION GUARD.  An applet only reads the flags it implements; a
; flag it does not know must REFUSE, never fall through as a file
; operand (`ls -l` once printed "-l").  The leading option tokens of
; argv are checked against the applet's table before it runs: a token
; is known when it matches exactly, when its two-character head is a
; known flag carrying an attached argument (-d, -f1 -n5), or when it
; is a cluster of known single-character flags (-rn).  Scanning stops
; at the first operand, at `--`, and never touches `-` or a negative
; number.  An applet absent from the table takes no options.
(def %cu-known-flags
  (list
    (pair "sort" (list "-r" "-n" "-u"))
    (pair "uniq" (list "-c"))
    (pair "head" (list "-n"))
    (pair "tail" (list "-n"))
    (pair "wc" (list "-l" "-w" "-c"))
    (pair "comm" (list "-1" "-2" "-3"))
    (pair "tr" (list "-d" "-s"))
    (pair "cut" (list "-d" "-f" "-c"))
    (pair "rm" (list "-r" "-f"))
    (pair "mkdir" (list "-p"))
    (pair "echo" (list "-n" "-e"))
    (pair "fold" (list "-w"))
    (pair "paste" (list "-d"))
    (pair "tee" (list "-a"))
    (pair "ls" (list "-a"))
    (pair "install" (list "-d" "-c" "-m"))
    (pair "cmp" (list "-s"))
    (pair "xargs" (list "-n"))
    (pair "test" (list "-e" "-f" "-d" "-s" "-z" "-n"
                   "-eq" "-ne" "-lt" "-le" "-gt" "-ge"))
    (pair "[" (list "-e" "-f" "-d" "-s" "-z" "-n"
                "-eq" "-ne" "-lt" "-le" "-gt" "-ge"))))

(def %cu-flags-of
  (fn (_ applet)
    (def go (fn (self es)
              (if (null? es) ()
                (if (string=? (first (first es)) applet) (rest (first es))
                  (self (rest es))))))
    (go %cu-known-flags)))

(def %cu-option-token?
  (fn (_ s)
    (if (< (byte-len s) 2) #f
      (if (not (= (byte-at s 0) 45)) #f              ; -
        (let ((c (byte-at s 1)))
          (if (if (>= c 48) (<= c 57) #f) #f          ; -N: a number
            #t))))))

(def %cu-flag-known?
  (fn (_ tok flags)
    (def exact? (fn (self fs)
                  (if (null? fs) #f
                    (if (string=? (first fs) tok) #t (self (rest fs))))))
    (def head2 (substring tok 0 2))
    (def single? (fn (self fs ch)
                   (if (null? fs) #f
                     (if (if (= (byte-len (first fs)) 2)
                           (= (byte-at (first fs) 1) ch) #f)
                       #t (self (rest fs) ch)))))
    (def cluster? (fn (self i)
                    (if (>= i (byte-len tok)) #t
                      (if (single? flags (byte-at tok i))
                        (self (+ i 1)) #f))))
    (if (exact? flags) #t
      (let ((known-head (let ((go (fn (self2 fs)
                                    (if (null? fs) #f
                                      (if (string=? (first fs) head2) #t
                                        (self2 (rest fs)))))))
                          (go flags))))
        (if known-head #t (cluster? 1))))))

; answers () when argv's options are all known, else the offender
(def %cu-unknown-option
  (fn (_ applet argv)
    (def flags (%cu-flags-of applet))
    (def go (fn (self as)
              (if (null? as) ()
                (let ((t (first as)))
                  (if (string=? t "--") ()
                    (if (not (%cu-option-token? t)) ()
                      (if (%cu-flag-known? t flags) (self (rest as)) t)))))))
    (go argv)))

(def %cu-refuse-option
  (fn (_ applet tok)
    (do (file-write 2
          (string-append applet
            (string-append ": unknown option "
              (string-append tok "\n"))))
        2)))

(def cu-run
  (fn (_ argv input)
    (if (null? argv)
      (do (file-write 2 "usage: coreutils APPLET [args]...\n") 2)
      (let ((h (%cu-find-applet (first argv))))
        (if (null? h)
          (do (file-write 2
                (string-append "coreutils: no such applet: "
                  (string-append (first argv) "\n")))
              2)
          (let ((bad (%cu-unknown-option (first argv) (rest argv))))
            (if (null? bad)
              (h (rest argv) (fn (_) input))
              (%cu-refuse-option (first argv) bad))))))))

(def %cu-cli-engine-flag?
  (fn (_ s)
    (if (string=? s "--quiet") #t
      (if (string=? s "--batch") #t
        (if (string=? s "--no-color") #t (string=? s "--verbose"))))))

(def cu-argv
  (fn (_ raw)
    (def ops
      (filter (fn (_ a) (not (%cu-cli-engine-flag? a)))
        (if (pair? raw) (rest raw) ())))
    (if (if (pair? ops) (string=? (first ops) "--") #f)
      (rest ops)
      ops)))

(def cu-main
  (fn (_ raw-args)
    (def argv (cu-argv raw-args))
    (def cache (list ()))
    (def stdin-thunk
      (fn (_)
        (if (null? (first cache))
          (do (set-first! cache (list (cu-stdin!)))
              (first (first cache)))
          (first (first cache)))))
    (if (null? argv)
      (sys-exit (cu-run argv ""))
      (let ((h (%cu-find-applet (first argv))))
        (if (null? h)
          (sys-exit (cu-run argv ""))
          (let ((bad (%cu-unknown-option (first argv) (rest argv))))
            (if (null? bad)
              (sys-exit (h (rest argv) stdin-thunk))
              (sys-exit (%cu-refuse-option (first argv) bad)))))))))

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
    (pair "md5sum" %cu-md5sum)
    (pair "sha1sum" %cu-sha1sum)
    (pair "sha512sum" %cu-sha512sum)
    (pair "cksum" %cu-cksum)
    (pair "sum" %cu-sum)
    (pair "yes" %cu-yes)
    (pair "factor" %cu-factor)
    (pair "expand" %cu-expand)
    (pair "unexpand" %cu-unexpand)
    (pair "dos2unix" %cu-dos2unix)
    (pair "unix2dos" %cu-unix2dos)
    (pair "split" %cu-split)
    (pair "shuf" %cu-shuf)
    (pair "base64" %cu-base64)
    (pair "stat" %cu-stat)
    (pair "du" %cu-du)
    (pair "dd" %cu-dd)
    (pair "truncate" %cu-truncate)
    (pair "unlink" %cu-unlink)
    (pair "shred" %cu-shred)
    (pair "timeout" %cu-timeout)
    (pair "usleep" %cu-usleep)
    (pair "tty" %cu-tty)
    (pair "nohup" %cu-nohup)
    (pair "[[" %cu-dbracket)
    (pair "od" %cu-od)
    (pair "uuencode" %cu-uuencode)
    (pair "uudecode" %cu-uudecode)
    (pair "expr" %cu-expr)
    (pair "chmod" %cu-chmod)
    (pair "chown" %cu-chown)
    (pair "chgrp" %cu-chgrp)
    (pair "ln" %cu-ln)
    (pair "link" %cu-link)
    (pair "readlink" %cu-readlink)
    (pair "realpath" %cu-realpath)
    (pair "mkfifo" %cu-mkfifo)
    (pair "df" %cu-df)
    (pair "sync" %cu-sync)
    (pair "id" %cu-id)
    (pair "whoami" %cu-whoami)
    (pair "logname" %cu-logname)
    (pair "groups" %cu-groups)
    (pair "uname" %cu-uname)
    (pair "arch" %cu-arch)
    (pair "nproc" %cu-nproc)
    (pair "nice" %cu-nice)
    (pair "chroot" %cu-chroot)
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

; THE OPTION DECLARATION.  One row per applet: the flags that stand
; alone, the flags that take an argument, and -- for an applet whose
; operands can themselves look like flags -- the word `leading`, which
; stops the parse at the first operand so that `echo hi -n` prints
; `hi -n` and `timeout 5 prog -x` leaves -x to prog.
;
; THE GUARD AND THE APPLET READ THE SAME ROW.  They used to disagree:
; the guard admitted `-sm`, `-k2` and `-r` while the applets behind it
; compared whole tokens, knew only the separated spelling, and in one
; case ignored the flag entirely -- three defects, each a flag accepted
; and then not read.  Both sides now go through %cu-opts, so an
; accepted-but-unread flag is not a bug to find, it is unspellable.
;
; An applet absent from this table takes no options at all.
; test's whole vocabulary -- the guard needs to know every dash-word
; the grammar accepts, or it would refuse an operator as an option.
(def %cu-test-operators
  (list "-e" "-f" "-d" "-s" "-z" "-n" "-r" "-w" "-x" "-L" "-h"
        "-b" "-c" "-p" "-S" "-k" "-u" "-g" "-t"
        "-eq" "-ne" "-lt" "-le" "-gt" "-ge" "-nt" "-ot" "-ef"
        "-a" "-o" "=" "==" "!=" "!" "(" ")"))

(def %cu-option-spec
  (list
    (pair "sort" (list (list "-n" "-r" "-u" "-g" "-M" "-c" "-s" "-b" "-d" "-f" "-i")
                       (list "-o" "-k" "-t")))
    (pair "uniq" (list (list "-c" "-d" "-u" "-i") (list "-f" "-s" "-w")))
    (pair "nl" (list () (list "-b" "-n" "-s" "-w" "-v" "-i")))
    (pair "head" (list (list "-q" "-v") (list "-n" "-c")))
    (pair "tail" (list (list "-q" "-v") (list "-n" "-c")))
    (pair "wc" (list (list "-l" "-w" "-c") ()))
    ; -a and -d are HONOURED no-ops here; cu/diff.x says why each is one.
    ; The three not declared -- -r -N -S -- are the directory walk.
    (pair "diff" (list (list "-i" "-b" "-w" "-B" "-q" "-s" "-a" "-d"
                         "-T" "-t")
                       (list "-U" "-L")))
    ; the checksum family shares one driver, so it shares one option set
    (pair "md5sum" (list (list "-c" "-s" "-w") ()))
    (pair "sha1sum" (list (list "-c" "-s" "-w") ()))
    (pair "sha256sum" (list (list "-c" "-s" "-w") ()))
    (pair "sha512sum" (list (list "-c" "-s" "-w") ()))
    (pair "comm" (list (list "-1" "-2" "-3") ()))
    (pair "tr" (list (list "-d" "-s") ()))
    (pair "cut" (list () (list "-d" "-f" "-c")))
    (pair "cat" (list (list "-n" "-b" "-v" "-t" "-e" "-A") ()))
    (pair "cp" (list (list "-a" "-r" "-R" "-P" "-L" "-H" "-p" "-f" "-i" "-l" "-s" "-T" "-u") ()))
    (pair "mv" (list (list "-f" "-i" "-n" "-T") ()))
    (pair "rm" (list (list "-i" "-r" "-R" "-f" "-v") ()))
    (pair "mkdir" (list (list "-p") (list "-m")))
    (pair "rmdir" (list (list "-p") ()))
    (pair "ln" (list (list "-s" "-f" "-n" "-b" "-v") (list "-t")))
    (pair "echo" (list (list "-n" "-e") () (lit leading)))
    (pair "fold" (list () (list "-w")))
    (pair "paste" (list () (list "-d")))
    (pair "tee" (list (list "-a") ()))
    (pair "ls" (list (list "-1" "-A" "-a" "-d" "-L" "-H" "-R" "-F" "-p" "-l"
                       "-i" "-n" "-s" "-h" "-r" "-S" "-X" "-v" "-c" "-t" "-u") ()))
    (pair "touch" (list (list "-c") (list "-r" "-d" "-t")))
    (pair "install" (list (list "-d" "-c" "-D" "-p") (list "-m" "-o" "-g" "-t")))
    (pair "cmp" (list (list "-s") ()))
    (pair "sum" (list (list "-s" "-r") ()))
    (pair "expand" (list () (list "-t")))
    (pair "unexpand" (list (list "-a") (list "-t")))
    (pair "split" (list () (list "-b" "-l")))
    (pair "shuf" (list (list "-e") (list "-n")))
    (pair "base64" (list (list "-d") ()))
    (pair "stat" (list (list "-L") (list "-c")))
    (pair "du" (list (list "-s" "-a" "-k" "-c" "-h" "-m" "-x" "-l" "-H" "-L") (list "-d")))
    (pair "truncate" (list () (list "-s")))
    (pair "od" (list (list "-v" "-c" "-b" "-x" "-d" "-o") (list "-A" "-t" "-N")))
    (pair "uuencode" (list (list "-m") ()))
    (pair "chmod" (list (list "-R" "-c" "-v" "-f") ()))
    (pair "chown" (list (list "-R" "-h" "-L" "-H" "-P" "-c" "-v" "-f") ()))
    (pair "chgrp" (list (list "-R" "-h" "-L" "-H" "-P" "-c" "-v" "-f") ()))
    (pair "readlink" (list (list "-f" "-e") ()))
    (pair "mkfifo" (list () (list "-m")))
    (pair "mktemp" (list (list "-d" "-t" "-q" "-u") (list "-p")))
    (pair "df" (list (list "-h" "-k" "-P" "-m" "-i") (list "-B")))
    (pair "id" (list (list "-u" "-g" "-G" "-n") ()))
    (pair "uname" (list (list "-a" "-s" "-n" "-r" "-v" "-m" "-p" "-i" "-o") ()))
    (pair "nice" (list () (list "-n") (lit leading)))
    (pair "shred" (list (list "-u") (list "-n")))
    (pair "timeout" (list () (list "-s") (lit leading)))
    ; -0 and -p are NOT here on purpose; cu/sys2.x says why
    (pair "xargs" (list (list "-r" "-t" "-x")
                        (list "-n" "-a" "-E" "-I" "-s") (lit leading)))
    ; test and its spellings are an EXPRESSION, not an option list:
    ; the operators are declared so the guard knows them, and the
    ; applet parses the expression itself.
    (pair "test" (list %cu-test-operators () (lit leading)))
    (pair "[" (list %cu-test-operators () (lit leading)))
    (pair "[[" (list %cu-test-operators () (lit leading)))))

(def %cu-spec-of
  (fn (_ applet)
    (def go (fn (self es)
              (if (null? es) ()
                (if (string=? (first (first es)) applet) (rest (first es))
                  (self (rest es))))))
    (go %cu-option-spec)))

; THE ONE PARSE.  Every applet and the guard reach their options
; through this, so both read the row that was declared for the applet.
(def %cu-opts
  (fn (_ applet argv)
    (def spec (%cu-spec-of applet))
    (def flags (if (null? spec) () (first spec)))
    (def values (if (null? spec) () (first (rest spec))))
    (def mode (if (null? spec) ()
                (if (null? (rest (rest spec))) () (first (rest (rest spec))))))
    (if (eq? mode (lit leading))
      (Opts parse-leading flags values argv)
      (Opts parse flags values argv))))

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
          (let ((bad (Opts unknown (%cu-opts (first argv) (rest argv)))))
            (if (null? bad)
              (h (rest argv) (fn (_) input))
              (%cu-refuse-option (first argv) bad))))))))

(def %cu-cli-engine-flag?
  (fn (_ s)
    (match
      ((string=? s "--quiet")    #t)
      ((string=? s "--batch")    #t)
      ((string=? s "--no-color") #t)
      (#t (string=? s "--verbose")))))

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
          (let ((bad (Opts unknown (%cu-opts (first argv) (rest argv)))))
            (if (null? bad)
              (sys-exit (h (rest argv) stdin-thunk))
              (sys-exit (%cu-refuse-option (first argv) bad)))))))))

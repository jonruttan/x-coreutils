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
    ; %cu-find is the applet; %cu-find-applet below is the table lookup.
    (pair "find" %cu-find)
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

; The option declaration. One row per applet: the flags that stand alone, the
; flags that take an argument, and -- for an applet whose operands can look like
; flags -- the word `leading`, which stops the parse at the first operand so
; `echo hi -n` prints `hi -n` and `timeout 5 prog -x` leaves -x to prog.
;
; The guard and the applet read the same row (both through %cu-opts), so a flag
; that is accepted but never read is unspellable rather than a bug to find. An
; applet absent from this table takes no options; test's whole vocabulary is
; here because the guard must know every dash-word the grammar accepts.
(def %cu-test-operators
  (list "-e" "-f" "-d" "-s" "-z" "-n" "-r" "-w" "-x" "-L" "-h"
        "-b" "-c" "-p" "-S" "-k" "-u" "-g" "-t"
        "-eq" "-ne" "-lt" "-le" "-gt" "-ge" "-nt" "-ot" "-ef"
        "-a" "-o" "=" "==" "!=" "!" "(" ")"))

; find's vocabulary is here for the same reason test's is: the guard has to
; know every dash-word the grammar accepts, or a valid expression reads as a
; bad flag.  cu/find.x parses them; this list only makes them spellable.
(def %cu-find-primaries
  (list "-name" "-iname" "-path" "-type" "-size" "-newer"
        "-maxdepth" "-mindepth" "-empty" "-print" "-print0" "-exec"
        "-true" "-false" "-not" "-a" "-and" "-o" "-or" "!" "(" ")"))

(def %cu-option-spec
  (list
    (pair "sort" (list (list "-n" "-r" "-u" "-g" "-M" "-c" "-s" "-b" "-d" "-f" "-i"
                         "-z")
                       (list "-o" "-k" "-t")))
    (pair "uniq" (list (list "-c" "-d" "-u" "-i") (list "-f" "-s" "-w")))
    (pair "nl" (list () (list "-b" "-n" "-s" "-w" "-v" "-i")))
    (pair "head" (list (list "-q" "-v") (list "-n" "-c")))
    (pair "tail" (list (list "-q" "-v" "-f") (list "-n" "-c" "-s")))
    (pair "wc" (list (list "-l" "-w" "-c" "-m" "-L") ()))
    (pair "env" (list (list "-i" "-0") (list "-u")))
    (pair "sync" (list (list "-d" "-f") ()))
    (pair "dos2unix" (list (list "-u" "-d") ()))
    (pair "unix2dos" (list (list "-u" "-d") ()))
    ; -s is NOT declared; cu/date.x says why.  -I's SPEC is attached and
    ; optional, which Opts has no way to say, so the five spellings are
    ; declared outright -- the declaration then lists exactly what is
    ; accepted, which is the point of having one.
    (pair "date" (list (list "-u" "-R" "-I" "-Idate" "-Ihours"
                         "-Iminutes" "-Iseconds" "-Ins")
                       (list "-d" "-D" "-r")))
    ; -a and -d are HONOURED no-ops here; cu/diff.x says why each is one.
    (pair "diff" (list (list "-i" "-b" "-w" "-B" "-q" "-s" "-a" "-d"
                         "-T" "-t" "-r" "-N")
                       (list "-U" "-L" "-S")))
    ; the checksum family shares one driver, so it shares one option set
    (pair "md5sum" (list (list "-c" "-s" "-w") ()))
    (pair "sha1sum" (list (list "-c" "-s" "-w") ()))
    (pair "sha256sum" (list (list "-c" "-s" "-w") ()))
    (pair "sha512sum" (list (list "-c" "-s" "-w") ()))
    (pair "comm" (list (list "-1" "-2" "-3") ()))
    (pair "tr" (list (list "-d" "-s" "-c") ()))
    (pair "cut" (list (list "-s" "-n") (list "-d" "-f" "-c" "-b")))
    ; join is not a busybox applet, so the matrix has no row for it; the
    ; declaration is still what the applet reads through.
    (pair "join" (list () (list "-t")))
    (pair "cat" (list (list "-n" "-b" "-v" "-t" "-e" "-A") ()))
    (pair "cp" (list (list "-a" "-r" "-R" "-P" "-L" "-H" "-p" "-f" "-i" "-l" "-s" "-T" "-u") ()))
    (pair "mv" (list (list "-f" "-i" "-n" "-T") ()))
    (pair "rm" (list (list "-i" "-r" "-R" "-f" "-v") ()))
    (pair "mkdir" (list (list "-p") (list "-m")))
    (pair "rmdir" (list (list "-p") ()))
    (pair "ln" (list (list "-s" "-f" "-n" "-b" "-v") (list "-t")))
    (pair "echo" (list (list "-n" "-e" "-E") () (lit leading)))
    (pair "basename" (list () (list "-s")))
    (pair "fold" (list (list "-b" "-s") (list "-w")))
    (pair "paste" (list (list "-s") (list "-d")))
    (pair "seq" (list (list "-w") (list "-s")))
    (pair "tee" (list (list "-a" "-i") ()))
    (pair "ls" (list (list "-1" "-A" "-a" "-d" "-L" "-H" "-R" "-F" "-p" "-l"
                       "-i" "-n" "-s" "-h" "-r" "-S" "-X" "-v" "-c" "-t" "-u"
                       "-C" "-x")
                     (list "-w")))
    (pair "touch" (list (list "-c") (list "-r" "-d" "-t")))
    (pair "install" (list (list "-d" "-c" "-D" "-p") (list "-m" "-o" "-g" "-t")))
    (pair "cmp" (list (list "-s" "-l") (list "-n")))
    (pair "sum" (list (list "-s" "-r") ()))
    (pair "expand" (list (list "-i") (list "-t")))
    (pair "unexpand" (list (list "-a" "-f") (list "-t")))
    (pair "split" (list () (list "-b" "-l" "-a")))
    (pair "shuf" (list (list "-e" "-z") (list "-n" "-i" "-o")))
    (pair "base64" (list (list "-d") (list "-w")))
    (pair "stat" (list (list "-L" "-f" "-t") (list "-c")))
    (pair "du" (list (list "-s" "-a" "-k" "-c" "-h" "-m" "-x" "-l" "-H" "-L") (list "-d")))
    (pair "truncate" (list (list "-c") (list "-s")))
    (pair "od" (list (list "-v" "-c" "-b" "-x" "-d" "-o") (list "-A" "-t" "-N" "-j")))
    (pair "uuencode" (list (list "-m") ()))
    (pair "chmod" (list (list "-R" "-c" "-v" "-f") ()))
    (pair "chown" (list (list "-R" "-h" "-L" "-H" "-P" "-c" "-v" "-f") ()))
    (pair "chgrp" (list (list "-R" "-h" "-L" "-H" "-P" "-c" "-v" "-f") ()))
    (pair "readlink" (list (list "-f" "-e" "-n" "-v") ()))
    (pair "mkfifo" (list () (list "-m")))
    (pair "mktemp" (list (list "-d" "-t" "-q" "-u") (list "-p")))
    (pair "df" (list (list "-h" "-k" "-P" "-m" "-i" "-T" "-a") (list "-B")))
    (pair "id" (list (list "-u" "-g" "-G" "-n" "-r") ()))
    (pair "uname" (list (list "-a" "-s" "-n" "-r" "-v" "-m" "-p" "-i" "-o") ()))
    (pair "nice" (list () (list "-n") (lit leading)))
    (pair "shred" (list (list "-u" "-f" "-z") (list "-n")))
    (pair "timeout" (list () (list "-s" "-k") (lit leading)))
    (pair "tty" (list (list "-s") ()))
    (pair "pwd" (list (list "-L" "-P") ()))
    (pair "which" (list (list "-a") ()))
    (pair "nproc" (list (list "--all") (list "--ignore")))
    (pair "uudecode" (list () (list "-o")))
    ; -p is NOT here on purpose; cu/sys2.x says why
    (pair "xargs" (list (list "-r" "-t" "-x" "-0")
                        (list "-n" "-a" "-E" "-I" "-s") (lit leading)))
    ; test and its spellings are an EXPRESSION, not an option list:
    ; the operators are declared so the guard knows them, and the
    ; applet parses the expression itself.
    (pair "test" (list %cu-test-operators () (lit leading)))
    (pair "[" (list %cu-test-operators () (lit leading)))
    (pair "[[" (list %cu-test-operators () (lit leading)))
    ; find is the same shape: the paths come first and the grammar after
    ; them, so the parse stops at the first operand and the applet reads
    ; what is left.
    (pair "find" (list %cu-find-primaries () (lit leading)))))

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

; Of FLAGS, the one given last, or nil: for flags where a later one overrides an
; earlier, as chmod's -v overrides -c.  The parse lists the flags it saw in the
; order given, except that it reverses the letters of one cluster, so -cv reads
; as -vc.
(def %cu-last-given
  (fn (_ o flags)
    (%cu-last-given-in (Assoc get (lit on) o) flags ())))

(def %cu-last-given-in
  (fn (self on flags found)
    (if (null? on) found
      (self (rest on) flags
        (if (%cu-member-s? (first on) flags) (first on) found)))))

; Of the value-taking FLAGS, the one given last, or nil: head's -n and -c, where
; the later one says what is counted.  The parse keeps each value with its flag,
; in the order given.
(def %cu-last-valued
  (fn (_ o flags)
    (%cu-last-given-in (map (fn (_ v) (first v)) (Assoc get (lit values) o))
      flags ())))

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

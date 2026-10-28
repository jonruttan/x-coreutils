; # x-coreutils -- the small tools, as applets
;
; ## cu/nsenter.x -- nsenter: a program run in other processes' namespaces
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's nsenter (util-linux/nsenter.c).  Each namespace asked for is
; opened from the FILE given with its option, or else from -t's process,
; /proc/PID/ns/NAME, and all of them first, then entered through setns in
; busybox's order -- user, ipc, uts, net, pid, mount -- so a user namespace
; entered first can let the rest be.  -r and -w open their directories the
; same way, /proc/PID/root and /proc/PID/cwd, and are changed to after.  A
; pid namespace holds only the children made after it is entered, so with
; -p, unless -F, this process forks and waits, and the child goes on.  A
; user namespace sets the uid and gid, -S's and -G's or 0, unless
; --preserve-credentials.  Last PROG, or a login shell, $SHELL or /bin/sh,
; takes the process over.  Darwin has no namespaces: no /proc to open, and
; setns answers Function not implemented.

(module cu/nsenter)

(import cu/cli cu-usage)
(import cu/getopt cu-getopt-long)
(import cu/inetd in-call in-exec)
(import cu/perm cu-basename-of)
(import cu/prims cu-err-label cu-int->str cu-libc-sym cu-ptr-call cu-ptr-ref
  cu-stdin-to-command! cu-str->ptr file-err-sym file-err-text file-open-or-err
  file-open-read file-write libc-strerror str-make-raw string-append
  string-concat sys-close sys-exec-or-err sys-exit sys-fork sys-getenv
  sys-getpid sys-kill sys-signal)
(import cu/strings cu-range-number)

(def %nse-die
  (fn (_ msg)
    (do (file-write 2 (string-concat (list "nsenter: " msg "\n")))
        (Err raise (lit nsenter) msg ()))))

; the usage text, and the run's end
(def %nse-usage
  (fn (_) (do (cu-usage "nsenter") (Err raise (lit nsenter) "usage" ()))))

; the namespaces, in the order they are entered: (LETTER NAME CLONE-FLAG)
(def %nse-spaces
  (list (list "U" "user" 268435456) (list "i" "ipc" 134217728)
        (list "u" "uts" 67108864) (list "n" "net" 1073741824)
        (list "p" "pid" 536870912) (list "m" "mnt" 131072)))

(def %nse-optstr "+U::i::u::n::p::m::t:S:G:r::w::F")

(def %nse-longs
  (list (list "user" 2 "U") (list "ipc" 2 "i") (list "uts" 2 "u") (list "net" 2 "n")
        (list "pid" 2 "p") (list "mount" 2 "m") (list "target" 1 "t") (list "setuid" 1 "S")
        (list "setgid" 1 "G") (list "root" 2 "r") (list "wd" 2 "w") (list "no-fork" 0 "F")
        (list "preserve-credentials" 0 "preserve-credentials")))

; the options as getopt32 leaves them: KEY to (KEY . VALUE), a later one in
; place of an earlier; -t, -S and -G numbers, read as each comes
(def %nse-options
  (fn (self taken acc)
    (if (null? taken) acc
      (let ((k (first (first taken))) (v (rest (first taken))))
        (self (rest taken)
          (pair (pair k (if (if (string=? k "t") #t (if (string=? k "S") #t (string=? k "G")))
                          (let ((n (cu-range-number "nsenter" v 0 2147483647)))
                            (if (null? n) (Err raise (lit nsenter) "number" ()) n))
                          v))
                (List filter (fn (_ e) (not (string=? (first e) k))) acc)))))))

(def %nse-given? (fn (_ os k) (pair? (List find (fn (_ e) (string=? (first e) k)) os))))

(def %nse-value
  (fn (_ os k)
    (let ((e (List find (fn (_ e) (string=? (first e) k)) os))) (if (null? e) () (rest e)))))

; open_by_path_or_target: PATH opened, or /proc/PID/FILE, the usage where
; there is neither
(def %nse-open
  (fn (_ path pid file)
    (def p (match ((not (null? path)) path)
                  ((= pid 0) (%nse-usage))
                  (#t (string-concat (list "/proc/" (cu-int->str pid) "/" file)))))
    (let ((fd (file-open-or-err file-open-read p)))
      (if (Err err? fd) (%nse-die (string-concat (list "can't open '" p "': " (file-err-text fd)))) fd))))

; libc's NAME called by CALL with its address: nil, or why it failed
(def %nse-libc
  (fn (_ name call)
    (let ((door (cu-libc-sym name)))
      (if (null? door) "Function not implemented"
        (let ((r (in-call (call door))))
          (if (< r 0) (libc-strerror (Err errno-of r)) ()))))))

(def %nse-or-die
  (fn (_ why what) (unless (null? why) (%nse-die (string-concat (list what ": " why))))))

(def %nse-zero (fn (_ v) (if (null? v) 0 v)))

(def %nse-setgroups
  (fn (_) (%nse-libc "setgroups" (fn (_ door) (cu-ptr-call door 0 0)))))

(def %nse-fchdir
  (fn (_ fd)
    (do (%nse-or-die (%nse-libc "fchdir" (fn (_ door) (cu-ptr-call door fd))) "fchdir")
        (sys-close fd))))

; xvfork_parent_waits_and_exits, the parent's side: KID waited for, and its
; end made this process's own, its exit status or the signal that killed it
(def %nse-wait-and-exit
  (fn (self kid)
    (def st (str-make-raw 4))
    (def r (in-call (cu-ptr-call (cu-libc-sym "waitpid") kid (cu-str->ptr st) 0)))
    (when (< r 0)
      (if (= (Err errno-of r) 4) (self kid) (%nse-die (string-append "waitpid: " (libc-strerror (Err errno-of r))))))
    (def raw (cu-ptr-ref (cu-str->ptr st) 0 4))
    (def sig (% raw 128))
    (when (> sig 0)
      (do (sys-signal sig 0) (sys-kill (sys-getpid) sig)))
    (sys-exit (if (> sig 0) (+ 128 sig) (% (>> raw 8) 256)))))

; a login shell, $SHELL or /bin/sh, its name behind a dash, as exec_login_shell
; runs one
(def %nse-shell
  (fn (_)
    (def sh (let ((s (sys-getenv "SHELL"))) (if (if (null? s) #t (string=? s "")) "/bin/sh" s)))
    (def name (cu-basename-of sh))
    (cu-stdin-to-command!)
    (def r (in-exec sh (list (string-append "-" name))))
    (%nse-die (string-concat (list "can't execute '" sh "': " (libc-strerror (Err errno-of r)))))))

; PROG run in place of this process, as BB_EXECVP_or_die runs it
(def %nse-exec
  (fn (_ prog)
    (cu-stdin-to-command!)
    (def err (sys-exec-or-err (first prog) (rest prog)))
    (file-write 2 (string-concat (list "nsenter: can't execute '" (first prog) "': " (file-err-text err) "\n")))
    (sys-exit (if (eq? (file-err-sym err) (lit enoent)) 127 126))))

(def %nse-run
  (fn (_ os prog)
    (def pid (let ((t (%nse-value os "t"))) (if (null? t) 0 t)))
    (def root (if (%nse-given? os "r") (%nse-open (%nse-value os "r") pid "root") -1))
    (def wd (if (%nse-given? os "w") (%nse-open (%nse-value os "w") pid "cwd") -1))
    ; each namespace's fd, -1 where not asked for: (FD . NS)
    (def fds
      (map (fn (_ ns)
             (pair (if (%nse-given? os (first ns))
                     (%nse-open (%nse-value os (first ns)) pid (string-append "ns/" (List ref 1 ns))) -1)
                   ns))
           %nse-spaces))
    ; a user namespace means -S and -G, and its groups gone: setgroups is
    ; asked before setns and after, and only the second refusal ends the run
    (def creds (if (%nse-given? os "U") (not (%nse-given? os "preserve-credentials")) #f))
    (def groups-failed (if creds (not (null? (%nse-setgroups))) #f))
    (map (fn (_ p)
           (let ((fd (first p)) (ns (rest p)))
             (when (>= fd 0)
               (do (%nse-or-die (%nse-libc "setns" (fn (_ door) (cu-ptr-call door fd (List ref 2 ns))))
                     (string-concat (list "setns(): can't reassociate to namespace '" (List ref 1 ns) "'")))
                   (sys-close fd)))))
         fds)
    (def wd2 (if (if (>= root 0) (< wd 0) #f) (%nse-open "." 0 ".") wd))
    (when (>= root 0)
      (do (%nse-fchdir root)
          (%nse-or-die (%nse-libc "chroot" (fn (_ door) (cu-ptr-call door ".")))
            "can't change root directory to '.'")))
    (when (>= wd2 0) (%nse-fchdir wd2))
    (when (if (%nse-given? os "p") (not (%nse-given? os "F")) #f)
      (let ((kid (sys-fork)))
        (when (> kid 0) (%nse-wait-and-exit kid))))
    (when (if creds #t (%nse-given? os "G"))
      (do (let ((why (%nse-setgroups))) (when groups-failed (%nse-or-die why "setgroups")))
          (%nse-or-die (%nse-libc "setgid" (fn (_ door) (cu-ptr-call door (%nse-zero (%nse-value os "G"))))) "setgid")))
    (when (if creds #t (%nse-given? os "S"))
      (%nse-or-die (%nse-libc "setuid" (fn (_ door) (cu-ptr-call door (%nse-zero (%nse-value os "S"))))) "setuid"))
    (if (null? prog) (%nse-shell) (%nse-exec prog))))

(def %nse-main
  (fn (_ argv)
    (def r (cu-getopt-long %nse-optstr %nse-longs argv))
    (def os (%nse-options (first r) ()))
    (if (null? (List ref 2 r))
      (%nse-run os (List ref 1 r))
      (do (file-write 2 (string-concat (list "nsenter: " (List ref 2 r) "\n")))
          (%nse-usage)))))

(def cu-nsenter
  (fn (_ argv stdin-thunk)
    (guard (e (if (eq? (cu-err-label e) (lit nsenter)) 1 (error e)))
      (%nse-main argv))))

(provide cu/nsenter cu-nsenter)

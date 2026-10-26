; # x-coreutils -- the small tools, as applets
;
; ## cu/unshare.x -- unshare: a program run in namespaces of its own
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's unshare (util-linux/unshare.c).  The options are getopt_long's,
; each namespace's long option taking a FILE after an = that its namespace
; is bound onto once made, so it outlives the process; -r maps this user to
; root in a new user namespace, --mount-proc mounts a fresh /proc in a new
; mount namespace.  unshare(2) takes the namespaces, then PROG runs in place
; of this process -- after a fork under -f, the parent waiting and leaving as
; the child did -- or with none a login shell, $SHELL's or /bin/sh.  A FILE
; for a namespace while the mount namespace is unshared too is bound by a
; child still in the old one, released once the parent has unshared.  Darwin
; has no namespaces: there unsharing none runs PROG, and any is ENOSYS.

(module cu/unshare)

(import cu/cli cu-usage)
(import cu/getopt cu-getopt-long)
(import cu/prims append byte-at byte-len cu-err-label cu-int->str cu-last
  cu-member-s? cu-nth substring
  cu-stdin-to-command! cu-string-type cvt file-close file-err-text
  file-put-or-errno file-read-fd file-write filter libc-strerror map
  string-append string-concat string=? sys-exec-or-err sys-execv sys-exit
  sys-fork sys-getegid sys-getenv sys-geteuid sys-getpid sys-kill sys-mount
  sys-pipe sys-signal sys-unshare sys-wait-status)

(def %us-die
  (fn (_ msg)
    (do (file-write 2 (string-concat (list "unshare: " msg "\n")))
        (Err raise (lit unshare) msg ()))))

(def %us-hex (fn (_ n) (string-append "0x" (cvt n cu-string-type 16))))

; each namespace: its option, its long option, its CLONE_NEW* bit, and its
; file in /proc/PID/ns
(def %us-spaces
  (list (list "-m" "--mount" 131072 "mnt")
        (list "-u" "--uts" 67108864 "uts")
        (list "-i" "--ipc" 134217728 "ipc")
        (list "-n" "--net" 1073741824 "net")
        (list "-p" "--pid" 536870912 "pid")
        (list "-U" "--user" 268435456 "user")))

(def %us-longs
  (list (pair "mount" 2) (pair "uts" 2) (pair "ipc" 2) (pair "net" 2)
        (pair "pid" 2) (pair "user" 2) (pair "fork" 0) (pair "map-root-user" 0)
        (pair "mount-proc" 2) (pair "propagation" 1) (pair "setgroups" 1)))

; is any of NAMES among the options given
(def %us-on?
  (fn (_ items names) (pair? (filter (fn (_ it) (cu-member-s? (first it) names)) items))))

; the argument the last NAME given with one had, or nil
(def %us-last
  (fn (_ items name)
    (def with (filter (fn (_ it) (if (string=? (first it) name)
                                   (if (null? (rest it)) #f (not (eq? (rest it) (lit none)))) #f))
                      items))
    (if (null? with) () (rest (cu-last with)))))

; a namespace's options, and those that imply it: -r a user namespace,
; --mount-proc a mount namespace
(def %us-names
  (fn (_ ns)
    (append (list (first ns) (cu-nth 1 ns))
      (match ((string=? (first ns) "-U") (list "-r" "--map-root-user"))
             ((string=? (first ns) "-m") (list "--mount-proc"))
             (#t ())))))

; the mount flags --propagation's word stands for, the whole tree's
(def %us-propagation
  (fn (_ word)
    (match ((string=? word "private") 278528)        ; MS_REC | MS_PRIVATE
           ((string=? word "unchanged") 0)
           ((string=? word "shared") 1064960)        ; MS_REC | MS_SHARED
           ((string=? word "slave") 540672)          ; MS_REC | MS_SLAVE
           (#t (%us-die (string-append "unrecognized: --propagation=" word))))))

(def %us-mount
  (fn (_ source target type flags)
    (let ((e (sys-mount source target type flags)))
      (unless (= e 0)
        (%us-die (string-concat (list "can't mount " source " on " target " (flags:" (%us-hex flags) "): " (libc-strerror e))))))))

; each of PID's namespaces in BINDS, (NAMESPACE . FILE), bound onto its FILE
(def %us-bind
  (fn (_ pid binds)
    (map (fn (_ b)
           (%us-mount (string-concat (list "/proc/" (cu-int->str pid) "/ns/" (cu-nth 3 (first b)))) (rest b) () 4096))
         binds)))

; the child that binds this process's namespaces, PPID's, once the parent
; has unshared them: it waits until PIPE's end is closed
(def %us-binder
  (fn (_ pipe ppid binds)
    (let ((pid (sys-fork)))
      (if (= pid 0)
        (do (file-close (rest pipe))
            (file-read-fd (first pipe) 1)
            (sys-exit (guard (e (if (eq? (cu-err-label e) (lit unshare)) 1 (error e)))
                        (do (%us-bind ppid binds) 0))))
        pid))))

(def %us-put
  (fn (_ path text)
    (let ((r (file-put-or-errno path text)))
      (when (pair? r)
        (%us-die
          (match ((eq? (first r) (lit open)) (string-concat (list "can't open '" path "': " (libc-strerror (rest r)))))
                 ((eq? (first r) (lit write)) (string-append "write error: " (libc-strerror (rest r))))
                 (#t "short write")))))))

; under -f the parent waits for the child and leaves as it did, by its
; signal or with its status; the child goes on
(def %us-fork
  (fn (_)
    (let ((pid (sys-fork)))
      (unless (= pid 0)
        (let ((st (sys-wait-status pid)))
          (when (> (rest st) 0)
            (do (sys-signal (rest st) 0) (sys-kill (sys-getpid) (rest st))))
          (sys-exit (if (> (rest st) 0) (+ 128 (rest st)) (first st))))))))

; PROG run in place of this process, as BB_EXECVP_or_die runs it, or with
; none a login shell: $SHELL, else /bin/sh, under its name with a dash before
(def %us-exec
  (fn (_ prog)
    (cu-stdin-to-command!)
    (if (pair? prog)
      (let ((err (sys-exec-or-err (first prog) (rest prog))))
        (file-write 2 (string-concat (list "unshare: can't execute '" (first prog) "': " (file-err-text err) "\n")))
        (sys-exit (if (string=? (file-err-text err) "No such file or directory") 127 126)))
      (let ((shell (let ((s (sys-getenv "SHELL"))) (if (if (null? s) #t (string=? s "")) "/bin/sh" s))))
        (def slash (fn (self i) (match ((< i 0) 0) ((= (byte-at shell i) #\/) (+ i 1)) (#t (self (- i 1))))))
        (def e (sys-execv shell (list (string-append "-" (substring shell (slash (- (byte-len shell) 1)) (byte-len shell))))))
        (%us-die (string-concat (list "can't execute '" shell "': " (libc-strerror e))))))))

; after the namespaces are made: -f, the user mapped or setgroups written,
; the mount tree's propagation, a fresh /proc, then PROG
(def %us-enter
  (fn (_ items prog uid gid)
    (when (%us-on? items (list "-f" "--fork")) (%us-fork))
    (def setgroups (%us-last items "--setgroups"))
    (match ((%us-on? items (list "-r" "--map-root-user"))
             (do (%us-put "/proc/self/setgroups" "deny")
                 (%us-put "/proc/self/uid_map" (string-append "0 " (string-append (cu-int->str uid) " 1")))
                 (%us-put "/proc/self/gid_map" (string-append "0 " (string-append (cu-int->str gid) " 1")))))
           ((null? setgroups) ())
           (#t (%us-put "/proc/self/setgroups" setgroups)))
    (def mnt (%us-on? items (%us-names (first %us-spaces))))
    (when mnt
      (%us-mount "none" "/" ()
        (%us-propagation (let ((p (%us-last items "--propagation"))) (if (null? p) "private" p)))))
    (when (%us-on? items (list "--mount-proc"))
      (let ((dir (let ((d (%us-last items "--mount-proc"))) (if (null? d) "/proc" d))))
        (do (%us-mount "none" dir () 278528)            ; MS_PRIVATE | MS_REC
            (%us-mount "proc" dir "proc" 14))))         ; MS_NOSUID | MS_NODEV | MS_NOEXEC
    (%us-exec prog)))

(def %us-run
  (fn (_ items prog)
    (def uid (sys-geteuid))
    (def gid (sys-getegid))
    (def setgroups (%us-last items "--setgroups"))
    (def map-root (%us-on? items (list "-r" "--map-root-user")))
    (match ((null? setgroups) ())
           ((string=? setgroups "allow")
             (when map-root (%us-die "--setgroups=allow and --map-root-user are mutually exclusive")))
           ((not (string=? setgroups "deny")) (%us-die (string-append "unrecognized: --setgroups=" setgroups))))
    (def flags
      (List fold (fn (_ acc ns) (if (%us-on? items (%us-names ns)) (| acc (cu-nth 2 ns)) acc)) 0 %us-spaces))
    (def binds
      (filter (fn (_ b) (not (null? (rest b))))
        (map (fn (_ ns) (pair ns (%us-last items (cu-nth 1 ns)))) %us-spaces)))
    (def mnt (%us-on? items (%us-names (first %us-spaces))))
    ; a bad --propagation is refused before anything is made
    (when mnt
      (%us-propagation (let ((p (%us-last items "--propagation"))) (if (null? p) "private" p))))
    (def pipe (if (if (pair? binds) mnt #f) (sys-pipe) ()))
    (def binder (if (pair? pipe) (%us-binder pipe (sys-getpid) binds) ()))
    (def e (sys-unshare flags))
    (unless (= e 0) (%us-die (string-concat (list "unshare(" (%us-hex flags) "): " (libc-strerror e)))))
    (when (pair? pipe) (do (file-close (rest pipe)) (file-close (first pipe))))
    (def bound
      (match ((null? binds) 0)
             (mnt (let ((st (sys-wait-status binder))) (if (= (rest st) 0) (first st) 0)))
             (#t (do (%us-bind (sys-getpid) binds) 0))))
    (if (= bound 0) (%us-enter items prog uid gid) bound)))

(def cu-unshare
  (fn (_ argv stdin-thunk)
    (guard (e (if (eq? (cu-err-label e) (lit unshare)) 1 (error e)))
      (let ((r (cu-getopt-long "+muinpUfr" %us-longs "unshare" argv)))
        (if (= (cu-nth 1 r) 0)
          (%us-run (first r) (cu-nth 2 r))
          (cu-usage "unshare"))))))

(provide cu/unshare cu-unshare)

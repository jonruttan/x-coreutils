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

; each namespace: its option's letter, its CLONE_NEW* bit, and its file in
; /proc/PID/ns
(def %us-spaces
  (list (list "m" 131072 "mnt")
        (list "u" 67108864 "uts")
        (list "i" 134217728 "ipc")
        (list "n" 1073741824 "net")
        (list "p" 536870912 "pid")
        (list "U" 268435456 "user")))

; the long options, each read as its letter -- a namespace's FILE its value --
; or as itself
(def %us-longs
  (list (list "mount" 2 "m") (list "uts" 2 "u") (list "ipc" 2 "i") (list "net" 2 "n")
        (list "pid" 2 "p") (list "user" 2 "U") (list "fork" 0 "f") (list "map-root-user" 0 "r")
        (list "mount-proc" 2 "mount-proc") (list "propagation" 1 "propagation")
        (list "setgroups" 1 "setgroups")))

; is any of KEYS among the options given
(def %us-on?
  (fn (_ taken keys) (pair? (filter (fn (_ t) (cu-member-s? (first t) keys)) taken))))

; the value the last KEY given with one had, or nil
(def %us-last
  (fn (_ taken key)
    (def with (filter (fn (_ t) (if (string=? (first t) key) (not (null? (rest t))) #f)) taken))
    (if (null? with) () (rest (cu-last with)))))

; a namespace's letter, and those that imply it: -r a user namespace,
; --mount-proc a mount namespace
(def %us-names
  (fn (_ ns)
    (pair (first ns)
      (match ((string=? (first ns) "U") (list "r"))
             ((string=? (first ns) "m") (list "mount-proc"))
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
           (%us-mount (string-concat (list "/proc/" (cu-int->str pid) "/ns/" (cu-nth 2 (first b)))) (rest b) () 4096))
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
    (when (%us-on? items (list "f")) (%us-fork))
    (def setgroups (%us-last items "setgroups"))
    (match ((%us-on? items (list "r"))
             (do (%us-put "/proc/self/setgroups" "deny")
                 (%us-put "/proc/self/uid_map" (string-append "0 " (string-append (cu-int->str uid) " 1")))
                 (%us-put "/proc/self/gid_map" (string-append "0 " (string-append (cu-int->str gid) " 1")))))
           ((null? setgroups) ())
           (#t (%us-put "/proc/self/setgroups" setgroups)))
    (def mnt (%us-on? items (%us-names (first %us-spaces))))
    (when mnt
      (%us-mount "none" "/" ()
        (%us-propagation (let ((p (%us-last items "propagation"))) (if (null? p) "private" p)))))
    (when (%us-on? items (list "mount-proc"))
      (let ((dir (let ((d (%us-last items "mount-proc"))) (if (null? d) "/proc" d))))
        (do (%us-mount "none" dir () 278528)            ; MS_PRIVATE | MS_REC
            (%us-mount "proc" dir "proc" 14))))         ; MS_NOSUID | MS_NODEV | MS_NOEXEC
    (%us-exec prog)))

(def %us-run
  (fn (_ items prog)
    (def uid (sys-geteuid))
    (def gid (sys-getegid))
    (def setgroups (%us-last items "setgroups"))
    (def map-root (%us-on? items (list "r")))
    (match ((null? setgroups) ())
           ((string=? setgroups "allow")
             (when map-root (%us-die "--setgroups=allow and --map-root-user are mutually exclusive")))
           ((not (string=? setgroups "deny")) (%us-die (string-append "unrecognized: --setgroups=" setgroups))))
    (def flags
      (List fold (fn (_ acc ns) (if (%us-on? items (%us-names ns)) (| acc (cu-nth 1 ns)) acc)) 0 %us-spaces))
    (def binds
      (filter (fn (_ b) (not (null? (rest b))))
        (map (fn (_ ns) (pair ns (%us-last items (first ns)))) %us-spaces)))
    (def mnt (%us-on? items (%us-names (first %us-spaces))))
    ; a bad --propagation is refused before anything is made
    (when mnt
      (%us-propagation (let ((p (%us-last items "propagation"))) (if (null? p) "private" p))))
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
      (let ((r (cu-getopt-long "+muinpUfr" %us-longs argv)))
        (if (null? (cu-nth 2 r))
          (%us-run (first r) (cu-nth 1 r))
          (do (file-write 2 (string-concat (list "unshare: " (cu-nth 2 r) "\n")))
              (cu-usage "unshare")))))))

(provide cu/unshare cu-unshare)

; # x-coreutils -- the small tools, as applets
;
; ## cu/who.x -- who am I, and what am I running on
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; id whoami groups logname uname arch nproc nice chroot.
;
; The name problem: there is no passwd or group door, so nothing here turns uid
; 501 into "jon". /etc/passwd is read when it holds the id (true on Linux, and
; for system accounts on macOS), and $USER or $LOGNAME stands in otherwise; the
; numeric id is the last resort and is never wrong. `id -u` and friends need no
; name at all.

(def %cu-passwd-name
  (fn (_ uid)
    (def want (%cu-int->str uid))
    (def go
      (fn (self ls)
        (if (null? ls) ()
          (let ((fs (%cu-split-byte (first ls) 58)))               ; :
            (if (< (length fs) 3) (self (rest ls))
              (if (string=? (%cu-nth 2 fs) want) (first fs)
                (self (rest ls))))))))
    (if (file-exists? "/etc/passwd")
      (go (%cu-lines (file-read-all "/etc/passwd")))
      ())))

; the name for a uid: the passwd file, then the environment, then the
; number itself
(def %cu-user-name
  (fn (_ uid)
    (let ((p (%cu-passwd-name uid)))
      (if (not (null? p)) p
        (let ((u (sys-getenv "USER")))
          (if (not (null? u)) u
            (let ((l (sys-getenv "LOGNAME")))
              (if (not (null? l)) l (%cu-int->str uid)))))))))

(def %cu-whoami
  (fn (_ argv stdin-thunk)
    (do (display (string-append (%cu-user-name (sys-geteuid)) "\n")) 0)))

; logname is the LOGIN name -- the real uid, not the effective one
(def %cu-logname
  (fn (_ argv stdin-thunk)
    (let ((l (sys-getenv "LOGNAME")))
      (do (display
            (string-append (if (null? l) (%cu-user-name (sys-getuid)) l) "\n"))
          0))))

(def %cu-groups
  (fn (_ argv stdin-thunk)
    (do (display
          (string-append
            (%cu-join-with (map (fn (_ g) (%cu-int->str g)) (sys-getgroups)) " ")
            "\n"))
        0)))

; id: the full line by default, or one field under -u -g -G, with -n
; asking for names where a name can be found and -r for the real ids in
; place of the effective ones.  -r on its own has nothing to print, and
; says so the way id does.
(def %cu-id
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "id" argv))
    (def n? (Opts on? o "-n"))
    (def r? (Opts on? o "-r"))
    (def one?
      (match ((Opts on? o "-u") #t) ((Opts on? o "-g") #t) (#t (Opts on? o "-G"))))
    (def uid (if r? (sys-getuid) (sys-geteuid)))
    (def gid (if r? (sys-getgid) (sys-getegid)))
    (match
      ((if r? (not one?) #f)
        (do (file-write 2
              "id: printing only names or real IDs requires -u, -g, or -G\n")
            1))
      ((Opts on? o "-u")
        (do (display
              (string-append (if n? (%cu-user-name uid) (%cu-int->str uid)) "\n"))
            0))
      ((Opts on? o "-g")
        (do (display (string-append (%cu-int->str gid) "\n")) 0))
      ((Opts on? o "-G")
        (do (display
              (string-append
                (%cu-join-with
                  (map (fn (_ g) (%cu-int->str g)) (sys-getgroups)) " ")
                "\n"))
            0))
      (#t
        (do (display
              (string-concat
                (list "uid=" (%cu-int->str uid)
                      "(" (%cu-user-name uid) ") gid="
                      (%cu-int->str gid) " groups="
                      (%cu-join-with
                        (map (fn (_ g) (%cu-int->str g)) (sys-getgroups))
                        ",")
                      "\n")))
            0)))))

; --- uname, arch, nproc -------------------------------------------------------

(def %cu-uname-field
  (fn (_ u key)
    (let ((e (Assoc entry key u))) (if (null? e) "unknown" (rest e)))))

(def %cu-uname
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "uname" argv))
    (def u (sys-uname))
    (def a? (Opts on? o "-a"))
    (def want
      (fn (_ flag key)
        (if (if a? #t (Opts on? o flag))
          (list (%cu-uname-field u key)) ())))
    ; -p -i -o have no door: the processor type and the "operating system"
    ; string are sysctl and a busybox compile-time constant. They answer
    ; `unknown`, as uname does when it cannot tell.
    (def parts
      (append (want "-s" (lit sysname))
        (append (want "-n" (lit nodename))
          (append (want "-r" (lit release))
            (append (want "-v" (lit version))
              (append (want "-m" (lit machine))
                (append (if (Opts on? o "-p") (list "unknown") ())
                  (append (if (Opts on? o "-i") (list "unknown") ())
                    (if (Opts on? o "-o") (list "unknown") ())))))))))
    ; bare uname is uname -s
    (do (display
          (string-append
            (%cu-join-with
              (if (null? parts) (list (%cu-uname-field u (lit sysname))) parts)
              " ")
            "\n"))
        0)))

(def %cu-arch
  (fn (_ argv stdin-thunk)
    (do (display
          (string-append (%cu-uname-field (sys-uname) (lit machine)) "\n"))
        0)))

; nproc: the processors this process may use, which the OpenMP variables
; narrow.  OMP_NUM_THREADS, when it holds a count, is the answer -- even above
; the processors installed -- and OMP_THREAD_LIMIT caps whatever the answer
; is.  --all asks for the processors installed and reads neither.
; --ignore=N holds N back and never answers below one.
;
; One door answers "available" and "installed" alike, so here the two differ
; only through those variables: CPU affinity, which also narrows what is
; available, is not read (recorded divergence).

; A count as OpenMP spells one, or 0 for none.  White space around it is
; allowed and a list answers its first element, but anything else after the
; digits leaves the variable unset: "3x" is not three, and neither is "0".
(def %cu-omp-count
  (fn (_ s)
    (if (null? s) 0
      (let ((end (byte-len s)))
        (def space?
          (fn (_ b)
            (match ((= b 32) #t) ((= b 9) #t) ((= b 10) #t)
                   ((= b 11) #t) ((= b 12) #t) (#t (= b 13)))))
        (def skip
          (fn (self i) (if (< i end) (if (space? (byte-at s i)) (self (+ i 1)) i) i)))
        (def digit? (fn (_ b) (if (>= b 48) (<= b 57) #f)))
        (def start (skip 0))
        (if (if (< start end) (not (digit? (byte-at s start))) #t) 0
          (let ((go (fn (self i n)
                      (if (if (< i end) (digit? (byte-at s i)) #f)
                        (self (+ i 1) (+ (* n 10) (- (byte-at s i) 48)))
                        (pair n i)))))
            (let ((read (go start 0)))
              (let ((after (skip (rest read))))
                (match
                  ((>= after end) (first read))
                  ((= (byte-at s after) 44) (first read))  ; ,
                  (#t 0))))))))))

(def %cu-nproc
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "nproc" argv))
    (def cpus (sys-cpu-count))
    (def limit (%cu-omp-count (sys-getenv "OMP_THREAD_LIMIT")))
    (def threads (%cu-omp-count (sys-getenv "OMP_NUM_THREADS")))
    (def capped (fn (_ c) (if (if (> limit 0) (< limit c) #f) limit c)))
    (def n
      (match
        ((Opts on? o "--all") cpus)
        ((> threads 0) (capped threads))
        (#t (capped cpus))))
    (def held
      (let ((v (Opts value o "--ignore"))) (if (null? v) 0 (%cu-num-prefix v))))
    (do (display
          (string-append (%cu-int->str (if (< (- n held) 1) 1 (- n held))) "\n"))
        0)))

; --- nice, chroot -------------------------------------------------------------

; nice [-n N] COMMAND: the increment applies to THIS process, which
; then becomes the command
(def %cu-nice
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "nice" argv))
    (def inc (let ((v (Opts value o "-n")))
               (if (null? v) 10 (%cu-num-prefix v))))
    (def cmd (Opts operands o))
    (if (null? cmd)
      (do (display (string-append (%cu-int->str (sys-nice 0)) "\n")) 0)
      (do (sys-nice inc)
          (sys-exec (first cmd) (rest cmd))
          127))))

(def %cu-chroot
  (fn (_ argv stdin-thunk)
    (if (null? argv)
      (do (file-write 2 "chroot: missing operand\n") 1)
      (if (< (sys-chroot (first argv)) 0)
        (do (file-write 2
              (string-concat
                (list "chroot: cannot change root to '" (first argv)
                      "': Operation not permitted\n")))
            1)
        (let ((cmd (rest argv)))
          (if (null? cmd) 0
            (do (sys-exec (first cmd) (rest cmd)) 127)))))))

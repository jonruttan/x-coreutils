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
; A uid's name is the system's, from sys-user-name (cu/prims.x); where the
; system has none, $USER or $LOGNAME stands in, and the numeric id is the last
; resort.  `id -u` and friends need no name at all.

; the name for a uid: the system's, then the environment, then the number itself
(def %cu-user-name
  (fn (_ uid)
    (let ((p (sys-user-name uid)))
      (if (not (null? p)) p
        (let ((u (sys-getenv "USER")))
          (if (not (null? u)) u
            (let ((l (sys-getenv "LOGNAME")))
              (if (not (null? l)) l (%cu-int->str uid)))))))))

(def %cu-whoami
  (fn (_ argv stdin-thunk)
    (%cu-operands "whoami" argv 0 0
      (fn (_) (do (display (string-append (%cu-user-name (sys-geteuid)) "\n")) 0)))))

; logname is the LOGIN name -- the real uid, not the effective one
(def %cu-logname
  (fn (_ argv stdin-thunk)
    (%cu-operands "logname" argv 0 0
      (fn (_)
        (let ((l (sys-getenv "LOGNAME")))
          (do (display
                (string-append (if (null? l) (%cu-user-name (sys-getuid)) l) "\n"))
              0))))))

; --- whom id and groups describe ----------------------------------------------

; (NAME RUID EUID RGID EGID GROUPS): the calling process, with the groups it
; holds; or the user a spec names, its ids real and effective both, with the
; groups the system lists for it.  id reads a spec that names no user as a uid
; -- blanks, an optional +, and digits to the end -- where groups does not.
; Nil where the spec is no user at all.
(def %cu-self
  (fn (_)
    (list (sys-user-name (sys-geteuid)) (sys-getuid) (sys-geteuid)
          (sys-getgid) (sys-getegid) (sys-getgroups))))

(def %cu-named-user
  (fn (_ spec uid?)
    (let ((uid (let ((u (if (= (byte-len spec) 0) () (sys-user-id spec))))
                 (if (if (null? u) uid? #f) (%cu-uid-digits spec) u))))
      (let ((name (if (null? uid) () (sys-user-name uid))))
        (if (null? name) ()
          (let ((gid (sys-user-group name)))
            (list name uid uid gid gid (sys-user-groups name gid))))))))

(def %cu-uid-digits
  (fn (_ s)
    (def end (byte-len s))
    (def blank (fn (self i)
                 (if (if (< i end) (if (= (byte-at s i) 32) #t (= (byte-at s i) 9)) #f)
                   (self (+ i 1)) i)))
    (let ((i (blank 0)))
      (%cu-chown-number
        (substring s (if (if (< i end) (= (byte-at s i) 43) #f) (+ i 1) i) end)))))

; the groups a line of them shows, as id -G and groups show them: the real
; group, the effective one where it differs, then the rest held
(def %cu-group-line
  (fn (_ who)
    (let ((rg (%cu-nth 3 who)) (eg (%cu-nth 4 who)))
      (append (if (= rg eg) (list rg) (list rg eg))
        (filter (fn (_ g) (if (= g rg) #f (not (= g eg)))) (%cu-nth 5 who))))))

; and the groups id's full line lists: the effective group, then the rest, where
; one that is the effective group again, or the one before it again, is dropped
(def %cu-group-list
  (fn (_ who)
    (let ((eg (%cu-nth 4 who)))
      (let ((go (fn (self gs last acc)
                  (if (null? gs) (reverse acc)
                    (if (if (= (first gs) eg) #t (= (first gs) last))
                      (self (rest gs) last acc)
                      (self (rest gs) (first gs) (pair (first gs) acc)))))))
        (go (%cu-nth 5 who) eg (list eg))))))

; a group by its name, or its number where it has none
(def %cu-group-shown
  (fn (_ g) (let ((n (sys-group-name g))) (if (null? n) (%cu-int->str g) n))))

; an id with its name after it in brackets, where it has one: 20(staff)
(def %cu-id-named
  (fn (_ id name)
    (if (null? name) (%cu-int->str id)
      (string-concat (list (%cu-int->str id) "(" name ")")))))

; groups [USER]...: the groups of the calling process, by name, or of each USER
; after its name and a colon.  A USER is a name -- groups reads no uid -- and
; one that is no user is said and passed over.
(def %cu-groups
  (fn (_ ops stdin-thunk)
    (def line
      (fn (_ who) (%cu-join-with (map %cu-group-shown (%cu-group-line who)) " ")))
    (if (null? ops)
      (do (display (string-append (line (%cu-self)) "\n")) 0)
      (%cu-groups-each ops line 0))))

(def %cu-groups-each
  (fn (self ops line st)
    (if (null? ops) st
      (let ((who (%cu-named-user (first ops) #f)))
        (self (rest ops) line
          (if (null? who)
            (do (file-write 2
                  (string-concat (list "groups: '" (first ops) "': no such user\n")))
                1)
            (do (display (string-concat (list (first ops) " : " (line who) "\n")))
                st)))))))

; id [USER]...: the full line by default, or one field under -u -g -G, with -n
; for names and -r for the real ids in place of the effective ones; -n and -r
; have nothing to print without one of the three, and more than one is refused,
; as id refuses them.  With no USER, the calling process; each USER, on a line
; of its own, is a name or a uid, and one that is neither is said and passed
; over.
(def %cu-id
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "id" argv))
    (def n? (Opts on? o "-n"))
    (def r? (Opts on? o "-r"))
    (def fields (filter (fn (_ f) (Opts on? o f)) (list "-u" "-g" "-G")))
    (def field (if (null? fields) () (first fields)))
    (def ops (Opts operands o))
    (match
      ((> (length fields) 1)
        (do (file-write 2 "id: cannot print \"only\" of more than one choice\n") 1))
      ((if (null? field) (if n? #t r?) #f)
        (do (file-write 2
              "id: printing only names or real IDs requires -u, -g, or -G\n")
            1))
      ((null? ops) (%cu-id-print (%cu-self) field n? r?))
      (#t (%cu-id-each ops field n? r? 0)))))

(def %cu-id-each
  (fn (self ops field n? r? st)
    (if (null? ops) st
      (let ((who (%cu-named-user (first ops) #t)))
        (self (rest ops) field n? r?
          (%cu-max-status st
            (if (null? who)
              (do (file-write 2
                    (string-concat (list "id: '" (first ops) "': no such user\n")))
                  1)
              (%cu-id-print who field n? r?))))))))

; one line of id for WHO, answering the status: 1 where -n finds no name for
; an id, which is said and printed as its number
(def %cu-id-print
  (fn (_ who field n? r?)
    (match
      ((null? field) (do (display (string-append (%cu-id-full who) "\n")) 0))
      ((string=? field "-u")
        (%cu-id-one (if r? (%cu-nth 1 who) (%cu-nth 2 who)) n? sys-user-name "user"))
      ((string=? field "-g")
        (%cu-id-one (if r? (%cu-nth 3 who) (%cu-nth 4 who)) n? sys-group-name "group"))
      (#t
        (do (display
              (string-append
                (%cu-join-with
                  (map (if n? %cu-group-shown %cu-int->str) (%cu-group-line who)) " ")
                "\n"))
            0)))))

(def %cu-id-one
  (fn (_ id n? look kind)
    (let ((name (if n? (look id) ())))
      (do (display (string-append (if (null? name) (%cu-int->str id) name) "\n"))
          (if (if n? (null? name) #f)
            (do (file-write 2
                  (string-concat
                    (list "id: cannot find name for " kind " ID " (%cu-int->str id) "\n")))
                1)
            0)))))

; the full line: uid=, gid=, euid= and egid= where they differ from the real
; ones, and the groups, each id followed by its name where it has one
(def %cu-id-full
  (fn (_ who)
    (let ((ru (%cu-nth 1 who)) (eu (%cu-nth 2 who)) (rg (%cu-nth 3 who))
          (eg (%cu-nth 4 who)))
      (string-concat
        (list "uid=" (%cu-id-named ru (sys-user-name ru))
              " gid=" (%cu-id-named rg (sys-group-name rg))
              (if (= eu ru) "" (string-append " euid=" (%cu-id-named eu (sys-user-name eu))))
              (if (= eg rg) "" (string-append " egid=" (%cu-id-named eg (sys-group-name eg))))
              " groups="
              (%cu-join-with
                (map (fn (_ g) (%cu-id-named g (sys-group-name g))) (%cu-group-list who))
                ","))))))

; --- uname, arch, nproc -------------------------------------------------------

(def %cu-uname-field
  (fn (_ u key)
    (let ((e (Assoc entry key u))) (if (null? e) "unknown" (rest e)))))

(def %cu-uname
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "uname" argv))
    (%cu-operands "uname" (Opts operands o) 0 0 (fn (_) (%cu-uname-run o)))))

(def %cu-uname-run
  (fn (_ o)
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

; arch is GNU's uname.c built another way, and refuses an operand as uname does
(def %cu-arch
  (fn (_ argv stdin-thunk)
    (%cu-operands "arch" argv 0 0
      (fn (_)
        (do (display
              (string-append (%cu-uname-field (sys-uname) (lit machine)) "\n"))
            0)))))

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
    (%cu-operands "nproc" (Opts operands o) 0 0 (fn (_) (%cu-nproc-run o)))))

(def %cu-nproc-run
  (fn (_ o)
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
          (cu-stdin-to-command!)
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
            (do (cu-stdin-to-command!) (sys-exec (first cmd) (rest cmd)) 127)))))))

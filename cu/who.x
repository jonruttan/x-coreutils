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
; THE NAME PROBLEM.  There is no passwd or group door -- nothing here
; can turn uid 501 into "jon".  Two answers are available and both are
; used: /etc/passwd is read when it holds the id (true on Linux, and
; for the system accounts on macOS), and $USER or $LOGNAME stands in
; when it does not.  The numeric id is the last resort, and is never
; wrong.  `id -u` and friends never need a name at all.

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
; asking for names where a name can be found
(def %cu-id
  (fn (_ argv stdin-thunk)
    (def n? (%cu-has-flag? argv "-n"))
    (def uid (sys-geteuid))
    (def gid (sys-getegid))
    (if (%cu-has-flag? argv "-u")
      (do (display
            (string-append (if n? (%cu-user-name uid) (%cu-int->str uid)) "\n"))
          0)
      (if (%cu-has-flag? argv "-g")
        (do (display (string-append (%cu-int->str gid) "\n")) 0)
        (if (%cu-has-flag? argv "-G")
          (do (display
                (string-append
                  (%cu-join-with
                    (map (fn (_ g) (%cu-int->str g)) (sys-getgroups)) " ")
                  "\n"))
              0)
          (do (display
                (string-concat
                  (list "uid=" (%cu-int->str uid)
                        "(" (%cu-user-name uid) ") gid="
                        (%cu-int->str gid) " groups="
                        (%cu-join-with
                          (map (fn (_ g) (%cu-int->str g)) (sys-getgroups))
                          ",")
                        "\n")))
              0))))))

; --- uname, arch, nproc -------------------------------------------------------

(def %cu-uname-field
  (fn (_ u key)
    (let ((e (Assoc entry key u))) (if (null? e) "unknown" (rest e)))))

(def %cu-uname
  (fn (_ argv stdin-thunk)
    (def u (sys-uname))
    (def a? (%cu-has-flag? argv "-a"))
    (def want
      (fn (_ flag key)
        (if (if a? #t (%cu-has-flag? argv flag))
          (list (%cu-uname-field u key)) ())))
    (def parts
      (append (want "-s" (lit sysname))
        (append (want "-n" (lit nodename))
          (append (want "-r" (lit release))
            (append (want "-v" (lit version))
              (want "-m" (lit machine)))))))
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

(def %cu-nproc
  (fn (_ argv stdin-thunk)
    (do (display (string-append (%cu-int->str (sys-cpu-count)) "\n")) 0)))

; --- nice, chroot -------------------------------------------------------------

; nice [-n N] COMMAND: the increment applies to THIS process, which
; then becomes the command
(def %cu-nice
  (fn (_ argv stdin-thunk)
    (def n? (%cu-has-flag? argv "-n"))
    (def inc (if n? (%cu-num-prefix (first (rest argv))) 10))
    (def cmd (filter (fn (_ x) (not (%cu-option-token? x)))
               (if n? (rest (rest argv)) argv)))
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

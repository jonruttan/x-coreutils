; # x-coreutils -- the small tools, as applets
;
; ## cu/tunctl.x -- tunctl: TAP interfaces made persistent and taken back
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's tunctl with FEATURE_TUNCTL_UG (networking/tunctl.c).  -f's
; device, /dev/net/tun unless named, is opened and TUNSETIFF asks it for a
; TAP interface without packet information, named by -t or -d (tapN unless
; named, a %d in the name the kernel's next number).  -d makes it
; nonpersistent, so it goes when the device closes; otherwise -g sets its
; group, -u its owner (the effective user without -g, none with -g alone),
; and TUNSETPERSIST keeps it.  -b writes only its name.  -u and -g take
; names, not numbers, as busybox's xuname2uid and xgroup2gid take them.

(module cu/tunctl)

(import cu/cli cu-opts cu-usage)
(import cu/inet inet-set! inet-zeros)
(import cu/inetd in-c in-call)
(import cu/prims byte-at byte-len cu-err-label cu-int->str cu-ptr->str
  cu-ptr-call cu-str->ptr file-write libc-strerror map string-append
  string-concat sys-geteuid sys-group-id sys-user-id)

(def %tu-die
  (fn (_ msg)
    (do (file-write 2 (string-concat (list "tunctl: " msg "\n")))
        (Err raise (lit tunctl) msg ()))))

; IOCTL: REQ on FD with ARG, its failure busybox's bare strerror
(def %tu-ioctl
  (fn (_ fd req arg)
    (let ((r (in-call (cu-ptr-call (in-c "ioctl") fd req arg))))
      (when (< r 0) (%tu-die (libc-strerror (Err errno-of r)))))))

(def %tu-fd -1)

; the interface made persistent: -g's group set, then its owner
(def %tu-create
  (fn (_ o made)
    (def g (Opts value o "-g"))
    (def group (if (null? g) -1
                 (let ((n (sys-group-id g))) (if (null? n) (%tu-die (string-append "unknown group " g)) n))))
    (unless (null? g) (%tu-ioctl %tu-fd 1074025678 group))
    (def u (Opts value o "-u"))
    (def user (if (null? u) (if (null? g) (sys-geteuid) -1)
                (let ((n (sys-user-id u))) (if (null? n) (%tu-die (string-append "unknown user " u)) n))))
    (%tu-ioctl %tu-fd 1074025676 user)
    (%tu-ioctl %tu-fd 1074025675 1)
    (file-write 1 (if (Opts on? o "-b") (string-append made "\n")
                    (string-concat (list "Set '" made "' persistent and owned by uid " (cu-int->str user)
                                         (if (= group -1) "" (string-append " gid " (cu-int->str group))) "\n"))))))

(def %tu-main
  (fn (_ argv)
    (def o (cu-opts "tunctl" argv))
    (def t (Opts value o "-t"))
    (def d (Opts value o "-d"))
    (when (if (pair? (Opts operands o)) #t (if (null? t) #f (not (null? d))))
      (Err raise (lit tunctl-usage) "usage" ()))
    (def name (if (null? t) (if (null? d) "tap%d" d) t))
    (def dev (let ((f (Opts value o "-f"))) (if (null? f) "/dev/net/tun" f)))
    (def ifr (inet-zeros 40))
    (List map (fn (_ i) (inet-set! ifr i (byte-at name i) 1))
              (List range 0 (if (> (byte-len name) 15) 15 (byte-len name))))
    (inet-set! ifr 16 4098 2)
    (set! %tu-fd (in-call (cu-ptr-call (in-c "open") dev 2)))
    (when (< %tu-fd 0) (%tu-die (string-concat (list "can't open '" dev "': " (libc-strerror (Err errno-of %tu-fd))))))
    (%tu-ioctl %tu-fd 1074025674 (cu-str->ptr ifr))
    (def made (cu-ptr->str (cu-str->ptr ifr)))
    (if (null? d) (%tu-create o made)
      (do (%tu-ioctl %tu-fd 1074025675 0)
          (file-write 1 (string-concat (list "Set '" made "' nonpersistent\n")))))
    0))

; the device closed however the run ends, as busybox's exit closes it
(def cu-tunctl
  (fn (_ argv stdin-thunk)
    (set! %tu-fd -1)
    (def status
      (guard (e (match ((eq? (cu-err-label e) (lit tunctl-usage)) (cu-usage "tunctl"))
                       ((eq? (cu-err-label e) (lit tunctl)) 1)
                       (#t (do (unless (< %tu-fd 0) (cu-ptr-call (in-c "close") %tu-fd)) (error e)))))
        (%tu-main argv)))
    (unless (< %tu-fd 0) (cu-ptr-call (in-c "close") %tu-fd))
    status))

(provide cu/tunctl cu-tunctl)

; # x-coreutils -- the small tools, as applets
;
; ## cu/setpriv.x -- setpriv: PROG run with other privilege settings
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's setpriv (util-linux/setpriv.c, libbb/capability.c).  -d shows
; the process's ids, groups, no_new_privs and its inheritable, ambient and
; bounding capabilities; otherwise --nnp sets no_new_privs, --inh-caps and
; --ambient-caps raise (+CAP) or lower (-CAP) capabilities, and the process
; becomes PROG.  The calls are the kernel's prctl, capget and capset, through
; syscall doors; Darwin has none of them, so they fail as ENOSYS there.

(module cu/setpriv)

(import cu/cli cu-opts cu-usage)
(import cu/inet inet-set! inet-zeros)
(import cu/inetd in-call)
(import cu/prims bit-and bit-or bit-shl bit-xor byte-at byte-len cu-err-label
  cu-int->str cu-ptr-ref cu-stdin-to-command! cu-str->ptr file-err-sym
  file-err-text file-write libc-strerror string-append string-concat substring
  sys-exec-or-err sys-exit sys-getegid sys-geteuid sys-getgid sys-getgroups
  sys-getuid)

(def %sp-die
  (fn (_ msg)
    (do (file-write 2 (string-concat (list "setpriv: " msg "\n")))
        (Err raise (lit setpriv) msg ()))))

(def %sp-warn (fn (_ msg) (file-write 2 (string-concat (list "setpriv: " msg "\n")))))

(def %sp-usage (fn (_) (Err raise (lit setpriv-usage) "usage" ())))

; CALL through its door with ARGS, answered as (R . ERRNO): ERRNO 0 unless R
; is below zero, and ENOSYS where the platform has no such call
(def %sp-enosys (if os-darwin? 78 38))
(def %sp-door (fn (_ name) (guard (_ ()) (syscall-door name))))
(def %sp-prctl-door (%sp-door (lit prctl)))
(def %sp-capget-door (%sp-door (lit capget)))
(def %sp-capset-door (%sp-door (lit capset)))

(def %sp-call
  (fn (_ door call)
    (if (null? door) (pair -1 %sp-enosys)
      (let ((r (in-call (call door))))
        (if (< r 0) (pair r (Err errno-of r)) (pair r 0))))))

(def %sp-prctl
  (fn (_ a0 a1 a2)
    (%sp-call %sp-prctl-door (fn (_ door) (door a0 a1 a2 0 0)))))

; perror's words: WHAT, then why the call failed
(def %sp-why (fn (_ what r) (string-concat (list what ": " (libc-strerror (rest r))))))

; the capabilities by number, as busybox names them; numbers up to the
; last the kernel headers know, CAP_CHECKPOINT_RESTORE, are valid
(def %sp-names
  (list "chown" "dac_override" "dac_read_search" "fowner" "fsetid" "kill"
        "setgid" "setuid" "setpcap" "linux_immutable" "net_bind_service"
        "net_broadcast" "net_admin" "net_raw" "ipc_lock" "ipc_owner"
        "sys_module" "sys_rawio" "sys_chroot" "sys_ptrace" "sys_pacct"
        "sys_admin" "sys_boot" "sys_nice" "sys_resource" "sys_time"
        "sys_tty_config" "mknod" "lease" "audit_write" "audit_control"
        "setfcap" "mac_override" "mac_admin" "syslog" "wake_alarm"
        "block_suspend" "audit_read"))
(def %sp-last-cap 40)

(def %sp-cap-name
  (fn (_ n)
    (if (< n (length %sp-names)) (List ref n %sp-names)
      (string-append "cap_" (cu-int->str n)))))

; A and B the same but for case, as strcasecmp compares them
(def %sp-lower (fn (_ c) (if (if (>= c 65) (<= c 90) #f) (+ c 32) c)))
(def %sp-same-case?
  (fn (_ a b)
    (if (= (byte-len a) (byte-len b))
      (let loop ((i 0))
        (match
          ((= i (byte-len a)) #t)
          ((= (%sp-lower (byte-at a i)) (%sp-lower (byte-at b i))) (loop (+ i 1)))
          (#t #f)))
      #f)))

(def %sp-digit? (fn (_ c) (if (>= c 48) (<= c 57) #f)))
(def %sp-space? (fn (_ c) (match ((= c 32) #t) ((if (>= c 9) (<= c 13) #f) #t) (#t #f))))

; sscanf's "cap_%u" on S: the number, or nil when S does not match; a
; minus sign wraps the number past every capability, unless it is 0
(def %sp-cap-digits
  (fn (_ s)
    (def n (byte-len s))
    (def at (let skip ((i 4)) (if (if (< i n) (%sp-space? (byte-at s i)) #f) (skip (+ i 1)) i)))
    (def sign (if (< at n) (byte-at s at) 0))
    (def from (if (if (= sign #\-) #t (= sign #\+)) (+ at 1) at))
    (def v (let digits ((i from) (v ()))
             (if (if (< i n) (%sp-digit? (byte-at s i)) #f)
               (digits (+ i 1) (+ (* 10 (if (null? v) 0 v)) (- (byte-at s i) 48)))
               v)))
    (match
      ((null? v) ())
      ((if (= sign #\-) (> v 0) #f) (+ %sp-last-cap 1))
      (#t v))))

(def %sp-cap-number
  (fn (_ name)
    (def prefixed (if (>= (byte-len name) 4)
                    (if (= (byte-at name 0) #\c)
                      (if (= (byte-at name 1) #\a)
                        (if (= (byte-at name 2) #\p) (= (byte-at name 3) #\_) #f) #f) #f) #f))
    (def n (if prefixed (%sp-cap-digits name) ()))
    (def i (if (null? n)
             (let find ((ns %sp-names) (i 0))
               (match ((null? ns) ()) ((%sp-same-case? (first ns) name) i) (#t (find (rest ns) (+ i 1)))))
             n))
    (if (if (null? i) #t (> i %sp-last-cap))
      (%sp-die (string-concat (list "unknown capability '" name "'")))
      i)))

; a +CAP or -CAP word's capability number
(def %sp-parse-cap
  (fn (_ word)
    (def c (if (> (byte-len word) 0) (byte-at word 0) 0))
    (unless (if (= c #\+) #t (= c #\-))
      (%sp-die (string-concat (list "invalid capability '" word "'"))))
    (%sp-cap-number (substring word 1 (byte-len word)))))

; strtok's words of S between commas, the empty ones dropped
(def %sp-words
  (fn (_ s) (List filter (fn (_ w) (> (byte-len w) 0)) (Str8 split "," s))))

; capget's version 3 header for this process, and its two data words:
; effective, permitted and inheritable, four bytes each, twice
(def %sp-header
  (fn (_)
    (let ((h (inet-zeros 8))) (do (inet-set! h 0 537396514 4) h))))

(def %sp-getcaps
  (fn (_ header)
    (def data (inet-zeros 24))
    (def r (%sp-call %sp-capget-door (fn (_ door) (door header data))))
    (when (< (first r) 0) (%sp-die (%sp-why "capget" r)))
    data))

(def %sp-inheritable-at (fn (_ i) (if (< i 32) 8 20)))
(def %sp-mask (fn (_ i) (bit-shl 1 (bit-and i 31))))
(def %sp-word (fn (_ data at) (cu-ptr-ref (cu-str->ptr data) at 4)))

(def %sp-set-inh-caps
  (fn (_ text)
    (def header (%sp-header))
    (def data (%sp-getcaps header))
    (List map
      (fn (_ word)
        (let ((cap (%sp-parse-cap word)))
          (let ((at (%sp-inheritable-at cap)) (m (%sp-mask cap)))
            (inet-set! data at
              (if (= (byte-at word 0) #\+) (bit-or (%sp-word data at) m)
                (bit-and (%sp-word data at) (bit-xor m 4294967295)))
              4))))
      (%sp-words text))
    (def r (%sp-call %sp-capset-door (fn (_ door) (door header data))))
    (when (< (first r) 0) (%sp-die (%sp-why "capset" r)))))

(def %sp-set-ambient-caps
  (fn (_ text)
    (List map
      (fn (_ word)
        (let ((cap (%sp-parse-cap word)) (raise? (= (byte-at word 0) #\+)))
          (let ((r (%sp-prctl 47 (if raise? 2 3) cap)))
            (when (< (first r) 0)
              (%sp-warn (%sp-why (if raise? "cap_ambient_raise" "cap_ambient_lower") r))))))
      (%sp-words text))))

; "TITLE: " and the capabilities HAS? holds, by name, or [none]
(def %sp-cap-line
  (fn (_ title has?)
    (def held (List filter has? (List range 0 (+ %sp-last-cap 1))))
    (string-concat (list title ": "
                         (if (null? held) "[none]" (Str8 join "," (map %sp-cap-name held)))
                         "\n"))))

(def %sp-prctl-bit
  (fn (_ what a0 a1 a2)
    (let ((r (%sp-prctl a0 a1 a2)))
      (do (when (< (first r) 0) (%sp-die (%sp-why (string-append "prctl: " what) r)))
          (> (first r) 0)))))

(def %sp-dump
  (fn (_)
    (def groups (sys-getgroups))
    (def nnp (%sp-prctl 39 0 0))
    (when (< (first nnp) 0) (%sp-die (%sp-why "prctl: GET_NO_NEW_PRIVS" nnp)))
    (file-write 1 (string-concat
                    (list "uid: " (cu-int->str (sys-getuid)) "\neuid: " (cu-int->str (sys-geteuid))
                          "\ngid: " (cu-int->str (sys-getgid)) "\negid: " (cu-int->str (sys-getegid))
                          "\nSupplementary groups: "
                          (if (null? groups) "[none]" (Str8 join "," (map cu-int->str groups)))
                          "\nno_new_privs: " (cu-int->str (first nnp)) "\n")))
    (def data (%sp-getcaps (%sp-header)))
    (file-write 1 (%sp-cap-line "Inheritable capabilities"
                    (fn (_ i) (> (bit-and (%sp-word data (%sp-inheritable-at i)) (%sp-mask i)) 0))))
    (file-write 1 (%sp-cap-line "Ambient capabilities"
                    (fn (_ i) (%sp-prctl-bit "CAP_AMBIENT_IS_SET" 47 1 i))))
    (file-write 1 (%sp-cap-line "Capability bounding set"
                    (fn (_ i) (%sp-prctl-bit "CAPBSET_READ" 23 i 0))))
    0))

; PROG run in place of this process, with busybox's statuses if it cannot be
(def %sp-exec
  (fn (_ prog)
    (do (cu-stdin-to-command!)
        (let ((e (sys-exec-or-err (first prog) (rest prog))))
          (do (file-write 2 (string-concat (list "setpriv: can't execute '" (first prog) "': " (file-err-text e) "\n")))
              (sys-exit (if (eq? (file-err-sym e) (lit enoent)) 127 126)))))))

(def %sp-main
  (fn (_ argv)
    (def o (cu-opts "setpriv" argv))
    (def prog (Opts operands o))
    (def nnp? (if (Opts on? o "--nnp") #t (Opts on? o "--no-new-privs")))
    (def inh (Opts value o "--inh-caps"))
    (def amb (Opts value o "--ambient-caps"))
    (def others? (if (pair? prog) #t (if nnp? #t (if (null? inh) (not (null? amb)) #t))))
    (match
      ((if (Opts on? o "-d") #t (Opts on? o "--dump")) (if others? (%sp-usage) (%sp-dump)))
      (#t (do (when nnp?
                (let ((r (%sp-prctl 38 1 0)))
                  (when (< (first r) 0) (%sp-die (%sp-why "prctl: SET_NO_NEW_PRIVS" r)))))
              (unless (null? inh) (%sp-set-inh-caps inh))
              (unless (null? amb) (%sp-set-ambient-caps amb))
              (if (null? prog) (%sp-usage) (%sp-exec prog)))))))

(def cu-setpriv
  (fn (_ argv stdin-thunk)
    (guard (e (match ((eq? (cu-err-label e) (lit setpriv-usage)) (cu-usage "setpriv"))
                     ((eq? (cu-err-label e) (lit setpriv)) 1)
                     (#t (error e))))
      (%sp-main argv))))

(provide cu/setpriv cu-setpriv)

; # x-coreutils -- the small tools, as applets
;
; ## lib/coreutils/klogd.x -- klogd: the kernel's messages to syslog
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; sysklogd/klogd.c, as busybox's defconfig builds it (klogctl): the
; kernel's ring is read through klogctl into a 1024-byte buffer, each
; newline-ended line its <PRI> read (info where there is none) and sent to
; syslog(3) as "kernel", a line that fills the buffer sent as it stands.
; -c N sets the console's level for the run, put back at the end; without
; -n the daemon goes to the background, in /.  A read waits on the ring's
; unread count, a quarter second at a time, so a signal ends it at once
; where a blocked klogctl(2) would sit.

(module coreutils/klogd)

(import coreutils/cli cu-opts)
(import coreutils/inetd in-call)
(import coreutils/logger lg-send)
(import coreutils/prims byte-at byte-len cu-int->ptr cu-int->str cu-libc-sym cu-ptr->str cu-ptr-call
  cu-ptr-set! cu-sig-ign cu-sweep-lines cu-sweep-tick! file-close file-unlink file-write hx-strtoul
  libc-strerror map string-append substring sys-getpid sys-kill sys-signal sys-usleep)
(import coreutils/signal ts-signal-number)
(import coreutils/syslogd sl-background! sl-number)
(import coreutils/vi vi-bundle-version)

(def %kl-size 1024)                    ; COMMON_BUFSIZE: the read buffer
(def %kl-pidfile "/var/run/klogd.pid")
(def %kl-ident "kernel")               ; openlog keeps the pointer: held for the run

(def %kl-die (fn (_ msg) (Err raise (lit klogd) msg ())))
(def %kl-ctl (fn (_ cmd buf n) (in-call (cu-ptr-call (cu-libc-sym "klogctl") cmd buf n))))
(def %kl-digit? (fn (_ c) (if (>= c #\0) (<= c #\9) #f)))

; one line, its <PRI> read as strtoul reads it: no digits is 0, past the
; largest word -1, and the text starts past a > that follows the digits;
; a lone < leaves nothing to send
(def %kl-line
  (fn (_ s)
    (def n (byte-len s))
    (def parsed
      (match
        ((if (> n 0) (not (= (byte-at s 0) #\<)) #t) (pair 6 0))
        ((= n 1) (pair 6 1))
        (#t (let ((r (if (%kl-digit? (byte-at s 1)) (hx-strtoul s 1 10 0x7FFFFFFFFFFFFFFF) (pair 0 1))))
              (pair (if (null? (first r)) -1 (first r))
                    (if (if (< (rest r) n) (= (byte-at s (rest r)) #\>) #f) (+ (rest r) 1) (rest r)))))))
    (def text (substring s (rest parsed) n))
    (when (> (byte-len text) 0) (lg-send (first parsed) text))))

; the lines of TEXT sent; what is left unended, unless it fills the buffer
(def %kl-lines
  (fn (_ text)
    (def n (byte-len text))
    (let go ((from 0))
      (let ((nl (let scan ((i from)) (if (if (< i n) (not (= (byte-at text i) 10)) #f) (scan (+ i 1)) i))))
        (if (< nl n)
          (do (%kl-line (substring text from nl)) (go (+ nl 1)))
          (if (< (- n from) (- %kl-size 1)) (substring text from n)
            (do (%kl-line (substring text from n)) "")))))))

; the read loop, to a signal caught -- its number -- or 0 after a read that failed
(def %kl-loop
  (fn (self buf left sigs)
    (cu-sweep-tick! cu-sweep-lines)
    (def sig (List find (fn (_ n) (Sys take-signal n)) sigs))
    (match
      ((not (null? sig)) sig)
      ((<= (%kl-ctl 9 (cu-int->ptr 0) 0) 0) (do (sys-usleep 250000) (self buf left sigs)))
      (#t
        (let ((n (%kl-ctl 2 (cu-int->ptr buf) (- (- %kl-size 1) (byte-len left)))))
          (if (< n 0)
            (do (lg-send 3 (string-append "klogctl(2) error: " (libc-strerror (Err errno-of -1)))) 0)
            (do (cu-ptr-set! (cu-int->ptr buf) n 0 1)
                (self buf (%kl-lines (string-append left (cu-ptr->str (cu-int->ptr buf)))) sigs))))))))

(def %kl-main
  (fn (_ argv)
    (def o (cu-opts "klogd" argv))
    (def c (Opts value o "-c"))
    (def level (if (null? c) 0 (sl-number c 1 8 0xFFFFFFFF %kl-die)))
    (unless (Opts on? o "-n") (sl-background!))
    (%kl-ctl 1 (cu-int->ptr 0) 0)
    (cu-ptr-call (cu-libc-sym "openlog") %kl-ident 0 0)
    (when (> level 0) (%kl-ctl 8 (cu-int->ptr 0) level))
    (sys-signal 1 cu-sig-ign)
    (def sigs (map ts-signal-number
                (list "INT" "TERM" "PIPE" "QUIT" "ABRT" "ALRM" "VTALRM" "XCPU" "XFSZ" "USR1" "USR2")))
    (map (fn (_ n) (Sys catch-signal n)) sigs)
    (lg-send 5 (string-append "klogd started: x-coreutils v" (vi-bundle-version)))
    (guard (_ ())
      (let ((fd (File open %kl-pidfile (list (lit wronly) (lit creat) (lit trunc)) 438)))
        (do (file-write fd (string-append (cu-int->str (sys-getpid)) "\n")) (file-close fd))))
    (def buf (cu-ptr-call (cu-libc-sym "malloc") %kl-size))
    (def sig (%kl-loop buf "" sigs))
    (%kl-ctl 7 (cu-int->ptr 0) 0)
    (%kl-ctl 0 (cu-int->ptr 0) 0)
    (lg-send 5 "klogd: exiting")
    (guard (_ ()) (file-unlink %kl-pidfile))
    (if (= sig 0) 1
      (do (sys-signal sig 0)
          (sys-kill (sys-getpid) sig)
          (+ 128 sig)))))

(def cu-klogd
  (fn (_ argv stdin-thunk)
    (guard (e (if (eq? (Err label e) (lit klogd))
                (do (file-write 2 (string-append "klogd: " (string-append (e msg) "\n"))) 1)
                (error e)))
      (%kl-main argv))))

(provide coreutils/klogd cu-klogd)

; # x-coreutils -- the small tools, as applets
;
; ## cu/dmesg.x -- dmesg: the kernel's ring, printed or cleared
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; util-linux/dmesg.c with busybox's FEATURE_DMESG_PRETTY: the whole ring
; read through klogctl(3), or (4) to clear it after (-c), into a buffer of
; the ring's size or -s, held to 16 KB..16 MB.  Each <PRI> at a line's start
; is dropped unless -r; the output ends in a newline.  -n sets the console's
; level and prints nothing.  The lines are moved down in the C buffer with
; memchr and memmove, so a ring of megabytes is no walk over its bytes.

(module cu/dmesg)

(import cu/cli cu-opts)
(import cu/inetd in-call)
(import cu/prims cu-int->ptr cu-libc-sym cu-ptr-call cu-ptr-ref file-write libc-strerror string-append)
(import cu/syslogd sl-number)

(def %dm-die (fn (_ msg) (Err raise (lit dmesg) msg ())))
(def %dm-ctl (fn (_ cmd buf n) (in-call (cu-ptr-call (cu-libc-sym "klogctl") cmd buf n))))
(def %dm-perror (fn (_) (%dm-die (string-append "klogctl: " (libc-strerror (Err errno-of -1))))))
(def %dm-positive (fn (_ s) (sl-number s 0 0x7FFFFFFF 0x7FFFFFFFFFFFFFFF %dm-die)))

; the address of the first BYTE in the N bytes from AT, or 0
(def %dm-find (fn (_ at byte n) (if (> n 0) (cu-ptr-call (cu-libc-sym "memchr") at byte n) 0)))

; the LEN bytes at BUF with each <...> at a line's start taken out, moved
; down in place: the new length
(def %dm-pretty!
  (fn (_ buf len)
    (def end (+ buf len))
    (def memmove (cu-libc-sym "memmove"))
    (let go ((in buf) (out buf) (start #t))
      (match
        ((>= in end) (- out buf))
        ((if start (= (cu-ptr-ref (cu-int->ptr in) 0 1) 60) #f)
          (let ((gt (%dm-find in 62 (- end in))))
            (go (if (= gt 0) end (+ gt 1)) out #t)))
        (#t
          (let ((nl (%dm-find in 10 (- end in))))
            (let ((k (- (if (= nl 0) end (+ nl 1)) in)))
              (do (cu-ptr-call memmove out in k)
                  (go (+ in k) (+ out k) (not (= nl 0)))))))))))

; the N bytes at BUF to stdout, as many writes as it takes
(def %dm-write
  (fn (self buf n)
    (when (> n 0)
      (let ((w (in-call (cu-ptr-call (cu-libc-sym "write") 1 buf n))))
        (if (< w 0) (%dm-die (string-append "write: " (libc-strerror (Err errno-of -1))))
          (self (+ buf w) (- n w)))))))

(def %dm-main
  (fn (_ argv)
    (def o (cu-opts "dmesg" argv))
    (def s (Opts value o "-s"))
    (def n (Opts value o "-n"))
    (def s-len (if (null? s) 0 (%dm-positive s)))
    (def level (if (null? n) 0 (%dm-positive n)))
    (if (not (null? n))
      (do (unless (= (%dm-ctl 8 (cu-int->ptr 0) level) 0) (%dm-perror)) 0)
      (let ((asked (if (null? s) (%dm-ctl 10 (cu-int->ptr 0) 0) s-len)))
        (def size (match ((< asked 16384) 16384) ((> asked 16777216) 16777216) (#t asked)))
        (def buf (cu-ptr-call (cu-libc-sym "malloc") size))
        (def len (%dm-ctl (if (Opts on? o "-c") 4 3) (cu-int->ptr buf) size))
        (when (< len 0) (%dm-perror))
        (when (> len 0)
          (let ((out (if (Opts on? o "-r") len (%dm-pretty! buf len))))
            (do (%dm-write buf out)
                (when (if (> out 0) (not (= (cu-ptr-ref (cu-int->ptr buf) (- out 1) 1) 10)) #f)
                  (file-write 1 "\n")))))
        (cu-ptr-call (cu-libc-sym "free") buf)
        0))))

(def cu-dmesg
  (fn (_ argv stdin-thunk)
    (guard (e (if (eq? (Err label e) (lit dmesg))
                (do (file-write 2 (string-append "dmesg: " (string-append (e msg) "\n"))) 1)
                (error e)))
      (%dm-main argv))))

(provide cu/dmesg cu-dmesg)

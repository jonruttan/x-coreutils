; # x-coreutils -- the small tools, as applets
;
; ## cu/logread.x -- logread: the messages in syslogd's shared buffer
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; sysklogd/logread.c, as busybox's defconfig builds it (double buffering
; on): the ring syslogd -C writes is attached read-only, the readers'
; semaphore taken while what lies between the oldest whole message and the
; tail is copied out, and each NUL-ended message in the copy written.  -f
; then waits a second at a time for the tail to move and writes what is
; new; -F writes the buffer first, then does as -f.

(module cu/logread)

(import cu/cli cu-opts)
(import cu/inetd in-call)
(import cu/prims bit-and bit-shr byte-len cu-int->ptr cu-libc-sym cu-ptr->str cu-ptr-call cu-ptr-ref
  cu-ptr-set! cu-str->ptr cu-sweep-lines cu-sweep-tick! file-write libc-strerror string-append
  sys-sleep)
(import cu/syslogd sl-key sl-sembuf)

(def %lr-rdn ())                       ; wait for no writer, count a reader
(def %lr-rup ())                       ; the reader gone

(def %lr-die (fn (_ msg) (Err raise (lit logread) msg ())))
(def %lr-errno (fn (_) (libc-strerror (Err errno-of -1))))
(def %lr-call (fn (_ name . args) (in-call (apply cu-ptr-call (pair (cu-libc-sym name) args)))))
(def %lr-sem
  (fn (_ semid ops n what)
    (when (= (%lr-call "semop" semid (cu-str->ptr ops) n) -1)
      (%lr-die (string-append what (string-append ": " (%lr-errno)))))))

; the copy: BUSYBOX's double buffer, in C memory -- an x string ends at
; its first NUL.  HEAD bytes from FROM, then TAIL bytes from the data's
; start, then a NUL; its address
(def %lr-copy
  (fn (_ from head data tail)
    (def total (+ head tail))
    (def buf (cu-ptr-call (cu-libc-sym "malloc") (+ total 1)))
    (cu-ptr-call (cu-libc-sym "memcpy") (cu-int->ptr buf) (cu-int->ptr from) head)
    (when (> tail 0) (cu-ptr-call (cu-libc-sym "memcpy") (cu-int->ptr (+ buf head)) (cu-int->ptr data) tail))
    (cu-ptr-set! (cu-int->ptr buf) total 0 1)
    (pair buf total)))

; each NUL-ended message in the copy C written, and the copy freed
(def %lr-print
  (fn (_ c)
    (let go ((i 0))
      (when (< i (rest c))
        (let ((s (cu-ptr->str (cu-int->ptr (+ (first c) i)))))
          (do (when (> (byte-len s) 0) (file-write 1 s))
              (go (+ i (+ (byte-len s) 1)))))))
    (cu-ptr-call (cu-libc-sym "free") (cu-int->ptr (first c)))))

; one pass over the ring at RAW: from CUR to the tail, read under the
; semaphore; FOLLOW is busybox's -f bit (1) and -F bit (2)
(def %lr-pass
  (fn (self raw semid cur follow)
    (cu-sweep-tick! cu-sweep-lines)
    (%lr-sem semid %lr-rdn 2 "semop[SMrdn]")
    (def p (cu-int->ptr raw))
    (def size (cu-ptr-ref p 0 4))
    (def tail (cu-ptr-ref p 4 4))
    (def data (+ raw 8))
    (def strlen (fn (_ at) (cu-ptr-call (cu-libc-sym "strlen") (cu-int->ptr at))))
    ; where the copy starts: without -f the oldest whole message, past the
    ; one the tail may have cut; with -f the last pass's end
    (def start
      (if (= (bit-and follow 1) 1)
        (if (= cur tail) (lit wait) cur)
        (let ((c (+ cur (strlen (+ data cur)))))
          (if (>= c size)
            (let ((c2 (cu-ptr-call (cu-libc-sym "strnlen") (cu-int->ptr data) tail)))
              (if (= c2 tail) (lit none) (if (>= (+ c2 1) size) 0 (+ c2 1))))
            (if (>= (+ c 1) size) 0 (+ c 1))))))
    (def copy
      (if (if (eq? start (lit wait)) #t (eq? start (lit none))) ()
        (if (< tail start)
          (%lr-copy (+ data start) (- size start) data tail)
          (%lr-copy (+ data start) (- tail start) data 0))))
    (%lr-sem semid %lr-rup 1 "semop[SMrup]")
    (if (eq? start (lit wait))
      (do (sys-sleep 1) (self raw semid cur follow))
      (do (unless (null? copy) (%lr-print copy))
          (let ((next (if (= (bit-and follow 1) 1) follow (bit-shr follow 1))))
            (if (= next 0) 0 (self raw semid tail next)))))))

(def %lr-main
  (fn (_ argv)
    (def o (cu-opts "logread" argv))
    (def follow (+ (if (Opts on? o "-f") 1 0) (if (Opts on? o "-F") 2 0)))
    (set! %lr-rdn (sl-sembuf (list (list 1 0 0) (list 0 1 4096))))
    (set! %lr-rup (sl-sembuf (list (list 0 -1 6144))))
    (def shmid (%lr-call "shmget" sl-key 0 0))
    (when (< shmid 0) (%lr-die (string-append "can't find syslogd buffer: " (%lr-errno))))
    (def raw (cu-ptr-call (cu-libc-sym "shmat") shmid 0 4096))
    (when (= (in-call raw) -1) (%lr-die (string-append "can't access syslogd buffer: " (%lr-errno))))
    (def semid (%lr-call "semget" sl-key 0 0))
    (when (< semid 0)
      (%lr-die (string-append "can't get access to semaphores for syslogd buffer: " (%lr-errno))))
    (%lr-pass raw semid (cu-ptr-ref (cu-int->ptr raw) 4 4) follow)))

(def cu-logread
  (fn (_ argv stdin-thunk)
    (guard (e (if (eq? (Err label e) (lit logread))
                (do (file-write 2 (string-append "logread: " (string-append (e msg) "\n"))) 1)
                (error e)))
      (%lr-main argv))))

(provide cu/logread cu-logread)

; # x-coreutils -- the small tools, as applets
;
; ## cu/sysinfo.x -- hostname, hostid, mountpoint, mknod, mesg, renice, ts
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's (networking/hostname.c, coreutils/hostid.c,
; util-linux/mountpoint.c, coreutils/mknod.c, util-linux/mesg.c,
; util-linux/renice.c, miscutils/ts.c).  Each is a libc call or two through
; the dlopen FFI: gethostname and sethostname, gethostbyname for the names
; and addresses hostname -f, -s, -d and -i show, gethostid, stat and lstat,
; mknod, fchmod, getpriority and setpriority, gettimeofday.  renice, mesg and
; hostid read their words as busybox does, without getopt.

(def %si-lib ())
(def %si-fn (fn (_ name) (%cu-dlsym %si-lib name)))
(def %si-resolve! (fn (_) (if (null? %si-lib) (set! %si-lib (%cu-dlopen () 1)) ())))

; a C int answered by libc's NAME on up to three ARGS, nil filling the rest,
; its top half folded back to negative
(def %si-call
  (fn (_ name . args)
    ; the Kth of ARGS, nil past the end -- walked with null? first, since rest
    ; of an empty list does not raise
    (def walk
      (fn (self k l) (match ((null? l) ()) ((= k 0) (first l)) (#t (self (- k 1) (rest l))))))
    (def at (fn (_ k) (walk k args)))
    (do (%si-resolve!)
        (Sys %sign-fold (%cu-ptr-call (%si-fn name) (at 0) (at 1) (at 2))))))

; errno cleared, before a call whose every answer is a value it may return
(def %si-errno-clear!
  (fn (_)
    (do (%si-resolve!)
        (let ((p (%cu-ptr-call (%si-fn (if os-darwin? "__error" "__errno_location")))))
          (%cu-ptr-set! (%cu-int->ptr p) 0 0 4)))))

(def %si-say (fn (_ applet msg) (file-write 2 (string-concat (list applet ": " msg "\n")))))

; the reason the last failed call left in errno
(def %si-why
  (fn (_ op name) (file-err-text (Err from-errno (Err errno-of -1) op name))))

; --- hostname --------------------------------------------------------------------

(def %si-hostname
  (fn (_)
    (let ((buf (%str-make-raw 256)))
      (do (%cu-ptr-set! (%cu-str->ptr buf) 255 0 1)
          (%si-call "gethostname" buf 255)
          (%cu-cstr-at buf 0 256)))))

; NAME's entry as gethostbyname answers it: (FQDN . ADDRESSES), the addresses
; dotted quads; #f where the name is not known
(def %si-host
  (fn (_ name)
    (do (%si-resolve!)
        (let ((hp (%cu-ptr-call (%si-fn "gethostbyname") name)))
          (if (= hp 0) #f
            (let ((p (%cu-int->ptr hp)))
              (pair (%cu-ptr->str (%cu-int->ptr (%cu-ptr-word p 0)))
                    (if (= (& (%cu-ptr-ref p 20 4) 4294967295) 4)
                      (%si-addrs (%cu-ptr-word p 24)) ()))))))))

; the dotted quads of a NULL-ended list of in_addr pointers at LIST
(def %si-addrs
  (fn (_ list)
    (def go
      (fn (self i acc)
        (let ((a (%cu-ptr-word (%cu-int->ptr list) (* 8 i))))
          (if (= a 0) (reverse acc)
            (self (+ i 1) (pair (%si-quad (%cu-int->ptr a)) acc))))))
    (go 0 ())))

(def %si-quad
  (fn (_ p)
    (%cu-join-with
      (map (fn (_ k) (%cu-int->str (& (%cu-ptr-ref p k 1) 255))) (list 0 1 2 3)) ".")))

(def %si-upto-dot
  (fn (_ s) (let ((d (%dp-find s 0 #\.))) (if (< d 0) s (substring s 0 d)))))

(def %si-after-dot
  (fn (_ s) (let ((d (%dp-find s 0 #\.))) (if (< d 0) () (substring s (+ d 1) (byte-len s))))))

(def %cu-hostname (fn (_ argv stdin-thunk) (%si-hostname-run "hostname" argv)))

; dnsdomainname: hostname's options taken, and -d whatever they are -- the
; domain of the host's full name, nothing when it has none
(def %cu-dnsdomainname
  (fn (_ argv stdin-thunk) (%si-host-show "dnsdomainname" (%si-hostname) #t #f #f)))

(def %si-hostname-run
  (fn (_ applet argv)
    (def o (%cu-opts applet argv))
    (def on (fn (_ a b) (if (Opts on? o a) #t (if (null? b) #f (Opts on? o b)))))
    (def d (on "-d" "--domain"))
    (def f (if d #f (on "-f" "--fqdn")))
    (def i (if (if d #t f) #f (on "-i" ())))
    (def s (on "-s" ()))
    (def file (let ((v (Opts value o "-F"))) (if (null? v) (Opts value o "--file") v)))
    (def name (%si-hostname))
    (match
      ((if d #t (if f #t i)) (%si-host-show applet name d f s))
      (s (do (file-write 1 (string-append (%si-upto-dot name) "\n")) 0))
      ((not (null? file)) (%si-set-from-file applet file))
      ((pair? (Opts operands o)) (%si-set applet (first (Opts operands o))))
      (#t (do (file-write 1 (string-append name "\n")) 0)))))

; -d, -f, -s or -i over NAME's entry
(def %si-host-show
  (fn (_ applet name d f s)
    (let ((h (%si-host name)))
      (match
        ((eq? h #f) (do (%si-say applet (string-append name ": Unknown host")) 1))
        (f (do (file-write 1 (string-append (first h) "\n")) 0))
        (s (do (file-write 1 (string-append (%si-upto-dot (first h)) "\n")) 0))
        (d (let ((dom (%si-after-dot (first h))))
             (do (if (null? dom) () (file-write 1 (string-append dom "\n"))) 0)))
        (#t (do (file-write 1 (string-append (%cu-join-with (rest h) " ") "\n")) 0))))))

(def %si-set
  (fn (_ applet name)
    (if (< (%si-call "sethostname" name (byte-len name)) 0)
      (do (%si-say applet (string-append "sethostname: " (%si-why (lit sethostname) name))) 1)
      0)))

; -F: each word of FILE that is not a comment set in turn, as busybox's
; config_read hands them over
(def %si-set-from-file
  (fn (_ applet file)
    (let ((fd (file-open-read file)))
      (if (< fd 0)
        (do (%si-say applet (string-concat (list "can't open '" file "': "
                                                  (file-err-text (file-open-err fd file)))))
            1)
        (do (file-close fd)
            (let ((words (%si-config-words (File read-all file))))
              (%si-set-each applet words)))))))

(def %si-set-each
  (fn (self applet words)
    (match
      ((null? words) 0)
      ((= (%si-set applet (first words)) 0) (self applet (rest words)))
      (#t 1))))

; the first word of each line, a # starting a comment
(def %si-config-words
  (fn (_ text)
    (filter (fn (_ w) (> (byte-len w) 0))
      (map (fn (_ l)
             (let ((c (%dp-find l 0 #\#)))
               (let ((t (if (< c 0) l (substring l 0 c))))
                 (let ((ws (%cu-words-line t))) (if (null? ws) "" (first ws))))))
           (%cu-lines text)))))

; --- hostid ----------------------------------------------------------------------

(def %cu-hostid
  (fn (_ argv stdin-thunk)
    (if (pair? argv) (%cu-usage "hostid")
      (let ((id (& (%si-call "gethostid") 4294967295)))
        (do (file-write 1 (string-append (%cu-pad-zero (%dp-udigits id 16 #f) 8) "\n")) 0)))))

; --- mountpoint -----------------------------------------------------------------

(def %cu-mountpoint
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "mountpoint" argv))
    (def q (Opts on? o "-q"))
    (if (not (= (length (Opts operands o)) 1)) (%cu-usage "mountpoint")
      (let ((arg (first (Opts operands o))))
        (if (Opts on? o "-x") (%si-mp-device q arg)
          (%si-mp-dir q (Opts on? o "-d") (Opts on? o "-n") arg))))))

(def %si-mp-say
  (fn (_ q msg) (do (if q () (%si-say "mountpoint" msg)) 1)))

(def %si-mp-device
  (fn (_ q arg)
    (let ((st (file-stat-full arg)))
      (match
        ((null? st) (%si-mp-say q (string-append arg ": " (%si-why (lit stat) arg))))
        ((eq? (%cu-stat-get st (lit file-type)) (lit block))
          (let ((dev (%cu-stat-get st (lit rdev))))
            (do (file-write 1 (string-concat (list (%cu-int->str (%cu-dev-major dev)) ":"
                                                  (%cu-int->str (%cu-dev-minor dev)) "\n")))
                0)))
        (#t (%si-mp-say q (string-append arg ": not a block device")))))))

(def %si-mp-dir
  (fn (_ q d n arg)
    (let ((st (file-lstat-full arg)))
      (match
        ((null? st) (%si-mp-say q (string-append arg ": " (%si-why (lit lstat) arg))))
        ((not (eq? (%cu-stat-get st (lit file-type)) (lit dir)))
          (%si-mp-say q (string-append arg ": Not a directory")))
        (#t
          (let ((up (file-stat-full (string-append arg "/.."))))
            (if (null? up)
              (%si-mp-say q (string-concat (list arg "/..: " (%si-why (lit stat) arg))))
              (%si-mp-report q d n arg st up))))))))

(def %si-mp-report
  (fn (_ q d n arg st up)
    (def dev (%cu-stat-get st (lit dev)))
    (def not-mnt
      (if (= dev (%cu-stat-get up (lit dev)))
        (not (= (%cu-stat-get st (lit ino)) (%cu-stat-get up (lit ino)))) #f))
    (do (if d (file-write 1 (string-concat (list (%cu-int->str (%cu-dev-major dev)) ":"
                                                (%cu-int->str (%cu-dev-minor dev)) "\n"))) ())
        (if n (file-write 1 (string-concat (list "UNKNOWN " arg "\n"))) ())
        (if (if q #t (if d #t n)) ()
          (file-write 1 (string-concat (list arg " is " (if not-mnt "not " "") "a mountpoint\n"))))
        (if not-mnt 1 0))))

; --- mknod -----------------------------------------------------------------------

(def %cu-mknod
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "mknod" argv))
    (def ops (Opts operands o))
    (def m (Opts value o "-m"))
    (def mode (if (null? m) 438 (%si-mknod-mode m)))
    (def type (if (< (length ops) 2) () (%si-node-type (first (rest ops)))))
    (match
      ((null? mode) 1)
      ((null? type) (%cu-usage "mknod"))
      ((= type 4096)
        (if (= (length ops) 2) (%si-mknod (first ops) (| mode type) 0 (not (null? m))) (%cu-usage "mknod")))
      ((not (= (length ops) 4)) (%cu-usage "mknod"))
      (#t
        (let ((maj (%cu-range-number "mknod" (%cu-nth 2 ops) 0 4294967295))
              (min (%cu-range-number "mknod" (%cu-nth 3 ops) 0 4294967295)))
          (if (if (null? maj) #t (null? min)) 1
            (%si-mknod (first ops) (| mode type) (%tar-makedev (pair maj min)) (not (null? m)))))))))

; the type a TYPE word names, as S_IFMT bits: b block, c or u character, p fifo
(def %si-node-type
  (fn (_ w)
    (if (= (byte-len w) 0) ()
      (let ((c (byte-at w 0)))
        (match
          ((= c #\b) 24576)
          ((if (= c #\c) #t (= c #\u)) 8192)
          ((= c #\p) 4096)
          (#t ()))))))

; -m's MODE over a=rw, as chmod reads it, no umask in it; nil, said, where it
; is not one
(def %si-mknod-mode
  (fn (_ m)
    (if (%cu-mode-valid? m) (& (%cu-mode-of m 438 #f 0) 4095)
      (do (%si-say "mknod" (string-append "invalid mode '" m "'")) ()))))

; NAME made; with -m, under a umask of 0, so its mode is the one asked for
(def %si-mknod
  (fn (_ name mode dev exact)
    (def old (if exact (%si-call "umask" 0) ()))
    (def r (%si-call "mknod" name mode dev))
    (do (if exact (%si-call "umask" old) ())
        (if (< r 0)
          (do (%si-say "mknod" (string-append name ": " (%si-why (lit mknod) name))) 1)
          0))))

; --- mesg ------------------------------------------------------------------------

(def %cu-mesg
  (fn (_ argv stdin-thunk)
    (def c (if (null? argv) () (let ((w (first argv))) (if (= (byte-len w) 0) 0 (byte-at w 0)))))
    (match
      ((if (pair? argv) (if (pair? (rest argv)) #t (not (if (= c #\y) #t (= c #\n)))) #f)
        (%cu-usage "mesg"))
      ((not (sys-isatty 0)) (do (%si-say "mesg" "not a tty") 1))
      (#t (%si-mesg-tty c)))))

(def %si-mesg-tty
  (fn (_ c)
    (let ((mode (%si-fd-mode 0)))
      (match
        ((null? c)
          (do (file-write 1 (if (= (& mode 18) 0) "is n\n" "is y\n")) 0))
        ((< (%si-call "fchmod" 0 (if (= c #\y) (| mode 16) (& mode 4077))) 0)
          (do (%si-say "mesg" (%si-why (lit fchmod) "stdin")) 1))
        (#t 0)))))

; FD's mode bits, by fstat
(def %si-fd-mode
  (fn (_ fd)
    (let ((p (string-append "/dev/fd/" (%cu-int->str fd))))
      (let ((st (file-stat-full p))) (if (null? st) 0 (& (%cu-stat-get st (lit mode)) 4095))))))

; --- renice ----------------------------------------------------------------------

(def %cu-renice
  (fn (_ argv stdin-thunk)
    (def rel (if (pair? argv) (%si-prefix? (first argv) "-n") #f))
    (def words
      (match
        ((not rel) argv)
        ((= (byte-len (first argv)) 2) (rest argv))
        (#t (pair (substring (first argv) 2 (byte-len (first argv))) (rest argv)))))
    (if (null? words) (%cu-usage "renice")
      (let ((adj (%si-int (first words))))
        (if (null? adj) (do (%si-say "renice" (string-concat (list "invalid number '" (%si-unsigned (first words)) "'"))) 1)
          (%si-renice-each rel adj (rest words) 0 0))))))

(def %si-prefix?
  (fn (_ s p) (if (>= (byte-len s) (byte-len p)) (string=? (substring s 0 (byte-len p)) p) #f)))

; WORD as a decimal int, a sign allowed; nil where it is not one
(def %si-int
  (fn (_ w)
    (def neg (if (> (byte-len w) 0) (= (byte-at w 0) #\-) #f))
    (def digits (if (if neg #t (if (> (byte-len w) 0) (= (byte-at w 0) #\+) #f))
                  (substring w 1 (byte-len w)) w))
    (if (%si-digits? digits)
      (let ((n (%cu-num-prefix digits))) (if neg (- 0 n) n))
      ())))

(def %si-digits?
  (fn (_ s)
    (if (= (byte-len s) 0) #f
      (let go ((i 0))
        (if (>= i (byte-len s)) #t
          (let ((c (byte-at s i))) (if (if (>= c #\0) (<= c #\9) #f) (go (+ i 1)) #f)))))))

; each ID, under the -p, -g or -u before it; WHICH is PRIO_PROCESS 0,
; PRIO_PGRP 1 or PRIO_USER 2
(def %si-renice-each
  (fn (self rel adj words which status)
    (if (null? words) status
      (let ((w (first words)))
        (let ((sw (%si-renice-switch w)))
          (match
            ((null? sw) (self rel adj (rest words) which (%si-renice-one rel adj w which status)))
            ((= (byte-len w) 2) (self rel adj (rest words) sw status))
            (#t (self rel adj (rest words) sw
                  (%si-renice-one rel adj (substring w 2 (byte-len w)) sw status)))))))))

(def %si-renice-switch
  (fn (_ w)
    (if (if (>= (byte-len w) 2) (= (byte-at w 0) #\-) #f)
      (let ((c (byte-at w 1)))
        (match ((= c #\p) 0) ((= c #\g) 1) ((= c #\u) 2) (#t ())))
      ())))

(def %si-renice-one
  (fn (_ rel adj w which status)
    (def who
      (if (= which 2)
        (let ((u (sys-user-id w))) (if (null? u) (do (%si-say "renice" (string-append "unknown user " w)) ()) u))
        (if (%si-digits? w) (%cu-num-prefix w)
          (do (%si-say "renice" (string-concat (list "invalid number '" w "'"))) ()))))
    (if (null? who) 1
      (let ((prio (if rel (%si-getprio which who) 0)))
        (match
          ((null? prio) 1)
          ((< (%si-call "setpriority" which who (+ prio adj)) 0)
            (do (%si-say "renice" (string-append "setpriority: " (%si-why (lit setpriority) ""))) 1))
          (#t status))))))

; the nice value of WHO, errno cleared first since -1 is one; nil, said, on
; failure
(def %si-getprio
  (fn (_ which who)
    (do (%si-resolve!)
        (%si-errno-clear!)
        (let ((p (%si-call "getpriority" which who)))
          (if (if (= p -1) (not (= (Err errno-of -1) 0)) #f)
            (do (%si-say "renice" (string-append "getpriority: " (%si-why (lit getpriority) ""))) ())
            p)))))

; --- ts --------------------------------------------------------------------------

(def %cu-ts
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "ts" argv))
    (def i (Opts on? o "-i"))
    (def s (Opts on? o "-s"))
    (def ops (Opts operands o))
    (if (> (length ops) 1) (%cu-usage "ts")
      (let ((fmt (if (pair? ops) (first ops) (if (if i #t s) "%H:%M:%S" "%b %d %H:%M:%S"))))
        (%si-ts-run i s fmt stdin-thunk)))))

; the time now, as (SECONDS . MICROSECONDS)
(def %si-now
  (fn (_)
    (let ((tv (%str-make-raw 16)))
      (do (%si-call "gettimeofday" tv 0)
          (let ((p (%cu-str->ptr tv)))
            (pair (%cu-ptr-word p 0) (& (%cu-ptr-ref p 8 4) 4294967295)))))))

; NOW less BASE, borrowing a second where the microseconds go below zero
(def %si-elapsed
  (fn (_ now base)
    (let ((us (- (rest now) (rest base))))
      (if (< us 0) (pair (- (- (first now) (first base)) 1) (+ us 1000000))
        (pair (- (first now) (first base)) us)))))

; FMT with a %.S or %.s at its end cut to %S or %s: (FORMAT . FRACTION?)
(def %si-ts-format
  (fn (_ fmt)
    (if (if (%gz-ends? fmt "%.S") #t (%gz-ends? fmt "%.s"))
      (pair (string-append (substring fmt 0 (- (byte-len fmt) 2)) (substring fmt (- (byte-len fmt) 1) (byte-len fmt))) #t)
      (pair fmt #f))))

(def %si-ts-run
  (fn (_ i s fmt stdin-thunk)
    (def ff (%si-ts-format fmt))
    (def base (list (%si-now)))
    (def stamp
      (fn (_ line)
        (let ((now (%si-now)))
          (let ((t (if (if i #t s) (%si-elapsed now (first base)) now)))
            (do (if i (%set-first! base now) ())
                (let ((secs (first t)))
                  (string-append
                    (%cu-date-fmt (first ff) (%cu-date-split secs (if i #t s)) secs)
                    (if (rest ff) (string-append "." (%cu-pad-zero (%cu-int->str (rest t)) 6)) "")
                    " " line)))))))
    (rest
      (%cu-fold-lines-said () stdin-thunk (%cu-says "ts")
        (fn (_ block st)
          (do (%si-ts-block stamp block) st))
        ()))))

; each line of BLOCK stamped and put out, a last line with no newline left
; without one
(def %si-ts-block
  (fn (_ stamp block)
    (def nl (if (> (byte-len block) 0) (= (byte-at block (- (byte-len block) 1)) 10) #f))
    (def go
      (fn (self ls)
        (if (null? ls) ()
          (do (file-write 1 (stamp (first ls)))
              (if (if (null? (rest ls)) (not nl) #f) () (file-write 1 "\n"))
              (self (rest ls))))))
    (go (%cu-lines block))))

; W less a leading sign, as busybox's xatoi quotes the number it could not read
(def %si-unsigned
  (fn (_ w)
    (if (if (> (byte-len w) 0) (if (= (byte-at w 0) #\-) #t (= (byte-at w 0) #\+)) #f)
      (substring w 1 (byte-len w)) w)))

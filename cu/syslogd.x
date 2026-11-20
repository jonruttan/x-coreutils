; # x-coreutils -- the small tools, as applets
;
; ## cu/syslogd.x -- syslogd: the system log daemon
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; sysklogd/syslogd.c, as busybox's defconfig builds it: a read of /dev/log
; takes at most 255 bytes; its trailing newlines and NULs go, and each piece
; between NULs is a message, its <PRI> read, a newline made a space and a
; control byte but tab written ^X.  A message's own "Mmm dd hh:mm:ss " stamp
; is kept unless -t; the line is "STAMP HOST FAC.PRIO MSG", or "STAMP MSG"
; with -S.  The rules of -f FILE, else /etc/syslog.conf where it exists,
; send a line to every file whose selector takes it; a line no rule takes
; and more urgent than -l goes to the -C shared buffer or to -O FILE
; (/var/log/messages; - is standard output), which is reopened once a
; second and rotated past -s KB, -b copies kept.  -K writes each line to
; /dev/kmsg instead; -R HOST[:PORT] sends each datagram on over UDP, and
; then the lines are kept here only with -L.  -D drops a datagram the same
; as the last.  Without -n the daemon goes to the background, in /.

(module cu/syslogd)

(import cu/cli cu-opts cu-optional cu-usage)
(import cu/date cu-date-fmt cu-date-split)
(import cu/inetd in-call in-dontwait in-lines in-tokens-max)
(import cu/logger lg-facilities lg-priorities)
(import cu/ntpd nt-family nt-host2sockaddr)
(import cu/prims append bit-and bit-or bit-shl bit-shr byte-at byte-len cu-cstr-at cu-int->ptr cu-int->str
  cu-libc-sym cu-ptr-call cu-ptr-ref cu-ptr-set! cu-sig-ign cu-stat-get cu-str->ptr
  cu-sweep-lines cu-sweep-tick!
  date-now-unix file-close file-fstat-full file-read-all file-rename file-unlink
  file-readlink file-write hx-strtoul length libc-strerror map reverse str-make-raw
  string-append string=?
  substring sys-close sys-dup2 sys-exit sys-fork sys-getpid sys-kill sys-poll
  sys-signal)
(import cu/signal ts-signal-number)
(import cu/vi vi-bundle-version)

(def %sl-max-read 256)                ; CONFIG_FEATURE_SYSLOGD_READ_BUFFER_SIZE
(def sl-key 0x414E4547)               ; "GENA", the key logread reads too
(def %sl-pidfile "/var/run/syslogd.pid")
(def %sl-dns-wait 120)

; the run's settings and state
(def %sl-opts ())
(def %sl-level 8)
(def %sl-file-size (* 200 1024))
(def %sl-rotate 1)
(def %sl-shm-size (* 16 1024))
(def %sl-host "")
(def %sl-out ())                       ; -O's file
(def %sl-rules ())                     ; (PRIOMAPS . FILE), in the config's order
(def %sl-remotes ())
(def %sl-shm 0)                        ; the shared buffer's address, 0 when none
(def %sl-shmid -1)
(def %sl-semid -1)
(def %sl-kmsg -1)

(def %sl-die (fn (_ msg) (Err raise (lit syslogd) msg ())))
(def %sl-say (fn (_ msg) (file-write 2 (%str-concat (list "syslogd: " msg "\n")))))
(def %sl-on? (fn (_ f) (Opts on? %sl-opts f)))

; libc's NAME on ARGS, its int answer signed
(def %sl-call (fn (_ name . args) (in-call (apply cu-ptr-call (pair (cu-libc-sym name) args)))))
(def %sl-errno (fn (_) (libc-strerror (Err errno-of -1))))
(def %sl-perror (fn (_ what) (%sl-die (%str-concat (list what ": " (%sl-errno))))))

(def %sl-alnum?
  (fn (_ c) (match ((if (>= c #\0) (<= c #\9) #f) #t) ((if (>= c #\a) (<= c #\z) #f) #t)
                   ((if (>= c #\A) (<= c #\Z) #f) #t) (#t #f))))

; xatou_range and xatoul_range: S in decimal, nothing before or after it, at
; most LIMIT, from LO to HI
(def %sl-number
  (fn (_ s lo hi limit)
    (def c (if (> (byte-len s) 0) (byte-at s 0) 0))
    (def r (if (if (>= c #\0) (<= c #\9) #f) (hx-strtoul s 0 10 limit) (pair 0 0)))
    (def range (fn (_) (%sl-die (%str-concat (list "number " s " is not in " (cu-int->str lo) ".." (cu-int->str hi) " range")))))
    (match
      ((if (= (rest r) 0) #t (if (null? (first r)) #t (< (rest r) (byte-len s))))
        (%sl-die (%str-concat (list "invalid number '" s "'"))))
      ((if (< (first r) lo) #t (> (first r) hi)) (range))
      (#t (first r)))))

; --- the names --------------------------------------------------------------------

(def %sl-by-name
  (fn (_ name table) (List find (fn (_ e) (string=? (first e) name)) table)))

(def %sl-by-val
  (fn (_ v table) (List find (fn (_ e) (= (rest e) v)) table)))

; parse_fac_prio_20: FAC.PRIO, or <PRI> where the facility has no name
(def %sl-fac-prio
  (fn (_ pri)
    (def fac (%sl-by-val (bit-and pri 1016) lg-facilities))
    (if (null? fac) (%str-concat (list "<" (cu-int->str pri) ">"))
      (%str-concat (list (first fac) "." (first (%sl-by-val (bit-and pri 7) lg-priorities)))))))

; --- the files ----------------------------------------------------------------------

; a log file: its path, descriptor, last second written, size, and whether
; it is a regular file
(def %sl-file (fn (_ path) (Vector build 5 (fn (_ i) (match ((= i 0) path) ((= i 1) -1) (#t 0))))))
(def %sf (fn (_ f i) (Vector ref i f)))
(def %sf! (fn (_ f i v) (Vector set! i v f)))

(def %sl-open!
  (fn (_ f)
    (def fd (guard (_ -1) (File open (%sf f 0) (list (lit wronly) (lit creat) (lit noctty) (lit append) (lit nonblock)) 438)))
    (%sf! f 1 fd)
    (when (>= fd 0)
      (let ((st (file-fstat-full fd)))
        (do (%sf! f 4 (if (null? st) #f (eq? (cu-stat-get st (lit file-type)) (lit file))))
            (%sf! f 3 (if (null? st) 0 (cu-stat-get st (lit size)))))))
    fd))

; rotation: F.N-1 to F.N, down to F to F.0, and F gone
(def %sl-rotate!
  (fn (_ f)
    (def path (%sf f 0))
    (def dot (fn (_ i) (string-append path (string-append "." (cu-int->str i)))))
    (when (> %sl-rotate 0)
      (let go ((i (- %sl-rotate 1)))
        (when (> i 0)
          (do (guard (_ ()) (file-rename (dot (- i 1)) (dot i))) (go (- i 1)))))
      (guard (_ ()) (file-rename path (dot 0))))
    (guard (_ ()) (file-unlink path))
    (sys-close (%sf f 1))))

; log_locally: MSG to F, opened again each second; where it cannot be
; opened, to the console, else standard error
(def %sl-local
  (fn (_ now msg f)
    (def opened
      (match
        ((> (%sf f 1) 1)
          (if (= (%sf f 2) now) #t
            (do (%sf! f 2 now) (sys-close (%sf f 1)) (>= (%sl-open! f) 0))))
        ((= (%sf f 1) 1) #t)
        ((string=? (%sf f 0) "-") (do (%sf! f 1 1) #t))
        (#t (>= (%sl-open! f) 0))))
    (if (not opened)
      (let ((fd (guard (_ -1) (File open "/dev/console" (list (lit wronly) (lit noctty) (lit nonblock))))))
        (do (file-write (if (< fd 0) 2 fd) msg)
            (when (>= fd 0) (sys-close fd))))
      (do (when (if (> %sl-file-size 0) (if (%sf f 4) (> (%sf f 3) %sl-file-size) #f) #f)
            (do (%sl-rotate! f)
                (when (< (%sl-open! f) 0)
                  (let ((fd (guard (_ -1) (File open "/dev/console" (list (lit wronly) (lit noctty) (lit nonblock))))))
                    (do (file-write (if (< fd 0) 2 fd) msg)
                        (when (>= fd 0) (sys-close fd)))))))
          (when (>= (%sf f 1) 0)
            (let ((n (guard (_ -1) (file-write (%sf f 1) msg))))
              (when (> n 0) (%sf! f 3 (+ (%sf f 3) n)))))))))

; --- the shared buffer --------------------------------------------------------------

; a sembuf per (NUMBER OP FLAGS), three 16-bit words; logread builds its own
(def sl-sembuf
  (fn (_ ops)
    (def b (str-make-raw (* 6 (length ops))))
    (let go ((l ops) (at 0))
      (unless (null? l)
        (do (cu-ptr-set! (cu-str->ptr b) at (first (first l)) 2)
            (cu-ptr-set! (cu-str->ptr b) (+ at 2) (bit-and (first (rest (first l))) 65535) 2)
            (cu-ptr-set! (cu-str->ptr b) (+ at 4) (first (rest (rest (first l)))) 2)
            (go (rest l) (+ at 6)))))
    b))

; made at the start, not at load: an image keeps no zeroed buffer
(def %sl-wdn ())
(def %sl-wup ())

; ipcsyslog_init: the buffer made and cleared, its size word set; the
; semaphores made, or found where logread's syslogd left them
(def %sl-ipc-init!
  (fn (_)
    (set! %sl-wdn (sl-sembuf (list (list 0 0 0) (list 1 0 0) (list 1 1 0))))
    (set! %sl-wup (sl-sembuf (list (list 1 -1 2048))))
    (set! %sl-shmid (%sl-call "shmget" sl-key %sl-shm-size 932))
    (when (< %sl-shmid 0) (%sl-perror "shmget"))
    (def at (cu-ptr-call (cu-libc-sym "shmat") %sl-shmid 0 0))
    (when (= (in-call at) -1) (%sl-perror "shmat"))
    (set! %sl-shm at)
    (cu-ptr-call (cu-libc-sym "memset") (cu-int->ptr at) 0 %sl-shm-size)
    (cu-ptr-set! (cu-int->ptr at) 0 (- %sl-shm-size 9) 4)
    (set! %sl-semid (%sl-call "semget" sl-key 2 2047))
    (when (< %sl-semid 0)
      (do (when (= (Err errno-of -1) 17) (set! %sl-semid (%sl-call "semget" sl-key 2 0)))
          (when (< %sl-semid 0) (%sl-perror "semget"))))))

; log_to_shmem: MSG and its NUL at the tail, around the end of the ring
(def %sl-shm-write!
  (fn (_ msg)
    (when (= (%sl-call "semop" %sl-semid (cu-str->ptr %sl-wdn) 3) -1) (%sl-perror "SMwdn"))
    (def p (cu-int->ptr %sl-shm))
    (def size (cu-ptr-ref p 0 4))
    (def n (byte-len msg))
    ; bytes FROM to FROM+K of MSG and its NUL at AT: the NUL set by hand,
    ; a string carries none of its own
    (def put
      (fn (_ at from k)
        (def c (if (> (+ from k) n) (- n from) k))
        (when (> c 0)
          (cu-ptr-call (cu-libc-sym "memcpy") (cu-int->ptr (+ %sl-shm 8 at)) (cu-str->ptr (substring msg from (+ from c))) c))
        (when (> (+ from k) n) (cu-ptr-set! p (+ 8 at c) 0 1))))
    (let go ((from 0) (len (+ n 1)))
      (let ((tail (cu-ptr-ref p 4 4)))
        (if (< (+ tail len) size)
          (do (put tail from len) (cu-ptr-set! p 4 (+ tail len) 4))
          (let ((k (- size tail)))
            (do (put tail from k) (cu-ptr-set! p 4 0 4) (go (+ from k) (- len k)))))))
    (when (= (%sl-call "semop" %sl-semid (cu-str->ptr %sl-wup) 1) -1) (%sl-perror "SMwup"))))

(def %sl-ipc-cleanup!
  (fn (_)
    (when (>= %sl-shmid 0)
      (do (%sl-call "shmdt" (cu-int->ptr %sl-shm))
          (%sl-call "shmctl" %sl-shmid 0 0)))
    (when (>= %sl-semid 0) (%sl-call "semctl" %sl-semid 0 0 0))))

; --- a message ----------------------------------------------------------------------

; whether MSG begins "Mmm dd hh:mm:ss "
(def %sl-stamped?
  (fn (_ msg)
    (if (>= (byte-len msg) 16)
      (List all? (fn (_ e) (= (byte-at msg (first e)) (rest e)))
        (list (pair 3 32) (pair 6 32) (pair 9 #\:) (pair 12 #\:) (pair 15 32)))
      #f)))

; timestamp_and_log
(def %sl-log
  (fn (_ pri msg check)
    (def own (if check (%sl-stamped? msg) #f))
    (def now (date-now-unix))
    (def stamp (if (if own (not (%sl-on? "-t")) #f) (substring msg 0 15)
                 (cu-date-fmt "%b %e %H:%M:%S" (cu-date-split now #f) now)))
    (def text (if own (substring msg 16 (byte-len msg)) msg))
    (if (%sl-on? "-K")
      (file-write %sl-kmsg (%str-concat (list "<" (cu-int->str pri) ">" text "\n")))
      (let ((line (if (%sl-on? "-S") (%str-concat (list stamp " " text "\n"))
                    (%str-concat (list stamp " " %sl-host " " (%sl-fac-prio pri) " " text "\n"))))
            (fac (bit-shr (bit-and pri 1016) 3)))
        (def hit
          (List fold
            (fn (_ acc r)
              (if (if (< fac 24) (> (bit-and (Vector ref fac (first r)) (bit-shl 1 (bit-and pri 7))) 0) #f)
                (do (%sl-local now line (rest r)) #t)
                acc))
            #f %sl-rules))
        (when (if (not hit) (< (bit-and pri 7) %sl-level) #f)
          (if (if (%sl-on? "-C") (> %sl-shm 0) #f)
            (%sl-shm-write! line)
            (%sl-local now line %sl-out)))))))

(def %sl-local? (fn (_) (if (null? (Opts values %sl-opts "-R")) #t (%sl-on? "-L"))))

(def %sl-internal
  (fn (_ msg) (when (%sl-local?) (%sl-log 46 msg #f))))

; bb_strtou at I of S, in decimal: (VALUE . END), VALUE -1 where it fails
(def %sl-strtou
  (fn (_ s i)
    (def n (byte-len s))
    (if (if (< i n) (not (%sl-alnum? (byte-at s i))) #t) (pair -1 i)
      (let ((r (hx-strtoul s i 10 4294967295)))
        (pair (if (null? (first r)) -1 (if (if (< (rest r) n) (%sl-alnum? (byte-at s (rest r))) #f) -1 (first r)))
              (rest r))))))

; one message of S from I to its NUL or END: its <PRI> read, its controls
; escaped; the place after it
(def %sl-one
  (fn (_ s i end)
    (def lt? (if (< i end) (= (byte-at s i) #\<) #f))
    (def parsed (if lt? (%sl-strtou s (+ i 1)) (pair 13 i)))
    (def p (if (if lt? (if (< (rest parsed) end) (= (byte-at s (rest parsed)) #\>) #f) #f) (+ (rest parsed) 1) (rest parsed)))
    (def pri (if (if (< (first parsed) 0) #t (> (first parsed) 1023)) 13 (first parsed)))
    (let go ((k p) (acc ()))
      (if (if (>= k end) #t (= (byte-at s k) 0))
        (do (let ((b (reverse acc))) (%sl-log pri (bytes->str b) #t))
            (+ k 1))
        (let ((c (byte-at s k)))
          (match
            ((= c 10) (go (+ k 1) (pair 32 acc)))
            ((if (< c 32) (not (= c 9)) #f) (go (+ k 1) (pair (+ c 64) (pair #\^ acc))))
            (#t (go (+ k 1) (pair c acc)))))))))

; split_escape_and_log: each piece of the first END bytes of S
(def %sl-split
  (fn (_ s end)
    (let go ((i 0)) (when (< i end) (go (%sl-one s i end))))))

; --- the remote hosts -----------------------------------------------------------------

; a remote host: its name, socket, address, last lookup
(def %sl-remote (fn (_ name) (Vector build 4 (fn (_ i) (match ((= i 0) name) ((= i 1) -1) ((= i 2) ()) (#t (- (%sl-sec) (+ %sl-dns-wait 1))))))))
(def %sl-sec (fn (_) (date-now-unix)))

(def %sl-resolve!
  (fn (_ rh)
    (when (null? (Vector ref 2 rh))
      (let ((now (%sl-sec)))
        (when (>= (- now (Vector ref 3 rh)) %sl-dns-wait)
          (do (Vector set! 3 now rh)
              (Vector set! 2 (nt-host2sockaddr (Vector ref 0 rh) 514 %sl-say) rh)))))
    (if (null? (Vector ref 2 rh)) -1
      (%sl-call "socket" (nt-family (first (Vector ref 2 rh))) 2 0))))

(def %sl-reset-errnos (if os-darwin? (list 54 57 32) (list 104 107 32)))
(def %sl-nosignal (if os-darwin? 0 16384))

(def %sl-send!
  (fn (_ rh data n)
    (when (< (Vector ref 1 rh) 0) (Vector set! 1 (%sl-resolve! rh) rh))
    (when (>= (Vector ref 1 rh) 0)
      (let ((a (Vector ref 2 rh)))
        (when (= (%sl-call "sendto" (Vector ref 1 rh) (cu-str->ptr data) n (bit-or in-dontwait %sl-nosignal)
                   (cu-str->ptr (first a)) (first (rest a))) -1)
          (when (List any? (fn (_ e) (= e (Err errno-of -1))) %sl-reset-errnos)
            (do (sys-close (Vector ref 1 rh)) (Vector set! 1 -1 rh) (Vector set! 2 () rh))))))))

; --- the config -----------------------------------------------------------------------

; one selector, FAC[,FAC].[!][=]PRIO, merged into MAPS; #f where it is bad
(def %sl-selector!
  (fn (_ maps sel)
    (def dot (Str8 index-of "." sel))
    (def t0 (if (null? dot) "" (substring sel (+ dot 1) (byte-len sel))))
    (def neg (Str8 starts? "!" t0))
    (def t1 (if neg (substring t0 1 (byte-len t0)) t0))
    (def single (Str8 starts? "=" t1))
    (def t (if single (substring t1 1 (byte-len t1)) t1))
    (def all (Str8 starts? "*" t))
    (def code (if all () (%sl-by-name t lg-priorities)))
    (def none (if (null? code) #f (= (rest code) 16)))
    (def primap
      (match (all 255)
             ((if (null? code) #t none) 0)
             (#t (let go ((b (bit-shl 1 (rest code))) (m 0))
                   (let ((m2 (bit-or m b)))
                     (if (if single #t (= (bit-shr b 1) 0))
                       (if neg (- 255 m2) m2)
                       (go (bit-shr b 1) m2)))))))
    (def facs (if (null? dot) "" (substring sel 0 dot)))
    ; the facilities' numbers, mark's passed over; nil where one has no name
    (def facmap
      (if (Str8 starts? "*" facs) (List range 0 24)
        (let go ((l (Str8 split "," facs)) (acc (list (lit ok))))
          (if (null? l) acc
            (let ((c (%sl-by-name (first l) lg-facilities)))
              (match ((null? c) ())
                     ((= (rest c) 192) (go (rest l) acc))
                     (#t (go (rest l) (pair (bit-shr (rest c) 3) acc)))))))))
    (if (if (null? dot) #t (if (if all #f (null? code)) #t (null? facmap))) #f
      (do (map (fn (_ i)
                 (unless (eq? i (lit ok))
                   (Vector set! i (if (if neg #t none) (bit-and (Vector ref i maps) primap)
                                    (bit-or (Vector ref i maps) primap)) maps)))
               facmap)
          #t))))

; parse_syslogdcfg: FILE's rules, or /etc/syslog.conf's where it exists
(def %sl-config!
  (fn (_ file)
    (def path (if (null? file) "/etc/syslog.conf" file))
    (def text (guard (_ ()) (file-read-all path)))
    (when (if (null? text) (not (null? file)) #f)
      (%sl-die (%str-concat (list "can't open '" path "': " (%sl-errno)))))
    (unless (null? text)
      (map (fn (_ l)
             (let ((t (in-tokens-max (rest l) 3)))
               (match
                 ((null? t) ())
                 ((< (length t) 2)
                   (%sl-die (%str-concat (list "bad line " (cu-int->str (first l)) ": 1 tokens found, 2 needed"))))
                 (#t (%sl-rule! path (first l) t)))))
           (in-lines text)))))

(def %sl-rule!
  (fn (_ path lineno t)
    (def bad (fn (_) (%sl-die (%str-concat (list "error in '" path "' at line " (cu-int->str lineno))))))
    (when (> (length t) 2) (bad))
    (def maps (Vector make 24 0))
    (unless (List all? (fn (_ s) (%sl-selector! maps s)) (Str8 split ";" (first t))) (bad))
    (def name (first (rest t)))
    (def f (match ((string=? (%sf %sl-out 0) name) %sl-out)
                  (#t (let ((r (List find (fn (_ r) (string=? (%sf (rest r) 0) name)) %sl-rules)))
                        (if (null? r) (%sl-file name) (rest r))))))
    (set! %sl-rules (append %sl-rules (list (pair maps f))))))

; --- the daemon ---------------------------------------------------------------------

(def %sl-hostname
  (fn (_)
    (let ((buf (str-make-raw 256)))
      (do (cu-ptr-set! (cu-str->ptr buf) 255 0 1)
          (cu-ptr-call (cu-libc-sym "gethostname") (cu-str->ptr buf) 255)
          (let ((h (cu-cstr-at buf 0 256)))
            (let ((d (Str8 index-of "." h)))
              (let ((h2 (if (null? d) h (substring h 0 d))))
                (if (> (byte-len h2) 64) (substring h2 0 64) h2))))))))

; create_socket: /dev/log, or what it links to, made afresh; then on fd 0
(def %sl-socket!
  (fn (_)
    (def path (%sl-follow "/dev/log" 0))
    (guard (_ ()) (file-unlink path))
    (def fd (guard (e (%sl-die (string-append "bind: " (%sl-errno)))) (Socket unix-dgram-bind path)))
    (cu-ptr-call (cu-libc-sym "chmod") "/dev/log" 438)
    (sys-dup2 fd 0)
    (when (> fd 0) (sys-close fd))))

; one datagram's text: its trailing NULs and newlines gone, nil where none is left
(def %sl-trim
  (fn (_ buf n)
    (match ((= n 0) ())
           ((if (= (byte-at buf (- n 1)) 0) #t (= (byte-at buf (- n 1)) 10)) (%sl-trim buf (- n 1)))
           (#t (substring buf 0 n)))))

; the read loop, to a signal caught -- its number -- or a read that failed
(def %sl-receive
  (fn (_ last sigs)
    (cu-sweep-tick! cu-sweep-lines)
    (def sig (List find (fn (_ n) (Sys take-signal n)) sigs))
    (def ready (if (null? sig) (sys-poll (list (pair 0 (list (lit in)))) 500) ()))
    (def r (if (null? ready) () (guard (_ (lit failed)) (Socket recv-run 0 (- %sl-max-read 1)))))
    (def s (if (pair? r) (%sl-trim (first r) (rest r)) ()))
    (match
      ((not (null? sig)) sig)
      ((eq? r (lit failed)) r)
      ((null? s) (%sl-receive last sigs))
      ((if (%sl-on? "-D") (if (null? last) #f (string=? last s)) #f) (%sl-receive last sigs))
      (#t (do (unless (null? %sl-remotes)
                (let ((out (string-append s "\n")))
                  (map (fn (_ rh) (%sl-send! rh out (byte-len out))) %sl-remotes)))
              (when (%sl-local?) (%sl-split s (byte-len s)))
              (%sl-receive s sigs))))))

; xmalloc_follow_symlinks: where PATH's links end
(def %sl-follow
  (fn (_ path k)
    (def to (if (< k 20) (guard (_ ()) (file-readlink path)) ()))
    (match ((null? to) path)
           ((Str8 starts? "/" to) (%sl-follow to (+ k 1)))
           (#t (let ((slash (Str8 last-index-of "/" path)))
                 (%sl-follow (if (null? slash) to (string-append (substring path 0 (+ slash 1)) to)) (+ k 1)))))))

(def %sl-daemon
  (fn (_)
    (def sigs (map ts-signal-number (list "TERM" "INT")))
    (map (fn (_ n) (Sys catch-signal n)) sigs)
    (sys-signal 1 cu-sig-ign)
    (%sl-socket!)
    (when (%sl-on? "-C") (%sl-ipc-init!))
    (when (%sl-on? "-K")
      (do (set! %sl-kmsg (guard (_ -1) (File open "/dev/kmsg" (list (lit wronly)))))
          (when (< %sl-kmsg 0) (%sl-die (%str-concat (list "can't open '/dev/kmsg': " (%sl-errno)))))))
    (%sl-internal (string-append "syslogd started: x-coreutils v" (vi-bundle-version)))
    (guard (_ ())
      (let ((fd (File open %sl-pidfile (list (lit wronly) (lit creat) (lit trunc)) 438)))
        (do (file-write fd (string-append (cu-int->str (sys-getpid)) "\n")) (file-close fd))))
    (def end (%sl-receive () sigs))
    (def sig (match ((eq? end (lit failed)) (do (%sl-say (string-append "read from /dev/log: " (%sl-errno))) 0))
                    (#t end)))
    (%sl-internal "syslogd exiting")
    (guard (_ ()) (file-unlink %sl-pidfile))
    (%sl-ipc-cleanup!)
    (when (>= %sl-kmsg 0) (sys-close %sl-kmsg))
    (if (= sig 0) 1
      (do (sys-signal sig 0)
          (sys-kill (sys-getpid) sig)
          (+ 128 sig)))))

(def %sl-main
  (fn (_ argv)
    (def o (cu-opts "syslogd" argv))
    (set! %sl-opts o)
    (if (not (null? (Opts operands o))) (cu-usage "syslogd")
      (do (def c (rest (cu-optional "syslogd" argv)))
          (let ((l (Opts value o "-l"))) (unless (null? l) (set! %sl-level (%sl-number l 1 8 0xFFFFFFFF))))
          (let ((s (Opts value o "-s"))) (unless (null? s) (set! %sl-file-size (* 1024 (%sl-number s 0 2097151 0xFFFFFFFF)))))
          (let ((b (Opts value o "-b"))) (unless (null? b) (set! %sl-rotate (%sl-number b 0 99 0xFFFFFFFF))))
          (unless (null? c) (set! %sl-shm-size (* 1024 (%sl-number c 4 2097151 0x7FFFFFFFFFFFFFFF))))
          (set! %sl-remotes (reverse (map %sl-remote (Opts values o "-R"))))
          (set! %sl-out (%sl-file (Opts value o "-O" "/var/log/messages")))
          (%sl-config! (Opts value o "-f"))
          (set! %sl-host (%sl-hostname))
          (unless (%sl-on? "-n")
            (do
                (when (> (sys-fork) 0) (sys-exit 0))
                (cu-ptr-call (cu-libc-sym "setsid"))
                (Sys chdir "/")))
          (%sl-daemon)))))

(def cu-syslogd
  (fn (_ argv stdin-thunk)
    (guard (e (if (eq? (Err label e) (lit syslogd))
                (do (%sl-say (e msg)) 1)
                (error e)))
      (%sl-main argv))))

(provide cu/syslogd cu-syslogd sl-key sl-sembuf)

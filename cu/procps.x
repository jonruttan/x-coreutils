; # x-coreutils -- the small tools, as applets
;
; ## cu/procps.x -- uptime, free, ps, pidof, pgrep, pkill, lsof
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's procps tools that read the machine rather than a process: uptime
; (procps/uptime.c) and free (procps/free.c).  What they print comes from
; x/sys/host through the host-* doors in cu/prims.x, which read the same
; records on Linux and Darwin -- busybox's own sources, sysinfo(2) and
; /proc/meminfo, on Linux.  The layouts are busybox's to the space.
;
; uptime's clock is local time, as busybox's localtime gives it: (Date local)
; reads the zone TZ names, through the C library.  The users counted are the
; utmpx sessions of type USER_PROCESS with a user name, as busybox counts them.
;
; free on Darwin has no shared, buffers, reclaimable or available: each counts
; as busybox counts a /proc/meminfo line that is not there, 0, and the three it
; looks for not all being there adds its `-/+ buffers/cache:` line.

; A divided by B, the remainder dropped: the bundle has no quotient
(def %ps-div (fn (_ a b) (/ (- a (% a b)) b)))

; --- uptime -----------------------------------------------------------------

(def %cu-uptime
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "uptime" argv))
    ; busybox's uptime reads no operands, and refuses none
    (do (display
          (if (Opts on? o "-s")
            (%ps-boot-line (host-boot-time))
            (let ((now (date-now-unix)))
              (%ps-uptime-line now (- now (host-boot-time))
                (length (host-users)) (host-load-centi)))))
        0)))

; uptime -s: when the machine booted, as YYYY-MM-DD HH:MM:SS
(def %ps-boot-line
  (fn (_ boot)
    (def d (Date local boot))
    (def two (fn (_ k) (cu-pad-zero (cu-int->str (Assoc get k d)) 2)))
    (string-concat
      (list (cu-pad-zero (cu-int->str (Assoc get (lit year) d)) 4)
            "-" (two (lit month)) "-" (two (lit day))
            " " (two (lit hour)) ":" (two (lit minute)) ":" (two (lit second)) "\n"))))

; uptime's line: the time NOW, the UP seconds since boot in days, hours and
; minutes, the USERS logged in and the LOADS, three hundredths
(def %ps-uptime-line
  (fn (_ now up users loads)
    (def d (Date local now))
    (def two (fn (_ n) (cu-pad-zero (cu-int->str n) 2)))
    (def days (%ps-div up 86400))
    (def minutes (%ps-div up 60))
    (def hours (% (%ps-div minutes 60) 24))
    (def load (fn (_ c) (string-append (cu-int->str (%ps-div c 100))
                          (string-append "." (two (% c 100))))))
    (string-concat
      (list " " (two (Assoc get (lit hour) d)) ":" (two (Assoc get (lit minute) d))
            ":" (two (Assoc get (lit second) d)) " up "
            (if (= days 0) ""
              (string-concat (list (cu-int->str days) " day" (if (= days 1) "" "s") ", ")))
            (if (= hours 0)
              (string-append (cu-int->str (% minutes 60)) " min")
              (string-concat (list (cu-pad-left (cu-int->str hours) 2) ":"
                                   (two (% minutes 60)))))
            ",  " (cu-int->str users) " users"
            ",  load average: " (load (first loads))
            ", " (load (first (rest loads)))
            ", " (load (first (rest (rest loads)))) "\n"))))

; --- free -------------------------------------------------------------------

(def %cu-free
  (fn (_ argv stdin-thunk)
    ; the guard has refused a letter free does not know
    (cu-opts "free" argv)
    (do (display (%ps-free-text (host-memory) (%ps-free-unit argv))) 0)))

; The unit free shows, from ARGV as busybox reads it: its first word alone,
; and of that the letter after the dash.  0 is -h's, human-readable.
(def %ps-free-unit
  (fn (_ argv)
    (def flag (if (null? argv) 0
                (let ((w (first argv)))
                  (if (if (> (byte-len w) 1) (= (byte-at w 0) #\-) #f) (byte-at w 1) 0))))
    (match ((= flag #\b) 1) ((= flag #\m) 1048576) ((= flag #\g) 1073741824)
           ((= flag #\h) 0) (#t 1024))))

; busybox's make_human_readable_str for a size in bytes: in UNIT's, rounded,
; or, UNIT 0, in the largest of K M G T ... under 1024, to a tenth
(def %ps-scale
  (fn (_ n unit)
    (def human
      (fn (self v frac u)
        (if (>= v 1024)
          (self (%ps-div v 1024) (%ps-div (+ (* (% v 1024) 10) 512) 1024) (+ u 1))
          (if (= u 0) (cu-int->str v)
            (let ((v2 (if (>= frac 10) (+ v 1) v)) (f2 (if (>= frac 10) 0 frac)))
              (string-concat (list (cu-int->str v2) "." (cu-int->str f2)
                                   (substring "KMGTPEZY" (- u 1) u))))))))
    (match
      ((= n 0) "0")
      ((> unit 0) (cu-int->str (%ps-div (+ n (%ps-div unit 2)) unit)))
      (#t (human n 0 0)))))

; free's table from MEM, Host's memory record, in UNIT
(def %ps-free-text
  (fn (_ mem unit)
    (def get (fn (_ k) (let ((v (Assoc get k mem))) (if (null? v) 0 v))))
    (def col (fn (_ n) (cu-pad-left (%ps-scale n unit) 12)))
    (def seen (if (null? (Assoc get (lit cached) mem)) #f
                (if (null? (Assoc get (lit available) mem)) #f
                  (not (null? (Assoc get (lit reclaimable) mem))))))
    (def cached (+ (get (lit cached)) (+ (get (lit buffers)) (get (lit reclaimable)))))
    (def free (get (lit free)))
    (def total (get (lit total)))
    (def used (- total (+ cached free)))
    (string-concat
      (list "       " (cu-pad-left "total" 12) (cu-pad-left "used" 12)
            (cu-pad-left "free" 12) (cu-pad-left "shared" 12)
            (cu-pad-left "buff/cache" 12) (cu-pad-left "available" 12) "\n"
            "Mem:   " (col total) (col used) (col free)
            (col (get (lit shared))) (col cached) (col (get (lit available))) "\n"
            (if seen ""
              (string-concat (list "-/+ buffers/cache: " (col used) (col (+ cached free)) "\n")))
            "Swap:  " (col (get (lit swap-total)))
            (col (- (get (lit swap-total)) (get (lit swap-free))))
            (col (get (lit swap-free))) "\n"))))

; --- ps ---------------------------------------------------------------------
;
; busybox's ps (procps/ps.c, built with DESKTOP): every process, the columns
; -o names or pid,user,time,args, each as wide as busybox makes it.  The
; records are x/sys/host's.  -Z -a -A -d -e -f -l are accepted and change
; nothing, as busybox's are.  A field the kernel does not report prints `-`,
; POSIX's mark for a field with no meaning here: on Darwin another user's
; process has no state, size or CPU time without root.

; busybox's out_spec, in its order: name, header, width
(def %ps-columns
  (list (list "user" "USER" 8) (list "group" "GROUP" 8) (list "comm" "COMMAND" 16)
        (list "args" "COMMAND" 2048) (list "pid" "PID" 5) (list "ppid" "PPID" 5)
        (list "pgid" "PGID" 5) (list "etime" "ELAPSED" 7) (list "nice" "NI" 5)
        (list "rgroup" "RGROUP" 8) (list "ruser" "RUSER" 8) (list "time" "TIME" 5)
        (list "tty" "TT" 6) (list "vsz" "VSZ" 4) (list "sid" "SID" 5)
        (list "stat" "STAT" 4) (list "rss" "RSS" 4)))

(def %ps-max-width 2048)

(def %cu-ps
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "ps" argv))
    (def specs (Opts values o "-o"))
    (def cols (%ps-parse-o (if (null? specs) (list "pid,user,time,args") specs)))
    (if (str? cols)
      (do (file-write 2 (string-append "ps: " (string-append cols "\n"))) 1)
      (do (display (%ps-table cols (%ps-sorted (host-processes)) (date-now-unix)
                     (if (sys-isatty 1)
                       (let ((w (- (first (Term window 0)) 1)))
                         (if (> w %ps-max-width) %ps-max-width w))
                       %ps-max-width)
                     host-args))
          0))))

; the processes by pid, as a walk of /proc lists them
(def %ps-sorted
  (fn (_ ps) (List sort (fn (_ a b) (< (Assoc get (lit pid) a) (Assoc get (lit pid) b))) ps)))

; The column busybox's find_out_spec finds for NAME: its own, or one whose six
; letters NAME's first six are.  nil for none.
(def %ps-column
  (fn (_ name)
    (List find
      (fn (_ c)
        (let ((n (first c)))
          (if (str=? n name) #t
            (if (if (= (byte-len n) 6) (> (byte-len name) 6) #f)
              (str=? n (substring name 0 6)) #f))))
      %ps-columns)))

; busybox's parse_o over each -o in turn: comma-separated names, a name
; followed by =HEADER taking the header to the next comma, and the column
; widening to a header that is not empty.  The columns, each (name header
; width), or the refusal's text.
(def %ps-parse-o
  (fn (_ specs)
    (def bad
      (fn (_ name)
        (string-concat (list "bad -o argument '" name "', supported arguments: "
                             (cu-join-with (map first %ps-columns) ",")))))
    (def one
      (fn (self s acc)
        (def comma (Str8 index-of "," s))
        (def equal (Str8 index-of "=" s))
        (def name-end (match ((null? comma) (if (null? equal) (byte-len s) equal))
                             ((null? equal) comma)
                             ((< equal comma) equal)
                             (#t comma)))
        (def name (substring s 0 name-end))
        (def c (%ps-column name))
        (match
          ((null? c) (bad name))
          ((if (null? equal) #f (if (null? comma) #t (< equal comma)))
            (let ((h (substring s (+ equal 1) (if (null? comma) (byte-len s) comma))))
              (def col (list (first c) h (if (> (byte-len h) 0) (byte-len h) (first (rest (rest c))))))
              (if (null? comma) (reverse (pair col acc))
                (self (substring s (+ comma 1) (byte-len s)) (pair col acc)))))
          ((null? comma) (reverse (pair c acc)))
          (#t (self (substring s (+ comma 1) (byte-len s)) (pair c acc))))))
    (def all
      (fn (self ss acc)
        (if (null? ss) acc
          (let ((r (one (first ss) ())))
            (if (str? r) r (self (rest ss) (append acc r)))))))
    (all specs ())))

; busybox's format_time: seconds as mm:ss, hhHmm, ddDhh or dddd in WIDTH
(def %ps-time
  (fn (_ tt width)
    (def two (fn (_ n) (cu-pad-zero (cu-int->str n) 2)))
    (def left (fn (_ n) (cu-pad-left (cu-int->str n) 2)))
    (def m (%ps-div tt 60))
    (def h (%ps-div m 60))
    (def d (%ps-div h 24))
    (def s
      (match
        ((< m 60) (string-concat (list (left m) ":" (two (% tt 60)))))
        ((< h 24) (string-concat (list (left h) "h" (two (% m 60)))))
        ((< d 100) (string-concat (list (left d) "d" (two (% h 24)))))
        (#t (string-append (cu-pad-left (cu-int->str d) 4) "d"))))
    (if (> (byte-len s) width) (substring s 0 width) s)))

; busybox's smart_ulltoa4: N in four characters, "1234" up to 9999, then
; "9.2m" or " 12m" in steps of 1024 through SCALE's letters
(def %ps-four
  (fn (_ n scale)
    (def digit (fn (_ k) (substring "0123456789" k (+ k 1))))
    (def lead (fn (_ k z) (if (if (= k 0) z #f) " " (digit k))))
    (def up
      (fn (self v idx) (if (>= v 10000) (self (%ps-div v 1024) (+ idx 1)) (pair v idx))))
    (if (<= n 9999)
      (let ((u (%ps-div n 10)) (v (% n 10)))
        (def a (lead (%ps-div u 100) #t))
        (def b (lead (% (%ps-div u 10) 10) (str=? a " ")))
        (def c (lead (% u 10) (str=? b " ")))
        (string-concat (list a b c (digit v))))
      (let ((r (up (%ps-div (* n 10) 1024) 1)))
        (def u (%ps-div (first r) 10))
        (def v (% (first r) 10))
        (def unit (substring scale (rest r) (+ (rest r) 1)))
        (if (>= u 10)
          (let ((a (lead (%ps-div u 100) #t)))
            (string-concat (list a (lead (% (%ps-div u 10) 10) (str=? a " ")) (digit (% u 10)) unit)))
          (string-concat (list (digit u) "." (digit v) unit)))))))

; libc's strcspn and strrchr, for the scans of a command line: a loop in x
; costs hundreds of objects a byte, and ps reads every process's line
(def %ps-c-strcspn ())
(def %ps-c-strrchr ())
(def %ps-controls (bytes->str (List range 1 32)))
(def %ps-addr (fn (_ s) ((prim-ref (lit ptr) (lit ->int)) ((prim-ref (lit str) (lit ->ptr)) s))))
(def %ps-resolve!
  (fn (_)
    (if (null? %ps-c-strcspn)
      (let ((lib (cu-dlopen () 1)))
        (set! %ps-c-strcspn (cu-dlsym lib "strcspn"))
        (set! %ps-c-strrchr (cu-dlsym lib "strrchr")))
      ())))

; busybox's read_cmdline: the arguments joined by spaces, a control byte as
; ?, and {comm} before them when the program's name does not start with comm;
; [comm] when there are none
(def %ps-args
  (fn (_ args comm)
    (%ps-resolve!)
    (if (null? args) (string-concat (list "[" comm "]"))
      (let ((line (%ps-printable (cu-join-with args " ")))
            ; argv[0] up to its first space, past a leading -, after its last /
            (argv0 (let ((a (first args)))
                     (substring a 0 (cu-ptr-call %ps-c-strcspn a " ")))))
        (def from (if (if (> (byte-len argv0) 0) (= (byte-at argv0 0) #\-) #f) 1 0))
        (def word (substring argv0 from (byte-len argv0)))
        (def slash (cu-ptr-call %ps-c-strrchr word 47))   ; 47 is /, a byte for the FFI
        (def base (if (= slash 0) word
                    (substring word (+ (- slash (%ps-addr word)) 1) (byte-len word))))
        (def m (byte-len comm))
        (if (if (<= m (byte-len base)) (str=? (substring base 0 m) comm) #f) line
          (string-concat (list "{" comm "} " line)))))))

; S with each control byte as ?; S itself when it holds none, as most lines do
(def %ps-printable
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i acc)
        (if (>= i end) (bytes->str (reverse acc))
          (let ((b (byte-at s i))) (self (+ i 1) (pair (if (< b 32) #\? b) acc))))))
    (if (= (cu-ptr-call %ps-c-strcspn s %ps-controls) end) s (go 0 ()))))

; One cell of a process's row, before padding, "" where busybox prints its -
(def %ps-cell
  (fn (_ name width p now args-of names)
    (def get (fn (_ k) (Assoc get k p)))
    (def right (fn (_ n) (if (null? n) "" (cu-pad-left (cu-int->str n) width))))
    (def cut (fn (_ s) (if (> (byte-len s) width) (substring s 0 width) s)))
    (def id (fn (_ k db) (let ((n (get k))) (if (null? n) "" (cut (names db n))))))
    (def kb (fn (_ k) (let ((n (get k))) (if (null? n) "" (cut (%ps-four (%ps-div n 1024) " mgtpezy"))))))
    (match
      ((str=? name "user") (id (lit uid) (lit user)))
      ((str=? name "group") (id (lit gid) (lit group)))
      ((str=? name "ruser") (id (lit ruid) (lit user)))
      ((str=? name "rgroup") (id (lit rgid) (lit group)))
      ((str=? name "comm") (cut (get (lit comm))))
      ((str=? name "args") (cut (%ps-args (args-of (get (lit pid))) (get (lit comm)))))
      ((str=? name "pid") (right (get (lit pid))))
      ((str=? name "ppid") (right (get (lit ppid))))
      ((str=? name "pgid") (right (get (lit pgid))))
      ((str=? name "sid") (right (get (lit sid))))
      ((str=? name "nice") (right (get (lit nice))))
      ((str=? name "etime") (if (null? (get (lit start))) "" (%ps-time (- now (get (lit start))) width)))
      ((str=? name "time")
        (if (if (null? (get (lit utime))) #t (null? (get (lit stime)))) ""
          (%ps-time (%ps-div (+ (get (lit utime)) (get (lit stime))) 1000000000) width)))
      ((str=? name "tty")
        (if (null? (get (lit tty-major))) "?"
          (cut (string-concat (list (cu-int->str (get (lit tty-major))) ","
                                    (cu-int->str (get (lit tty-minor))))))))
      ((str=? name "vsz") (kb (lit vsz)))
      ((str=? name "rss") (kb (lit rss)))
      ((str=? name "stat") (%ps-stat p))
      (#t ""))))

; busybox's state: the letter, then W for a process with no memory, then < or
; N for a nice below or above 0 -- three characters, the unused ones spaces
(def %ps-stat
  (fn (_ p)
    (def st (Assoc get (lit state) p))
    (def vsz (Assoc get (lit vsz) p))
    (def nice (Assoc get (lit nice) p))
    (if (null? st) ""
      (let ((w (if (if (null? vsz) #f (if (= vsz 0) (not (str=? st "Z")) #f)) "W" "")))
        (def n (match ((null? nice) "") ((< nice 0) "<") ((> nice 0) "N") (#t "")))
        (cu-pad-right (string-concat (list st w n)) 3)))))

; The table: the header when a column has one, then a row a process -- each
; column but the last padded to its width and a space, each line cut to WIDTH
; characters, and the columns past WIDTH dropped as busybox drops them.
(def %ps-table
  (fn (_ cols procs now width args-of)
    (def fit
      (fn (self cs used acc)
        (if (null? cs) (reverse acc)
          (let ((used2 (+ used (+ (first (rest (rest (first cs)))) 1))))
            (if (> used2 width) (reverse (pair (first cs) acc))
              (self (rest cs) used2 (pair (first cs) acc)))))))
    (def shown (fit cols 0 ()))
    (def cache (list ()))
    ; a name per id, looked up once a run, as busybox's get_cached_username
    ; does; an id the system has no name for is its number.  DB is user or
    ; group.
    (def names
      (fn (_ db n)
        (def hit (List find (fn (_ e) (if (eq? (first (first e)) db) (= (rest (first e)) n) #f)) (first cache)))
        (if (not (null? hit)) (rest hit)
          (let ((s (let ((nm (if (eq? db (lit user)) (sys-user-name n) (sys-group-name n))))
                     (if (null? nm) (cu-int->str n) nm))))
            (set-first! cache (pair (pair (pair db n) s) (first cache)))
            s))))
    (def line
      (fn (_ cells)
        (def go
          (fn (self cs ws acc)
            (if (null? (rest cs)) (string-concat (reverse (pair (first cs) acc)))
              (let ((gap (- (+ (first ws) 1) (byte-len (first cs)))))
                (self (rest cs) (rest ws)
                  (pair (str-make-raw (if (< gap 1) 1 gap)) (pair (first cs) acc)))))))
        (def l (go cells (map (fn (_ c) (first (rest (rest c)))) shown) ()))
        (string-append (if (> (byte-len l) width) (substring l 0 width) l) "\n")))
    (def header?
      (List any? (fn (_ c) (> (byte-len (first (rest c))) 0)) shown))
    (def row
      (fn (_ p)
        (line (map (fn (_ c)
                     (let ((s (%ps-cell (first c) (first (rest (rest c))) p now args-of names)))
                       (if (= (byte-len s) 0) "-" s)))
                   shown))))
    ; a row costs a few hundred thousand objects, its arguments read and
    ; laid out; a sweep every 32 rows keeps a table of any length to the
    ; garbage of 32
    (def rows
      (fn (self ps k acc)
        (if (null? ps) (reverse acc)
          (do (if (= (% k 32) 31) (cu-heap-collect) ())
              (self (rest ps) (+ k 1) (pair (row (first ps)) acc))))))
    (string-concat
      (pair (if header? (line (map (fn (_ c) (first (rest c))) shown)) "")
            (rows procs 0 ())))))

; --- pidof, pgrep, pkill ----------------------------------------------------
;
; busybox's procps/pidof.c and procps/pgrep.c over the same process records
; ps reads.  They read a process's arguments and executable only when its
; name has not already decided, and sweep every 32 processes, as ps does.

; S after its last /, by libc's strrchr
(def %pg-base
  (fn (_ s)
    (%ps-resolve!)
    (def slash (cu-ptr-call %ps-c-strrchr s 47))   ; 47 is /, a byte for the FFI
    (if (= slash 0) s (substring s (+ (- slash (%ps-addr s)) 1) (byte-len s)))))

; the first N bytes of S, or all of it when it is shorter
(def %pg-head (fn (_ s n) (if (> (byte-len s) n) (substring s 0 n) s)))

; each process in turn, a sweep every 32
(def %pg-each
  (fn (_ procs f)
    (def go
      (fn (self ps k)
        (if (null? ps) ()
          (do (if (= (% k 32) 31) (cu-heap-collect) ())
              (f (first ps))
              (self (rest ps) (+ k 1))))))
    (go procs 0)))

; busybox's find_pid_by_name, for one process P: its comm as comm_match reads
; it -- the first 15 bytes, and when comm fills them, the basename of argv[1]
; settles it -- or the basename of argv[0], or its executable, whole when NAME
; is a path and by basename otherwise
(def %pg-named?
  (fn (_ p name)
    (def comm (Assoc get (lit comm) p))
    (def pid (Assoc get (lit pid) p))
    (def args (fn (_) (host-args pid)))
    (def by-comm
      (if (str=? (%pg-head comm 15) (%pg-head name 15))
        (if (< (byte-len comm) 15) #t
          (let ((a (args)))
            (if (if (null? a) #t (null? (rest a))) #f (str=? (%pg-base (first (rest a))) name))))
        #f))
    (match
      (by-comm #t)
      ((let ((a (args))) (if (null? a) #f (str=? (%pg-base (first a)) name))) #t)
      (#t (let ((e (host-exe pid)))
            (if (null? e) #f
              (str=? (if (= (byte-at name 0) #\/) e (%pg-base e)) name)))))))

(def %cu-pidof
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "pidof" argv))
    (def me (host-process (sys-getpid)))
    ; -o %PPID is pidof's parent
    (def omits
      (map (fn (_ v) (if (str=? v "%PPID") (Assoc get (lit ppid) me) (%cu-range-number "pidof" v 0 4294967295)))
           (Opts values o "-o")))
    (if (List any? null? omits) 1
      (let ((procs (%ps-sorted (host-processes))) (single (Opts on? o "-s")))
        (def found
          (fn (_ name)
            (def hits (list ()))
            (%pg-each procs (fn (_ p) (if (%pg-named? p name) (set-first! hits (pair (Assoc get (lit pid) p) (first hits))) ())))
            ; busybox reverses its scan, newest pid first
            (def kept (filter (fn (_ pid) (not (List includes? pid omits))) (first hits)))
            (if (if single (not (null? kept)) #f) (list (first kept)) kept)))
        (def all (List flat-map found (Opts operands o)))
        (if (null? all) 1
          (do (display (string-append (cu-join-with (map cu-int->str all) " ") "\n")) 0))))))


; --- signals ------------------------------------------------------------------
;
; busybox's libbb/u_signal_names.c, for kill and pkill: the names are the
; kernel's, from (Sys signals), and the real-time range is libc's, as busybox
; reads it with FEATURE_RTMINMAX_USE_LIBC_DEFINITIONS.

(def %pg-alnum?
  (fn (_ c)
    (match
      ((if (>= c #\0) (<= c #\9) #f) #t)
      ((if (>= c #\A) (<= c #\Z) #f) #t)
      (#t (if (>= c #\a) (<= c #\z) #f)))))

; busybox's bb_strtou and bb_strtoi, base 10, from I of S (bb_strtonum.c):
; (N . END), END where the digits stop.  N is nil where busybox answers
; ERANGE: no digit to read (a - first only where LO is below 0), a digit or
; letter straight after the digits, or outside LO..HI.  Digits that stop at
; anything else are busybox's EINVAL, the value kept; the caller reads END.
(def %pg-strto
  (fn (_ s i lo hi)
    (def len (byte-len s))
    (def neg (if (< lo 0) (if (< i len) (= (byte-at s i) #\-) #f) #f))
    (def j (if neg (+ i 1) i))
    (def r (%hx-strtoul s j 10 (if neg (- 0 lo) hi)))
    (def k (rest r))
    (match
      ((= k j) (pair () k))
      ((if (< k len) (%pg-alnum? (byte-at s k)) #f) (pair () k))
      ((null? (first r)) (pair () k))
      (#t (pair (if neg (- 0 (first r)) (first r)) k)))))

; libc's real-time signals, (MIN . MAX), or nil where libc has none (Darwin).
; glibc and musl both answer them by function, as SIGRTMIN and SIGRTMAX do.
(def %pg-rt-cell (list ()))
(def %pg-rt
  (fn (_)
    (do (if (null? (first %pg-rt-cell))
          (let ((lib (cu-dlopen () 1)))
            (let ((lo (cu-dlsym lib "__libc_current_sigrtmin"))
                  (hi (cu-dlsym lib "__libc_current_sigrtmax")))
              (set-first! %pg-rt-cell
                (list (if (if (null? lo) #t (null? hi)) ()
                        (pair (Sys %sign-fold (cu-ptr-call lo))
                              (Sys %sign-fold (cu-ptr-call hi))))))))
          ())
        (first (first %pg-rt-cell)))))

; NSIG, one past the last signal: past RTMAX where there is one, else past
; the kernel's named signals -- 65 on Linux, 32 on Darwin
(def %pg-nsig
  (fn (_)
    (let ((rt (%pg-rt)))
      (if (null? rt) (+ (length (sys-signals)) 1) (+ (rest rt) 1)))))

; the number of the kernel's signal NAME, or nil
(def %pg-named
  (fn (_ name)
    (let ((hit (List find (fn (_ e) (str=? (first e) name)) (sys-signals))))
      (if (null? hit) () (rest hit)))))

; busybox's get_signum: a number below NSIG, as bb_strtou reads it (digits a
; blank or a comma ends are read); or a name in any case, with or without SIG
; -- EXIT is 0, IO is POLL where the kernel calls it that (Linux), IOT is
; ABRT; or RTMIN, RTMIN+N, RTMAX, RTMAX-N inside libc's range.  nil for none.
(def %pg-signum
  (fn (_ s)
    (def n (first (%pg-strto s 0 0 4294967295)))
    (def up (Str8 upcase s))
    (def bare (if (Str8 starts? "SIG" up) (substring up 3 (byte-len up)) up))
    (def rt (%pg-rt))
    ; RTMIN+N and RTMAX-N: N no further from the end than the range is long
    (def rt-off
      (fn (_ sign)
        (if (if (> (byte-len bare) 5) (= (byte-at bare 5) sign) #f)
          (let ((i (first (%pg-strto bare 6 0 4294967295))))
            (if (if (null? i) #f (<= i (- (rest rt) (first rt)))) i ()))
          ())))
    (match
      ((if (null? n) #f (< n (%pg-nsig))) n)
      ((str=? bare "EXIT") 0)
      ((not (null? (%pg-named bare))) (%pg-named bare))
      ((str=? bare "IO") (%pg-named "POLL"))
      ((str=? bare "IOT") (%pg-named "ABRT"))
      ((null? rt) ())
      ((str=? bare "RTMIN") (first rt))
      ((str=? bare "RTMAX") (rest rt))
      ((Str8 starts? "RTMIN" bare) (let ((i (rt-off #\+))) (if (null? i) () (+ (first rt) i))))
      ((Str8 starts? "RTMAX" bare) (let ((i (rt-off #\-))) (if (null? i) () (- (rest rt) i))))
      (#t ()))))

; busybox's get_signame: the kernel's name for N, EXIT for 0, else N itself
(def %pg-signame
  (fn (_ n)
    (if (= n 0) "EXIT"
      (let ((hit (List find (fn (_ e) (= (rest e) n)) (sys-signals))))
        (if (null? hit) (cu-int->str n) (first hit))))))

; busybox's print_signames: each signal as " 9) KILL", then libc's RTMIN and
; RTMAX where it has them
(def %pg-print-signames
  (fn (_)
    (def rt (%pg-rt))
    (def line (fn (_ n name) (display (string-concat (list (cu-pad-left (cu-int->str n) 2) ") " name "\n")))))
    (do (map (fn (_ e) (line (rest e) (first e))) (sys-signals))
        (if (null? rt) ()
          (do (line (first rt) "RTMIN") (line (rest rt) "RTMAX")))
        0)))

(def %cu-pgrep (fn (_ argv stdin-thunk) (%pg-run "pgrep" argv)))

; the signal ARGV's first word names as -SIGNAL, or nil; the parse (cu/cli.x)
; sets that word aside for pkill
(def %pg-signal-word
  (fn (_ argv)
    (if (if (null? argv) #f (if (> (byte-len (first argv)) 1) (= (byte-at (first argv) 0) #\-) #f))
      (%pg-signum (substring (first argv) 1 (byte-len (first argv)))) ())))

(def %cu-pkill
  (fn (_ argv stdin-thunk)
    (def sig (%pg-signal-word argv))
    (%pg-run-with "pkill" argv (if (null? sig) cu-sigterm sig))))

; --- kill -----------------------------------------------------------------------
;
; busybox's procps/kill.c, as kill_main reads its words itself: -l, -SIG or
; -s SIG, or -- in the first word only, then the pids.  Each status is the
; count of what failed.  A pid word is read as the shell's kill reads it,
; several pids apart by single blanks, so " -12" names a process group and an
; empty word names none.

(def %kl-say
  (fn (_ s) (do (file-write 2 (string-concat (list "kill: " s "\n"))) 1)))

(def %cu-kill
  (fn (_ argv stdin-thunk)
    (def a (if (null? argv) "" (first argv)))
    (match
      ((if (null? argv) #t (if (= (byte-len a) 0) #t (not (= (byte-at a 0) #\-))))
        (%kl-pids argv cu-sigterm))
      ((str=? a "-l")
        (if (null? (rest argv)) (%pg-print-signames) (%kl-list %kl-say (rest argv))))
      ((str=? a "--") (%kl-pids (rest argv) cu-sigterm))
      ; -s SIG takes the next word, where there is one; -s alone is a name
      ((if (str=? a "-s") (not (null? (rest argv))) #f)
        (%kl-signalled (first (rest argv)) (rest (rest argv))))
      (#t (%kl-signalled (substring a 1 (byte-len a)) (rest argv))))))

(def %kl-signalled
  (fn (_ name pids)
    (let ((n (%pg-signum name)))
      (if (null? n) (%kl-say (string-concat (list "bad signal name '" name "'")))
        (%kl-pids pids n)))))

; kill -l WORD... and killall's: a number's name -- its low 7 bits, as a
; shell's status above 128 is a signal -- or a name's number; the first word
; that is neither is told to SAY, which answers 1
(def %kl-list
  (fn (self say words)
    (if (null? words) 0
      (let ((w (first words)))
        (def digit (if (> (byte-len w) 0) (if (>= (byte-at w 0) #\0) (<= (byte-at w 0) #\9) #f) #f))
        (def r (%pg-strto w 0 0 4294967295))
        (def n (if digit (if (= (rest r) (byte-len w)) (first r) ()) (%pg-signum w)))
        (if (null? n) (say (string-concat (list "unknown signal '" w "'")))
          (do (display (string-append (if digit (%pg-signame (& n 127)) (cu-int->str n)) "\n"))
              (self say (rest words))))))))

(def %kl-pids
  (fn (_ words signo)
    (if (null? words) (%kl-say "you need to specify whom to kill")
      (List fold (fn (_ errs w) (+ errs (%kl-word w 0 signo))) 0 words))))

; the pids in W from I, each signalled: the count that failed.  One blank
; before a pid is passed over; a word that does not read as a number is said
; from where it went wrong, and ends this word.
(def %kl-word
  (fn (self w i signo)
    (def len (byte-len w))
    (def j (if (if (< i len) (= (byte-at w i) #\space) #f) (+ i 1) i))
    (def r (%pg-strto w j -2147483648 2147483647))
    (def pid (first r))
    (def end (rest r))
    (match
      ((>= i len) 0)
      ((if (null? pid) #t (if (< end len) (not (= (byte-at w end) #\space)) #f))
        (%kl-say (string-concat (list "invalid number '" (substring w j len) "'"))))
      ; errno is read straight after the refusal
      (#t (let ((err (if (< (sys-kill pid signo) 0) (Err from-errno (Err errno-of (- 0 1)) (lit kill) ()) ())))
            (+ (if (null? err) 0
                 (%kl-say (string-concat (list "can't kill pid " (cu-int->str pid) ": " (file-err-text err)))))
               (self w end signo)))))))

(def %pg-run (fn (_ applet argv) (%pg-run-with applet argv cu-sigterm)))

(def %pg-run-with
  (fn (_ applet argv signo)
    (def o (cu-opts applet argv))
    (def on (fn (_ f) (Opts on? o f)))
    (def num (fn (_ f) (let ((v (Opts value o f))) (if (null? v) -1 (%cu-range-number applet v 0 2147483647)))))
    (def ops (Opts operands o))
    (def sid-asked (num "-s"))
    (def ppid (num "-P"))
    (def me (sys-getpid))
    (match
      ((if (null? sid-asked) #t (null? ppid)) 1)
      ((if (str=? applet "pkill") (on "-l") #f) (%pg-print-signames))
      ((if (< sid-asked 0) (if (< ppid 0) (if (null? ops) #t (not (null? (rest ops)))) #f) #f)
        (cu-usage applet))
      (#t (%pg-scan applet o ops
            (if (= sid-asked 0) (Assoc get (lit sid) (host-process me)) sid-asked)
            ppid me signo)))))

; busybox's pgrep_main from the scan on: each process but this one, its argv[0]
; -- or with -f its whole command line, a control byte or NUL as a space --
; tried against the pattern, then its comm; -x wants the whole of it; -v turns
; the match over; -o stops at the first and -n acts on the last
(def %pg-scan
  (fn (_ applet o ops sid ppid me signo)
    (def on (fn (_ f) (Opts on? o f)))
    (def rx (if (null? ops) () (re-compile (first ops))))
    (def full (on "-f"))
    (def invert (on "-v"))
    (def matches?
      (fn (_ cmd)
        (let ((m (re-search rx cmd)))
          (if (null? m) #f
            (if (on "-x") (if (= (first m) 0) (= (first (rest m)) (byte-len cmd)) #f) #t)))))
    (def act
      (fn (_ p shown)
        (def pid (Assoc get (lit pid) p))
        (if (str=? applet "pgrep")
          (display (string-append (cu-int->str pid)
                     (if (if (on "-l") #t (on "-a")) (string-append " " shown "\n") "\n")))
          (do (sys-kill pid signo)
              (if (on "-e") (display (string-concat (list shown " killed (pid " (cu-int->str pid) ")\n"))) ())))))
    (def found (list ()))
    (def stop (list #f))
    (%pg-each (%ps-sorted (host-processes))
      (fn (_ p)
        (def pid (Assoc get (lit pid) p))
        (def ids-differ (if (if (>= ppid 0) (not (= ppid (Assoc get (lit ppid) p))) #f) #t
                          (if (>= sid 0) (not (= sid (Assoc get (lit sid) p))) #f)))
        (if (match ((first stop) #t) ((= pid me) #t) (invert #f) (#t ids-differ)) ()
          (let ((args (host-args pid)) (comm (Assoc get (lit comm) p)))
            (def cmd (if (null? args) comm
                       (if full (%pg-spaced (cu-join-with args " ")) (first args))))
            ; what -l and -a print: the first argument, or with -f -a the line
            (def shown (if (null? args) comm (if (if full (on "-a")) cmd (first args))))
            (def by-cmd (if (null? rx) #f (matches? cmd)))
            (def m (match ((null? rx) #t) (by-cmd #t) ((null? args) #f) (#t (matches? comm))))
            (def hit (if (if invert ids-differ #f) #t (if invert (not m) m)))
            ; a match by comm shows comm
            (def shown2 (match ((not hit) shown) ((null? rx) shown) ((null? args) shown) (by-cmd shown) (#t comm)))
            (if hit
              (if (on "-n") (set-first! found (pair p shown2))
                (do (act p shown2)
                    (set-first! found (pair p shown2))
                    (if (on "-o") (set-first! stop #t) ())))
              ())))))
    (if (null? (first found)) 1
      (do (if (on "-n") (act (first (first found)) (rest (first found))) ()) 0))))

; S with each control byte as a space, as busybox prints a command line
(def %pg-spaced
  (fn (_ s)
    (%ps-resolve!)
    (def end (byte-len s))
    (def go
      (fn (self i acc)
        (if (>= i end) (bytes->str (reverse acc))
          (let ((b (byte-at s i))) (self (+ i 1) (pair (if (< b 32) #\space b) acc))))))
    (if (= (cu-ptr-call %ps-c-strcspn s %ps-controls) end) s (go 0 ()))))

; --- lsof -------------------------------------------------------------------
;
; busybox's procps/lsof.c: every process's open descriptors but lsof's own, a
; line each -- pid, executable, descriptor, and what it holds -- tab-separated.
; busybox reads no options and no operands.  Only the processes this user may
; look into are listed; another's answers no descriptors, as busybox's opendir
; of its /proc/PID/fd fails.  A process whose executable the kernel will not
; name prints (null), as musl's printf does busybox's NULL.  Linux names what
; a descriptor holds by its /proc/PID/fd link; Darwin names a file by its
; path, and anything else by its type and the kernel's number for it, as
; Linux spells a socket's or pipe's link.

; what descriptor record F holds, as a /proc/PID/fd link reads
(def %lsof-target
  (fn (_ f)
    (def name (Assoc get (lit name) f))
    (def type (Assoc get (lit type) f))
    (def id (Assoc get (lit id) f))
    (def kind (if (null? type) "?" (symbol->str type)))
    (match
      ((not (null? name)) name)
      ((null? id) kind)
      (#t (string-concat (list kind ":[" (cu-int->str id) "]"))))))

(def %cu-lsof
  (fn (_ argv stdin-thunk)
    (def me (sys-getpid))
    (%pg-each (%ps-sorted (host-processes))
      (fn (_ p)
        (def pid (Assoc get (lit pid) p))
        (def fs (if (= pid me) () (host-files pid)))
        (if (null? fs) ()
          (let ((head (string-concat (list (cu-int->str pid) "\t"
                                           (let ((e (host-exe pid))) (if (null? e) "(null)" e)) "\t"))))
            ((fn (self l)
               (if (null? l) ()
                 (do (display (string-concat (list head (cu-int->str (Assoc get (lit fd) (first l))) "\t"
                                                   (%lsof-target (first l)) "\n")))
                     ; a process can hold thousands of descriptors
                     (cu-sweep-tick! cu-sweep-lines)
                     (self (rest l)))))
             fs)))))
    0))

; --- pwdx -------------------------------------------------------------------

; busybox's procps/pwdx.c: each PID's current directory, or why the kernel
; will not say.  A PID is NUM or /proc/NUM, and the line names it as it was
; given.  An operand that is not a pid ends the run, status 1, after the
; lines before it.
(def %cu-pwdx
  (fn (_ argv stdin-thunk)
    (def ops (Opts operands (cu-opts "pwdx" argv)))
    ; getopt reads -5 as the option 5, before any pid
    (def dash (%vm-dash-number ops))
    (match
      ((not (null? dash)) (cu-refuse-option "pwdx" dash))
      ((null? ops) (cu-usage "pwdx"))
      (#t (%pw-each ops)))))

(def %pw-each
  (fn (self ops)
    (if (null? ops) 0
      (let ((arg (first ops)))
        (def s (if (Str8 starts? "/proc/" arg) (substring arg 6 (byte-len arg)) arg))
        (def pid (%pw-pid s))
        (if (null? pid)
          (do (file-write 2 (string-concat (list "pwdx: invalid process id: '" s "'\n"))) 1)
          (do (display (string-concat (list arg ": " (%pw-cwd pid) "\n")))
              (self (rest ops))))))))

; S as busybox's bb_strtou reads it: decimal digits only, at least one, up to
; 4294967295.  nil for anything else.
(def %pw-pid
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i n)
        (match
          ((> n 4294967295) ())
          ((>= i end) n)
          ((if (>= (byte-at s i) #\0) (<= (byte-at s i) #\9) #f)
            (self (+ i 1) (+ (* n 10) (- (byte-at s i) #\0))))
          (#t ()))))
    (if (= end 0) () (go 0 0))))

; busybox prints readlink's errno: ENOENT, read as ESRCH, for a process gone
; or a zombie, whose cwd link is gone; otherwise EACCES, a process this user
; may not read.  Host reports no errno, so the process record tells them apart.
(def %pw-cwd
  (fn (_ pid)
    (def d (host-cwd pid))
    (if (not (null? d)) d
      (let ((p (host-process pid)))
        (if (if (null? p) #t (equal? (Assoc get (lit state) p) "Z"))
          "No such process" "Permission denied")))))

; --- killall ----------------------------------------------------------------
;
; busybox's kill_main as killall (procps/kill.c).  Its words are read by
; hand, not by getopt: -l, or -q, then one -SIG, -s SIG or --, then the
; names.  Each name is find_pid_by_name's, as pidof reads it, and every
; process it names but this one is signalled.  The status counts the names
; nothing answered and the signals that failed.

(def %cu-killall
  (fn (_ argv stdin-thunk)
    (def dash? (fn (_ w) (if (> (byte-len w) 0) (= (byte-at w 0) #\-) #f)))
    (match
      ((if (null? argv) #t (not (dash? (first argv)))) (%ka-kill argv cu-sigterm #f))
      ((str=? (first argv) "-l")
        (if (null? (rest argv)) (%pg-print-signames) (%kl-list %ka-say (rest argv))))
      ((str=? (first argv) "-q")
        (match
          ((null? (rest argv)) (cu-usage "killall"))
          ((dash? (first (rest argv))) (%ka-signal (rest argv) #t))
          (#t (%ka-kill (rest argv) cu-sigterm #t))))
      (#t (%ka-signal argv #f)))))

(def %ka-say
  (fn (_ s) (do (file-write 2 (string-concat (list "killall: " s "\n"))) 1)))

; ARGV's first word is --, -s SIG with a word after it, or -SIG; the names
; follow it
(def %ka-signal
  (fn (_ argv quiet)
    (def w (substring (first argv) 1 (byte-len (first argv))))
    (def by-s (if (str=? w "s") (not (null? (rest argv))) #f))
    (def word (if by-s (first (rest argv)) w))
    (def signo (%pg-signum word))
    (def names (if by-s (rest (rest argv)) (rest argv)))
    (match
      ((str=? w "-") (%ka-kill names cu-sigterm quiet))
      ((null? signo) (%ka-say (string-concat (list "bad signal name '" word "'"))))
      (#t (%ka-kill names signo quiet)))))

; SIGNO to every process each of NAMES names, this one aside; a name with no
; process, and a signal refused, each count one
(def %ka-kill
  (fn (_ names signo quiet)
    (if (null? names)
      (%ka-say "you need to specify whom to kill")
      (%ka-kill-each names signo quiet))))

(def %ka-kill-each
  (fn (_ names signo quiet)
    (def procs (%ps-sorted (host-processes)))
    (def me (sys-getpid))
    (def send
      (fn (_ pid)
        (if (= pid me) 0
          (let ((r (sys-kill pid signo)))
            (if (< r 0)
              (do (if quiet ()
                    (%ka-say (string-concat (list "can't kill pid " (cu-int->str pid) ": "
                               (file-err-text (Err from-errno (Err errno-of r) (lit kill) ()))))))
                  1)
              0)))))
    (def one
      (fn (_ name)
        (def hits (list ()))
        (%pg-each procs (fn (_ p) (if (%pg-named? p name) (set-first! hits (pair (Assoc get (lit pid) p) (first hits))) ())))
        (if (null? (first hits))
          (do (if quiet () (%ka-say (string-append name ": no process killed"))) 1)
          (List fold (fn (_ acc pid) (+ acc (send pid))) 0 (reverse (first hits))))))
    (& (List fold (fn (_ acc name) (+ acc (one name))) 0 names) 255)))

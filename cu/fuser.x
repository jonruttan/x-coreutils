; # x-coreutils -- the small tools, as applets
;
; ## cu/fuser.x -- fuser
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's fuser (procps/fuser.c): the processes that use a file, the file
; system a file is on (-m), or a port.  A FILE's holders are Host's: the
; processes holding it as a working directory, root or executable, through a
; descriptor or a mapping.  A PORT/PROTO is the device and inode of every
; socket bound to that local port, matched against each process's
; descriptors.  Every match but this process is printed, in pid order, and
; with -k signalled.

; busybox reads its -SIGNAL before getopt: the first word before a -- that is
; a - and a signal, wherever it stands.  -4 and -6 are taken here as well, as
; gzip takes its digits, since a dash and a digit reads to the parse as a
; number.  (SIGNO FAMILIES ARGV): SIGNO nil when no word names one, FAMILIES
; the digits given (#\4, #\6), ARGV the words left for the parse.
(module cu/fuser)

(import cu/cli cu-opts cu-usage)
(import cu/prims append byte-at byte-len cu-int->str cu-sigkill file-stat-full
  file-write filter host-files-of host-holders host-processes map reverse
  set-first! string-append string-concat substring sys-getpid)
(import cu/text cu-num-prefix)

(def fu-args
  (fn (_ argv)
    (def digit? (fn (_ c) (if (= c #\4) #t (= c #\6))))
    ; WORD's bytes past the dash when it is a cluster with a 4 or a 6 in it
    (def cluster
      (fn (_ w)
        (def bs (if (> (byte-len w) 1) (if (= (byte-at w 0) #\-) (rest (gz-word-bytes w)) ()) ()))
        (if (if (null? bs) #t (= (first bs) #\-)) () (if (List any? digit? bs) bs ()))))
    (def go
      (fn (self ws sig fams acc)
        (if (null? ws) (list sig fams (reverse acc))
          (let ((w (first ws)) (bs (cluster (first ws))))
            (match
              ((str=? w "--") (list sig fams (append (reverse acc) ws)))
              ((not (null? bs))
                (let ((left (filter (fn (_ c) (not (digit? c))) bs)))
                  (self (rest ws) sig (append (filter digit? bs) fams)
                        (if (null? left) acc (pair (bytes->str (pair #\- left)) acc)))))
              ((if (null? sig) (not (null? (pg-signal-word ws))) #f)
                (self (rest ws) (pg-signal-word ws) fams acc))
              (#t (self (rest ws) sig fams (pair w acc))))))))
    (go argv () () ())))

; the protocols a PORT/PROTO may name, as busybox finds them under /proc/net,
; each as the files records' proto and family
(def %fu-protocols
  (list (list "tcp" (lit tcp) 4) (list "udp" (lit udp) 4) (list "raw" (lit raw) 4)
        (list "icmp" (lit icmp) 4) (list "tcp6" (lit tcp) 6) (list "udp6" (lit udp) 6)
        (list "raw6" (lit raw) 6)))

; S as busybox's sscanf "%u/%4s" reads it: (PORT PROTO FAMILY) for digits, a
; slash and a protocol (its first four bytes), or nil
(def %fu-port-of
  (fn (_ s)
    (def n (byte-len s))
    (def digits (fn (self i) (if (if (< i n) (if (>= (byte-at s i) #\0) (<= (byte-at s i) #\9) #f) #f) (self (+ i 1)) i)))
    (def d (digits 0))
    (if (if (> d 0) (if (< d n) (= (byte-at s d) #\/) #f) #f)
      (let ((name (pg-head (substring s (+ d 1) n) 4)))
        (def hit (List find (fn (_ p) (str=? (first p) name)) %fu-protocols))
        (if (null? hit) () (pair (cu-num-prefix (substring s 0 d)) (rest hit))))
      ())))

; two numbers, either of them nil, the same: = reads only integers
(def %fu-same? (fn (_ a b) (if (null? a) (null? b) (if (null? b) #f (= a b)))))

; a record's (DEV . INO); a socket whose link will not stat is its inode,
; the number in socket:[N]
(def %fu-id
  (fn (_ r)
    (def ino (Assoc get (lit ino) r))
    (pair (Assoc get (lit dev) r) (if (null? ino) (Assoc get (lit id) r) ino))))

; the ids of each socket in PIDS bound to PORT over PROTO and FAMILY, unless
; a -4 or -6 in FAMILIES rules its family out
(def %fu-sockets
  (fn (_ fams pids port proto family)
    (if (List any? (fn (_ c) (= c (if (= family 6) #\4 #\6))) fams) ()
      (List flat-map
        (fn (_ pid)
          (List flat-map
            (fn (_ r)
              (if (if (eq? (Assoc get (lit proto) r) proto)
                    (if (%fu-same? (Assoc get (lit family) r) family) (%fu-same? (Assoc get (lit port) r) port) #f) #f)
                (list (%fu-id r)) ()))
            (host-files-of pid (list (lit fd)))))
        pids))))

; the processes in PIDS with a descriptor that is one of the sockets IDS --
; or with -m, anything on one's device, as busybox's -m reads a port
(def %fu-socket-holders
  (fn (_ mount? pids ids)
    (def hit?
      (fn (_ r)
        (def id (%fu-id r))
        (List any? (fn (_ w) (if (%fu-same? (first w) (first id)) (if mount? #t (%fu-same? (rest w) (rest id))) #f)) ids)))
    (filter (fn (_ pid) (do (%top-sweep-if-due!) (List any? hit? (host-files-of pid (list (lit fd)))))) pids)))

(def cu-fuser
  (fn (_ argv stdin-thunk)
    (def args (fu-args argv))
    (def signo (if (null? (first args)) cu-sigkill (first args)))
    (def o (cu-opts "fuser" argv))
    (def ops (Opts operands o))
    (if (null? ops) (cu-usage "fuser")
      (let ((ws (%fu-wanted ops ())))
        (if (eq? ws #f) 1 (%fu-act o (%fu-found o (first (rest args)) ws) signo))))))

; each operand as fuser will look for it, in order: (file . PATH) or
; (port PORT PROTO FAMILY); #f once a FILE will not stat, after saying so, as
; busybox's xstat stops before any process is matched
(def %fu-wanted
  (fn (self ops acc)
    (if (null? ops) (reverse acc)
      (let ((port (%fu-port-of (first ops))))
        (match
          ((not (null? port)) (self (rest ops) (pair (pair (lit port) port) acc)))
          ((null? (file-stat-full (first ops)))
            (do (file-write 2 (string-concat (list "fuser: can't stat '" (first ops) "': "
                                                   (tar-why (lit stat) (first ops)) "\n")))
                #f))
          (#t (self (rest ops) (pair (pair (lit file) (first ops)) acc))))))))

; the pids, but this process's, that hold any of WANTED, ascending and each
; once; the process table is read only for a port
(def %fu-found
  (fn (_ o fams wanted)
    (def mount? (Opts on? o "-m"))
    (def me (sys-getpid))
    (def ports (filter (fn (_ w) (eq? (first w) (lit port))) wanted))
    (def pids (if (null? ports) ()
                (filter (fn (_ pid) (not (= pid me)))
                  (map (fn (_ p) (Assoc get (lit pid) p)) (ps-sorted (host-processes))))))
    (def ids (List flat-map (fn (_ w) (let ((p (rest w))) (%fu-sockets fams pids (first p) (first (rest p)) (first (rest (rest p)))))) ports))
    (def held
      (List flat-map (fn (_ w) (if (eq? (first w) (lit file)) (host-holders (rest w) mount?) ())) wanted))
    (def all (append held (if (null? ids) () (%fu-socket-holders mount? pids ids))))
    (def uniq (fn (self l acc) (if (null? l) (reverse acc) (self (rest l) (if (if (null? acc) #f (= (first l) (first acc))) acc (pair (first l) acc))))))
    (uniq (List sort < (filter (fn (_ pid) (not (= pid me))) all)) ())))

; each of PIDS printed unless -s and signalled with -k; 0 when there was one
; and every signal went, else 1
(def %fu-act
  (fn (_ o pids signo)
    (def failed (list #f))
    (map (fn (_ pid)
           (do (if (if (Opts on? o "-k") (< (sys-kill pid signo) 0) #f)
                 (do (file-write 2 (string-concat (list "fuser: kill pid " (cu-int->str pid) ": "
                                                        (tar-why (lit kill) (cu-int->str pid)) "\n")))
                     (set-first! failed #t))
                 ())
               (if (Opts on? o "-s") () (display (string-append (cu-int->str pid) " ")))))
         pids)
    (match
      ((null? pids) 1)
      (#t (do (if (Opts on? o "-s") () (display "\n"))
              (if (first failed) 1 0))))))

(provide cu/fuser cu-fuser fu-args)

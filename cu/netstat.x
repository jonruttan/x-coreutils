; # x-coreutils -- the small tools, as applets
;
; ## cu/netstat.x -- netstat: the kernel's sockets and routing table
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's netstat (networking/netstat.c).  The sockets of /proc/net's tcp,
; udp and raw tables, IPv4 and IPv6, and of its unix table: the connected
; ones, or with -l the listening, -a both; -t, -u, -w and -x pick the kinds,
; all of them where none is picked.  -n leaves addresses and ports as
; numbers, -W widens the address columns, -p names the process holding each
; socket, found through /proc/PID/fd.  -r is route's table, in netstat's
; columns unless -e.

(def %nst-say (fn (_ msg) (file-write 2 (string-append "netstat: " msg "\n"))))

(def %nst-tcp-states
  (list "" "ESTABLISHED" "SYN_SENT" "SYN_RECV" "FIN_WAIT1" "FIN_WAIT2" "TIME_WAIT" "CLOSE"
        "CLOSE_WAIT" "LAST_ACK" "LISTEN" "CLOSING"))

; --- addresses ----------------------------------------------------------------------

; a /proc/net address: (FAMILY . BYTES) -- 8 hex digits an IPv4 address, the
; u32 the kernel holds; 32 an IPv6 one, four such u32s
(def %nst-addr
  (fn (_ hex)
    (if (<= (byte-len hex) 8) (pair 4 (%inet-hex hex))
      (pair 6 (List fold (fn (_ acc k)
                           (let ((v (%inet-hex (substring hex (* 8 k) (+ (* 8 k) 8)))))
                             (append acc (map (fn (_ b) (& (>> v (* 8 b)) 255)) (list 0 1 2 3)))))
                         () (List range 0 4))))))

(def %nst-null?
  (fn (_ a) (if (= (first a) 4) (= (rest a) 0) (List all? (fn (_ b) (= b 0)) (rest a)))))

; xmalloc_sockaddr2dotted_noport: the address as numbers
(def %nst-dotted
  (fn (_ a)
    (if (= (first a) 4) (%inet-dotted (rest a))
      (let ((buf (str-make-raw 16)))
        (do (let go ((k 0) (bs (rest a))) (unless (null? bs) (do (%inet-set! buf k (first bs) 1) (go (+ k 1) (rest bs)))))
            (%inet-ntop6-bytes buf))))))

; xmalloc_sockaddr2host_noport: the address's name, nil where it has none
(def %nst-name
  (fn (_ a)
    (if (= (first a) 4) (%inet-addr-host (rest a))
      (let ((buf (str-make-raw 16)))
        (do (let go ((k 0) (bs (rest a))) (unless (null? bs) (do (%inet-set! buf k (first bs) 1) (go (+ k 1) (rest bs)))))
            (%inet-addr-host6 buf))))))

; get_sname: "*" for port 0, the service's name unless NUMERIC?, else the number
(def %nst-service
  (fn (_ port proto numeric?)
    (match
      ((= port 0) "*")
      (numeric? (cu-int->str port))
      (#t (let ((s (%inet-service port proto))) (if (null? s) (cu-int->str port) s))))))

; ip_port_str: ADDRESS:PORT, by name unless NUMERIC?
(def %nst-endpoint
  (fn (_ a port proto numeric?)
    (string-concat (list (let ((n (if numeric? () (%nst-name a)))) (if (null? n) (%nst-dotted a) n))
                         ":" (%nst-service port proto numeric?)))))

; --- the process names, for -p ------------------------------------------------------

; prg_cache_load: (INODE . "PID/NAME") for every socket a process holds, the
; first process found for an inode kept; and whether every process was read
(def %nst-programs
  (fn (_)
    (def pids (filter (fn (_ n) (if (> (byte-len n) 0) (if (>= (byte-at n 0) #\0) (<= (byte-at n 0) #\9) #f) #f))
                      (reverse (guard (_ ()) (file-list-dir "/proc")))))
    (let go ((ps pids) (acc ()) (ok #t))
      (if (null? ps) (pair (reverse acc) ok)
        (let ((cmd (guard (_ ()) (file-read-unsized (string-concat (list "/proc/" (first ps) "/cmdline"))))))
          (if (null? cmd) (go (rest ps) acc #f)
            (let ((name (%nst-prog-name (first ps) cmd)))
              (go (rest ps)
                  (List fold (fn (_ a fd)
                               (let ((inode (%nst-socket-inode (guard (_ "") (file-readlink (string-concat (list "/proc/" (first ps) "/fd/" fd)))))))
                                 (if (if (null? inode) #t (not (null? (Assoc entry inode a)))) a (pair (pair inode name) a))))
                             acc (reverse (guard (_ ()) (file-list-dir (string-concat (list "/proc/" (first ps) "/fd"))))))
                  ok))))))))

; "PID/" and the base name of the command line's first word, nineteen at most
(def %nst-prog-name
  (fn (_ pid cmd)
    (def nul (%dp-find cmd 0 #\null))
    (def argv0 (if (< nul 0) cmd (substring cmd 0 nul)))
    (def slash (let go ((i (- (byte-len argv0) 1))) (match ((< i 0) -1) ((= (byte-at argv0 i) #\/) i) (#t (go (- i 1))))))
    (def s (string-concat (list pid "/" (substring argv0 (+ slash 1) (byte-len argv0)))))
    (if (> (byte-len s) 19) (substring s 0 19) s)))

; extract_socket_inode: socket:[N] or [0000]:N's N, nil for any other link
(def %nst-socket-inode
  (fn (_ link)
    (match
      ((if (Str8 starts? "socket:[" link) (Str8 ends? "]" link) #f) (cu-num-prefix (substring link 8 (- (byte-len link) 1))))
      ((Str8 starts? "[0000]:" link) (cu-num-prefix (substring link 7 (byte-len link))))
      (#t ()))))

; --- the tables -----------------------------------------------------------------------

; one tcp, udp or raw line of /proc/net, as scan_inet_proc_line reads it:
; (LOCAL LPORT REMOTE RPORT STATE TXQ RXQ INODE), nil for a line it cannot read
(def %nst-inet-line
  (fn (_ line)
    (def w (%inet-words line))
    (def ep (fn (_ s) (let ((c (%dp-find s 0 #\:))) (if (< c 0) () (pair (substring s 0 c) (%inet-hex (substring s (+ c 1) (byte-len s))))))))
    (if (< (length w) 10) ()
      (let ((l (ep (List ref 1 w))) (r (ep (List ref 2 w))) (q (ep (List ref 4 w))))
        (if (if (null? l) #t (if (null? r) #t (null? q))) ()
          (list (%nst-addr (first l)) (rest l) (%nst-addr (first r)) (rest r) (%inet-hex (List ref 3 w))
                (%inet-hex (first q)) (rest q) (cu-num-prefix (List ref 9 w))))))))

; print_inet_line: one socket, where its side (CONNECTED?) is asked for
(def %nst-inet-print
  (fn (_ st p state proto connected?)
    (when (if connected? (List ref 0 st) (List ref 1 st))
      (let ((numeric? (List ref 2 st)) (width (List ref 3 st)) (progs (List ref 4 st)))
        (file-write 1
          (string-concat
            (list proto "   " (cu-pad-left (cu-int->str (List ref 6 p)) 6) " " (cu-pad-left (cu-int->str (List ref 5 p)) 6) " "
                  (%inet-left (%nst-endpoint (List ref 0 p) (List ref 1 p) proto numeric?) width) " "
                  (%inet-left (%nst-endpoint (List ref 2 p) (List ref 3 p) proto numeric?) width) " "
                  (%inet-left state 12)
                  (if (null? progs) ""
                    (let ((e (Assoc entry (List ref 7 p) progs))) (if (null? e) "-" (rest e))))
                  "\n")))))))

; do_info: FILE's lines after its first, each through DO-ONE, a line it
; cannot read said as bogus
(def %nst-table
  (fn (_ file do-one)
    (let ((text (file-or-err (fn (_) (file-read-unsized file)))))
      (if (Err err? text)
        (%nst-say (string-concat (list file ": " (libc-strerror (Err errno-of -1)))))
        (let go ((ls (rest (cu-lines text))) (n 2))
          (unless (null? ls)
            (do (unless (do-one (first ls)) (%nst-say (string-concat (list file ": bogus data on line " (cu-int->str n)))))
                (go (rest ls) (+ n 1)))))))))

(def %nst-tcp
  (fn (_ st)
    (fn (_ line)
      (let ((p (%nst-inet-line line)))
        (if (null? p) #f
          (do (%nst-inet-print st p (let ((s (List ref 4 p))) (if (< s 12) (List ref s %nst-tcp-states) "")) "tcp" (not (= (List ref 3 p) 0))) #t))))))

(def %nst-udp
  (fn (_ st)
    (fn (_ line)
      (let ((p (%nst-inet-line line)))
        (if (null? p) #f
          (do (%nst-inet-print st p (match ((= (List ref 4 p) 1) "ESTABLISHED") ((= (List ref 4 p) 7) "") (#t "UNKNOWN"))
                              "udp" (not (%nst-null? (List ref 2 p))))
              #t))))))

(def %nst-raw
  (fn (_ st)
    (fn (_ line)
      (let ((p (%nst-inet-line line)))
        (if (null? p) #f
          (do (%nst-inet-print st p (cu-int->str (List ref 4 p)) "raw" (not (%nst-null? (List ref 2 p)))) #t))))))

; unix_do_one: one socket of /proc/net/unix
(def %nst-unix
  (fn (_ st)
    (fn (_ line)
      (def w (%inet-words line))
      (if (= (byte-len line) 0) #t
        (if (< (length w) 7) #f
          (let ((refcnt (%inet-hex (List ref 1 w))) (proto (%inet-hex (List ref 2 w))) (fl (%inet-hex (List ref 3 w)))
                (type (%inet-hex (List ref 4 w))) (state (%inet-hex (List ref 5 w))) (inode (cu-num-prefix (List ref 6 w))))
            (do
                (when (if (if (List ref 0 st) (List ref 1 st) #f) #t
                        (if (if (= state 1) (not (= (& fl 65536) 0)) #f) (List ref 1 st) (List ref 0 st)))
                  (file-write 1
                    (string-concat
                      (list (%inet-left (if (= proto 0) "unix" "??") 5) " " (%inet-left (cu-int->str refcnt) 6) " "
                            (%inet-left (string-concat (list "[ " (if (= (& fl 65536) 0) "" "ACC ") (if (= (& fl 131072) 0) "" "W ")
                                                             (if (= (& fl 262144) 0) "" "N ") "]")) 11) " "
                            (%inet-left (match ((= type 1) "STREAM") ((= type 2) "DGRAM") ((= type 3) "RAW") ((= type 4) "RDM")
                                               ((= type 5) "SEQPACKET") (#t "UNKNOWN")) 10) " "
                            (%inet-left (match ((= state 0) "FREE") ((= state 1) (if (= (& fl 65536) 0) "" "LISTENING"))
                                               ((= state 2) "CONNECTING") ((= state 3) "CONNECTED") ((= state 4) "DISCONNECTING")
                                               (#t "UNKNOWN")) 13) " "
                            (cu-pad-left (cu-int->str inode) 6) " "
                            (let ((progs (List ref 4 st)))
                              (if (null? progs) "" (%inet-left (let ((e (Assoc entry inode progs))) (if (null? e) "-" (rest e))) 20)))
                            (if (>= (length w) 8) (List ref 7 w) "") "\n"))))
                #t)))))))

; the heading's words for which sides are shown
(def %nst-which
  (fn (_ st)
    (match ((if (List ref 0 st) (List ref 1 st) #f) "(servers and established)")
           ((List ref 1 st) "(only servers)")
           (#t "(w/o servers)"))))

(def %cu-netstat
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "netstat" argv))
    (def on? (fn (_ f) (Opts on? o f)))
    (def listen (if (on? "-a") #t (on? "-l")))
    (def connected (if (on? "-a") #t (not (on? "-l"))))
    (def kinds (filter on? (list "-t" "-u" "-w" "-x")))
    (def want? (fn (_ k) (if (null? kinds) #t (List find (fn (_ x) (string=? x k)) kinds))))
    (if (on? "-r") (%rt-show4 (on? "-n") (not (on? "-e")))
      (let ((progs (if (on? "-p") (%nst-load-programs) ())))
        (def st (list connected listen (on? "-n") (if (on? "-W") 51 23) (if (on? "-p") progs ())))
        (def banner (if (on? "-p") "PID/Program name    " ""))
        (when (if (want? "-t") #t (if (want? "-u") #t (want? "-w")))
          (file-write 1 (string-concat (list "Active Internet connections " (%nst-which st) "\nProto Recv-Q Send-Q "
                                             (%inet-left "Local Address" (List ref 3 st)) " " (%inet-left "Foreign Address" (List ref 3 st))
                                             " State       " banner "\n"))))
        (when (want? "-t") (do (%nst-table "/proc/net/tcp" (%nst-tcp st)) (%nst-table "/proc/net/tcp6" (%nst-tcp st))))
        (when (want? "-u") (do (%nst-table "/proc/net/udp" (%nst-udp st)) (%nst-table "/proc/net/udp6" (%nst-udp st))))
        (when (want? "-w") (do (%nst-table "/proc/net/raw" (%nst-raw st)) (%nst-table "/proc/net/raw6" (%nst-raw st))))
        (when (want? "-x")
          (do (file-write 1 (string-concat (list "Active UNIX domain sockets " (%nst-which st)
                                                 "\nProto RefCnt Flags       Type       State         I-Node " banner "Path\n")))
              (%nst-table "/proc/net/unix" (%nst-unix st))))
        0))))

; prg_cache_load, and what it says where a process could not be read
(def %nst-load-programs
  (fn (_)
    (let ((r (%nst-programs)))
      (do (unless (rest r)
            (%nst-say (if (null? (first r)) "can't scan /proc - are you root?" "showing only processes with your user ID")))
          (first r)))))

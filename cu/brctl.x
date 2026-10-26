; # x-coreutils -- the small tools, as applets
;
; ## cu/brctl.x -- brctl: ethernet bridges made, joined, set and shown
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's brctl with FEATURE_BRCTL_FANCY and FEATURE_BRCTL_SHOW
; (networking/brctl.c).  addbr and delbr make and remove a bridge, addif
; and delif join an interface to one and take it out, through the kernel's
; SIOCBR ioctls; the rest read and write the files under /sys/class/net.
; show lists the bridges with their ids, STP and interfaces, showmacs a
; bridge's forwarding database sorted by address, showstp its STP state
; and each port's; stp, setageing, setfd, sethello, setmaxage,
; setbridgeprio, setpathcost and setportprio write a setting, the times in
; seconds made hundredths as strtod reads them.
;
; busybox works from /sys/class/net, so the paths its messages name are
; relative to it, a name in them cut to 16 bytes; setpathcost and
; setportprio pass over the bridge they are given, as busybox's do.

(module cu/brctl)

(import cu/cli cu-usage)
(import cu/inet inet-set! inet-zeros)
(import cu/inetd in-c in-call)
(import cu/ping pn-div pn-number)
(import cu/prims byte-at byte-len cu-err-label cu-int->str cu-ptr-call
  cu-ptr-ref cu-str->ptr cu-string-type cvt file-list-dir file-read-unsized
  file-write length libc-strerror map reverse string-append string-concat
  string=? substring)
(import cu/text cu-pad-left cu-pad-zero)

(def %br-root "/sys/class/net/")

(def %br-say (fn (_ msg) (file-write 2 (string-concat (list "brctl: " msg "\n")))))
(def %br-die (fn (_ msg) (do (%br-say msg) (Err raise (lit brctl) msg ()))))
(def %br-usage (fn (_) (Err raise (lit brctl-usage) "usage" ())))
(def %br-out (fn (_ s) (file-write 1 s)))

; a name as the paths carry it, %.16s
(def %br-16 (fn (_ name) (if (> (byte-len name) 16) (substring name 0 16) name)))

; read_file: PATH's text under /sys/class/net, one newline off its end, or
; nil where it will not open
(def %br-read
  (fn (_ path)
    (def t (guard (e (if (eq? (cu-err-label e) (lit io)) () (error e)))
             (file-read-unsized (string-append %br-root path))))
    (match ((null? t) ())
           ((if (> (byte-len t) 0) (= (byte-at t (- (byte-len t) 1)) 10) #f) (substring t 0 (- (byte-len t) 1)))
           (#t t))))

(def %br-text (fn (_ path) (let ((t (%br-read path))) (if (null? t) "" t))))

; the entries of PATH under /sys/class/net in the kernel's order, none
; where it will not open
(def %br-dir
  (fn (_ path)
    (reverse (guard (e (if (eq? (cu-err-label e) (lit io)) () (error e)))
               (file-list-dir (string-append %br-root path))))))

; xstrtou(S, 0): 0x hex, 0 octal, else decimal, all of S
(def %br-number
  (fn (_ s)
    (def n (byte-len s))
    (def hex? (if (> n 2) (if (= (byte-at s 0) #\0) (= (| (byte-at s 1) 32) #\x) #f) #f))
    (def base (match (hex? 16) ((if (> n 1) (= (byte-at s 0) #\0) #f) 8) (#t 10)))
    (def digit (fn (_ c) (match ((if (>= c #\0) (<= c #\9) #f) (- c #\0))
                                ((if (>= (| c 32) #\a) (<= (| c 32) #\f) #f) (+ 10 (- (| c 32) #\a)))
                                (#t 99))))
    (let go ((i (if hex? 2 0)) (v 0))
      (match ((= n 0) (%br-die "invalid number ''"))
             ((>= i n) v)
             ((>= (digit (byte-at s i)) base) (%br-die (string-concat (list "invalid number '" s "'"))))
             (#t (go (+ i 1) (+ (* v base) (digit (byte-at s i)))))))))

(def %br-hex4 (fn (_ v) (cu-pad-zero (cvt v cu-string-type 16) 4)))
(def %br-u4 (fn (_ v) (cu-pad-left (cu-int->str v) 4)))

; show_bridge_timer: hundredths as SECONDS.HH, the seconds four wide
(def %br-timer
  (fn (_ text)
    (def c (%br-number text))
    (string-concat (list (%br-u4 (pn-div c 100)) "." (cu-pad-zero (cu-int->str (% c 100)) 2)))))

; --- show ------------------------------------------------------------------------

; show_bridge: NAME's line and its interfaces' lines, the header before them
; where HDR; #f where NAME is no bridge
(def %br-show-one
  (fn (_ name hdr)
    (def base (string-append (%br-16 name) "/bridge/"))
    (def id (%br-read (string-append base "bridge_id")))
    (if (null? id) #f
      (do (when hdr (%br-out "bridge name\tbridge id\t\tSTP enabled\tinterfaces\n"))
          (let ((stp (%br-text (string-append base "stp_state")))
                (ifs (%br-dir (string-append (%br-16 name) "/brif"))))
            (do (%br-out (string-concat (list name "\t\t" id "\t" (match ((string=? stp "0") "no") ((string=? stp "1") "yes") (#t stp)))))
                (if (null? ifs) (%br-out "\n")
                  (%br-out (string-concat (List map (fn (_ k) (string-concat (list (if (= k 0) "" "\t\t\t\t\t") "\t\t" (List ref k ifs) "\n")))
                                                    (List range 0 (List length ifs))))))
                #t))))))

(def %br-show
  (fn (_ names)
    (if (null? names)
      (do (List fold (fn (_ hdr n) (if (%br-show-one n hdr) #f hdr)) #t (%br-dir "")) 0)
      (let go ((ns names) (hdr #t) (st 0))
        (if (null? ns) st
          (if (%br-show-one (first ns) hdr) (go (rest ns) #f st)
            (do (%br-say (string-concat (list "bridge " (first ns) " does not exist"))) (go (rest ns) hdr 1))))))))

; --- showmacs --------------------------------------------------------------------

; the forwarding database's entries, each its 16 bytes as a list, by address
(def %br-fdb
  (fn (_ name)
    (def path (string-append (%br-16 name) "/brforward"))
    (def fd (in-call (cu-ptr-call (in-c "open") (string-append %br-root path) 0)))
    (when (< fd 0) (%br-die (string-concat (list "bridge " name " does not exist"))))
    (def buf (inet-zeros 16))
    (def entries
      (let go ((acc ()))
        (let ((n (in-call (cu-ptr-call (in-c "read") fd (cu-str->ptr buf) 16))))
          (match ((= n 0) acc)
                 ((not (= n 16))
                   (do (cu-ptr-call (in-c "close") fd)
                       (%br-die (string-concat (list "can't read bridge " name " forward db"
                                                     (if (< n 0) (string-append ": " (libc-strerror (Err errno-of n))) ""))))))
                 (#t (go (pair (List map (fn (_ i) (& (cu-ptr-ref (cu-str->ptr buf) i 1) 255)) (List range 0 16)) acc)))))))
    (cu-ptr-call (in-c "close") fd)
    (def mac< (fn (_ a b) (let go ((i 0)) (match ((= i 6) #f) ((< (List ref i a) (List ref i b)) #t)
                                                  ((> (List ref i a) (List ref i b)) #f) (#t (go (+ i 1)))))))
    (List sort mac< (reverse entries))))

(def %br-showmacs
  (fn (_ name)
    (def rows (%br-fdb name))
    (%br-out "port no\tmac addr\t\tis local?\tageing timer\n")
    (List map (fn (_ e)
                (let ((age (| (List ref 8 e) (<< (List ref 9 e) 8) (<< (List ref 10 e) 16) (<< (List ref 11 e) 24))))
                  (%br-out (string-concat (list (cu-pad-left (cu-int->str (List ref 6 e)) 3) "\t"
                                                (Str8 join ":" (List map (fn (_ i) (cu-pad-zero (cvt (List ref i e) cu-string-type 16) 2)) (List range 0 6)))
                                                "\t" (if (= (List ref 7 e) 0) "no" "yes") "\t\t"
                                                (%br-u4 (pn-div age 100)) "." (cu-pad-zero (cu-int->str (% age 100)) 2) "\n")))))
              rows)
    0))

; --- showstp ---------------------------------------------------------------------

(def %br-states (list "disabled" "listening" "learning" "forwarding" "blocking"))

; show_bridge_port: PORT's STP state, from its brport files
(def %br-port
  (fn (_ port)
    (def f (fn (_ leaf) (%br-text (string-concat (list (%br-16 port) "/brport/" leaf)))))
    (def n (fn (_ leaf) (%br-number (f leaf))))
    (def state (n "state"))
    (string-concat
      (list port " (" (cu-int->str (n "port_no")) ")\n"
            " port id\t\t" (%br-hex4 (n "port_id"))
            "\t\t\tstate\t\t" (cu-pad-left (if (< state 5) (List ref state %br-states) (cu-int->str state)) 15) "\n"
            " designated root\t" (f "designated_root")
            "\tpath cost\t\t" (%br-u4 (n "path_cost")) "\n"
            " designated bridge\t" (f "designated_bridge")
            "\tmessage age timer\t" (%br-timer (f "message_age_timer"))
            "\n designated port\t" (%br-hex4 (n "designated_port"))
            "\t\t\tforward delay timer\t" (%br-timer (f "forward_delay_timer"))
            "\n designated cost\t" (%br-u4 (n "designated_cost"))
            "\t\t\thold timer\t\t" (%br-timer (f "hold_timer"))
            "\n flags\t\t\t"
            (if (string=? (f "config_pending") "0") "" "CONFIG_PENDING ")
            (if (string=? (f "change_ack") "0") "" "TOPOLOGY_CHANGE_ACK ")
            (let ((h (f "hairpin_mode"))) (if (string=? h "0") "" (string-append "\n hairpin mode\t\t" (%br-u4 (%br-number h)))))
            "\n\n"))))

(def %br-showstp
  (fn (_ name)
    (def base (string-append (%br-16 name) "/bridge/"))
    (def id (%br-read (string-append base "bridge_id")))
    (when (null? id) (%br-die (string-concat (list "bridge " name " does not exist"))))
    (def f (fn (_ leaf) (%br-text (string-append base leaf))))
    (def n (fn (_ leaf) (%br-number (f leaf))))
    (def t (fn (_ leaf) (%br-timer (f leaf))))
    (%br-out
      (string-concat
        (list name "\n bridge id\t\t" id
              "\n designated root\t" (f "root_id")
              "\n root port\t\t" (%br-u4 (n "root_port")) "\t\t\t"
              "path cost\t\t" (%br-u4 (n "root_path_cost")) "\n"
              " max age\t\t" (t "max_age") "\t\t\tbridge max age\t\t" (t "max_age")
              "\n hello time\t\t" (t "hello_time") "\t\t\tbridge hello time\t" (t "hello_time")
              "\n forward delay\t\t" (t "forward_delay") "\t\t\tbridge forward delay\t" (t "forward_delay")
              "\n ageing time\t\t" (t "ageing_time")
              "\n hello timer\t\t" (t "hello_timer")
              "\t\t\ttcn timer\t\t" (t "tcn_timer")
              "\n topology change timer\t" (t "topology_change_timer")
              "\t\t\tgc timer\t\t" (t "gc_timer")
              "\n flags\t\t\t"
              (if (string=? (f "topology_change") "0") "" "TOPOLOGY_CHANGE ")
              (if (string=? (f "topology_change_detected") "0") "" "TOPOLOGY_CHANGE_DETECTED ")
              "\n\n\n")))
    (List map (fn (_ p) (%br-out (%br-port p))) (%br-dir (string-append (%br-16 name) "/brif")))
    0))

; --- the settings ----------------------------------------------------------------

; write_uint: "VAL\n" to NAME/LEAF under /sys/class/net
(def %br-write
  (fn (_ name leaf val)
    (def path (string-concat (list (%br-16 name) "/" leaf)))
    (def fd (in-call (cu-ptr-call (in-c "open") (string-append %br-root path) 1)))
    (when (< fd 0) (%br-die (string-concat (list "can't open '" path "': " (libc-strerror (Err errno-of fd))))))
    (def s (string-append (cu-int->str val) "\n"))
    (def r (in-call (cu-ptr-call (in-c "write") fd s (byte-len s))))
    (cu-ptr-call (in-c "close") fd)
    (when (< r 0) (%br-die (string-concat (list name ": " (libc-strerror (Err errno-of r))))))
    0))

(def %br-space? (fn (_ c) (if (= c 32) #t (if (>= c 9) (<= c 13) #f))))

; the span strtod reads of S from I: the sign, then decimal digits with a
; dot and an exponent, hex digits after 0x, or inf or nan; I where none
(def %br-strtod-end
  (fn (_ s i)
    (def n (byte-len s))
    (def at (fn (_ k) (if (< k n) (| (byte-at s k) 32) 0)))
    (def dec? (fn (_ c) (if (>= c #\0) (<= c #\9) #f)))
    (def hex? (fn (_ c) (if (dec? c) #t (if (>= c #\a) (<= c #\f) #f))))
    (def digits (fn (self k ok?) (if (ok? (at k)) (self (+ k 1) ok?) k)))
    (def j (if (if (= (at i) #\-) #t (= (at i) #\+)) (+ i 1) i))
    (def word? (fn (_ w) (let go ((k 0)) (if (= k (byte-len w)) #t (if (= (at (+ j k)) (byte-at w k)) (go (+ k 1)) #f)))))
    (match
      ((word? "infinity") (+ j 8))
      ((word? "inf") (+ j 3))
      ((word? "nan") (+ j 3))
      (#t (let ((x? (if (= (at j) #\0) (if (= (at (+ j 1)) #\x) (hex? (at (+ j 2))) #f) #f)))
            (let ((ok? (if x? hex? dec?)) (from (if x? (+ j 2) j)))
              (let ((a (digits from ok?)))
                (let ((b (if (= (at a) #\.) (digits (+ a 1) ok?) a)))
                  (if (= b (if (= (at a) #\.) (+ from 1) from)) i
                    (let ((e (at b)) (mark (if x? #\p #\e)))
                      (if (= e mark)
                        (let ((k (if (if (= (at (+ b 1)) #\-) #t (= (at (+ b 1)) #\+)) (+ b 2) (+ b 1))))
                          (if (dec? (at k)) (digits k dec?) b))
                        b)))))))))))

; str_to_jiffies: S's seconds as hundredths, capped at INT_MAX
(def %br-jiffies
  (fn (_ s)
    (def i (%br-span-space s 0))
    (def e (%br-strtod-end s i))
    (def bad (fn (_) (%br-die (string-concat (list "invalid argument '" s "' to 'timespec'")))))
    (when (= e i) (bad))
    (def w (Str8 downcase (substring s i e)))
    (def neg? (= (byte-at w 0) #\-))
    (def body (if (if neg? #t (= (byte-at w 0) #\+)) (substring w 1 (byte-len w)) w))
    (match
      ((if (>= (byte-len body) 3) (string=? (substring body 0 3) "nan") #f) (bad))
      ((if (>= (byte-len body) 3) (string=? (substring body 0 3) "inf") #f) (if neg? (bad) 2147483647))
      (#t (let ((d (Float from (string-append (if neg? "-" "") body))))
            (if (Float < d (Float from 0)) (bad)
              (let ((dd (Float * d (Float from 100))))
                (if (Float < (Float from 2147483647) dd) 2147483647 (Float ->int dd)))))))))

(def %br-span-space (fn (_ s i) (if (if (< i (byte-len s)) (%br-space? (byte-at s i)) #f) (%br-span-space s (+ i 1)) i)))

(def %br-stp
  (fn (_ br word)
    (def words (list "0" "off" "n" "no" "1" "on" "y" "yes"))
    (def k (List find-index (fn (_ w) (string=? w word)) words))
    (when (null? k) (%br-die (string-concat (list "invalid argument '" word "' to 'brctl'"))))
    (%br-write br "bridge/stp_state" (if (< k 4) 0 1))))

; --- the ioctls ------------------------------------------------------------------

(def %br-socket
  (fn (_)
    (let ((fd (in-call (cu-ptr-call (in-c "socket") 2 1 0))))
      (if (< fd 0) (%br-die (string-append "socket(AF_INET,1,0): " (libc-strerror (Err errno-of fd)))) fd))))

; NAME in a zeroed buffer, IFNAMSIZ bytes of it
(def %br-name-buf
  (fn (_ name size)
    (let ((b (inet-zeros size)))
      (do (List map (fn (_ i) (inet-set! b i (byte-at name i) 1)) (List range 0 (if (> (byte-len name) 16) 16 (byte-len name))))
          b))))

(def %br-ioctl
  (fn (_ req arg br)
    (def fd (%br-socket))
    (def r (in-call (cu-ptr-call (in-c "ioctl") fd req (cu-str->ptr arg))))
    (cu-ptr-call (in-c "close") fd)
    (when (< r 0) (%br-die (string-concat (list "bridge " br ": " (libc-strerror (Err errno-of r))))))
    0))

; addif and delif: IFACE's index in an ifreq naming BR
(def %br-if
  (fn (_ req br iface)
    (def index (cu-ptr-call (in-c "if_nametoindex") iface))
    (when (= index 0) (%br-die (string-concat (list "iface " iface ": " (libc-strerror (Err errno-of (- 0 1)))))))
    (def ifr (%br-name-buf br 40))
    (inet-set! ifr 16 index 4)
    (%br-ioctl req ifr br)))

; --- the commands ----------------------------------------------------------------

(def %br-keywords
  (list "addbr" "delbr" "addif" "delif" "stp" "showstp" "setageing" "setfd" "sethello" "setmaxage"
        "setpathcost" "setportprio" "setbridgeprio" "showmacs" "show"))

(def %br-leaves
  (list (pair "setageing" "bridge/ageing_time") (pair "setfd" "bridge/forward_delay")
        (pair "sethello" "bridge/hello_time") (pair "setmaxage" "bridge/max_age")))

; KEY, a command other than show, on its words ARGS: the bridge, then the rest
(def %br-command
  (fn (_ key args)
    (when (null? args) (%br-usage))
    (def br (first args))
    (def more (rest args))
    (def leaf (List find (fn (_ l) (string=? (first l) key)) %br-leaves))
    (match
      ((string=? key "addbr") (%br-ioctl 35232 (%br-name-buf br 32) br))
      ((string=? key "delbr") (%br-ioctl 35233 (%br-name-buf br 32) br))
      ((string=? key "showmacs") (%br-showmacs br))
      ((string=? key "showstp") (%br-showstp br))
      ((null? more) (%br-usage))
      ((string=? key "stp") (%br-stp br (first more)))
      ((not (null? leaf)) (%br-write br (rest leaf) (%br-jiffies (first more))))
      ((string=? key "setbridgeprio") (%br-write br "bridge/priority" (pn-number (first more) 0 2147483647 %br-die)))
      ((if (string=? key "setpathcost") #t (string=? key "setportprio"))
        (if (null? (rest more)) (%br-usage)
          (%br-write (first more) (if (string=? key "setpathcost") "brport/path_cost" "brport/priority")
                     (pn-number (first (rest more)) 0 2147483647 %br-die))))
      (#t (%br-if (if (string=? key "addif") 35234 35235) br (first more))))))

(def %br-main
  (fn (_ words)
    (when (null? words) (%br-usage))
    (unless (pair? (guard (e (if (eq? (cu-err-label e) (lit io)) () (error e))) (list (file-list-dir %br-root))))
      (%br-die "can't change directory to '/sys/class/net': No such file or directory"))
    (def key (first words))
    (unless (List find (fn (_ k) (string=? k key)) %br-keywords)
      (%br-die (string-concat (list "invalid argument '" key "' to 'brctl'"))))
    (if (string=? key "show") (%br-show (rest words)) (%br-command key (rest words)))))

(def cu-brctl
  (fn (_ argv stdin-thunk)
    (guard (e (match ((eq? (cu-err-label e) (lit brctl-usage)) (cu-usage "brctl"))
                     ((eq? (cu-err-label e) (lit brctl)) 1)
                     (#t (error e))))
      (%br-main argv))))

(provide cu/brctl cu-brctl)

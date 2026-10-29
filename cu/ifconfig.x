; # x-coreutils -- the small tools, as applets
;
; ## cu/ifconfig.x -- ifconfig: the kernel's network interfaces, shown and set
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's ifconfig (networking/ifconfig.c) and the display it shares with
; networking/interface.c.  With no word, or one, the interfaces that are up
; (-a: all of them, IFACE: that one), sorted by name from /proc/net/dev and
; SIOCGIFCONF, each with its hardware address, IPv4 addresses, IPv6 ones
; from /proc/net/if_inet6, flags, MTU and metric, and its counters.  With
; more, IFACE and what to set: an address, netmask, broadcast, pointopoint,
; dstaddr, hw ether, metric, mtu, txqueuelen, mem_start, io_addr, irq,
; keepalive, outfill, add and del (IPv6), and the flags up, down, arp,
; trailers, promisc, multicast, allmulti and dynamic, a leading - clearing
; one -- each the SIOCSIF ioctl busybox makes.

(module cu/ifconfig)

(import cu/arp ar-ether)
(import cu/cli cu-usage)
(import cu/dump dp-find)
(import cu/inet inet-aton inet-dotted inet-hex inet-host-addr inet-left
  inet-ntop6 inet-pton6! inet-set! inet-sin! inet-socket inet-words inet-zeros)
(import cu/inetd in-call)
(import cu/prims append byte-at byte-len cal/ char->integer cu-err-label
  cu-int->ptr cu-int->str cu-libc-sym cu-lines cu-ptr->str cu-ptr-call
  cu-ptr-ref cu-ptr-set! cu-str->ptr cu-string-type cvt file-or-err
  file-read-unsized file-write filter length libc-strerror map reverse
  set-first! string-append string=? substring)
(import cu/strings cu-range-number)
(import cu/sysctl sy-trim)
(import cu/telnetd td-ptr->int)
(import cu/text cu-num-prefix cu-pad-zero)

(def %if-say (fn (_ msg) (file-write 2 (string-append "ifconfig: " msg "\n"))))
(def %if-die (fn (_ msg) (do (%if-say msg) (Err raise (lit ifconfig) msg ()))))
(def %if-usage (fn (_) (Err raise (lit ifconfig-usage) "usage" ())))

; --- an ifreq ---------------------------------------------------------------------

; a zeroed ifreq naming NAME
(def if-req
  (fn (_ name)
    (let ((r (inet-zeros 40)))
      (do (map (fn (_ k) (inet-set! r k (char->integer (byte-at name k)) 1))
               (List range 0 (if (> (byte-len name) 15) 15 (byte-len name))))
          r))))

(def if-ref (fn (_ r at n) (cu-ptr-ref (cu-str->ptr r) at n)))

; REQ on an AF_INET datagram socket with R; the call's answer
(def %if-ioctl
  (fn (_ req r)
    (let ((fd (inet-socket 2 %if-die)))
      (let ((n (in-call (cu-ptr-call (cu-libc-sym "ioctl") fd req (cu-str->ptr r)))))
        (do (cu-ptr-call (cu-libc-sym "close") fd) n)))))

; an IPv4 address at AT of R, as the u32 the kernel holds
(def %if-sin (fn (_ r at) (if-ref r (+ at 4) 4)))

; --- the interfaces ---------------------------------------------------------------

; /proc/net/dev's counters for each interface: ((NAME . FIELDS) ...), FIELDS
; busybox's sixteen numbers in its order
(def %if-dev
  (fn (_)
    (let ((text (file-or-err (fn (_) (file-read-unsized "/proc/net/dev")))))
      (if (Err err? text) ()
        (filter (fn (_ e) (not (null? e)))
                (map (fn (_ line)
                       (let ((c (dp-find line 0 #\:)))
                         (if (< c 0) ()
                           (pair (sy-trim (substring line 0 c))
                                 (map cu-num-prefix (inet-words (substring line (+ c 1) (byte-len line))))))))
                     (rest (rest (cu-lines text)))))))))

; SIOCGIFCONF's interfaces: those with an IPv4 address, aliases among them
(def %if-conf
  (fn (_)
    (def n 64)
    (def buf (inet-zeros (* n 40)))
    (def ifc (inet-zeros 16))
    (inet-set! ifc 0 (* n 40) 4)
    (cu-ptr-set! (cu-str->ptr ifc) 8 (td-ptr->int (cu-str->ptr buf)) 8)
    (if (< (%if-ioctl 35090 ifc) 0) ()
      (map (fn (_ k) (cu-ptr->str (cu-int->ptr (+ (td-ptr->int (cu-str->ptr buf)) (* 40 k)))))
           (List range 0 (cal/ (if-ref ifc 0 4) 40))))))

; the entry of ENTRIES named NAME, a string, or nil
(def %if-find (fn (_ name entries) (List find (fn (_ e) (string=? (first e) name)) entries)))

; the names in busybox's order, strcmp's, each once, its counters where
; /proc/net/dev has them
(def %if-sorted
  (fn (_ entries)
    (List sort (fn (_ a b) (Str8 <? (first a) (first b)))
          (List fold (fn (_ acc e) (if (null? (%if-find (first e) acc)) (pair e acc) acc)) () entries))))

; if_fetch: what the kernel says of NAME, or nil where it says nothing
(def %if-fetch
  (fn (_ name)
    (def r (if-req name))
    (if (< (%if-ioctl 35091 r) 0) ()
      (let ((get (fn (_ req at n) (let ((q (if-req name))) (if (< (%if-ioctl req q) 0) () (if-ref q at n))))))
        (def flags (if-ref r 16 2))
        (def hw (let ((q (if-req name))) (do (%if-ioctl 35111 q) q)))
        (def addr (let ((q (if-req name))) (do (inet-set! q 16 2 2) (if (< (%if-ioctl 35093 q) 0) () q))))
        (list flags (if-ref hw 16 2) (map (fn (_ k) (if-ref hw (+ 18 k) 1)) (List range 0 8))
              (let ((m (get 35101 16 4))) (if (null? m) 0 m)) (let ((m (get 35105 16 4))) (if (null? m) 0 m))
              (let ((q (if-req name))) (if (< (%if-ioctl 35184 q) 0) (list 0 0 0 0) (list (if-ref q 32 2) (if-ref q 34 1) (if-ref q 16 8) (if-ref q 24 8) (if-ref q 35 1))))
              (let ((t (get 35138 16 4))) (if (null? t) -1 t))
              (if (null? addr) ()
                (list (%if-sin addr 16) (get 35095 20 4) (get 35097 20 4) (get 35099 20 4))))))))

; --- display ----------------------------------------------------------------------

(def %if-hwtitles
  (list (list 772 "Local Loopback" #f) (list 1 "Ethernet" #t) (list 512 "Point-to-Point Protocol" #f)
        (list 776 "IPv6-in-IPv4" (lit unspec-suppress))))

; the flags ife_print names, in its order
(def %if-flag-names
  (list (pair 1 "UP") (pair 2 "BROADCAST") (pair 4 "DEBUG") (pair 8 "LOOPBACK") (pair 16 "POINTOPOINT")
        (pair 32 "NOTRAILERS") (pair 64 "RUNNING") (pair 128 "NOARP") (pair 256 "PROMISC") (pair 512 "ALLMULTI")
        (pair 2048 "SLAVE") (pair 1024 "MASTER") (pair 4096 "MULTICAST")))

(def %if-hex2 (fn (_ b) (cu-pad-zero (Str8 upcase (cvt b cu-string-type 16)) 2)))

; print_bytes_scaled: "X bytes:N (I.F UNITB)"
(def %if-scaled
  (fn (_ n)
    (let go ((i 4) (int n) (frac 0) (ext ""))
      (if (= i 0) (%str-concat (list "X bytes:" (cu-int->str n) " (" (cu-int->str int) "." (cu-int->str frac) " " ext "B)"))
        (if (>= int 1024)
          (go (- i 1) (cal/ int 1024) (cal/ (* (& int 1023) 10) 1024)
              (match ((string=? ext "") "Ki") ((string=? ext "Ki") "Mi") ((string=? ext "Mi") "Gi") (#t "Ti")))
          (go (- i 1) int frac ext))))))

; ife_print6: NAME's IPv6 addresses, from /proc/net/if_inet6
(def %if-inet6
  (fn (_ name)
    (let ((text (file-or-err (fn (_) (file-read-unsized "/proc/net/if_inet6")))))
      (if (Err err? text) ""
        (%str-concat
          (map (fn (_ line)
                 (let ((w (inet-words line)))
                   (if (if (>= (length w) 6) (string=? (List ref 5 w) name) #f)
                     (let ((scope (& (inet-hex (List ref 3 w)) 240)))
                       (%str-concat
                         (list "          inet6 addr: " (inet-ntop6 (first w)) "/" (cu-int->str (inet-hex (List ref 2 w)))
                               " Scope:" (match ((= scope 0) "Global") ((= scope 32) "Link") ((= scope 64) "Site")
                                                ((= scope 128) "Compat") ((= scope 16) "Host") (#t "Unknown")) "\n")))
                     "")))
               (cu-lines text)))))))

; ife_print: one interface, its counters STATS where it has them
(def %if-print
  (fn (_ name ife stats)
    (def flags (List ref 0 ife))
    (%str-concat
      (list (%if-link-line name (List ref 1 ife) (List ref 2 ife))
            (%if-ip-line flags (List ref 7 ife))
            (%if-inet6 name)
            "          "
            (if (= flags 0) "[NO FLAGS] "
              (%str-concat (map (fn (_ f) (if (= (& flags (first f)) 0) "" (string-append (rest f) " "))) %if-flag-names)))
            " MTU:" (cu-int->str (List ref 4 ife)) "  Metric:" (cu-int->str (let ((m (List ref 3 ife))) (if (= m 0) 1 m))) "\n"
            (if (null? stats) "" (%if-stats-lines stats (List ref 6 ife)))
            (%if-map-line (List ref 5 ife))
            "\n"))))

; the first line: the name, the hardware's title, and its address where the
; type prints one
(def %if-link-line
  (fn (_ name type hwb)
    (def hw (let ((h (List find (fn (_ h) (= (first h) type)) %if-hwtitles))) (if (null? h) (list type "UNSPEC" (lit unspec)) h)))
    (def unspec (Str8 join "-" (map %if-hex2 (append hwb (list 0 0 0 0 0 0 0 0)))))
    (def hwtext
      (match ((eq? (List ref 2 hw) #t) (Str8 join ":" (map %if-hex2 (List take 6 hwb))))
             ((eq? (List ref 2 hw) (lit unspec)) unspec)
             ((if (eq? (List ref 2 hw) (lit unspec-suppress)) (not (List all? (fn (_ b) (= b 0)) hwb)) #f) unspec)
             (#t ())))
    (%str-concat (list (inet-left name 9) " Link encap:" (List ref 1 hw) "  "
                         (if (null? hwtext) "" (%str-concat (list "HWaddr " hwtext "  "))) "\n"))))

; the IPv4 line, where IP (address, dstaddr, broadcast, netmask) is given
(def %if-ip-line
  (fn (_ flags ip)
    (if (null? ip) ""
      (%str-concat
        (list "          inet addr:" (inet-dotted (first ip)) " "
              (if (= (& flags 16) 0) "" (%str-concat (list " P-t-P:" (inet-dotted (%if-or0 (List ref 1 ip))) " ")))
              (if (= (& flags 2) 0) "" (%str-concat (list " Bcast:" (inet-dotted (%if-or0 (List ref 2 ip))) " ")))
              " Mask:" (inet-dotted (%if-or0 (List ref 3 ip))) "\n")))))

; the counters' lines, and txqueuelen where the kernel gave it
(def %if-stats-lines
  (fn (_ stats txq)
    (def n (fn (_ k) (cu-int->str (List ref k stats))))
    (%str-concat
      (list "          RX packets:" (n 1) " errors:" (n 2) " dropped:" (n 3) " overruns:" (n 4) " frame:" (n 5) "\n"
            "          TX packets:" (n 9) " errors:" (n 10) " dropped:" (n 11) " overruns:" (n 12) " carrier:" (n 14) "\n"
            "          collisions:" (n 13) " "
            (if (= txq -1) "" (%str-concat (list "txqueuelen:" (cu-int->str txq) " ")))
            "\n          R" (%if-scaled (List ref 0 stats)) "  T" (%if-scaled (List ref 8 stats)) "\n"))))

; the hardware map's line, IFMAP (base_addr irq mem_start mem_end dma), where
; any of it is set
(def %if-map-line
  (fn (_ ifmap)
    (def hex (fn (_ v) (cvt v cu-string-type 16)))
    (if (List all? (fn (_ k) (= (List ref k ifmap) 0)) (list 0 1 2 4)) ""
      (%str-concat
        (list "          "
              (if (= (List ref 1 ifmap) 0) "" (%str-concat (list "Interrupt:" (cu-int->str (List ref 1 ifmap)) " ")))
              (if (< (List ref 0 ifmap) 256) "" (%str-concat (list "Base address:0x" (hex (List ref 0 ifmap)) " ")))
              (if (= (List ref 2 ifmap) 0) "" (%str-concat (list "Memory:" (hex (List ref 2 ifmap)) "-" (hex (List ref 3 ifmap)) " ")))
              (if (= (List ref 4 ifmap) 0) "" (%str-concat (list "DMA chan:" (hex (List ref 4 ifmap)) " ")))
              "\n")))))

(def %if-or0 (fn (_ v) (if (null? v) 0 v)))

; display_interfaces: those up, all with -a, or NAME alone
(def %if-show
  (fn (_ all? name)
    (def dev (%if-dev))
    (def found? (if (null? name) #f (not (null? (%if-find name dev)))))
    (def names
      (%if-sorted (append (map (fn (_ e) (pair (first e) (rest e))) (if (null? name) dev (%if-dev-upto dev name)))
                          (if found? () (map (fn (_ n) (pair n ())) (%if-conf))))))
    (def one (fn (_ n stats)
               (let ((ife (%if-fetch n)))
                 (if (null? ife)
                   (do (%if-say (%str-concat (list n ": error fetching interface information: " (%if-fetch-err n)))) #f)
                   (do (when (if (null? name) (if all? #t (not (= (& (List ref 0 ife) 1) 0))) #t)
                         (file-write 1 (%if-print n ife stats)))
                       #t)))))
    (if (null? name)
      (let go ((ns names)) (if (null? ns) 0 (if (one (first (first ns)) (rest (first ns))) (go (rest ns)) 1)))
      (let ((e (%if-find name names))) (if (one name (if (null? e) () (rest e))) 0 1)))))

; if_readlist_proc stops at NAME
(def %if-dev-upto
  (fn (_ dev name)
    (let go ((ds dev) (acc ()))
      (match ((null? ds) (reverse acc))
             ((string=? (first (first ds)) name) (reverse (pair (first ds) acc)))
             (#t (go (rest ds) (pair (first ds) acc)))))))

; do_if_fetch's words for why NAME could not be read
(def %if-fetch-err
  (fn (_ name)
    (let ((r (%if-ioctl 35091 (if-req name))))
      (let ((e (Err errno-of r))) (if (= e 19) "Device not found" (libc-strerror e))))))

; --- setting ----------------------------------------------------------------------

; OptArray: (NAME FLAGS KIND SELECTOR IOCTL OFFSET IOCTL-NAME), its flag bits
; busybox's -- N_CLR 1, M_CLR 2, N_SET 4, M_SET 8, N_ARG 16 -- and KIND what
; the argument is: an int, an address (netmask one of them, a flag set after
; for broadcast and pointopoint), a hardware address, a pointer, a map
; field, an IPv6 add or del
(def %if-options
  (list (list "metric" 16 (lit int) 0 35102 16 "SIFMETRIC") (list "mtu" 16 (lit int) 0 35106 16 "SIFMTU")
        (list "txqueuelen" 16 (lit int) 0 35139 16 "SIFTXQLEN") (list "dstaddr" 16 (lit addr) 0 35096 16 "SIFDSTADDR")
        (list "netmask" 16 (lit netmask) 0 35100 16 "SIFNETMASK") (list "broadcast" 18 (lit after) 2 35098 16 "SIFBRDADDR")
        (list "hw" 16 (lit hw) 0 35108 16 "SIFHWADDR") (list "pointopoint" 18 (lit after) 16 35096 16 "SIFDSTADDR")
        (list "keepalive" 16 (lit ptr) 0 35312 16 "SKEEPALIVE") (list "outfill" 16 (lit ptr) 0 35314 16 "SOUTFILL")
        (list "mem_start" 16 (lit map-ulong) 0 35185 16 "SIFMAP") (list "io_addr" 16 (lit map-ushort) 0 35185 32 "SIFMAP")
        (list "irq" 16 (lit map-uchar) 0 35185 34 "SIFMAP")
        (list "add" 16 (lit add) 0 35094 16 "SIFADDR") (list "del" 16 (lit add) 0 35126 16 "DIFADDR")
        (list "arp" 9 () 128 0 0 "") (list "trailers" 9 () 32 0 0 "") (list "promisc" 6 () 256 0 0 "")
        (list "multicast" 6 () 4096 0 0 "") (list "allmulti" 6 () 512 0 0 "") (list "dynamic" 6 () 32768 0 0 "")
        (list "up" 4 () 65 0 0 "") (list "down" 1 () 1 0 0 "")))

; the row a word no option names takes: an address set, the interface up
(def %if-host-op (list "" 0 (lit host) 65 35094 16 "SIFADDR"))

; ioctl_or_perror_and_die "SIOC%s": REQ with R, the run ended where it fails
(def %if-set!
  (fn (_ req r name)
    (let ((n (%if-ioctl req r)))
      (when (< n 0) (%if-die (%str-concat (list "SIOC" name ": " (libc-strerror (Err errno-of n)))))))))

; xioctl for the flags: the ioctl's number where it fails
(def %if-xioctl!
  (fn (_ req r)
    (let ((n (%if-ioctl req r)))
      (when (< n 0) (%if-die (%str-concat (list "ioctl 0x" (cvt req cu-string-type 16) " failed: " (libc-strerror (Err errno-of n)))))))))

; the flags SEL set or cleared
(def %if-flag!
  (fn (_ iface sel set?)
    (let ((r (if-req iface)))
      (do (%if-xioctl! 35091 r)
          (let ((f (if-ref r 16 2))) (inet-set! r 16 (if set? (| f sel) (& f (^ sel 65535))) 2))
          (%if-xioctl! 35092 r)))))

; xhost2sockaddr: (4 . U32) or (6 . BUF16), the run ended where it is not one
(def %if-host
  (fn (_ host)
    (def b (inet-zeros 16))
    (match
      ((string=? host "default") (pair 4 0))
      ((not (null? (inet-aton host))) (pair 4 (inet-aton host)))
      ((inet-pton6! b 0 host) (pair 6 b))
      (#t (let ((a (inet-host-addr host))) (if (null? a) (%if-die (%str-concat (list "bad address '" host "'"))) (pair 4 a)))))))

; an address for OP into IFACE: an IPv4 one by OP's ioctl, an IPv6 one by an
; in6_ifreq, ADDR/PREFIX taken only for IPv6; #t where it was IPv4
(def %if-address!
  (fn (_ iface op host)
    (def slash (dp-find host 0 #\/))
    (def plen (if (< slash 0) 0
                (let ((n (cu-range-number "ifconfig" (substring host (+ slash 1) (byte-len host)) 0 128)))
                  (if (null? n) (Err raise (lit ifconfig) "number" ()) n))))
    (def a (%if-host (if (< slash 0) host (substring host 0 slash))))
    (match
      ((= (first a) 6) (do (%if-address6! iface op (rest a) plen) #f))
      ((>= slash 0) (%if-die (%str-concat (list "bad address '" host "'"))))
      (#t (let ((r (if-req iface)))
            (do (inet-sin! r (List ref 5 op) (rest a))
                (%if-set! (List ref 4 op) r (List ref 6 op))
                #t))))))

(def %if-address6!
  (fn (_ iface op bytes plen)
    (def idx (if-req iface))
    (def fd (inet-socket 10 %if-die))
    (def r6 (inet-zeros 24))
    (let ((n (in-call (cu-ptr-call (cu-libc-sym "ioctl") fd 35123 (cu-str->ptr idx)))))
      (when (< n 0) (do (cu-ptr-call (cu-libc-sym "close") fd) (%if-die (string-append "ioctl 0x8933 failed: " (libc-strerror (Err errno-of n)))))))
    (map (fn (_ k) (inet-set! r6 k (cu-ptr-ref (cu-str->ptr bytes) k 1) 1)) (List range 0 16))
    (inet-set! r6 16 plen 4)
    (inet-set! r6 20 (if-ref idx 16 4) 4)
    (let ((n (in-call (cu-ptr-call (cu-libc-sym "ioctl") fd (List ref 4 op) (cu-str->ptr r6)))))
      (do (cu-ptr-call (cu-libc-sym "close") fd)
          (when (< n 0) (%if-die (%str-concat (list "SIOC" (List ref 6 op) ": " (libc-strerror (Err errno-of n))))))))))

; strtoul with base 0: decimal, 0x hex or 0 octal, its digits as far as they go
(def %if-strtoul
  (fn (_ s)
    (def hex? (if (> (byte-len s) 1) (if (= (byte-at s 0) #\0) (= (| (char->integer (byte-at s 1)) 32) 120) #f) #f))
    (def oct? (if hex? #f (if (> (byte-len s) 1) (= (byte-at s 0) #\0) #f)))
    (def base (match (hex? 16) (oct? 8) (#t 10)))
    (let go ((i (if hex? 2 0)) (n 0))
      (if (>= i (byte-len s)) n
        (let ((c (| (char->integer (byte-at s i)) 32)))
          (let ((d (match ((if (>= c 48) (<= c 57) #f) (- c 48)) ((if (>= c 97) (<= c 102) #f) (- c 87)) (#t 99))))
            (if (>= d base) n (go (+ i 1) (+ (* n base) d)))))))))

; a number for OP into IFACE: an int, a pointer, or a field of its map
(def %if-number!
  (fn (_ iface op arg)
    (def kind (List ref 2 op))
    (def r (if-req iface))
    (def n (%if-strtoul arg))
    (when (List find (fn (_ k) (eq? k kind)) (list (lit map-ulong) (lit map-ushort) (lit map-uchar)))
      (%if-xioctl! 35184 r))
    (match ((eq? kind (lit map-ulong)) (inet-set! r 16 n 8))
           ((eq? kind (lit map-ushort)) (inet-set! r 32 n 2))
           ((eq? kind (lit map-uchar)) (inet-set! r 34 n 1))
           ((eq? kind (lit ptr)) (inet-set! r 16 n 8))
           (#t (inet-set! r 16 n 4)))
    (%if-set! (List ref 4 op) r (List ref 6 op))))

; hw ether ADDRESS: the hardware address set
(def %if-hw!
  (fn (_ iface op class addr)
    (unless (string=? class "ether") (%if-usage))
    (let ((bytes (ar-ether addr)) (r (if-req iface)))
      (do (when (null? bytes) (%if-die (string-append "invalid hw-addr " addr)))
          (inet-set! r 16 1 2)
          (let go ((k 0) (bs bytes)) (unless (null? bs) (do (inet-set! r (+ 18 k) (first bs) 1) (go (+ k 1) (rest bs)))))
          (%if-set! (List ref 4 op) r (List ref 6 op))))))

; an alias whose name ends with "-" is deleted with its address, and no flag
; is set on it after
(def %if-deleted-alias?
  (fn (_ iface) (if (>= (dp-find iface 0 #\:) 0) (Str8 ends? "-" iface) #f)))

; one word of those after IFACE, and those after it: the words left, and
; whether a netmask has been set (STATE, a cell)
(def %if-word!
  (fn (_ iface ws state)
    (def w (first ws))
    (def minus? (if (> (byte-len w) 0) (= (byte-at w 0) #\-) #f))
    (def p (if minus? (substring w 1 (byte-len w)) w))
    (def op (List find (fn (_ o) (string=? (first o) p)) %if-options))
    (def mask (if (null? op) 0 (& (if minus? 42 21) (List ref 1 op))))
    (def arg (if (null? (rest ws)) () (first (rest ws))))
    (def kind (if (null? op) () (List ref 2 op)))
    (match
      ((if (null? op) #f (= mask 0)) (%if-die (%str-concat (list "bad: '" w "'"))))
      ; a word no option names: an address, the interface brought up after
      ((null? op)
        (do (unless (string=? w "inet")
              (when (if (%if-address! iface %if-host-op w) (not (%if-deleted-alias? iface)) #f) (%if-flag! iface 65 #t)))
            (rest ws)))
      ((= (& mask 16) 0) (do (%if-flag! iface (List ref 3 op) (not (= (& mask 12) 0))) (rest ws)))
      ((if (eq? kind (lit netmask)) (first state) #f) (%if-usage))
      ((null? arg) (if (eq? kind (lit add)) (do (%if-flag! iface 0 #t) (rest ws)) (%if-usage)))
      ((eq? kind (lit hw))
        (if (null? (rest (rest ws))) (%if-usage) (do (%if-hw! iface op arg (first (rest (rest ws)))) (rest (rest (rest ws))))))
      ((List find (fn (_ k) (eq? k kind)) (list (lit addr) (lit netmask) (lit after) (lit add)))
        (do (when (eq? kind (lit netmask)) (set-first! state #t))
            (unless (string=? arg "inet")
              (when (if (%if-address! iface op arg) (if (eq? kind (lit after)) #t (eq? kind (lit add))) #f)
                (%if-flag! iface (List ref 3 op) #t)))
            (rest (rest ws))))
      (#t (do (%if-number! iface op arg) (rest (rest ws)))))))

(def cu-ifconfig
  (fn (_ argv stdin-thunk)
    (def all? (if (pair? argv) (string=? (first argv) "-a") #f))
    (def words (if all? (rest argv) argv))
    (guard (e (match ((eq? (cu-err-label e) (lit ifconfig-usage)) (cu-usage "ifconfig"))
                     ((eq? (cu-err-label e) (lit ifconfig)) 1)
                     (#t (error e))))
      (if (if (null? words) #t (null? (rest words)))
        (%if-show all? (if (null? words) () (first words)))
        (let go ((ws (rest words)) (state (list #f)))
          (if (null? ws) 0 (go (%if-word! (first words) ws state) state)))))))

(provide cu/ifconfig cu-ifconfig if-ref if-req)

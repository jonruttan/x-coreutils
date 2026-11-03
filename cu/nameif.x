; # x-coreutils -- the small tools, as applets
;
; ## cu/nameif.x -- nameif: network interfaces renamed by what they are
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's nameif with FEATURE_NAMEIF_EXTENDED (networking/nameif.c).  Each
; IFNAME SELECTOR pair, or each line of -c's file (/etc/mactab unless named),
; names an interface and how to find it: a hardware address, mac= before it
; or not, driver=, bus= and phyaddr=, all of them to match.  The interfaces
; of /proc/net/dev are taken in turn, each renamed (SIOCSIFNAME) to the first
; entry it matches, latest given first, and that entry is spent.  -s writes
; the errors to syslog as well.
;
; As busybox's does, each word of a selector clears the phyaddr= before it,
; so it holds only as the last; and a hardware address is read as musl's
; ether_aton_r reads it, strtoul's base 16 for each byte.

(module cu/nameif)

(import cu/cli cu-opts cu-usage)
(import cu/ifconfig if-ref if-req)
(import cu/inet inet-set! inet-zeros)
(import cu/inetd in-call in-lines in-percent in-tokens-max)
(import cu/ping pn-number)
(import cu/prims byte-at byte-len cu-err-label cu-int->ptr cu-int->str
  cu-libc-sym cu-lines cu-ptr->str cu-ptr-call cu-str->ptr file-err-text
  file-read-all file-read-unsized file-write filter libc-strerror map reverse
  string-append string=? substring)
(import cu/telnetd td-ptr->int)

(def %ni-syslog? #f)
(def %ni-say
  (fn (_ msg)
    (do (file-write 2 (%str-concat (list "nameif: " msg "\n")))
        (when %ni-syslog? (cu-ptr-call (cu-libc-sym "syslog") 3 (in-percent msg))))))
(def %ni-die (fn (_ msg) (do (%ni-say msg) (Err raise (lit nameif) msg ()))))

; --- selectors -------------------------------------------------------------------

(def %ni-space? (fn (_ c) (if (= c 32) #t (if (>= c 9) (<= c 13) #f))))

(def %ni-hex
  (fn (_ c) (match ((if (>= c #\0) (<= c #\9) #f) (- c #\0))
                   ((if (>= (| c 32) #\a) (<= (| c 32) #\f) #f) (+ 10 (- (| c 32) #\a)))
                   (#t ()))))

; strtoul base 16 from I in S: (VALUE . END), END I where no digit was read
; and VALUE past 255 for any that will not fit a byte
(def %ni-strtoul16
  (fn (_ s i)
    (def n (byte-len s))
    (def at (fn (_ k) (if (< k n) (byte-at s k) 0)))
    (def j (let go ((k i)) (if (%ni-space? (at k)) (go (+ k 1)) k)))
    (def neg (= (at j) #\-))
    (def k (if (if neg #t (= (at j) #\+)) (+ j 1) j))
    (def d (if (if (= (at k) #\0) (if (= (| (at (+ k 1)) 32) #\x) (not (null? (%ni-hex (at (+ k 2))))) #f) #f) (+ k 2) k))
    (let go ((m d) (v 0))
      (if (null? (%ni-hex (at m)))
        (if (= m d) (pair 0 i) (pair (if (if neg (> v 0) #f) 256 v) m))
        (go (+ m 1) (let ((w (+ (* v 16) (%ni-hex (at m))))) (if (> w 256) 256 w)))))))

; ether_aton_r: S's six bytes, or nil
(def %ni-ether
  (fn (_ s)
    (let go ((k 0) (i 0) (acc ()))
      (match ((= k 6) (if (= i (byte-len s)) (reverse acc) ()))
             ((if (> k 0) (not (if (< i (byte-len s)) (= (byte-at s i) #\:) #f)) #f) ())
             (#t (let ((r (%ni-strtoul16 s (if (> k 0) (+ i 1) i))))
                   (if (> (first r) 255) () (go (+ k 1) (rest r) (pair (first r) acc)))))))))

(def %ni-prefixed?
  (fn (_ s p) (if (>= (byte-len s) (byte-len p)) (string=? (substring s 0 (byte-len p)) p) #f)))

; the index of the first byte of S from I that SKIP? does not hold for
(def %ni-span
  (fn (_ s i skip?)
    (if (if (< i (byte-len s)) (skip? (byte-at s i)) #f) (%ni-span s (+ i 1) skip?) i)))

; an entry: (IFNAME MAC BUS DRIVER PHY), nil where a selector was not given
; and PHY -1
(def %ni-entry
  (fn (_ ifname selector)
    (when (>= (byte-len ifname) 16) (%ni-die (%str-concat (list "interface name '" ifname "' too long"))))
    (def n (byte-len selector))
    (let go ((i 0) (mac ()) (bus ()) (driver ()) (found 0))
      (let ((s (%ni-span selector i %ni-space?)))
        (if (>= s n)
          (if (= found 0) (%ni-die (string-append "no selectors found for " ifname)) (list ifname mac bus driver -1))
          (let ((e (%ni-span selector s (fn (_ c) (not (%ni-space? c))))))
            (let ((w (substring selector s e)) (next (if (< e n) (+ e 1) e)))
              (match
                ((%ni-prefixed? w "bus=") (go next mac (substring w 4 (byte-len w)) driver (+ found 1)))
                ((%ni-prefixed? w "driver=") (go next mac bus (substring w 7 (byte-len w)) (+ found 1)))
                ((%ni-prefixed? w "phyaddr=")
                  (let ((p (pn-number (substring w 8 (byte-len w)) 0 2147483647 %ni-die)))
                    (if (>= next n) (list ifname mac bus driver p) (go next mac bus driver (+ found 1)))))
                (#t (let ((m (%ni-ether (if (%ni-prefixed? w "mac=") (substring w 4 (byte-len w)) w))))
                      (if (null? m) (%ni-die (string-append "can't parse " w)) (go next m bus driver (+ found 1)))))))))))))

; the entries -c's file names, latest first; bad lines said and passed over,
; a file that will not open said and none
(def %ni-file
  (fn (_ fname)
    (def text (guard (e (if (eq? (cu-err-label e) (lit io))
                          (do (%ni-say (%str-concat (list fname ": " (file-err-text e)))) ())
                          (error e)))
                (file-read-all fname)))
    (let go ((lines (if (null? text) () (in-lines text))) (acc ()))
      (if (null? lines) acc
        (let ((t (in-tokens-max (rest (first lines)) 2)))
          (match ((null? t) (go (rest lines) acc))
                 ((null? (rest t))
                   (do (%ni-say (%str-concat (list "bad line " (cu-int->str (first (first lines))) ": 1 tokens found, 2 needed")))
                       (go (rest lines) acc)))
                 (#t (go (rest lines) (pair (%ni-entry (first t) (first (rest t))) acc)))))))))

; --- the interfaces --------------------------------------------------------------

(def %ni-ioctl (fn (_ fd req r) (in-call (cu-ptr-call (cu-libc-sym "ioctl") fd req (cu-str->ptr r)))))

; the C string at AT in B
(def %ni-cstr (fn (_ b at) (cu-ptr->str (cu-int->ptr (+ (td-ptr->int (cu-str->ptr b)) at)))))

; what the selectors are matched against: (NAME MAC BUS DRIVER PHY), read
; by SIOCETHTOOL and SIOCGIFHWADDR, a failed call leaving its fields zero
(def %ni-probe
  (fn (_ fd name)
    (def ifr (if-req name))
    (def cmd (inet-zeros 44))
    (inet-set! cmd 0 1 4)
    (inet-set! ifr 16 (td-ptr->int (cu-str->ptr cmd)) 8)
    (%ni-ioctl fd 35142 ifr)
    (def drv (inet-zeros 196))
    (inet-set! drv 0 3 4)
    (inet-set! ifr 16 (td-ptr->int (cu-str->ptr drv)) 8)
    (%ni-ioctl fd 35142 ifr)
    (inet-set! ifr 16 0 8)
    (%ni-ioctl fd 35111 ifr)
    (list name (List map (fn (_ k) (if-ref ifr (+ 18 k) 1)) (List range 0 6))
          (%ni-cstr drv 100) (%ni-cstr drv 4) (if-ref cmd 16 1))))

(def %ni-same-mac?
  (fn (_ a b) (if (null? a) #t (if (= (first a) (first b)) (%ni-same-mac? (rest a) (rest b)) #f))))

(def %ni-matches?
  (fn (_ e dev)
    (match ((not (if (null? (List ref 2 e)) #t (string=? (List ref 2 e) (List ref 2 dev)))) #f)
           ((not (if (null? (List ref 3 e)) #t (string=? (List ref 3 e) (List ref 3 dev)))) #f)
           ((not (if (= (List ref 4 e) -1) #t (= (List ref 4 e) (List ref 4 dev)))) #f)
           (#t (%ni-same-mac? (List ref 1 e) (List ref 1 dev))))))

; /proc/net/dev's interface names, past its two header lines
(def %ni-devs
  (fn (_)
    (def text (guard (e (if (eq? (cu-err-label e) (lit io))
                          (%ni-die (%str-concat (list "can't open '/proc/net/dev': " (file-err-text e))))
                          (error e)))
                (file-read-unsized "/proc/net/dev")))
    (List map (fn (_ line)
                (let ((s (%ni-span line 0 %ni-space?)))
                  (substring line s (%ni-span line s (fn (_ c) (not (if (= c #\:) #t (%ni-space? c))))))))
              (List filter (fn (_ l) (> (byte-len l) 0)) (List drop 2 (cu-lines text))))))

; each interface renamed to the first entry it matches, that entry spent
(def %ni-rename
  (fn (_ fd devs entries)
    (unless (if (null? devs) #t (null? entries))
      (let ((dev (%ni-probe fd (first devs))))
        (let ((e (List find (fn (_ e) (%ni-matches? e dev)) entries)))
          (if (null? e) (%ni-rename fd (rest devs) entries)
            (do (unless (string=? (first dev) (first e))
                  (let ((ifr (if-req (first dev))))
                    (do (List map (fn (_ i) (inet-set! ifr (+ 16 i) (byte-at (first e) i) 1)) (List range 0 (byte-len (first e))))
                        (let ((r (%ni-ioctl fd 35107 ifr)))
                          (when (< r 0)
                            (%ni-die (%str-concat (list "can't change ifname " (first dev) " to " (first e) ": "
                                                          (libc-strerror (Err errno-of r))))))))))
                (%ni-rename fd (rest devs) (List filter (fn (_ x) (not (eq? x e))) entries)))))))))

; the entries the operands name, in pairs, latest first
(def %ni-pairs
  (fn (_ ws acc)
    (match ((null? ws) acc)
           ((null? (rest ws)) (Err raise (lit nameif-usage) "usage" ()))
           (#t (%ni-pairs (rest (rest ws)) (pair (%ni-entry (first ws) (first (rest ws))) acc))))))

(def %ni-main
  (fn (_ argv)
    (def o (cu-opts "nameif" argv))
    (set! %ni-syslog? (Opts on? o "-s"))
    (when %ni-syslog? (cu-ptr-call (cu-libc-sym "openlog") "nameif" 0 128))
    (def ops (Opts operands o))
    (def c (Opts value o "-c"))
    (def entries (if (null? ops) (%ni-file (if (null? c) "/etc/mactab" c)) (%ni-pairs ops ())))
    (def fd (in-call (cu-ptr-call (cu-libc-sym "socket") 2 2 0)))
    (when (< fd 0) (%ni-die (string-append "socket(AF_INET,2,0): " (libc-strerror (Err errno-of fd)))))
    (def devs (%ni-devs))
    (%ni-rename fd devs entries)
    (cu-ptr-call (cu-libc-sym "close") fd)
    0))

(def cu-nameif
  (fn (_ argv stdin-thunk)
    (set! %ni-syslog? #f)
    (guard (e (match ((eq? (cu-err-label e) (lit nameif-usage)) (cu-usage "nameif"))
                     ((eq? (cu-err-label e) (lit nameif)) 1)
                     (#t (error e))))
      (%ni-main argv))))

(provide cu/nameif cu-nameif)

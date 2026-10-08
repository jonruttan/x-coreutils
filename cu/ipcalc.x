; # x-coreutils -- the small tools, as applets
;
; ## cu/ipcalc.x -- ipcalc: busybox's network settings from an address
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; networking/ipcalc.c: ADDRESS[/PREFIX] [NETMASK] read as inet_aton reads an
; address -- one to four parts, each decimal, 0x hex or 0 octal, the last
; filling the bytes left -- the netmask the class's when none is given, and
; NETMASK=, BROADCAST=, NETWORK=, PREFIX= and HOSTNAME= lines in that order
; for -m, -b, -n, -p and -h.  -s keeps the errors to the status.

(def %ic-silent #f)

(def %ic-die
  (fn (_ msg)
    (Err raise (lit net) msg ())))

; strtoul with base 0 at I of S: (VALUE . END), VALUE nil when no digit is read
(def %ic-strtoul
  (fn (_ s i)
    (def hex? (if (< (+ i 1) (byte-len s))
                (if (= (byte-at s i) #\0) (%wget-memv (byte-at s (+ i 1)) (list #\x #\X)) #f) #f))
    (def base (match (hex? 16) ((if (< i (byte-len s)) (= (byte-at s i) #\0) #f) 8) (#t 10)))
    (def start (if hex? (+ i 2) i))
    (def digit (fn (_ c)
      (match ((if (>= c #\0) (<= c #\9) #f) (- c #\0))
             ((if (>= c #\a) (<= c #\f) #f) (+ 10 (- c #\a)))
             ((if (>= c #\A) (<= c #\F) #f) (+ 10 (- c #\A)))
             (#t 99))))
    (let go ((j start) (v 0))
      (if (if (< j (byte-len s)) (< (digit (byte-at s j)) base) #f)
        (go (+ j 1) (+ (* v base) (digit (byte-at s j))))
        ; "0x" with no hex digit after it reads as the 0 alone, as strtoul does
        (match ((> j start) (pair v j))
               (hex? (pair 0 (+ i 1)))
               (#t (pair () j)))))))

; musl's inet_aton: the address as one 32-bit number, or nil
(def %ic-aton
  (fn (_ s)
    (def parts (%ic-parts s 0 ()))
    (if (null? parts) ()
      (let ((n (length parts)) (p parts))
        (let ((v (match
                   ((= n 1) (%ic-split-bytes (first p) 4 ()))
                   ((= n 2) (append (list (first p)) (%ic-split-bytes (%cu-nth 1 p) 3 ())))
                   ((= n 3) (append (list (first p) (%cu-nth 1 p)) (%ic-split-bytes (%cu-nth 2 p) 2 ())))
                   (#t p))))
          (if (let ok ((bs v)) (if (null? bs) #f (if (> (first bs) 255) #t (ok (rest bs))))) ()
            (+ (* (first v) 16777216) (* (%cu-nth 1 v) 65536) (* (%cu-nth 2 v) 256) (%cu-nth 3 v))))))))

; the dotted parts of S from I, each starting with a digit; nil when one is not
; a number, ends in anything but a dot, or makes a fifth
(def %ic-parts
  (fn (self s i acc)
    (if (if (>= i (byte-len s)) #t (not (if (>= (byte-at s i) #\0) (<= (byte-at s i) #\9) #f))) ()
      (let ((r (%ic-strtoul s i)))
        (match
          ((null? (first r)) ())
          ((= (rest r) (byte-len s)) (reverse (pair (first r) acc)))
          ((not (= (byte-at s (rest r)) #\.)) ())
          ((>= (length acc) 3) ())
          (#t (self s (+ (rest r) 1) (pair (first r) acc))))))))

; V as N bytes, most significant first; what does not fit stays in the first,
; past 255, so the caller refuses it
(def %ic-split-bytes
  (fn (self v n acc)
    (if (= n 1) (pair v acc)
      (self (%wget-div v 256) (- n 1) (pair (% v 256) acc)))))

(def %ic-ntoa
  (fn (_ v)
    (string-concat
      (list (%cu-int->str (% (%wget-div v 16777216) 256)) "."
            (%cu-int->str (% (%wget-div v 65536) 256)) "."
            (%cu-int->str (% (%wget-div v 256) 256)) "."
            (%cu-int->str (% v 256))))))

; the netmask of an address's class: C for 11..., B for 10..., A for 0...
(def %ic-class-mask
  (fn (_ ip)
    (match ((>= ip 3221225472) 4294967040)
           ((>= ip 2147483648) 4294901760)
           (#t 4278190080))))

(def %ic-prefix-mask
  (fn (_ n) (let go ((k n) (bit 2147483648) (m 0)) (if (= k 0) m (go (- k 1) (%wget-div bit 2) (+ m bit))))))

(def %ic-popcount
  (fn (_ v) (let go ((v v) (n 0)) (if (= v 0) n (go (%wget-div v 2) (+ n (% v 2)))))))

; xatoul_range: S as 0..32 or the run ends as busybox's ends it
(def %ic-prefix
  (fn (_ s)
    (let ((r (%ic-digits s)))
      (match
        ((if (null? (first r)) #t (< (rest r) (byte-len s))) (%ic-die (string-concat (list "invalid number '" s "'"))))
        ((> (first r) 32) (%ic-die (string-concat (list "number " s " is not in 0..32 range"))))
        (#t (first r))))))

; gethostbyaddr's name for IP, lower case, or nil
(def %ic-host-name
  (fn (_ ip)
    (def f (%cu-dlsym (%cu-dlopen () 1) "gethostbyaddr"))
    (def buf (%str-make-raw 4))
    (%cu-ptr-set! (%cu-str->ptr buf) 0 (% (%wget-div ip 16777216) 256) 1)
    (%cu-ptr-set! (%cu-str->ptr buf) 1 (% (%wget-div ip 65536) 256) 1)
    (%cu-ptr-set! (%cu-str->ptr buf) 2 (% (%wget-div ip 256) 256) 1)
    (%cu-ptr-set! (%cu-str->ptr buf) 3 (% ip 256) 1)
    (def r (if (null? f) 0 (%cu-ptr-call f (%cu-str->ptr buf) 4 2)))
    (if (= r 0) ()
      (%wget-lower (%cu-ptr->str (%cu-int->ptr (%cu-ptr-word (%cu-int->ptr r) 0)))))))

(def %cu-ipcalc
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "ipcalc" argv))
    (def on? (fn (_ short long) (if (Opts on? o short) #t (Opts on? o long))))
    (def ops (Opts operands o))
    (set! %ic-silent (on? "-s" "--silent"))
    (def any? (if (on? "-m" "--netmask") #t (on? "-h" "--hostname")))
    (match
      ((if (null? ops) #t (> (length ops) 2)) (%cu-usage "ipcalc"))
      ((if (if (on? "-b" "--broadcast") #f (if (on? "-n" "--network") #f (not (on? "-p" "--prefix"))))
         (if (not any?) #t (= (length ops) 2)) #f)
        (%cu-usage "ipcalc"))
      (#t (guard (e (if (eq? (Err label e) (lit net))
                      (do (unless %ic-silent (file-write 2 (string-concat (list "ipcalc: " (e msg) "\n")))) 1)
                      (error e)))
            (%ic-run on? ops))))))

(def %ic-run
  (fn (_ on? ops)
    (def arg (first ops))
    (def slash (%wget-index arg #\/ 0))
    (def ipstr (if (null? slash) arg (substring arg 0 slash)))
    (def pstr (if (null? slash) "" (substring arg (+ slash 1) (byte-len arg))))
    (def pmask (if (= (byte-len pstr) 0) () (%ic-prefix-mask (%ic-prefix pstr))))
    (def ip (%ic-aton ipstr))
    (when (null? ip) (%ic-die (string-append "bad IP address: " ipstr)))
    (def mask
      (if (null? (rest ops))
        (if (null? pmask) (%ic-class-mask ip) pmask)
        (do (unless (null? pmask) (%ic-die "use prefix or netmask, not both"))
            (let ((m (%ic-aton (first (rest ops)))))
              (if (null? m) (%ic-die (string-append "bad netmask: " (first (rest ops)))) m)))))
    (def net (bit-and ip mask))
    (when (on? "-m" "--netmask") (file-write 1 (string-concat (list "NETMASK=" (%ic-ntoa mask) "\n"))))
    (when (on? "-b" "--broadcast")
      (file-write 1 (string-concat (list "BROADCAST=" (%ic-ntoa (bit-or net (bit-xor mask %cu-m32))) "\n"))))
    (when (on? "-n" "--network") (file-write 1 (string-concat (list "NETWORK=" (%ic-ntoa net) "\n"))))
    (when (on? "-p" "--prefix") (file-write 1 (string-concat (list "PREFIX=" (%cu-int->str (%ic-popcount mask)) "\n"))))
    (when (on? "-h" "--hostname")
      (let ((h (%ic-host-name ip)))
        (if (null? h) (%ic-die (string-concat (list "can't find hostname for " ipstr ": Unknown host")))
          (file-write 1 (string-concat (list "HOSTNAME=" h "\n"))))))
    0))

; the decimal digits S starts with: (N . END), N nil when there are none
(def %ic-digits
  (fn (_ s)
    (let go ((j 0) (n 0))
      (if (if (< j (byte-len s)) (if (>= (byte-at s j) #\0) (<= (byte-at s j) #\9) #f) #f)
        (go (+ j 1) (+ (* n 10) (- (byte-at s j) #\0)))
        (pair (if (= j 0) () n) j)))))

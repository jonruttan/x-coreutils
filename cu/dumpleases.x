; # x-coreutils -- the small tools, as applets
;
; ## cu/dumpleases.x -- dumpleases: the leases a udhcpd lease file holds
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; networking/udhcp/dumpleases.c: -f FILE, else /var/lib/misc/udhcpd.leases --
; an eight-byte big-endian time it was written at (taken as now when it is
; later), then 36-byte leases: the expiry in seconds after that time (32-bit,
; big-endian), the IPv4 address, six bytes of MAC, a 20-byte NUL-padded host
; name and two bytes of padding.  Each lease is a line: MAC, address, name,
; and the time left -- [D days ]HH:MM:SS, -d in seconds -- or with -a the
; time it ends, ctime's way or -d in seconds since the epoch; "expired" when
; that is past.  A partial lease at the end is passed over.  -a and -r
; exclude each other.  The name's unprintable bytes show as ?, as busybox
; shows them without a UTF-8 locale.

(module cu/dumpleases)

(import cu/cli cu-opts cu-usage)
(import cu/date cu-date-fmt cu-date-split)
(import cu/ntpd nt-imin)
(import cu/prims cu-hexs cu-int->str cu-ptr-ref cu-str->ptr file-open-or-err
  file-open-read file-read-run file-write length map reverse string-append
  string=? wget-div wget-err-text)
(import cu/sysinfo si-now)
(import cu/tar tar-printable)
(import cu/text cu-pad-right cu-pad-zero)

(def %dl-file "/var/lib/misc/udhcpd.leases")

; a flag given in either spelling
(def %dl-on? (fn (_ o short long) (if (Opts on? o short) #t (Opts on? o long))))

; full_read: up to N bytes of FD, fewer only at the end, as a list
(def %dl-read
  (fn (_ fd n)
    (let go ((want n) (acc ()))
      (if (= want 0) (reverse acc)
        (let ((r (file-read-run fd want)))
          (if (= (rest r) 0) (reverse acc)
            (go (- want (rest r))
                (List fold (fn (_ a i) (pair (cu-ptr-ref (cu-str->ptr (first r)) i 1) a))
                  acc (%dl-iota (rest r))))))))))

(def %dl-iota (fn (_ n) (let go ((k (- n 1)) (acc ())) (if (< k 0) acc (go (- k 1) (pair k acc))))))
(def %dl-be (fn (_ l) (List fold (fn (_ acc b) (+ (* acc 256) b)) 0 l)))
(def %dl-hex2 (fn (_ b) (cu-pad-zero (cu-hexs b) 2)))
(def %dl-2 (fn (_ n) (cu-pad-zero (cu-int->str n) 2)))

(def cu-dumpleases
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "dumpleases" argv))
    (if (match ((not (null? (Opts operands o))) #t)
               (#t (if (%dl-on? o "-a" "--absolute") (%dl-on? o "-r" "--remaining") #f)))
      (cu-usage "dumpleases")
      ; a value is filed under the spelling given: -f or --file, the last of them
      (let ((file (List fold (fn (_ acc e) (if (if (string=? (first e) "-f") #t (string=? (first e) "--file")) (rest e) acc))
                    %dl-file (rest (Assoc entry (lit values) o)))))
        (let ((fd (file-open-or-err file-open-read file)))
          (if (Err err? fd)
            (do (file-write 2 (%str-concat (list "dumpleases: can't open '" file "': " (wget-err-text fd) "\n"))) 1)
            (%dl-show fd (%dl-on? o "-a" "--absolute") (%dl-on? o "-d" "--decimal"))))))))

(def %dl-show
  (fn (_ fd abs? dec?)
    (file-write 1 (%str-concat (list "Mac Address       IP Address      Host Name           Expires " (if abs? "at" "in") "\n")))
    (def head (%dl-read fd 8))
    (if (< (length head) 8)
      (do (file-write 2 "dumpleases: short read\n") 1)
      (let ((curr (first (si-now))))
        (let ((written (nt-imin (%dl-be head) curr)))
          (let go ()
            (let ((lease (%dl-read fd 36)))
              (when (= (length lease) 36)
                (do (file-write 1 (%dl-line lease written curr abs? dec?)) (go)))))
          0)))))

; one lease's line
(def %dl-line
  (fn (_ l written curr abs? dec?)
    (def mac (Str8 join ":" (map %dl-hex2 (List take 6 (List drop 8 l)))))
    (def ip (Str8 join "." (map cu-int->str (List take 4 (List drop 4 l)))))
    (def name-bytes (let go ((l (List take 19 (List drop 14 l))) (acc ()))
                      (if (if (null? l) #t (= (first l) 0)) (reverse acc) (go (rest l) (pair (first l) acc)))))
    (def name (tar-printable (bytes->str name-bytes)))
    (def ends (+ (%dl-be (List take 4 l)) written))
    (%str-concat
      (list mac " " (cu-pad-right ip 16) (cu-pad-right name 19) " "
            (match ((<= ends curr) "expired")
                   (dec? (cu-int->str (if abs? ends (- ends curr))))
                   (abs? (cu-date-fmt "%a %b %e %H:%M:%S %Y" (cu-date-split ends #f) ends))
                   (#t (%dl-left (- ends curr))))
            "\n"))))

; [D days ]HH:MM:SS
(def %dl-left
  (fn (_ s)
    (def d (wget-div s 86400))
    (def r (% s 86400))
    (string-append (if (> d 0) (string-append (cu-int->str d) " days ") "")
                   (%str-concat (list (%dl-2 (wget-div r 3600)) ":" (%dl-2 (wget-div (% r 3600) 60)) ":" (%dl-2 (% r 60)))))))

(provide cu/dumpleases cu-dumpleases)

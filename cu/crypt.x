; # x-coreutils -- the small tools, as applets
;
; ## cu/crypt.x -- cryptpw and mkpasswd, and the pw_encrypt httpd shares
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's cryptpw (loginutils/cryptpw.c), which is mkpasswd too.  -m names
; the method -- des, md5, sha256 or sha512, the default -- and -S, or a second
; word, the salt, put after the method's prefix; without one, one is made from
; /dev/urandom.  The hashes are x-lang's Crypt; yescrypt is not among them.

(module cu/crypt)

(import cu/cli cu-opts cu-usage)
(import cu/dump dp-find)
(import cu/hash cu-bytes cu-crypt64)
(import cu/prims bit-and byte-at byte-len char->integer file-close
  file-open-read file-read-run file-write length map reverse str-make-raw
  string-append string-concat string=? substring sys-dup2)
(import cu/strings cu-range-number)
(import cu/text cu-stdin-pieces)

(import x/codec/crypt)

; pw_encrypt: PW hashed with SALT, the method the salt's prefix names -- $1$
; md5, $5$ sha256, $6$ sha512, anything else the DES of its first two
; characters -- as the libc crypt busybox calls answers it: "*" for a DES
; salt that is too short, or holds a newline or a colon
(def cu-pw-encrypt
  (fn (_ pw salt)
    (def unsafe? (fn (_ i) (if (< i (byte-len salt)) (let ((c (byte-at salt i))) (if (= c #\newline) #t (= c #\:))) #t)))
    (match
      ((Str8 starts? "$1$" salt) (Crypt md5 pw (substring salt 3 (byte-len salt))))
      ((Str8 starts? "$5$" salt) (Crypt sha256 pw (substring salt 3 (byte-len salt))))
      ((Str8 starts? "$6$" salt) (Crypt sha512 pw (substring salt 3 (byte-len salt))))
      ((if (unsafe? 0) #t (unsafe? 1)) "*")
      (#t (Crypt des pw salt)))))

(def cu-cryptpw (fn (_ argv stdin-thunk) (%cw-run "cryptpw" argv stdin-thunk)))
(def cu-mkpasswd (fn (_ argv stdin-thunk) (%cw-run "mkpasswd" argv stdin-thunk)))

(def %cw-run
  (fn (_ applet argv stdin-thunk)
    (def opts (cu-opts applet argv))
    (def either (fn (_ a b) (let ((v (Opts value opts a))) (if (null? v) (Opts value opts b) v))))
    (def words (Opts operands opts))
    (def method (let ((v (either "-m" "--method"))) (if (null? v) (let ((a (Opts value opts "-a"))) (if (null? a) "sha512" a)) v)))
    (def given (let ((v (either "-S" "--salt"))) (if (null? v) (if (pair? words) (if (pair? (rest words)) (first (rest words)) ()) ()) v)))
    (def pfd (either "-P" "--password-fd"))
    (def fd (if (null? pfd) 0 (cu-range-number applet pfd 0 2147483647)))
    (match
      ((> (length words) 2) (cu-usage applet))
      ((null? fd) 1)
      ; -P's descriptor becomes standard input before anything is read
      ((< (sys-dup2 fd fd) 0)
        (do (file-write 2 (string-append applet ": can't duplicate file descriptor: Bad file descriptor\n")) 1))
      (#t
        (let ((pw (if (pair? words) (first words) (%cw-read-line fd stdin-thunk))))
          (do (unless (null? pw) (file-write 1 (string-append (cu-pw-encrypt pw (%cw-salt method given)) "\n")))
              0))))))

; crypt_make_pw_salt: the method's prefix, by its first letter in any case --
; d des, none; s sha256's $5$, or sha512's $6$ when it is that; anything else
; md5's $1$ -- then S, or as many random characters as the method takes
(def %cw-salt
  (fn (_ m s)
    (def c (if (= (byte-len m) 0) #\space (| (char->integer (byte-at m 0)) 32)))
    (def sha512? (string=? (Str8 downcase m) "sha512"))
    (def prefix (match ((= c #\d) "") ((= c #\s) (if sha512? "$6$" "$5$")) (#t "$1$")))
    (string-append prefix
      (if (null? s) (hd-salt (match ((= c #\d) 2) ((= c #\s) 16) (#t 8))) s))))

; a line from FD, its newline dropped; nil at the end before any byte.
; Standard input is the applet's own, read through its thunk.
(def %cw-read-line
  (fn (_ fd stdin-thunk)
    (if (= fd 0)
      (let ((p ((cu-stdin-pieces stdin-thunk))))
        (if (= (rest p) 0) ()
          (let ((t (if (= (rest p) (byte-len (first p))) (first p) (substring (first p) 0 (rest p)))))
            (let ((nl (dp-find t 0 #\newline))) (if (< nl 0) t (substring t 0 nl))))))
      (let ((buf (str-make-raw 1)))
        (let go ((acc ()))
          (let ((r (File read fd buf 1)))
            (match
              ((<= r 0) (if (null? acc) () (bytes->str (reverse acc))))
              ((= (char->integer (byte-at buf 0)) 10) (bytes->str (reverse acc)))
              (#t (go (pair (char->integer (byte-at buf 0)) acc))))))))))

; crypt_make_rand64encoded: N characters of crypt's base-64, from /dev/urandom
(def hd-salt
  (fn (_ n)
    (let ((fd (file-open-read "/dev/urandom")))
      (let ((r (file-read-run fd n)))
        (do (file-close fd)
            (string-concat
              (map (fn (_ b) (let ((v (bit-and b 63))) (substring cu-crypt64 v (+ v 1))))
                   (cu-bytes (first r) 0 (rest r)))))))))

(provide cu/crypt cu-cryptpw cu-mkpasswd cu-pw-encrypt hd-salt)

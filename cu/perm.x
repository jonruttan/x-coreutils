; # x-coreutils -- the small tools, as applets
;
; ## cu/perm.x -- the permission and link half of the parity set
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; chmod chown chgrp ln link readlink realpath mkfifo df sync.  Every
; applet here rides a door x-lang opened for this bundle (PR #607);
; none of them existed while the tool tier could only read and write.

; --- the mode, read two ways --------------------------------------------------

(def %cu-octal->int
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i acc)
        (if (>= i end) acc
          (let ((b (byte-at s i)))
            (if (if (>= b 48) (<= b 55) #f)
              (self (+ i 1) (+ (* acc 8) (- b 48)))
              acc)))))
    (go 0 0)))

(def %cu-octal-mode?
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i)
        (if (>= i end) (> end 0)
          (let ((b (byte-at s i)))
            (if (if (>= b 48) (<= b 55) #f) (self (+ i 1)) #f)))))
    (go 0)))

; a symbolic mode is [ugoa]*[+-=][rwx]*, and the WHO selects which of
; the three permission triples the [rwx] bits land in
(def %cu-mode-who
  (fn (_ s stop)
    (def go
      (fn (self i acc)
        (if (>= i stop) (if (= acc 0) 448 acc)         ; bare op means u
          (let ((b (byte-at s i)))
            (if (= b 117) (self (+ i 1) (bit-or acc 448))     ; u
              (if (= b 103) (self (+ i 1) (bit-or acc 56))    ; g
                (if (= b 111) (self (+ i 1) (bit-or acc 7))   ; o
                  (if (= b 97) (self (+ i 1) (bit-or acc 511)) ; a
                    (if (= acc 0) 448 acc)))))))))
    (go 0 0)))

; the [rwx] letters, spread across all three triples; the who mask
; then selects the ones that apply
(def %cu-mode-bits
  (fn (_ s from)
    (def end (byte-len s))
    (def go
      (fn (self i acc)
        (if (>= i end) acc
          (let ((b (byte-at s i)))
            (if (= b 114) (self (+ i 1) (bit-or acc 292))     ; r: 0444
              (if (= b 119) (self (+ i 1) (bit-or acc 146))   ; w: 0222
                (if (= b 120) (self (+ i 1) (bit-or acc 73))  ; x: 0111
                  (self (+ i 1) acc))))))))
    (go from 0)))

(def %cu-mode-op-at
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i)
        (if (>= i end) (- 0 1)
          (let ((b (byte-at s i)))
            (if (if (= b 43) #t (if (= b 45) #t (= b 61))) i   ; + - =
              (self (+ i 1)))))))
    (go 0)))

; one symbolic clause applied to a current mode
(def %cu-apply-symbolic
  (fn (_ spec mode)
    (def at (%cu-mode-op-at spec))
    (if (< at 0) mode
      (let ((who (%cu-mode-who spec at)))
        (def bits (bit-and (%cu-mode-bits spec (+ at 1)) who))
        (def op (byte-at spec at))
        (if (= op 43) (bit-or mode bits)                       ; +
          (if (= op 45) (bit-and mode (bit-xor bits 4095))     ; -
            (bit-or (bit-and mode (bit-xor who 4095)) bits))))))) ; =

(def %cu-mode-of
  (fn (_ spec current)
    (if (%cu-octal-mode? spec) (%cu-octal->int spec)
      (let ((go (fn (self cs m)
                  (if (null? cs) m
                    (self (rest cs) (%cu-apply-symbolic (first cs) m))))))
        (go (%cu-split-byte spec 44) current)))))               ; ,

; --- chmod, chown, chgrp ------------------------------------------------------

(def %cu-chmod-one
  (fn (_ spec path recurse?)
    (let ((st (file-stat-full path)))
      (if (null? st) 1
        (do (file-chmod path
              (%cu-mode-of spec (bit-and (%cu-stat-get st (lit mode)) 4095)))
            (if (if recurse? (eq? (%cu-stat-get st (lit kind)) (lit dir)) #f)
              (%cu-chmod-kids spec path)
              ())
            0)))))

(def %cu-chmod-kids
  (fn (_ spec dir)
    (def go
      (fn (self ns)
        (if (null? ns) ()
          (do (%cu-chmod-one spec (%cu-path-join dir (first ns)) #t)
              (self (rest ns))))))
    (go (filter (fn (_ n) (not (%cu-dot? n))) (file-list-dir dir)))))

(def %cu-chmod
  (fn (_ argv stdin-thunk)
    (def r? (%cu-has-flag? argv "-R"))
    (def ops (filter (fn (_ x) (not (%cu-option-token? x))) argv))
    (if (null? (rest ops))
      (do (file-write 2 "chmod: need MODE and a path\n") 1)
      (let ((spec (first ops)))
        (def go
          (fn (self ps st)
            (if (null? ps) st
              (let ((r (%cu-chmod-one spec (first ps) r?)))
                (do (if (= r 0) ()
                      (file-write 2
                        (string-concat
                          (list "chmod: cannot access '" (first ps) "'\n"))))
                    (self (rest ps) (if (> r st) r st)))))))
        (go (rest ops) 0)))))

; chown and chgrp take NUMERIC ids: there is no passwd or group door,
; so a name cannot be resolved.  USER:GROUP is accepted, either half
; may be empty, and -1 leaves that half alone.
(def %cu-owner-pair
  (fn (_ spec)
    (def parts (%cu-split-byte spec 58))                        ; :
    (def u (if (null? parts) "" (first parts)))
    (def g (if (null? parts) "" (if (null? (rest parts)) "" (first (rest parts)))))
    (pair (if (= (byte-len u) 0) (- 0 1) (%cu-num-prefix u))
      (if (= (byte-len g) 0) (- 0 1) (%cu-num-prefix g)))))

(def %cu-chown-with
  (fn (_ ids argv)
    (def ops (filter (fn (_ x) (not (%cu-option-token? x))) argv))
    (def go
      (fn (self ps st)
        (if (null? ps) st
          (if (not (file-exists? (first ps)))
            (do (file-write 2
                  (string-concat
                    (list "chown: cannot access '" (first ps) "'\n")))
                (self (rest ps) 1))
            (do (file-chown (first ps) (first ids) (rest ids))
                (self (rest ps) st))))))
    (go ops 0)))

(def %cu-chown
  (fn (_ argv stdin-thunk)
    (def ops (filter (fn (_ x) (not (%cu-option-token? x))) argv))
    (if (null? (rest ops))
      (do (file-write 2 "chown: need OWNER and a path\n") 1)
      (%cu-chown-with (%cu-owner-pair (first ops)) (rest ops)))))

(def %cu-chgrp
  (fn (_ argv stdin-thunk)
    (def ops (filter (fn (_ x) (not (%cu-option-token? x))) argv))
    (if (null? (rest ops))
      (do (file-write 2 "chgrp: need GROUP and a path\n") 1)
      (%cu-chown-with (pair (- 0 1) (%cu-num-prefix (first ops)))
        (rest ops)))))

; --- ln, link, readlink, realpath ---------------------------------------------

(def %cu-ln
  (fn (_ argv stdin-thunk)
    (def s? (%cu-has-flag? argv "-s"))
    (def f? (%cu-has-flag? argv "-f"))
    (def ops (filter (fn (_ x) (not (%cu-option-token? x))) argv))
    (if (null? (rest ops))
      (do (file-write 2 "ln: need TARGET and a name\n") 1)
      (let ((target (first ops)))
        ; `ln target dir` puts the link INSIDE the directory
        (def named (first (rest ops)))
        (def name (if (file-dir? named)
                    (%cu-path-join named (%cu-basename-of target))
                    named))
        (do (if (if f? (file-exists? name) #f) (file-unlink name) ())
            (if s? (file-symlink target name) (file-link target name))
            0)))))

(def %cu-basename-of
  (fn (_ p)
    (def end (byte-len p))
    (def go
      (fn (self i)
        (if (< i 0) p
          (if (= (byte-at p i) 47) (substring p (+ i 1) end)
            (self (- i 1))))))
    (go (- end 1))))

(def %cu-link
  (fn (_ argv stdin-thunk)
    (if (null? (rest argv))
      (do (file-write 2 "link: need TARGET and a name\n") 1)
      (do (file-link (first argv) (first (rest argv))) 0))))

(def %cu-dirname-of
  (fn (_ p)
    (def go
      (fn (self i)
        (if (< i 0) "."
          (if (= (byte-at p i) 47) (if (= i 0) "/" (substring p 0 i))
            (self (- i 1))))))
    (go (- (byte-len p) 1))))

(def %cu-readlink
  (fn (_ argv stdin-thunk)
    (def f? (if (%cu-has-flag? argv "-f") #t (%cu-has-flag? argv "-e")))
    (def ops (filter (fn (_ x) (not (%cu-option-token? x))) argv))
    (if (null? ops)
      (do (file-write 2 "readlink: missing operand\n") 1)
      (let ((p (first ops)))
        (if f?
          (do (display (string-append (%cu-realpath-of p) "\n")) 0)
          (if (eq? (file-lstat-kind p) (lit link))
            (do (display (string-append (file-readlink p) "\n")) 0)
            1))))))

; realpath: walk the segments, resolving every prefix that turns out to
; be a link.  A resolved link REPLACES what has been walked so far and
; the walk RESTARTS over it -- /tmp is a link to /private/tmp, so the
; prefix must be re-examined, not patched.  The fuel bounds a cycle.
(def %cu-path-parts
  (fn (_ p)
    (filter (fn (_ s) (> (byte-len s) 0)) (%cu-split-byte p 47))))

(def %cu-realpath-walk
  (fn (self parts acc fuel)
    (if (null? parts) (pair acc #t)
      (if (<= fuel 0) (pair acc #f)
        (let ((seg (first parts)))
          (if (string=? seg ".")
            (self (rest parts) acc fuel)
            (if (string=? seg "..")
              (self (rest parts) (if (null? acc) acc (rest acc)) fuel)
              (let ((here (string-append "/"
                            (%cu-join-with (reverse (pair seg acc)) "/"))))
                (if (eq? (file-lstat-kind here) (lit link))
                  (self
                    (append (%cu-path-parts (%cu-readlink-from here))
                      (rest parts))
                    () (- fuel 1))
                  (self (rest parts) (pair seg acc) fuel))))))))))

; a link's target as an ABSOLUTE path: a relative target is read
; against the directory the link itself sits in
(def %cu-readlink-from
  (fn (_ path)
    (let ((t (file-readlink path)))
      (if (= (byte-len t) 0) t
        (if (= (byte-at t 0) 47) t
          (%cu-path-join (%cu-dirname-of path) t))))))

(def %cu-realpath-of
  (fn (_ p)
    (def abs (if (= (byte-len p) 0) (sys-getcwd)
               (if (= (byte-at p 0) 47) p
                 (%cu-path-join (sys-getcwd) p))))
    (def r (%cu-realpath-walk (%cu-path-parts abs) () 64))
    (if (null? (first r)) "/"
      (string-append "/" (%cu-join-with (reverse (first r)) "/")))))

(def %cu-realpath
  (fn (_ argv stdin-thunk)
    (if (null? argv)
      (do (file-write 2 "realpath: missing operand\n") 1)
      (let ((go (fn (self ps st)
                  (if (null? ps) st
                    (if (not (file-exists? (first ps)))
                      (do (file-write 2
                            (string-concat
                              (list "realpath: " (first ps)
                                    ": No such file or directory\n")))
                          (self (rest ps) 1))
                      (do (display
                            (string-append (%cu-realpath-of (first ps)) "\n"))
                          (self (rest ps) st)))))))
        (go argv 0)))))

; --- mkfifo, df, sync ---------------------------------------------------------

(def %cu-mkfifo
  (fn (_ argv stdin-thunk)
    (def m? (%cu-has-flag? argv "-m"))
    (def mode (if m? (%cu-octal->int (first (rest argv))) 420))
    (def ops (filter (fn (_ x) (not (%cu-option-token? x)))
               (if m? (rest (rest argv)) argv)))
    (if (null? ops)
      (do (file-write 2 "mkfifo: missing operand\n") 1)
      (let ((go (fn (self ps)
                  (if (null? ps) 0
                    (do (file-mkfifo (first ps) mode) (self (rest ps)))))))
        (go ops)))))

; df: one row per operand (the mount a path sits on), in 1024-byte
; blocks.  There is no mount-table door, so a bare `df` measures the
; working directory rather than listing every filesystem.
(def %cu-df-row
  (fn (_ path human?)
    (let ((s (file-statfs path)))
      (def bsize (%cu-stat-get s (lit bsize)))
      (def per-k (/ (- bsize (% bsize 1024)) 1024))
      (def total (* (%cu-stat-get s (lit blocks)) per-k))
      (def avail (* (%cu-stat-get s (lit bavail)) per-k))
      (def used (- total avail))
      (def pct (if (= total 0) 0
                 (let ((n (* used 100)))
                   (/ (- n (% n total)) total))))
      (display
        (string-concat
          (list (%cu-pad-left (if human? (%cu-human total) (%cu-int->str total)) 10)
                (%cu-pad-left (if human? (%cu-human used) (%cu-int->str used)) 10)
                (%cu-pad-left (if human? (%cu-human avail) (%cu-int->str avail)) 10)
                (%cu-pad-left (string-append (%cu-int->str pct) "%") 5)
                " " path "\n"))))))

; a size in kilobytes, printed the way -h does: the largest unit whose
; value is still a whole number of digits
(def %cu-human
  (fn (_ k)
    (if (< k 1024) (string-append (%cu-int->str k) "K")
      (let ((m (/ (- k (% k 1024)) 1024)))
        (if (< m 1024) (string-append (%cu-int->str m) "M")
          (let ((g (/ (- m (% m 1024)) 1024)))
            (if (< g 1024) (string-append (%cu-int->str g) "G")
              (string-append
                (%cu-int->str (/ (- g (% g 1024)) 1024)) "T"))))))))

(def %cu-df
  (fn (_ argv stdin-thunk)
    (def h? (%cu-has-flag? argv "-h"))
    (def ops0 (filter (fn (_ x) (not (%cu-option-token? x))) argv))
    (def ops (if (null? ops0) (list (sys-getcwd)) ops0))
    (do (display
          (string-concat
            (list (%cu-pad-left (if h? "Size" "1K-blocks") 10)
                  (%cu-pad-left "Used" 10)
                  (%cu-pad-left "Avail" 10)
                  (%cu-pad-left "Use%" 5)
                  " Mounted on\n")))
        (let ((go (fn (self ps st)
                    (if (null? ps) st
                      (if (not (file-exists? (first ps)))
                        (do (file-write 2
                              (string-concat
                                (list "df: " (first ps) ": No such file\n")))
                            (self (rest ps) 1))
                        (do (%cu-df-row (first ps) h?)
                            (self (rest ps) st)))))))
          (go ops 0)))))

(def %cu-sync
  (fn (_ argv stdin-thunk) (do (sys-sync) 0)))

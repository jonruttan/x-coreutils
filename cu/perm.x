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
            (match
              ((= b 117) (self (+ i 1) (bit-or acc 448)))     ; u
              ((= b 103) (self (+ i 1) (bit-or acc 56)))      ; g
              ((= b 111) (self (+ i 1) (bit-or acc 7)))       ; o
              ((= b 97)  (self (+ i 1) (bit-or acc 511)))     ; a
              (#t (if (= acc 0) 448 acc)))))))
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
            (match
              ((= b 114) (self (+ i 1) (bit-or acc 292)))     ; r: 0444
              ((= b 119) (self (+ i 1) (bit-or acc 146)))     ; w: 0222
              ((= b 120) (self (+ i 1) (bit-or acc 73)))      ; x: 0111
              (#t (self (+ i 1) acc)))))))
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
        (match
          ((= op 43) (bit-or mode bits))                       ; +
          ((= op 45) (bit-and mode (bit-xor bits 4095)))       ; -
          (#t (bit-or (bit-and mode (bit-xor who 4095)) bits))))))) ; =

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
    (%cu-walk-status dir
      (fn (_ n)
        (do (%cu-chmod-one spec (%cu-path-join dir n) #t) 0)))))

(def %cu-chmod
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "chmod" argv))
    (def r? (Opts on? o "-R"))
    (def ops (Opts operands o))
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

; -R descends; -h changes the LINK rather than what it points at, and
; -L/-H/-P say whether the descent follows one (-P, not following, is
; the default and the only one a chown of a link can honour without a
; lchown door -- -h is that door's absence made loud).
(def %cu-chown-one
  (fn (self path ids o name)
    (def kind (file-lstat-kind path))
    (if (eq? kind (lit none))
      (do (if (Opts on? o "-f") ()
            (file-write 2
              (string-concat
                (list name ": cannot access '" path "'\n"))))
          (if (Opts on? o "-f") 0 1))
      (do
        ; a symlink is skipped unless -h asks for the link itself; there
        ; is no lchown door, so -h REFUSES rather than changing the
        ; target behind the caller's back
        (if (eq? kind (lit link))
          (if (Opts on? o "-h")
            (do (file-write 2
                  (string-concat
                    (list name ": no lchown door: cannot change '"
                          path "' itself\n")))
                ())
            ())
          (do (file-chown path (first ids) (rest ids))
              (if (Opts on? o "-v")
                (display (string-concat
                           (list "changed ownership of '" path "'\n")))
                ())))
        (if (if (Opts on? o "-R") (eq? kind (lit dir)) #f)
          (%cu-walk-status path
            (fn (_ n) (self (%cu-path-join path n) ids o name)))
          0)))))

; the first operand is the owner spec; the rest are the paths
(def %cu-chown-with
  (fn (_ ids paths o name)
    (def go
      (fn (self ps st)
        (if (null? ps) st
          (let ((r (%cu-chown-one (first ps) ids o name)))
            (self (rest ps) (if (> r st) r st))))))
    (go paths 0)))

(def %cu-chown
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "chown" argv))
    (def ops (Opts operands o))
    (if (null? (rest ops))
      (do (file-write 2 "chown: need OWNER and a path\n") 1)
      (%cu-chown-with (%cu-owner-pair (first ops)) (rest ops) o "chown"))))

(def %cu-chgrp
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "chgrp" argv))
    (def ops (Opts operands o))
    (if (null? (rest ops))
      (do (file-write 2 "chgrp: need GROUP and a path\n") 1)
      (%cu-chown-with (pair (- 0 1) (%cu-num-prefix (first ops))) (rest ops) o "chgrp"))))

; --- ln, link, readlink, realpath ---------------------------------------------

; ln moved to cu/fs.x with busybox's option set (-s -f -n -b -t -v).

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

; -n leaves the newline off; -v names what went wrong, where the plain
; form answers a non-link with a silent 1.
(def %cu-readlink
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "readlink" argv))
    (def f? (if (Opts on? o "-f") #t (Opts on? o "-e")))
    (def nl (if (Opts on? o "-n") "" "\n"))
    (def complain
      (fn (_ p why)
        (do (if (Opts on? o "-v")
              (file-write 2 (string-concat (list "readlink: " p ": " why "\n")))
              ())
            1)))
    (def ops (Opts operands o))
    (if (null? ops)
      (do (file-write 2 "readlink: missing operand\n") 1)
      (let ((p (first ops)))
        (match
          (f? (do (display (string-append (%cu-realpath-of p) nl)) 0))
          ((eq? (file-lstat-kind p) (lit link))
            (do (display (string-append (file-readlink p) nl)) 0))
          ((file-exists? p) (complain p "Invalid argument"))
          (#t (complain p "No such file or directory")))))))

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
    (def o (%cu-opts "mkfifo" argv))
    (def m (Opts value o "-m"))
    (def mode (if (null? m) 420 (%cu-octal->int m)))
    (def ops (Opts operands o))
    (if (null? ops)
      (do (file-write 2 "mkfifo: missing operand\n") 1)
      (let ((go (fn (self ps)
                  (if (null? ps) 0
                    (do (file-mkfifo (first ps) mode) (self (rest ps)))))))
        (go ops)))))

; df: one row per operand (the mount a path sits on) or, with none, one
; per mounted filesystem, in 1024-byte blocks.  The mount table is
; file-mounts'; a path is matched to its mount by the filesystem id
; statfs answers for it, so the row names the device and the mount
; point, as df's does.
;
; What a bare df lists is what df lists.  A mount of a dummy type
; (devfs, autofs, proc ...) is left out, as is one whose mount point
; shares its device with a shorter one -- APFS's firmlinked Data volume
; stats as the root's device -- and one with no blocks.  -a lists them
; all: the dummies with their counts, the duplicates with dashes, since
; df does not stat those.

; the unit a row counts in, in BYTES: 1024 by default and under -k,
; 1048576 under -m, and -B SIZE with a K, M, G or T after the number as
; df takes it.  -h formats the bytes instead of counting them.
(def %cu-df-unit
  (fn (_ o)
    (let ((b (Opts value o "-B")))
      (if (not (null? b))
        (let ((n (%cu-num-prefix b)))
          (def suffix
            (let ((go (fn (self i)
                        (if (>= i (byte-len b)) 0
                          (let ((c (byte-at b i)))
                            (if (if (>= c 48) (<= c 57) #f) (self (+ i 1)) c))))))
              (go 0)))
          (def bytes
            (* n (match
                   ((= suffix 75) 1024)                   ; K
                   ((= suffix 77) 1048576)                ; M
                   ((= suffix 71) 1073741824)             ; G
                   ((= suffix 84) 1099511627776)          ; T
                   (#t 1))))
          (if (< bytes 1) 1 bytes))
        (if (Opts on? o "-m") 1048576 1024)))))

; BYTES as a row shows them: -h through %ls-human, ls's -h formatter,
; else in the unit, rounded UP as df rounds -- 409K under -m is 1
(def %cu-df-show
  (fn (_ bytes o)
    (if (Opts on? o "-h") (%ls-human bytes)
      (%cu-int->str (let ((u (%cu-df-unit o)))
                      (let ((c (+ bytes (- u 1))))
                        (/ (- c (% c u)) u)))))))

; the heading names the unit: 1K-blocks, 1M-blocks, 2K-blocks,
; 512B-blocks
(def %cu-df-heading
  (fn (_ o)
    (let ((u (%cu-df-unit o)))
      (match
        ((= (% u 1073741824) 0)
          (string-append (%cu-int->str (/ u 1073741824)) "G-blocks"))
        ((= (% u 1048576) 0)
          (string-append (%cu-int->str (/ u 1048576)) "M-blocks"))
        ((= (% u 1024) 0)
          (string-append (%cu-int->str (/ u 1024)) "K-blocks"))
        (#t (string-append (%cu-int->str u) "B-blocks"))))))

; the types df calls dummies and leaves out of a plain listing
(def %cu-df-dummy-types
  (list "devfs" "autofs" "proc" "subfs" "debugfs" "devpts" "fusectl"
        "mqueue" "rpc_pipefs" "sysfs" "kernfs" "ignore" "none"))

; the mount table as (MOUNT DUP? DEV) rows: DEV the device its mount
; point stats as, DUP? whether an earlier or shorter mount point sits on
; the same device -- df folds those into the shorter one
(def %cu-df-mounts
  (fn (_)
    (def ms (file-mounts))
    (def dev-of
      (fn (_ m)
        (let ((st (file-stat-full (%cu-stat-get m (lit on)))))
          (if (null? st) (- 0 1) (%cu-stat-get st (lit dev))))))
    (def tagged (map (fn (_ m) (pair m (dev-of m))) ms))
    (def dup?
      (fn (_ m d i)
        (def on (byte-len (%cu-stat-get m (lit on))))
        (def go
          (fn (self xs j)
            (match
              ((null? xs) #f)
              ((not (= (rest (first xs)) d)) (self (rest xs) (+ j 1)))
              ((= j i) (self (rest xs) (+ j 1)))
              ((< (byte-len (%cu-stat-get (first (first xs)) (lit on))) on) #t)
              ((if (= (byte-len (%cu-stat-get (first (first xs)) (lit on))) on)
                 (< j i) #f)
                #t)
              (#t (self (rest xs) (+ j 1))))))
        (if (< d 0) #f (go tagged 0))))
    (def go
      (fn (self xs i acc)
        (if (null? xs) (reverse acc)
          (self (rest xs) (+ i 1)
            (pair (list (first (first xs))
                        (dup? (first (first xs)) (rest (first xs)) i)
                        (rest (first xs)))
                  acc)))))
    (go tagged 0 ())))

; a mount's counts: total, used, available and the percentage, as -i,
; -h and the unit ask for them.  Blocks go to 1024-byte units through
; the byte count, rounded UP as df rounds, so a block size under 1024
; (devfs's 512) is not zero; used counts from what is free to anyone,
; not from what a plain user may take; the percentage is of used plus
; available, rounded UP -- df's and busybox's rule both -- and a dash
; over nothing.  A duplicate is four dashes.
(def %cu-df-cells
  (fn (_ m o dup?)
    (def inodes? (Opts on? o "-i"))
    (def bsize (%cu-stat-get m (lit bsize)))
    ; counts in bytes, exact; the unit and -h are applied at the end
    (def total (if inodes? (%cu-stat-get m (lit files))
                 (* bsize (%cu-stat-get m (lit blocks)))))
    (def avail (if inodes? (%cu-stat-get m (lit ffree))
                 (* bsize (%cu-stat-get m (lit bavail)))))
    (def used (if inodes? (- total avail)
                (* bsize (- (%cu-stat-get m (lit blocks))
                            (%cu-stat-get m (lit bfree))))))
    (def pct (let ((d (+ used avail)))
               (if (= d 0) "-"
                 (let ((n (+ (* used 100) (- d 1))))
                   (string-append (%cu-int->str (/ (- n (% n d)) d)) "%")))))
    (def show (fn (_ v) (if inodes? (%cu-int->str v) (%cu-df-show v o))))
    (if dup? (list "-" "-" "-" "-")
      (list (show total) (show used) (show avail) pct))))

; the table: a column is as wide as its widest cell, its heading, or
; df's own floor for it -- the name fourteen, a count five, the
; percentage four -- with one space between and the last column
; unpadded.  LEFTS says which columns align left.
(def %cu-df-table
  (fn (_ header rows mins lefts)
    (def n (length header))
    (def width
      (fn (_ c)
        (def go
          (fn (self rs w)
            (if (null? rs) w
              (self (rest rs)
                (let ((l (byte-len (%cu-nth c (first rs))))) (if (> l w) l w))))))
        (go rows
          (let ((h (byte-len (%cu-nth c header))) (m (%cu-nth c mins)))
            (if (> h m) h m)))))
    (def ws
      (let ((go (fn (self c acc) (if (< c 0) acc (self (- c 1) (pair (width c) acc))))))
        (go (- n 1) ())))
    (def line
      (fn (_ cells)
        (def go
          (fn (self c acc)
            (if (>= c n) (string-concat (reverse acc))
              (let ((cell (%cu-nth c cells)) (w (%cu-nth c ws)))
                (self (+ c 1)
                  (pair (if (= c (- n 1)) cell
                          (string-append
                            (if (%cu-nth c lefts) (%cu-pad-right cell w)
                              (%cu-pad-left cell w))
                            " "))
                        acc))))))
        (string-append (go 0 ()) "\n")))
    (string-concat (map line (pair header rows)))))

; The mount a path sits on, from the (MOUNT DUP? DEV) rows: the listed
; one on the path's device -- the way df names /tmp on an APFS Data
; volume as the root it was folded into -- else the one whose id statfs
; answers for the path, else the path measured on its own, unnamed.
(def %cu-df-mount-of
  (fn (_ path marked)
    (let ((st (file-stat-full path)))
      (if (null? st) ()
        (let ((dev (%cu-stat-get st (lit dev)))
              (fs (file-statfs-full path)))
          (def by-dev
            (filter (fn (_ e) (if (%cu-nth 1 e) #f (= (%cu-nth 2 e) dev))) marked))
          (def by-id
            (filter (fn (_ e) (= (%cu-stat-get (first e) (lit fsid))
                                 (%cu-stat-get fs (lit fsid))))
              marked))
          (match
            ((pair? by-dev) (first (first by-dev)))
            ((pair? by-id) (first (first by-id)))
            (#t (append (list (pair (lit from) "-") (pair (lit on) path)) fs))))))))

; the heading, each column's floor, and which columns align left, as
; -T -i -h -P and the unit ask for them: (HEADER MINS LEFTS)
(def %cu-df-columns
  (fn (_ o)
    (def t? (Opts on? o "-T"))
    (def i? (Opts on? o "-i"))
    (def h? (Opts on? o "-h"))
    (def p? (Opts on? o "-P"))
    (list
      (append (list "Filesystem")
        (append (if t? (list "Type") ())
          (list (match (i? "Inodes") (h? "Size") (p? "1024-blocks")
                       (#t (%cu-df-heading o)))
                (if i? "IUsed" "Used")
                (match (i? "IFree") (h? "Avail") (#t "Available"))
                (match (i? "IUse%") (p? "Capacity") (#t "Use%"))
                "Mounted on")))
      (append (list 14) (append (if t? (list 4) ()) (list 5 5 5 4 0)))
      (append (list #t) (append (if t? (list #t) ()) (list #f #f #f #f #t))))))

; one mount's row: its name, its type under -T, the counts, the mount point
(def %cu-df-row
  (fn (_ m o dup?)
    (append (list (%cu-stat-get m (lit from)))
      (append (if (Opts on? o "-T")
                (list (if dup? "-" (%cu-stat-get m (lit typename))))
                ())
        (append (%cu-df-cells m o dup?)
          (list (%cu-stat-get m (lit on))))))))

; a plain df's entries from the table: without the dummies, the folded
; duplicates and the empty; -a takes them all
(def %cu-df-listed
  (fn (_ o marked)
    (def dummy?
      (fn (_ m) (%cu-member-s? (%cu-stat-get m (lit typename)) %cu-df-dummy-types)))
    (filter
      (fn (_ e)
        (match
          ((Opts on? o "-a") #t)
          ((%cu-nth 1 e) #f)
          ((dummy? (first e)) #f)
          (#t (> (%cu-stat-get (first e) (lit blocks)) 0))))
      marked)))

(def %cu-df
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "df" argv))
    (def ops (Opts operands o))
    (def marked (%cu-df-mounts))
    (def found (map (fn (_ p) (pair p (%cu-df-mount-of p marked))) ops))
    (def missing
      (map (fn (_ f) (first f)) (filter (fn (_ f) (null? (rest f))) found)))
    ; the rows: the operands' mounts, else the table's listing
    (def rows
      (if (pair? ops)
        (map (fn (_ f) (%cu-df-row (rest f) o #f))
          (filter (fn (_ f) (not (null? (rest f)))) found))
        (map (fn (_ e) (%cu-df-row (first e) o (%cu-nth 1 e)))
          (%cu-df-listed o marked))))
    (def cols (%cu-df-columns o))
    (do (%cu-print-lines-to 2
          (map (fn (_ p) (string-concat (list "df: " p ": No such file or directory")))
            missing))
        ; no table when nothing asked for could be found
        (if (if (pair? ops) (null? rows) #f) ()
          (display
            (%cu-df-table (first cols) rows (%cu-nth 1 cols) (%cu-nth 2 cols))))
        (if (null? missing) 0 1))))

; sync with no operand syncs everything. -d asks for a file's DATA and -f
; for the filesystem holding it; this has fsync and a whole-system sync,
; both of which are supersets of what is asked, so the guarantee each
; flag wants is met by doing more than it wants rather than less.
(def %cu-sync
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "sync" argv))
    (def ops (Opts operands o))
    (if (null? ops)
      (do (sys-sync) 0)
      (if (Opts on? o "-f")
        (do (sys-sync) 0)
        (let ((go (fn (self os st)
                    (if (null? os) st
                      (let ((fd (file-open-read (first os))))
                        (if (null? fd)
                          (do (file-write 2
                                (string-concat
                                  (list "sync: cannot open " (first os) "\n")))
                              (self (rest os) 1))
                          (do (sys-fsync fd) (file-close fd)
                              (self (rest os) st))))))))
          (go ops 0))))))

; # x-coreutils -- the small tools, as applets
;
; ## cu/fs3.x -- the parity expansion, file and process half
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; stat du dd truncate unlink shred timeout usleep tty nohup [[.
; These ride the WIDE stat (cu/prims.x): File stat answers four fields,
; and stat(1) and du(1) want uid, gid, links, inode and the block
; count as well.

; Options come off (Opts parse ...) against cu/cli.x's declaration, so the guard
; and the applet cannot disagree about what a flag meant -- the hand-rolled
; per-applet parsers that lived here and across the applets are gone.

(def %cu-stat-get
  (fn (_ st key)
    (let ((e (Assoc entry key st)))
      (if (null? e) 0 (rest e)))))

; --- the mode, spelled two ways -----------------------------------------------

(def %cu-mode-octal
  (fn (_ mode) (%cu-oct->str (bit-and mode 4095))))

; four digits, as stat's Access line and chmod's reports show a mode: 0644
(def %cu-mode-octal4
  (fn (_ mode) (%cu-zero-pad (%cu-mode-octal mode) 4)))

(def %cu-kind-letter
  (fn (_ kind)
    (match
      ((eq? kind (lit dir))    "d")
      ((eq? kind (lit link))   "l")
      ((eq? kind (lit char))   "c")
      ((eq? kind (lit block))  "b")
      ((eq? kind (lit fifo))   "p")
      ((eq? kind (lit socket)) "s")
      (#t "-"))))

(def %cu-kind-word
  (fn (_ kind)
    (match
      ((eq? kind (lit dir))    "directory")
      ((eq? kind (lit link))   "symbolic link")
      ((eq? kind (lit char))   "character special file")
      ((eq? kind (lit block))  "block special file")
      ((eq? kind (lit fifo))   "fifo")
      ((eq? kind (lit socket)) "socket")
      (#t "regular file"))))

; rwx for one octal digit, the execute place spelled X when the bit is set and
; DASH when it is clear
(def %cu-rwx
  (fn (_ d x dash)
    (string-append (if (= (bit-and d 4) 0) "-" "r")
      (string-append (if (= (bit-and d 2) 0) "-" "w")
        (if (= (bit-and d 1) 0) dash x)))))

; the triple SHIFT bits up, its execute place spelled X or DASH when the
; SPECIAL bit is set
(def %cu-perm-triple
  (fn (_ mode shift special x dash)
    (if (= (bit-and mode special) 0)
      (%cu-rwx (bit-and (bit-shr mode shift) 7) "x" "-")
      (%cu-rwx (bit-and (bit-shr mode shift) 7) x dash))))

; the nine places of a mode.  The setuid, setgid and sticky bits show in the
; execute places of the user, the group and the others: s and t over a set
; execute bit, S and T over a clear one -- rwsr-xr-x, rw-r--r-T
(def %cu-perm-places
  (fn (_ mode)
    (string-append (%cu-perm-triple mode 6 2048 "s" "S")       ; 04000
      (string-append (%cu-perm-triple mode 3 1024 "s" "S")     ; 02000
        (%cu-perm-triple mode 0 512 "t" "T")))))               ; 01000

(def %cu-perm-string
  (fn (_ kind mode)
    (string-append (%cu-kind-letter kind) (%cu-perm-places mode))))

; --- stat ---------------------------------------------------------------------

; a device number's halves, as the platform packs them: Darwin keeps the
; major in the top byte; Linux (glibc) splits each across the word
(def %cu-dev-major
  (fn (_ dev)
    (if os-darwin? (bit-and (bit-shr dev 24) 255)
      (+ (bit-and (bit-shr dev 8) 4095)
         (bit-and (bit-shr dev 32) 4294963200)))))

(def %cu-dev-minor
  (fn (_ dev)
    (if os-darwin? (bit-and dev 16777215)
      (+ (bit-and dev 255) (bit-and (bit-shr dev 12) 4294967040)))))

; -c FMT: the GNU specifiers busybox carries. Anything else is copied through,
; so a format is never silently eaten.
(def %cu-stat-spec
  (fn (_ c name st)
    (def kind (%cu-stat-get st (lit kind)))
    (def mode (%cu-stat-get st (lit mode)))
    (def num (fn (_ key) (%cu-int->str (%cu-stat-get st key))))
    (def hex (fn (_ key) (%cu-hexs (%cu-stat-get st key))))
    (match
      ((= c 110) name)                          ; n
      ((= c 115) (num (lit size)))              ; s
      ((= c 98)  (num (lit blocks)))            ; b
      ((= c 66)  "512")                         ; B
      ((= c 102) (%cu-hexs mode))               ; f
      ((= c 97)  (%cu-mode-octal mode))         ; a
      ((= c 65)  (%cu-perm-string kind mode))   ; A
      ((= c 117) (num (lit uid)))               ; u
      ((= c 103) (num (lit gid)))               ; g
      ((= c 104) (num (lit nlink)))             ; h
      ((= c 105) (num (lit ino)))               ; i
      ((= c 100) (num (lit dev)))               ; d
      ((= c 68)  (hex (lit dev)))               ; D
      ((= c 114) (num (lit rdev)))              ; r
      ((= c 82)  (hex (lit rdev)))              ; R
      ((= c 116) (%cu-hexs (%cu-dev-major (%cu-stat-get st (lit rdev)))))   ; t
      ((= c 84)  (%cu-hexs (%cu-dev-minor (%cu-stat-get st (lit rdev)))))   ; T
      ((= c 70)  (%cu-kind-word kind))          ; F
      ((= c 88)  (num (lit atime)))             ; X
      ((= c 89)  (num (lit mtime)))             ; Y
      ((= c 90)  (num (lit ctime)))             ; Z
      ((= c 87)  (num (lit btime)))             ; W
      ((= c 111) (num (lit blksize)))           ; o
      (#t (string-append "%" (%cu-b->s c))))))

; -f's specifiers, for a filesystem.  Darwin has no name limit to
; report, and stat prints `?` for it.
(def %cu-stat-fs-spec
  (fn (_ c name fs)
    (def num (fn (_ key) (%cu-int->str (%cu-stat-get fs key))))
    (match
      ((= c 110) name)                                       ; n
      ((= c 105) (%cu-hexs (%cu-stat-get fs (lit fsid))))    ; i
      ((= c 108)                                             ; l
        (let ((e (Assoc entry (lit namelen) fs)))
          (if (null? e) "?" (%cu-int->str (rest e)))))
      ((= c 116) (%cu-hexs (%cu-stat-get fs (lit type))))    ; t
      ((= c 84)  (%cu-stat-get fs (lit typename)))           ; T
      ((= c 115) (num (lit bsize)))                          ; s
      ((= c 83)  (num (lit frsize)))                         ; S
      ((= c 98)  (num (lit blocks)))                         ; b
      ((= c 102) (num (lit bfree)))                          ; f
      ((= c 97)  (num (lit bavail)))                         ; a
      ((= c 99)  (num (lit files)))                          ; c
      ((= c 100) (num (lit ffree)))                          ; d
      (#t (string-append "%" (%cu-b->s c))))))

; The scanning is cu/fmt-lex.x's; SPEC is one of the two above.
(def %cu-stat-format
  (fn (_ fmt name st spec)
    (def go
      (fn (self ts acc)
        (if (null? ts) (string-concat (reverse acc))
          (let ((t (first ts)))
            (self (rest ts)
              (pair
                (if (%cu-fmt-dir? t)
                  (let ((conv (%cu-fmt-conv t)))
                    ; %% is a %, and so is a format ending in a bare one
                    (match
                      ((= (byte-len conv) 0) "%")
                      ((string=? conv "%") "%")
                      (#t (spec (byte-at conv 0) name st))))
                  t)
                acc))))))
    (go (%cu-fmt-parse fmt #f) ())))

; the default block, as stat lays it out: the device as major,minor,
; the inode padded to ten, a device's own type after its link count.
; The user and group are NUMERIC: there is no passwd door, so the name
; column real stat(1) prints is not available.
(def %cu-stat-default
  (fn (_ name st)
    (def kind (%cu-stat-get st (lit kind)))
    (def mode (%cu-stat-get st (lit mode)))
    (def dev (%cu-stat-get st (lit dev)))
    (def rdev (%cu-stat-get st (lit rdev)))
    (def nlink (%cu-int->str (%cu-stat-get st (lit nlink))))
    (def device? (if (eq? kind (lit char)) #t (eq? kind (lit block))))
    (string-concat
      (list "  File: " name "\n"
            "  Size: " (%cu-int->str (%cu-stat-get st (lit size)))
            "\tBlocks: " (%cu-int->str (%cu-stat-get st (lit blocks)))
            "\tIO Block: " (%cu-int->str (%cu-stat-get st (lit blksize)))
            "\t" (%cu-kind-word kind) "\n"
            "Device: " (%cu-int->str (%cu-dev-major dev)) ","
            (%cu-int->str (%cu-dev-minor dev))
            "\tInode: "
            (%cu-pad-right (%cu-int->str (%cu-stat-get st (lit ino))) 10)
            "  Links: "
            (if device?
              (string-concat
                (list (%cu-pad-right nlink 5) " Device type: "
                      (%cu-int->str (%cu-dev-major rdev)) ","
                      (%cu-int->str (%cu-dev-minor rdev))))
              nlink)
            "\n"
            "Access: (" (%cu-mode-octal4 mode) "/"
            (%cu-perm-string kind mode) ")  Uid: ("
            (%cu-int->str (%cu-stat-get st (lit uid))) ")   Gid: ("
            (%cu-int->str (%cu-stat-get st (lit gid))) ")\n"))))

; the filesystem block under -f, in stat -f's column widths
(def %cu-stat-fs-default
  (fn (_ name fs)
    (def sp (fn (_ c) (%cu-stat-fs-spec c name fs)))
    (string-concat
      (list "  File: \"" name "\"\n"
            "    ID: " (%cu-pad-right (sp 105) 8)
            " Namelen: " (%cu-pad-right (sp 108) 7)
            " Type: " (sp 84) "\n"
            "Block size: " (%cu-pad-right (sp 115) 10)
            " Fundamental block size: " (sp 83) "\n"
            "Blocks: Total: " (%cu-pad-right (sp 98) 10)
            " Free: " (%cu-pad-right (sp 102) 10)
            " Available: " (sp 97) "\n"
            "Inodes: Total: " (%cu-pad-right (sp 99) 10)
            " Free: " (sp 100) "\n"))))

(def %cu-stat
  (fn (_ argv stdin-thunk)
    ; Read through the declaration, so -c may follow its operands and -L is
    ; reached at all.
    (def o (%cu-opts "stat" argv))
    (def fmt (Opts value o "-c"))
    (def fs? (Opts on? o "-f"))
    (def terse? (Opts on? o "-t"))
    (def ops (Opts operands o))
    ; -L follows the link; not following it is the default, since stat
    ; describes the name it was given and for a symlink that is the link.
    ; -f asks about the filesystem under the name instead.
    (def stat-of
      (fn (_ path)
        (match
          (fs? (file-statfs-full path))
          ((Opts on? o "-L") (file-stat-full path))
          (#t (file-lstat-full path)))))
    ; -c's format, else -t's line in stat's own terse order, else the block
    (def render
      (fn (_ name st)
        (def spec (if fs? %cu-stat-fs-spec %cu-stat-spec))
        (def line
          (fn (_ f) (string-append (%cu-stat-format f name st spec) "\n")))
        (match
          ((not (null? fmt)) (line fmt))
          ((if fs? terse? #f) (line "%n %i %l %t %s %S %b %f %a %c %d"))
          (terse? (line "%n %s %b %f %u %g %D %i %h %t %T %X %Y %Z %W %o"))
          (fs? (%cu-stat-fs-default name st))
          (#t (%cu-stat-default name st)))))
    (def go
      (fn (self os st)
        (if (null? os) st
          (let ((s (stat-of (first os))))
            (if (null? s)
              (do (file-write 2
                    (string-concat
                      (if fs?
                        (list "stat: cannot read file system information for '"
                              (first os) "': No such file or directory\n")
                        (list "stat: cannot stat '" (first os) "'\n"))))
                  (self (rest os) 1))
              (do (display (render (first os) s))
                  (self (rest os) st)))))))
    (if (null? ops)
      (do (file-write 2 "stat: missing operand\n") 1)
      (go ops 0))))

; --- du -----------------------------------------------------------------------

; the disk usage, in 1024-byte units (the block count the kernel
; reports is in 512s, so it halves).  Directories recurse; -s prints
; only the total, -a every file as well.
(def %cu-du-blocks
  (fn (_ st) (/ (- (%cu-stat-get st (lit blocks))
                   (% (%cu-stat-get st (lit blocks)) 2)) 2)))

(def %cu-path-join
  (fn (_ dir name)
    (if (string=? dir "/") (string-append "/" name)
      (string-append dir (string-append "/" name)))))

(def %cu-dot?
  (fn (_ n) (if (string=? n ".") #t (string=? n ".."))))

; LEVEL is how deep this path sits below the operand, and LIMIT is
; -d's ceiling on what gets PRINTED -- the walk still descends past it,
; because the totals above depend on what is below.
(def %cu-du-walk
  (fn (self path all? show-dirs? emit level limit)
    (def st (file-stat-full path))
    (if (null? st) 0
      (if (eq? (%cu-stat-get st (lit kind)) (lit dir))
        ; du SUMS rather than folding a status, so it takes the names
        ; and keeps its own loop -- the listing is the shared part.
        (let ((kids (%cu-walk-names path)))
          (def sub
            (fn (self2 ns acc)
              (if (null? ns) acc
                (self2 (rest ns)
                  (+ acc
                    (self (%cu-path-join path (first ns))
                      all? show-dirs? emit (+ level 1) limit))))))
          (let ((total (+ (%cu-du-blocks st) (sub kids 0))))
            (do (if (if show-dirs? (%cu-du-deep? level limit) #f)
                  (emit total path) ())
                total)))
        (let ((n (%cu-du-blocks st)))
          (do (if (if all? (%cu-du-deep? level limit) #f) (emit n path) ())
              n))))))

(def %cu-du-deep?
  (fn (_ level limit) (if (< limit 0) #t (<= level limit))))

; du: -s totals only, -a every file, -d N stops the printing below a
; depth, -c adds a grand total, -h and -m choose the unit (-k, the
; default here, is 1024-byte blocks), -H -L follow links, -x and -l
; are accepted and named below.
(def %cu-du-show
  (fn (_ n o)
    ; Blocks to bytes: -k is du's own unit and %ls-human's is bytes, so a 268K
    ; directory would print as a bare "268" without this scaling.
    (if (Opts on? o "-h") (%ls-human (* n 1024))
      (if (Opts on? o "-m")
        (%cu-int->str (/ (- n (% n 1024)) 1024))
        (%cu-int->str n)))))

(def %cu-du
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "du" argv))
    (def s? (Opts on? o "-s"))
    (def a? (Opts on? o "-a"))
    (def depth (let ((v (Opts value o "-d"))) (if (null? v) (- 0 1) (%cu-num-prefix v))))
    (def ops0 (Opts operands o))
    (def ops (if (null? ops0) (list ".") ops0))
    (def emit
      (fn (_ n path)
        (display
          (string-concat (list (%cu-du-show n o) "\t" path "\n")))))
    (def quiet (fn (_ n path) ()))
    (def go
      (fn (self os total)
        (if (null? os) total
          (let ((n (%cu-du-walk (first os) (if s? #f a?)
                     (not s?) (if s? quiet emit) 0 depth)))
            (do (if s? (emit n (first os)) ())
                (self (rest os) (+ total n)))))))
    (def grand (go ops 0))
    (do (if (Opts on? o "-c") (emit grand "total") ()) 0)))

; --- dd -----------------------------------------------------------------------

; the operands are KEY=VALUE, not flags; this is the one applet whose
; command line the option guard never sees.
; A key=value operand's value, or nil.
(def %cu-dd-operand
  (fn (_ argv key)
    (def klen (byte-len key))
    (def go
      (fn (self as)
        (if (null? as) ()
          (let ((a (first as)))
            (if (if (> (byte-len a) klen)
                  (if (string=? (substring a 0 klen) key)
                    (= (byte-at a klen) 61) #f)               ; =
                  #f)
              (substring a (+ klen 1) (byte-len a))
              (self (rest as)))))))
    (go argv)))

; conv=, iflag= and oflag= take a comma-separated list. Every value a caller
; may give is one this applet acts on: the rest are refused by name rather
; than accepted and ignored.
(def %cu-dd-list
  (fn (_ argv key)
    (let ((v (%cu-dd-operand argv key)))
      (if (null? v) () (%cu-split-byte v 44)))))

(def %cu-dd-has?
  (fn (self vs name)
    (if (null? vs) #f
      (if (string=? (first vs) name) #t (self (rest vs) name)))))

(def %cu-dd-conv-known
  (list "swab" "lcase" "ucase" "notrunc"))
(def %cu-dd-iflag-known
  (list "skip_bytes" "count_bytes" "fullblock"))
(def %cu-dd-oflag-known
  (list "seek_bytes" "append"))

; The first value of VS that KNOWN does not carry, or nil.
(def %cu-dd-unknown
  (fn (self vs known)
    (if (null? vs) ()
      (if (%cu-dd-has? known (first vs))
        (self (rest vs) known)
        (first vs)))))

; Swap each pair of bytes; an odd byte at the end stays where it is.
(def %cu-dd-swab
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i acc)
        (if (>= (+ i 1) end)
          (if (< i end) (string-append acc (substring s i end)) acc)
          (self (+ i 2)
            (string-append acc
              (string-append (substring s (+ i 1) (+ i 2))
                (substring s i (+ i 1))))))))
    (go 0 "")))

(def %cu-dd-convert
  (fn (_ s conv)
    (def a (if (%cu-dd-has? conv "swab") (%cu-dd-swab s) s))
    (def b (if (%cu-dd-has? conv "lcase") (Str8 downcase a) a))
    (if (%cu-dd-has? conv "ucase") (Str8 upcase b) b)))

; Blocks of SIZE in N bytes, as "WHOLE+PARTIAL".
(def %cu-dd-records
  (fn (_ n size)
    (string-append (%cu-int->str (/ (- n (% n size)) size))
      (string-append "+" (if (= (% n size) 0) "0" "1")))))

(def %cu-dd
  (fn (_ argv stdin-thunk)
    (def in (%cu-dd-operand argv "if"))
    (def out (%cu-dd-operand argv "of"))
    (def bs (%cu-dd-operand argv "bs"))
    ; bs= sets both sides; ibs= and obs= set one each and win over it.
    (def ibs (let ((v (%cu-dd-operand argv "ibs")))
               (if (null? v) (if (null? bs) 512 (%cu-num-prefix bs))
                 (%cu-num-prefix v))))
    (def obs (let ((v (%cu-dd-operand argv "obs")))
               (if (null? v) (if (null? bs) 512 (%cu-num-prefix bs))
                 (%cu-num-prefix v))))
    (def conv (%cu-dd-list argv "conv"))
    (def iflag (%cu-dd-list argv "iflag"))
    (def oflag (%cu-dd-list argv "oflag"))
    (def bad
      (let ((c (%cu-dd-unknown conv %cu-dd-conv-known)))
        (if (not (null? c)) (pair "conv" c)
          (let ((i (%cu-dd-unknown iflag %cu-dd-iflag-known)))
            (if (not (null? i)) (pair "iflag" i)
              (let ((o (%cu-dd-unknown oflag %cu-dd-oflag-known)))
                (if (null? o) () (pair "oflag" o))))))))
    (if (not (null? bad))
      (do (file-write 2
            (string-concat
              (list "dd: unknown " (first bad) " value: " (rest bad) "\n")))
          1)
      (do
        (def count (let ((v (%cu-dd-operand argv "count")))
                     (if (null? v) (- 0 1) (%cu-num-prefix v))))
        (def skip (let ((v (%cu-dd-operand argv "skip")))
                    (if (null? v) 0 (%cu-num-prefix v))))
        (def seek (let ((v (%cu-dd-operand argv "seek")))
                    (if (null? v) 0 (%cu-num-prefix v))))
        (def quiet? (let ((v (%cu-dd-operand argv "status")))
                      (if (null? v) #f (string=? v "none"))))
        ; skip and count are blocks unless a flag says bytes; seek likewise.
        (def from
          (* skip (if (%cu-dd-has? iflag "skip_bytes") 1 ibs)))
        (def at
          (* seek (if (%cu-dd-has? oflag "seek_bytes") 1 obs)))
        (def source (if (null? in) (stdin-thunk) (file-read-all in)))
        (def avail (byte-len source))
        (def want
          (if (< count 0) (- avail from)
            (* count (if (%cu-dd-has? iflag "count_bytes") 1 ibs))))
        (def stop (let ((e (+ from want))) (if (> e avail) avail e)))
        (def raw (if (>= from avail) "" (substring source from stop)))
        (def chunk (%cu-dd-convert raw conv))
        (def n (byte-len chunk))
        (do
          (if (null? out)
            (display chunk)
            (let ((fd (if (%cu-dd-has? oflag "append")
                        (file-open-append out)
                        (file-open-update out))))
              (do (if (> at 0) (file-seek fd at) ())
                  (file-write fd chunk)
                  ; conv=notrunc leaves whatever followed the write in
                  ; place, and appending says the same thing: truncating
                  ; to at+n after an append cuts off what was just written.
                  (if (if (%cu-dd-has? conv "notrunc") #t
                        (%cu-dd-has? oflag "append")) ()
                    (file-truncate fd (+ at n)))
                  (file-close fd))))
          ; records in are counted in ibs, records out in obs; they differ
          ; whenever the two block sizes do.
          (if quiet? ()
            (file-write 2
              (string-concat
                (list (%cu-dd-records n ibs) " records in\n"
                      (%cu-dd-records n obs) " records out\n"
                      (%cu-int->str n) " bytes copied\n"))))
          0)))))


; --- truncate, unlink, shred --------------------------------------------------

(def %cu-truncate
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "truncate" argv))
    ; -s TAKES A VALUE, and a value flag is not among the record's
    ; standalone flags -- its presence IS its value being there.
    (def size-arg (Opts value o "-s"))
    ; -c truncates only what is already there: a missing file is passed
    ; over rather than created, and that is not an error.
    (def no-create? (Opts on? o "-c"))
    (if (null? size-arg)
      (do (file-write 2 "truncate: need -s SIZE\n") 1)
      (let ((size (%cu-num-prefix size-arg)))
        ; The operands come from the parse, not from a fixed position:
        ; with -c in the line the old (rest (rest argv)) ate a file.
        (def ops (Opts operands o))
        (def go
          (fn (self os)
            (match
              ((null? os) 0)
              ((if no-create? (not (file-exists? (first os))) #f)
                (self (rest os)))
              (#t (let ((fd (file-open-update (first os))))
                    (do (file-truncate fd size)
                        (file-close fd)
                        (self (rest os))))))))
        (go ops)))))

; File unlink RAISES on a missing path rather than answering a
; negative, so the absence is tested before the door is opened.
(def %cu-unlink
  (fn (_ argv stdin-thunk)
    (if (null? argv)
      (do (file-write 2 "unlink: missing operand\n") 1)
      (if (not (file-exists? (first argv)))
        (do (file-write 2
              (string-concat
                (list "unlink: cannot unlink '" (first argv) "'\n")))
            1)
        (do (file-unlink (first argv)) 0)))))

; shred: N passes of random bytes over the file's length, then -u
; removes it.  The filler avoids NUL -- a byte a C string cannot hold
; (the same limit sha256sum records).
(def %cu-shred-filler
  (fn (_ r n)
    (def go
      (fn (self k acc)
        (if (<= k 0) (string-concat acc)
          (self (- k 1) (pair (%cu-b->s (+ 1 (rng-int r 255))) acc)))))
    (go n ())))

(def %cu-shred
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "shred" argv))
    (def n-arg (Opts value o "-n"))
    (def passes (if (null? n-arg) 3 (%cu-num-prefix n-arg)))
    (def u? (Opts on? o "-u"))
    ; -f takes a file the mode denies: 0600 first, then the passes.
    (def f? (Opts on? o "-f"))
    ; -z adds a last pass of zeros, so what is left does not read as the
    ; random bytes the earlier passes wrote.  The zeros are written with
    ; an explicit count (cu/prims.x), which overwrites the blocks rather
    ; than freeing them the way a truncate would.
    (def z? (Opts on? o "-z"))
    (def ops (Opts operands o))
    (def r (rng-make (date-now-unix)))
    (def one
      (fn (_ path)
        (do
          (if f? (guard (_ ()) (file-chmod path 384)) ())   ; 0600
          (let ((st (file-stat-full path)))
            (if (null? st) 1
              (let ((size (%cu-stat-get st (lit size))))
                (def pass
                  (fn (self k)
                    (if (<= k 0) ()
                      (do (file-write-all path (%cu-shred-filler r size))
                          (self (- k 1))))))
                (do (pass passes)
                    (if z?
                      (let ((fd (file-open-write path)))
                        (do (file-write-nuls fd size) (file-close fd)))
                      ())
                    (if u? (file-unlink path) ())
                    0)))))))
    (def go
      (fn (self os st)
        (if (null? os) st
          (let ((r2 (one (first os))))
            (self (rest os) (if (> r2 st) r2 st))))))
    (if (null? ops)
      (do (file-write 2 "shred: missing operand\n") 1)
      (go ops 0))))

; --- timeout, usleep, tty, nohup ----------------------------------------------

; timeout(1) without an alarm door: the parent forks the command AND a
; watchdog that sleeps and then kills it.  Whichever finishes first,
; the parent reaps both; a killed command reports 124, as timeout does.
;
; The watchdog's own exit says whether it FIRED, because the command's
; status cannot say so on its own: a command that ignores the signal and
; then exits 0 has still timed out, and timeout reports 124 for it.  A
; command killed by a signal keeps 128+N instead -- which is how -k's
; KILL comes back as 137 rather than 124.
(def %cu-timeout
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "timeout" argv))
    (def fired 7)                     ; the watchdog's "I signalled" status
    (def sig-arg (Opts value o "-s"))
    (def sig (if (null? sig-arg) cu-sigterm (%cu-num-prefix sig-arg)))
    ; -k DURATION: if the command outlives the first signal by DURATION,
    ; follow it with KILL, which cannot be caught.  The watcher sends both,
    ; so the parent still learns the command's own status from one wait.
    (def kill-arg (Opts value o "-k"))
    (def rest1 (Opts operands o))
    (if (null? (rest rest1))
      (do (file-write 2 "timeout: need SECONDS COMMAND\n") 1)
      (let ((secs (%cu-num-prefix (first rest1))))
        (def cmd (rest rest1))
        (def pid (sys-fork))
        (if (= pid 0)
          (do (cu-stdin-to-command!) (sys-exec (first cmd) (rest cmd)) (sys-exit 127))
          (let ((watch (sys-fork)))
            (if (= watch 0)
              (do (sys-sleep secs)
                  (sys-kill pid sig)
                  (if (null? kill-arg) ()
                    (do (sys-sleep (%cu-num-prefix kill-arg))
                        (sys-kill pid cu-sigkill)))
                  (sys-exit fired))
              (let ((st (sys-wait pid)))
                (do (sys-kill watch cu-sigterm)
                    (let ((wst (sys-wait watch)))
                      (match
                        ; Killed by our signal: 124, the timeout status --
                        ; except KILL, which timeout does not mask and
                        ; which therefore keeps 137 (measured against GNU
                        ; across TERM HUP INT QUIT USR1 KILL).
                        ((if (= st (+ 128 sig)) (not (= sig cu-sigkill)) #f) 124)
                        ; Signal ignored and the command exited on its own:
                        ; it still timed out, so 124 rather than its status.
                        ((if (= wst fired) (< st 128) #f) 124)
                        (#t st))))))))))))

(def %cu-usleep
  (fn (_ argv stdin-thunk)
    (do (sys-usleep (if (null? argv) 0 (%cu-num-prefix (first argv)))) 0)))

; tty(1) names the terminal; there is no ttyname door, so this answers
; the QUESTION isatty asks and says so plainly.
; -s answers with the status alone.  The name is not discoverable through
; the doors this bundle has -- ttyname(3) is not among them -- so the
; reporting form names the controlling terminal generically.
(def %cu-tty
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "tty" argv))
    (def quiet? (Opts on? o "-s"))
    (def say (fn (_ s) (if quiet? () (display s))))
    (if (sys-isatty 0)
      (do (say "/dev/tty\n") 0)
      (do (say "not a tty\n") 1))))

(def %cu-nohup
  (fn (_ argv stdin-thunk)
    (if (null? argv)
      (do (file-write 2 "nohup: missing operand\n") 1)
      (do (sys-signal cu-sighup cu-sig-ign)
          (cu-stdin-to-command!)
          (sys-exec (first argv) (rest argv))
          127))))

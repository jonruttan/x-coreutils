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
  (fn (_ mode) (%cu-pad-zero (%cu-mode-octal mode) 4)))

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

; the name stat shows for an owner or a group, or UNKNOWN where the system has
; none, as stat says it
(def %cu-stat-user
  (fn (_ uid) (let ((n (sys-user-name uid))) (if (null? n) "UNKNOWN" n))))

(def %cu-stat-group
  (fn (_ gid) (let ((n (sys-group-name gid))) (if (null? n) "UNKNOWN" n))))

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
      ((= c 85)  (%cu-stat-user (%cu-stat-get st (lit uid))))    ; U
      ((= c 103) (num (lit gid)))               ; g
      ((= c 71)  (%cu-stat-group (%cu-stat-get st (lit gid))))   ; G
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
; the inode padded to ten, a device's own type after its link count, and
; the owner and group as their ids in five columns and names in eight.
(def %cu-stat-default
  (fn (_ name st)
    (def kind (%cu-stat-get st (lit kind)))
    (def mode (%cu-stat-get st (lit mode)))
    (def dev (%cu-stat-get st (lit dev)))
    (def rdev (%cu-stat-get st (lit rdev)))
    (def uid (%cu-stat-get st (lit uid)))
    (def gid (%cu-stat-get st (lit gid)))
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
            (%cu-pad-left (%cu-int->str uid) 5) "/"
            (%cu-pad-left (%cu-stat-user uid) 8) ")   Gid: ("
            (%cu-pad-left (%cu-int->str gid) 5) "/"
            (%cu-pad-left (%cu-stat-group gid) 8) ")\n"))))

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

; du: -a prints every file as well as each directory, -d N stops the printing
; below a depth and -s is -d 0, -c adds a grand total, and -h and -m choose the
; unit (-k, the default, is 1024-byte blocks).  A file named on the command
; line is printed whatever -a says.
;
; What du does with a symlink is the last of -P, -H and -L: -P, the default,
; counts the link itself; -H follows one named on the command line; -L
; follows every one.  -x counts nothing on a device other than the operand's,
; and -l counts a file under each of its names.
;
; Without -l an inode counts ONCE.  Where there are several operands, or -L,
; that holds for every inode; otherwise for a file with several names -- and
; under -L it is what keeps the walk out of a directory it is already inside,
; reached again through a link, since that directory is counted already.
;
; A run's settings ride the walk as `way`, read once: (links . none|args|all),
; (count-all . -l), (xdev . -x), (hash-all . as above), (all . -a),
; (limit . -d), (emit . the printer), and two cells -- (seen . the (DEV . INO)
; pairs counted so far) and (bad . the status).
(def %cu-du-way
  (fn (_ o many?)
    (let ((links (%cu-du-links o)) (s? (Opts on? o "-s")))
      (list (pair (lit links) links)
            (pair (lit count-all) (Opts on? o "-l"))
            (pair (lit xdev) (Opts on? o "-x"))
            (pair (lit hash-all) (if many? #t (eq? links (lit all))))
            (pair (lit all) (if s? #f (Opts on? o "-a")))
            (pair (lit limit) (if s? 0 (%cu-du-depth o)))
            (pair (lit emit)
              (fn (_ n path)
                (display
                  (string-concat (list (%cu-du-show n o) "\t" path "\n")))))
            (pair (lit seen) (list ()))
            (pair (lit bad) (list 0))))))

(def %cu-du-at (fn (_ way key) (rest (Assoc entry key way))))

(def %cu-du-links
  (fn (_ o)
    (let ((v (%cu-last-given o (list "-H" "-L" "-P"))))
      (if (null? v) (lit none)
        (match
          ((string=? v "-H") (lit args))
          ((string=? v "-L") (lit all))
          (#t (lit none)))))))

(def %cu-du-depth
  (fn (_ o)
    (let ((v (Opts value o "-d"))) (if (null? v) (- 0 1) (%cu-num-prefix v)))))

(def %cu-du-deep?
  (fn (_ level limit) (if (< limit 0) #t (<= level limit))))

; a complaint, which also leaves the run's status at 1
(def %cu-du-bad!
  (fn (_ way line)
    (do (file-write 2 line) (set-first! (%cu-du-at way (lit bad)) 1))))

; The stat a path is walked by: what a link points at where -H or -L says so,
; the link's own otherwise.  A path that cannot be read is complained about and
; answers nil -- with the reason, but for a link pointing nowhere, where du
; names the path alone.
(def %cu-du-read
  (fn (_ way path top?)
    (let ((through? (match
                      ((eq? (%cu-du-at way (lit links)) (lit all)) #t)
                      ((eq? (%cu-du-at way (lit links)) (lit args)) top?)
                      (#t #f))))
      (let ((st (file-or-err
                  (fn (_) (if through? (file-stat-wide path)
                            (file-lstat-wide path))))))
        (if (not (Err err? st)) st
          (do (%cu-du-bad! way
                (string-concat
                  (if (eq? (file-lstat-kind path) (lit link))
                    (list "du: cannot access '" path "'\n")
                    (list "du: cannot access '" path "': " (file-err-text st)
                          "\n"))))
              ()))))))

; Whether a path counts for nothing: it is on another device under -x, or its
; inode was counted already.  A path that counts is remembered from here on.
(def %cu-du-skip?
  (fn (_ way st top? root)
    (match
      ((if (%cu-du-at way (lit xdev))
         (if top? #f (not (= (%cu-stat-get st (lit dev)) root)))
         #f)
        #t)
      ((%cu-du-at way (lit count-all)) #f)
      ((%cu-du-once? way st) (%cu-du-counted! way st))
      (#t #f))))

; whether an inode counts once: every one under hash-all, else a file -- not a
; directory -- with more than one name
(def %cu-du-once?
  (fn (_ way st)
    (if (%cu-du-at way (lit hash-all)) #t
      (if (eq? (%cu-stat-get st (lit kind)) (lit dir)) #f
        (> (%cu-stat-get st (lit nlink)) 1)))))

; whether ST's inode was counted already; it is counted from now on either way
(def %cu-du-counted!
  (fn (_ way st)
    (let ((cell (%cu-du-at way (lit seen)))
          (id (pair (%cu-stat-get st (lit dev)) (%cu-stat-get st (lit ino)))))
      (if (%cu-du-member? id (first cell)) #t
        (do (set-first! cell (pair id (first cell))) #f)))))

(def %cu-du-member?
  (fn (self id ids)
    (if (null? ids) #f
      (if (if (= (first id) (first (first ids)))
            (= (rest id) (rest (first ids))) #f)
        #t
        (self id (rest ids))))))

; One path's usage, printed as the run asks and answered as a block count.
; LEVEL is how deep it sits below the operand -- -d's ceiling is on what is
; PRINTED, and the walk still goes past it, because the totals above depend on
; what is below.  TOP? says the path was named on the command line, and ROOT is
; the device its operand stands on.
(def %cu-du-walk
  (fn (_ way path level top? root)
    (let ((st (%cu-du-read way path top?)))
      (if (null? st) 0
        (let ((here (if top? (%cu-stat-get st (lit dev)) root)))
          (match
            ((%cu-du-skip? way st top? here) 0)
            ((eq? (%cu-stat-get st (lit kind)) (lit dir))
              (%cu-du-dir way path level st here))
            (#t
              (let ((n (%cu-du-blocks st)))
                (do (if (if top? #t (%cu-du-at way (lit all)))
                      (%cu-du-emit way level n path) ())
                    n)))))))))

; a directory: its entries first, then its own line; one whose entries cannot
; be read is complained about and counted for its own blocks alone
(def %cu-du-dir
  (fn (_ way path level st root)
    (let ((names (file-or-err (fn (_) (%cu-walk-names path)))))
      (let ((total
              (+ (%cu-du-blocks st)
                 (if (Err err? names)
                   (do (%cu-du-bad! way
                         (string-concat
                           (list "du: cannot read directory '" path "': "
                                 (file-err-text names) "\n")))
                       0)
                   (%cu-du-sum way path names (+ level 1) root 0)))))
        (do (%cu-du-emit way level total path) total)))))

; the entries' usage, summed as it goes: a directory can hold more entries
; than a call stack holds frames
(def %cu-du-sum
  (fn (self way dir names level root acc)
    (if (null? names) acc
      (self way dir (rest names) level root
        (+ acc
          (%cu-du-walk way (%cu-path-join dir (first names)) level #f root))))))

(def %cu-du-emit
  (fn (_ way level n path)
    (if (%cu-du-deep? level (%cu-du-at way (lit limit)))
      ((%cu-du-at way (lit emit)) n path)
      ())))

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
    (def ops0 (Opts operands o))
    (def ops (if (null? ops0) (list ".") ops0))
    (def way (%cu-du-way o (> (length ops) 1)))
    (def grand (%cu-du-operands way ops 0))
    (do (if (Opts on? o "-c") ((%cu-du-at way (lit emit)) grand "total") ())
        (first (%cu-du-at way (lit bad))))))

(def %cu-du-operands
  (fn (self way ops total)
    (if (null? ops) total
      (self way (rest ops)
        (+ total (%cu-du-walk way (first ops) 0 #t 0))))))

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
      ; the input is read before anything else, as dd opens it first; one
      ; it cannot open is said, and nothing is written
      (let ((source (if (null? in) (stdin-thunk)
                      (file-or-err (fn (_) (file-read-all in))))))
        (if (Err err? source) (%cu-dd-failed in source)
          (do
            (def count (let ((v (%cu-dd-operand argv "count")))
                         (if (null? v) (- 0 1) (%cu-num-prefix v))))
            (def skip (let ((v (%cu-dd-operand argv "skip")))
                        (if (null? v) 0 (%cu-num-prefix v))))
            (def seek (let ((v (%cu-dd-operand argv "seek")))
                        (if (null? v) 0 (%cu-num-prefix v))))
            (def quiet? (let ((v (%cu-dd-operand argv "status")))
                          (if (null? v) #f (string=? v "none"))))
            ; skip and count are blocks unless a flag says bytes; seek
            ; likewise.
            (def from
              (* skip (if (%cu-dd-has? iflag "skip_bytes") 1 ibs)))
            (def at
              (* seek (if (%cu-dd-has? oflag "seek_bytes") 1 obs)))
            (def avail (byte-len source))
            (def want
              (if (< count 0) (- avail from)
                (* count (if (%cu-dd-has? iflag "count_bytes") 1 ibs))))
            (def stop (let ((e (+ from want))) (if (> e avail) avail e)))
            (def raw (if (>= from avail) "" (substring source from stop)))
            (def chunk (%cu-dd-convert raw conv))
            (def n (byte-len chunk))
            (let ((st (if (null? out) (do (display chunk) 0)
                        (%cu-dd-write out chunk at conv oflag))))
              ; records in are counted in ibs, records out in obs; they
              ; differ whenever the two block sizes do.  A write that
              ; failed made no records.
              (do (if (if quiet? #t (> st 0)) ()
                    (file-write 2
                      (string-concat
                        (list (%cu-dd-records n ibs) " records in\n"
                              (%cu-dd-records n obs) " records out\n"
                              (%cu-int->str n) " bytes copied\n"))))
                  st))))))))

; CHUNK written to OUT at AT: opened to append under oflag=append, and cut
; where the write ended -- unless conv=notrunc leaves whatever followed it in
; place, as appending does too, since truncating to AT plus the chunk after
; an append cuts off what was just written.  An OUT dd cannot open is said.
(def %cu-dd-write
  (fn (_ out chunk at conv oflag)
    (let ((fd (file-open-or-err
                (if (%cu-dd-has? oflag "append") file-open-append
                  file-open-update)
                out)))
      (if (Err err? fd) (%cu-dd-failed out fd)
        (do (if (> at 0) (file-seek fd at) ())
            (file-write fd chunk)
            (if (if (%cu-dd-has? conv "notrunc") #t
                  (%cu-dd-has? oflag "append")) ()
              (file-truncate fd (+ at (byte-len chunk))))
            (file-close fd)
            0)))))

(def %cu-dd-failed
  (fn (_ path r)
    (do (file-write 2
          (string-concat
            (list "dd: failed to open '" path "': " (file-err-text r) "\n")))
        1)))


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
        ; a file truncate cannot open is said, and the rest are still cut
        (def go
          (fn (self os st)
            (match
              ((null? os) st)
              ((if no-create? (not (file-exists? (first os))) #f)
                (self (rest os) st))
              (#t (let ((fd (file-open-or-err file-open-update (first os))))
                    (if (Err err? fd)
                      (do (file-write 2
                            (string-concat
                              (list "truncate: cannot open '" (first os)
                                    "' for writing: " (file-err-text fd) "\n")))
                          (self (rest os) 1))
                      (do (file-truncate fd size)
                          (file-close fd)
                          (self (rest os) st))))))))
        (go ops 0)))))

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

; shred: N passes of random bytes over the file's blocks, then -u removes it.
; The bytes go out through the counted write (cu/prims.x), so every one of the
; 256 is written, NUL included.

; SIZE rounded up to whole BLKSIZE blocks, which is the length shred covers:
; what is left of a block would still hold the bytes that were there.  An
; empty file has no block to cover and stays empty.
(def %cu-shred-blocks
  (fn (_ size blksize)
    (if (if (> size 0) (> blksize 0) #f)
      (let ((over (% size blksize)))
        (if (= over 0) size (+ size (- blksize over))))
      size)))


; the length the passes cover, from what stat says of the file now
(def %cu-shred-size
  (fn (_ path)
    (let ((st (file-stat-full path)))
      (if (null? st) 0
        (%cu-shred-blocks (%cu-stat-get st (lit size))
          (%cu-stat-get st (lit blksize)))))))

; K passes of random bytes over SIZE, each from the start
(def %cu-shred-passes
  (fn (self fd r size k)
    (if (<= k 0) ()
      (do (file-seek fd 0)
          (file-write-random fd r size)
          (self fd r size (- k 1))))))

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
    ; One file: opened to write and nothing more -- a truncate would free the
    ; very blocks the passes are there to write over -- then each pass from
    ; the start of it.  One shred cannot open is said, and fails.
    (def one
      (fn (_ path)
        (do
          (if f? (guard (_ ()) (file-chmod path 384)) ())   ; 0600
          (let ((fd (file-open-or-err file-open-wronly path)))
            (if (Err err? fd)
              (do (file-write 2
                    (string-concat
                      (list "shred: " path ": failed to open for writing: "
                            (file-err-text fd) "\n")))
                  1)
              (let ((size (%cu-shred-size path)))
                (do (%cu-shred-passes fd r size passes)
                    (if z? (do (file-seek fd 0) (file-write-nuls fd size)) ())
                    (file-close fd)
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

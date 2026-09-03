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

; does argv carry this exact flag anywhere before its operands?
(def %cu-has-flag?
  (fn (_ argv flag)
    (def go (fn (self as)
              (if (null? as) #f
                (if (string=? (first as) flag) #t (self (rest as))))))
    (go argv)))

(def %cu-stat-get
  (fn (_ st key)
    (let ((e (Assoc entry key st)))
      (if (null? e) 0 (rest e)))))

; --- the mode, spelled two ways -----------------------------------------------

(def %cu-mode-octal
  (fn (_ mode) (%cu-oct->str (bit-and mode 4095))))

(def %cu-kind-letter
  (fn (_ kind)
    (if (eq? kind (lit dir)) "d"
      (if (eq? kind (lit link)) "l"
        (if (eq? kind (lit char)) "c"
          (if (eq? kind (lit block)) "b"
            (if (eq? kind (lit fifo)) "p"
              (if (eq? kind (lit socket)) "s" "-"))))))))

(def %cu-kind-word
  (fn (_ kind)
    (if (eq? kind (lit dir)) "directory"
      (if (eq? kind (lit link)) "symbolic link"
        (if (eq? kind (lit char)) "character special file"
          (if (eq? kind (lit block)) "block special file"
            (if (eq? kind (lit fifo)) "fifo"
              (if (eq? kind (lit socket)) "socket" "regular file"))))))))

; rwx for one octal digit; the sticky and setid bits are not spelled
(def %cu-rwx
  (fn (_ d)
    (string-append (if (= (bit-and d 4) 0) "-" "r")
      (string-append (if (= (bit-and d 2) 0) "-" "w")
        (if (= (bit-and d 1) 0) "-" "x")))))

(def %cu-perm-string
  (fn (_ kind mode)
    (string-append (%cu-kind-letter kind)
      (string-append (%cu-rwx (bit-and (bit-shr mode 6) 7))
        (string-append (%cu-rwx (bit-and (bit-shr mode 3) 7))
          (%cu-rwx (bit-and mode 7)))))))

; --- stat ---------------------------------------------------------------------

; -c FMT: the GNU specifiers busybox carries.  Anything else is copied
; through, so a format is never silently eaten.
(def %cu-stat-spec
  (fn (_ c name st)
    (def kind (%cu-stat-get st (lit kind)))
    (def mode (%cu-stat-get st (lit mode)))
    (if (= c 110) name                                       ; n
      (if (= c 115) (%cu-int->str (%cu-stat-get st (lit size)))    ; s
        (if (= c 98) (%cu-int->str (%cu-stat-get st (lit blocks))) ; b
          (if (= c 66) "512"                                       ; B
            (if (= c 102) (%cu-hexs mode)                          ; f
              (if (= c 97) (%cu-mode-octal mode)                   ; a
                (if (= c 65) (%cu-perm-string kind mode)           ; A
                  (if (= c 117) (%cu-int->str (%cu-stat-get st (lit uid)))   ; u
                    (if (= c 103) (%cu-int->str (%cu-stat-get st (lit gid))) ; g
                      (if (= c 104) (%cu-int->str (%cu-stat-get st (lit nlink))) ; h
                        (if (= c 105) (%cu-int->str (%cu-stat-get st (lit ino)))  ; i
                          (if (= c 70) (%cu-kind-word kind)        ; F
                            (if (= c 88) (%cu-int->str (%cu-stat-get st (lit atime)))  ; X
                              (if (= c 89) (%cu-int->str (%cu-stat-get st (lit mtime))) ; Y
                                (if (= c 90) (%cu-int->str (%cu-stat-get st (lit ctime))) ; Z
                                  (if (= c 111) (%cu-int->str (%cu-stat-get st (lit blksize))) ; o
                                    (string-append "%" (%cu-b->s c))))))))))))))))))))

(def %cu-stat-format
  (fn (_ fmt name st)
    (def end (byte-len fmt))
    (def go
      (fn (self i acc)
        (if (>= i end) (string-concat (reverse acc))
          (let ((b (byte-at fmt i)))
            (if (if (= b 37) (< (+ i 1) end) #f)              ; %
              (self (+ i 2)
                (pair (%cu-stat-spec (byte-at fmt (+ i 1)) name st) acc))
              (self (+ i 1) (pair (%cu-b->s b) acc)))))))
    (go 0 ())))

; the default block.  The user and group are NUMERIC: there is no
; passwd door, so the name column real stat(1) prints is not available.
(def %cu-stat-default
  (fn (_ name st)
    (def kind (%cu-stat-get st (lit kind)))
    (def mode (%cu-stat-get st (lit mode)))
    (string-concat
      (list "  File: " name "\n"
            "  Size: " (%cu-int->str (%cu-stat-get st (lit size)))
            "\tBlocks: " (%cu-int->str (%cu-stat-get st (lit blocks)))
            "\tIO Block: " (%cu-int->str (%cu-stat-get st (lit blksize)))
            "\t" (%cu-kind-word kind) "\n"
            "Device: -\tInode: " (%cu-int->str (%cu-stat-get st (lit ino)))
            "\tLinks: " (%cu-int->str (%cu-stat-get st (lit nlink))) "\n"
            "Access: (" (%cu-mode-octal mode) "/"
            (%cu-perm-string kind mode) ")  Uid: ("
            (%cu-int->str (%cu-stat-get st (lit uid))) ")   Gid: ("
            (%cu-int->str (%cu-stat-get st (lit gid))) ")\n"))))

(def %cu-stat
  (fn (_ argv stdin-thunk)
    (def c? (if (pair? argv) (string=? (first argv) "-c") #f))
    (def fmt (if c? (first (rest argv)) ()))
    (def ops (if c? (rest (rest argv)) argv))
    (def go
      (fn (self os st)
        (if (null? os) st
          (let ((s (file-stat-full (first os))))
            (if (null? s)
              (do (file-write 2
                    (string-concat
                      (list "stat: cannot stat '" (first os) "'\n")))
                  (self (rest os) 1))
              (do (display
                    (if c?
                      (string-append (%cu-stat-format fmt (first os) s) "\n")
                      (%cu-stat-default (first os) s)))
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

(def %cu-du-walk
  (fn (self path all? show-dirs? emit)
    (def st (file-stat-full path))
    (if (null? st) 0
      (if (eq? (%cu-stat-get st (lit kind)) (lit dir))
        (let ((kids (filter (fn (_ n) (not (%cu-dot? n)))
                      (file-list-dir path))))
          (def sub
            (fn (self2 ns acc)
              (if (null? ns) acc
                (self2 (rest ns)
                  (+ acc
                    (self (%cu-path-join path (first ns))
                      all? show-dirs? emit))))))
          (let ((total (+ (%cu-du-blocks st) (sub kids 0))))
            (do (if show-dirs? (emit total path) ()) total)))
        (let ((n (%cu-du-blocks st)))
          (do (if all? (emit n path) ()) n))))))

(def %cu-du
  (fn (_ argv stdin-thunk)
    (def s? (%cu-has-flag? argv "-s"))
    (def a? (%cu-has-flag? argv "-a"))
    (def ops0 (filter (fn (_ x) (not (%cu-option-token? x))) argv))
    (def ops (if (null? ops0) (list ".") ops0))
    (def emit
      (fn (_ n path)
        (display
          (string-append (%cu-int->str n)
            (string-append "\t" (string-append path "\n"))))))
    (def quiet (fn (_ n path) ()))
    (def go
      (fn (self os)
        (if (null? os) 0
          (let ((total (%cu-du-walk (first os) (if s? #f a?)
                         (not s?) (if s? quiet emit))))
            (do (if s? (emit total (first os)) ())
                (self (rest os)))))))
    (go ops)))

; --- dd -----------------------------------------------------------------------

; the operands are KEY=VALUE, not flags; this is the one applet whose
; command line the option guard never sees.
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

(def %cu-dd
  (fn (_ argv stdin-thunk)
    (def in (%cu-dd-operand argv "if"))
    (def out (%cu-dd-operand argv "of"))
    (def bs (let ((v (%cu-dd-operand argv "bs")))
              (if (null? v) 512 (%cu-num-prefix v))))
    (def count (let ((v (%cu-dd-operand argv "count")))
                 (if (null? v) (- 0 1) (%cu-num-prefix v))))
    (def skip (let ((v (%cu-dd-operand argv "skip")))
                (if (null? v) 0 (%cu-num-prefix v))))
    (def seek (let ((v (%cu-dd-operand argv "seek")))
                (if (null? v) 0 (%cu-num-prefix v))))
    (def quiet? (let ((v (%cu-dd-operand argv "status")))
                  (if (null? v) #f (string=? v "none"))))
    (def source (if (null? in) (stdin-thunk) (file-read-all in)))
    (def from (* skip bs))
    (def avail (byte-len source))
    (def want (if (< count 0) (- avail from) (* count bs)))
    (def stop (let ((e (+ from want))) (if (> e avail) avail e)))
    (def chunk (if (>= from avail) "" (substring source from stop)))
    (def n (byte-len chunk))
    (def recs (/ (- n (% n bs)) bs))
    (def partial (if (= (% n bs) 0) 0 1))
    (do
      (if (null? out)
        (display chunk)
        (let ((fd (file-open-update out)))
          (do (if (> seek 0) (file-seek fd (* seek bs)) ())
              (file-write fd chunk)
              (file-truncate fd (+ (* seek bs) n))
              (file-close fd))))
      (if quiet? ()
        (file-write 2
          (string-concat
            (list (%cu-int->str recs) "+" (%cu-int->str partial)
                  " records in\n"
                  (%cu-int->str recs) "+" (%cu-int->str partial)
                  " records out\n"
                  (%cu-int->str n) " bytes copied\n"))))
      0)))

; --- truncate, unlink, shred --------------------------------------------------

(def %cu-truncate
  (fn (_ argv stdin-thunk)
    (if (not (%cu-has-flag? argv "-s"))
      (do (file-write 2 "truncate: need -s SIZE\n") 1)
      (let ((size (%cu-num-prefix (first (rest argv)))))
        (def ops (rest (rest argv)))
        (def go
          (fn (self os)
            (if (null? os) 0
              (let ((fd (file-open-update (first os))))
                (do (file-truncate fd size)
                    (file-close fd)
                    (self (rest os)))))))
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
    (def n? (%cu-has-flag? argv "-n"))
    (def passes (if n? (%cu-num-prefix (first (rest argv))) 3))
    (def u? (%cu-has-flag? argv "-u"))
    (def ops (filter (fn (_ x) (not (%cu-option-token? x)))
               (if n? (rest (rest argv)) argv)))
    (def r (rng-make (date-now-unix)))
    (def one
      (fn (_ path)
        (let ((st (file-stat-full path)))
          (if (null? st) 1
            (let ((size (%cu-stat-get st (lit size))))
              (def pass
                (fn (self k)
                  (if (<= k 0) ()
                    (do (file-write-all path (%cu-shred-filler r size))
                        (self (- k 1))))))
              (do (pass passes)
                  (if u? (file-unlink path) ())
                  0))))))
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
(def %cu-timeout
  (fn (_ argv stdin-thunk)
    (def s? (%cu-has-flag? argv "-s"))
    (def sig (if s? (%cu-num-prefix (first (rest argv))) cu-sigterm))
    (def rest1 (if s? (rest (rest argv)) argv))
    (if (null? (rest rest1))
      (do (file-write 2 "timeout: need SECONDS COMMAND\n") 1)
      (let ((secs (%cu-num-prefix (first rest1))))
        (def cmd (rest rest1))
        (def pid (sys-fork))
        (if (= pid 0)
          (do (sys-exec (first cmd) (rest cmd)) (sys-exit 127))
          (let ((watch (sys-fork)))
            (if (= watch 0)
              (do (sys-sleep secs) (sys-kill pid sig) (sys-exit 0))
              (let ((st (sys-wait pid)))
                (do (sys-kill watch cu-sigterm)
                    (sys-wait watch)
                    (if (= st (+ 128 sig)) 124 st))))))))))

(def %cu-usleep
  (fn (_ argv stdin-thunk)
    (do (sys-usleep (if (null? argv) 0 (%cu-num-prefix (first argv)))) 0)))

; tty(1) names the terminal; there is no ttyname door, so this answers
; the QUESTION isatty asks and says so plainly.
(def %cu-tty
  (fn (_ argv stdin-thunk)
    (if (sys-isatty 0)
      (do (display "/dev/tty\n") 0)
      (do (display "not a tty\n") 1))))

(def %cu-nohup
  (fn (_ argv stdin-thunk)
    (if (null? argv)
      (do (file-write 2 "nohup: missing operand\n") 1)
      (do (sys-signal cu-sighup cu-sig-ign)
          (sys-exec (first argv) (rest argv))
          127))))

; --- [[ -----------------------------------------------------------------------

(def %cu-dbracket
  (fn (_ argv stdin-thunk)
    (if (null? argv) 2
      (if (not (string=? (%cu-last argv) "]]"))
        (do (file-write 2 "[[: missing ]]\n") 2)
        (%cu-test-eval (%cu-drop-last argv))))))

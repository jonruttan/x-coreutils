; # x-coreutils -- the small tools, as applets
;
; ## cu/ls.x -- ls, with busybox's option set
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox: ls [-1AaCxdLHRFplinshrSXvctuw].  Everything here but the
; column layout (-C -x -w): busybox itself lists one name per line when
; stdout is not a terminal, which is where a tool's output goes.
;
; A LISTING is a list of entries (NAME PATH STAT); the flags choose
; which entries (-a -A -d -R), how they order (-t -S -X -v -r, with
; -c and -u choosing the time -t reads), and how each prints (-l -n -i
; -s -h -F -p).  The stat is lstat unless -L (or -H, for operands)
; asks to follow the link, so a link prints as itself, with its target.
;
; Divergences, loud: uid and gid print as NUMBERS (no passwd door, so
; -n and -l are the same line), and the date column is UTC.

(def %ls-flag? (fn (_ argv f) (%cu-has-flag? argv f)))

; --- entries ------------------------------------------------------------------

(def %ls-stat
  (fn (_ path follow?)
    (let ((st (if follow? (file-stat-full path) (file-lstat-full path))))
      (if (null? st) (file-lstat-full path) st))))

(def %ls-entry
  (fn (_ name path follow?)
    (list name path (%ls-stat path follow?))))

(def %ls-name (fn (_ e) (first e)))
(def %ls-path (fn (_ e) (first (rest e))))
(def %ls-st (fn (_ e) (first (rest (rest e)))))
(def %ls-get (fn (_ e key) (%cu-stat-get (%ls-st e) key)))
(def %ls-dir? (fn (_ e) (eq? (%ls-get e (lit kind)) (lit dir))))

(def %ls-listed?
  (fn (self x xs)
    (if (null? xs) #f (if (string=? (first xs) x) #t (self x (rest xs))))))

(def %ls-hidden?
  (fn (_ n) (if (> (byte-len n) 0) (= (byte-at n 0) 46) #f)))

; a directory's entries: dotfiles need -a or -A, and . .. need -a
(def %ls-children
  (fn (_ dir argv)
    (def a? (%ls-flag? argv "-a"))
    (def A? (%ls-flag? argv "-A"))
    (def follow? (%ls-flag? argv "-L"))
    ; the dir door lists neither . nor ..; -a wants both, so they are
    ; added rather than filtered in
    (def listed (file-list-dir dir))
    (def names
      (append
        (if a? (filter (fn (_ d) (not (%ls-listed? d listed))) (list "." "..")) ())
        (filter (fn (_ n)
                  (if (%cu-dot? n) a?
                    (if (%ls-hidden? n) (if a? #t A?) #t)))
          listed)))
    (map (fn (_ n) (%ls-entry n (%cu-path-join dir n) follow?)) names)))

; --- order --------------------------------------------------------------------

(def %ls-time-key
  (fn (_ argv)
    (if (%ls-flag? argv "-c") (lit ctime)
      (if (%ls-flag? argv "-u") (lit atime) (lit mtime)))))

(def %ls-ext
  (fn (_ n)
    (def end (byte-len n))
    (def go (fn (self i)
              (if (< i 0) ""
                (if (= (byte-at n i) 46) (substring n (+ i 1) end)
                  (self (- i 1))))))
    (go (- end 1))))

; version order: a run of digits compares as a number, the rest as bytes
(def %ls-digit? (fn (_ b) (if (>= b 48) (<= b 57) #f)))
(def %ls-num-run
  (fn (_ s i)
    (def end (byte-len s))
    (def go (fn (self j acc)
              (if (>= j end) (pair acc j)
                (if (%ls-digit? (byte-at s j))
                  (self (+ j 1) (+ (* acc 10) (- (byte-at s j) 48)))
                  (pair acc j)))))
    (go i 0)))
(def %ls-natural<
  (fn (_ a b)
    (def la (byte-len a))
    (def lb (byte-len b))
    (def go
      (fn (self i j)
        (if (>= i la) (< j lb)
          (if (>= j lb) #f
            (let ((ca (byte-at a i)) (cb (byte-at b j)))
              (if (if (%ls-digit? ca) (%ls-digit? cb) #f)
                (let ((ra (%ls-num-run a i)) (rb (%ls-num-run b j)))
                  (if (< (first ra) (first rb)) #t
                    (if (> (first ra) (first rb)) #f
                      (self (rest ra) (rest rb)))))
                (if (< ca cb) #t
                  (if (> ca cb) #f (self (+ i 1) (+ j 1))))))))))
    (go 0 0)))

(def %ls-desc-then-name
  (fn (_ kx ky x y)
    (if (> kx ky) #t
      (if (< kx ky) #f (%cu-str< (%ls-name x) (%ls-name y))))))

(def %ls-less
  (fn (_ argv)
    (def tk (%ls-time-key argv))
    (if (%ls-flag? argv "-t")
      ; ties fall back to the name, as ls orders them
      (fn (_ x y) (%ls-desc-then-name (%ls-get x tk) (%ls-get y tk) x y))
      (if (%ls-flag? argv "-S")
        (fn (_ x y) (%ls-desc-then-name (%ls-get x (lit size)) (%ls-get y (lit size)) x y))
        (if (%ls-flag? argv "-X")
          (fn (_ x y)
            (let ((ex (%ls-ext (%ls-name x))) (ey (%ls-ext (%ls-name y))))
              (if (string=? ex ey) (%cu-str< (%ls-name x) (%ls-name y))
                (%cu-str< ex ey))))
          (if (%ls-flag? argv "-v")
            (fn (_ x y) (%ls-natural< (%ls-name x) (%ls-name y)))
            (fn (_ x y) (%cu-str< (%ls-name x) (%ls-name y)))))))))

(def %ls-order
  (fn (_ es argv)
    (let ((sorted (%cu-msort es (%ls-less argv))))
      (if (%ls-flag? argv "-r") (reverse sorted) sorted))))

; --- one line -----------------------------------------------------------------

(def %ls-months
  (list "Jan" "Feb" "Mar" "Apr" "May" "Jun"
        "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))

(def %ls-two (fn (_ n) (%cu-pad-zero (%cu-int->str n) 2)))

; Mon DD HH:MM within six months either way, Mon DD  YYYY otherwise
(def %ls-date
  (fn (_ t now)
    (def d (Date from-unix t))
    (def f (fn (_ k) (rest (Assoc entry k d))))
    (def recent? (< (if (> now t) (- now t) (- t now)) 15768000))
    (string-concat
      (list (%cu-nth (- (f (lit month)) 1) %ls-months) " "
            (%cu-pad-left (%cu-int->str (f (lit day))) 2) " "
            (if recent?
              (string-append (%ls-two (f (lit hour))) (string-append ":" (%ls-two (f (lit minute)))))
              (string-append " " (%cu-int->str (f (lit year)))))))))

; -h: bytes with one decimal below ten of a unit, as ls -h prints
(def %ls-human
  (fn (_ n)
    (def go
      (fn (self v units)
        (if (if (< v 1024) #t (null? (rest units)))
          (string-append (%cu-int->str v) (first units))
          (let ((q (/ (- v (% v 1024)) 1024)))
            (if (< q 10)
              (let ((tenths (/ (- (* (% v 1024) 10) (% (* (% v 1024) 10) 1024)) 1024)))
                (if (< (+ q (if (> tenths 0) 1 0)) 10)
                  (string-concat (list (%cu-int->str q) "." (%cu-int->str tenths) (first (rest units))))
                  (self q (rest units))))
              (self q (rest units)))))))
    (go n (list "" "K" "M" "G" "T"))))

(def %ls-suffix
  (fn (_ e argv)
    (def k (%ls-get e (lit kind)))
    (if (eq? k (lit dir)) (if (if (%ls-flag? argv "-F") #t (%ls-flag? argv "-p")) "/" "")
      (if (not (%ls-flag? argv "-F")) ""
        (if (eq? k (lit link)) "@"
          (if (eq? k (lit fifo)) "|"
            (if (eq? k (lit socket)) "="
              (if (= 0 (bit-and (%ls-get e (lit mode)) 73)) "" "*"))))))))

(def %ls-size-str
  (fn (_ e argv)
    (if (%ls-flag? argv "-h") (%ls-human (%ls-get e (lit size)))
      (%cu-int->str (%ls-get e (lit size))))))

; the widths a listing's long lines share, so the columns line up
(def %ls-widths
  (fn (_ es argv)
    (def w (fn (_ f) (let ((go (fn (self xs m)
                                 (if (null? xs) m
                                   (let ((n (byte-len (f (first xs)))))
                                     (self (rest xs) (if (> n m) n m)))))))
                       (go es 0))))
    (list (w (fn (_ e) (%cu-int->str (%ls-get e (lit nlink)))))
          (w (fn (_ e) (%cu-int->str (%ls-get e (lit uid)))))
          (w (fn (_ e) (%cu-int->str (%ls-get e (lit gid)))))
          (w (fn (_ e) (%ls-size-str e argv)))
          (w (fn (_ e) (%cu-int->str (%ls-get e (lit ino)))))
          (w (fn (_ e) (%cu-int->str (%cu-du-blocks (%ls-st e))))))))

(def %ls-line
  (fn (_ e argv ws now)
    (def long? (if (%ls-flag? argv "-l") #t (%ls-flag? argv "-n")))
    (def st (%ls-st e))
    (def name (string-append (%ls-name e) (%ls-suffix e argv)))
    (string-concat
      (list
        (if (%ls-flag? argv "-i")
          (string-append (%cu-pad-left (%cu-int->str (%ls-get e (lit ino))) (%cu-nth 4 ws)) " ") "")
        (if (%ls-flag? argv "-s")
          (string-append (%cu-pad-left (%cu-int->str (%cu-du-blocks st)) (%cu-nth 5 ws)) " ") "")
        (if (not long?) name
          (string-concat
            (list (%cu-perm-string (%ls-get e (lit kind)) (%ls-get e (lit mode))) " "
                  (%cu-pad-left (%cu-int->str (%ls-get e (lit nlink))) (%cu-nth 0 ws)) " "
                  (%cu-pad-left (%cu-int->str (%ls-get e (lit uid))) (%cu-nth 1 ws)) " "
                  (%cu-pad-left (%cu-int->str (%ls-get e (lit gid))) (%cu-nth 2 ws)) " "
                  (%cu-pad-left (%ls-size-str e argv) (%cu-nth 3 ws)) " "
                  (%ls-date (%ls-get e (%ls-time-key argv)) now) " "
                  name
                  (if (eq? (%ls-get e (lit kind)) (lit link))
                    (string-append " -> " (file-readlink (%ls-path e)))
                    ""))))
        "\n"))))

; --- a listing ----------------------------------------------------------------

(def %ls-print
  (fn (_ es argv now dir?)
    (def ordered (%ls-order es argv))
    (def ws (%ls-widths ordered argv))
    (def long? (if (%ls-flag? argv "-l") #t (%ls-flag? argv "-n")))
    (def blocks
      (let ((go (fn (self xs acc)
                  (if (null? xs) acc
                    (self (rest xs) (+ acc (%cu-du-blocks (%ls-st (first xs)))))))))
        (go ordered 0)))
    ; `total` heads a DIRECTORY listing only, as ls prints it
    (do (if (if dir? (if long? #t (%ls-flag? argv "-s")) #f)
          (display (string-append "total " (string-append (%cu-int->str blocks) "\n")))
          ())
        (let ((go (fn (self xs)
                    (if (null? xs) ()
                      (do (display (%ls-line (first xs) argv ws now))
                          (self (rest xs)))))))
          (go ordered))
        ordered)))

; a directory, and under -R every directory below it, each with its
; header; the header is printed whenever more than one listing appears
(def %ls-dir
  (fn (self dir argv now header?)
    (def es (%ls-children dir argv))
    (do (if header? (display (string-append dir ":\n")) ())
        (let ((ordered (%ls-print es argv now #t)))
          (if (%ls-flag? argv "-R")
            (let ((go (fn (self2 xs)
                        (if (null? xs) ()
                          (do (if (if (%ls-dir? (first xs))
                                    (not (%cu-dot? (%ls-name (first xs)))) #f)
                                (do (display "\n")
                                    (self (%ls-path (first xs)) argv now #t))
                                ())
                              (self2 (rest xs)))))))
              (go ordered))
            ())))))

(def %cu-ls
  (fn (_ argv stdin-thunk)
    (def ops0 (filter (fn (_ x) (not (%cu-option-token? x))) argv))
    (def ops (if (null? ops0) (list ".") ops0))
    (def now (date-now-unix))
    (def d? (%ls-flag? argv "-d"))
    (def follow-ops? (if (%ls-flag? argv "-L") #t (%ls-flag? argv "-H")))
    (def entries (map (fn (_ p) (%ls-entry p p follow-ops?)) ops))
    (def missing (filter (fn (_ e) (null? (%ls-st e))) entries))
    (def present (filter (fn (_ e) (not (null? (%ls-st e)))) entries))
    (def files (filter (fn (_ e) (if d? #t (not (%ls-dir? e)))) present))
    (def dirs (filter (fn (_ e) (if d? #f (%ls-dir? e))) present))
    (def many? (if (%ls-flag? argv "-R") #t (> (+ (length files) (length dirs)) 1)))
    (do
      (let ((go (fn (self ms)
                  (if (null? ms) ()
                    (do (file-write 2
                          (string-concat
                            (list "ls: " (%ls-name (first ms))
                                  ": No such file or directory\n")))
                        (self (rest ms)))))))
        (go missing))
      (if (null? files) () (%ls-print files argv now #f))
      (let ((go (fn (self ds first?)
                  (if (null? ds) ()
                    (do (if (if first? (null? files) #f) () (display "\n"))
                        (%ls-dir (%ls-path (first ds)) argv now many?)
                        (self (rest ds) #f))))))
        (go (%ls-order dirs argv) #t))
      (if (null? missing) 0 1))))

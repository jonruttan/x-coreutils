; # x-coreutils -- the small tools, as applets
;
; ## cu/text.x -- the line tools
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; sort uniq head tail cat wc comm join basename dirname.  An applet is
; (fn (_ argv stdin-thunk) -> status); output goes to stdout, and the
; shared %cu-gather answers the operands' concatenated text (stdin when
; none, - meaning stdin among them).

; --- shared helpers ----------------------------------------------------------

(def %cu-b->s
  (fn (_ b) (list->string (list (integer->char b)))))

(def %cu-lines-go
  (fn (self s end i start acc)
    (if (>= i end)
      (if (> i start)
        (reverse (pair (substring s start i) acc))
        (reverse acc))
      (if (= (byte-at s i) 10)
        (self s end (+ i 1) (+ i 1) (pair (substring s start i) acc))
        (self s end (+ i 1) start acc)))))
(def %cu-lines
  (fn (_ s) (%cu-lines-go s (byte-len s) 0 0 ())))

; run BODY over each operand in turn, with `-` and the empty list
; standing for stdin -- the shape head and tail share once they print
; a header per file.
(def %cu-each-operand
  (fn (_ ops stdin-thunk body)
    (if (null? ops) (body "standard input" (stdin-thunk) #t)
      (let ((go (fn (self os first?)
                  (if (null? os) ()
                    (do (body (first os)
                          (if (string=? (first os) "-") (stdin-thunk)
                            (file-read-all (first os)))
                          first?)
                        (self (rest os) #f))))))
        (go ops #t)))))

(def %cu-drop
  (fn (self l k) (if (<= k 0) l (if (null? l) l (self (rest l) (- k 1))))))

(def %cu-print-lines
  (fn (self ls)
    (if (null? ls) ()
      (do (display (string-append (first ls) "\n"))
          (self (rest ls))))))

(def %cu-str<
  (fn (_ a b)
    (def la (byte-len a))
    (def lb (byte-len b))
    (def go
      (fn (self i)
        (if (>= i la) (< la lb)
          (if (>= i lb) #f
            (let ((ca (byte-at a i)) (cb (byte-at b i)))
              (if (< ca cb) #t
                (if (> ca cb) #f (self (+ i 1)))))))))
    (go 0)))

; merge sort: n log n, shallow recursion
(def %cu-merge
  (fn (self a b less?)
    (match
      ((null? a) b)
      ((null? b) a)
      ((less? (first b) (first a)) (pair (first b) (self a (rest b) less?)))
      (#t (pair (first a) (self (rest a) b less?))))))
(def %cu-msort
  (fn (self l less?)
    (if (null? l) ()
      (if (null? (rest l)) l
        (let ((split (let ((go (fn (self2 slow fast acc)
                                 (if (if (pair? fast) (pair? (rest fast)) #f)
                                   (self2 (rest slow) (rest (rest fast))
                                     (pair (first slow) acc))
                                   (pair (reverse acc) slow)))))
                       (go l l ()))))
          (%cu-merge (self (first split) less?)
            (self (rest split) less?) less?))))))

; a leading number for sort -n: optional blanks, sign, digits[.digits]
(def %cu-num-prefix
  (fn (_ s)
    (def end (byte-len s))
    (def i0 (let ((go (fn (self i)
                        (if (>= i end) i
                          (let ((b (byte-at s i)))
                            (if (if (= b 32) #t (= b 9)) (self (+ i 1)) i))))))
              (go 0)))
    (def neg (if (< i0 end) (= (byte-at s i0) 45) #f))
    (def i1 (if neg (+ i0 1) i0))
    (def ir (let ((go (fn (self i acc any)
                        (if (>= i end) (pair acc any)
                          (let ((b (byte-at s i)))
                            (if (if (>= b 48) (<= b 57) #f)
                              (self (+ i 1) (+ (* acc 10) (- b 48)) #t)
                              (pair acc any)))))))
              (go i1 0 #f)))
    (if (not (rest ir)) 0
      (if neg (- 0 (first ir)) (first ir)))))

(def %cu-int->str
  (fn (_ n)
    (if (= n 0) "0"
      (let ((go (fn (self t acc)
                  (if (= t 0) acc
                    (self (/ (- t (% t 10)) 10)
                      (pair (integer->char (+ 48 (% t 10))) acc))))))
        (if (< n 0)
          (string-append "-" (list->string (go (- 0 n) ())))
          (list->string (go n ())))))))

(def %cu-pad-left
  (fn (_ s w)
    (def gap (- w (byte-len s)))
    (def sp (fn (self k) (if (<= k 0) "" (string-append " " (self (- k 1))))))
    (if (<= gap 0) s (string-append (sp gap) s))))

(def %cu-pad-right
  (fn (_ s w)
    (def gap (- w (byte-len s)))
    (def sp (fn (self k) (if (<= k 0) "" (string-append " " (self (- k 1))))))
    (if (<= gap 0) s (string-append s (sp gap)))))

; operands to one text: files in order, - or none meaning stdin
(def %cu-gather
  (fn (_ operands stdin-thunk)
    (if (null? operands)
      (stdin-thunk)
      (let ((go (fn (self ops acc)
                  (if (null? ops)
                    (string-concat (reverse acc))
                    (self (rest ops)
                      (pair
                        (if (string=? (first ops) "-")
                          (stdin-thunk)
                          (file-read-all (first ops)))
                        acc))))))
        (go operands ())))))

; The -z and -0 reading shape: operands (or standard input) as fields
; split on a byte, which is %cu-lines over %cu-gather when the delimiter
; is a newline and the bytes are a string.  A NUL is neither, so the
; operands are read as bytes and the leftover of one file opens the
; next, the way the tools read their inputs as one stream.
(def %cu-delim-fields
  (fn (_ ops stdin-thunk delim)
    (if (null? ops) (cu-stdin-fields! delim)
      (let ((go (fn (self os partial acc)
                  (if (null? os)
                    (append acc
                      (if (= (byte-len partial) 0) () (list partial)))
                    (if (string=? (first os) "-")
                      (self (rest os) "" (append acc (cu-stdin-fields! delim)))
                      (let ((fd (file-open-read (first os))))
                        (let ((r (%cu-fd-fields fd delim partial)))
                          (do (file-close fd)
                              (self (rest os) (rest r)
                                (append acc (first r)))))))))))
        (go ops "" ())))))

; each field, then its delimiter -- %cu-print-lines for a -z output
(def %cu-print-fields
  (fn (self ls delim)
    (if (null? ls) ()
      (do (file-write-field 1 (first ls) delim)
          (self (rest ls) delim)))))

; The last hand-rolled option read: everything reads its options off cu/cli.x's
; declaration except comm, whose flags are digits -- v0.13.0's Opts decides
; `-12` is a negative number before consulting the declaration, so the cluster
; never reaches the parse. x-lang#650 makes the declaration win, and these two
; go when it ships.
(def %cu-option-token-ish?
  (fn (_ s) (if (< (byte-len s) 2) #f (= (byte-at s 0) 45))))

(def %cu-token-has?
  (fn (_ tok d)
    (let ((go (fn (self i)
                (if (>= i (byte-len tok)) #f
                  (if (= (byte-at tok i) d) #t (self (+ i 1)))))))
      (go 1))))

(def %cu-head
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "head" argv))
    (def ops (Opts operands o))
    (def bytes (Opts value o "-c"))
    (def n (%cu-num-prefix (Opts value o "-n" "10")))
    ; a header per operand when there is more than one, as head does;
    ; -v forces it and -q suppresses it
    (def head?
      (if (Opts on? o "-q") #f
        (if (Opts on? o "-v") #t (> (length ops) 1))))
    (def one
      (fn (_ name text first?)
        (do (if head?
              (display (string-concat
                         (list (if first? "" "\n") "==> " name " <==\n")))
              ())
            (if (null? bytes)
              (%cu-print-lines (%cu-take (%cu-lines text) n))
              (let ((k (%cu-num-prefix bytes)))
                (display (substring text 0
                           (if (> k (byte-len text)) (byte-len text) k))))))))
    (do (%cu-each-operand ops stdin-thunk one) 0)))

(def %cu-member-s?
  (fn (_ s l)
    (def go
      (fn (self es)
        (if (null? es) #f
          (if (string=? (first es) s) #t (self (rest es))))))
    (go l)))

; LINES to FD, one per line -- stderr's %cu-print-lines
(def %cu-print-lines-to
  (fn (self fd ls)
    (if (null? ls) ()
      (do (file-write fd (string-append (first ls) "\n"))
          (self fd (rest ls))))))

; -s's interval: "2", "0.5", "1.25" -- whole seconds through sleep and
; the fraction, to the microsecond, through usleep, which on Darwin
; takes less than a second.
(def %cu-tail-sleep
  (fn (_ spec)
    (def parts (%cu-split-byte spec 46))                          ; .
    (def secs
      (if (= (byte-len (first parts)) 0) 0 (%cu-num-prefix (first parts))))
    (def us
      (if (null? (rest parts)) 0
        (%cu-num-prefix
          (substring (string-append (first (rest parts)) "000000") 0 6))))
    (do (if (> secs 0) (sys-sleep secs) ())
        (if (> us 0) (sys-usleep us) ())
        ())))

; the bytes of NAME from FROM up to TO
(def %cu-read-range
  (fn (_ name from to)
    (let ((fd (file-open-read name)))
      (do (file-seek fd from)
          (let ((s (file-read-fd fd (- to from))))
            (do (file-close fd) s))))))

; One round of -f over NAMES, each followed from its entry in OFFS: what
; grew is printed, under a header when headers are on and the file is
; not the one printed last, and a file that shrank was truncated -- said
; on stderr, then read again from its start.  A file that cannot be
; read this round keeps its offset for the next.  Answers the new
; offsets paired with the name printed last, which the next round takes.
(def %cu-tail-round
  (fn (_ names offs head? last)
    (def go
      (fn (self ns os last acc)
        (if (null? ns) (pair (reverse acc) last)
          (let ((st (file-stat-full (first ns))))
            (if (null? st)
              (self (rest ns) (rest os) last (pair (first os) acc))
              (let ((size (%cu-stat-get st (lit size))))
                (def from
                  (if (< size (first os))
                    (do (file-write 2
                          (string-concat
                            (list "tail: " (first ns) ": file truncated\n")))
                        0)
                    (first os)))
                (if (> size from)
                  (do (if (if head? (not (string=? last (first ns))) #f)
                        (display
                          (string-concat (list "\n==> " (first ns) " <==\n")))
                        ())
                      (display (%cu-read-range (first ns) from size))
                      (self (rest ns) (rest os) (first ns) (pair size acc)))
                  (self (rest ns) (rest os) last (pair from acc)))))))))
    (go names offs last ())))

; rounds forever (ROUNDS below zero) or for a count, sleeping INTERVAL
; between them; "0" does not sleep.  OFFS is where each file's initial
; read ENDED, not its size now: a line appended between that read and
; the first round belongs to the follow, and sizing the file again here
; would skip it.
(def %cu-tail-follow
  (fn (_ names offs head? last interval rounds)
    (def go
      (fn (self offs last k)
        (if (= k 0) 0
          (do (if (string=? interval "0") () (%cu-tail-sleep interval))
              (let ((r (%cu-tail-round names offs head? last)))
                (self (first r) (rest r) (if (< k 0) k (- k 1))))))))
    (go offs last rounds)))

; -f follows its files by NAME, polled every -s seconds (1 by default).
; Standard input has been read whole by the time an applet runs, so it
; has nothing to follow: -f with only stdin prints the tail and returns.
(def %cu-tail
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "tail" argv))
    (def ops (Opts operands o))
    (def bytes (Opts value o "-c"))
    (def n (%cu-num-prefix (Opts value o "-n" "10")))
    (def head?
      (if (Opts on? o "-q") #f
        (if (Opts on? o "-v") #t (> (length ops) 1))))
    ; where each file's read ended, newest first: the follow starts there
    (def read-to (list ()))
    (def one
      (fn (_ name text first?)
        (do (if head?
              (display (string-concat
                         (list (if first? "" "\n") "==> " name " <==\n")))
              ())
            (if (if (string=? name "-") #f (not (string=? name "standard input")))
              (%set-first! read-to (pair (byte-len text) (first read-to)))
              ())
            (if (null? bytes)
              (let ((ls (%cu-lines text)))
                (%cu-print-lines (%cu-drop ls (- (length ls) n))))
              (let ((k (%cu-num-prefix bytes)))
                (def end (byte-len text))
                (display (substring text (if (> k end) 0 (- end k)) end)))))))
    ; A file that cannot be opened is named and dropped, as tail does, and
    ; the rest are read; with nothing left to follow, -f says so.  Only
    ; when no operand was given at all is stdin the input.
    (def missing
      (filter (fn (_ p) (if (string=? p "-") #f (not (file-exists? p)))) ops))
    (def kept (filter (fn (_ p) (not (%cu-member-s? p missing))) ops))
    (def files (filter (fn (_ p) (not (string=? p "-"))) kept))
    (def f? (Opts on? o "-f"))
    (do (%cu-print-lines-to 2
          (map (fn (_ p)
                 (string-concat
                   (list "tail: cannot open '" p
                         "' for reading: No such file or directory")))
            missing))
        (if (if (null? kept) (pair? ops) #f) ()
          (%cu-each-operand kept stdin-thunk one))
        (match
          ((if f? (if (pair? ops) (null? files) #f) #f)
            (do (file-write 2 "tail: no files remaining\n") 1))
          ((if f? (pair? files) #f)
            (do (%cu-tail-follow files (reverse (first read-to)) head?
                  (if (null? kept) "" (%cu-last kept))
                  (Opts value o "-s" "1") (- 0 1))
                (if (null? missing) 0 1)))
          (#t (if (null? missing) 0 1))))))

; counts for one text: (lines words bytes)
; (LINES WORDS BYTES LONGEST). LONGEST is the longest line without its
; newline, which is what -L reports.
(def %cu-wc-counts
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i nl nw in-word col longest)
        (if (>= i end)
          (list nl (if in-word (+ nw 1) nw) end
            (if (> col longest) col longest))
          (let ((b (byte-at s i)))
            (def ws (match ((= b 32) #t) ((= b 9) #t) (#t (= b 10))))
            (self (+ i 1)
              (if (= b 10) (+ nl 1) nl)
              (if (if in-word ws #f) (+ nw 1) nw)
              (not ws)
              (if (= b 10) 0 (+ col 1))
              (if (= b 10) (if (> col longest) col longest) longest))))))
    (go 0 0 0 #f 0 0)))

(def %cu-wc
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "wc" argv))
    (def any?
      (match
        ((Opts on? o "-l") #t) ((Opts on? o "-w") #t) ((Opts on? o "-c") #t)
        ((Opts on? o "-m") #t) ((Opts on? o "-L") #t)
        (#t #f)))
    ; With no flag at all wc shows lines, words and bytes -- not -m or -L,
    ; which are asked for or not shown.
    (def show?
      (fn (_ f)
        (if any? (Opts on? o f)
          (match ((string=? f "-m") #f) ((string=? f "-L") #f) (#t #t)))))
    (def row
      (fn (_ counts name)
        ; Columns in wc's order: lines, words, chars, bytes, longest line.
        ; -m and -c report the same number here, because this wc counts
        ; bytes and a character is a byte -- asking for both prints it
        ; twice, which is what asking for both means.
        (def col
          (fn (_ flag n)
            (if (show? flag)
              (list (%cu-pad-left (%cu-int->str (%cu-nth n counts)) 8))
              ())))
        (def parts
          (append (col "-l" 0)
            (append (col "-w" 1)
              (append (col "-m" 2)
                (append (col "-c" 2) (col "-L" 3))))))
        (display
          (string-append (%cu-join-sp parts)
            (if (null? name) "\n"
              (string-append " " (string-append name "\n")))))))
    (if (null? (Opts operands o))
      (do (row (%cu-wc-counts (stdin-thunk)) ()) 0)
      (let ((go (fn (self ops)
                  (if (null? ops) 0
                    (do (row (%cu-wc-counts
                               (if (string=? (first ops) "-")
                                 (stdin-thunk)
                                 (file-read-all (first ops))))
                          (first ops))
                        (self (rest ops)))))))
        (go (Opts operands o))))))

(def %cu-join-sp
  (fn (self ws)
    (if (null? ws) ""
      (if (null? (rest ws)) (first ws)
        (string-append (first ws) (self (rest ws)))))))

; comm: three columns over two sorted inputs; -1 -2 -3 suppress
(def %cu-comm
  (fn (_ argv stdin-thunk)
    ; comm's flags are digits, and v0.13.0's Opts decides `-12` is a negative
    ; number before consulting the declaration, so comm reads its three digits
    ; itself until x-lang#650 ships. Everything else comes off the one parse.
    (def o (%cu-opts "comm" argv))
    (def digit?
      (fn (_ d)
        (let ((go (fn (self as)
                    (if (null? as) #f
                      (if (%cu-option-token-ish? (first as))
                        (if (%cu-token-has? (first as) d) #t (self (rest as)))
                        (self (rest as)))))))
          (go argv))))
    (def s1 (not (digit? 49)))
    (def s2 (not (digit? 50)))
    (def s3 (not (digit? 51)))
    (def ops (filter (fn (_ a) (not (%cu-option-token-ish? a))) argv))
    (def read-op
      (fn (_ op) (if (string=? op "-") (stdin-thunk) (file-read-all op))))
    (def a (%cu-lines (read-op (first ops))))
    (def b (%cu-lines (read-op (first (rest ops)))))
    (def ind2 (if s1 "\t" ""))
    (def ind3 (string-append (if s1 "\t" "") (if s2 "\t" "")))
    (def go
      (fn (self la lb)
        (match
          ((null? la)
            (if (null? lb) ()
              (do (if s2 (display (string-append ind2
                                    (string-append (first lb) "\n"))) ())
                  (self la (rest lb)))))
          ((null? lb)
            (do (if s1 (display (string-append (first la) "\n")) ())
                (self (rest la) lb)))
          ((string=? (first la) (first lb))
            (do (if s3 (display (string-append ind3
                                  (string-append (first la) "\n"))) ())
                (self (rest la) (rest lb))))
          ((%cu-str< (first la) (first lb))
            (do (if s1 (display (string-append (first la) "\n")) ())
                (self (rest la) lb)))
          (#t
            (do (if s2 (display (string-append ind2
                                  (string-append (first lb) "\n"))) ())
                (self la (rest lb)))))))
    (do (go a b) 0)))

; join on field 1 of two sorted inputs; -t CHAR sets the delimiter
(def %cu-split-line
  (fn (_ line delim)
    (if (null? delim)
      (%cu-words-line line)
      (%cu-split-byte line (byte-at delim 0)))))

(def %cu-words-line
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i start acc in)
        (if (>= i end)
          (reverse (if in (pair (substring s start i) acc) acc))
          (let ((ws (let ((b (byte-at s i)))
                      (if (= b 32) #t (= b 9)))))
            (if ws
              (self (+ i 1) (+ i 1) (if in (pair (substring s start i) acc) acc) #f)
              (self (+ i 1) (if in start i) acc #t))))))
    (go 0 0 () #f)))

(def %cu-split-byte
  (fn (_ s b)
    (def end (byte-len s))
    (def go
      (fn (self i start acc)
        (if (>= i end)
          (reverse (pair (substring s start end) acc))
          (if (= (byte-at s i) b)
            (self (+ i 1) (+ i 1) (pair (substring s start i) acc))
            (self (+ i 1) start acc)))))
    (go 0 0 ())))

(def %cu-join
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "join" argv))
    (def delim (Opts value o "-t"))
    (def ops (Opts operands o))
    (def sep (if (null? delim) " " delim))
    (def read-op
      (fn (_ op) (if (string=? op "-") (stdin-thunk) (file-read-all op))))
    (def a (%cu-lines (read-op (first ops))))
    (def b (%cu-lines (read-op (first (rest ops)))))
    (def key (fn (_ line)
               (let ((fs (%cu-split-line line delim)))
                 (if (null? fs) "" (first fs)))))
    (def rest-fields
      (fn (_ line)
        (let ((fs (%cu-split-line line delim)))
          (if (null? fs) () (rest fs)))))
    (def emit
      (fn (_ la lb)
        (display
          (string-append
            (%cu-join-with
              (pair (key la)
                (append (rest-fields la) (rest-fields lb)))
              sep)
            "\n"))))
    ; runs of equal keys pair cartesianly
    (def take-run
      (fn (_ ls k)
        (let ((go (fn (self l acc)
                    (if (if (pair? l) (string=? (key (first l)) k) #f)
                      (self (rest l) (pair (first l) acc))
                      (pair (reverse acc) l)))))
          (go ls ()))))
    (def go
      (fn (self la lb)
        (if (null? la) ()
          (if (null? lb) ()
            (let ((ka (key (first la))) (kb (key (first lb))))
              (if (string=? ka kb)
                (let ((ra (take-run la ka)))
                  (def rb (take-run lb ka))
                  ; equal-key runs pair cartesianly
                  (def outer
                    (fn (self2 xs)
                      (if (null? xs) ()
                        (do (let ((inner (fn (self3 ys)
                                           (if (null? ys) ()
                                             (do (emit (first xs) (first ys))
                                                 (self3 (rest ys)))))))
                              (inner (first rb)))
                            (self2 (rest xs))))))
                  (do (outer (first ra))
                      (self (rest ra) (rest rb))))
                (if (%cu-str< ka kb)
                  (self (rest la) lb)
                  (self la (rest lb)))))))))
    (do (go a b) 0)))

(def %cu-join-with
  (fn (self ws sep)
    (if (null? ws) ""
      (if (null? (rest ws)) (first ws)
        (string-append (first ws)
          (string-append sep (self (rest ws) sep)))))))

; The suffix is either -s SUFFIX or a second operand; busybox takes both
; spellings and they mean the same thing.
(def %cu-basename
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "basename" argv))
    (def ops (Opts operands o))
    (def p (first ops))
    (def stripped
      (let ((go (fn (self e)
                  (if (if (> e 1) (= (byte-at p (- e 1)) 47) #f)
                    (self (- e 1))
                    e))))
        (substring p 0 (go (byte-len p)))))
    (def slash
      (let ((go (fn (self i last)
                  (if (>= i (byte-len stripped)) last
                    (self (+ i 1)
                      (if (= (byte-at stripped i) 47) i last))))))
        (go 0 (- 0 1))))
    (def base (if (< slash 0) stripped
                (substring stripped (+ slash 1) (byte-len stripped))))
    (def suf
      (let ((v (Opts value o "-s")))
        (match
          ((not (null? v)) v)
          ((null? (rest ops)) ())
          (#t (first (rest ops))))))
    (def final
      (if (null? suf) base
        (let ((lb (byte-len base)) (ls (byte-len suf)))
          (if (if (> lb ls)
                (string=? (substring base (- lb ls) lb) suf)
                #f)
            (substring base 0 (- lb ls))
            base))))
    (do (display (string-append final "\n")) 0)))

(def %cu-dirname
  (fn (_ argv stdin-thunk)
    (def p (first argv))
    (def stripped
      (let ((go (fn (self e)
                  (if (if (> e 1) (= (byte-at p (- e 1)) 47) #f)
                    (self (- e 1))
                    e))))
        (substring p 0 (go (byte-len p)))))
    (def slash
      (let ((go (fn (self i last)
                  (if (>= i (byte-len stripped)) last
                    (self (+ i 1)
                      (if (= (byte-at stripped i) 47) i last))))))
        (go 0 (- 0 1))))
    (def d
      (if (< slash 0) "."
        (if (= slash 0) "/"
          (substring stripped 0 slash))))
    (do (display (string-append d "\n")) 0)))

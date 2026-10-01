; # x-coreutils -- the small tools, as applets
;
; ## cu/tsort.x -- tsort
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's tsort (coreutils/tsort.c): the words of one file, or of standard
; input, read in pairs, each pair an edge from the first to the second, and
; the nodes put out in an order where every edge points forward.  The order is
; busybox's own, from Kahn's algorithm over its array of nodes: the array
; sorted by name, the first node with no edge coming in taken, and the last
; node moved into its place.  Where no node is free the rest hold a cycle: it
; is said, `cycle at NAME`, broken at the array's first node, and the status
; is 1.  An odd number of words is `odd input`, and nothing is put out.

; isspace's bytes: the space, and tab up to carriage return
(def %ts-space?
  (fn (_ b) (if (= b #\space) #t (if (< b #\tab) #f (<= b #\return)))))

; The words of S onto WORDS, newest first.  CARRY is a word the last piece ended
; inside, its first bytes; it goes in front of the first word S starts with.
; Answers (CARRY . WORDS), CARRY the word S ends inside, or "".
(def %ts-words
  (fn (_ s carry words)
    (def end (byte-len s))
    (def go
      (fn (self i start pre acc)
        (match
          ((>= i end)
            (pair (if (< start 0) "" (string-append pre (substring s start end))) acc))
          ((%ts-space? (byte-at s i))
            (if (< start 0) (self (+ i 1) -1 pre acc)
              (do (%cu-sweep-tick! %cu-sweep-lines)
                  (self (+ i 1) -1 ""
                    (pair (string-append pre (substring s start i)) acc)))))
          (#t (self (+ i 1) (if (< start 0) i start) pre acc)))))
    (go 0 (if (= (byte-len carry) 0) -1 0) carry words)))

; the index of WORD among NAMES, a vector sorted by %cu-str<
(def %ts-find
  (fn (_ names word)
    (def go
      (fn (self a b)
        (let ((m (/ (- (+ a b) (% (+ a b) 2)) 2)))
          (let ((n (vec-ref names m)))
            (match
              ((string=? word n) m)
              ((%cu-str< word n) (self a m))
              (#t (self (+ m 1) b)))))))
    (go 0 (Vector length names))))

; WORDS, in order, sorted by name with each once
(def %ts-names
  (fn (_ words)
    (def go
      (fn (self ws acc)
        (match
          ((null? ws) (reverse acc))
          ((if (pair? acc) (string=? (first ws) (first acc)) #f) (self (rest ws) acc))
          (#t (self (rest ws) (pair (first ws) acc))))))
    (go (%cu-msort words %cu-str<) ())))

; Kahn's algorithm, as busybox runs it, over NAMES with the edges OUT (each
; node's list of the nodes its edges go to) and IN (each node's count of edges
; coming in).  Answers (LINES . CYCLES), LINES newest first.
(def %ts-order
  (fn (_ names out in)
    (def n (Vector length names))
    (def arr (vec-build n (fn (_ i) i)))
    (def free
      (fn (self i len)
        (if (>= i len) -1
          (if (= (vec-ref in (vec-ref arr i)) 0) i (self (+ i 1) len)))))
    (def drop
      (fn (self bs)
        (if (null? bs) ()
          (do (vec-set! in (first bs) (- (vec-ref in (first bs)) 1))
              (self (rest bs))))))
    (def go
      (fn (self len lines cycles)
        (if (= len 0) (pair lines cycles)
          (let ((f (free 0 len)))
            (let ((i (if (< f 0) 0 f)))
              (let ((node (vec-ref arr i)))
                (do (%cu-sweep-tick! %cu-sweep-lines)
                    (if (< f 0)
                      (file-write 2
                        (string-concat (list "tsort: cycle at " (vec-ref names node) "\n")))
                      ())
                    (vec-set! arr i (vec-ref arr (- len 1)))
                    (drop (vec-ref out node))
                    (self (- len 1)
                      (pair (string-append (vec-ref names node) "\n") lines)
                      (if (< f 0) (+ cycles 1) cycles)))))))))
    (go n () 0)))

; WORDS, in order and even in number, sorted
(def %ts-sort
  (fn (_ words)
    (def names (Vector from-list (%ts-names words)))
    (def n (Vector length names))
    (def out (vec-make n ()))
    (def in (vec-make n 0))
    (def edges
      (fn (self ws)
        (if (null? ws) ()
          (let ((a (%ts-find names (first ws)))
                (b (%ts-find names (first (rest ws)))))
            (do (if (= a b) ()
                  (do (vec-set! out a (pair b (vec-ref out a)))
                      (vec-set! in b (+ (vec-ref in b) 1))))
                (self (rest (rest ws))))))))
    (do (edges words)
        (let ((r (%ts-order names out in)))
          (do (file-write 1 (string-concat (reverse (first r))))
              (if (= (rest r) 0) 0 1))))))

(def %ts-usage
  (fn (_)
    (do (file-write 2 "Usage: tsort [FILE]\n\nTopological sort\n") 1)))

; tsort [FILE]: FILE, or `-` or no operand standard input.  A FILE that will
; not open ends it; one that opens and will not read, a directory, is empty.
(def %cu-tsort
  (fn (_ argv stdin-thunk)
    (def ops argv)
    (def name (if (null? ops) "-" (first ops)))
    (def take
      (fn (_ p s)
        (%ts-words (%cu-run-text p) (first s) (rest s))))
    (if (if (pair? ops) (pair? (rest ops)) #f) (%ts-usage)
      (let ((src (%cu-pieces name stdin-thunk)))
        (if (Err err? src)
          (do (file-write 2
                (string-concat
                  (list "tsort: can't open '" name "': " (file-err-text src) "\n")))
              1)
          (let ((s (first (%cu-fold-pieces src take (pair "" ())))))
            (do (src (lit close))
                (let ((words (reverse (if (= (byte-len (first s)) 0) (rest s)
                                        (pair (first s) (rest s))))))
                  (if (= (% (length words) 2) 1)
                    (do (file-write 2 "tsort: odd input\n") 1)
                    (%ts-sort words))))))))))

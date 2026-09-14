; # x-coreutils -- the small tools, as applets
;
; ## cu/trcut.x -- tr and cut
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

; a tr SET to a byte list: literals, a-z ranges, \n \t \\ escapes
(def %cu-tr-set
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i acc)
        (if (>= i end) (reverse acc)
          (let ((b (byte-at s i)))
            (if (if (= b 92) (< (+ i 1) end) #f)          ; backslash
              (let ((e (byte-at s (+ i 1))))
                (self (+ i 2)
                  (pair (if (= e 110) 10 (if (= e 116) 9 e)) acc)))
              (if (if (< (+ i 2) end)
                    (if (= (byte-at s (+ i 1)) 45)        ; range a-z
                      (not (= (byte-at s (+ i 2)) 92))
                      #f)
                    #f)
                (let ((hi (byte-at s (+ i 2))))
                  (def fill
                    (fn (self2 v acc2)
                      (if (> v hi) acc2 (self2 (+ v 1) (pair v acc2)))))
                  (self (+ i 3) (fill b acc)))
                (self (+ i 1) (pair b acc))))))))
    (go 0 ())))

(def %cu-member-b?
  (fn (_ b l)
    (def go
      (fn (self es)
        (if (null? es) #f
          (if (= (first es) b) #t (self (rest es))))))
    (go l)))

; the 256-entry translate map as an alist would scan; a flat pairing
; walk per byte is fine at this scale
(def %cu-tr-map
  (fn (_ set1 set2 b)
    (def go
      (fn (self s1 s2 lastv)
        (if (null? s1) b
          (let ((v (if (null? s2) lastv (first s2))))
            (if (= (first s1) b) v
              (self (rest s1) (if (null? s2) () (rest s2)) v))))))
    (go set1 set2 (if (null? set2) b (first set2)))))

(def %cu-tr
  (fn (_ argv stdin-thunk)
    (def del? (if (pair? argv) (string=? (first argv) "-d") #f))
    (def sq? (if (pair? argv) (string=? (first argv) "-s") #f))
    (def args (if (if del? #t sq?) (rest argv) argv))
    (def set1 (%cu-tr-set (first args)))
    (def set2 (if (null? (rest args)) () (%cu-tr-set (first (rest args)))))
    (def text (stdin-thunk))
    (def end (byte-len text))
    (def squeeze-set (if sq? (if (null? set2) set1 set2) ()))
    (def go
      (fn (self i acc prev)
        (if (>= i end) (string-concat (reverse acc))
          (let ((b (byte-at text i)))
            (if (if del? (%cu-member-b? b set1) #f)
              (self (+ i 1) acc prev)
              (let ((v (if (null? set2) b (%cu-tr-map set1 set2 b))))
                (if (if sq? (if (= v prev) (%cu-member-b? v squeeze-set) #f) #f)
                  (self (+ i 1) acc prev)
                  (self (+ i 1) (pair (%cu-b->s v) acc) v))))))))
    (do (display (go 0 () (- 0 1))) 0)))

; a cut LIST: N, N-M, N-, -M, comma-separated; answers (lo . hi) pairs
; with hi () for open
(def %cu-cut-list
  (fn (_ s)
    (def parts (%cu-split-byte s 44))                     ; ,
    (map
      (fn (_ p)
        (let ((dash (let ((go (fn (self i)
                                (if (>= i (byte-len p)) (- 0 1)
                                  (if (= (byte-at p i) 45) i
                                    (self (+ i 1)))))))
                      (go 0))))
          (if (< dash 0)
            (pair (%cu-num-prefix p) (%cu-num-prefix p))
            (let ((lo-s (substring p 0 dash)))
              (def hi-s (substring p (+ dash 1) (byte-len p)))
              (pair (if (= (byte-len lo-s) 0) 1 (%cu-num-prefix lo-s))
                (if (= (byte-len hi-s) 0) () (%cu-num-prefix hi-s)))))))
      parts)))

(def %cu-in-ranges?
  (fn (_ n ranges)
    (def go
      (fn (self rs)
        (if (null? rs) #f
          (let ((lo (first (first rs))) (hi (rest (first rs))))
            (if (if (>= n lo) (if (null? hi) #t (<= n hi)) #f)
              #t
              (self (rest rs)))))))
    (go ranges)))

; -b/-c LIST selects positions, -d C -f LIST selects fields. -s drops a line
; that holds no delimiter; without it such a line passes whole.
;
; -b and -c are the same operation here, and -n is a no-op that is honoured
; rather than ignored: this cut is byte-oriented, so a character is a byte,
; and "do not split a multibyte character" cannot fail when nothing is
; multibyte.
(def %cu-cut
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "cut" argv))
    (def ops (Opts operands o))
    (def blist (Opts value o "-b"))
    (def clist (Opts value o "-c"))
    (def flist (Opts value o "-f"))
    (def positions (if (null? blist) clist blist))
    (if (if (null? positions) (null? flist) #f)
      (do (file-write 2 "cut: need -b, -c or -f\n") 1)
      (do
        (def delim (Opts value o "-d"))
        (def suppress? (Opts on? o "-s"))
        (def text (%cu-gather ops stdin-thunk))
        (def lines (%cu-lines text))
        (if (not (null? positions))
          (let ((ranges (%cu-cut-list positions)))
            (def cut-line
              (fn (_ line)
                (def end (byte-len line))
                (def go
                  (fn (self i acc)
                    (if (>= i end) (string-concat (reverse acc))
                      (self (+ i 1)
                        (if (%cu-in-ranges? (+ i 1) ranges)
                          (pair (%cu-b->s (byte-at line i)) acc)
                          acc)))))
                (go 0 ())))
            (do (%cu-print-lines (map (fn (_ l) (cut-line l)) lines)) 0))
          (let ((ranges (%cu-cut-list flist)))
            (def db (if (null? delim) 9 (byte-at delim 0)))
            (def sep (%cu-b->s db))
            (def cut-line
              (fn (_ line)
                (def fields (%cu-split-byte line db))
                (if (null? (rest fields))
                  line                                    ; no delimiter
                  (let ((go (fn (self fs n acc)
                              (if (null? fs) (reverse acc)
                                (self (rest fs) (+ n 1)
                                  (if (%cu-in-ranges? n ranges)
                                    (pair (first fs) acc)
                                    acc))))))
                    (%cu-join-with (go fields 1 ()) sep)))))
            (def keep?
              (fn (_ line)
                (if suppress? (pair? (rest (%cu-split-byte line db))) #t)))
            (do (%cu-print-lines
                  (map (fn (_ l) (cut-line l)) (filter keep? lines)))
                0)))))))


; # x-coreutils -- the small tools, as applets
;
; ## cu/trcut.x -- tr and cut
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

; A tr SET to a byte list: literals, the escapes cu/fmt-lex.x reads for tr,
; a-z ranges, and the bracket forms -- [:alpha:] and its fellows, [=c=], and
; [c*n] for n copies of c.  The escapes and the brackets are read first, so a
; byte either names is a literal and never a range's dash: `tr '\055' -` is the
; dash itself.
;
; [c*] with no count is one c, which is all it needs to be: a SET2 shorter than
; SET1 already repeats its last byte, which is what the form asks for.
(def %cu-tr-set
  (fn (_ s) (%cu-tr-ranges (%cu-tr-items s 0 ()))))

; the set's bytes before the ranges are filled: (BYTE . WRITTEN-AS-ITSELF?),
; false only for a plain byte, which a dash beside it can span
(def %cu-tr-items
  (fn (self s i acc)
    (if (>= i (byte-len s)) (reverse acc)
      (match
        ((= (byte-at s i) 92)
          (let ((e (%cu-esc-at s i (lit tr))))
            (self s (%cu-nth 1 e)
              (if (< (%cu-nth 3 e) 0) acc
                (pair (pair (%cu-nth 3 e) #t) acc)))))
        ((= (byte-at s i) 91)                                      ; [
          (let ((br (%cu-tr-bracket s i)))
            (if (null? br) (self s (+ i 1) (pair (pair 91 #f) acc))
              (self s (rest br)
                (%cu-tr-marked (first br) acc)))))
        (#t (self s (+ i 1) (pair (pair (byte-at s i) #f) acc)))))))

(def %cu-tr-marked
  (fn (self bs acc)
    (if (null? bs) acc (self (rest bs) (pair (pair (first bs) #t) acc)))))

; The bracket form at I, where S[I] is a [ : (BYTES . NEXT), or nil when what
; is there is not one of the forms and the [ is a byte of its own.
(def %cu-tr-bracket
  (fn (_ s i)
    (let ((close (%cu-tr-find s (+ i 1) 93)))                      ; ]
      (if (< close 0) ()
        (let ((body (substring s (+ i 1) close)))
          (let ((end (byte-len body)))
            (match
              ((< end 2) ())
              ((if (= (byte-at body 0) 58)                         ; [:name:]
                 (= (byte-at body (- end 1)) 58) #f)
                (let ((bs (%cu-tr-class (substring body 1 (- end 1)))))
                  (if (null? bs) () (pair bs (+ close 1)))))
              ((if (= (byte-at body 0) 61)                         ; [=c=]
                 (if (= (byte-at body (- end 1)) 61) (= end 3) #f) #f)
                (pair (list (byte-at body 1)) (+ close 1)))
              ((if (> end 1) (= (byte-at body 1) 42) #f)           ; [c*n]
                (pair (%cu-tr-copies (byte-at body 0)
                        (if (= end 2) 1
                          (%cu-num-prefix (substring body 2 end))))
                  (+ close 1)))
              (#t ()))))))))

(def %cu-tr-find
  (fn (self s i b)
    (match
      ((>= i (byte-len s)) (- 0 1))
      ((= (byte-at s i) b) i)
      (#t (self s (+ i 1) b)))))

(def %cu-tr-copies
  (fn (self b n) (if (< n 1) () (pair b (self b (- n 1))))))

; The bytes of a character class, as the C locale holds them: the classes tr
; names, in byte order.  An unknown name answers nil, which the applet refuses
; before it reads either set.
(def %cu-tr-class
  (fn (_ name)
    (match
      ((string=? name "alpha") (append (%cu-tr-fill 65 90) (%cu-tr-fill 97 122)))
      ((string=? name "digit") (%cu-tr-fill 48 57))
      ((string=? name "alnum")
        (append (%cu-tr-fill 48 57)
          (append (%cu-tr-fill 65 90) (%cu-tr-fill 97 122))))
      ((string=? name "upper") (%cu-tr-fill 65 90))
      ((string=? name "lower") (%cu-tr-fill 97 122))
      ((string=? name "space") (append (%cu-tr-fill 9 13) (list 32)))
      ((string=? name "blank") (list 9 32))
      ((string=? name "print") (%cu-tr-fill 32 126))
      ((string=? name "graph") (%cu-tr-fill 33 126))
      ((string=? name "cntrl") (append (%cu-tr-fill 0 31) (list 127)))
      ((string=? name "xdigit")
        (append (%cu-tr-fill 48 57)
          (append (%cu-tr-fill 65 70) (%cu-tr-fill 97 102))))
      ; the printable bytes that are neither alphanumeric nor a space
      ((string=? name "punct")
        (append (%cu-tr-fill 33 47)
          (append (%cu-tr-fill 58 64)
            (append (%cu-tr-fill 91 96) (%cu-tr-fill 123 126)))))
      (#t ()))))

; the class names a SET names, in order
(def %cu-tr-class-names
  (fn (self s i acc)
    (match
      ((>= (+ i 1) (byte-len s)) (reverse acc))
      ((if (= (byte-at s i) 92) #t #f) (self s (+ i 2) acc))        ; an escape
      ((if (= (byte-at s i) 91) (= (byte-at s (+ i 1)) 58) #f)      ; [:
        (let ((close (%cu-tr-find s (+ i 2) 58)))                   ; :
          (if (< close 0) (reverse acc)
            (self s (+ close 2) (pair (substring s (+ i 2) close) acc)))))
      (#t (self s (+ i 1) acc)))))

; a dash between two bytes, itself written as a dash, spans them
(def %cu-tr-ranges
  (fn (self items)
    (match
      ((null? items) ())
      ((%cu-tr-range? items)
        (append (%cu-tr-fill (first (first items))
                  (first (first (rest (rest items)))))
          (self (rest (rest (rest items))))))
      (#t (pair (first (first items)) (self (rest items)))))))

(def %cu-tr-range?
  (fn (_ items)
    (if (if (pair? (rest items)) (pair? (rest (rest items))) #f)
      (if (= (first (first (rest items))) 45)                    ; -
        (not (rest (first (rest items))))
        #f)
      #f)))

(def %cu-tr-fill
  (fn (self lo hi)
    (if (> lo hi) () (pair lo (self (+ lo 1) hi)))))

(def %cu-member-b?
  (fn (_ b l)
    (def go
      (fn (self es)
        (if (null? es) #f
          (if (= (first es) b) #t (self (rest es))))))
    (go l)))

; -c: every byte NOT in the set, ascending -- the set tr then maps,
; deletes or squeezes in place of the one written.  Walking down from
; 255 and consing at the front leaves it in order.
(def %cu-tr-complement
  (fn (_ set)
    (def go
      (fn (self b acc)
        (if (< b 0) acc
          (self (- b 1) (if (%cu-member-b? b set) acc (pair b acc))))))
    (go 255 ())))

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

; the first class name in SETS that tr does not know, or nil
(def %cu-tr-bad-class
  (fn (self sets)
    (if (null? sets) ()
      (let ((bad (%cu-tr-first-unknown (%cu-tr-class-names (first sets) 0 ()))))
        (if (null? bad) (self (rest sets)) bad)))))

(def %cu-tr-first-unknown
  (fn (self names)
    (if (null? names) ()
      (if (null? (%cu-tr-class (first names))) (first names)
        (self (rest names))))))

; the first class in SET2 that is neither upper nor lower, or nil: a
; translation through any other is refused, as tr refuses it
(def %cu-tr-other-class
  (fn (self names)
    (if (null? names) ()
      (if (%cu-member-s? (first names) (list "upper" "lower"))
        (self (rest names))
        (first names)))))

(def %cu-tr
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "tr" argv))
    (def del? (Opts on? o "-d"))
    (def sq? (Opts on? o "-s"))
    (def args (Opts operands o))
    ; translating wants two SETs, and so does deleting while squeezing;
    ; deleting or squeezing alone wants one
    (if (< (length args) (if del? (if sq? 2 1) (if sq? 1 2)))
      (%cu-tr-few args sq?)
      (%cu-tr-classes o del? args stdin-thunk))))

; too few SETs, in GNU's words; where one was given, a second line says why
; another is wanted
(def %cu-tr-few
  (fn (_ args sq?)
    (do (%cu-missing-operand "tr" args)
        (if (null? args) ()
          (file-write 2
            (if sq?
              "Two strings must be given when both deleting and squeezing repeats.\n"
              "Two strings must be given when translating.\n")))
        1)))

; the SETs' classes checked, then the run
(def %cu-tr-classes
  (fn (_ o del? args stdin-thunk)
    (let ((bad (%cu-tr-bad-class args))
          (other (if (if del? #f (pair? (rest args)))
                   (%cu-tr-other-class
                     (%cu-tr-class-names (first (rest args)) 0 ()))
                   ())))
      (match
        ((not (null? bad))
          (do (file-write 2
                (string-concat
                  (list "tr: invalid character class '" bad "'\n")))
              1))
        ((not (null? other))
          (do (file-write 2
                (string-concat
                  (list "tr: when translating, the only character classes that "
                        "may appear in\nstring2 are 'upper' and 'lower'\n")))
              1))
        (#t (%cu-tr-run o del? (Opts on? o "-s") args stdin-thunk))))))

(def %cu-tr-run
  (fn (_ o del? sq? args stdin-thunk)
    (def set1
      (let ((s (%cu-tr-set (first args))))
        (if (Opts on? o "-c") (%cu-tr-complement s) s)))
    (def set2 (if (null? (rest args)) () (%cu-tr-set (first (rest args)))))
    (def text (stdin-thunk))
    (def end (byte-len text))
    (def squeeze-set (if sq? (if (null? set2) set1 set2) ()))
    ; the bytes are gathered as bytes and written as a run (cu/prims.x), so a
    ; set that names a NUL writes one
    (def go
      (fn (self i acc n prev)
        (if (>= i end) (%cu-run-bytes (reverse acc) n)
          (let ((b (byte-at text i)))
            (if (if del? (%cu-member-b? b set1) #f)
              (self (+ i 1) acc n prev)
              (let ((v (if (null? set2) b (%cu-tr-map set1 set2 b))))
                (if (if sq? (if (= v prev) (%cu-member-b? v squeeze-set) #f) #f)
                  (self (+ i 1) acc n prev)
                  (self (+ i 1) (pair v acc) (+ n 1) v))))))))
    (do (file-write-run 1 (go 0 () 0 (- 0 1))) 0)))

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
        (def g (%cu-gather-said ops stdin-thunk (%cu-says "cut") #f))
        (def lines (%cu-lines (first g)))
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
            (do (%cu-print-lines (map (fn (_ l) (cut-line l)) lines)) (rest g)))
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
                (rest g))))))))


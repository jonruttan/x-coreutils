; # x-coreutils -- the small tools, as applets
;
; ## cu/find.x -- find, the expression walk
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; find belongs to findutils rather than to busybox's coreutils set, so the
; option matrix has no row for it; join is the bundle's other such applet.
; It is here because the build closure reaches for it.
;
; Like test, this is a grammar rather than an option list:
;
;   expr    := term (-o term)*
;   term    := factor (-a? factor)*
;   factor  := ! factor | ( expr ) | PRIMARY
;
; Two factors side by side are joined by -a, which is why the operators have
; to be parsed and cannot be declared.  Where find parts from test is what a
; factor ANSWERS: test evaluates against one path and is finished, find parses
; to a PREDICATE of the entry and applies it at every point of the walk.
; Actions are predicates too -- -print answers true after printing -- which is
; what lets `-name x -o -print` mean what it reads as.
;
; The walk reads lstat, so a symlink is a link and never the thing it names
; (find's own default; -L is not implemented).  -prune, -delete, -depth and
; -xdev are not implemented either: the first three want the walk to carry
; state or to run post-order, and this walk does neither.  Recorded
; divergences, all five.

; --- globs --------------------------------------------------------------------
;
; -name matches a shell glob, not a regex, and the bundle had no matcher.
; * ? [...] with ranges, a leading ! or ^ negating the class, and a backslash
; escaping the next byte.

; [...] from PI, which is just past the '['.  Answers (MATCHED? . PI-AFTER),
; or nil when the class never closes -- an unclosed [ is a literal byte, which
; is what the shells settle on.
(def %cu-glob-class
  (fn (_ pat pi c)
    (def pn (byte-len pat))
    (def neg
      (if (>= pi pn) #f
        (if (= (byte-at pat pi) 33) #t (= (byte-at pat pi) 94))))
    (def go
      (fn (self i hit first?)
        (if (>= i pn) ()
          (let ((b (byte-at pat i)))
            (match
              ; ] closes the class unless it is the very first byte in it
              ((if (= b 93) (not first?) #f)
                (pair (if neg (not hit) hit) (+ i 1)))
              ((%cu-glob-range? pat i pn)
                (self (+ i 3)
                  (if hit #t
                    (if (>= c b) (<= c (byte-at pat (+ i 2))) #f))
                  #f))
              (#t (self (+ i 1) (if hit #t (= c b)) #f)))))))
    (go (if neg (+ pi 1) pi) #f #t)))

; a-z sits at I when a dash follows it and the byte after that is not the
; closer -- `[a-]` is the two literals a and -.
(def %cu-glob-range?
  (fn (_ pat i pn)
    (if (>= (+ i 2) pn) #f
      (if (= (byte-at pat (+ i 1)) 45)
        (not (= (byte-at pat (+ i 2)) 93))
        #f))))

(def %cu-glob?
  (fn (_ pat s)
    (def pn (byte-len pat))
    (def sn (byte-len s))
    (def go
      (fn (self pi si)
        (if (>= pi pn) (>= si sn)
          (let ((p (byte-at pat pi)))
            (match
              ; * takes nothing first, then one more byte at a time
              ((= p 42)
                (if (self (+ pi 1) si) #t
                  (if (>= si sn) #f (self pi (+ si 1)))))
              ((= p 63)
                (if (>= si sn) #f (self (+ pi 1) (+ si 1))))
              ((= p 91)
                (if (>= si sn) #f
                  (let ((r (%cu-glob-class pat (+ pi 1) (byte-at s si))))
                    (if (null? r) #f
                      (if (first r) (self (rest r) (+ si 1)) #f)))))
              ((if (= p 92) (< (+ pi 1) pn) #f)
                (if (>= si sn) #f
                  (if (= (byte-at pat (+ pi 1)) (byte-at s si))
                    (self (+ pi 2) (+ si 1)) #f)))
              (#t
                (if (>= si sn) #f
                  (if (= p (byte-at s si)) (self (+ pi 1) (+ si 1)) #f))))))))
    (go 0 0)))

; --- the pieces a primary asks about -------------------------------------------

(def %find-lower
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i acc)
        (if (>= i end) (string-concat (reverse acc))
          (let ((b (byte-at s i)))
            (self (+ i 1)
              (pair (%cu-b->s (if (if (>= b 65) (<= b 90) #f) (+ b 32) b))
                acc))))))
    (go 0 ())))

(def %find-type-kind
  (fn (_ c)
    (match
      ((string=? c "f") (lit file))
      ((string=? c "d") (lit dir))
      ((string=? c "l") (lit link))
      ((string=? c "b") (lit block))
      ((string=? c "c") (lit char))
      ((string=? c "p") (lit fifo))
      ((string=? c "s") (lit socket))
      (#t (lit unknown)))))

; +N is more than N, -N is fewer, N is exactly N -- find's numeric argument
; everywhere it takes one.
(def %find-num?
  (fn (_ arg v)
    (def end (byte-len arg))
    (if (= end 0) #f
      (let ((lead (byte-at arg 0)))
        (def n (%cu-num-prefix
                 (if (if (= lead 43) #t (= lead 45)) (substring arg 1 end) arg)))
        (match
          ((= lead 43) (> v n))
          ((= lead 45) (< v n))
          (#t (= v n)))))))

; -size counts 512-byte blocks unless a unit says otherwise, and a partial
; block counts as a whole one.
(def %find-size-units
  (fn (_ arg)
    (def end (byte-len arg))
    (if (= end 0) (pair arg 512)
      (let ((last (byte-at arg (- end 1))))
        (match
          ((= last 99) (pair (substring arg 0 (- end 1)) 1))          ; c
          ((= last 107) (pair (substring arg 0 (- end 1)) 1024))      ; k
          ((= last 77) (pair (substring arg 0 (- end 1)) 1048576))    ; M
          ((= last 71) (pair (substring arg 0 (- end 1)) 1073741824)) ; G
          ((= last 98) (pair (substring arg 0 (- end 1)) 512))        ; b
          (#t (pair arg 512)))))))

(def %find-size?
  (fn (_ arg size)
    (let ((u (%find-size-units arg)))
      (def unit (rest u))
      ; round up -- a 1-byte file is one block, as find counts it.  The
      ; remainder comes off first so `/` stays exact and never answers a
      ; rational, which is how ls -h divides too.
      (def blocks
        (if (= unit 1) size
          (let ((c (+ size (- unit 1)))) (/ (- c (% c unit)) unit))))
      (%find-num? (first u) blocks))))

(def %find-empty?
  (fn (_ path st)
    (let ((kind (%cu-stat-get st (lit kind))))
      (match
        ((eq? kind (lit dir)) (null? (%cu-walk-names path)))
        ((eq? kind (lit file)) (= (%cu-stat-get st (lit size)) 0))
        (#t #f)))))

(def %find-mtime-of
  (fn (_ path)
    (let ((st (file-lstat-full path)))
      (if (null? st) (- 0 1) (%cu-stat-get st (lit mtime))))))

; --- -exec --------------------------------------------------------------------
;
; The command runs once per entry and ends at a bare ; -- every {} in it is
; replaced by the path.  +-batching is not implemented (recorded divergence);
; xargs is the tool for that shape and this bundle has one.

(def %find-exec-argv
  (fn (_ cmd path)
    (map (fn (_ a) (if (string=? a "{}") path a)) cmd)))

; the command's words, up to the ; that closes it: (CMD . AFTER), or nil
(def %find-exec-take
  (fn (_ args)
    (def go
      (fn (self xs acc)
        (if (null? xs) ()
          (if (string=? (first xs) ";")
            (pair (reverse acc) (rest xs))
            (self (rest xs) (pair (first xs) acc))))))
    (go args ())))

; --- the grammar ---------------------------------------------------------------
;
; Each of these answers (PREDICATE . REMAINING-ARGS), with nil for the
; predicate when the expression is malformed -- the same shape test's parser
; uses, so the two read alike.

(def %find-bad (fn (_ xs) (pair () xs)))

(def %find-print
  (fn (_ path name depth st)
    (do (display (string-append path "\n")) #t)))

; The primaries that swallow the word after them.  A scan of the expression
; has to know these or it reads an argument as an operator: in
; `find . -name -print` the -print is a pattern, not an action.
(def %find-takes-arg?
  (fn (_ a)
    (match
      ((string=? a "-name") #t)
      ((string=? a "-iname") #t)
      ((string=? a "-path") #t)
      ((string=? a "-type") #t)
      ((string=? a "-size") #t)
      ((string=? a "-newer") #t)
      ((string=? a "-maxdepth") #t)
      ((string=? a "-mindepth") #t)
      (#t #f))))

; find prints when the expression names no action of its own, so `find . -name
; x` means `find . -name x -print`.  Reaching -exec is enough to answer yes:
; whatever follows it is the command's, not ours.
(def %find-action?
  (fn (_ args)
    (def go
      (fn (self xs)
        (if (null? xs) #f
          (let ((a (first xs)))
            (match
              ((string=? a "-exec") #t)
              ((string=? a "-print") #t)
              ((string=? a "-print0") #t)
              ((%find-takes-arg? a)
                (if (null? (rest xs)) #f (self (rest (rest xs)))))
              (#t (self (rest xs))))))))
    (go args)))

(def %find-operator?
  (fn (_ a)
    (match
      ((string=? a "-o") #t)
      ((string=? a "-or") #t)
      ((string=? a "-a") #t)
      ((string=? a "-and") #t)
      ((string=? a ")") #t)
      (#t #f))))

(def %find-expr
  (fn (_ args)
    (def r (%find-term args))
    (def go
      (fn (self p xs)
        (match
          ((null? p) (pair () xs))
          ((null? xs) (pair p xs))
          ((if (string=? (first xs) "-o") #f (not (string=? (first xs) "-or")))
            (pair p xs))
          (#t
            (let ((r2 (%find-term (rest xs))))
              (if (null? (first r2)) (pair () (rest r2))
                (self
                  (let ((l p) (rt (first r2)))
                    (fn (_ path name depth st)
                      (if (l path name depth st) #t (rt path name depth st))))
                  (rest r2))))))))
    (go (first r) (rest r))))

(def %find-term
  (fn (_ args)
    (def r (%find-factor args))
    (def go
      (fn (self p xs)
        (match
          ((null? p) (pair () xs))
          ((null? xs) (pair p xs))
          ; -a is optional: two factors side by side are joined by it, and
          ; anything that is not an operator starts another factor.
          ((%find-operator? (first xs))
            (if (if (string=? (first xs) "-a") #t
                  (string=? (first xs) "-and"))
              (let ((r2 (%find-factor (rest xs))))
                (if (null? (first r2)) (pair () (rest r2))
                  (self (%find-both p (first r2)) (rest r2))))
              (pair p xs)))
          (#t
            (let ((r2 (%find-factor xs)))
              (if (null? (first r2)) (pair () (rest r2))
                (self (%find-both p (first r2)) (rest r2))))))))
    (go (first r) (rest r))))

(def %find-both
  (fn (_ l r)
    (fn (_ path name depth st)
      (if (l path name depth st) (r path name depth st) #f))))

(def %find-factor
  (fn (_ args)
    (if (null? args) (%find-bad args)
      (let ((a (first args)))
        (match
          ((if (string=? a "!") #t (string=? a "-not"))
            (let ((r (%find-factor (rest args))))
              (if (null? (first r)) (%find-bad (rest r))
                (pair
                  (let ((p (first r)))
                    (fn (_ path name depth st) (not (p path name depth st))))
                  (rest r)))))
          ((string=? a "(")
            (let ((r (%find-expr (rest args))))
              (match
                ((null? (first r)) (%find-bad (rest r)))
                ((null? (rest r)) (%find-bad ()))
                ((string=? (first (rest r)) ")") (pair (first r) (rest (rest r))))
                (#t (%find-bad (rest r))))))
          (#t (%find-primary args)))))))

(def %find-primary
  (fn (_ args)
    (def a (first args))
    (def more (rest args))
    (def arg (if (null? more) () (first more)))
    (match
      ((string=? a "-print") (pair %find-print more))
      ((string=? a "-print0")
        (pair (fn (_ path name depth st)
                (do (file-write-field 1 path 0) #t))
          more))
      ((string=? a "-true") (pair (fn (_ path name depth st) #t) more))
      ((string=? a "-false") (pair (fn (_ path name depth st) #f) more))
      ((string=? a "-empty")
        (pair (fn (_ path name depth st) (%find-empty? path st)) more))
      ((string=? a "-exec")
        (let ((taken (%find-exec-take more)))
          (if (null? taken) (%find-bad more)
            (pair
              (let ((cmd (first taken)))
                (fn (_ path name depth st)
                  (= 0 (proc-run (%find-exec-argv cmd path)))))
              (rest taken)))))
      ((null? more) (%find-bad ()))
      ((string=? a "-name")
        (pair (let ((pat arg))
                (fn (_ path name depth st) (%cu-glob? pat name)))
          (rest more)))
      ((string=? a "-iname")
        (pair (let ((pat (%find-lower arg)))
                (fn (_ path name depth st)
                  (%cu-glob? pat (%find-lower name))))
          (rest more)))
      ((string=? a "-path")
        (pair (let ((pat arg))
                (fn (_ path name depth st) (%cu-glob? pat path)))
          (rest more)))
      ((string=? a "-type")
        (pair (let ((k (%find-type-kind arg)))
                (fn (_ path name depth st)
                  (eq? (%cu-stat-get st (lit kind)) k)))
          (rest more)))
      ((string=? a "-size")
        (pair (let ((spec arg))
                (fn (_ path name depth st)
                  (%find-size? spec (%cu-stat-get st (lit size)))))
          (rest more)))
      ((string=? a "-newer")
        (pair (let ((when (%find-mtime-of arg)))
                (fn (_ path name depth st)
                  (> (%cu-stat-get st (lit mtime)) when)))
          (rest more)))
      ; -maxdepth and -mindepth are tested per entry like any other primary;
      ; -maxdepth additionally stops the descent, which the walk reads off the
      ; argument list rather than the predicate.
      ((string=? a "-maxdepth")
        (pair (let ((n (%cu-num-prefix arg)))
                (fn (_ path name depth st) (<= depth n)))
          (rest more)))
      ((string=? a "-mindepth")
        (pair (let ((n (%cu-num-prefix arg)))
                (fn (_ path name depth st) (>= depth n)))
          (rest more)))
      (#t (%find-bad args)))))

; --- the walk ------------------------------------------------------------------

; -maxdepth bounds the DESCENT, not just the test: without reading it here a
; `find . -maxdepth 1` would still walk the whole tree and reject what it
; found.  The value is read straight off the argument list, since the parse
; answers one predicate and cannot report a depth.
(def %find-maxdepth
  (fn (_ args)
    (def go
      (fn (self xs)
        (match
          ((null? xs) (- 0 1))
          ((null? (rest xs)) (- 0 1))
          ((string=? (first xs) "-maxdepth") (%cu-num-prefix (first (rest xs))))
          ((%find-takes-arg? (first xs)) (self (rest (rest xs))))
          (#t (self (rest xs))))))
    (go args)))

(def %find-visit
  (fn (self path name depth pred limit st)
    (do
      (pred path name depth st)
      (if (eq? (%cu-stat-get st (lit kind)) (lit dir))
        (if (if (< limit 0) #t (< depth limit))
          (%find-descend path depth pred limit)
          ())
        ())
      0)))

(def %find-descend
  (fn (_ dir depth pred limit)
    (def go
      (fn (self ns)
        (if (null? ns) 0
          (let ((child (%cu-path-join dir (first ns))))
            (do
              (let ((cst (file-lstat-full child)))
                (if (null? cst) ()
                  (%find-visit child (first ns) (+ depth 1) pred limit cst)))
              (self (rest ns)))))))
    (go (%cu-walk-names dir))))

; --- the applet ----------------------------------------------------------------

(def %cu-find
  (fn (_ argv stdin-thunk)
    ; The operands are the leading words: find takes its paths first and the
    ; expression after them, so the split is at the first dash-word (or at a
    ; ! or a paren, which open an expression too).
    (def split (%find-split argv))
    (def paths (if (null? (first split)) (list ".") (first split)))
    (def expr (rest split))
    (def parsed (if (null? expr) () (%find-expr expr)))
    (match
      ((if (null? expr) #f (null? (first parsed)))
        (do (file-write 2 "find: bad expression\n") 1))
      ((if (null? expr) #f (pair? (rest parsed)))
        (do (file-write 2
              (string-append "find: unexpected: "
                (string-append (first (rest parsed)) "\n")))
            1))
      (#t
        (let ((pred (match
                      ((null? expr) %find-print)
                      ((%find-action? expr) (first parsed))
                      ; no action named: the whole expression gates a print
                      (#t (%find-both (first parsed) %find-print))))
              (limit (%find-maxdepth expr)))
          (def go
            (fn (self ps st)
              (if (null? ps) st
                (let ((p (first ps)))
                  (let ((pst (file-lstat-full p)))
                    (if (null? pst)
                      (do (file-write 2
                            (string-append "find: " (string-append p ": not found\n")))
                          (self (rest ps) 1))
                      (do (%find-visit p (%cu-base-of p) 0 pred limit pst)
                          (self (rest ps) st))))))))
          (go paths 0))))))

; A word starting with a dash opens the expression; so do ! and ( --
; `find ! -name x` has no path at all.
(def %find-expr-word?
  (fn (_ a)
    (match
      ((= (byte-len a) 0) #f)
      ((= (byte-at a 0) 45) #t)
      ((string=? a "!") #t)
      (#t (string=? a "(")))))

; The paths are the words before that one.
(def %find-split
  (fn (_ argv)
    (def go
      (fn (self xs acc)
        (if (null? xs) (pair (reverse acc) ())
          (if (%find-expr-word? (first xs))
            (pair (reverse acc) xs)
            (self (rest xs) (pair (first xs) acc))))))
    (go argv ())))

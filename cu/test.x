; # x-coreutils -- the small tools, as applets
;
; ## cu/test.x -- test, [ and [[ : the whole expression grammar
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox: test EXPR, and the [ / [[ spellings that want a closer.
; This is a GRAMMAR, not an option list -- `-a` and `-o` join terms,
; parentheses group them, and every other dash-word is an operator on
; one or two arguments:
;
;   expr   := term (-o term)*
;   term   := factor (-a factor)*
;   factor := ! factor | ( expr ) | UNARY arg | arg BINARY arg | arg
;
; A bare argument is true when it is not the empty string, which is
; what makes `test "$x"` the idiom it is.
;
; THE PERMISSION TESTS ARE COMPUTED, NOT ASKED.  There is no access(2)
; door, so -r -w -x read the mode against our own ids: the owner
; triple when the uid matches, the group triple when a group does,
; the other triple otherwise.  That is what access answers for an
; ordinary process; it does not model ACLs, and root is not special-
; cased -- both are recorded divergences.

(def %t-stat (fn (_ p) (file-stat-full p)))
(def %t-lstat (fn (_ p) (file-lstat-full p)))

; -f -d -b -c -p -S FOLLOW a symlink, as POSIX says: only -L and -h
; ask about the link itself.  Reading them all off lstat made
; `test -d /tmp` false on a machine where /tmp is a link.
(def %t-kind?
  (fn (_ p k)
    (let ((st (%t-stat p)))
      (if (null? st) #f (eq? (%cu-stat-get st (lit kind)) k)))))

(def %t-link?
  (fn (_ p)
    (let ((st (%t-lstat p)))
      (if (null? st) #f (eq? (%cu-stat-get st (lit kind)) (lit link))))))

(def %t-mode-bit?
  (fn (_ p bit)
    (let ((st (%t-stat p)))
      (if (null? st) #f (not (= 0 (bit-and (%cu-stat-get st (lit mode)) bit)))))))

; the permission triple that applies to US: owner, group, or other
(def %t-permitted?
  (fn (_ p want)
    (let ((st (%t-stat p)))
      (if (null? st) #f
        (let ((mode (%cu-stat-get st (lit mode))))
          (def uid (sys-geteuid))
          (def in-group?
            (let ((go (fn (self gs)
                        (if (null? gs) #f
                          (if (= (first gs) (%cu-stat-get st (lit gid))) #t
                            (self (rest gs)))))))
              (go (sys-getgroups))))
          (def triple
            (if (= uid (%cu-stat-get st (lit uid))) (bit-shr mode 6)
              (if in-group? (bit-shr mode 3) mode)))
          (not (= 0 (bit-and triple want))))))))

(def %t-mtime
  (fn (_ p)
    (let ((st (%t-stat p))) (if (null? st) (- 0 1) (%cu-stat-get st (lit mtime))))))

(def %t-same-file?
  (fn (_ a b)
    (let ((x (%t-stat a)) (y (%t-stat b)))
      (if (null? x) #f
        (if (null? y) #f
          (if (= (%cu-stat-get x (lit dev)) (%cu-stat-get y (lit dev)))
            (= (%cu-stat-get x (lit ino)) (%cu-stat-get y (lit ino)))
            #f))))))

; --- the operators ------------------------------------------------------------

(def %t-unary?
  (fn (_ op)
    (let ((go (fn (self ops)
                (if (null? ops) #f
                  (if (string=? (first ops) op) #t (self (rest ops)))))))
      (go (list "-e" "-f" "-d" "-s" "-z" "-n" "-r" "-w" "-x" "-L" "-h"
                "-b" "-c" "-p" "-S" "-k" "-u" "-g" "-t")))))

(def %t-binary?
  (fn (_ op)
    (let ((go (fn (self ops)
                (if (null? ops) #f
                  (if (string=? (first ops) op) #t (self (rest ops)))))))
      (go (list "=" "==" "!=" "-eq" "-ne" "-lt" "-le" "-gt" "-ge"
                "-nt" "-ot" "-ef")))))

(def %t-unary
  (fn (_ op v)
    (match
      ((string=? op "-e") (file-exists? v))
      ((string=? op "-f") (%t-kind? v (lit file)))
      ((string=? op "-d") (%t-kind? v (lit dir)))
      ((string=? op "-b") (%t-kind? v (lit block)))
      ((string=? op "-c") (%t-kind? v (lit char)))
      ((string=? op "-p") (%t-kind? v (lit fifo)))
      ((string=? op "-S") (%t-kind? v (lit socket)))
      ((string=? op "-L") (%t-link? v))
      ((string=? op "-h") (%t-link? v))
      ((string=? op "-s")
        (let ((st (%t-stat v)))
          (if (null? st) #f (> (%cu-stat-get st (lit size)) 0))))
      ((string=? op "-z") (= (byte-len v) 0))
      ((string=? op "-n") (> (byte-len v) 0))
      ((string=? op "-r") (%t-permitted? v 4))
      ((string=? op "-w") (%t-permitted? v 2))
      ((string=? op "-x") (%t-permitted? v 1))
      ((string=? op "-k") (%t-mode-bit? v 512))       ; sticky
      ((string=? op "-u") (%t-mode-bit? v 2048))      ; setuid
      ((string=? op "-g") (%t-mode-bit? v 1024))      ; setgid
      ((string=? op "-t") (sys-isatty (%cu-num-prefix v)))
      (#t #f))))

(def %t-binary
  (fn (_ a op b)
    (def na (%cu-num-prefix a))
    (def nb (%cu-num-prefix b))
    (match
      ((string=? op "=")   (string=? a b))
      ((string=? op "==")  (string=? a b))
      ((string=? op "!=")  (not (string=? a b)))
      ((string=? op "-eq") (= na nb))
      ((string=? op "-ne") (not (= na nb)))
      ((string=? op "-lt") (< na nb))
      ((string=? op "-le") (<= na nb))
      ((string=? op "-gt") (> na nb))
      ((string=? op "-ge") (>= na nb))
      ((string=? op "-nt") (> (%t-mtime a) (%t-mtime b)))
      ((string=? op "-ot") (< (%t-mtime a) (%t-mtime b)))
      (#t (%t-same-file? a b)))))

; --- the grammar --------------------------------------------------------------
;
; Each level answers (VALUE . REST), with VALUE nil standing for a
; malformed expression -- which the applet reports as status 2 rather
; than as false, because "I could not read this" is not "no".

(def %t-bad (fn (_ rest) (pair () rest)))

(def %t-expr
  (fn (_ args)
    (def r (%t-term args))
    ; the accumulator is NOT called `rest`: that name is the list
    ; function, and shadowing it here made every -a and -o expression
    ; unreadable rather than wrong.
    (def go
      (fn (self v xs)
        (if (null? v) (pair () xs)
          (if (null? xs) (pair v xs)
            (if (not (string=? (first xs) "-o")) (pair v xs)
              (let ((r2 (%t-term (rest xs))))
                (self (if (null? (first r2)) ()
                        (if v #t (first r2)))
                  (rest r2))))))))
    (go (first r) (rest r))))

(def %t-term
  (fn (_ args)
    (def r (%t-factor args))
    ; the accumulator is NOT called `rest`: that name is the list
    ; function, and shadowing it here made every -a and -o expression
    ; unreadable rather than wrong.
    (def go
      (fn (self v xs)
        (if (null? v) (pair () xs)
          (if (null? xs) (pair v xs)
            (if (not (string=? (first xs) "-a")) (pair v xs)
              (let ((r2 (%t-factor (rest xs))))
                (self (if (null? (first r2)) ()
                        (if v (first r2) #f))
                  (rest r2))))))))
    (go (first r) (rest r))))

(def %t-factor
  (fn (_ args)
    (if (null? args) (%t-bad args)
      (let ((a (first args)))
        (if (string=? a "!")
          (let ((r (%t-factor (rest args))))
            (if (null? (first r)) (%t-bad (rest r))
              (pair (not (first r)) (rest r))))
          (if (string=? a "(")
            (let ((r (%t-expr (rest args))))
              (if (null? (first r)) (%t-bad (rest r))
                (if (null? (rest r)) (%t-bad ())
                  (if (string=? (first (rest r)) ")")
                    (pair (first r) (rest (rest r)))
                    (%t-bad (rest r))))))
            ; a unary operator binds tighter than a binary one, but only
            ; when something follows it AND the token after that is not
            ; itself a binary operator (`-n = x` compares the string -n)
            (if (%t-binary-next? args) (%t-binary-factor args)
              (if (if (%t-unary? a) (pair? (rest args)) #f)
                (pair (%t-unary a (first (rest args))) (rest (rest args)))
                (pair (> (byte-len a) 0) (rest args))))))))))

(def %t-binary-next?
  (fn (_ args)
    (if (null? (rest args)) #f
      (%t-binary? (first (rest args))))))

(def %t-binary-factor
  (fn (_ args)
    (if (null? (rest (rest args))) (%t-bad ())
      (pair (%t-binary (first args) (first (rest args))
              (first (rest (rest args))))
        (rest (rest (rest args)))))))

; --- the applets --------------------------------------------------------------

(def %cu-test-eval
  (fn (_ args)
    (if (null? args) 1
      (let ((r (%t-expr args)))
        (if (null? (first r)) 2
          (if (pair? (rest r)) 2
            (if (first r) 0 1)))))))

(def %cu-test
  (fn (_ argv stdin-thunk) (%cu-test-eval argv)))

(def %cu-bracket
  (fn (_ argv stdin-thunk)
    (if (null? argv) 2
      (if (not (string=? (%cu-last argv) "]"))
        (do (file-write 2 "[: missing ]\n") 2)
        (%cu-test-eval (%cu-drop-last argv))))))

(def %cu-dbracket
  (fn (_ argv stdin-thunk)
    (if (null? argv) 2
      (if (not (string=? (%cu-last argv) "]]"))
        (do (file-write 2 "[[: missing ]]\n") 2)
        (%cu-test-eval (%cu-drop-last argv))))))

; # x-coreutils -- the small tools, as applets
;
; ## cu/sha256.x -- SHA-256, and the digest applets' shared driver
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The digest is x/codec/sha256's, read by count through hex-n, so a NUL in
; the input is a byte like any other.
;
; Retires the build's sha256sum/shasum fallback dance (155 calls in
; the measured closure).

(module cu/sha256)

(import cu/cli cu-opts cu-usage)
(import cu/prims byte-at byte-len cu-as-run cu-int->str cu-lines
  cu-max-status file-err-op file-err-text file-or-err file-read-all file-write
  string-append string-concat string=? substring)
(import cu/text cu-each-run-said cu-read-run-said cu-say cu-says)

(import x/codec/sha256)

(def cu-m32 4294967295)

(def cu-hex-digit
  (fn (_ d) (if (< d 10) (+ 48 d) (+ 87 d))))

; TEXT's SHA-256 as hex: TEXT a string, or a run, digested by its count
(def cu-sha256
  (fn (_ text)
    (def run (cu-as-run text))
    (Sha256 hex-n (first run) (rest run))))

; The shared driver, not a second copy: md5sum, sha1sum and sha256sum emit
; through one loop, so a change (like growing -c) reaches all of them.
(def cu-sha256sum
  (fn (_ argv stdin-thunk)
    (cu-sum-applet "sha256sum" (fn (_ t) (cu-sha256 t)) argv stdin-thunk)))

(def %cu-hex=?
  (fn (_ a b)
    (def n (byte-len a))
    (if (not (= n (byte-len b)))
      #f
      (let ((go (fn (self i)
                  (if (>= i n) #t
                    (if (= (%cu-lc-byte (byte-at a i))
                           (%cu-lc-byte (byte-at b i)))
                      (self (+ i 1))
                      #f)))))
        (go 0)))))

; A digest is compared case-insensitively -- a checksum file may spell its hex
; either way -- and only at the comparison, not by lowering the whole string
; first.
(def %cu-lc-byte
  (fn (_ b) (if (if (>= b 65) (<= b 90) #f) (+ b 32) b)))

; The lines of the list SHOWN checked in turn, and what the list comes to.
; Every line counts, a blank one too.  One with no space in it fails, and -w
; says `invalid format` for it, under -s as well.  A listed file that will not
; read is said, and FAILED.  A list where anything failed ends with how many of
; its lines did, unless -s; a list of no lines is said whatever the flags.
; Answers 1 for either, else 0.
(def %cu-sum-check-lines
  (fn (_ name digest shown lines stdin-thunk status? warn?)
    (def says (%cu-sum-says name))
    (def say (fn (_ line) (if status? () (display (string-append line "\n")))))
    (def check
      (fn (self ls total failed)
        (if (null? ls) (list total failed)
          (let ((row (%cu-sum-parse-line (first ls))))
            (if (null? row)
              (do (if warn? (file-write 2 (string-append name ": invalid format\n")) ())
                  (self (rest ls) (+ total 1) (+ failed 1)))
              (let ((text (cu-read-run-said says (rest row) stdin-thunk)))
                (if (if (Err err? text) #f (%cu-hex=? (digest text) (first row)))
                  (do (say (string-append (rest row) ": OK"))
                      (self (rest ls) (+ total 1) failed))
                  (do (say (string-append (rest row) ": FAILED"))
                      (self (rest ls) (+ total 1) (+ failed 1))))))))))
    (def counts (check lines 0 0))
    (def total (first counts))
    (def failed (first (rest counts)))
    (do (if (if status? #t (= failed 0)) ()
          (file-write 2
            (string-concat
              (list name ": WARNING: " (cu-int->str failed) " of " (cu-int->str total)
                    " computed checksums did NOT match\n"))))
        (if (= total 0)
          (file-write 2 (string-concat (list name ": " shown ": no checksum lines found\n")))
          ())
        (if (if (= total 0) #t (> failed 0)) 1 0))))

; -c: each list in turn, `-` for stdin.  A list that will not open is said and
; ends the run, answering 1; one that opens and will not read -- a directory --
; is a list of no lines.  Answers 1 once any list failed.
(def %cu-sum-check-lists
  (fn (self name digest lists stdin-thunk status? warn? st)
    (if (null? lists) st
      (let ((text (if (string=? (first lists) "-") (stdin-thunk)
                    (file-or-err (fn (_) (file-read-all (first lists)))))))
        (if (if (Err err? text) (not (eq? (file-err-op text) (lit read))) #f)
          (do (cu-say (cu-says name) (first lists) text) 1)
          (self name digest (rest lists) stdin-thunk status? warn?
            (cu-max-status st
              (%cu-sum-check-lines name digest (first lists)
                (if (Err err? text) () (cu-lines text)) stdin-thunk
                status? warn?))))))))

; One line of a checksum file -> (DIGEST . NAME), or nil for a line with no
; space in it.  The digest is everything before the first space; one space or
; star after that is the separator, and passed over -- the two spaces these
; tools write, the " *" of a binary read, or no second character at all, as
; coreutils 9.1 writes -- and the rest of the line is the name.
(def %cu-sum-parse-line
  (fn (_ line)
    (def end (byte-len line))
    (def sp
      (let ((go (fn (self i)
                  (match
                    ((>= i end) ())
                    ((= (byte-at line i) #\space) i)
                    (#t (self (+ i 1)))))))
        (go 0)))
    (if (null? sp) ()
      (let ((from (if (< (+ sp 1) end)
                    (let ((c (byte-at line (+ sp 1))))
                      (if (if (= c #\space) #t (= c #\*)) (+ sp 2) (+ sp 1)))
                    (+ sp 1))))
        (pair (substring line 0 sp) (substring line from end))))))

; busybox's words for a file a digest could not read: `can't open 'NAME'` for
; one that would not open, `can't read 'NAME'` for one that opened and would
; not read, as a directory does
(def %cu-sum-says
  (fn (_ applet)
    (fn (_ name err)
      (string-concat
        (list applet
              (if (eq? (file-err-op err) (lit read)) ": can't read '" ": can't open '")
              name "': " (file-err-text err))))))

; -s and -w shape only what -c says: without it busybox refuses them with its
; usage text.  No operand is stdin.
(def cu-sum-applet
  (fn (_ name digest argv stdin-thunk)
    (def o (cu-opts name argv))
    (def ops (if (null? (Opts operands o)) (list "-") (Opts operands o)))
    (def one
      (fn (_ path text)
        (display (string-concat (list (digest text) "  " path "\n")))))
    (match
      ((Opts on? o "-c")
        (%cu-sum-check-lists name digest ops stdin-thunk
          (Opts on? o "-s") (Opts on? o "-w") 0))
      ((if (Opts on? o "-s") #t (Opts on? o "-w")) (cu-usage name))
      (#t (cu-each-run-said ops stdin-thunk (%cu-sum-says name) one 0)))))

(provide cu/sha256 cu-hex-digit cu-m32 cu-sha256 cu-sha256sum cu-sum-applet)

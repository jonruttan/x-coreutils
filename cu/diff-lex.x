; # x-coreutils -- the small tools, as applets
;
; ## cu/diff-lex.x -- what diff calls a line, on a reader base of its own
;
; @description -i, -b and -w ask a LEXICAL question -- which runs of
;   characters are one thing, and which spellings of a thing are the
;   same -- so a tokenizer base answers it instead of a string walk.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; ## WHY A BASE AND NOT A LOOP
;
; diff's comparison flags are not string rewriting, even though string
; rewriting can imitate them.  -w says a run of spaces is NOTHING; -b
; says it is ONE thing however long it ran; -i says two spellings of a
; word are one word.  Those are the three answers a tokenizer gives --
; a negative score, a squeezed token, a folded read -- and the platform
; has a reader that gives them.
;
; The loop this replaces walked every byte of every line in x, per file,
; and carried its own case table because it had no byte->string door.
; Str8 downcase is that door, and the base is the walker.
;
; ## AN ISOLATED BASE, NOT THE SHARED ONE
;
; (Base make-tok) is the bare base with no types on it at all.  A type
; registered on the SHARED base would compete by score with the sexp
; types -- x-ash documents that exact failure -- and diff's idea of a
; word is not the reader's.
;
; ## THE BASE IS PROCESS STATE
;
; It lives on a chain of its own, so a state image cannot carry it: the
; writer images it as nil, and the next read remakes it from the type
; table below.  Registration is write-once per base, so the FLAGS cannot
; be registered in -- they live in cells the handlers read, set before
; each tokenize.

(def %cu-dl-types (pair () ()))     ; ((name . handlers) ...), newest first
(def %cu-dl-type!
  (fn (_ nm hs)
    (set-first! %cu-dl-types (pair (pair nm hs) (first %cu-dl-types)))))

(def %cu-dl-raw (pair () ()))

; The policy, read by the analysers and the read handlers alike.
(def %cu-dl-fold (pair #f ()))      ; -i
(def %cu-dl-squeeze (pair #f ()))   ; -b
(def %cu-dl-strip (pair #f ()))     ; -w

(def %cu-dl-read-string (prim-ref (lit tok) (lit read-str)))
(def %cu-dl-token (prim-ref (lit buf) (lit tok)))

(def %cu-dl-space? (fn (_ c) (if (= c 32) #t (= c 9))))
(def %cu-dl-plain?
  (fn (_ c) (if (%cu-dl-space? c) #f (not (= c 10)))))

; --- CU-WS: a run of spaces and tabs -----------------------------------------
;
; One type, three answers: the run reads as nothing under -w, as a single space
; under -b, and as itself otherwise. A line's tokens concatenate to its normal
; form, so "reads as nothing" is the empty string and the words close up. The
; handler decides all three: a negative-score type with no read handler would
; drop the run (how other bundles discard whitespace), but -b needs a handler
; to answer " ", and a type with a read handler produces its value whatever the
; score.
(def %cu-dl-ws-more ())
(set! %cu-dl-ws-more
  (fn (_ buffer score chr)
    (if (%cu-dl-space? chr)
      %cu-dl-ws-more
      (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))

(def %cu-dl-t-ws
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (%cu-dl-space? chr)
          (%seq (%score-set score 1 buffer) %cu-dl-ws-more)
          ())))
    (pair (lit read)
      (fn (_ . args)
        (if (first %cu-dl-strip) ""
          (if (first %cu-dl-squeeze) " " (%cu-dl-token (first args))))))))
(%cu-dl-type! "CU-WS" %cu-dl-t-ws)

; --- CU-WORD: a run of anything else on the line -----------------------------
;
; -i FOLDS IT AT READ TIME, where the whole token is in hand and the
; platform's Str8 downcase can take it in one call.
(def %cu-dl-word-more ())
(set! %cu-dl-word-more
  (fn (_ buffer score chr)
    (if (%cu-dl-plain? chr)
      %cu-dl-word-more
      (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))

(def %cu-dl-t-word
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (%cu-dl-plain? chr)
          (%seq (%score-set score 1 buffer) %cu-dl-word-more)
          ())))
    (pair (lit read)
      (fn (_ . args)
        (let ((s (%cu-dl-token (first args))))
          (if (first %cu-dl-fold) (Str8 downcase s) s))))))
(%cu-dl-type! "CU-WORD" %cu-dl-t-word)

; --- CU-NL: the line boundary ------------------------------------------------
;
; It reads as a SYMBOL, not as a string, so the grouping below can tell a
; boundary from a line that happens to contain a newline's spelling.
(def %cu-dl-t-nl
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (= chr 10) (%score-set score 1 buffer) ())))
    (pair (lit read) (fn (_ . args) (lit cu-nl)))))
(%cu-dl-type! "CU-NL" %cu-dl-t-nl)

(def %cu-dl-base!
  (fn (_)
    (if (null? (first %cu-dl-raw))
      (let ((b (Base make-tok)))
        (do
          ((fn (self l)
             (if (null? l) ()
               (do (self (rest l))
                   (Base make-type b (first (first l)) (rest (first l))))))
           (first %cu-dl-types))
          (set-first! %cu-dl-raw (Base raw-of b))
          (first %cu-dl-raw)))
      (first %cu-dl-raw))))

; A LINE, from its tokens reversed.
;
; -b IGNORES WHITESPACE AT THE END OF A LINE ENTIRELY, which is not the
; same rule as the one it applies in the middle: "a  " and "a" are the
; same line, while "  a" and "a" are not.  That is a property of the
; LINE and not of the run -- the token cannot know it is last -- so it
; is applied here, where the line is assembled, rather than by teaching
; the read handler to look ahead.  Runs squeeze to one space, so there
; is at most one to drop.
(def %cu-dl-close
  (fn (_ cur)
    (if (first %cu-dl-squeeze)
      (if (null? cur)
        ""
        (if (string=? (first cur) " ")
          (string-concat (reverse (rest cur)))
          (string-concat (reverse cur))))
      (string-concat (reverse cur)))))

; TEXT -> the lines as diff compares them, one string each.
;
; The tokens of a line concatenate to its normal form: under -w the
; whitespace produced nothing and the words close up, under -b each run
; came back as one space, under -i each word came back folded.  Nothing
; here inspects a character.
(def %cu-dl-lines
  (fn (_ text fold? squeeze? strip?)
    (do
      (set-first! %cu-dl-fold fold?)
      (set-first! %cu-dl-squeeze squeeze?)
      (set-first! %cu-dl-strip strip?)
      (let ((end (byte-len text)))
        (let ((src (if (= end 0) text
                    (if (= (byte-at text (- end 1)) 10)
                      text
                      (string-append text "\n")))))
          (if (= (byte-len src) 0) ()
            (let ((toks (%cu-dl-read-string (%cu-dl-base!) src)))
              (let ((go (fn (self l cur acc)
                          (if (null? l)
                            (reverse acc)
                            (if (eq? (first l) (lit cu-nl))
                              (self (rest l) ()
                                (pair (%cu-dl-close cur) acc))
                              (self (rest l) (pair (first l) cur) acc))))))
                (go toks () ())))))))))

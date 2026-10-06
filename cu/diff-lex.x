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
; Str8 downcase is that door, and the lexer is the walker.
;
; ## THE PLATFORM'S LEXER, ITS STATES COMPILED
;
; A line is three kinds of token: a run of spaces and tabs, a run of
; anything else, and the newline that ends it.  x/reader/lexer makes those
; three rules into a tokenizer base whose states run as native code, made on
; the first diff and kept; it rebuilds itself after a state image loads.
;
; THE FLAGS ARE APPLIED HERE, NOT IN THE READER.  The lexer's tokens are the
; text as it stands, and the line assembly below gives each run the answer the
; flags ask for -- nothing under -w, one space under -b, itself otherwise --
; and folds each word under -i.  So one lexer serves every combination, and no
; x code runs inside the tokenizer base.

(import x/reader/lexer)

(def %cu-dl-lexer-cell (pair () ()))
(def %cu-dl-lexer
  (fn (_)
    (if (null? (first %cu-dl-lexer-cell))
      ((fn (_ other)
         (set-first! %cu-dl-lexer-cell
           (Lexer make (list
             (Lexer run (lit ws) " \t" " \t")
             (Lexer table (lit nl) (list "\n"))
             (Lexer run (lit w) other other)))))
       ; every byte but space, tab and newline, high bytes either way the
       ; engine hands them over
       (list (pair 0 8) (pair 11 31) (pair 33 127) (pair 128 255) (pair -128 -1))))
    (first %cu-dl-lexer-cell)))

; A LINE, from its pieces reversed.
;
; -b IGNORES WHITESPACE AT THE END OF A LINE ENTIRELY, which is not the
; same rule as the one it applies in the middle: "a  " and "a" are the
; same line, while "  a" and "a" are not.  That is a property of the
; LINE and not of the run -- the token cannot know it is last -- so it
; is applied here, where the line is assembled.  Runs squeeze to one
; space, so there is at most one to drop.
(def %cu-dl-close
  (fn (_ cur squeeze?)
    (if squeeze?
      (if (null? cur)
        ""
        (if (string=? (first cur) " ")
          (string-concat (reverse (rest cur)))
          (string-concat (reverse cur))))
      (string-concat (reverse cur)))))

; TEXT -> the lines as diff compares them, one string each.
;
; The pieces of a line concatenate to its normal form: under -w a run gives
; nothing and the words close up, under -b each run gives one space.
;
; -i FOLDS THE WHOLE TEXT ONCE, before it is tokenized.  Folding changes no
; space, tab or newline, so the lines of the folded text are the folded
; lines; and Str8 downcase is a class call that allocates by the thousand,
; so once a file beats once a word -- 256 lines of six words folded a word
; at a time cost 3 s and ran a 32-line file's worth of heap into the guard.
(def %cu-dl-lines
  (fn (_ text fold? squeeze? strip?)
    (let ((end (byte-len text)))
      (let ((src ((fn (_ s) (if fold? (Str8 downcase s) s))
                  (if (= end 0) text
                    (if (= (byte-at text (- end 1)) 10)
                      text
                      (string-append text "\n"))))))
        (if (= (byte-len src) 0) ()
          (let ((go (fn (self l cur acc)
                      (if (null? l)
                        (reverse acc)
                        (let ((tag (first (first l))) (tx (first (rest (first l)))))
                          (if (eq? tag (lit nl))
                            (self (rest l) () (pair (%cu-dl-close cur squeeze?) acc))
                            (if (eq? tag (lit ws))
                              (if strip? (self (rest l) cur acc)
                                (self (rest l) (pair (if squeeze? " " tx) cur) acc))
                              (self (rest l) (pair tx cur) acc))))))))
            (go ((%cu-dl-lexer) read-str src) () ())))))))

; # x-coreutils -- the small tools, as applets
;
; ## cu/vi-syntax.x -- vi's syntax colouring
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; With the option syntax (sy) set, the screen is drawn in the colours of the
; grammar x/tool/syntax has for the file's name.  Each row on the screen has a
; row of cells beside its text, one a column: 64 plus the index of the
; column's class, or a space for none (Syntax cells).  A row is written again
; where its text or its cells differ from what the screen shows, an SGR
; sequence before each run of one class and a reset after it.
;
; Busybox's vi has no colour.  The option is off when a run starts, and with
; it off the bytes written are busybox's; :set lists it only while it is on.

(module cu/vi)

(import x/tool/syntax)


(def %vi-cells ())         ; the cell rows as last drawn, beside %vi-screen
(def %vi-cells-screen ())  ; the %vi-screen those cell rows were drawn with
(def %vi-drawn-sy #f)      ; whether the rows were drawn in colour
(def %vi-drawn-theme ())   ; the Theme they were drawn in, nil for none

; The grammar for the file being edited, found again when the name changes.
(def %vi-grammar-name ())
(def %vi-grammar ())

; A run starts in the theme the user's theme file names, whatever an earlier
; run set with :set theme=NAME.
(def %vi-syntax-init!
  (fn (_)
    (set! %vi-cells ())
    (set! %vi-cells-screen ())
    (set! %vi-drawn-sy #f)
    (set! %vi-drawn-theme ())
    (set! %vi-grammar-name ())
    (set! %vi-grammar ())
    (Theme forget!)))

; Whether the colours on the screen are not the ones SY would draw: syntax
; turned on or off, or the theme changed.
(def %vi-colours-stale?
  (fn (_ sy)
    (match
      ((null? sy) %vi-drawn-sy)
      ((not %vi-drawn-sy) #t)
      (#t (not (eq? %vi-drawn-theme (Theme current)))))))

; the grammar to draw with, or nil when the option is off or none is the
; file's
(def %vi-syntax
  (fn (_)
    (match
      ((not (%vi-opt? %vi-sy)) ())
      ((null? %vi-filename) ())
      ((eq? %vi-filename %vi-grammar-name) %vi-grammar)
      (#t (do (set! %vi-grammar-name %vi-filename)
              (set! %vi-grammar (Syntax for-file %vi-filename))
              %vi-grammar)))))

; --- the cells --------------------------------------------------------------

; The cells of the screen's bytes, from the top of the screen to the end of
; its last line, and where they start.
(def %vi-region-cells "")
(def %vi-region-at 0)

(def %vi-region!
  (fn (_ g)
    (def top %vi-screenbegin)
    (def end (vi-min (vi+ (%vi-end-screen) 1) %vi-end))
    (def len (vi-max 0 (vi- end top)))
    (set! %vi-region-at top)
    (set! %vi-region-cells
      (if (= len 0) "" (Syntax cells (g spans %vi-text top len %vi-end) top len)))))

; The cells of the row the line at SRC shows, as %vi-format-line lays out its
; text: a byte's cell for each column it shows in, from the column
; %vi-offset, COLUMNS of them.
(def %vi-format-cells
  (fn (_ src)
    (def shown
      (if (vi< src %vi-end)
        (%vi-shown-cells src (vi+ %vi-offset %vi-columns))
        ""))
    (def len (byte-len shown))
    (def row
      (if (vi< %vi-offset len)
        (vi-bsub shown %vi-offset (vi-min %vi-columns (vi- len %vi-offset)))
        ""))
    (def short (vi- %vi-columns (byte-len row)))
    (if (vi< 0 short) (string-append row (%vi-spaces short)) row)))

(def %vi-shown-cells
  (fn (_ src lim)
    (def pieces (%vi-cells-from src 0 lim ()))
    (if (null? pieces) "" (%str-concat (reverse pieces)))))

; %vi-shown-from's walk: a run of plain bytes takes its cells as they are, a
; tab or a control byte its one cell for each column it shows in
(def %vi-cells-from
  (fn (self a co lim acc)
    (def q (vi-min (%vi-plain-end a) %vi-end))
    (def n (vi-min (vi- q a) (vi- lim co)))
    (def acc2 (if (vi< 0 n) (pair (%vi-cells-at a n) acc) acc))
    (def co2 (vi+ co n))
    (def c (byte-at %vi-text q))
    (match
      ((if (vi< co2 lim) #f #t) acc2)
      ((= c #\newline) acc2)
      ((if (vi< q %vi-end) #f #t) acc2)
      (#t (let ((w (byte-len (%vi-shown-byte c co2))))
            (self (vi+ q 1) (vi+ co2 w) lim
              (pair (%vi-cell-run (%vi-cells-at q 1) w) acc2)))))))

; the N cells of the bytes at P, spaces for any outside the region
(def %vi-cells-at
  (fn (_ p n)
    (def i (vi- p %vi-region-at))
    (if (if (vi< i 0) #f (vi< (vi+ i (vi- n 1)) (byte-len %vi-region-cells)))
      (vi-bsub %vi-region-cells i n)
      (%vi-spaces n))))

(def %vi-cell-run
  (fn (self cell w)
    (if (vi< w 2) cell (string-append cell (self cell (vi- w 1))))))

; --- drawing ----------------------------------------------------------------

; busybox's refresh, a row at a time, with each row's cells: what differs in
; the text or the cells, from the first differing column to the last, or all
; of it when forced.  Answers the rows, and leaves their cells in %vi-cells.
(def %vi-refresh-rows-sy
  (fn (_ g force)
    (%vi-region! g)
    (def olds (if (eq? %vi-screen %vi-cells-screen) %vi-cells ()))
    (def r (%vi-rows-sy %vi-screenbegin 0 %vi-screen olds force () ()))
    (set! %vi-cells (rest r))
    (first r)))

(def %vi-rows-sy
  (fn (self tp li old oldc force acc accc)
    (if (vi< li (vi- %vi-rows 1))
      (let ((row (%vi-format-line tp)) (cells (%vi-format-cells tp)))
        (%vi-row-drawn-sy li row cells old (if (null? oldc) () (first oldc)) force)
        (self (%vi-row-next tp) (vi+ li 1) (if (null? old) () (rest old))
          (if (null? oldc) () (rest oldc)) force (pair row acc) (pair cells accc)))
      (pair (reverse acc) (reverse accc)))))

(def %vi-row-drawn-sy
  (fn (_ li row cells old oldc force)
    (def oc (if (null? oldc) (%vi-spaces %vi-columns) oldc))
    (def last (vi- (byte-len row) 1))
    (match
      ((if force #t (null? old)) (%vi-span-sy li row cells 0 last))
      ((string=? row (first old))
        (if (string=? cells oc) ()
          (%vi-span-sy li row cells (%vi-first-diff cells oc 0) (%vi-last-diff cells oc last))))
      ((string=? cells oc)
        (%vi-span-sy li row cells (%vi-first-diff row (first old) 0) (%vi-last-diff row (first old) last)))
      (#t (%vi-span-sy li row cells
            (vi-min (%vi-first-diff row (first old) 0) (%vi-first-diff cells oc 0))
            (vi-max (%vi-last-diff row (first old) last) (%vi-last-diff cells oc last)))))))

(def %vi-span-sy
  (fn (_ li row cells cs ce)
    (%vi-place-cursor li cs)
    (%vi-put-runs row cells cs (vi+ ce 1))))

; the columns [I, E) of ROW, each run of one class in its sequence and a reset
(def %vi-put-runs
  (fn (self row cells i e)
    (if (vi< i e)
      (let ((j (%vi-run-end cells (byte-at cells i) (vi+ i 1) e)))
        (def text (vi-bsub row i (vi- j i)))
        (def sgr (if (= (byte-at cells i) #\space) "" (Syntax sgr (Syntax cell-class (byte-at cells i)))))
        (%vi-put (if (= (byte-len sgr) 0) text (string-append sgr text %vi-sgr-reset)))
        (self row cells j e))
      ())))

(def %vi-run-end
  (fn (self cells c i e)
    (if (if (vi< i e) (= (byte-at cells i) c) #f) (self cells c (vi+ i 1) e) i)))

(def %vi-sgr-reset (string-append %vi-esc "[0m"))

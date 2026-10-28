# @weight 1

vi's syntax option, x's own: with `:set syntax` (`sy`) the rows are drawn in
the colours of the grammar x/tool/syntax has for the file's name.  Busybox's
vi has no colour, so every case here is x's.  Each case types keys at the
editor through `vi-typed` into a window 6 rows by 30 columns, and shows the
rows as drawn, each with its cells beside it -- a class byte a column, a space
for none, as `(Syntax cells)` makes them -- and the bottom line.  `colours`
counts the SGR sequences drawn that are not resets.

## the fixtures

### a typist for vi

```cu
(def vi-state (fn (_ name) (eval name (module cu/vi))))
; the user's theme file is not read: every case draws in the default theme
(Sys setenv "X_THEME" "")
(def esc (bytes->str (list 27)))
(def cr (bytes->str (list 13)))
(def vi-trim
  (fn (self s)
    (if (if (< 0 (byte-len s)) (= (byte-at s (- (byte-len s) 1)) #\space) #f)
      (self (substring s 0 (- (byte-len s) 1)))
      s)))
(def vi-sgrs-in
  (fn (self s i n)
    (if (< (+ i 2) (byte-len s))
      (self s (+ i 1)
        (if (if (= (byte-at s i) #\escape)
              (if (= (byte-at s (+ i 1)) #\[)
                (if (= (byte-at s (+ i 2)) #\0) #f (string=? (vi-sgr-tail s (+ i 2)) "m")) #f) #f)
          (+ n 1) n))
      n)))
; the byte that ends the sequence at I: digits and ; are passed over
(def vi-sgr-tail
  (fn (self s i)
    (if (< i (byte-len s))
      (let ((c (byte-at s i)))
        (if (if (= c #\;) #t (if (< c #\0) #f (< c #\:))) (self s (+ i 1)) (substring s i (+ i 1))))
      "")))
(def vi-case
  (fn (_ name text bursts . cols)
    (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-vsy && mkdir -p /tmp/x-cu-vsy"))
    (def path (string-append "/tmp/x-cu-vsy/" name))
    (def fd (File open path (list (lit wronly) (lit creat) (lit trunc)) 420))
    (File write fd text (byte-len text))
    (File close fd)
    (vi-typed (list path) bursts 6 (if (null? cols) 30 (first cols)))
    (def cells (vi-state (lit %vi-cells)))
    (display
      (string-concat
        (list
          (string-concat
            (List map
              (fn (_ r) (string-append "|" (vi-trim r) "\n"))
              (vi-state (lit %vi-screen))))
          (if (null? cells) "no cells\n"
            (string-concat (List map (fn (_ c) (string-append ":" (vi-trim c) "\n")) cells)))
          "status " (vi-trim (vi-state (lit %vi-bottom))) "\n"
          "colours " (cu-int->str (List fold (fn (_ n d) (vi-sgrs-in d 0 n)) 0 (vi-state (lit %vi-drawn)))) "\n")))))
(display "made")
```
---
    made

## :set syntax

### an x file is coloured by x-lang's grammar

`(` and `)` are punct (J), `def` a keyword (E), `x` a name (I), `1` a number
(D) and the comment A.  Punct is drawn plain, so four runs take a colour.

```cu
(vi-case "f.x" "(def x 1) ; c\n" (list (string-append ":set sy" cr)))
```
---
```output
|(def x 1) ; c
|~
|~
|~
|~
:JEEE I DJ AAA
:
:
:
:
status - /tmp/x-cu-vsy/f.x 1/1 100%
colours 4
```

### a file no grammar is for is drawn plain

```cu
(vi-case "f.txt" "(def x 1)\n" (list (string-append ":set sy" cr)))
```
---
```output
|(def x 1)
|~
|~
|~
|~
no cells
status - /tmp/x-cu-vsy/f.txt 1/1 100%
colours 0
```

### the option is off when a run starts

```cu
(vi-case "f.x" "(def x 1)\n" (list "l"))
```
---
```output
|(def x 1)
|~
|~
|~
|~
no cells
status - /tmp/x-cu-vsy/f.x 1/1 100%
colours 0
```

### nosyntax draws the rows plain again

The three colours are the draw before `:set nosy`.

```cu
(vi-case "f.x" "(def x 1)\n" (list (string-append ":set sy" cr) (string-append ":set nosy" cr)))
```
---
```output
|(def x 1)
|~
|~
|~
|~
no cells
status - /tmp/x-cu-vsy/f.x 1/1 100%
colours 3
```

### :set lists syntax only while it is on

```cu
(vi-case "f.x" "x\n" (list (string-append ":set sy" cr) (string-append ":set" cr)) 80)
```
---
```output
|x
|~
|~
|~
|~
:I
:
:
:
:
status noautoindent noexpandtab noflash noignorecase noshowmatch tabstop=8 syntax
colours 3
```

## :set theme

### theme=NAME draws the screen again in that theme

The theme draws keywords bold and nothing else, so after the first draw's
four runs the screen is drawn again with one; the bold :set line is two more.

```cu
(Theme register! (Theme make 'spec-mono '((keyword (bold) () ()))))
(vi-case "f.x" "(def x 1) ; c\n"
  (list (string-append ":set sy" cr) (string-append ":set theme=spec-mono" cr)
        (string-append ":set" cr))
  100)
```
---
```output
|(def x 1) ; c
|~
|~
|~
|~
:JEEE I DJ AAA
:
:
:
:
status noautoindent noexpandtab noflash noignorecase noshowmatch tabstop=8 syntax theme=spec-mono
colours 7
```

### a run starts in the user's theme again

:set names the theme only when it is not the default.

```cu
(vi-case "f.x" "x\n" (list (string-append ":set sy" cr) (string-append ":set" cr)) 100)
```
---
```output
|x
|~
|~
|~
|~
:I
:
:
:
:
status noautoindent noexpandtab noflash noignorecase noshowmatch tabstop=8 syntax
colours 3
```

### a theme no one knows, or theme with no name, is a bad option

```cu
(vi-case "f.x" "x\n" (list (string-append ":set theme=nope" cr)))
(vi-case "f.x" "x\n" (list (string-append ":set notheme" cr)))
```
---
```output
|x
|~
|~
|~
|~
no cells
status bad option: theme=nope
colours 2
|x
|~
|~
|~
|~
no cells
status bad option: notheme
colours 2
```

## Colours follow the text

### a string opened above the screen colours its top

The top of the screen is inside the string; the grammar reads from the line
that opens the form.

```cu
(vi-case "f.x" "(def s \"a\nb\nc\nd\ne\nf\ng\nh\")\n(f)\n"
  (list (string-append ":set sy" cr) "8G"))
```
---
```output
|f
|g
|h")
|(f)
|~
:B
:B
:BBJ
:JIJ
:
status - /tmp/x-cu-vsy/f.x 8/9 88%
colours 11
```

### an edit recolours the line

A `;` typed after `def` makes the rest of the line a comment, and only that
part of the row is drawn again.

```cu
(vi-case "f.x" "(def x 1)\n" (list (string-append ":set sy" cr) "5|i;" esc))
```
---
```output
|(def; x 1)
|~
|~
|~
|~
:JEEEAAAAAA
:
:
:
:
status - /tmp/x-cu-vsy/f.x [Modified]
colours 4
```

### a tab's columns take its byte's class

```cu
(vi-case "f.x" "\"a\tb\"\n" (list (string-append ":set sy" cr)))
```
---
```output
|"a      b"
|~
|~
|~
|~
:BBBBBBBBBB
:
:
:
:
status - /tmp/x-cu-vsy/f.x 1/1 100%
colours 1
```

### moving the cursor draws no row again

```cu
(vi-case "f.x" "(f x)\n" (list (string-append ":set sy" cr) "l" "l" "0"))
```
---
```output
|(f x)
|~
|~
|~
|~
:JI IJ
:
:
:
:
status - /tmp/x-cu-vsy/f.x 1/1 100%
colours 2
```

### an empty colon command draws no row again

```cu
(vi-case "f.x" "(f x)\n" (list (string-append ":set sy" cr) (string-append ":" cr)))
```
---
```output
|(f x)
|~
|~
|~
|~
:JI IJ
:
:
:
:
status - /tmp/x-cu-vsy/f.x 1/1 100%
colours 2
```

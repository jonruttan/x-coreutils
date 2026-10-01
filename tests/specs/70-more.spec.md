# @weight 1

busybox's more (util-linux/more.c), clear and reset.  With standard output not
a terminal more is cat.  On one, it reads its keys from the terminal and pages
a byte at a time: a tab to the next stop of eight, a line wider than the window
folded, and `--More--` asked once the window's height less one is full -- with
`(P% of S bytes)` for a file, P the bytes read so far over a hundredth of S, a
hundredth that is 1 below a hundred bytes.  Space shows a page, Enter a line,
r the rest, q (or Q) quits; any other key is told those four.  Each key first
erases what was asked: a carriage return, as many spaces, a carriage return.
A file's lines start a page of their own count; there is no prompt between
two files.

The paging runs through %more-typed: the keys typed, the window's rows and
columns, and what was written to the screen.  A carriage return shows as
`<CR>`, an escape as `<ESC>`, and `|` marks the end of what was written.
busybox's more reads keys from the terminal for ever; here the end of the
typed keys ends the paging.

## the fixtures

### files, a run of the pager, and a run of an applet with what it writes

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-mp && mkdir -p /tmp/x-cu-mp && printf '1\\n2\\n3\\n4\\n5\\n' > /tmp/x-cu-mp/n && printf '1\\n2\\n3\\n4\\n5\\n6\\n7\\n8\\n' > /tmp/x-cu-mp/e && printf 'abcdefg\\nh\\n' > /tmp/x-cu-mp/w && printf 'a\\tb\\n' > /tmp/x-cu-mp/t && printf '1\\n2\\n' > /tmp/x-cu-mp/a && printf '3\\n4\\n' > /tmp/x-cu-mp/b && for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do echo abcdefghi; done > /tmp/x-cu-mp/big")) (def mp (fn (_ n) (string-append "/tmp/x-cu-mp/" n))) (def mp-cr (bytes->str (list #\return))) (def mp-esc (bytes->str (list #\escape))) (def mp-show (fn (_ r) (string-append (%cu-int->str (first r)) "\n" (Str8 replace mp-cr "<CR>" (rest r)) "|"))) (def mp-page (fn (_ argv stdin keys rows cols) (display (mp-show (%more-typed argv stdin keys rows cols))))) (def mp-run (fn (_ argv) (do (sys-dup2 1 9) (let ((oo (file-open-write (mp ".out")))) (do (sys-dup2 oo 1) (def st (cu-run argv "")) (sys-dup2 9 1) (file-close oo) (display (string-concat (list (Str8 replace mp-esc "<ESC>" (file-read-all (mp ".out"))) "|\nstatus " (%cu-int->str st))))))))) (display "made"))
```
---
    made

## paging

### a page, then Space for the next

The window is 4 rows, so a page is 3 lines.  The prompt comes as the fourth
line's first byte is read, the seventh of the file's ten.

```cu
(mp-page (list (mp "n")) "" " " 4 10)
```
---
```output
0
1
2
3
--More-- (7% of 10 bytes)<CR>                         <CR>4
5
|
```

### at a hundred bytes and more, the share is of a hundredth of the size

300 bytes, so a hundredth is 3: the prompt comes at the 31st byte.

```cu
(mp-page (list (mp "big")) "" "q" 4 10)
```
---
```output
0
abcdefghi
abcdefghi
abcdefghi
--More-- (10% of 300 bytes)<CR>                           <CR>|
```

### q quits at the prompt, and so does Q

```cu
(do (mp-page (list (mp "n")) "" "q" 4 10) (newline) (mp-page (list (mp "n")) "" "Q" 4 10))
```
---
```output
0
1
2
3
--More-- (7% of 10 bytes)<CR>                         <CR>|
0
1
2
3
--More-- (7% of 10 bytes)<CR>                         <CR>|
```

### Enter shows one more line and asks again

```cu
(mp-page (list (mp "n")) "" (bytes->str (list #\return)) 4 10)
```
---
```output
0
1
2
3
--More-- (7% of 10 bytes)<CR>                         <CR>4
--More-- (9% of 10 bytes)<CR>                         <CR>|
```

### Space asks again a page on; r shows the rest without asking

```cu
(do (mp-page (list (mp "e")) "" " " 4 10) (newline) (mp-page (list (mp "e")) "" "r" 4 10))
```
---
```output
0
1
2
3
--More-- (7% of 16 bytes)<CR>                         <CR>4
5
6
--More-- (13% of 16 bytes)<CR>                          <CR>|
0
1
2
3
--More-- (7% of 16 bytes)<CR>                         <CR>4
5
6
7
8
|
```

### any other key is told the four, and the next key erases that too

```cu
(mp-page (list (mp "n")) "" "x " 4 10)
```
---
```output
0
1
2
3
--More-- (7% of 10 bytes)<CR>                         <CR>(Enter:next line Space:next page Q:quit R:show the rest)<CR>                                                        <CR>4
5
|
```

### Ctrl-C ends the paging with status 1

```cu
(mp-page (list (mp "n")) "" (bytes->str (list 3)) 4 10)
```
---
```output
1
1
2
3
--More-- (7% of 10 bytes)<CR>                         <CR>|
```

## the screen

### a line wider than the window is folded by the terminal, and counts as a line

Four columns, three rows: `abcd` and `efg` are two lines, so the prompt comes
before `h`.

```cu
(mp-page (list (mp "w")) "" " " 3 4)
```
---
```output
0
abcdefg
--More-- (9% of 10 bytes)<CR>                         <CR>h
|
```

### a tab goes out as spaces to the next stop of eight

```cu
(mp-page (list (mp "t")) "" "" 10 20)
```
---
```output
0
a       b
|
```

### standard input has no size to say

```cu
(mp-page () "1\n2\n3\n4\n" "q" 4 10)
```
---
```output
0
1
2
3
--More-- <CR>         <CR>|
```

### each file starts its own count, and a file that will not open is passed

```cu
(do (mp-page (list (mp "a") (mp "b")) "" "" 3 10) (newline) (mp-page (list (mp "nope") (mp "n")) "" "" 10 10))
```
---
```output
0
1
2
3
4
|
0
1
2
3
4
5
|
```

## not a terminal

### more is cat, and a file that will not open fails it

```cu
(do (mp-run (list "more" (mp "n"))) (newline) (mp-run (list "more" (mp "nope") (mp "a"))))
```
---
```output
1
2
3
4
5
|
status 0
1
2
|
status 1
```

## clear and reset

### clear homes the cursor and clears the screen; reset writes nothing to a pipe

```cu
(do (mp-run (list "clear")) (newline) (mp-run (list "reset")) (newline) (mp-run (list "clear" "-x" "y")))
```
---
```output
<ESC>[H<ESC>[J|
status 0
|
status 0
<ESC>[H<ESC>[J|
status 0
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-mp")) (display "clean"))
```
---
    clean

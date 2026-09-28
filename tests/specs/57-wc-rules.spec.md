# @weight 1

What wc counts as a word and how wide it measures a line, as GNU's wc does in
the C locale.  A space, a tab, a newline, a vertical tab, a form feed, a
carriage return and a no-break space (160) end a word, and every other byte
is in one -- a NUL, a byte past 126, a control character.  For -L, a tab moves the width on to the next
stop of 8, a printable byte moves it by one and any other byte not at all,
and a carriage return and a form feed end the width as a newline does.  The
expected output is GNU's wc's for the same files.

## the files

### separators, bytes that do not print, tabs, and a NUL

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-wcr && mkdir -p /tmp/x-cu-wcr && cd /tmp/x-cu-wcr && printf 'a\\rb\\nab\\rc\\nabc\\fd\\na\\vb\\n' > seps && printf '\\001\\002 a\\001b \\377\\n' > unprint && printf 'a\\tb\\n\\tx\\nabcdefgh\\ty\\n' > tabs && printf 'x\\000y z\\n' > nul && printf 'a\\240b \\240c\\240\\n' > nbsp")) (display (map (fn (_ n) (%cu-stat-get (file-stat-full (string-append "/tmp/x-cu-wcr/" n)) (lit size))) (list "seps" "unprint" "tabs" "nul" "nbsp"))))
```
---
    (19 9 18 6 8)

## the counts

### lines, words and bytes, and words with the longest line

```cu
(do (cu-run (list "wc" "/tmp/x-cu-wcr/seps") "") (cu-run (list "wc" "-w" "-L" "/tmp/x-cu-wcr/seps") "") (cu-run (list "wc" "/tmp/x-cu-wcr/unprint") "") (cu-run (list "wc" "-w" "-L" "/tmp/x-cu-wcr/unprint") "") (cu-run (list "wc" "/tmp/x-cu-wcr/tabs") "") (cu-run (list "wc" "-w" "-L" "/tmp/x-cu-wcr/tabs") "") (cu-run (list "wc" "/tmp/x-cu-wcr/nul") "") (cu-run (list "wc" "-w" "-L" "/tmp/x-cu-wcr/nul") "") (cu-run (list "wc" "/tmp/x-cu-wcr/nbsp") "") (cu-run (list "wc" "-w" "-L" "/tmp/x-cu-wcr/nbsp") "") (display ""))
```
---
```output
 4  8 19 /tmp/x-cu-wcr/seps
 8  3 /tmp/x-cu-wcr/seps
1 3 9 /tmp/x-cu-wcr/unprint
3 4 /tmp/x-cu-wcr/unprint
 3  5 18 /tmp/x-cu-wcr/tabs
 5 17 /tmp/x-cu-wcr/tabs
1 2 6 /tmp/x-cu-wcr/nul
2 4 /tmp/x-cu-wcr/nul
1 3 8 /tmp/x-cu-wcr/nbsp
3 4 /tmp/x-cu-wcr/nbsp
```

### the longest line of two files, and of their total

```cu
(do (cu-run (list "wc" "-L" "/tmp/x-cu-wcr/seps" "/tmp/x-cu-wcr/tabs") "") (display ""))
```
---
```output
 3 /tmp/x-cu-wcr/seps
17 /tmp/x-cu-wcr/tabs
17 total
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-wcr")) (display "clean"))
```
---
    clean

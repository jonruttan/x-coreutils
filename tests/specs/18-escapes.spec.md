# @weight 2

The backslash escapes printf, echo -e and tr read, and printf's conversions.
The expected bytes are the GNU tools' for the same arguments, shown as the hex
od prints so a byte is checked by a tool outside this bundle.

The three tools differ where their manuals differ: printf's format takes \NNN
as up to three octal digits and \" as a quote, echo -e and printf's %b take the
leading 0 as well (\0NNN), and tr takes neither \x nor \e and drops the
backslash from an escape it does not know.

An escape naming NUL is dropped: a string's length stops at its first NUL, so
`printf '\0'` writes nothing where GNU writes the byte (the limit the README
records).

## the fixtures

### a scratch directory, and a reader for output as hex

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-esc && mkdir -p /tmp/x-cu-esc")) (def hx (fn (_ argv input) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((o (file-open-write "/tmp/x-cu-esc/.out")) (e (file-open-write "/tmp/x-cu-esc/.err"))) (do (sys-dup2 o 1) (sys-dup2 e 2) (def hx-st (cu-run argv input)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close o) (file-close e) (proc-run (list "/bin/sh" "-c" "od -An -tx1 -v /tmp/x-cu-esc/.out | tr -s ' \\n' ' ' | sed 's/^ //; s/ $//' > /tmp/x-cu-esc/.hex")) (display (file-read-all "/tmp/x-cu-esc/.hex")) (display " | ") (display (file-read-all "/tmp/x-cu-esc/.err")) (display "status ") (display hx-st) (newline)))))) (display "made"))
```
---
    made

## printf's format

### the named escapes

```cu
(do (hx (list "printf" "\\a\\b\\f\\v") "") (hx (list "printf" "\\n\\r\\t") "") (hx (list "printf" "\\\\\\\"") "") (hx (list "printf" "\\e") ""))
```
---
```output
07 08 0c 0b | status 0
0a 0d 09 | status 0
5c 22 | status 0
1b | status 0
```

### a number: up to three octal digits, or x and up to two hex digits

```cu
(do (hx (list "printf" "\\101\\1") "") (hx (list "printf" "\\0101") "") (hx (list "printf" "\\x41\\x4") "") (hx (list "printf" "\\x411") ""))
```
---
```output
41 01 | status 0
08 31 | status 0
41 04 | status 0
41 31 | status 0
```

### an escape printf does not know keeps its backslash, and \c ends the output

```cu
(do (hx (list "printf" "\\q\\8") "") (hx (list "printf" "\\xZ") "") (hx (list "printf" "a\\cb") ""))
```
---
```output
5c 71 5c 38 | status 0
5c 78 5a | status 0
61 | status 0
```

## printf's conversions

### %b reads its argument's escapes, with the leading 0 its manual spells

```cu
(do (hx (list "printf" "%b" "\\101\\0101") "") (hx (list "printf" "%b%b" "\\a" "\\x41") "") (hx (list "printf" "%b" "x\\cy") "") (hx (list "printf" "%b" "\\q") ""))
```
---
```output
41 41 | status 0
07 41 | status 0
78 | status 0
5c 71 | status 0
```

### %i and %u read a number as %d does, and %X spells hex in capitals

```cu
(do (hx (list "printf" "%i:%u:%d" "5" "6" "7") "") (hx (list "printf" "%x:%X" "255" "255") ""))
```
---
```output
35 3a 36 3a 37 | status 0
66 66 3a 46 46 | status 0
```

### a conversion printf does not read is refused by name

```cu
(do (hx (list "printf" "%z" "5") "") (hx (list "printf" "a%") "") (hx (list "printf" "%5") ""))
```
---
```output
 | printf: %z: invalid conversion specification
status 1
61 | printf: %: invalid conversion specification
status 1
 | printf: %5: invalid conversion specification
status 1
```

## echo -e

### the same escapes, with the leading 0, and \c ending the line as well as the output

```cu
(do (hx (list "echo" "-e" "\\a\\e\\v") "") (hx (list "echo" "-e" "\\0101\\101") "") (hx (list "echo" "-e" "\\x41\\x4") "") (hx (list "echo" "-e" "\\q") "") (hx (list "echo" "-e" "a\\cb") "") (hx (list "echo" "\\n\\t") ""))
```
---
```output
07 1b 0b 0a | status 0
41 41 0a | status 0
41 04 0a | status 0
5c 71 0a | status 0
61 | status 0
5c 6e 5c 74 0a | status 0
```

## tr

### a tr SET reads \NNN and the named escapes, and drops the backslash from the rest

tr has no \x and no \e, so those are the letters themselves.

```cu
(do (hx (list "tr" "X" "\\101") "aXb\n") (hx (list "tr" "X" "\\a") "aXb\n") (hx (list "tr" "X" "\\e") "aXb\n") (hx (list "tr" "X" "\\x41") "aXb\n") (hx (list "tr" "X" "\\q") "aXb\n"))
```
---
```output
61 41 62 0a | status 0
61 07 62 0a | status 0
61 65 62 0a | status 0
61 78 62 0a | status 0
61 71 62 0a | status 0
```

### three octal digits past 255 are read as two, and an escaped byte is never a range's dash

A dash written as \055 between two bytes is a third byte, where a dash itself
spans them.

```cu
(do (hx (list "tr" "X" "\\400") "aXb\n") (hx (list "tr" "a\\055c" "xyz") "a-cb\n") (hx (list "tr" "a-c" "xyz") "a-cb\n") (hx (list "tr" "\\101-\\103" "xyz") "ABC\n"))
```
---
```output
61 20 62 0a | status 0
78 79 7a 62 0a | status 0
78 2d 7a 79 0a | status 0
78 79 7a 0a | status 0
```

## cleanup

### the scratch directory goes

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-esc")) (display "clean"))
```
---
    clean

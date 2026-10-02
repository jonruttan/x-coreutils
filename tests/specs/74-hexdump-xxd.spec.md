# @weight 1

busybox's hexdump, hd and xxd (util-linux/hexdump.c, hexdump_xxd.c), over
its dump engine (libbb/dump.c).  Every expectation is busybox's own output,
from a busybox built from its source, less the banner line its usage text
starts with.  A `|` marks the end of each line written to standard output, so
trailing blanks can be seen; where the output holds bytes that are not text
(xxd -r, a %s of raw bytes), it is shown in hex, 32 bytes a line.

## the fixtures

### the files, and a run of an applet with its standard input, stdout, stderr and status

`t` holds text with a tab, a NUL, controls and bytes past 0x7F; `z` 64 zero
bytes and an A; `z2` 48 zeros, 16 As and 32 zeros; `f.fmt` a format file;
`r1` to `r4` dumps for xxd -r to read back.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-hx && mkdir -p /tmp/x-cu-hx/dir && cd /tmp/x-cu-hx && printf 'Hello, world!\\n\\tabc\\000\\001\\177\\200\\377 more text here.\\n' > t && head -c 64 /dev/zero > z && printf A >> z && { head -c 48 /dev/zero; printf AAAAAAAAAAAAAAAA; head -c 32 /dev/zero; } > z2 && printf '# a comment\\n\\n  \"%%07_ax \"\\n8/1 \"%%02x \" \"\\\\n\"\\n' > f.fmt && printf '00000000: 4865 6c6c 6f0a  Hello.\\n00000010: 6869 0a  hi.\\n' > r1 && printf '48656c 6c6f\\n0a 3\\n10a\\n' > r2 && printf '00000003: 41 42\\n00000000: 5a\\n' > r3 && printf '00000000: 41!42 43!!44 45\\n' > r4")) (def nf (fn (_ n) (string-append "/tmp/x-cu-hx/" n))) (def shown (fn (_ mode) (if (string=? mode "x") (do (proc-run (list "/bin/sh" "-c" "od -An -v -tx1 /tmp/x-cu-hx/.out | tr -d ' \\n' | fold -w 64 > /tmp/x-cu-hx/.hex; [ -s /tmp/x-cu-hx/.hex ] && echo >> /tmp/x-cu-hx/.hex")) (file-read-all (nf ".hex"))) (Str8 replace "\n" "|\n" (Str8 replace "/tmp/x-cu-hx/" "" (file-read-all (nf ".out"))))))) (def run (fn (_ mode argv in) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv in)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (shown mode) "stderr:\n" (Str8 replace "/tmp/x-cu-hx/" "" (file-read-all (nf ".err"))) "status " (%cu-int->str st) "\n")))))))) (display "made"))
```
---
    made

## hd and hexdump -C

### hd is hexdump -C: the offset, sixteen bytes in two groups of eight, and the printable ones between bars; the end offset on a line of its own

```cu
(do (run "-" (list "hd" (nf "t")) "") (run "-" (list "hexdump" "-C" (nf "t")) ""))
```
---
```output
00000000  48 65 6c 6c 6f 2c 20 77  6f 72 6c 64 21 0a 09 61  |Hello, world!..a||
00000010  62 63 00 01 7f 80 ff 20  6d 6f 72 65 20 74 65 78  |bc..... more tex||
00000020  74 20 68 65 72 65 2e 0a                           |t here..||
00000028|
stderr:
status 0
00000000  48 65 6c 6c 6f 2c 20 77  6f 72 6c 64 21 0a 09 61  |Hello, world!..a||
00000010  62 63 00 01 7f 80 ff 20  6d 6f 72 65 20 74 65 78  |bc..... more tex||
00000020  74 20 68 65 72 65 2e 0a                           |t here..||
00000028|
stderr:
status 0
```

### standard input, and several files read as one stream

```cu
(do (run "-" (list "hd") "abc\n") (run "-" (list "hd" (nf "t") (nf "z")) ""))
```
---
```output
00000000  61 62 63 0a                                       |abc.||
00000004|
stderr:
status 0
00000000  48 65 6c 6c 6f 2c 20 77  6f 72 6c 64 21 0a 09 61  |Hello, world!..a||
00000010  62 63 00 01 7f 80 ff 20  6d 6f 72 65 20 74 65 78  |bc..... more tex||
00000020  74 20 68 65 72 65 2e 0a  00 00 00 00 00 00 00 00  |t here..........||
00000030  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................||
*|
00000060  00 00 00 00 00 00 00 00  41                       |........A||
00000069|
stderr:
status 0
```

### a file that will not open is said and passed, and the status is 1; one that will not read is said, and is not a failure

```cu
(do (run "-" (list "hd" (nf "t") (nf "nope")) "") (run "-" (list "hd" (nf "dir")) "") (run "-" (list "hd" "/dev/null") ""))
```
---
```output
00000000  48 65 6c 6c 6f 2c 20 77  6f 72 6c 64 21 0a 09 61  |Hello, world!..a||
00000010  62 63 00 01 7f 80 ff 20  6d 6f 72 65 20 74 65 78  |bc..... more tex||
00000020  74 20 68 65 72 65 2e 0a                           |t here..||
00000028|
stderr:
hd: nope: No such file or directory
status 1
stderr:
hd: dir: Is a directory
status 0
stderr:
status 0
```

### a block the same as the last is one * line, and each run of them another; -v shows them all

```cu
(do (run "-" (list "hexdump" "-C" (nf "z")) "") (run "-" (list "hexdump" "-C" (nf "z2")) "") (run "-" (list "hexdump" "-Cv" (nf "z")) ""))
```
---
```output
00000000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................||
*|
00000040  41                                                |A||
00000041|
stderr:
status 0
00000000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................||
*|
00000030  41 41 41 41 41 41 41 41  41 41 41 41 41 41 41 41  |AAAAAAAAAAAAAAAA||
00000040  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................||
*|
00000060|
stderr:
status 0
00000000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................||
00000010  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................||
00000020  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................||
00000030  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................||
00000040  41                                                |A||
00000041|
stderr:
status 0
```

## hexdump's own formats

### with no format, -x less a space; -b -c -d -o -x, the octal, character, decimal, octal and hex views

```cu
(do (run "-" (list "hexdump" (nf "t")) "") (run "-" (list "hexdump" "-b" (nf "t")) "") (run "-" (list "hexdump" "-c" (nf "t")) "") (run "-" (list "hexdump" "-d" (nf "t")) "") (run "-" (list "hexdump" "-o" (nf "t")) "") (run "-" (list "hexdump" "-x" (nf "t")) ""))
```
---
```output
0000000 6548 6c6c 2c6f 7720 726f 646c 0a21 6109|
0000010 6362 0100 807f 20ff 6f6d 6572 7420 7865|
0000020 2074 6568 6572 0a2e                    |
0000028|
stderr:
status 0
0000000 110 145 154 154 157 054 040 167 157 162 154 144 041 012 011 141|
0000010 142 143 000 001 177 200 377 040 155 157 162 145 040 164 145 170|
0000020 164 040 150 145 162 145 056 012                                |
0000028|
stderr:
status 0
0000000   H   e   l   l   o   ,       w   o   r   l   d   !  \n  \t   a|
0000010   b   c  \0 001 177 200 377       m   o   r   e       t   e   x|
0000020   t       h   e   r   e   .  \n                                |
0000028|
stderr:
status 0
0000000   25928   27756   11375   30496   29295   25708   02593   24841|
0000010   25442   00256   32895   08447   28525   25970   29728   30821|
0000020   08308   25960   25970   02606                                |
0000028|
stderr:
status 0
0000000  062510  066154  026157  073440  071157  062154  005041  060411|
0000010  061542  000400  100177  020377  067555  062562  072040  074145|
0000020  020164  062550  062562  005056                                |
0000028|
stderr:
status 0
0000000    6548    6c6c    2c6f    7720    726f    646c    0a21    6109|
0000010    6362    0100    807f    20ff    6f6d    6572    7420    7865|
0000020    2074    6568    6572    0a2e                                |
0000028|
stderr:
status 0
```

### each option adds its formats, so two print each block twice over

```cu
(do (run "-" (list "hexdump" "-b" "-c" (nf "t")) "") (run "-" (list "hexdump" "-C" "-C" (nf "z")) ""))
```
---
```output
0000000 110 145 154 154 157 054 040 167 157 162 154 144 041 012 011 141|
0000000   H   e   l   l   o   ,       w   o   r   l   d   !  \n  \t   a|
0000010 142 143 000 001 177 200 377 040 155 157 162 145 040 164 145 170|
0000010   b   c  \0 001 177 200 377       m   o   r   e       t   e   x|
0000020 164 040 150 145 162 145 056 012                                |
0000020   t       h   e   r   e   .  \n                                |
0000028|
stderr:
status 0
00000000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................||
00000000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................||
*|
00000040  41                                                |A||
00000040  41                                                |A||
00000041|
stderr:
status 0
```

## -n and -s

### -n reads so many bytes and -s passes so many, in decimal, hex or octal, with busybox's suffixes

```cu
(do (run "-" (list "hexdump" "-n" "5" "-C" (nf "t")) "") (run "-" (list "hexdump" "-n" "0x10" "-C" (nf "t")) "") (run "-" (list "hexdump" "-n" "1k" "-C" (nf "t")) "") (run "-" (list "hexdump" "-s" "3" "-C" (nf "t")) "") (run "-" (list "hexdump" "-s" "010" "-C" (nf "t")) ""))
```
---
```output
00000000  48 65 6c 6c 6f                                    |Hello||
00000005|
stderr:
status 0
00000000  48 65 6c 6c 6f 2c 20 77  6f 72 6c 64 21 0a 09 61  |Hello, world!..a||
00000010|
stderr:
status 0
00000000  48 65 6c 6c 6f 2c 20 77  6f 72 6c 64 21 0a 09 61  |Hello, world!..a||
00000010  62 63 00 01 7f 80 ff 20  6d 6f 72 65 20 74 65 78  |bc..... more tex||
00000020  74 20 68 65 72 65 2e 0a                           |t here..||
00000028|
stderr:
status 0
00000003  6c 6f 2c 20 77 6f 72 6c  64 21 0a 09 61 62 63 00  |lo, world!..abc.||
00000013  01 7f 80 ff 20 6d 6f 72  65 20 74 65 78 74 20 68  |.... more text h||
00000023  65 72 65 2e 0a                                    |ere..||
00000028|
stderr:
status 0
00000008  6f 72 6c 64 21 0a 09 61  62 63 00 01 7f 80 ff 20  |orld!..abc..... ||
00000018  6d 6f 72 65 20 74 65 78  74 20 68 65 72 65 2e 0a  |more text here..||
00000028|
stderr:
status 0
```

### a skip past a file goes on into the next; past them all, only the end offset is shown

```cu
(do (run "-" (list "hexdump" "-s" "50" "-C" (nf "t") (nf "z")) "") (run "-" (list "hexdump" "-s" "1000" "-C" (nf "t")) ""))
```
---
```output
00000032  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................||
*|
00000062  00 00 00 00 00 00 41                              |......A||
00000069|
stderr:
status 0
00000028|
stderr:
status 0
```

### a count that is not a number is refused

```cu
(do (run "-" (list "hexdump" "-n" "x" (nf "t")) "") (run "-" (list "hexdump" "-s" "-1" (nf "t")) ""))
```
---
```output
stderr:
hexdump: invalid number 'x'
status 1
stderr:
hexdump: invalid number '-1'
status 1
```

## -e and -f

### a format is an iteration count, a byte count and a printf format; the last unit repeats to fill the block, and its last iteration loses its trailing blank

```cu
(do (run "-" (list "hexdump" "-e" "8/1 \"%02X \"\"\\n\"" (nf "t")) "") (run "-" (list "hexdump" "-e" "\"%07.7_ax \" 8/1 \"%_u \" \"\\n\"" (nf "t")) "") (run "-" (list "hexdump" "-e" "4/1 \"%4d\" \"\\n\"" (nf "t")) "") (run "-" (list "hexdump" "-e" "1/4 \"%08x\" \"\\n\"" (nf "t")) "") (run "-" (list "hexdump" "-e" "1/2 \"%6d\" \"\\n\"" (nf "t")) ""))
```
---
```output
48 65 6C 6C 6F 2C 20 77|
6F 72 6C 64 21 0A 09 61|
62 63 00 01 7F 80 FF 20|
6D 6F 72 65 20 74 65 78|
74 20 68 65 72 65 2E 0A|
stderr:
status 0
0000000 H e l l o ,   w|
0000008 o r l d ! lf ht a|
0000010 b c nul soh del 80 ff  |
0000018 m o r e   t e x|
0000020 t   h e r e . lf|
stderr:
status 0
  72 101 108 108|
 111  44  32 119|
 111 114 108 100|
  33  10   9  97|
  98  99   0   1|
 127-128  -1  32|
 109 111 114 101|
  32 116 101 120|
 116  32 104 101|
 114 101  46  10|
stderr:
status 0
6c6c6548|
77202c6f|
646c726f|
61090a21|
01006362|
20ff807f|
65726f6d|
78657420|
65682074|
0a2e6572|
stderr:
status 0
 25928|
 27756|
 11375|
 30496|
 29295|
 25708|
  2593|
 24841|
 25442|
   256|
-32641|
  8447|
 28525|
 25970|
 29728|
 30821|
  8308|
 25960|
 25970|
  2606|
stderr:
status 0
```

### %_c spells the controls as escapes and the rest in octal; %_p prints a dot for them; %s reads its byte count

```cu
(do (run "-" (list "hexdump" "-e" "16/1 \"%3_c\" \"\\n\"" (nf "t")) "") (run "-" (list "hexdump" "-e" "16/1 \"%_p\" \"\\n\"" (nf "t")) "") (run "x" (list "hexdump" "-e" "1/5 \"%s\" \"\\n\"" (nf "t")) ""))
```
---
```output
  H  e  l  l  o  ,     w  o  r  l  d  ! \n \t  a|
  b  c \0001177200377     m  o  r  e     t  e  x|
  t     h  e  r  e  . \n                        |
stderr:
status 0
Hello, world!..a|
bc..... more tex|
t here..|
stderr:
status 0
48656c6c6f0a2c20776f720a6c64210a090a6162630a7f80ff206d0a6f726520
740a65787420680a6572652e0a0a
stderr:
status 0
```

### flags, width and precision as printf takes them; the end offset with %_A

```cu
(do (run "-" (list "hexdump" "-e" "4/1 \"%#x %+d|\" \"\\n\"" (nf "t")) "") (run "-" (list "hexdump" "-e" "4/1 \"%-5o|\" 1/1 \"%05.3u\" \"\\n\"" (nf "t")) "") (run "-" (list "hexdump" "-e" "\"%_Ad\\n\"" "-e" "16/1 \"%02x\" \"\\n\"" (nf "t")) ""))
```
---
```output
stderr:
hexdump: byte count with multiple conversion characters
status 1
110  |145  |154  |154  |  111|
54   |40   |167  |157  |  114|
154  |144  |41   |12   |  009|
141  |142  |143  |0    |  001|
177  |200  |377  |40   |  109|
157  |162  |145  |40   |  116|
145  |170  |164  |40   |  104|
145  |162  |145  |56   |  010|
stderr:
status 0
48656c6c6f2c20776f726c64210a0961|
626300017f80ff206d6f726520746578|
7420686572652e0a                |
40|
stderr:
status 0
```

### formats added together each print the same block

```cu
(run "-" (list "hexdump" "-e" "16/1 \"%02x\" \"\\n\"" "-e" "16/1 \"%_p\" \"\\n\"" (nf "t")) "")
```
---
```output
48656c6c6f2c20776f726c64210a0961|
Hello, world!..a|
626300017f80ff206d6f726520746578|
bc..... more tex|
7420686572652e0a                |
t here..|
stderr:
status 0
```

### -f reads formats from a file, passing blank lines and # comments

```cu
(do (run "-" (list "hexdump" "-f" (nf "f.fmt") (nf "t")) "") (run "-" (list "hexdump" "-f" (nf "nope") (nf "t")) ""))
```
---
```output
0000000 48 65 6c 6c 6f 2c 20 77|
0000008 6f 72 6c 64 21 0a 09 61|
0000010 62 63 00 01 7f 80 ff 20|
0000018 6d 6f 72 65 20 74 65 78|
0000020 74 20 68 65 72 65 2e 0a|
stderr:
status 0
stderr:
hexdump: can't open 'nope': No such file or directory
status 1
```

### a format busybox cannot read is refused, and nothing is dumped

```cu
(do (run "-" (list "hexdump" "-e" "8/1 %02x" (nf "t")) "") (run "-" (list "hexdump" "-e" "\"%z\"" (nf "t")) "") (run "-" (list "hexdump" "-e" "1/3 \"%d\"" (nf "t")) "") (run "-" (list "hexdump" "-e" "\"%s\"" (nf "t")) "") (run "-" (list "hexdump" "-e" "1/1 \"%x%x\"" (nf "t")) ""))
```
---
```output
stderr:
hexdump: bad format {8/1 %02x}
status 1
stderr:
hexdump: bad conversion character %z
status 1
stderr:
hexdump: bad byte count for conversion character d
status 1
stderr:
hexdump: %s needs precision or byte count
status 1
stderr:
hexdump: byte count with multiple conversion characters
status 1
```

## xxd

### the offset, the bytes in groups of two and the text; -g sets the group, -c the bytes a line

```cu
(do (run "-" (list "xxd" (nf "t")) "") (run "-" (list "xxd" "-g1" (nf "t")) "") (run "-" (list "xxd" "-g" "0" (nf "t")) "") (run "-" (list "xxd" "-c" "8" "-g" "3" (nf "t")) "") (run "-" (list "xxd" "-c" "5" (nf "t")) ""))
```
---
```output
00000000: 4865 6c6c 6f2c 2077 6f72 6c64 210a 0961  Hello, world!..a|
00000010: 6263 0001 7f80 ff20 6d6f 7265 2074 6578  bc..... more tex|
00000020: 7420 6865 7265 2e0a                      t here..|
stderr:
status 0
00000000: 48 65 6c 6c 6f 2c 20 77 6f 72 6c 64 21 0a 09 61  Hello, world!..a|
00000010: 62 63 00 01 7f 80 ff 20 6d 6f 72 65 20 74 65 78  bc..... more tex|
00000020: 74 20 68 65 72 65 2e 0a                          t here..|
stderr:
status 0
00000000: 48656c6c6f2c20776f726c64210a0961  Hello, world!..a|
00000010: 626300017f80ff206d6f726520746578  bc..... more tex|
00000020: 7420686572652e0a                  t here..|
stderr:
status 0
00000000: 48656c 6c6f2c 2077  Hello, w|
00000008: 6f726c 64210a 0961  orld!..a|
00000010: 626300 017f80 ff20  bc..... |
00000018: 6d6f72 652074 6578  more tex|
00000020: 742068 657265 2e0a  t here..|
stderr:
status 0
00000000: 4865 6c6c 6f  Hello|
00000005: 2c20 776f 72  , wor|
0000000a: 6c64 210a 09  ld!..|
0000000f: 6162 6300 01  abc..|
00000014: 7f80 ff20 6d  ... m|
00000019: 6f72 6520 74  ore t|
0000001e: 6578 7420 68  ext h|
00000023: 6572 652e 0a  ere..|
stderr:
status 0
```

### -p is the plain hex, -c bytes a line; -i a C array named for the file

```cu
(do (run "-" (list "xxd" "-p" (nf "t")) "") (run "-" (list "xxd" "-ps" "-c" "4" (nf "t")) "") (run "-" (list "xxd" "-i" (nf "t")) "") (run "-" (list "xxd" "-i") "hi\n"))
```
---
```output
48656c6c6f2c20776f726c64210a0961626300017f80ff206d6f72652074|
65787420686572652e0a|
stderr:
status 0
48656c6c|
6f2c2077|
6f726c64|
210a0961|
62630001|
7f80ff20|
6d6f7265|
20746578|
74206865|
72652e0a|
stderr:
status 0
unsigned char _tmp_x_cu_hx_t[] = {|
  0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x2c, 0x20, 0x77, 0x6f, 0x72, 0x6c, 0x64,|
  0x21, 0x0a, 0x09, 0x61, 0x62, 0x63, 0x00, 0x01, 0x7f, 0x80, 0xff, 0x20,|
  0x6d, 0x6f, 0x72, 0x65, 0x20, 0x74, 0x65, 0x78, 0x74, 0x20, 0x68, 0x65,|
  0x72, 0x65, 0x2e, 0x0a,|
};|
unsigned int _tmp_x_cu_hx_t_len = 40;|
stderr:
status 0
  0x68, 0x69, 0x0a,|
stderr:
status 0
```

### -o adds to the offsets shown, -l stops after so many bytes, -s passes so many

```cu
(do (run "-" (list "xxd" "-o" "16" "-l" "10" (nf "t")) "") (run "-" (list "xxd" "-o" "-2" "-l" "4" (nf "t")) "") (run "-" (list "xxd" "-s" "2" (nf "t")) "") (run "-" (list "xxd" "-l" "0" (nf "t")) ""))
```
---
```output
00000010: 4865 6c6c 6f2c 2077 6f72                 Hello, wor|
stderr:
status 0
fffffffffffffffe: 4865 6c6c                                Hell|
stderr:
status 0
00000002: 6c6c 6f2c 2077 6f72 6c64 210a 0961 6263  llo, world!..abc|
00000012: 0001 7f80 ff20 6d6f 7265 2074 6578 7420  ..... more text |
00000022: 6865 7265 2e0a                           here..|
stderr:
status 0
stderr:
status 0
```

### one file at most; a count that is not a number is refused; a file that will not open is said

```cu
(do (run "-" (list "xxd" (nf "t") (nf "t")) "") (run "-" (list "xxd" "-l" "x" (nf "t")) "") (run "-" (list "xxd" "-g" "x" (nf "t")) "") (run "-" (list "xxd" (nf "nope")) ""))
```
---
```output
stderr:
Usage: xxd [-ri] [-ps] [-g N] [-c N] [-l LEN] [-s OFS] [-o OFS] [FILE]

Hex dump FILE (or stdin)

	-g N		Bytes per group (default 2)
	-c N		Bytes per line (default:16, -ps:30, -i:12)
	-ps		Show only hex bytes (no offset/spaces)
	-i		C include file style
	-l LENGTH	Show only first LENGTH bytes
	-s OFFSET	Skip OFFSET bytes
	-o OFFSET	Add OFFSET to displayed offset
	-r		Reverse (with -p, assumes no offsets in input)
status 1
stderr:
xxd: invalid number 'x'
status 1
stderr:
xxd: invalid number 'x'
status 1
stderr:
xxd: nope: No such file or directory
status 1
```

## xxd -r

### a dump read back into its bytes; under -p, plain hex digits, which pair across lines

```cu
(do (run "x" (list "xxd" "-r" (nf "r1")) "") (run "x" (list "xxd" "-r" "-p" (nf "r2")) ""))
```
---
```output
48656c6c6f0a0000000000000000000068690a
stderr:
status 0
48656c6c6f0a310a
stderr:
status 0
```

### an offset behind the last is sought back to; one character between digits is passed over, two end the line

```cu
(do (run "x" (list "xxd" "-r" (nf "r3")) "") (run "x" (list "xxd" "-r" (nf "r4")) "") (run "-" (list "xxd" "-r" (nf "nope")) ""))
```
---
```output
5a00004142
stderr:
status 0
414243
stderr:
status 0
stderr:
xxd: can't open 'nope': No such file or directory
status 1
```

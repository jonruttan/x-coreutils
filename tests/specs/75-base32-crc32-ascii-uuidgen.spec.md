# @weight 1

busybox's base32 (coreutils/uudecode.c), crc32 (coreutils/cksum.c), ascii
(miscutils/ascii.c) and uuidgen (util-linux/uuidgen.c).  Every expectation
is busybox's own output, from a busybox built from its source, less the
banner line its usage text starts with -- but for uuidgen's UUID, which is
random, and is checked for its shape.  A `|` marks the end of each line
written to standard output; where the output holds bytes that are not text,
it is shown in hex, 32 bytes a line.

## the fixtures

### the files, and a run of an applet with its standard input, stdout, stderr and status

`h` holds hello, `e` nothing, `bin` a NUL and a byte past 0x7F, `l` a line
of 84 bytes, `d` is a directory, and `d1` to `d7` are for base32 -d.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-b4 && mkdir -p /tmp/x-cu-b4/d && cd /tmp/x-cu-b4 && printf hello > h && : > e && printf 'a\\000b\\377' > bin && printf 'The quick brown fox jumps over the lazy dog, and the lazy dog sleeps on in the sun.\\n' > l && printf 'NBSWY3DP\\n' > d1 && printf 'NB SW\\nY3DP' > d2 && printf 'MFRGG===' > d3 && printf MFRG > d4 && printf 'M!F*RGG===' > d5 && printf 'MEAGF7Y=\\n' > d6 && printf 'NBSWY3DPEB3W64TMMQ======\\n' > d7")) (def nf (fn (_ n) (string-append "/tmp/x-cu-b4/" n))) (def shown (fn (_ mode) (if (string=? mode "x") (do (proc-run (list "/bin/sh" "-c" "od -An -v -tx1 /tmp/x-cu-b4/.out | tr -d ' \\n' | fold -w 64 > /tmp/x-cu-b4/.hex; [ -s /tmp/x-cu-b4/.hex ] && echo >> /tmp/x-cu-b4/.hex")) (file-read-all (nf ".hex"))) (Str8 replace "\n" "|\n" (Str8 replace "/tmp/x-cu-b4/" "" (file-read-all (nf ".out"))))))) (def run (fn (_ mode argv in) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv in)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (shown mode) "stderr:\n" (Str8 replace "/tmp/x-cu-b4/" "" (file-read-all (nf ".err"))) "status " (%cu-int->str st) "\n")))))))) (display "made"))
```
---
    made

## ascii

### the table: decimal, hex and the character or its name, eight columns; arguments make no difference

```cu
(do (run "-" (list "ascii") "") (run "-" (list "ascii" "x" "y") ""))
```
---
```output
Dec Hex    Dec Hex    Dec Hex  Dec Hex  Dec Hex  Dec Hex   Dec Hex   Dec Hex|
  0 00 NUL  16 10 DLE  32 20    48 30 0  64 40 @  80 50 P   96 60 `  112 70 p|
  1 01 SOH  17 11 DC1  33 21 !  49 31 1  65 41 A  81 51 Q   97 61 a  113 71 q|
  2 02 STX  18 12 DC2  34 22 "  50 32 2  66 42 B  82 52 R   98 62 b  114 72 r|
  3 03 ETX  19 13 DC3  35 23 #  51 33 3  67 43 C  83 53 S   99 63 c  115 73 s|
  4 04 EOT  20 14 DC4  36 24 $  52 34 4  68 44 D  84 54 T  100 64 d  116 74 t|
  5 05 ENQ  21 15 NAK  37 25 %  53 35 5  69 45 E  85 55 U  101 65 e  117 75 u|
  6 06 ACK  22 16 SYN  38 26 &  54 36 6  70 46 F  86 56 V  102 66 f  118 76 v|
  7 07 BEL  23 17 ETB  39 27 '  55 37 7  71 47 G  87 57 W  103 67 g  119 77 w|
  8 08 BS   24 18 CAN  40 28 (  56 38 8  72 48 H  88 58 X  104 68 h  120 78 x|
  9 09 HT   25 19 EM   41 29 )  57 39 9  73 49 I  89 59 Y  105 69 i  121 79 y|
 10 0a NL   26 1a SUB  42 2a *  58 3a :  74 4a J  90 5a Z  106 6a j  122 7a z|
 11 0b VT   27 1b ESC  43 2b +  59 3b ;  75 4b K  91 5b [  107 6b k  123 7b {|
 12 0c FF   28 1c FS   44 2c ,  60 3c <  76 4c L  92 5c \  108 6c l  124 7c ||
 13 0d CR   29 1d GS   45 2d -  61 3d =  77 4d M  93 5d ]  109 6d m  125 7d }|
 14 0e SO   30 1e RS   46 2e .  62 3e >  78 4e N  94 5e ^  110 6e n  126 7e ~|
 15 0f SI   31 1f US   47 2f /  63 3f ?  79 4f O  95 5f _  111 6f o  127 7f DEL|
stderr:
status 0
Dec Hex    Dec Hex    Dec Hex  Dec Hex  Dec Hex  Dec Hex   Dec Hex   Dec Hex|
  0 00 NUL  16 10 DLE  32 20    48 30 0  64 40 @  80 50 P   96 60 `  112 70 p|
  1 01 SOH  17 11 DC1  33 21 !  49 31 1  65 41 A  81 51 Q   97 61 a  113 71 q|
  2 02 STX  18 12 DC2  34 22 "  50 32 2  66 42 B  82 52 R   98 62 b  114 72 r|
  3 03 ETX  19 13 DC3  35 23 #  51 33 3  67 43 C  83 53 S   99 63 c  115 73 s|
  4 04 EOT  20 14 DC4  36 24 $  52 34 4  68 44 D  84 54 T  100 64 d  116 74 t|
  5 05 ENQ  21 15 NAK  37 25 %  53 35 5  69 45 E  85 55 U  101 65 e  117 75 u|
  6 06 ACK  22 16 SYN  38 26 &  54 36 6  70 46 F  86 56 V  102 66 f  118 76 v|
  7 07 BEL  23 17 ETB  39 27 '  55 37 7  71 47 G  87 57 W  103 67 g  119 77 w|
  8 08 BS   24 18 CAN  40 28 (  56 38 8  72 48 H  88 58 X  104 68 h  120 78 x|
  9 09 HT   25 19 EM   41 29 )  57 39 9  73 49 I  89 59 Y  105 69 i  121 79 y|
 10 0a NL   26 1a SUB  42 2a *  58 3a :  74 4a J  90 5a Z  106 6a j  122 7a z|
 11 0b VT   27 1b ESC  43 2b +  59 3b ;  75 4b K  91 5b [  107 6b k  123 7b {|
 12 0c FF   28 1c FS   44 2c ,  60 3c <  76 4c L  92 5c \  108 6c l  124 7c ||
 13 0d CR   29 1d GS   45 2d -  61 3d =  77 4d M  93 5d ]  109 6d m  125 7d }|
 14 0e SO   30 1e RS   46 2e .  62 3e >  78 4e N  94 5e ^  110 6e n  126 7e ~|
 15 0f SI   31 1f US   47 2f /  63 3f ?  79 4f O  95 5f _  111 6f o  127 7f DEL|
stderr:
status 0
```

## crc32

### the zlib CRC-32 in eight hex digits, and the name; standard input is unnamed, and `-` is named

```cu
(do (run "-" (list "crc32" (nf "h")) "") (run "-" (list "crc32") "hello") (run "-" (list "crc32" "-") "hello"))
```
---
```output
3610a686 h|
stderr:
status 0
3610a686|
stderr:
status 0
3610a686 -|
stderr:
status 0
```

### a file that will not open is said and passed, and the status is 1; one that will not read ends the run

```cu
(do (run "-" (list "crc32" (nf "h") (nf "e") (nf "nope") (nf "bin")) "") (run "-" (list "crc32" (nf "d")) ""))
```
---
```output
3610a686 h|
00000000 e|
d817a9d2 bin|
stderr:
crc32: can't open 'nope': No such file or directory
status 1
stderr:
crc32: d: Is a directory
status 1
```

## base32

### five bytes to eight characters, the last group padded with =; lines of 76, or of -w COL, and -w 0 none, with no newline at all

```cu
(do (run "-" (list "base32" (nf "h")) "") (run "-" (list "base32" (nf "bin")) "") (run "-" (list "base32" (nf "l")) "") (run "-" (list "base32" "-w" "5" (nf "l")) "") (run "-" (list "base32" "-w" "0" (nf "h")) "") (run "-" (list "base32" (nf "e")) ""))
```
---
```output
NBSWY3DP|
stderr:
status 0
MEAGF7Y=|
stderr:
status 0
KRUGKIDROVUWG2ZAMJZG653OEBTG66BANJ2W24DTEBXXMZLSEB2GQZJANRQXU6JAMRXWOLBAMFXG|
IIDUNBSSA3DBPJ4SAZDPM4QHG3DFMVYHGIDPNYQGS3RAORUGKIDTOVXC4CQ=|
stderr:
status 0
KRUGK|
IDROV|
UWG2Z|
AMJZG|
653OE|
BTG66|
BANJ2|
W24DT|
EBXXM|
ZLSEB|
2GQZJ|
ANRQX|
U6JAM|
RXWOL|
BAMFX|
GIIDU|
NBSSA|
3DBPJ|
4SAZD|
PM4QH|
G3DFM|
VYHGI|
DPNYQ|
GS3RA|
ORUGK|
IDTOV|
XC4CQ|
=|
stderr:
status 0
NBSWY3DPstderr:
status 0
stderr:
status 0
```

### -d decodes, passing over blanks, newlines and characters not of the alphabet; = ends a group

```cu
(do (run "-" (list "base32" "-d" (nf "d1")) "") (run "-" (list "base32" "-d" (nf "d2")) "") (run "-" (list "base32" "-d" (nf "d3")) "") (run "-" (list "base32" "-d" (nf "d5")) "") (run "-" (list "base32" "-d" (nf "d7")) "") (run "x" (list "base32" "-d" (nf "d6")) ""))
```
---
```output
hellostderr:
status 0
hellostderr:
status 0
abcstderr:
status 0
abcstderr:
status 0
hello worldstderr:
status 0
610062ff
stderr:
status 0
```

### a group the input ends inside is truncated input; -i changes nothing

```cu
(do (run "-" (list "base32" "-d" (nf "d4")) "") (run "-" (list "base32" "-i" (nf "h")) ""))
```
---
```output
stderr:
base32: truncated input
status 1
NBSWY3DP|
stderr:
status 0
```

### one file at most; a width that is not a number is refused; a file that will not open is said

```cu
(do (run "-" (list "base32" (nf "h") (nf "h")) "") (run "-" (list "base32" "-w" "x" (nf "h")) "") (run "-" (list "base32" (nf "nope")) ""))
```
---
```output
stderr:
Usage: base32 [-d] [-w COL] [FILE]

Base32 encode or decode FILE to standard output

	-d	Decode data
	-w COL	Wrap lines at COL (default 76, 0 disables)
status 1
stderr:
base32: invalid number 'x'
status 1
stderr:
base32: nope: No such file or directory
status 1
```

## uuidgen

### uuidgen takes no operand

```cu
(run "-" (list "uuidgen" "x") "")
```
---
```output
stderr:
Usage: uuidgen

Generate a random UUID
status 1
```

### a random version-4 UUID: 36 characters and a newline, dashes at 8 13 18 and 23, lower-case hex, a 4 starting the third group and 8 9 a or b the fourth

```cu
(do (def cap (fn (_ argv) (do (sys-dup2 1 9) (let ((oo (file-open-write (nf ".out")))) (do (sys-dup2 oo 1) (def st (cu-run argv "")) (sys-dup2 9 1) (file-close oo) (pair st (file-read-all (nf ".out")))))))) (def hex? (fn (_ c) (if (if (>= c #\0) (<= c #\9) #f) #t (if (>= c #\a) (<= c #\f) #f)))) (def dash? (fn (_ i) (%cu-member-s? (%cu-int->str i) (list "8" "13" "18" "23")))) (def shaped (fn (self u i) (if (= i 36) #t (if (if (dash? i) (= (byte-at u i) #\-) (hex? (byte-at u i))) (self u (+ i 1)) #f)))) (def judge (fn (_ r) (let ((u (rest r))) (if (if (= (first r) 0) (if (= (byte-len u) 37) (if (shaped u 0) (if (= (byte-at u 36) #\newline) (if (= (byte-at u 14) #\4) (%cu-member-s? (bytes->str (list (byte-at u 19))) (list "8" "9" "a" "b")) #f) #f) #f) #f) #f) "ok" (string-append "bad: " u))))) (display (string-append (judge (cap (list "uuidgen"))) (string-append " " (judge (cap (list "uuidgen" "-r")))))))
```
---
    ok ok

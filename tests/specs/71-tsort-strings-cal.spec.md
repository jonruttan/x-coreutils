# @weight 1

busybox's tsort (coreutils/tsort.c), strings (miscutils/strings.c) and cal
(util-linux/cal.c).  Every expectation is busybox's own output, from a
busybox built from its source, less the banner line its usage text starts
with.  A `|` marks the end of each line written to standard output, so the
trailing spaces cal keeps can be seen.

## the fixtures

### the files, and a run of an applet with its standard input, stdout, stderr and status

`bin` holds runs of printable bytes between a control byte, a byte past
0x7F and a NUL; `long` holds a run that starts 16380 bytes in, past the
first piece read.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-tsc && mkdir -p /tmp/x-cu-tsc/dir && cd /tmp/x-cu-tsc && printf 'ab\\001cdefg\\tz\\377hijklmnop\\000qrst' > bin && printf 'a a' > noeol && printf 'a a\\n' > aa && head -c 16380 /dev/zero > long && printf 'abcdefghij\\001\\tkl\\tmn\\n' >> long")) (def nf (fn (_ n) (string-append "/tmp/x-cu-tsc/" n))) (def run (fn (_ argv in) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv in)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (Str8 replace "/tmp/x-cu-tsc/" "" (string-concat (list (Str8 replace "\n" "|\n" (file-read-all (nf ".out"))) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n"))))))))) (display "made"))
```
---
    made

## tsort

### busybox's tests: a word paired with itself, from standard input, `-`, a file, and a file with no last newline

```cu
(do (run (list "tsort") "a a\n") (run (list "tsort" "-") "a a\n") (run (list "tsort" (nf "aa")) "") (run (list "tsort" (nf "noeol")) ""))
```
---
```output
a|
stderr:
status 0
a|
stderr:
status 0
a|
stderr:
status 0
a|
stderr:
status 0
```

### busybox's tests: nothing to sort -- an empty file, empty input, blank lines, blanks

```cu
(do (run (list "tsort" "/dev/null") "") (run (list "tsort") "") (run (list "tsort") "\n") (run (list "tsort") "\n\n \t\n "))
```
---
```output
stderr:
status 0
stderr:
status 0
stderr:
status 0
stderr:
status 0
```

### busybox's tests: one edge, two, and its other inputs, each in busybox's own order

```cu
(do (run (list "tsort") "a b\n") (run (list "tsort") "a b b c\n") (run (list "tsort") "a b c c d e g g f g e f h h\n") (run (list "tsort") "a aa aa aaa aaaa aaaaa a aaaaa\n") (run (list "tsort") "a a b b\n") (run (list "tsort") "a b a b b c\n"))
```
---
```output
a|
b|
stderr:
status 0
a|
b|
c|
stderr:
status 0
a|
h|
b|
c|
d|
e|
f|
g|
stderr:
status 0
a|
aa|
aaaa|
aaaaa|
aaa|
stderr:
status 0
a|
b|
stderr:
status 0
a|
b|
c|
stderr:
status 0
```

### words are paired across blanks and lines

```cu
(run (list "tsort") "a\tb\n\n  b c  \n")
```
---
```output
a|
b|
c|
stderr:
status 0
```

## odd input and cycles

### an odd number of words is odd input, and nothing goes out

```cu
(do (run (list "tsort") "a\n") (run (list "tsort") "a b c\n"))
```
---
```output
stderr:
tsort: odd input
status 1
stderr:
tsort: odd input
status 1
```

### a cycle is said at the array's first node, broken there, and the rest go on; the status is 1

```cu
(do (run (list "tsort") "a b b a\n") (run (list "tsort") "c d b c a b x y d b\n") (run (list "tsort") "a b\nb c\nc a\nd e\n"))
```
---
```output
a|
b|
stderr:
tsort: cycle at a
status 1
a|
x|
y|
d|
b|
c|
stderr:
tsort: cycle at d
status 1
d|
e|
a|
b|
c|
stderr:
tsort: cycle at a
status 1
```

## tsort's operands

### a file that will not open ends it; a directory reads as empty; two operands is the usage; there are no options

```cu
(do (run (list "tsort" (nf "nope")) "") (run (list "tsort" (nf "dir")) "") (run (list "tsort" (nf "aa") (nf "noeol")) "") (run (list "tsort" "-x") ""))
```
---
```output
stderr:
tsort: can't open 'nope': No such file or directory
status 1
stderr:
status 0
stderr:
Usage: tsort [FILE]

Topological sort
status 1
stderr:
tsort: can't open '-x': No such file or directory
status 1
```

## strings

### busybox's way: runs of four or more printable bytes, the tab among them

```cu
(do (run (list "strings" (nf "bin")) "") (run (list "strings" "-f" (nf "bin")) ""))
```
---
```output
cdefg	z|
hijklmnop|
qrst|
stderr:
status 0
bin: cdefg	z|
bin: hijklmnop|
bin: qrst|
stderr:
status 0
```

### with no operand the name is {standard input}; `-` is named `-`

```cu
(do (run (list "strings" "-f") "hello\tworld\n\nhi\nthere\n") (run (list "strings" "-f" "-") "hello\tworld\n\nhi\nthere\n"))
```
---
```output
{standard input}: hello	world|
{standard input}: there|
stderr:
status 0
-: hello	world|
-: there|
stderr:
status 0
```

### -o and -t put the run's offset, seven wide, in octal, hex or decimal; -n sets the least length

```cu
(do (run (list "strings" "-o" (nf "bin")) "") (run (list "strings" "-t" "x" "-n" "2" (nf "bin")) "") (run (list "strings" "-o" "-t" "x" (nf "bin")) "") (run (list "strings" "-t" "d" (nf "bin") (nf "nope") (nf "bin")) ""))
```
---
```output
      3 cdefg	z|
     13 hijklmnop|
     25 qrst|
stderr:
status 0
      0 ab|
      3 cdefg	z|
      b hijklmnop|
     15 qrst|
stderr:
status 0
      3 cdefg	z|
      b hijklmnop|
     15 qrst|
stderr:
status 0
      3 cdefg	z|
     11 hijklmnop|
     21 qrst|
      3 cdefg	z|
     11 hijklmnop|
     21 qrst|
stderr:
strings: nope: No such file or directory
status 1
```

### a radix that is not o, d or x is the usage; a length is a number from 1, no more than an unsigned int, with no sign

```cu
(do (run (list "strings" "-t" "q" (nf "bin")) "") (run (list "strings" "-n" "0" (nf "bin")) "") (run (list "strings" "-n" "x" (nf "bin")) "") (run (list "strings" "-n" "99999999999" (nf "bin")) "") (run (list "strings" "-n" "+5" (nf "bin")) ""))
```
---
```output
stderr:
Usage: strings [-fo] [-t o|d|x] [-n LEN] [FILE]...

Display printable strings in a binary file

	-f		Precede strings with filenames
	-o		Precede strings with octal offsets
	-t o|d|x	Precede strings with offsets in base 8/10/16
	-n LEN		At least LEN characters form a string (default 4)
status 1
stderr:
strings: number 0 is not in 1..2147483647 range
status 1
stderr:
strings: invalid number 'x'
status 1
stderr:
strings: invalid number '99999999999'
status 1
stderr:
strings: invalid number '+5'
status 1
```

### a directory reads as empty; a run past the first piece read keeps its offset; -a changes nothing

```cu
(do (run (list "strings" (nf "dir")) "") (run (list "strings" "-t" "d" (nf "long")) "") (run (list "strings" "-a" "-n" "1" (nf "bin")) "") (run (list "strings" "-n" "9" (nf "bin")) ""))
```
---
```output
stderr:
status 0
  16380 abcdefghij|
  16391 	kl	mn|
stderr:
status 0
ab|
cdefg	z|
hijklmnop|
qrst|
stderr:
status 0
hijklmnop|
stderr:
status 0
```

## cal

### busybox's test, January 2000; -j numbers the days through the year; a row with no day is spaces

```cu
(do (run (list "cal" "1" "2000") "") (run (list "cal" "-j" "2" "2000") ""))
```
---
```output
    January 2000|
Su Mo Tu We Th Fr Sa|
                   1|
 2  3  4  5  6  7  8|
 9 10 11 12 13 14 15|
16 17 18 19 20 21 22|
23 24 25 26 27 28 29|
30 31|
stderr:
status 0
       February 2000|
 Su  Mo  Tu  We  Th  Fr  Sa|
         32  33  34  35  36|
 37  38  39  40  41  42  43|
 44  45  46  47  48  49  50|
 51  52  53  54  55  56  57|
 58  59  60|
                            |
stderr:
status 0
```

### September 1752, with and without -j, the week from Monday under -m

```cu
(do (run (list "cal" "-m" "9" "1752") "") (run (list "cal" "-j" "9" "1752") ""))
```
---
```output
   September 1752|
Mo Tu We Th Fr Sa Su|
    1  2 14 15 16 17|
18 19 20 21 22 23 24|
25 26 27 28 29 30|
                     |
                     |
                     |
stderr:
status 0
      September 1752|
 Su  Mo  Tu  We  Th  Fr  Sa|
        245 246 258 259 260|
261 262 263 264 265 266 267|
268 269 270 271 272 273 274|
                            |
                            |
                            |
stderr:
status 0
```

### the leap years: 1900 is not one, 1700 is, under the Julian rule

```cu
(do (run (list "cal" "2" "1900") "") (run (list "cal" "2" "1700") ""))
```
---
```output
   February 1900|
Su Mo Tu We Th Fr Sa|
             1  2  3|
 4  5  6  7  8  9 10|
11 12 13 14 15 16 17|
18 19 20 21 22 23 24|
25 26 27 28|
                     |
stderr:
status 0
   February 1700|
Su Mo Tu We Th Fr Sa|
             1  2  3|
 4  5  6  7  8  9 10|
11 12 13 14 15 16 17|
18 19 20 21 22 23 24|
25 26 27 28 29|
                     |
stderr:
status 0
```

### the last month, the first, three digits under -j, and -m with -j

```cu
(do (run (list "cal" "12" "9999") "") (run (list "cal" "1" "1") "") (run (list "cal" "-j" "12" "2000") "") (run (list "cal" "-mj" "3" "2024") ""))
```
---
```output
   December 9999|
Su Mo Tu We Th Fr Sa|
          1  2  3  4|
 5  6  7  8  9 10 11|
12 13 14 15 16 17 18|
19 20 21 22 23 24 25|
26 27 28 29 30 31|
                     |
stderr:
status 0
     January 1|
Su Mo Tu We Th Fr Sa|
                   1|
 2  3  4  5  6  7  8|
 9 10 11 12 13 14 15|
16 17 18 19 20 21 22|
23 24 25 26 27 28 29|
30 31|
stderr:
status 0
       December 2000|
 Su  Mo  Tu  We  Th  Fr  Sa|
                    336 337|
338 339 340 341 342 343 344|
345 346 347 348 349 350 351|
352 353 354 355 356 357 358|
359 360 361 362 363 364 365|
366|
stderr:
status 0
        March 2024|
 Mo  Tu  We  Th  Fr  Sa  Su|
                 61  62  63|
 64  65  66  67  68  69  70|
 71  72  73  74  75  76  77|
 78  79  80  81  82  83  84|
 85  86  87  88  89  90  91|
                            |
stderr:
status 0
```

### a year, three months a row, the year and the names keeping their trailing spaces

```cu
(run (list "cal" "2000") "")
```
---
```output
                              2000                              |
|
      January               February               March        |
Su Mo Tu We Th Fr Sa  Su Mo Tu We Th Fr Sa  Su Mo Tu We Th Fr Sa|
                   1         1  2  3  4  5            1  2  3  4|
 2  3  4  5  6  7  8   6  7  8  9 10 11 12   5  6  7  8  9 10 11|
 9 10 11 12 13 14 15  13 14 15 16 17 18 19  12 13 14 15 16 17 18|
16 17 18 19 20 21 22  20 21 22 23 24 25 26  19 20 21 22 23 24 25|
23 24 25 26 27 28 29  27 28 29              26 27 28 29 30 31|
30 31|
       April                  May                   June        |
Su Mo Tu We Th Fr Sa  Su Mo Tu We Th Fr Sa  Su Mo Tu We Th Fr Sa|
                   1      1  2  3  4  5  6               1  2  3|
 2  3  4  5  6  7  8   7  8  9 10 11 12 13   4  5  6  7  8  9 10|
 9 10 11 12 13 14 15  14 15 16 17 18 19 20  11 12 13 14 15 16 17|
16 17 18 19 20 21 22  21 22 23 24 25 26 27  18 19 20 21 22 23 24|
23 24 25 26 27 28 29  28 29 30 31           25 26 27 28 29 30|
30|
        July                 August              September      |
Su Mo Tu We Th Fr Sa  Su Mo Tu We Th Fr Sa  Su Mo Tu We Th Fr Sa|
                   1         1  2  3  4  5                  1  2|
 2  3  4  5  6  7  8   6  7  8  9 10 11 12   3  4  5  6  7  8  9|
 9 10 11 12 13 14 15  13 14 15 16 17 18 19  10 11 12 13 14 15 16|
16 17 18 19 20 21 22  20 21 22 23 24 25 26  17 18 19 20 21 22 23|
23 24 25 26 27 28 29  27 28 29 30 31        24 25 26 27 28 29 30|
30 31|
      October               November              December      |
Su Mo Tu We Th Fr Sa  Su Mo Tu We Th Fr Sa  Su Mo Tu We Th Fr Sa|
 1  2  3  4  5  6  7            1  2  3  4                  1  2|
 8  9 10 11 12 13 14   5  6  7  8  9 10 11   3  4  5  6  7  8  9|
15 16 17 18 19 20 21  12 13 14 15 16 17 18  10 11 12 13 14 15 16|
22 23 24 25 26 27 28  19 20 21 22 23 24 25  17 18 19 20 21 22 23|
29 30 31              26 27 28 29 30        24 25 26 27 28 29 30|
                                            31|
stderr:
status 0
```

### under -j two months a row, and a row of nothing but spaces goes out whole

```cu
(run (list "cal" "-j" "2000") "")
```
---
```output
                          2000                          |
|
          January                     February          |
 Su  Mo  Tu  We  Th  Fr  Sa   Su  Mo  Tu  We  Th  Fr  Sa|
                          1           32  33  34  35  36|
  2   3   4   5   6   7   8   37  38  39  40  41  42  43|
  9  10  11  12  13  14  15   44  45  46  47  48  49  50|
 16  17  18  19  20  21  22   51  52  53  54  55  56  57|
 23  24  25  26  27  28  29   58  59  60|
 30  31|
           March                        April           |
 Su  Mo  Tu  We  Th  Fr  Sa   Su  Mo  Tu  We  Th  Fr  Sa|
             61  62  63  64                           92|
 65  66  67  68  69  70  71   93  94  95  96  97  98  99|
 72  73  74  75  76  77  78  100 101 102 103 104 105 106|
 79  80  81  82  83  84  85  107 108 109 110 111 112 113|
 86  87  88  89  90  91      114 115 116 117 118 119 120|
                             121|
            May                         June            |
 Su  Mo  Tu  We  Th  Fr  Sa   Su  Mo  Tu  We  Th  Fr  Sa|
    122 123 124 125 126 127                  153 154 155|
128 129 130 131 132 133 134  156 157 158 159 160 161 162|
135 136 137 138 139 140 141  163 164 165 166 167 168 169|
142 143 144 145 146 147 148  170 171 172 173 174 175 176|
149 150 151 152              177 178 179 180 181 182|
                                                                               |
           July                        August           |
 Su  Mo  Tu  We  Th  Fr  Sa   Su  Mo  Tu  We  Th  Fr  Sa|
                        183          214 215 216 217 218|
184 185 186 187 188 189 190  219 220 221 222 223 224 225|
191 192 193 194 195 196 197  226 227 228 229 230 231 232|
198 199 200 201 202 203 204  233 234 235 236 237 238 239|
205 206 207 208 209 210 211  240 241 242 243 244|
212 213|
         September                     October          |
 Su  Mo  Tu  We  Th  Fr  Sa   Su  Mo  Tu  We  Th  Fr  Sa|
                    245 246  275 276 277 278 279 280 281|
247 248 249 250 251 252 253  282 283 284 285 286 287 288|
254 255 256 257 258 259 260  289 290 291 292 293 294 295|
261 262 263 264 265 266 267  296 297 298 299 300 301 302|
268 269 270 271 272 273 274  303 304 305|
                                                                               |
         November                     December          |
 Su  Mo  Tu  We  Th  Fr  Sa   Su  Mo  Tu  We  Th  Fr  Sa|
            306 307 308 309                      336 337|
310 311 312 313 314 315 316  338 339 340 341 342 343 344|
317 318 319 320 321 322 323  345 346 347 348 349 350 351|
324 325 326 327 328 329 330  352 353 354 355 356 357 358|
331 332 333 334 335          359 360 361 362 363 364 365|
                             366|
stderr:
status 0
```

### -y with two operands takes the second as the year

```cu
(run (list "cal" "-m" "-y" "1" "2001") "")
```
---
```output
                              2001                              |
|
      January               February               March        |
Mo Tu We Th Fr Sa Su  Mo Tu We Th Fr Sa Su  Mo Tu We Th Fr Sa Su|
 1  2  3  4  5  6  7            1  2  3  4            1  2  3  4|
 8  9 10 11 12 13 14   5  6  7  8  9 10 11   5  6  7  8  9 10 11|
15 16 17 18 19 20 21  12 13 14 15 16 17 18  12 13 14 15 16 17 18|
22 23 24 25 26 27 28  19 20 21 22 23 24 25  19 20 21 22 23 24 25|
29 30 31              26 27 28              26 27 28 29 30 31|
                                                                               |
       April                  May                   June        |
Mo Tu We Th Fr Sa Su  Mo Tu We Th Fr Sa Su  Mo Tu We Th Fr Sa Su|
                   1      1  2  3  4  5  6               1  2  3|
 2  3  4  5  6  7  8   7  8  9 10 11 12 13   4  5  6  7  8  9 10|
 9 10 11 12 13 14 15  14 15 16 17 18 19 20  11 12 13 14 15 16 17|
16 17 18 19 20 21 22  21 22 23 24 25 26 27  18 19 20 21 22 23 24|
23 24 25 26 27 28 29  28 29 30 31           25 26 27 28 29 30|
30|
        July                 August              September      |
Mo Tu We Th Fr Sa Su  Mo Tu We Th Fr Sa Su  Mo Tu We Th Fr Sa Su|
                   1         1  2  3  4  5                  1  2|
 2  3  4  5  6  7  8   6  7  8  9 10 11 12   3  4  5  6  7  8  9|
 9 10 11 12 13 14 15  13 14 15 16 17 18 19  10 11 12 13 14 15 16|
16 17 18 19 20 21 22  20 21 22 23 24 25 26  17 18 19 20 21 22 23|
23 24 25 26 27 28 29  27 28 29 30 31        24 25 26 27 28 29 30|
30 31|
      October               November              December      |
Mo Tu We Th Fr Sa Su  Mo Tu We Th Fr Sa Su  Mo Tu We Th Fr Sa Su|
 1  2  3  4  5  6  7            1  2  3  4                  1  2|
 8  9 10 11 12 13 14   5  6  7  8  9 10 11   3  4  5  6  7  8  9|
15 16 17 18 19 20 21  12 13 14 15 16 17 18  10 11 12 13 14 15 16|
22 23 24 25 26 27 28  19 20 21 22 23 24 25  17 18 19 20 21 22 23|
29 30 31              26 27 28 29 30        24 25 26 27 28 29 30|
                                            31|
stderr:
status 0
```

## cal's operands

### a month from 1 to 12, a year from 1 to 9999, digits only; three operands is the usage

```cu
(do (run (list "cal" "13" "2000") "") (run (list "cal" "0") "") (run (list "cal" "x") "") (run (list "cal" "1" "2" "3") "") (run (list "cal" "+1") "") (run (list "cal" "10000") "") (run (list "cal" "0" "2000") ""))
```
---
```output
stderr:
cal: number 13 is not in 1..12 range
status 1
stderr:
cal: number 0 is not in 1..9999 range
status 1
stderr:
cal: invalid number 'x'
status 1
stderr:
Usage: cal [-jmy] [[MONTH] YEAR]

Display a calendar

	-j	Use julian dates
	-m	Week starts on Monday
	-y	Display the entire year
status 1
stderr:
cal: invalid number '+1'
status 1
stderr:
cal: number 10000 is not in 1..9999 range
status 1
stderr:
cal: number 0 is not in 1..12 range
status 1
```

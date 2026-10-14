# @weight 2

makemime and reformime as busybox's.  Each case runs SETUP (sh) in a fresh
/tmp/x-cu-mime to make its files, then APPLET ARGS (split as sh splits them)
there, the file STDIN its input (- for none).  Every expectation is busybox's
own output for the same case: stdout through LC_ALL=C cat -v, the status,
stderr, then each file under out/ after --- NAME.  makemime's boundary is
shown as BOUNDARY, and the name reformime makes for an unnamed part (the time
and its pid) as UNIQ.

## the fixture

### a directory, an applet, and the report

```cu
(do
  (def mm-d "/tmp/x-cu-mime")
  (def mm-f (fn (_ n) (string-append "/tmp/x-cu-mime/" n)))
  (def mm-lines (fn (_ s)
    (let go ((i 0) (acc ()))
      (let ((nl (%wget-index s #\newline i)))
        (if (null? nl) (reverse (if (< i (byte-len s)) (pair (substring s i (byte-len s)) acc) acc))
          (go (+ nl 1) (pair (substring s i nl) acc)))))))
  (def mm-sh (fn (_ script) (proc-run (list "/bin/sh" "-c" script))))
  (def mm (fn (_ setup cmd input)
    (%cu-heap-collect)
    (sys-setenv "MM_SETUP" setup) (sys-setenv "MM_CMD" cmd)
    (mm-sh "rm -rf /tmp/x-cu-mime && mkdir -p /tmp/x-cu-mime/out && cd /tmp/x-cu-mime && sh -c \"$MM_SETUP\" && eval \"set -- $MM_CMD\" && for a; do printf '%s\\n' \"$a\"; done > /tmp/x-cu-mime/.argv")
    (def argv (mm-lines (file-read-all (mm-f ".argv"))))
    (def in (if (string=? input "-") "" (file-read-all (mm-f input))))
    (def pid (sys-fork))
    (when (= pid 0)
      (do (Sys chdir mm-d)
          (sys-dup2 (file-open-write (mm-f ".so")) 1) (sys-dup2 (file-open-write (mm-f ".se")) 2)
          (sys-exit (cu-run argv in))))
    (def st (sys-wait pid))
    (mm-sh (string-concat (list
      "cd /tmp/x-cu-mime; norm() { LC_ALL=C sed -E -e 's/[0-9]+-[0-9]+-[0-9]+/BOUNDARY/g' -e 's/[0-9]{6,}\\.[0-9]+/UNIQ/g'; }; "
      "{ LC_ALL=C cat -v .so | norm; echo \"[status " (%cu-int->str st) "]\"; norm < .se; "
      "for f in $(ls out | sort); do echo \"--- $f\" | norm; LC_ALL=C cat -v out/$f | norm; echo; done; } > .report")))
    (display (file-read-all (mm-f ".report")))))
  (display "made"))
```
---
    made

## busybox's makemime and reformime

### makemime: stdin, one part

```cu
(mm "printf 'hello\\n' > in" "makemime" "in")
```
---
```output
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: application/octet-stream; charset=us-ascii
Content-Disposition: inline; filename="-"
Content-Transfer-Encoding: base64

aGVsbG8K
--BOUNDARY--

[status 0]
```

### makemime: a file named by its last component

```cu
(mm "mkdir -p d; printf 'abc' > d/a.txt" "makemime d/a.txt" "-")
```
---
```output
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: application/octet-stream; charset=us-ascii
Content-Disposition: inline; filename="a.txt"
Content-Transfer-Encoding: base64

YWJj
--BOUNDARY--

[status 0]
```

### makemime: two files

```cu
(mm "printf 'one\\n' > a; printf 'two\\n' > b" "makemime a b" "-")
```
---
```output
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: application/octet-stream; charset=us-ascii
Content-Disposition: inline; filename="a"
Content-Transfer-Encoding: base64

b25lCg==
--BOUNDARY
Content-Type: application/octet-stream; charset=us-ascii
Content-Disposition: inline; filename="b"
Content-Transfer-Encoding: base64

dHdvCg==
--BOUNDARY--

[status 0]
```

### makemime: 100 bytes, two base64 lines

```cu
(mm "i=0; while [ $i -lt 100 ]; do printf x; i=$((i+1)); done > big" "makemime big" "-")
```
---
```output
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: application/octet-stream; charset=us-ascii
Content-Disposition: inline; filename="big"
Content-Transfer-Encoding: base64

eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4
eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eA==
--BOUNDARY--

[status 0]
```

### makemime: 57 bytes, one full line

```cu
(mm "i=0; while [ $i -lt 57 ]; do printf y; i=$((i+1)); done > f57" "makemime f57" "-")
```
---
```output
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: application/octet-stream; charset=us-ascii
Content-Disposition: inline; filename="f57"
Content-Transfer-Encoding: base64

eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5eXl5
--BOUNDARY--

[status 0]
```

### makemime: an empty file

```cu
(mm ": > empty" "makemime empty" "-")
```
---
```output
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: application/octet-stream; charset=us-ascii
Content-Disposition: inline; filename="empty"
Content-Transfer-Encoding: base64

--BOUNDARY--

[status 0]
```

### makemime: -c and -C

```cu
(mm "printf 'hi\\n' > t" "makemime -c text/plain -C utf-8 t" "-")
```
---
```output
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: text/plain; charset=utf-8
Content-Disposition: inline; filename="t"
Content-Transfer-Encoding: base64

aGkK
--BOUNDARY--

[status 0]
```

### makemime: -a headers, in order

```cu
(mm "printf 'x' > t" "makemime -a \"From: a@b\" -a \"Subject: s\" t" "-")
```
---
```output
From: a@b
Subject: s
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: application/octet-stream; charset=us-ascii
Content-Disposition: inline; filename="t"
Content-Transfer-Encoding: base64

eA==
--BOUNDARY--

[status 0]
```

### makemime: -o FILE

```cu
(mm "printf 'z\\n' > t" "makemime -o out/msg t" "-")
```
---
```output
[status 0]
--- msg
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: application/octet-stream; charset=us-ascii
Content-Disposition: inline; filename="t"
Content-Transfer-Encoding: base64

ego=
--BOUNDARY--


```

### makemime: -e and -N take arguments and are ignored

```cu
(mm "printf 'q' > t" "makemime -e quoted-printable -N x t" "-")
```
---
```output
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: application/octet-stream; charset=us-ascii
Content-Disposition: inline; filename="t"
Content-Transfer-Encoding: base64

cQ==
--BOUNDARY--

[status 0]
```

### makemime: a file that cannot be read

```cu
(mm "printf 'a' > a" "makemime a nope" "-")
```
---
```output
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: application/octet-stream; charset=us-ascii
Content-Disposition: inline; filename="a"
Content-Transfer-Encoding: base64

YQ==
--BOUNDARY
Content-Type: application/octet-stream; charset=us-ascii
Content-Disposition: inline; filename="nope"
Content-Transfer-Encoding: base64
[status 1]
makemime: can't open 'nope': No such file or directory
```

### makemime: a trailing slash

```cu
(mm "mkdir -p d; printf 'w' > d/f" "makemime d/f/" "-")
```
---
```output
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: application/octet-stream; charset=us-ascii
Content-Disposition: inline; filename="f"
Content-Transfer-Encoding: base64

dw==
--BOUNDARY--

[status 0]
```

### makemime: binary bytes

```cu
(mm "printf '\\000\\001\\377\\376' > bin" "makemime bin" "-")
```
---
```output
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY"

--BOUNDARY
Content-Type: application/octet-stream; charset=us-ascii
Content-Disposition: inline; filename="bin"
Content-Transfer-Encoding: base64

AAH//g==
--BOUNDARY--

[status 0]
```

### reformime -X: a plain message, its headers

```cu
(mm "printf '#!/bin/sh\\necho \"[$CONTENT_TYPE|$CHARSET|$ENCODING|$FILENAME]\"\\ncat\\n' > show; chmod +x show; printf 'Content-Type: text/plain; charset=utf-8\\n\\nhello\\nworld\\n' > m" "reformime -X ./show" "m")
```
---
```output
[text/plain|utf-8|7bit|UNIQ]
hello
world
[status 0]
```

### reformime -X: no Content-Type, text/plain

```cu
(mm "printf '#!/bin/sh\\necho \"[$CONTENT_TYPE|$CHARSET|$ENCODING|$FILENAME]\"\\ncat\\n' > show; chmod +x show; printf 'Subject: x\\n\\nbody\\n' > m" "reformime -X ./show" "m")
```
---
```output
[text/plain|us-ascii|7bit|UNIQ]
body
[status 0]
```

### reformime -X: multipart, two 7bit parts

```cu
(mm "printf '#!/bin/sh\\necho \"[$CONTENT_TYPE|$CHARSET|$ENCODING|$FILENAME]\"\\ncat\\n' > show; chmod +x show; printf 'Content-Type: multipart/mixed; boundary=\"BB\"\\n\\n--BB\\nContent-Type: text/plain; name=\"a\"; filename=\"a.txt\"\\n\\none\\n--BB\\nContent-Type: text/html; filename=\"b.html\"\\n\\ntwo\\n--BB--\\n' > m" "reformime -X ./show" "m")
```
---
```output
[text/plain|us-ascii|7bit|a.txt]
one
[text/html|us-ascii|7bit|b.html]
two
[status 0]
```

### reformime -X: base64 parts, CRLF lines

```cu
(mm "printf '#!/bin/sh\\necho \"[$CONTENT_TYPE|$CHARSET|$ENCODING|$FILENAME]\"\\ncat\\n' > show; chmod +x show; printf 'Content-Type: multipart/mixed; boundary=\"Q\"\\r\\n\\r\\n--Q\\r\\nContent-Type: application/octet-stream; charset=us-ascii\\r\\nContent-Disposition: inline; filename=\"h\"\\r\\nContent-Transfer-Encoding: base64\\r\\n\\r\\naGVsbG8K\\r\\n--Q\\r\\nContent-Type: text/plain; filename=\"w\"\\r\\nContent-Transfer-Encoding: base64\\r\\n\\r\\nd29y\\r\\nbGQK\\r\\n--Q--\\r\\n' > m" "reformime -X ./show" "m")
```
---
```output
[application/octet-stream|us-ascii|base64|h]
hello
[text/plain|us-ascii|base64|w]
world
[text/plain|us-ascii|7bit|UNIQ]
[status 0]
```

### reformime -X: an encoding before Content-Type is not read

```cu
(mm "printf '#!/bin/sh\\necho \"[$CONTENT_TYPE|$CHARSET|$ENCODING|$FILENAME]\"\\ncat\\n' > show; chmod +x show; printf 'Content-Transfer-Encoding: base64\\nContent-Type: text/plain; filename=\"f\"\\n\\naGkK\\n' > m" "reformime -X ./show" "m")
```
---
```output
[text/plain|us-ascii|7bit|f]
aGkK
[status 0]
```

### reformime -x: parts written to PREFIX + filename

```cu
(mm "printf 'Content-Type: multipart/mixed; boundary=B\\n\\n--B\\nContent-Type: text/plain; filename=one\\n\\n1\\n--B\\nContent-Type: text/plain; filename=two\\nContent-Transfer-Encoding: base64\\n\\nMgo=\\n--B--\\n' > m" "reformime -x out/p-" "m")
```
---
```output
[status 0]
--- p-UNIQ

--- p-one
1

--- p-two
2

```

### reformime: quoted-printable is not supported

```cu
(mm "printf 'Content-Type: text/plain; filename=f\\nContent-Transfer-Encoding: quoted-printable\\n\\nx=41\\n' > m" "reformime -x out/" "m")
```
---
```output
[status 1]
reformime: encoding 'quoted-printable' not supported
--- f

```

### reformime: multipart/alternative is not supported

```cu
(mm "printf 'Content-Type: multipart/alternative; boundary=B\\n\\n--B\\n\\nx\\n--B--\\n' > m" "reformime -x out/" "m")
```
---
```output
[status 1]
reformime: no support of content type 'multipart/alternative'
```

### reformime: multipart without a boundary

```cu
(mm "printf 'Content-Type: multipart/mixed\\n\\nx\\n' > m" "reformime -x out/" "m")
```
---
```output
[status 1]
reformime: not found: 'boundary'
```

### reformime: truncated base64

```cu
(mm "printf 'Content-Type: text/plain; filename=f\\nContent-Transfer-Encoding: base64\\n\\naGk\\n' > m" "reformime -x out/" "m")
```
---
```output
[status 1]
reformime: truncated input
--- f

```

### reformime -X: PROG failing adds 20 to its status

```cu
(mm "printf '#!/bin/sh\\ncat > /dev/null; exit 3\\n' > fail; chmod +x fail; printf 'Content-Type: text/plain; filename=f\\n\\nx\\n' > m" "reformime -X ./fail" "m")
```
---
```output
[status 23]
```

### reformime: -x and -X together

```cu
(mm "printf 'x\\n' > m" "reformime -x a -X cat" "m")
```
---
```output
[status 1]
Usage: reformime [OPTIONS]

Parse MIME-encoded message on stdin

	-x PREFIX	Extract content of MIME sections to files
	-X PROG ARGS	Filter content of MIME sections through PROG
			Must be the last option

Other options are silently ignored
```

### reformime: no input

```cu
(mm ":" "reformime -x out/" "-")
```
---
```output
[status 0]
```

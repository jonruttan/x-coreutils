# @weight 4

sendmail as busybox's, against a scripted SMTP server on a free port of
127.0.0.1 that keeps each line it gets.  The server greets 220 (554 with FLAGS
no220), answers EHLO 250 (502 with noehlo), HELO, MAIL and NOOP 250, RCPT 250
-- 550 for an address with "bad" in it -- DATA 354, or 503 when no RCPT was
taken, the message's "." 250, AUTH LOGIN 334 334 235, AUTH PLAIN 334 235,
QUIT 221 and anything else 500; FLAGS none is no server.  sendmail runs in a
child with ARGS (split as sh splits them, P the port) and INPUT (as printf's
%b reads it) as the message.  Every expectation is busybox's own output for
the same case: stdout, the status, stderr, then what the server got, through
cat -v, the host's name shown as HOST.

## the fixture

### a server, a sendmail, and the report

```cu
(do (import x/sys/socket)
  (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-smtp && mkdir -p /tmp/x-cu-smtp"))
  (def sm-f (fn (_ n) (string-append "/tmp/x-cu-smtp/" n)))
  (def sm-lines (fn (_ s)
    (let go ((i 0) (acc ()))
      (let ((nl (%wget-index s #\newline i)))
        (if (null? nl) (reverse (if (< i (byte-len s)) (pair (substring s i (byte-len s)) acc) acc))
          (go (+ nl 1) (pair (substring s i nl) acc)))))))
  (def sm-sh (fn (_ script) (proc-run (list "/bin/sh" "-c" script))))
  (def sm-prep (fn (_ args input port)
    (sys-setenv "SM_ARGS" args) (sys-setenv "SM_IN" input) (sys-setenv "SM_PORT" (%cu-int->str port))
    (sm-sh (string-concat (list
      "d=/tmp/x-cu-smtp; rm -f $d/out $d/err $d/got $d/argv; printf '%b' \"$SM_IN\" > $d/in; : > $d/got; "
      "eval \"set -- $(printf ' %s ' \"$SM_ARGS\" | sed -e \"s/ P / $SM_PORT /g\" -e \"s/:P /:$SM_PORT /g\" -e \"s/ P'/ $SM_PORT'/g\" -e \"s/ P 2>/ $SM_PORT 2>/g\")\"; "
      "for a; do printf '%s\\n' \"$a\"; done > $d/argv")))
    (sm-lines (file-read-all (sm-f "argv")))))
  ; the server's reply to LINE in MODE: (REPLY . NEXT-MODE), REPLY nil for
  ; none and NEXT-MODE quit when the exchange ends
  (def sm-reply (fn (_ l mode flags rcpt?)
    (def has? (fn (_ s) (not (null? (Str8 index-of s l)))))
    (def r (fn (_ s) (string-append s "\r\n")))
    (match
      ((string=? mode "data") (if (string=? l ".") (pair (r "250 queued") "cmd") (pair () "data")))
      ((string=? mode "login1") (pair (r "334 UGFzc3dvcmQ6") "login2"))
      ((if (string=? mode "login2") #t (string=? mode "plain")) (pair (r "235 ok") "cmd"))
      ((Str8 starts? "EHLO" l) (pair (if (has?-flag flags "noehlo") (r "502 no") (string-append (r "250-test") (r "250 AUTH LOGIN PLAIN"))) "cmd"))
      ((if (Str8 starts? "HELO" l) #t (if (Str8 starts? "MAIL" l) #t (Str8 starts? "NOOP" l))) (pair (r "250 ok") "cmd"))
      ((if (Str8 starts? "RCPT" l) (has? "bad") #f) (pair (r "550 no such user") "cmd"))
      ((Str8 starts? "RCPT" l) (pair (r "250 ok") "rcpt"))
      ((Str8 starts? "DATA" l) (if rcpt? (pair (r "354 go") "data") (pair (r "503 no recipients") "cmd")))
      ((Str8 starts? "AUTH LOGIN" l) (pair (r "334 VXNlcm5hbWU6") "login1"))
      ((Str8 starts? "AUTH PLAIN" l) (pair (r "334 ") "plain"))
      ((Str8 starts? "QUIT" l) (pair (r "221 bye") "quit"))
      (#t (pair (r "500 what") "cmd")))))
  (def has?-flag (fn (_ flags f) (List any? (fn (_ w) (string=? w f)) (Str8 split " " flags))))
  (def sm-serve (fn (_ l flags)
    (def got (file-open-write (sm-f "got")))
    (def c (if (null? (sys-poll (list (pair l (list (lit in)))) 30000)) () (Socket accept l)))
    (unless (null? c)
      (do (Socket send c (if (has?-flag flags "no220") "554 go away\r\n" "220 test ESMTP\r\n"))
          (let go ((buf "") (mode "cmd") (rcpt? #f))
            (let ((nl (%wget-index buf #\newline 0)))
              (if (null? nl)
                (let ((r (if (null? (sys-poll (list (pair c (list (lit in)))) 10000)) () (guard (_ ()) (Socket recv-run c 4096)))))
                  (unless (null? r) (go (string-append buf (substring (first r) 0 (rest r))) mode rcpt?)))
                (let ((line (substring buf 0 nl)))
                  (do (file-write got (string-append line "\n"))
                      (let ((rp (sm-reply (Str8 replace "\r" "" line) mode flags rcpt?)))
                        (do (unless (null? (first rp)) (guard (_ ()) (Socket send c (first rp))))
                            (unless (string=? (rest rp) "quit")
                              (go (substring buf (+ nl 1) (byte-len buf))
                                  (if (string=? (rest rp) "rcpt") "cmd" (rest rp))
                                  (if rcpt? #t (string=? (rest rp) "rcpt")))))))))))
          (Socket close c)))
    (file-close got)))
  (def sm (fn (_ flags args input)
    (%cu-heap-collect)
    (def none? (string=? flags "none"))
    (def l (if none? () (Socket tcp-listen-on "127.0.0.1" 0 5)))
    (def port (if none? (let ((q (Socket tcp-listen 0))) (let ((n (Socket local-port q))) (do (Socket close q) n)))
                (Socket local-port l)))
    (def argv (sm-prep args input port))
    (def in (file-read-all (sm-f "in")))
    (sys-signal 13 1)
    (def pid (sys-fork))
    (when (= pid 0)
      (do (unless none? (Socket close l))
          (sys-dup2 (file-open-write (sm-f "out")) 1) (sys-dup2 (file-open-write (sm-f "err")) 2)
          (sys-exit (cu-run (pair "sendmail" argv) in))))
    (unless none? (do (sm-serve l flags) (Socket close l)))
    (def st (sys-wait pid))
    (sm-sh (string-concat (list
      "d=/tmp/x-cu-smtp; h=$(uname -n); { LC_ALL=C cat -v $d/out; echo \"[status " (%cu-int->str st) "]\"; "
      "sed -e \"s/$h/HOST/g\" -e \"s/:$SM_PORT/:PORT/g\" $d/err; "
      (if none? "" "echo '--- server got'; LC_ALL=C cat -v $d/got | sed \"s/$h/HOST/g\"; ")
      "} > $d/report")))
    (display (file-read-all (sm-f "report")))))
  (display "made"))
```
---
    made

## busybox's sendmail

### a message to one recipient: To added, leading dots doubled

```cu
(sm "" "-S 127.0.0.1:P -f me@x.org a@b.c" "Subject: hi\\n\\nhello\\n.dot\\n..two\\n")
```
---
```output
[status 0]
--- server got
EHLO HOST^M
MAIL FROM:<me@x.org>^M
RCPT TO:<a@b.c>^M
DATA^M
Subject: hi^M
To: a@b.c^M
^M
hello^M
..dot^M
...two^M
.^M
QUIT^M
```

### two recipients: a To list

```cu
(sm "" "-S 127.0.0.1:P -f me@x.org a@b.c d@e.f" "Subject: hi\\n\\nbody\\n")
```
---
```output
[status 0]
--- server got
EHLO HOST^M
MAIL FROM:<me@x.org>^M
RCPT TO:<a@b.c>^M
RCPT TO:<d@e.f>^M
DATA^M
Subject: hi^M
To: a@b.c,^M
 d@e.f^M
^M
body^M
.^M
QUIT^M
```

### a To: header already: none added

```cu
(sm "" "-S 127.0.0.1:P -f me@x.org a@b.c" "To: x@y.z\\nSubject: s\\n\\nbody\\n")
```
---
```output
[status 0]
--- server got
EHLO HOST^M
MAIL FROM:<me@x.org>^M
RCPT TO:<a@b.c>^M
DATA^M
To: x@y.z^M
Subject: s^M
^M
body^M
.^M
QUIT^M
```

### -t: To, Cc and Bcc read, Bcc dropped

```cu
(sm "" "-S 127.0.0.1:P -t -f me@x.org" "To: a@b.c, \"Doe, J\" <j@d.e>\\nCc: c@d.e\\nBcc: h@i.j\\nSubject: s\\n\\nbody\\n")
```
---
```output
[status 0]
--- server got
EHLO HOST^M
MAIL FROM:<me@x.org>^M
RCPT TO:<a@b.c>^M
RCPT TO:<j@d.e>^M
RCPT TO:<c@d.e>^M
RCPT TO:<h@i.j>^M
DATA^M
To: a@b.c, "Doe, J" <j@d.e>^M
Cc: c@d.e^M
Subject: s^M
^M
body^M
.^M
QUIT^M
```

### -t: a continuation line adds recipients

```cu
(sm "" "-S 127.0.0.1:P -t -f me@x.org" "To: a@b.c,\\n  d@e.f\\nSubject: s\\n\\nbody\\n")
```
---
```output
[status 0]
--- server got
EHLO HOST^M
MAIL FROM:<me@x.org>^M
RCPT TO:<a@b.c>^M
RCPT TO:<d@e.f>^M
DATA^M
To: a@b.c,^M
  d@e.f^M
Subject: s^M
^M
body^M
.^M
QUIT^M
```

### a recipient refused

```cu
(sm "" "-S 127.0.0.1:P -f me@x.org a@b.c bad@b.c" "Subject: s\\n\\nbody\\n")
```
---
```output
[status 0]
sendmail: Bad recipient: <bad@b.c>
--- server got
EHLO HOST^M
MAIL FROM:<me@x.org>^M
RCPT TO:<a@b.c>^M
RCPT TO:<bad@b.c>^M
DATA^M
Subject: s^M
To: a@b.c,^M
 bad@b.c^M
^M
body^M
.^M
QUIT^M
```

### every recipient refused: DATA fails, QUIT

```cu
(sm "" "-S 127.0.0.1:P -f me@x.org bad@b.c" "Subject: s\\n\\nbody\\n")
```
---
```output
[status 0]
sendmail: Bad recipient: <bad@b.c>
--- server got
EHLO HOST^M
MAIL FROM:<me@x.org>^M
RCPT TO:<bad@b.c>^M
DATA^M
QUIT^M
```

### a bad address

```cu
(sm "" "-S 127.0.0.1:P -f me@x.org 'a b@c' ok@d.e" "Subject: s\\n\\nbody\\n")
```
---
```output
[status 0]
sendmail: bad address 'a b@c'
--- server got
EHLO HOST^M
MAIL FROM:<me@x.org>^M
RCPT TO:<ok@d.e>^M
DATA^M
Subject: s^M
To: ,^M
 ok@d.e^M
^M
body^M
.^M
QUIT^M
```

### no headers, no recipients

```cu
(sm "" "-S 127.0.0.1:P -f me@x.org" "")
```
---
```output
[status 0]
--- server got
EHLO HOST^M
MAIL FROM:<me@x.org>^M
DATA^M
QUIT^M
```

### an empty message to one recipient

```cu
(sm "" "-S 127.0.0.1:P -f me@x.org a@b.c" "")
```
---
```output
[status 0]
--- server got
EHLO HOST^M
MAIL FROM:<me@x.org>^M
RCPT TO:<a@b.c>^M
DATA^M
To: a@b.c^M
^M
.^M
QUIT^M
```

### a body with no blank line before it

```cu
(sm "" "-S 127.0.0.1:P -f me@x.org a@b.c" "just text\\nmore\\n")
```
---
```output
[status 0]
--- server got
EHLO HOST^M
MAIL FROM:<me@x.org>^M
RCPT TO:<a@b.c>^M
DATA^M
To: a@b.c^M
just text^M
more^M
.^M
QUIT^M
```

### CRLF input

```cu
(sm "" "-S 127.0.0.1:P -f me@x.org a@b.c" "Subject: s\\r\\n\\r\\nbody\\r\\n")
```
---
```output
[status 0]
--- server got
EHLO HOST^M
MAIL FROM:<me@x.org>^M
RCPT TO:<a@b.c>^M
DATA^M
Subject: s^M^M
^M^M
To: a@b.c^M
body^M^M
.^M
QUIT^M
```

### EHLO refused: HELO

```cu
(sm "noehlo" "-S 127.0.0.1:P -f me@x.org a@b.c" "Subject: s\\n\\nbody\\n")
```
---
```output
[status 0]
--- server got
EHLO HOST^M
HELO HOST^M
MAIL FROM:<me@x.org>^M
RCPT TO:<a@b.c>^M
DATA^M
Subject: s^M
To: a@b.c^M
^M
body^M
.^M
QUIT^M
```

### no 220 greeting

```cu
(sm "no220" "-S 127.0.0.1:P -f me@x.org a@b.c" "Subject: s\\n\\nbody\\n")
```
---
```output
[status 1]
sendmail: (null) failed
--- server got
```

### AUTH LOGIN with -au -ap

```cu
(sm "" "-S 127.0.0.1:P -f me@x.org -auuser -appass a@b.c" "Subject: s\\n\\nbody\\n")
```
---
```output
[status 0]
--- server got
EHLO HOST^M
AUTH LOGIN^M
dXNlcg==^M
cGFzcw==^M
MAIL FROM:<me@x.org>^M
RCPT TO:<a@b.c>^M
DATA^M
Subject: s^M
To: a@b.c^M
^M
body^M
.^M
QUIT^M
```

### AUTH PLAIN

```cu
(sm "" "-S 127.0.0.1:P -f me@x.org -amPLAIN -auuser -appass a@b.c" "Subject: s\\n\\nbody\\n")
```
---
```output
[status 0]
--- server got
EHLO HOST^M
AUTH PLAIN^M
AHVzZXIAcGFzcw==^M
MAIL FROM:<me@x.org>^M
RCPT TO:<a@b.c>^M
DATA^M
Subject: s^M
To: a@b.c^M
^M
body^M
.^M
QUIT^M
```

### an AUTH method not supported

```cu
(sm "" "-S 127.0.0.1:P -f me@x.org -amCRAM-MD5 -auu -app a@b.c" "x\\n")
```
---
```output
[status 1]
sendmail: unsupported AUTH method CRAM-MD5
--- server got
```

### an empty sender

```cu
(sm "" "-S 127.0.0.1:P -f '' a@b.c" "Subject: s\\n\\nbody\\n")
```
---
```output
[status 0]
--- server got
EHLO HOST^M
MAIL FROM:<>^M
RCPT TO:<a@b.c>^M
DATA^M
Subject: s^M
To: a@b.c^M
^M
body^M
.^M
QUIT^M
```

### -v: what is sent and received

```cu
(sm "" "-S 127.0.0.1:P -v -f me@x.org a@b.c" "Subject: s\\n\\nbody\\n")
```
---
```output
[status 0]
sendmail: recv:'220 test ESMTP'
sendmail: send:'EHLO HOST'
sendmail: recv:'250-test'
sendmail: recv:'250 AUTH LOGIN PLAIN'
sendmail: send:'MAIL FROM:<me@x.org>'
sendmail: recv:'250 ok'
sendmail: send:'RCPT TO:<a@b.c>'
sendmail: recv:'250 ok'
sendmail: send:'DATA'
sendmail: recv:'354 go'
sendmail: send:'Subject: s'
sendmail: send:'To: a@b.c'
sendmail: send:''
sendmail: send:'body'
sendmail: send:'.'
sendmail: recv:'250 queued'
sendmail: send:'QUIT'
sendmail: recv:'221 bye'
--- server got
EHLO HOST^M
MAIL FROM:<me@x.org>^M
RCPT TO:<a@b.c>^M
DATA^M
Subject: s^M
To: a@b.c^M
^M
body^M
.^M
QUIT^M
```

### -H: through a connection helper

```cu
(sm "" "-f me@x.org -H 'nc 127.0.0.1 P 2>/dev/null' a@b.c" "Subject: s\\n\\nbody\\n")
```
---
```output
[status 0]
--- server got
NOOP^M
EHLO HOST^M
MAIL FROM:<me@x.org>^M
RCPT TO:<a@b.c>^M
DATA^M
Subject: s^M
To: a@b.c^M
^M
body^M
.^M
QUIT^M
```

### -o and -i accepted

```cu
(sm "" "-S 127.0.0.1:P -oi -i -f me@x.org a@b.c" "Subject: s\\n\\nbody\\n")
```
---
```output
[status 0]
--- server got
EHLO HOST^M
MAIL FROM:<me@x.org>^M
RCPT TO:<a@b.c>^M
DATA^M
Subject: s^M
To: a@b.c^M
^M
body^M
.^M
QUIT^M
```

### nothing listening

```cu
(sm "none" "-S 127.0.0.1:P -f me@x.org a@b.c" "x\\n")
```
---
```output
[status 1]
sendmail: can't connect to remote host (127.0.0.1): Connection refused
```

### -H and -S together

```cu
(sm "none" "-H cat -S 127.0.0.1 a@b.c" "x\\n")
```
---
```output
[status 1]
Usage: sendmail [-tv] [-f SENDER] [-amLOGIN 4<user_pass.txt | -auUSER -apPASS]
		[-w SECS] [-H 'PROG ARGS' | -S HOST] [RECIPIENT_EMAIL]...

Read email from stdin and send it

Standard options:
	-t		Read additional recipients from message body
	-f SENDER	For use in MAIL FROM:<sender>. Can be empty string
			Default: -auUSER, or username of current UID
	-o OPTIONS	Various options. -oi implied, others are ignored
	-i		-oi synonym, implied and ignored

Busybox specific options:
	-v		Verbose
	-w SECS		Network timeout
	-H 'PROG ARGS'	Run connection helper. Examples:
		openssl s_client -quiet -tls1 -starttls smtp -connect smtp.gmail.com:25
		openssl s_client -quiet -tls1 -connect smtp.gmail.com:465
			$SMTP_ANTISPAM_DELAY: seconds to wait after helper connect
	-S HOST[:PORT]	Server (default $SMTPHOST or 127.0.0.1)
	-amLOGIN	Log in using AUTH LOGIN
	-amPLAIN	or AUTH PLAIN
			(-amCRAM-MD5 not supported)
	-auUSER		Username for AUTH
	-apPASS 	Password for AUTH

If no -a options are given, authentication is not done.
If -amLOGIN is given but no -au/-ap, user/password is read from fd #4.
Other options are silently ignored; -oi is implied.
Use makemime to create emails with attachments.
```

# @weight 2

wget as busybox's, over the platform's Http.  Each case's server is a
forked child serving its responses in order, one a connection, then
accepting and closing every later connection with no reply -- as busybox's
`nc -lk -e` does in the oracle runs every expectation here comes from.  In
a case's arguments, U/ is that server's url and D the case's directory;
the report gives stdout, stderr and the status, then each file the run
left in D, with the directory and the port spelled D and PORT.

## the fixture

### a server, a run, and its report

```cu
(do (import x/sys/socket) (sys-unsetenv "COLUMNS") (def wg-dir "/tmp/x-cu-wg") (def wg-cap "/tmp/x-cu-net.cap") (def wg-port "") (def wg-drain (fn (_ c) (let go ((acc "")) (if (Str8 includes? "\r\n\r\n" acc) acc (let ((r (Socket recv c 4096))) (if (null? r) acc (go (string-append acc r)))))))) (def wg-child (fn (_ lfd url resps) (do (guard (e ()) (let loop ((rs resps)) (let ((c (Socket accept lfd))) (do (let ((rq (wg-drain c)) (fd (file-open-append (string-append wg-cap "/req")))) (do (file-write fd rq) (file-close fd))) (unless (null? rs) (Socket send c (Str8 replace "U/" url (first rs)))) (Socket close c) (loop (if (null? rs) () (rest rs))))))) (sys-exec "/bin/sh" (list "-c" "exit 0"))))) (def wg-less? (fn (self a b i) (match ((>= i (byte-len a)) (< i (byte-len b))) ((>= i (byte-len b)) #f) ((< (byte-at a i) (byte-at b i)) #t) ((> (byte-at a i) (byte-at b i)) #f) (#t (self a b (+ i 1)))))) (def wg-sort (fn (_ l) (let ins ((l l) (acc ())) (if (null? l) acc (ins (rest l) (let put ((x (first l)) (s acc)) (if (null? s) (list x) (if (wg-less? x (first s) 0) (pair x s) (pair (first s) (put x (rest s))))))))))) (def wg-files (fn (_) (string-concat (map (fn (_ f) (let ((t (file-read-all (string-concat (list wg-dir "/" f))))) (string-concat (list "file " f ":\n" t (if (if (> (byte-len t) 0) (= (byte-at t (- (byte-len t) 1)) 10) #t) "" "\n"))))) (wg-sort (filter (fn (_ f) (not (if (string=? f ".") #t (string=? f "..")))) (file-list-dir wg-dir))))))) (def wg (fn (_ name resps args) (do (proc-run (list "/bin/sh" "-c" (string-concat (list "rm -rf " wg-dir " " wg-cap " && mkdir -p " wg-dir " " wg-cap)))) (when (string=? name "exists") (file-write-all (string-append wg-dir "/f") "old\n")) (when (Str8 starts? "continue" name) (file-write-all (string-append wg-dir "/f") "hel")) (def lfd (Socket tcp-listen 0)) (def port (%cu-int->str (Socket local-port lfd))) (set! wg-port port) (def url (string-concat (list "http://127.0.0.1:" port "/"))) (def pid (if (string=? name "refused") -1 (sys-fork))) (when (= pid 0) (wg-child lfd url resps)) (Socket close lfd) (def argv (map (fn (_ a) (match ((string=? a "D") wg-dir) ((Str8 starts? "D/" a) (string-append wg-dir (substring a 1 (byte-len a)))) ((Str8 starts? "U/" a) (string-append url (substring a 2 (byte-len a)))) ((Str8 starts? "U?" a) (string-append (substring url 0 (- (byte-len url) 1)) (substring a 1 (byte-len a)))) ((Str8 starts? "R/" a) (string-append url (substring a 2 (byte-len a)))) ((Str8 includes? "@U/" a) (Str8 replace "@U/" (string-concat (list "@127.0.0.1:" port "/")) a)) (#t a))) args)) (sys-dup2 1 9) (sys-dup2 2 8) (def oo (file-open-write (string-append wg-cap "/out"))) (def ee (file-open-write (string-append wg-cap "/err"))) (sys-dup2 oo 1) (sys-dup2 ee 2) (let tick ((s0 (date-now-unix))) (when (= (date-now-unix) s0) (do (sys-usleep 20000) (tick s0)))) (def st (guard (e (do (file-write 2 (string-append "raised: " (if (Err err? e) (e msg) (if (string? e) e "?")))) -1)) (cu-run (pair "wget" argv) ""))) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (when (> pid 0) (do (sys-kill pid 9) (sys-wait pid))) (display (Str8 replace (string-append ":" port) ":PORT" (Str8 replace wg-dir "D" (Str8 replace (string-append wg-dir "/") "" (string-concat (list (file-read-all (string-append wg-cap "/out")) "stderr:\n" (file-read-all (string-append wg-cap "/err")) "status " (%cu-int->str st) "\n" (wg-files)))))))))) (def wg-req (fn (_) (display (string-append "request:\n" (Str8 replace (string-append ":" wg-port) ":PORT" (Str8 replace "\r" "" (file-read-all (string-append wg-cap "/req")))))))) (display "made"))
```
---
    made

## busybox's behaviour

### plain

```cu
(wg "plain" (list "HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n") (list "-P" "D" "U/f.txt"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'f.txt'
f.txt                100% |********************************|     6  0:00:00 ETA
'f.txt' saved
status 0
file f.txt:
hello
```

### quiet-stdout

```cu
(wg "quiet-stdout" (list "HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n") (list "-q" "-O" "-" "U/f.txt"))
```
---
```output
hello
stderr:
status 0
```

### named

```cu
(wg "named" (list "HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n") (list "-O" "D/g" "U/f.txt"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'g'
g                    100% |********************************|     6  0:00:00 ETA
'g' saved
status 0
file g:
hello
```

### index

```cu
(wg "index" (list "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\n<i>\n") (list "-P" "D" "U/"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'index.html'
index.html           100% |********************************|     4  0:00:00 ETA
'index.html' saved
status 0
file index.html:
<i>
```

### 404-S

```cu
(wg "404-S" (list "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n") (list "-S" "-P" "D" "U/nope"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
  HTTP/1.1 404 Not Found
wget: server returned error: HTTP/1.1 404 Not Found
status 1
```

### spider

```cu
(wg "spider" (list "HTTP/1.1 200 OK\r\nX-A: 1\r\nContent-Length: 6\r\n\r\nhello\n") (list "-S" "--spider" "U/f.txt"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
  HTTP/1.1 200 OK
  X-A: 1
  Content-Length: 6
  
remote file exists
status 0
```

### chunked

```cu
(wg "chunked" (list "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n2;x=1\r\nde\r\n0\r\n\r\n") (list "-P" "D" "U/c"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'c'
c                    100% |********************************|     5  0:00:00 ETA
'c' saved
status 0
file c:
abcde
```

### nolen

```cu
(wg "nolen" (list "HTTP/1.0 200 OK\r\n\r\nnolen") (list "-t" "1" "-P" "D" "U/n"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'n'
n                        5 --:--:-- ETA
wget: connection closed at byte 5
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
wget: error getting response
status 1
file n:
nolen
```

### nolen-retry

```cu
(wg "nolen-retry" (list "HTTP/1.0 200 OK\r\n\r\nnol" "HTTP/1.1 206 Partial Content\r\nContent-Length: 2\r\n\r\nen") (list "-t" "1" "-P" "D" "U/n"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'n'
n                        3 --:--:-- ETA
wget: connection closed at byte 3
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'n'
n                    100% |********************************|     5  0:00:00 ETA
'n' saved
status 0
file n:
nolen
```

### short

```cu
(wg "short" (list "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nshort") (list "-t" "0" "-P" "D" "U/s"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 's'
s                     50% |****************                |     5  0:00:00 ETA
wget: connection closed at byte 5
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
wget: error getting response
status 1
file s:
short
```

### gzip

```cu
(wg "gzip" (list "HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip\r\n\r\nzz") (list "-P" "D" "U/g"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
wget: transfer encoding 'gzip' is not supported
status 1
```

### badlen

```cu
(wg "badlen" (list "HTTP/1.1 200 OK\r\nContent-Length: x5\r\n\r\nzz") (list "-P" "D" "U/b"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
wget: content-length x5 is garbage
status 1
```

### badline

```cu
(wg "badline" (list "HTTP/1.1 200 OK\r\nNo colon here\r\n\r\nzz") (list "-P" "D" "U/b"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
wget: bad header line: no colon here
status 1
```

### redirect-abs

```cu
(wg "redirect-abs" (list "HTTP/1.1 302 Found\r\nX-A: 1\r\nLocation: U/b\r\nX-B: 2\r\n\r\n" "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok") (list "-S" "-P" "D" "U/a"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
  HTTP/1.1 302 Found
  X-A: 1
  Location: http://127.0.0.1:PORT/b
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
  HTTP/1.1 200 OK
  Content-Length: 2
  
saving to 'a'
a                    100% |********************************|     2  0:00:00 ETA
'a' saved
status 0
file a:
ok
```

### redirect-path

```cu
(wg "redirect-path" (list "HTTP/1.1 301 Moved\r\nLocation: /b\r\n\r\n" "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok") (list "-P" "D" "U/a"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'a'
a                    100% |********************************|     2  0:00:00 ETA
'a' saved
status 0
file a:
ok
```

### 

```cu
(wg "" (list "-q -P D U/a") (list))
```
---
```output
stderr:
Usage: wget [-cqS] [--spider] [-O FILE] [-o LOGFILE] [--header STR]...
	[-U AGENT] [--post-data STR | --post-file FILE] [-Y on/off]
	[--no-check-certificate] [-P DIR] [-T SEC] [-t TRIES] URL...

Retrieve files via HTTP or FTP

	--spider	Only check URL existence: $? is 0 if exists
	--header STR	Add STR (of form 'header: value') to headers
	-U AGENT	Use AGENT for User-Agent header
	--post-data STR	Send STR using POST method
	--post-file FILE	Send FILE using POST method
	--no-check-certificate	Don't validate the server's certificate
	-c		Continue retrieval of partial download
	-q		Quiet
	-P DIR		Save to DIR (default .)
	-S    		Show server response
	-t TRIES	Retry count (default 20)
	-T SEC		Network read timeout is SEC seconds
	-O FILE		Save to FILE ('-' for stdout)
	-o LOGFILE	Log messages to FILE
	-Y on/off	Use proxy
status 1
```

### zero

```cu
(wg "zero" (list "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n") (list "-P" "D" "U/z"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'z'
z                        0 --:--:-- ETA
'z' saved
status 0
file z:
```

### 204

```cu
(wg "204" (list "HTTP/1.1 204 No Content\r\n\r\n") (list "-t" "1" "-P" "D" "U/z"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'z'
z                        0 --:--:-- ETA
wget: connection closed at byte 0
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
wget: error getting response
status 1
file z:
```

### noresp

```cu
(wg "noresp" (list) (list "-P" "D" "U/z"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
wget: error getting response
status 1
```

### log

```cu
(wg "log" (list "HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n") (list "-o" "D/lg" "-P" "D" "U/f.txt"))
```
---
```output
stderr:
status 0
file f.txt:
hello
file lg:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'f.txt'
'f.txt' saved
```

### continue

```cu
(wg "continue" (list "HTTP/1.1 206 Partial Content\r\nContent-Length: 3\r\n\r\nlo\n") (list "-c" "-O" "D/f" "U/f.txt"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'f'
f                    100% |********************************|     6  0:00:00 ETA
'f' saved
status 0
file f:
hello
```

### continue-200

```cu
(wg "continue-200" (list "HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n") (list "-c" "-O" "D/f" "U/f.txt"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
wget: restart failed
saving to 'f'
f                    100% |********************************|     6  0:00:00 ETA
'f' saved
status 0
file f:
hello
```

### exists

```cu
(wg "exists" (list "HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nhello\n") (list "-P" "D" "U/f"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
wget: can't open 'f': File exists
status 1
file f:
old
```

### two-O

```cu
(wg "two-O" (list "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\na\n" "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nb\n") (list "-O" "D/all" "U/a" "U/b"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'all'
all                  100% |********************************|     2  0:00:00 ETA
'all' saved
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'all'
all                  100% |********************************|     2  0:00:00 ETA
'all' saved
status 0
file all:
a
b
```

### two-one-fails

```cu
(wg "two-one-fails" (list "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\na\n" "HTTP/1.1 500 Oops\r\n\r\n") (list "-P" "D" "U/a" "U/b"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'a'
a                    100% |********************************|     2  0:00:00 ETA
'a' saved
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
wget: server returned error: HTTP/1.1 500 Oops
status 1
file a:
a
```

### qmark

```cu
(wg "qmark" (list "HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nabc") (list "-P" "D" "U?a=b/c"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'c'
c                    100% |********************************|     3  0:00:00 ETA
'c' saved
status 0
file c:
abc
```

### badscheme

```cu
(wg "badscheme" (list) (list "-P" "D" "gopher://h/x"))
```
---
```output
stderr:
wget: not an http or ftp url: gopher://h/x
status 1
```

### badtries

```cu
(wg "badtries" (list) (list "-t" "x" "U/f"))
```
---
```output
stderr:
wget: invalid number 'x'
status 1
```

### noargs

```cu
(wg "noargs" (list) (list))
```
---
```output
stderr:
Usage: wget [-cqS] [--spider] [-O FILE] [-o LOGFILE] [--header STR]...
	[-U AGENT] [--post-data STR | --post-file FILE] [-Y on/off]
	[--no-check-certificate] [-P DIR] [-T SEC] [-t TRIES] URL...

Retrieve files via HTTP or FTP

	--spider	Only check URL existence: $? is 0 if exists
	--header STR	Add STR (of form 'header: value') to headers
	-U AGENT	Use AGENT for User-Agent header
	--post-data STR	Send STR using POST method
	--post-file FILE	Send FILE using POST method
	--no-check-certificate	Don't validate the server's certificate
	-c		Continue retrieval of partial download
	-q		Quiet
	-P DIR		Save to DIR (default .)
	-S    		Show server response
	-t TRIES	Retry count (default 20)
	-T SEC		Network read timeout is SEC seconds
	-O FILE		Save to FILE ('-' for stdout)
	-o LOGFILE	Log messages to FILE
	-Y on/off	Use proxy
status 1
```

### refused

```cu
(wg "refused" (list) (list "-P" "D" "R/x"))
```
---
```output
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
wget: can't connect to remote host (127.0.0.1): Connection refused
status 1
```

### redirect-loop

```cu
(wg "redirect-loop" (list "HTTP/1.1 302 Found\r\nLocation: /a\r\n\r\n" "HTTP/1.1 302 Found\r\nLocation: /a\r\n\r\n" "HTTP/1.1 302 Found\r\nLocation: /a\r\n\r\n" "HTTP/1.1 302 Found\r\nLocation: /a\r\n\r\n" "HTTP/1.1 302 Found\r\nLocation: /a\r\n\r\n" "HTTP/1.1 302 Found\r\nLocation: /a\r\n\r\n" "HTTP/1.1 302 Found\r\nLocation: /a\r\n\r\n" "HTTP/1.1 302 Found\r\nLocation: /a\r\n\r\n" "HTTP/1.1 302 Found\r\nLocation: /a\r\n\r\n" "HTTP/1.1 302 Found\r\nLocation: /a\r\n\r\n" "HTTP/1.1 302 Found\r\nLocation: /a\r\n\r\n" "HTTP/1.1 302 Found\r\nLocation: /a\r\n\r\n" "HTTP/1.1 302 Found\r\nLocation: /a\r\n\r\n" "HTTP/1.1 302 Found\r\nLocation: /a\r\n\r\n" "HTTP/1.1 302 Found\r\nLocation: /a\r\n\r\n" "HTTP/1.1 302 Found\r\nLocation: /a\r\n\r\n" "HTTP/1.1 302 Found\r\nLocation: /a\r\n\r\n") (list "-q" "-P" "D" "U/a"))
```
---
```output
stderr:
wget: too many redirections
status 1
```

## what the server is sent

The request carries the same headers as busybox's, in Http's order:
Host and Connection first, then the rest as busybox sends them.  Not
from the oracle; read against busybox's own request for the same flags.

### the user's headers, an agent of their own, and the url's credentials

```cu
(do (wg "req" (list "HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nok\n") (list "-q" "-O" "-" "--header" "X-A: 1" "--header" "User-Agent: Mine" "--header=X-B:2" "http://u%20x:p%40w@U/p?q=1#frag")) (wg-req))
```
---
```output
ok
stderr:
status 0
request:
GET /p?q=1#frag HTTP/1.1
Host: 127.0.0.1:PORT
Connection: close
Authorization: Basic dSB4OnBAdw==
X-A: 1
User-Agent: Mine
X-B: 2

```

### -U names the agent; --post-data posts a form

```cu
(do (wg "req" (list "HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nok\n") (list "-q" "-O" "-" "-U" "Me" "--post-data" "a=b" "U/f")) (wg-req))
```
---
```output
ok
stderr:
status 0
request:
POST /f HTTP/1.1
Host: 127.0.0.1:PORT
Connection: close
Content-Length: 3
User-Agent: Me
Content-Type: application/x-www-form-urlencoded

a=b
```

### --post-file posts a file's text; a file that is not there ends the run after the Connecting line

```cu
(do (file-write-all "/tmp/x-cu-net.pf" "k=v") (wg "req" (list "HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nok\n") (list "-q" "-O" "-" "--post-file" "/tmp/x-cu-net.pf" "U/")) (wg-req) (wg "nofile" (list "HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nok\n") (list "--post-file" "/tmp/x-cu-net.none" "-P" "D" "U/")))
```
---
```output
ok
stderr:
status 0
request:
POST / HTTP/1.1
Host: 127.0.0.1:PORT
Connection: close
Content-Length: 3
User-Agent: Wget
Content-Type: application/x-www-form-urlencoded

k=vstderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
wget: can't open '/tmp/x-cu-net.none': No such file or directory
status 1
```

## https

`openssl s_server` relays a canned response from its standard input over
a certificate made for the run.  A server's certificate is checked, as
busybox's openssl helper checks it: one that does not verify is
"error getting response", and --no-check-certificate skips the check.

### --no-check-certificate reads from a self-signed server; without it the run fails

```cu
(do (def wgs (fn (_ args) (do (def p (Socket tcp-listen 0)) (def port (%cu-int->str (Socket local-port p))) (Socket close p) (proc-run (list "/bin/sh" "-c" (string-concat (list "mkdir -p /tmp/x-cu-net.tls && cd /tmp/x-cu-net.tls && { [ -f cert.pem ] || openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 1 -subj /CN=localhost >/dev/null 2>&1; } && printf 'HTTP/1.1 200 OK\\r\\nContent-Length: 4\\r\\n\\r\\ntls\\n' > resp && { openssl s_server -quiet -naccept 1 -accept " port " -cert cert.pem -key key.pem < resp >/dev/null 2>&1 & echo $! > pid; } && sleep 1")))) (sys-dup2 1 9) (sys-dup2 2 8) (def oo (file-open-write "/tmp/x-cu-net.tls/out")) (def ee (file-open-write "/tmp/x-cu-net.tls/err")) (sys-dup2 oo 1) (sys-dup2 ee 2) (let tick ((s0 (date-now-unix))) (when (= (date-now-unix) s0) (do (sys-usleep 20000) (tick s0)))) (def st (guard (e -1) (cu-run (pair "wget" (append args (list (string-concat (list "https://127.0.0.1:" port "/x"))))) ""))) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (proc-run (list "/bin/sh" "-c" "kill $(cat /tmp/x-cu-net.tls/pid) 2>/dev/null; true")) (display (Str8 replace (string-append ":" port) ":PORT" (string-concat (list (file-read-all "/tmp/x-cu-net.tls/out") "stderr:\n" (file-read-all "/tmp/x-cu-net.tls/err") "status " (%cu-int->str st) "\n"))))))) (wgs (list "--no-check-certificate" "-O" "-")) (wgs (list "-O" "-")))
```
---
```output
tls
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
writing to stdout
-                    100% |********************************|     4  0:00:00 ETA
written to stdout
status 0
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
wget: error getting response
status 1
```

## what the network did not do is not reported as the network

### a refusal and a failed exchange in busybox's words; anything else as it is

A platform without Http open, say, raises something that is neither an io
failure nor Http's report of a head it could not read: wget lets it through
with its own message rather than calling it "error getting response".

```cu
(do (import x/sys/socket) (def wf-p (Socket tcp-listen 0)) (def wf-port (Socket local-port wf-p)) (Socket close wf-p) (def wf-refused (guard (e e) (net-connect "127.0.0.1" wf-port))) (def wf-tls (guard (e e) (Err raise (lit io) "Tls: handshake failed" -1))) (def wf-head (guard (e e) (Err raise (lit value) "Http: bad response: no header terminator" ()))) (def wf-other (guard (e e) (Err raise (lit value) "no such static member open" ()))) (write (list (%whois-after (%wget-open-failure wf-refused "127.0.0.1") "can't connect to remote host (127.0.0.1): ") (%wget-open-failure wf-tls "1.2.3.4") (%wget-open-failure wf-head "1.2.3.4") (%wget-open-failure wf-other "1.2.3.4"))))
```
---
    ("Connection refused" "error getting response" "error getting response" ())

## size

### a megabyte is written as it arrives, every byte of it

```cu
(do (def lfd (Socket tcp-listen 0)) (def port (%cu-int->str (Socket local-port lfd))) (def pid (sys-fork)) (when (= pid 0) (do (guard (e ()) (let ((c (Socket accept lfd))) (do (wg-drain c) (Socket send c "HTTP/1.1 200 OK\r\nContent-Length: 1048576\r\n\r\n") (let go ((k 0)) (when (< k 16) (do (Socket send c (Str8 repeat 1024 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")) (go (+ k 1))))) (Socket close c)))) (sys-exec "/bin/sh" (list "-c" "exit 0")))) (Socket close lfd) (def st (cu-run (list "wget" "-q" "-O" "/tmp/x-cu-net.big" (string-concat (list "http://127.0.0.1:" port "/big"))) "")) (sys-kill pid 9) (sys-wait pid) (display (list st (Assoc get (lit size) (file-stat "/tmp/x-cu-net.big")))))
```
---
    (0 1048576)

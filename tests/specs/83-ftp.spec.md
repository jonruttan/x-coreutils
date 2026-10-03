# @weight 2

ftpget, ftpput and wget's ftp:// urls as busybox's.  The server is a forked
child speaking busybox's ftpd as `tcpsvd 127.0.0.1 PORT ftpd -w -a root D/srv`
answers -- its replies word for word, anonymous logged in at USER, any other
name asked a password and refused it -- on an ephemeral port, P in the
arguments; R is a port nothing listens on.  D/srv holds small.txt (6 bytes),
big.bin (70000 bytes) and an empty file; each run starts in an empty D/work.
Every expectation is busybox's own output for the same command against
busybox's ftpd; the report gives the status, stdout and stderr, each file left
in D/work (its size and first 40 bytes), and each file a put left in D/srv,
with the port spelled PORT and an EPSV reply's data port DPORT.  The progress
meter's clock is held still for each run, so a run that crosses a second
draws only the lines busybox draws within one.

## the fixture

### a server, a run, and its report

```cu
(do (import x/sys/socket) (sys-unsetenv "COLUMNS")
  (def fp "/tmp/x-cu-net.fp")
  (def fp-home (sys-getcwd))
  (def fp-buf "")
  (def fp-user "")
  (def fp-rest 0)
  (def fp-dl ())
  (def fp-line (fn (self c)
    (let ((nl (%wget-index fp-buf #\newline 0)))
      (if (null? nl)
        (let ((r (Socket recv-run c 4096)))
          (if (null? r) ()
            (do (set! fp-buf (string-append fp-buf (substring (first r) 0 (rest r)))) (self c))))
        (let ((l (substring fp-buf 0 nl)))
          (do (set! fp-buf (substring fp-buf (+ nl 1) (byte-len fp-buf)))
              (if (if (> (byte-len l) 0) (= (byte-at l (- (byte-len l) 1)) #\return) #f)
                (substring l 0 (- (byte-len l) 1)) l)))))))
  (def fp-say (fn (_ c s) (Socket send c (string-append s "\r\n"))))
  (def fp-file? (fn (_ name)
    (let ((path (string-concat (list fp "/srv/" name))))
      (if (= (byte-len name) 0) #f (if (file-exists? path) (not (file-dir? path)) #f)))))
  (def fp-size (fn (_ name) (Assoc get (lit size) (file-stat (string-concat (list fp "/srv/" name))))))
  (def fp-listen (fn (_)
    (do (unless (null? fp-dl) (Socket close fp-dl))
        (set! fp-dl (Socket tcp-listen 0))
        (Socket local-port fp-dl))))
  (def fp-retr (fn (_ c name)
    (match
      ((null? fp-dl) (fp-say c "425 Use PORT/PASV first"))
      ((not (fp-file? name)) (fp-say c "550 Error"))
      (#t
        (let ((d (Socket accept fp-dl)) (text (file-read-all (string-concat (list fp "/srv/" name)))))
          (do (fp-say c (string-concat (list "150 Opening BINARY connection for " name
                                             " (" (%cu-int->str (fp-size name)) " bytes)")))
              (Socket send d (substring text fp-rest (byte-len text)))
              (Socket close d) (Socket close fp-dl) (set! fp-dl ())
              (fp-say c "226 Operation successful")))))
    (set! fp-rest 0)))
  (def fp-stor (fn (_ c name)
    (let ((fd (file-open-or-err file-open-write (string-concat (list fp "/srv/" name)))))
      (if (Err err? fd) (fp-say c "553 Error")
        (let ((d (Socket accept fp-dl)))
          (do (fp-say c "150 Ok to send data")
              (let go () (let ((r (Socket recv-run d 65536))) (unless (null? r) (do (file-write-run fd r) (go)))))
              (file-close fd) (Socket close d) (Socket close fp-dl) (set! fp-dl ())
              (fp-say c "226 Operation successful")))))))
  (def fp-cmd (fn (_ c cmd arg)
    (match
      ((string=? cmd "USER")
        (do (set! fp-user arg)
            (fp-say c (if (string=? arg "anonymous") "230 Operation successful" "331 Specify password"))))
      ((string=? cmd "PASS")
        (fp-say c (if (string=? fp-user "anonymous") "230 Operation successful" "530 Login failed")))
      ((string=? cmd "TYPE") (fp-say c "200 Operation successful"))
      ((string=? cmd "SIZE")
        (fp-say c (if (fp-file? arg) (string-append "213 " (%cu-int->str (fp-size arg))) "550 Error")))
      ((string=? cmd "EPSV")
        (fp-say c (string-concat (list "229 EPSV ok (|||" (%cu-int->str (fp-listen)) "|)"))))
      ((string=? cmd "PASV")
        (let ((p (fp-listen)))
          (fp-say c (string-concat (list "227 PASV ok (127,0,0,1," (%cu-int->str (%wget-div p 256)) ","
                                         (%cu-int->str (% p 256)) ")")))))
      ((string=? cmd "REST") (do (set! fp-rest (%wget-digits arg)) (fp-say c "350 Operation successful")))
      ((string=? cmd "RETR") (fp-retr c arg))
      ((string=? cmd "STOR") (fp-stor c arg))
      (#t (fp-say c "500 Unknown command")))))
  (def fp-session (fn (self c)
    (let ((l (fp-line c)))
      (unless (null? l)
        (let ((sp (%wget-index l #\space 0)))
          (let ((cmd (if (null? sp) l (substring l 0 sp)))
                (arg (if (null? sp) "" (substring l (+ sp 1) (byte-len l)))))
            (if (string=? cmd "QUIT") (fp-say c "221 Operation successful")
              (do (fp-cmd c cmd arg) (self c)))))))))
  (def fp-serve (fn (_ lfd)
    (do (guard (_ ())
          (let loop ()
            (let ((c (Socket accept lfd)))
              (do (set! fp-buf "") (set! fp-user "") (set! fp-rest 0) (set! fp-dl ())
                  (fp-say c "220 Operation successful")
                  (fp-session c)
                  (Socket close c)
                  (loop)))))
        (sys-exec "/bin/sh" (list "-c" "exit 0")))))
  (def fp-files (fn (_ dir pre)
    (string-concat
      (map (fn (_ f)
             (let ((path (string-concat (list dir "/" f))))
               (if (file-dir? path) (fp-files path (string-concat (list pre f "/")))
                 (let ((t (file-read-all path)))
                   (string-concat (list "file " pre f ": " (%cu-int->str (byte-len t)) " bytes\n"
                                        (substring t 0 (if (> (byte-len t) 40) 40 (byte-len t))) "\n"))))))
           (filter (fn (_ f) (not (if (string=? f ".") #t (string=? f "..")))) (file-list-dir dir))))))
  (def fp-srv (fn (_)
    (string-concat
      (map (fn (_ f) (string-concat (list "srv " f ":\n" (file-read-all (string-concat (list fp "/srv/" f))))))
           (filter (fn (_ f) (not (%cu-member-s? f (list "." ".." "small.txt" "big.bin" "empty"))))
                   (file-list-dir (string-append fp "/srv")))))))
  (def fp-dport (fn (self s)
    (let ((i (%wget-find s "(|||")))
      (if (null? i) s
        (let ((j (%wget-index s #\| (+ i 4))))
          (string-concat (list (substring s 0 (+ i 4)) "DPORT"
                               (self (substring s j (byte-len s))))))))))
  (def fp-case (fn (_ pre args input)
    (proc-run (list "/bin/sh" "-c" (string-concat (list "rm -rf " fp " && mkdir -p " fp "/srv " fp "/work && cd " fp " && printf 'hello\\n' > srv/small.txt && : > srv/empty && awk 'BEGIN { for (i = 0; i < 70000; i++) printf \"%c\", 65 + i % 26 }' > srv/big.bin && cd work && " pre))))
    (def lfd (Socket tcp-listen 0))
    (def port (%cu-int->str (Socket local-port lfd)))
    (def rfd (Socket tcp-listen 0))
    (def rport (%cu-int->str (Socket local-port rfd)))
    (Socket close rfd)
    (def pid (sys-fork))
    (when (= pid 0) (fp-serve lfd))
    (Socket close lfd)
    (Sys chdir (string-append fp "/work"))
    (sys-dup2 1 9) (sys-dup2 2 8)
    (def oo (file-open-write (string-append fp "/out")))
    (def ee (file-open-write (string-append fp "/err")))
    (sys-dup2 oo 1) (sys-dup2 ee 2)
    (def fp-clock date-now-unix)
    (def fp-now (date-now-unix))
    (set! date-now-unix (fn (_) fp-now))
    (def st (guard (e (do (file-write 2 (string-append "raised: " (if (Err err? e) (e msg) "?"))) -1))
              (cu-run (map (fn (_ a) (match ((string=? a "P") port) ((string=? a "R") rport)
                                            (#t (Str8 replace ":R/" (string-concat (list ":" rport "/"))
                                                  (Str8 replace ":P/" (string-concat (list ":" port "/")) a)))))
                           args)
                      input)))
    (set! date-now-unix fp-clock)
    (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
    (Sys chdir fp-home)
    (sys-kill pid 9) (sys-wait pid)
    (display (fp-dport (Str8 replace (string-append ":" rport) ":PORT" (Str8 replace (string-append ":" port) ":PORT"
      (string-concat (list "status " (%cu-int->str st) "\nstdout:\n" (file-read-all (string-append fp "/out"))
                           "stderr:\n" (file-read-all (string-append fp "/err"))
                           (fp-files (string-append fp "/work") "") (fp-srv)))))))))
  (display "made"))
```
---
    made

## ftpget

### a get

```cu
(fp-case ":" (list "ftpget" "-P" "P" "127.0.0.1" "got.txt" "small.txt") "")
```
---
```output
status 0
stdout:
stderr:
file got.txt: 6 bytes
hello

```

### -v: the connection on stdout, each command on stderr

```cu
(fp-case ":" (list "ftpget" "-v" "-P" "P" "127.0.0.1" "got.txt" "small.txt") "")
```
---
```output
status 0
stdout:
Connecting to 127.0.0.1 (127.0.0.1:PORT)
stderr:
ftpget: cmd (null) (null)
ftpget: cmd USER anonymous
ftpget: cmd TYPE I (null)
ftpget: cmd EPSV (null)
ftpget: cmd SIZE small.txt
ftpget: cmd RETR small.txt
ftpget: cmd (null) (null)
ftpget: cmd QUIT (null)
file got.txt: 6 bytes
hello

```

### the remote name alone is the local name too

```cu
(fp-case ":" (list "ftpget" "-P" "P" "127.0.0.1" "small.txt") "")
```
---
```output
status 0
stdout:
stderr:
file small.txt: 6 bytes
hello

```

### - is stdout

```cu
(fp-case ":" (list "ftpget" "-P" "P" "127.0.0.1" "-" "small.txt") "")
```
---
```output
status 0
stdout:
hello
stderr:
```

### a file larger than a read

```cu
(fp-case ":" (list "ftpget" "-P" "P" "127.0.0.1" "big.bin" "big.bin") "")
```
---
```output
status 0
stdout:
stderr:
file big.bin: 70000 bytes
ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMN
```

### an empty file

```cu
(fp-case ":" (list "ftpget" "-P" "P" "127.0.0.1" "e" "empty") "")
```
---
```output
status 0
stdout:
stderr:
file e: 0 bytes

```

### a file the server does not have

```cu
(fp-case ":" (list "ftpget" "-P" "P" "127.0.0.1" "n" "nope") "")
```
---
```output
status 1
stdout:
stderr:
ftpget: unexpected server response to RETR: 550 Error
```

### -c: REST from the local file's size

```cu
(fp-case "printf hel > part" (list "ftpget" "-v" "-c" "-P" "P" "127.0.0.1" "part" "small.txt") "")
```
---
```output
status 0
stdout:
Connecting to 127.0.0.1 (127.0.0.1:PORT)
stderr:
ftpget: cmd (null) (null)
ftpget: cmd USER anonymous
ftpget: cmd TYPE I (null)
ftpget: cmd EPSV (null)
ftpget: cmd SIZE small.txt
ftpget: cmd REST 3 (null)
ftpget: cmd RETR small.txt
ftpget: cmd (null) (null)
ftpget: cmd QUIT (null)
file part: 6 bytes
hello

```

### -c with no local file

```cu
(fp-case ":" (list "ftpget" "-c" "-P" "P" "127.0.0.1" "none" "small.txt") "")
```
---
```output
status 1
stdout:
stderr:
ftpget: stat: No such file or directory
```

### -c with an empty local file: no REST

```cu
(fp-case ": > z" (list "ftpget" "-v" "-c" "-P" "P" "127.0.0.1" "z" "small.txt") "")
```
---
```output
status 0
stdout:
Connecting to 127.0.0.1 (127.0.0.1:PORT)
stderr:
ftpget: cmd (null) (null)
ftpget: cmd USER anonymous
ftpget: cmd TYPE I (null)
ftpget: cmd EPSV (null)
ftpget: cmd SIZE small.txt
ftpget: cmd RETR small.txt
ftpget: cmd (null) (null)
ftpget: cmd QUIT (null)
file z: 6 bytes
hello

```

### -c to stdout

```cu
(fp-case ":" (list "ftpget" "-c" "-P" "P" "127.0.0.1" "-" "small.txt") "")
```
---
```output
status 0
stdout:
hello
stderr:
```

### a user the server asks a password of, and refuses

```cu
(fp-case ":" (list "ftpget" "-v" "-u" "bob" "-p" "secret" "-P" "P" "127.0.0.1" "g" "small.txt") "")
```
---
```output
status 1
stdout:
Connecting to 127.0.0.1 (127.0.0.1:PORT)
stderr:
ftpget: cmd (null) (null)
ftpget: cmd USER bob
ftpget: cmd PASS secret
ftpget: unexpected server response to PASS: 530 Login failed
```

### the long options

```cu
(fp-case ":" (list "ftpget" "--verbose" "--username" "bob" "--password" "pw" "--port" "P" "127.0.0.1" "g" "small.txt") "")
```
---
```output
status 1
stdout:
Connecting to 127.0.0.1 (127.0.0.1:PORT)
stderr:
ftpget: cmd (null) (null)
ftpget: cmd USER bob
ftpget: cmd PASS pw
ftpget: unexpected server response to PASS: 530 Login failed
```

### a port nothing listens on

```cu
(fp-case ":" (list "ftpget" "-P" "R" "127.0.0.1" "g" "small.txt") "")
```
---
```output
status 1
stdout:
stderr:
ftpget: can't connect to remote host (127.0.0.1): Connection refused
```

### a port that is not a number

```cu
(fp-case ":" (list "ftpget" "-P" "zz" "127.0.0.1" "g" "small.txt") "")
```
---
```output
status 1
stdout:
stderr:
ftpget: bad port 'zz'
```

### one operand is too few

```cu
(fp-case ":" (list "ftpget" "127.0.0.1") "")
```
---
```output
status 1
stdout:
stderr:
Usage: ftpget [OPTIONS] HOST [LOCAL_FILE] REMOTE_FILE

Download a file via FTP

	-c	Continue previous transfer
	-v	Verbose
	-u USER	Username
	-p PASS	Password
	-P PORT
```

### four operands are too many

```cu
(fp-case ":" (list "ftpget" "127.0.0.1" "a" "b" "c") "")
```
---
```output
status 1
stdout:
stderr:
Usage: ftpget [OPTIONS] HOST [LOCAL_FILE] REMOTE_FILE

Download a file via FTP

	-c	Continue previous transfer
	-v	Verbose
	-u USER	Username
	-p PASS	Password
	-P PORT
```

## ftpput

### a put: the local name alone is the remote name too

```cu
(fp-case "printf 'up\\n' > up.txt" (list "ftpput" "-P" "P" "127.0.0.1" "up.txt") "")
```
---
```output
status 0
stdout:
stderr:
file up.txt: 3 bytes
up

srv up.txt:
up
```

### -v, to another name

```cu
(fp-case "printf 'up\\n' > up.txt" (list "ftpput" "-v" "-P" "P" "127.0.0.1" "r.txt" "up.txt") "")
```
---
```output
status 0
stdout:
Connecting to 127.0.0.1 (127.0.0.1:PORT)
stderr:
ftpput: cmd (null) (null)
ftpput: cmd USER anonymous
ftpput: cmd TYPE I (null)
ftpput: cmd EPSV (null)
ftpput: cmd STOR r.txt
ftpput: cmd (null) (null)
ftpput: cmd QUIT (null)
file up.txt: 3 bytes
up

srv r.txt:
up
```

### - is stdin

```cu
(fp-case ":" (list "ftpput" "-P" "P" "127.0.0.1" "s.txt" "-") "from stdin\n")
```
---
```output
status 0
stdout:
stderr:
srv s.txt:
from stdin
```

### a local file that is not there

```cu
(fp-case ":" (list "ftpput" "-P" "P" "127.0.0.1" "r.txt" "nolocal") "")
```
---
```output
status 1
stdout:
stderr:
ftpput: can't open 'nolocal': No such file or directory
```

### a name the server cannot store

```cu
(fp-case "printf x > x" (list "ftpput" "-P" "P" "127.0.0.1" "nodir/x" "x") "")
```
---
```output
status 1
stdout:
stderr:
ftpput: unexpected server response to STOR: 553 Error
file x: 1 bytes
x
```

### -c is taken, and does nothing

```cu
(fp-case "printf x > x" (list "ftpput" "-c" "-P" "P" "127.0.0.1" "x") "")
```
---
```output
status 0
stdout:
stderr:
file x: 1 bytes
x
srv x:
x
```

## wget ftp://

### a get

```cu
(fp-case ":" (list "wget" "ftp://127.0.0.1:P/small.txt") "")
```
---
```output
status 0
stdout:
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'small.txt'
small.txt            100% |********************************|     6  0:00:00 ETA
'small.txt' saved
file small.txt: 6 bytes
hello

```

### -O -

```cu
(fp-case ":" (list "wget" "-O" "-" "ftp://127.0.0.1:P/small.txt") "")
```
---
```output
status 0
stdout:
hello
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
writing to stdout
-                    100% |********************************|     6  0:00:00 ETA
written to stdout
```

### -q

```cu
(fp-case ":" (list "wget" "-q" "ftp://127.0.0.1:P/small.txt") "")
```
---
```output
status 0
stdout:
stderr:
file small.txt: 6 bytes
hello

```

### -S: each command and each reply

```cu
(fp-case ":" (list "wget" "-S" "ftp://127.0.0.1:P/small.txt") "")
```
---
```output
status 0
stdout:
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
220 Operation successful
--> USER anonymous

230 Operation successful
--> TYPE I

200 Operation successful
--> SIZE small.txt

213 6
--> EPSV

229 EPSV ok (|||DPORT|)
--> RETR small.txt

150 Opening BINARY connection for small.txt (6 bytes)
saving to 'small.txt'
small.txt            100% |********************************|     6  0:00:00 ETA
'small.txt' saved
226 Operation successful
file small.txt: 6 bytes
hello

```

### a file larger than a read

```cu
(fp-case ":" (list "wget" "ftp://127.0.0.1:P/big.bin") "")
```
---
```output
status 0
stdout:
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'big.bin'
big.bin              100% |********************************| 70000  0:00:00 ETA
'big.bin' saved
file big.bin: 70000 bytes
ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMN
```

### an empty file

```cu
(fp-case ":" (list "wget" "ftp://127.0.0.1:P/empty") "")
```
---
```output
status 0
stdout:
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'empty'
empty                    0 --:--:-- ETA
'empty' saved
file empty: 0 bytes

```

### a file the server does not have

```cu
(fp-case ":" (list "wget" "ftp://127.0.0.1:P/nope") "")
```
---
```output
status 1
stdout:
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
wget: bad response to RETR: 550 Error
```

### -c -S: REST from the local file's size

```cu
(fp-case "printf hel > small.txt" (list "wget" "-c" "-S" "ftp://127.0.0.1:P/small.txt") "")
```
---
```output
status 0
stdout:
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
220 Operation successful
--> USER anonymous

230 Operation successful
--> TYPE I

200 Operation successful
--> SIZE small.txt

213 6
--> EPSV

229 EPSV ok (|||DPORT|)
--> REST 3

350 Operation successful
--> RETR small.txt

150 Opening BINARY connection for small.txt (6 bytes)
saving to 'small.txt'
small.txt            100% |********************************|     6  0:00:00 ETA
'small.txt' saved
226 Operation successful
file small.txt: 6 bytes
hello

```

### a user and password the server refuses

```cu
(fp-case ":" (list "wget" "ftp://bob:secret@127.0.0.1:P/small.txt") "")
```
---
```output
status 1
stdout:
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
wget: ftp login: 530 Login failed
```

### a port nothing listens on

```cu
(fp-case ":" (list "wget" "ftp://127.0.0.1:R/small.txt") "")
```
---
```output
status 1
stdout:
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
wget: can't connect to remote host (127.0.0.1): Connection refused
```

### no path

```cu
(fp-case ":" (list "wget" "ftp://127.0.0.1:P/") "")
```
---
```output
status 1
stdout:
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
wget: bad response to RETR: 550 Error
```

### --spider

```cu
(fp-case ":" (list "wget" "--spider" "ftp://127.0.0.1:P/small.txt") "")
```
---
```output
status 0
stdout:
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
remote file exists
```

### -P DIR

```cu
(fp-case "mkdir d" (list "wget" "-P" "d" "ftp://127.0.0.1:P/small.txt") "")
```
---
```output
status 0
stdout:
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
saving to 'd/small.txt'
small.txt            100% |********************************|     6  0:00:00 ETA
'd/small.txt' saved
file d/small.txt: 6 bytes
hello

```

### a file that already exists

```cu
(fp-case "printf old > small.txt" (list "wget" "ftp://127.0.0.1:P/small.txt") "")
```
---
```output
status 1
stdout:
stderr:
Connecting to 127.0.0.1:PORT (127.0.0.1:PORT)
wget: can't open 'small.txt': File exists
file small.txt: 3 bytes
old
```

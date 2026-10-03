# @weight 2

tftp as busybox's.  The server is a forked child serving D/srv on an
ephemeral port, P in the arguments, as busybox's tftpd -c serves: each
request answered from a port of its own, with an OACK when it asks a
block size or, for a download, the file's size, and refused with
"can't open file" (1) for a file that is not there and "dot in file
name" (0) for a name holding one.  D/srv holds small.txt (6 bytes) and
big.bin (1500 bytes) and an empty file.  Every expectation is busybox's
own output for the same requests against busybox's tftpd; the report
gives stdout, stderr, the status and each file left in D/work, and the
text of any file a put left in D/srv.  The progress meter's clock is
held still for each run, so a run that crosses a second draws only the
lines busybox draws within one.

## the fixture

### a server, a run, and its report

```cu
(do (import x/sys/socket) (sys-unsetenv "COLUMNS")
  (def tf "/tmp/x-cu-net.tf")
  (def tf-cat (fn (_ . ls) (let go ((l ls)) (if (null? l) () (append (first l) (go (rest l)))))))
  (def tf-take (fn (self n l) (if (if (<= n 0) #t (null? l)) () (pair (first l) (self (- n 1) (rest l))))))
  (def tf-drop (fn (self n l) (if (if (<= n 0) #t (null? l)) l (self (- n 1) (rest l)))))
  (def tf-str (fn (_ s) (%tftp-bytes s 0 (byte-len s))))
  (def tf-z (fn (_ s) (append (tf-str s) (list 0))))
  (def tf-u16 (fn (_ n) (list (% (%wget-div n 256) 256) (% n 256))))
  (def tf-b (fn (_ run) (%tftp-bytes (first run) 0 (rest run))))
  (def tf-cstr (fn (_ bs i)
    (let go ((j i) (acc ()))
      (if (if (< j (length bs)) (not (= (%cu-nth j bs) 0)) #f)
        (go (+ j 1) (pair (%cu-nth j bs) acc))
        (pair (bytes->str (reverse acc)) (+ j 1))))))
  (def tf-opts (fn (self bs i acc)
    (if (>= i (length bs)) acc
      (let ((k (tf-cstr bs i)))
        (let ((v (tf-cstr bs (rest k))))
          (self bs (rest v) (pair (pair (%wget-lower (first k)) (first v)) acc)))))))
  (def tf-send (fn (_ s to bs) (Socket send-to-run s (pair (bytes->str bs) (length bs)) (first to) (rest to))))
  (def tf-recv (fn (_ s) (tf-b (first (Socket recv-from-run s 70000)))))
  (def tf-err (fn (_ s to code text) (tf-send s to (tf-cat (tf-u16 5) (tf-u16 code) (tf-z text)))))
  (def tf-bsz (fn (_ opts) (let ((b (Assoc find "blksize" opts))) (if (null? b) 512 (%wget-digits (rest b))))))
  (def tf-download (fn (_ s to path opts)
    (def data (tf-str (file-read-all path)))
    (def bsz (tf-bsz opts))
    (when (if (= bsz 512) (not (null? (Assoc find "tsize" opts))) #t)
      (do (tf-send s to (tf-cat (tf-u16 6)
                                (if (= bsz 512) () (append (tf-z "blksize") (tf-z (%cu-int->str bsz))))
                                (tf-z "tsize") (tf-z (%cu-int->str (length data)))))
          (tf-recv s)))
    (let go ((n 1) (left data))
      (let ((block (tf-take bsz left)))
        (do (tf-send s to (tf-cat (tf-u16 3) (tf-u16 n) block))
            (tf-recv s)
            (when (= (length block) bsz) (go (+ n 1) (tf-drop bsz left))))))))
  (def tf-upload (fn (_ s to path opts)
    (def bsz (tf-bsz opts))
    (if (= bsz 512) (tf-send s to (tf-cat (tf-u16 4) (tf-u16 0)))
      (tf-send s to (tf-cat (tf-u16 6) (tf-z "blksize") (tf-z (%cu-int->str bsz)))))
    (def fd (file-open-write path))
    (let go ((n 1))
      (let ((p (tf-recv s)))
        (do (file-write-run fd (pair (bytes->str (tf-drop 4 p)) (- (length p) 4)))
            (tf-send s to (tf-cat (tf-u16 4) (tf-u16 n)))
            (if (< (- (length p) 4) bsz) (file-close fd) (go (+ n 1))))))))
  (def tf-one (fn (_ got)
    (def bs (tf-b (first got)))
    (def to (rest got))
    (def s (Socket udp-bind 0))
    (def name (first (tf-cstr bs 2)))
    (def opts (tf-opts bs (rest (tf-cstr bs (rest (tf-cstr bs 2)))) ()))
    (def path (string-concat (list tf "/srv/" name)))
    (match
      ((if (= (byte-at name 0) #\.) #t (not (null? (%wget-find name "/.")))) (tf-err s to 0 "dot in file name"))
      ((= (first (rest bs)) 1) (if (file-exists? path) (tf-download s to path opts) (tf-err s to 1 "can't open file")))
      (#t (tf-upload s to path opts)))
    (Socket close s)))
  (def tf-serve (fn (_ lfd)
    (do (guard (_ ()) (let loop () (do (tf-one (Socket recv-from-run lfd 600)) (loop))))
        (sys-exec "/bin/sh" (list "-c" "exit 0")))))
  (def tf-arg (fn (_ port a)
    (match ((string=? a "P") port)
           ((Str8 starts? "D/" a) (string-append tf (substring a 1 (byte-len a))))
           (#t a))))
  (def tf-files (fn (_ dir)
    (string-concat
      (map (fn (_ f) (string-concat (list "file " f ": "
                       (%cu-int->str (Assoc get (lit size) (file-stat (string-concat (list dir "/" f))))) " bytes\n")))
           (filter (fn (_ f) (not (if (string=? f ".") #t (string=? f "..")))) (file-list-dir dir))))))
  (def tf-case (fn (_ args)
    (proc-run (list "/bin/sh" "-c" (string-concat (list "rm -rf " tf " && mkdir -p " tf "/srv " tf "/work && printf 'hello\\n' > " tf "/srv/small.txt && : > " tf "/srv/empty && awk 'BEGIN { for (i = 0; i < 1500; i++) printf \"%c\", 65 + i % 26 }' > " tf "/srv/big.bin"))))
    (def lfd (Socket udp-bind 0))
    (def port (%cu-int->str (Socket local-port lfd)))
    (def pid (sys-fork))
    (when (= pid 0) (tf-serve lfd))
    (Socket close lfd)
    (sys-dup2 1 9) (sys-dup2 2 8)
    (def oo (file-open-write (string-append tf "/out")))
    (def ee (file-open-write (string-append tf "/err")))
    (sys-dup2 oo 1) (sys-dup2 ee 2)
    (def tf-clock date-now-unix)
    (def tf-now (date-now-unix))
    (set! date-now-unix (fn (_) tf-now))
    (def st (guard (e (do (file-write 2 (string-append "raised: " (if (Err err? e) (e msg) "?"))) -1))
              (cu-run (pair "tftp" (map (fn (_ a) (tf-arg port a)) args)) "")))
    (set! date-now-unix tf-clock)
    (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
    (sys-kill pid 9) (sys-wait pid)
    (display (string-concat (list (file-read-all (string-append tf "/out")) "stderr:\n"
                                  (file-read-all (string-append tf "/err")) "status " (%cu-int->str st) "\n"
                                  (tf-files (string-append tf "/work")))))))
  (display "made"))
```
---
    made

## busybox's behaviour

### a get: the progress line twice and a blank line, as busybox draws it

```cu
(tf-case (list "-g" "-r" "small.txt" "-l" "D/work/small.txt" "127.0.0.1" "P"))
```
---
```output
stderr:
small.txt            100% |********************************|     6  0:00:00 ETA
small.txt            100% |********************************|     6  0:00:00 ETA

status 0
file small.txt: 6 bytes
```

### -l - writes to stdout

```cu
(tf-case (list "-g" "-r" "small.txt" "-l" "-" "127.0.0.1" "P"))
```
---
```output
hello
stderr:
small.txt            100% |********************************|     6  0:00:00 ETA
small.txt            100% |********************************|     6  0:00:00 ETA

status 0
```

### three blocks

```cu
(tf-case (list "-g" "-r" "big.bin" "-l" "D/work/big.bin" "127.0.0.1" "P"))
```
---
```output
stderr:
big.bin              100% |********************************|  1500  0:00:00 ETA
big.bin              100% |********************************|  1500  0:00:00 ETA

status 0
file big.bin: 1500 bytes
```

### -b 1024: two blocks

```cu
(tf-case (list "-g" "-b" "1024" "-r" "big.bin" "-l" "D/work/big.bin" "127.0.0.1" "P"))
```
---
```output
stderr:
big.bin              100% |********************************|  1500  0:00:00 ETA
big.bin              100% |********************************|  1500  0:00:00 ETA

status 0
file big.bin: 1500 bytes
```

### an empty file: no size, no progress line

```cu
(tf-case (list "-g" "-r" "empty" "-l" "D/work/empty" "127.0.0.1" "P"))
```
---
```output
stderr:
status 0
file empty: 0 bytes
```

### a file the server cannot open

```cu
(tf-case (list "-g" "-r" "nope.txt" "-l" "D/work/nope.txt" "127.0.0.1" "P"))
```
---
```output
stderr:
tftp: server error: (1) can't open file
status 1
```

### a name the server refuses

```cu
(tf-case (list "-g" "-r" "../etc/passwd" "-l" "D/work/passwd" "127.0.0.1" "P"))
```
---
```output
stderr:
tftp: server error: (0) dot in file name
status 1
```

### a put, the file arriving on the server

```cu
(do (tf-case (list "-p" "-l" "D/srv/small.txt" "-r" "up.txt" "127.0.0.1" "P")) (display (file-read-all "/tmp/x-cu-net.tf/srv/up.txt")))
```
---
```output
stderr:
up.txt               100% |********************************|     6  0:00:00 ETA
up.txt               100% |********************************|     6  0:00:00 ETA

status 0
hello
```

### a put of a file that is not there

```cu
(tf-case (list "-p" "-l" "D/work/none.txt" "127.0.0.1" "P"))
```
---
```output
stderr:
tftp: can't open '/tmp/x-cu-net.tf/work/none.txt': No such file or directory
status 1
```

### tftp-hpa's -c get

```cu
(tf-case (list "-l" "D/work/small.txt" "-c" "get" "small.txt" "127.0.0.1" "P"))
```
---
```output
stderr:
small.txt            100% |********************************|     6  0:00:00 ETA
small.txt            100% |********************************|     6  0:00:00 ETA

status 0
file small.txt: 6 bytes
```

### a block size under 24

```cu
(tf-case (list "-g" "-b" "10" "-r" "small.txt" "127.0.0.1" "P"))
```
---
```output
stderr:
tftp: bad blocksize '10'
status 1
```

### neither -g nor -p, both, and no host

```cu
(do (tf-case (list "-r" "small.txt" "127.0.0.1" "P")) (tf-case (list "-g" "-p" "-r" "small.txt" "127.0.0.1" "P")) (tf-case (list "-g" "-r" "small.txt")))
```
---
```output
stderr:
Usage: tftp [OPTIONS] HOST [PORT]

Transfer a file from/to tftp server

	-l FILE	Local FILE
	-r FILE	Remote FILE
	-g	Get file
	-p	Put file
	-b SIZE	Transfer blocks in bytes
status 1
stderr:
Usage: tftp [OPTIONS] HOST [PORT]

Transfer a file from/to tftp server

	-l FILE	Local FILE
	-r FILE	Remote FILE
	-g	Get file
	-p	Put file
	-b SIZE	Transfer blocks in bytes
status 1
stderr:
Usage: tftp [OPTIONS] HOST [PORT]

Transfer a file from/to tftp server

	-l FILE	Local FILE
	-r FILE	Remote FILE
	-g	Get file
	-p	Put file
	-b SIZE	Transfer blocks in bytes
status 1
```

# @weight 4

ntpd as busybox's.  Each case makes /tmp/x-cu-ntp afresh, runs SETUP (sh)
there -- $port the case's port -- and ntpd ARGS in a child there, an
ntp.conf written by SETUP standing for /etc/ntp.conf.  KIND c: a scripted
NTP server answers on 127.0.0.1:P (P in ARGS its port), and ntpd runs until
it has said what the reply makes it say, then gets SIGTERM.  The server
keeps the size and first byte of each query, its key id and whether its
digest is right for the key "secret" (MD5) or the hex key 0102..14 (SHA1),
and answers by FLAGS: stratum 2, refid 127.0.0.1, rootdelay 1/512 and its
clock 1000 s ahead (neg: behind); strat0, strat16 and alarm (leap indicator
3) unsynced; short a 30-byte reply, size68 and size100 longer ones; badorg
a wrong originate stamp; keymd5 and keysha signed with the key, badkey with
a wrong digest; noreply none.  KIND s:MODE:VERSION:SIZE: ntpd -n -l ARGS
on a free port, then one query of SIZE bytes (its transmit stamp 01..08)
and the reply decoded, its times shown as now when within 5 s of the
clock.  Every expectation is busybox's own output for the same case:
stderr (the port as P, an offset's and a delay's digits as N), the status,
then the server's record or the reply.

## the fixture

### a server or a client, an ntpd, and the report

```cu
(do (import x/sys/socket)
  (def nt-f (fn (_ n) (string-append "/tmp/x-cu-ntp/" n)))
  (def nt-lines (fn (_ s)
    (let go ((i 0) (acc ()))
      (let ((nl (%wget-index s #\newline i)))
        (if (null? nl) (reverse (if (< i (byte-len s)) (pair (substring s i (byte-len s)) acc) acc))
          (go (+ nl 1) (pair (substring s i nl) acc)))))))
  (def nt-sh (fn (_ script) (proc-run (list "/bin/sh" "-c" script))))
  (def nt-iota (fn (_ n) (let go ((k (- n 1)) (acc ())) (if (< k 0) acc (go (- k 1) (pair k acc))))))
  (eval (lit (set! %nt-conf-file "/tmp/x-cu-ntp/ntp.conf")) (module cu/ntpd))
  (def nt-prep (fn (_ flags args setup port)
    (sys-setenv "NT_FLAGS" flags) (sys-setenv "NT_ARGS" args) (sys-setenv "NT_SETUP" setup) (sys-setenv "NT_PORT" (cu-int->str port))
    (nt-sh (string-concat (list
      "d=/tmp/x-cu-ntp; rm -rf $d; mkdir -p $d; cd $d; port=$NT_PORT; : > $d/got; : > $d/err; eval \"$NT_SETUP\"; "
      "eval \"set -- $(printf '%s' \"$NT_ARGS\" | sed \"s/:P/:$port/g\")\"; for a; do printf '%s\\n' \"$a\"; done > $d/.argv")))
    (nt-lines (file-read-all (nt-f ".argv")))))
  (def nt-start (fn (_ argv)
    (let ((pid (sys-fork)))
      (if (= pid 0)
        (do (Sys chdir "/tmp/x-cu-ntp")
            (sys-dup2 (file-open-write (nt-f "err")) 2)
            (sys-exit (guard (e (do (file-write 2 "uncaught: ") (sys-dup2 2 1) (display e) (file-write 2 "\n") 99)) (cu-run (pair "ntpd" argv) ""))))
        pid))))
  ; the child's raw wait status, nil while it runs (WNOHANG)
  (def nt-reap (fn (_ pid hang?)
    (let ((st (str-make-raw 4)))
      (if (> (in-call (cu-ptr-call (in-c "waitpid") pid (cu-str->ptr st) (if hang? 0 1))) 0)
        (cu-ptr-ref (cu-str->ptr st) 0 4) ()))))
  (def nt-status (fn (_ raw) (if (> (% raw 128) 0) (+ 128 (% raw 128)) (% (%wget-div raw 256) 256))))
  (def nt-said? (fn (_ words) (let ((e (file-read-all (nt-f "err")))) (List any? (fn (_ w) (not (null? (Str8 index-of w e)))) words))))
  (def nt-has? (fn (_ flags w) (List any? (fn (_ x) (string=? x w)) (Str8 split " " flags))))
  (def nt-be (fn (_ n k) (nt-be-bytes n k)))
  (def nt-hexs (fn (_ l) (string-concat (map (fn (_ b) (cu-pad-zero (cu-hexs b) 2)) l))))
  (def nt-sha-key (list 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20))
  ; the server's record of a query Q, its bytes
  (def nt-record (fn (_ q)
    (def n (length q))
    (string-concat (list "query " (cu-int->str n) " bytes, status 0x" (nt-hexs (list (first q)))
      (if (<= n 48) ""
        (let ((got (List drop 52 q)) (head (List take 48 q)))
          (string-concat (list ", keyid " (nt-hexs (List take 4 (List drop 48 q)))
            (match ((equal? got (cu-md5-bytes (append (tn-str-bytes "secret") head))) ", md5 digest ok")
                   ((equal? got (nt-sha1-bytes (append nt-sha-key head))) ", sha1 digest ok")
                   (#t (string-append ", digest " (nt-hexs got))))))))
      "\n"))))
  ; the reply FLAGS make to Q
  (def nt-answer (fn (_ q flags)
    (def has? (fn (_ w) (nt-has? flags w)))
    (def s (+ (first (si-now)) 2208988800 (if (has? "neg") -1000 1000)))
    (def head (append (list (if (has? "alarm") 228 36) (match ((has? "strat0") 0) ((has? "strat16") 16) (#t 2)) 6 247)
                      (list 0 0 0 128 0 0 0 128 127 0 0 1) (nt-be s 4) (nt-be 0 4)
                      (if (has? "badorg") (nt-zeros 8) (List take 8 (List drop 40 q)))
                      (nt-be s 4) (nt-be 2147483648 4) (nt-be s 4) (nt-be 2147483648 4)))
    (def full
      (match ((if (has? "keymd5") #t (has? "badkey"))
               (append head (List take 4 (List drop 48 q))
                       (if (has? "badkey") (list 0 17 34 51 68 85 102 119 136 153 170 187 204 221 238 255)
                         (cu-md5-bytes (append (tn-str-bytes "secret") head)))))
             ((has? "keysha") (append head (List take 4 (List drop 48 q)) (nt-sha1-bytes (append nt-sha-key head))))
             ((has? "size68") (append head (nt-zeros 20)))
             ((has? "size100") (append head (nt-zeros 52)))
             (#t head)))
    (if (has? "short") (List take 30 full) full)))
  ; what the oracle does: serve SOCK until ntpd or the server has said
  ; something (or five seconds), then 0.7 s more, then SIGTERM -- the child's
  ; raw status, or the one it ended with by itself
  (def nt-serve-one (fn (_ sock flags)
    (let ((d (in-recvfrom sock 200)))
      (let ((q (map (fn (_ k) (cu-ptr-ref (cu-str->ptr (first d)) k 1)) (nt-iota (cu-nth 1 d)))))
        (do (let ((fd (file-open-append (nt-f "got")))) (do (file-write fd (nt-record q)) (file-close fd)))
            (unless (nt-has? flags "noreply")
              (let ((r (nt-answer q flags))) (in-sendto sock (nt-raw r) (length r) d))))))))
  (def nt-serve (fn (_ sock flags pid)
    (def said? (fn (_) (if (> (byte-len (file-read-all (nt-f "err"))) 0) #t (> (byte-len (file-read-all (nt-f "got"))) 0))))
    (let go ((i 0) (left ()))
      (let ((r (nt-reap pid #f)))
        (match ((not (null? r)) r)
               ((if (null? left) #f (<= left 0)) (do (sys-kill pid 15) (nt-reap pid #t)))
               (#t (do (unless (null? (sys-poll (list (pair sock (list (lit in)))) 100)) (nt-serve-one sock flags))
                       (go (+ i 1) (match ((not (null? left)) (- left 1))
                                          ((if (said?) #t (>= i 50)) 7)
                                          (#t ()))))))))))
  (def nt-report (fn (_ port st tail)
    (sys-setenv "NT_PORT" (cu-int->str port))
    (nt-sh (string-concat (list
      "d=/tmp/x-cu-ntp; { sed -E -e \"s/:$NT_PORT([^0-9]|\\$)/:P\\1/g\" -e 's/offset:([+-])[0-9.]+/offset:\\1N/' -e 's/delay:[0-9.]+ /delay:N /' $d/err; "
      "echo \"[status " (cu-int->str st) "]\"; " tail "; } > $d/report")))
    (display (file-read-all (nt-f "report")))))
  (def nt-client (fn (_ flags args setup)
    (def sock (net-udp-open "127.0.0.1" 0 #f))
    (def port (rest (net-sock-addr sock)))
    (def argv (nt-prep flags args setup port))
    (def pid (nt-start argv))
    (def raw (nt-serve sock flags pid))
    (Socket close sock)
    (nt-report port (nt-status raw) "echo '--- server got'; cat $d/got")))
  (def nt-server (fn (_ spec args setup)
    (def parts (Str8 split ":" spec))
    (def q (List take (%wget-digits (cu-nth 3 parts))
                      (append (list (+ (* (%wget-digits (cu-nth 2 parts)) 8) (%wget-digits (cu-nth 1 parts))))
                              (nt-zeros 39) (list 1 2 3 4 5 6 7 8) (nt-zeros 200))))
    (def port (let ((s (net-udp-open "127.0.0.1" 0 #f))) (let ((p (rest (net-sock-addr s)))) (do (Socket close s) p))))
    (eval (list (lit set!) (lit %nt-server-port) port) (module cu/ntpd))
    (def argv (append (list "-n" "-l") (nt-prep "" args setup port)))
    (def pid (nt-start argv))
    (sys-usleep 500000)
    (def c (net-udp-open "127.0.0.1" 0 #f))
    (in-sendto c (nt-raw q) (length q) (list () () (net-sockaddr "127.0.0.1" port) 16))
    (def reply (if (null? (sys-poll (list (pair c (list (lit in)))) 1000)) ()
                 (let ((d (in-recvfrom c 200))) (map (fn (_ k) (cu-ptr-ref (cu-str->ptr (first d)) k 1)) (nt-iota (cu-nth 1 d))))))
    (Socket close c)
    (let ((fd (file-open-write (nt-f "reply")))) (do (File write fd (nt-raw reply) (length reply)) (file-close fd)))
    (sys-usleep 300000)
    (sys-kill pid 15)
    (def st (nt-status (nt-reap pid #t)))
    (nt-report port st (string-concat (list
      "od -An -tx1 -v $d/reply | tr -s ' \\n' '  ' | awk -v now=$(( $(date +%s) + 2208988800 )) '"
      "{ n = split($0, b, \" \") } "
      "function hx(i, k,   s, j) { s = \"\"; for (j = i; j < i + k; j++) s = s b[j + 1]; return s } "
      "function t(i,   v, j) { v = 0; for (j = i; j < i + 4; j++) v = v * 256 + (\"0x\" b[j + 1]) + 0; return (v - now <= 5 && now - v <= 5) ? \"now\" : hx(i, 8) } "
      "END { if (n == 0) { print \"no reply\"; exit } "
      "printf \"reply %d bytes: status:%s stratum:%s poll:%s precision:%s rootdelay:%s rootdisp:%s refid:%s\\n\", n, hx(0,1), hx(1,1), hx(2,1), hx(3,1), hx(4,4), hx(8,4), hx(12,4); "
      "printf \"reftime:%s orgtime:%s rectime:%s xmttime:%s\", t(16), hx(24,8), t(32), t(40); "
      "if (n > 48) { z = 1; for (j = 49; j <= n; j++) if (b[j] != \"00\") z = 0; printf \" tail:%s\", z ? \"zeros\" : hx(48, n - 48) } "
      "printf \"\\n\" }'")))))
  (def nt (fn (_ kind flags args setup)
    (cu-heap-collect)
    (if (string=? kind "c") (nt-client flags args setup) (nt-server kind args setup))))
  (display "made"))
```
---
    made

## busybox's ntpd

### a reply, said with -w

```cu
(nt "c" "" "-w -p 127.0.0.1:P" "")
```
---
```output
ntpd: reply from 127.0.0.1: offset:+N delay:N status:0x24 strat:2 refid:0x0100007f rootdelay:0.001953 reach:0x01
[status 143]
--- server got
query 48 bytes, status 0x23
```

### -d says the name and the query

```cu
(nt "c" "" "-w -d -p 127.0.0.1:P" "")
```
---
```output
ntpd: '127.0.0.1:P' is 127.0.0.1
ntpd: sending query to 127.0.0.1
ntpd: reply from 127.0.0.1: offset:+N delay:N status:0x24 strat:2 refid:0x0100007f rootdelay:0.001953 reach:0x01
[status 143]
--- server got
query 48 bytes, status 0x23
```

### a server behind

```cu
(nt "c" "neg" "-w -p 127.0.0.1:P" "")
```
---
```output
ntpd: reply from 127.0.0.1: offset:-N delay:N status:0x24 strat:2 refid:0x0100007f rootdelay:0.001953 reach:0x01
[status 143]
--- server got
query 48 bytes, status 0x23
```

### -n -w

```cu
(nt "c" "" "-n -w -p 127.0.0.1:P" "")
```
---
```output
ntpd: reply from 127.0.0.1: offset:+N delay:N status:0x24 strat:2 refid:0x0100007f rootdelay:0.001953 reach:0x01
[status 143]
--- server got
query 48 bytes, status 0x23
```

### stratum 0: unsynced

```cu
(nt "c" "strat0" "-w -p 127.0.0.1:P" "")
```
---
```output
ntpd: reply from 127.0.0.1: peer is unsynced
[status 143]
--- server got
query 48 bytes, status 0x23
```

### stratum 16: unsynced

```cu
(nt "c" "strat16" "-w -p 127.0.0.1:P" "")
```
---
```output
ntpd: reply from 127.0.0.1: peer is unsynced
[status 143]
--- server got
query 48 bytes, status 0x23
```

### leap indicator 3: unsynced

```cu
(nt "c" "alarm" "-w -p 127.0.0.1:P" "")
```
---
```output
ntpd: reply from 127.0.0.1: peer is unsynced
[status 143]
--- server got
query 48 bytes, status 0x23
```

### a 30-byte reply: malformed

```cu
(nt "c" "short" "-w -p 127.0.0.1:P" "")
```
---
```output
ntpd: malformed packet received from 127.0.0.1: size 30
[status 143]
--- server got
query 48 bytes, status 0x23
```

### a 68-byte reply taken

```cu
(nt "c" "size68" "-w -p 127.0.0.1:P" "")
```
---
```output
ntpd: reply from 127.0.0.1: offset:+N delay:N status:0x24 strat:2 refid:0x0100007f rootdelay:0.001953 reach:0x01
[status 143]
--- server got
query 48 bytes, status 0x23
```

### a longer reply cut to 72 bytes

```cu
(nt "c" "size100" "-w -p 127.0.0.1:P" "")
```
---
```output
ntpd: reply from 127.0.0.1: offset:+N delay:N status:0x24 strat:2 refid:0x0100007f rootdelay:0.001953 reach:0x01
[status 143]
--- server got
query 48 bytes, status 0x23
```

### a reply to some other query: ignored

```cu
(nt "c" "badorg" "-w -p 127.0.0.1:P" "")
```
---
```output
[status 143]
--- server got
query 48 bytes, status 0x23
```

### no reply yet

```cu
(nt "c" "noreply" "-w -p 127.0.0.1:P" "")
```
---
```output
[status 143]
--- server got
query 48 bytes, status 0x23
```

### an MD5 key: the query and the reply signed

```cu
(nt "c" "keymd5" "-w -k keys -p keyno:1:127.0.0.1:P" "printf '1 M secret\\n' > keys")
```
---
```output
ntpd: reply from 127.0.0.1: offset:+N delay:N status:0x24 strat:2 refid:0x0100007f rootdelay:0.001953 reach:0x01
[status 143]
--- server got
query 68 bytes, status 0x23, keyid 00000001, md5 digest ok
```

### a SHA1 key

```cu
(nt "c" "keysha" "-w -k keys -p keyno:7:127.0.0.1:P" "printf '# keys\\n7 SHA1 0102030405060708090a0b0c0d0e0f1011121314 # note\\n' > keys")
```
---
```output
ntpd: reply from 127.0.0.1: offset:+N delay:N status:0x24 strat:2 refid:0x0100007f rootdelay:0.001953 reach:0x01
[status 143]
--- server got
query 72 bytes, status 0x23, keyid 00000007, sha1 digest ok
```

### a reply with the wrong digest

```cu
(nt "c" "badkey" "-w -k keys -p keyno:1:127.0.0.1:P" "printf '1 MD5 secret\\n' > keys")
```
---
```output
ntpd: invalid cryptographic hash received from 127.0.0.1
[status 143]
--- server got
query 68 bytes, status 0x23, keyid 00000001, md5 digest ok
```

### a keyed peer and an unsigned reply

```cu
(nt "c" "" "-w -k keys -p keyno:1:127.0.0.1:P" "printf '1 md5 secret\\n' > keys")
```
---
```output
ntpd: invalid cryptographic hash received from 127.0.0.1
[status 143]
--- server got
query 68 bytes, status 0x23, keyid 00000001, md5 digest ok
```

### the last key of an id is the one taken

```cu
(nt "c" "keymd5" "-w -k keys -p keyno:1:127.0.0.1:P" "printf '1 M other\\n1 M secret\\n' > keys")
```
---
```output
ntpd: reply from 127.0.0.1: offset:+N delay:N status:0x24 strat:2 refid:0x0100007f rootdelay:0.001953 reach:0x01
[status 143]
--- server got
query 68 bytes, status 0x23, keyid 00000001, md5 digest ok
```

### a key not defined

```cu
(nt "c" "" "-w -k keys -p keyno:2:127.0.0.1:P" "printf '1 M secret\\n' > keys")
```
---
```output
ntpd: key 2 is not defined
[status 1]
--- server got
```

### keyno without its colon

```cu
(nt "c" "" "-w -k keys -p keyno:1" "printf '1 M secret\\n' > keys")
```
---
```output
Usage: ntpd [-dnqNwl] [-I IFACE] [-S PROG] [-k KEYFILE] [-p [keyno:N:]PEER]...

NTP client/server

	-d[d]	Verbose
	-n	Run in foreground
	-q	Quit after clock is set
	-N	Run at high priority
	-w	Do not set time (only query peers), implies -n
	-S PROG	Run PROG after stepping time, stratum change, and every 11 min
	-k FILE	Key file (ntp.keys compatible)
	-p [keyno:NUM:]PEER
		Obtain time from PEER (may be repeated)
		Use key NUM for authentication
		If -p is not given, 'server HOST' lines
		from /etc/ntp.conf are used
	-l	Also run as server on port 123
	-I IFACE Bind server to IFACE, implies -l
[status 1]
--- server got
```

### a key number out of range

```cu
(nt "c" "" "-w -k keys -p keyno:0:127.0.0.1:P" "printf '1 M secret\\n' > keys")
```
---
```output
ntpd: number 0 is not in 1..65535 range
[status 1]
--- server got
```

### a key type not known

```cu
(nt "c" "" "-w -k keys -p 127.0.0.1:P" "printf '1 RMD160 secret\\n' > keys")
```
---
```output
ntpd: only MD5 and SHA1 keys supported
[status 1]
--- server got
```

### a SHA1 key of odd length

```cu
(nt "c" "" "-w -k keys -p 127.0.0.1:P" "printf '1 SHA abc\\n' > keys")
```
---
```output
ntpd: malformed key at line 1
[status 1]
--- server got
```

### a SHA1 key not hex

```cu
(nt "c" "" "-w -k keys -p 127.0.0.1:P" "printf '1 SHA zz\\n' > keys")
```
---
```output
ntpd: malformed key at line 1
[status 1]
--- server got
```

### a key too long

```cu
(nt "c" "" "-w -k keys -p 127.0.0.1:P" "printf '1 M 0123456789012345678901234567890123456789x\\n' > keys")
```
---
```output
ntpd: malformed key at line 1
[status 1]
--- server got
```

### a key line short of a key

```cu
(nt "c" "" "-w -k keys -p 127.0.0.1:P" "printf '\\n1 M\\n' > keys")
```
---
```output
ntpd: bad line 2: 2 tokens found, 3 needed
[status 1]
--- server got
```

### a key id not a number

```cu
(nt "c" "" "-w -k keys -p 127.0.0.1:P" "printf 'one M secret\\n' > keys")
```
---
```output
ntpd: invalid number 'one'
[status 1]
--- server got
```

### no key file

```cu
(nt "c" "" "-w -k nokeys -p 127.0.0.1:P" "")
```
---
```output
ntpd: nokeys: No such file or directory
ntpd: reply from 127.0.0.1: offset:+N delay:N status:0x24 strat:2 refid:0x0100007f rootdelay:0.001953 reach:0x01
[status 143]
--- server got
query 48 bytes, status 0x23
```

### the same address twice

```cu
(nt "c" "" "-w -p 127.0.0.1:P -p 127.0.0.1:9" "")
```
---
```output
ntpd: duplicate peer 127.0.0.1:9 (127.0.0.1)
ntpd: reply from 127.0.0.1: offset:+N delay:N status:0x24 strat:2 refid:0x0100007f rootdelay:0.001953 reach:0x01
[status 143]
--- server got
query 48 bytes, status 0x23
```

### a bad port

```cu
(nt "c" "" "-w -p 127.0.0.1:99999" "")
```
---
```output
ntpd: bad port '99999'
[status 143]
--- server got
```

### a bracketed address without its colon

```cu
(nt "c" "" "-w -p [::1]x" "")
```
---
```output
ntpd: bad address '[::1]x'
[status 143]
--- server got
```

### no peers, no -l

```cu
(nt "c" "" "-w" "")
```
---
```output
ntpd: /etc/ntp.conf: No such file or directory
Usage: ntpd [-dnqNwl] [-I IFACE] [-S PROG] [-k KEYFILE] [-p [keyno:N:]PEER]...

NTP client/server

	-d[d]	Verbose
	-n	Run in foreground
	-q	Quit after clock is set
	-N	Run at high priority
	-w	Do not set time (only query peers), implies -n
	-S PROG	Run PROG after stepping time, stratum change, and every 11 min
	-k FILE	Key file (ntp.keys compatible)
	-p [keyno:NUM:]PEER
		Obtain time from PEER (may be repeated)
		Use key NUM for authentication
		If -p is not given, 'server HOST' lines
		from /etc/ntp.conf are used
	-l	Also run as server on port 123
	-I IFACE Bind server to IFACE, implies -l
[status 1]
--- server got
```

### an operand

```cu
(nt "c" "" "-w -p 127.0.0.1:P extra" "")
```
---
```output
Usage: ntpd [-dnqNwl] [-I IFACE] [-S PROG] [-k KEYFILE] [-p [keyno:N:]PEER]...

NTP client/server

	-d[d]	Verbose
	-n	Run in foreground
	-q	Quit after clock is set
	-N	Run at high priority
	-w	Do not set time (only query peers), implies -n
	-S PROG	Run PROG after stepping time, stratum change, and every 11 min
	-k FILE	Key file (ntp.keys compatible)
	-p [keyno:NUM:]PEER
		Obtain time from PEER (may be repeated)
		Use key NUM for authentication
		If -p is not given, 'server HOST' lines
		from /etc/ntp.conf are used
	-l	Also run as server on port 123
	-I IFACE Bind server to IFACE, implies -l
[status 1]
--- server got
```

### the server answers a client query

```cu
(nt "s:3:4:48" "" "" "")
```
---
```output
ntpd: /etc/ntp.conf: No such file or directory
[status 143]
reply 48 bytes: status:24 stratum:01 poll:00 precision:f7 rootdelay:00000000 rootdisp:00000000 refid:00000000
reftime:now orgtime:0102030405060708 rectime:now xmttime:now
```

### a symmetric active query: passive

```cu
(nt "s:1:4:48" "" "" "")
```
---
```output
ntpd: /etc/ntp.conf: No such file or directory
[status 143]
reply 48 bytes: status:22 stratum:01 poll:00 precision:f7 rootdelay:00000000 rootdisp:00000000 refid:00000000
reftime:now orgtime:0102030405060708 rectime:now xmttime:now
```

### a version 3 query

```cu
(nt "s:3:3:48" "" "" "")
```
---
```output
ntpd: /etc/ntp.conf: No such file or directory
[status 143]
reply 48 bytes: status:1c stratum:01 poll:00 precision:f7 rootdelay:00000000 rootdisp:00000000 refid:00000000
reftime:now orgtime:0102030405060708 rectime:now xmttime:now
```

### a server-mode query: no answer

```cu
(nt "s:4:4:48" "" "" "")
```
---
```output
ntpd: /etc/ntp.conf: No such file or directory
[status 143]
no reply
```

### a 68-byte query: a 68-byte reply

```cu
(nt "s:3:4:68" "" "" "")
```
---
```output
ntpd: /etc/ntp.conf: No such file or directory
[status 143]
reply 68 bytes: status:24 stratum:01 poll:00 precision:f7 rootdelay:00000000 rootdisp:00000000 refid:00000000
reftime:now orgtime:0102030405060708 rectime:now xmttime:now tail:zeros
```

### a longer query cut to 72 bytes

```cu
(nt "s:3:4:100" "" "" "")
```
---
```output
ntpd: /etc/ntp.conf: No such file or directory
[status 143]
reply 72 bytes: status:24 stratum:01 poll:00 precision:f7 rootdelay:00000000 rootdisp:00000000 refid:00000000
reftime:now orgtime:0102030405060708 rectime:now xmttime:now tail:zeros
```

### a 10-byte query: malformed

```cu
(nt "s:3:4:10" "" "" "")
```
---
```output
ntpd: /etc/ntp.conf: No such file or directory
ntpd: malformed packet received from ::ffff:127.0.0.1: size 10
[status 143]
no reply
```

### -d -d -d says each answer

```cu
(nt "s:3:4:48" "" "-d -d -d" "")
```
---
```output
ntpd: /etc/ntp.conf: No such file or directory
ntpd: poll:661s sockets:1 interval:1s
ntpd: responded to query from ::ffff:127.0.0.1
ntpd: poll:660s sockets:1 interval:1s
[status 143]
reply 48 bytes: status:24 stratum:01 poll:00 precision:f7 rootdelay:00000000 rootdisp:00000000 refid:00000000
reftime:now orgtime:0102030405060708 rectime:now xmttime:now
```

### a peer not yet heard from: stratum 16

```cu
(nt "s:3:4:48" "" "-p 127.0.0.1:9" "")
```
---
```output
[status 143]
reply 48 bytes: status:e4 stratum:10 poll:00 precision:f7 rootdelay:00000000 rootdisp:00000000 refid:00000000
reftime:now orgtime:0102030405060708 rectime:now xmttime:now
```

### /etc/ntp.conf's server lines, others skipped

```cu
(nt "c" "" "-w" "printf '# servers\\nserver 127.0.0.1:%s iburst\\n\\ndriftfile /var/lib/drift\\nserver\\n' $port > ntp.conf")
```
---
```output
ntpd: skipping /etc/ntp.conf:4: unimplemented command 'driftfile'
ntpd: skipping /etc/ntp.conf:5: unimplemented command 'server'
ntpd: reply from 127.0.0.1: offset:+N delay:N status:0x24 strat:2 refid:0x0100007f rootdelay:0.001953 reach:0x01
[status 143]
--- server got
query 48 bytes, status 0x23
```

### a server line naming a key

```cu
(nt "c" "keymd5" "-w -k keys" "printf '1 M secret\\n' > keys; printf 'server 127.0.0.1:%s key 1\\n' $port > ntp.conf")
```
---
```output
ntpd: reply from 127.0.0.1: offset:+N delay:N status:0x24 strat:2 refid:0x0100007f rootdelay:0.001953 reach:0x01
[status 143]
--- server got
query 68 bytes, status 0x23, keyid 00000001, md5 digest ok
```

### a server line naming a key not defined

```cu
(nt "c" "" "-w" "printf 'server 127.0.0.1:%s key 3\\n' $port > ntp.conf")
```
---
```output
ntpd: key 3 is not defined
[status 1]
--- server got
```

### -p wins over /etc/ntp.conf

```cu
(nt "c" "" "-w -p 127.0.0.1:P" "printf 'server 127.0.0.2\\n' > ntp.conf")
```
---
```output
ntpd: reply from 127.0.0.1: offset:+N delay:N status:0x24 strat:2 refid:0x0100007f rootdelay:0.001953 reach:0x01
[status 143]
--- server got
query 48 bytes, status 0x23
```

# @weight 2

dnsd as busybox's.  Each case writes the config file CONF (as printf's %b
makes it), runs dnsd -c CONF -i 127.0.0.1 -p PORT ARGS in a child, sends it
each of QUERIES (;-separated, each a datagram written as hex bytes) from one
socket, and shows each answer as hex -- an empty line for none within a
second -- then dnsd's stdout and stderr, the port shown as 5353, the
oracle's.  Every expectation is busybox's own output for the same queries,
from busybox in Podman.

## the fixture

### a config, a server, the queries, and the report

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-dn && mkdir -p /tmp/x-cu-dn"))
  (def dn-f (fn (_ n) (string-append "/tmp/x-cu-dn/" n)))
  (def dn-hexval (fn (_ c) (if (<= c #\9) (- c #\0) (+ 10 (- c #\a)))))
  (def dn-bytes (fn (_ hex)
    (map (fn (_ h) (+ (* 16 (dn-hexval (byte-at h 0))) (dn-hexval (byte-at h 1))))
         (filter (fn (_ w) (= (byte-len w) 2)) (Str8 split " " hex)))))
  (def dn-hex (fn (_ run)
    (def h "0123456789abcdef")
    (let go ((i (- (rest run) 1)) (acc ()))
      (if (< i 0) (string-concat acc)
        (let ((b (& (byte-at (first run) i) 255)))
          (go (- i 1) (pair (string-concat (list (substring h (%wget-div b 16) (+ (%wget-div b 16) 1))
                                                 (substring h (% b 16) (+ (% b 16) 1))
                                                 (if (null? acc) "" " ")))
                            acc)))))))
  (def dn-ask (fn (_ s port hex)
    (def bs (dn-bytes hex))
    (net-send-to-run s (pair (bytes->str bs) (length bs)) "127.0.0.1" port)
    (if (null? (sys-poll (list (pair s (list (lit in)))) 1000)) ""
      (dn-hex (first (net-recv-from-run s 1024))))))
  (def dn-run (fn (_ args conf queries)
    (sys-setenv "DN_C" conf)
    (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-dn; mkdir -p /tmp/x-cu-dn; printf '%b' \"$DN_C\" > /tmp/x-cu-dn/conf"))
    (def p0 (net-udp-bind 0))
    (def port (Socket local-port p0))
    (net-close p0)
    (def pid (sys-fork))
    (when (= pid 0)
      (do (sys-dup2 (file-open-write (dn-f "out")) 1)
          (sys-dup2 (file-open-write (dn-f "err")) 2)
          (sys-exit (guard (e (do (file-write 2 (string-append "raised: " (if (Err err? e) (e msg) "?") "\n")) 99))
                      (cu-run (append (list "dnsd" "-c" (dn-f "conf") "-i" "127.0.0.1" "-p" (%cu-int->str port))
                                      (filter (fn (_ w) (> (byte-len w) 0)) (Str8 split " " args)))
                              "")))))
    (sys-usleep 400000)
    (def s (net-udp-bind 0))
    (def answers (map (fn (_ q) (string-append (dn-ask s port q) "\n")) (Str8 split ";" queries)))
    (net-close s)
    (sys-usleep 200000)
    (sys-kill pid 15)
    (sys-wait pid)
    (display (Str8 replace (string-append ":" (%cu-int->str port)) ":5353"
               (string-concat (list (string-concat answers) "stdout:\n" (file-read-all (dn-f "out"))
                                    "stderr:\n" (file-read-all (dn-f "err"))))))))
  (display "made"))
```
---
    made

## the queries

### an A query

```cu
(dn-run "" "host1.example 1.2.3.4\\n# a comment\\nother.example 5.6.7.8\\n" "12 34 01 00 00 01 00 00 00 00 00 00 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 01 00 01")
```
---
```output
12 34 85 00 00 01 00 01 00 00 00 00 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 01 00 01 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 01 00 01 00 00 00 78 00 04 01 02 03 04
stdout:
stderr:
dnsd: accepting UDP packets on 127.0.0.1:5353
```

### an A query in another case

```cu
(dn-run "" "host1.example 1.2.3.4\\n# a comment\\nother.example 5.6.7.8\\n" "12 34 01 00 00 01 00 00 00 00 00 00 05 48 4f 53 54 31 07 45 78 61 6d 70 6c 65 00 00 01 00 01")
```
---
```output
12 34 85 00 00 01 00 01 00 00 00 00 05 48 4f 53 54 31 07 45 78 61 6d 70 6c 65 00 00 01 00 01 05 48 4f 53 54 31 07 45 78 61 6d 70 6c 65 00 00 01 00 01 00 00 00 78 00 04 01 02 03 04
stdout:
stderr:
dnsd: accepting UDP packets on 127.0.0.1:5353
```

### a name not there: name error

```cu
(dn-run "" "host1.example 1.2.3.4\\n# a comment\\nother.example 5.6.7.8\\n" "12 34 01 00 00 01 00 00 00 00 00 00 04 6e 6f 70 65 07 65 78 61 6d 70 6c 65 00 00 01 00 01")
```
---
```output
12 34 85 03 00 01 00 00 00 00 00 00 04 6e 6f 70 65 07 65 78 61 6d 70 6c 65 00 00 01 00 01
stdout:
stderr:
dnsd: accepting UDP packets on 127.0.0.1:5353
```

### a PTR query

```cu
(dn-run "" "host1.example 1.2.3.4\\n# a comment\\nother.example 5.6.7.8\\n" "12 34 01 00 00 01 00 00 00 00 00 00 01 38 01 37 01 36 01 35 07 69 6e 2d 61 64 64 72 04 61 72 70 61 00 00 0c 00 01")
```
---
```output
12 34 85 00 00 01 00 01 00 00 00 00 01 38 01 37 01 36 01 35 07 69 6e 2d 61 64 64 72 04 61 72 70 61 00 00 0c 00 01 01 38 01 37 01 36 01 35 07 69 6e 2d 61 64 64 72 04 61 72 70 61 00 00 0c 00 01 00 00 00 78 00 0f 05 6f 74 68 65 72 07 65 78 61 6d 70 6c 65 00
stdout:
stderr:
dnsd: accepting UDP packets on 127.0.0.1:5353
```

### a PTR query for an address not there

```cu
(dn-run "" "host1.example 1.2.3.4\\n# a comment\\nother.example 5.6.7.8\\n" "12 34 01 00 00 01 00 00 00 00 00 00 01 39 01 39 01 39 01 39 07 69 6e 2d 61 64 64 72 04 61 72 70 61 00 00 0c 00 01")
```
---
```output
12 34 85 03 00 01 00 00 00 00 00 00 01 39 01 39 01 39 01 39 07 69 6e 2d 61 64 64 72 04 61 72 70 61 00 00 0c 00 01
stdout:
stderr:
dnsd: accepting UDP packets on 127.0.0.1:5353
```

### an AAAA query: not implemented

```cu
(dn-run "" "host1.example 1.2.3.4\\n# a comment\\nother.example 5.6.7.8\\n" "12 34 01 00 00 01 00 00 00 00 00 00 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 1c 00 01")
```
---
```output
12 34 81 04 00 01 00 00 00 00 00 00 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 1c 00 01
stdout:
stderr:
dnsd: accepting UDP packets on 127.0.0.1:5353
```

### a class that is not IN

```cu
(dn-run "" "host1.example 1.2.3.4\\n# a comment\\nother.example 5.6.7.8\\n" "12 34 01 00 00 01 00 00 00 00 00 00 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 01 00 03")
```
---
```output
12 34 81 04 00 01 00 00 00 00 00 00 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 01 00 03
stdout:
stderr:
dnsd: accepting UDP packets on 127.0.0.1:5353
```

### an opcode that is not 0

```cu
(dn-run "" "host1.example 1.2.3.4\\n# a comment\\nother.example 5.6.7.8\\n" "12 34 09 00 00 01 00 00 00 00 00 00 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 01 00 01")
```
---
```output
12 34 89 04 00 01 00 00 00 00 00 00 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 01 00 01
stdout:
stderr:
dnsd: accepting UDP packets on 127.0.0.1:5353
```

### a response, ignored

```cu
(dn-run "" "host1.example 1.2.3.4\\n# a comment\\nother.example 5.6.7.8\\n" "12 34 81 00 00 01 00 00 00 00 00 00 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 01 00 01")
```
---
```output

stdout:
stderr:
dnsd: accepting UDP packets on 127.0.0.1:5353
dnsd: response packet, ignored
```

### no questions, ignored

```cu
(dn-run "" "host1.example 1.2.3.4\\n# a comment\\nother.example 5.6.7.8\\n" "12 34 01 00 00 00 00 00 00 00 00 00 05 68 6f 73 74 31 00 00 01 00 01")
```
---
```output

stdout:
stderr:
dnsd: accepting UDP packets on 127.0.0.1:5353
dnsd: packet has 0 queries, ignored
```

### a packet too short

```cu
(dn-run "" "host1.example 1.2.3.4\\n# a comment\\nother.example 5.6.7.8\\n" "12 34 01 00 00 01")
```
---
```output

stdout:
stderr:
dnsd: accepting UDP packets on 127.0.0.1:5353
dnsd: packet size 6, ignored
```

### -t: the TTL

```cu
(dn-run "-t 3600" "host1.example 1.2.3.4\\n# a comment\\nother.example 5.6.7.8\\n" "12 34 01 00 00 01 00 00 00 00 00 00 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 01 00 01")
```
---
```output
12 34 85 00 00 01 00 01 00 00 00 00 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 01 00 01 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 01 00 01 00 00 0e 10 00 04 01 02 03 04
stdout:
stderr:
dnsd: accepting UDP packets on 127.0.0.1:5353
```

### -s: no answer for a name not there

```cu
(dn-run "-s" "host1.example 1.2.3.4\\n# a comment\\nother.example 5.6.7.8\\n" "12 34 01 00 00 01 00 00 00 00 00 00 04 6e 6f 70 65 07 65 78 61 6d 70 6c 65 00 00 01 00 01;12 34 01 00 00 01 00 00 00 00 00 00 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 01 00 01")
```
---
```output

12 34 85 00 00 01 00 01 00 00 00 00 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 01 00 01 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 01 00 01 00 00 00 78 00 04 01 02 03 04
stdout:
stderr:
dnsd: accepting UDP packets on 127.0.0.1:5353
```

### -v: what it does

```cu
(dn-run "-v" "host1.example 1.2.3.4\\n# a comment\\nother.example 5.6.7.8\\n" "12 34 01 00 00 01 00 00 00 00 00 00 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 01 00 01;12 34 01 00 00 01 00 00 00 00 00 00 04 6e 6f 70 65 07 65 78 61 6d 70 6c 65 00 00 01 00 01;12 34 01 00 00 01 00 00 00 00 00 00 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 1c 00 01")
```
---
```output
12 34 85 00 00 01 00 01 00 00 00 00 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 01 00 01 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 01 00 01 00 00 00 78 00 04 01 02 03 04
12 34 85 03 00 01 00 00 00 00 00 00 04 6e 6f 70 65 07 65 78 61 6d 70 6c 65 00 00 01 00 01
12 34 81 04 00 01 00 00 00 00 00 00 05 68 6f 73 74 31 07 65 78 61 6d 70 6c 65 00 00 1c 00 01
stdout:
stderr:
dnsd: name:host1.example, ip:1.2.3.4
dnsd: name:other.example, ip:5.6.7.8
dnsd: accepting UDP packets on 127.0.0.1:5353
dnsd: got UDP packet
dnsd: returning positive reply
dnsd: got UDP packet
dnsd: name is not found, sending error reply
dnsd: got UDP packet
dnsd: type is !REQ_A and !REQ_PTR, sending error reply
```

### -v -s

```cu
(dn-run "-v -s" "host1.example 1.2.3.4\\n# a comment\\nother.example 5.6.7.8\\n" "12 34 01 00 00 01 00 00 00 00 00 00 04 6e 6f 70 65 07 65 78 61 6d 70 6c 65 00 00 01 00 01")
```
---
```output

stdout:
stderr:
dnsd: name:host1.example, ip:1.2.3.4
dnsd: name:other.example, ip:5.6.7.8
dnsd: accepting UDP packets on 127.0.0.1:5353
dnsd: got UDP packet
dnsd: name is not found, dropping query
```

### a wildcard

```cu
(dn-run "" "*.example 9.8.7.6\\n* 10.0.0.1\\n" "12 34 01 00 00 01 00 00 00 00 00 00 08 61 6e 79 74 68 69 6e 67 02 61 74 03 61 6c 6c 00 00 01 00 01;12 34 01 00 00 01 00 00 00 00 00 00 01 31 01 30 01 30 02 31 30 07 69 6e 2d 61 64 64 72 04 61 72 70 61 00 00 0c 00 01")
```
---
```output
12 34 85 00 00 01 00 01 00 00 00 00 08 61 6e 79 74 68 69 6e 67 02 61 74 03 61 6c 6c 00 00 01 00 01 08 61 6e 79 74 68 69 6e 67 02 61 74 03 61 6c 6c 00 00 01 00 01 00 00 00 78 00 04 09 08 07 06
12 34 85 03 00 01 00 00 00 00 00 00 01 31 01 30 01 30 02 31 30 07 69 6e 2d 61 64 64 72 04 61 72 70 61 00 00 0c 00 01
stdout:
stderr:
dnsd: accepting UDP packets on 127.0.0.1:5353
```

### a line that is not name and address

```cu
(dn-run "" "one\\nbad.example 1.2.3.999\\ngood.example 1.2.3.4\\ntoo many words here\\n" "12 34 01 00 00 01 00 00 00 00 00 00 04 67 6f 6f 64 07 65 78 61 6d 70 6c 65 00 00 01 00 01")
```
---
```output
12 34 85 00 00 01 00 01 00 00 00 00 04 67 6f 6f 64 07 65 78 61 6d 70 6c 65 00 00 01 00 01 04 67 6f 6f 64 07 65 78 61 6d 70 6c 65 00 00 01 00 01 00 00 00 78 00 04 01 02 03 04
stdout:
stderr:
dnsd: bad line 1: 1 tokens found, 2 needed
dnsd: error at line 2, skipping
dnsd: error at line 4, skipping
dnsd: accepting UDP packets on 127.0.0.1:5353
```

## what ends a run

Each run below ends before it binds: stdout with a `|` at the end of each
line, then stderr, then the status.

### the fixture: a run of an applet, with its stdout, stderr and status

```cu
(do (def nf (fn (_ n) (string-append "/tmp/x-cu-dn/" n))) (def run (fn (_ argv in) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv in)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (Str8 replace "\n" "|\n" (file-read-all (nf ".out"))) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n")))))))) (display "made"))
```
---
    made

### -p: 0

```cu
(run (list "dnsd" "-p" "0") "")
```
---
```output
stderr:
dnsd: number 0 is not in 1..65535 range
status 1
```

### -p: past 65535

```cu
(run (list "dnsd" "-p" "70000") "")
```
---
```output
stderr:
dnsd: number 70000 is not in 1..65535 range
status 1
```

### -t: not a number

```cu
(run (list "dnsd" "-t" "x") "")
```
---
```output
stderr:
dnsd: invalid number 'x'
status 1
```

### -t: 0

```cu
(run (list "dnsd" "-t" "0") "")
```
---
```output
stderr:
dnsd: number 0 is not in 1..4294967295 range
status 1
```

### -i: an address that is not numeric

```cu
(run (list "dnsd" "-c" "/dev/null" "-i" "nosuchhost" "-p" "5354") "")
```
---
```output
stderr:
dnsd: bad address 'nosuchhost'
status 1
```

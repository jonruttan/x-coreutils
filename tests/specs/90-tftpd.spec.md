# @weight 2

tftpd as busybox's.  Each case makes the tree /tmp/x-cu-td/srv with PRE and
the client's directory /tmp/x-cu-td/cli with c.txt ("client\n"), runs tftpd
ARGS in the tree with a UDP socket on stdin -- in a child, as udpsvd runs it
-- and sends it CLIENT: tftp ARGS, the tftp applet run in the client's
directory against it, or raw:BYTES, the datagram printf's %b makes of BYTES,
what comes back shown as hex.  Every expectation is busybox's own output for
the same exchange, run by a user who is not root: the client's output (less
its progress lines, which vary from run to run) and status, tftpd's status,
its stderr after log:, and both trees after ===.  tftpd serves its working
directory: a DIR is a chroot, which only root may make.

## the fixture

### a tree, a server, a client, and the report

```cu
(do (import x/sys/socket)
  (def td-f (fn (_ n) (string-append "/tmp/x-cu-td/" n)))
  (def td-sh (fn (_ script) (proc-run (list "/bin/sh" "-c" script))))
  (def td-words (fn (_ s)
    (sys-setenv "TD_W" s)
    (td-sh "eval \"set -- $TD_W\"; for a; do printf '%s\\n' \"$a\"; done > /tmp/x-cu-td/words")
    (let ((t (file-read-all (td-f "words")))) (if (= (byte-len t) 0) () (filter (fn (_ l) (> (byte-len l) 0)) (Str8 split "\n" t))))))
  (def td-hex (fn (_ run)
    (def h "0123456789abcdef")
    (string-concat
      (let go ((i (- (rest run) 1)) (acc ()))
        (if (< i 0) acc
          (let ((b (& (byte-at (first run) i) 255)))
            (go (- i 1) (pair (string-concat (list (substring h (%wget-div b 16) (+ (%wget-div b 16) 1))
                                                   (substring h (% b 16) (+ (% b 16) 1))
                                                   (if (null? acc) "" " ")))
                              acc))))))))
  (def td-raw (fn (_ port bytes)
    (sys-setenv "TD_B" bytes)
    (td-sh "printf '%b' \"$TD_B\" > /tmp/x-cu-td/raw")
    (def fd (file-open-read (td-f "raw")))
    (def pkt (file-read-run fd 1024))
    (file-close fd)
    (def s (net-udp-bind 0))
    (net-send-to-run s pkt "127.0.0.1" port)
    (def got (let go ((acc ()))
      (if (null? (sys-poll (list (pair s (list (lit in)))) 1000)) (reverse acc)
        (go (pair (td-hex (first (net-recv-from-run s 1024))) acc)))))
    (net-close s)
    (string-concat (list (string-concat (let j ((xs got)) (if (null? xs) () (pair (first xs) (if (null? (rest xs)) () (pair " " (j (rest xs)))))))) "\nclient status 0\n"))))
  (def td-client (fn (_ port words)
    (Sys chdir "/tmp/x-cu-td/cli")
    (sys-dup2 1 9) (sys-dup2 2 8)
    (def out (file-open-write (td-f "cout")))
    (sys-dup2 out 1) (sys-dup2 out 2)
    (def st (cu-run (append words (list "127.0.0.1" (%cu-int->str port))) ""))
    (sys-dup2 9 1) (sys-dup2 8 2) (file-close out)
    (Sys chdir "/")
    (td-sh "tr '\\r' '\\n' < /tmp/x-cu-td/cout | grep -v -e '% |' -e '^ *$' > /tmp/x-cu-td/cout2")
    (string-append (file-read-all (td-f "cout2")) (string-concat (list "client status " (%cu-int->str st) "\n")))))
  (def td-run (fn (_ args pre client)
    (sys-setenv "TD_PRE" pre)
    (td-sh "rm -rf /tmp/x-cu-td; mkdir -p /tmp/x-cu-td/srv /tmp/x-cu-td/cli; cd /tmp/x-cu-td/srv && sh -c \"$TD_PRE\" >/dev/null 2>&1; printf 'client\\n' > /tmp/x-cu-td/cli/c.txt")
    (def argv (td-words args))
    (def s (net-udp-bind 0))
    (def port (Socket local-port s))
    (def pid (sys-fork))
    (when (= pid 0)
      (do (sys-dup2 s 0) (net-close s)
          (sys-dup2 (file-open-write (td-f "log")) 2)
          (Sys chdir "/tmp/x-cu-td/srv")
          (sys-exit (guard (e (do (file-write 2 (string-append "raised: " (if (Err err? e) (e msg) "?") "\n")) 99))
                      (cu-run (pair "tftpd" argv) "")))))
    (net-close s)
    (def out (if (Str8 starts? "raw:" client) (td-raw port (substring client 4 (byte-len client)))
               (td-client port (td-words client))))
    (sys-usleep 600000)
    (sys-kill pid 9)
    (def st (sys-wait pid))
    (file-write-all (td-f "out") out)
    (file-write-all (td-f "st") (%cu-int->str st))
    (td-sh "cd /tmp/x-cu-td; tree() { (cd \"$1\" && find . | sort | while read f; do if [ -f \"$f\" ]; then echo \"$f: $(cat \"$f\")\"; else echo \"$f/\"; fi; done); }; { cat out; echo \"server status $(cat st)\"; echo 'log:'; cat log; echo '==='; tree srv; echo '--- cli'; tree cli; } > report")
    (display (file-read-all (td-f "report")))))
  (display "made"))
```
---
    made

## the requests

### a get

```cu
(td-run "" "printf 'hello\\n' > a.txt" "tftp -g -r a.txt -l got.txt")
```
---
```output
client status 0
server status 0
log:
===
./
./a.txt: hello
--- cli
./
./c.txt: client
./got.txt: hello
```

### a get of several blocks, -b 600

```cu
(td-run "" "i=0; while [ $i -lt 200 ]; do printf 'line %03d\\n' $i; i=$((i+1)); done > big.txt" "tftp -g -b 600 -r big.txt -l got.txt")
```
---
```output
client status 0
server status 0
log:
===
./
./big.txt: line 000
line 001
line 002
line 003
line 004
line 005
line 006
line 007
line 008
line 009
line 010
line 011
line 012
line 013
line 014
line 015
line 016
line 017
line 018
line 019
line 020
line 021
line 022
line 023
line 024
line 025
line 026
line 027
line 028
line 029
line 030
line 031
line 032
line 033
line 034
line 035
line 036
line 037
line 038
line 039
line 040
line 041
line 042
line 043
line 044
line 045
line 046
line 047
line 048
line 049
line 050
line 051
line 052
line 053
line 054
line 055
line 056
line 057
line 058
line 059
line 060
line 061
line 062
line 063
line 064
line 065
line 066
line 067
line 068
line 069
line 070
line 071
line 072
line 073
line 074
line 075
line 076
line 077
line 078
line 079
line 080
line 081
line 082
line 083
line 084
line 085
line 086
line 087
line 088
line 089
line 090
line 091
line 092
line 093
line 094
line 095
line 096
line 097
line 098
line 099
line 100
line 101
line 102
line 103
line 104
line 105
line 106
line 107
line 108
line 109
line 110
line 111
line 112
line 113
line 114
line 115
line 116
line 117
line 118
line 119
line 120
line 121
line 122
line 123
line 124
line 125
line 126
line 127
line 128
line 129
line 130
line 131
line 132
line 133
line 134
line 135
line 136
line 137
line 138
line 139
line 140
line 141
line 142
line 143
line 144
line 145
line 146
line 147
line 148
line 149
line 150
line 151
line 152
line 153
line 154
line 155
line 156
line 157
line 158
line 159
line 160
line 161
line 162
line 163
line 164
line 165
line 166
line 167
line 168
line 169
line 170
line 171
line 172
line 173
line 174
line 175
line 176
line 177
line 178
line 179
line 180
line 181
line 182
line 183
line 184
line 185
line 186
line 187
line 188
line 189
line 190
line 191
line 192
line 193
line 194
line 195
line 196
line 197
line 198
line 199
--- cli
./
./c.txt: client
./got.txt: line 000
line 001
line 002
line 003
line 004
line 005
line 006
line 007
line 008
line 009
line 010
line 011
line 012
line 013
line 014
line 015
line 016
line 017
line 018
line 019
line 020
line 021
line 022
line 023
line 024
line 025
line 026
line 027
line 028
line 029
line 030
line 031
line 032
line 033
line 034
line 035
line 036
line 037
line 038
line 039
line 040
line 041
line 042
line 043
line 044
line 045
line 046
line 047
line 048
line 049
line 050
line 051
line 052
line 053
line 054
line 055
line 056
line 057
line 058
line 059
line 060
line 061
line 062
line 063
line 064
line 065
line 066
line 067
line 068
line 069
line 070
line 071
line 072
line 073
line 074
line 075
line 076
line 077
line 078
line 079
line 080
line 081
line 082
line 083
line 084
line 085
line 086
line 087
line 088
line 089
line 090
line 091
line 092
line 093
line 094
line 095
line 096
line 097
line 098
line 099
line 100
line 101
line 102
line 103
line 104
line 105
line 106
line 107
line 108
line 109
line 110
line 111
line 112
line 113
line 114
line 115
line 116
line 117
line 118
line 119
line 120
line 121
line 122
line 123
line 124
line 125
line 126
line 127
line 128
line 129
line 130
line 131
line 132
line 133
line 134
line 135
line 136
line 137
line 138
line 139
line 140
line 141
line 142
line 143
line 144
line 145
line 146
line 147
line 148
line 149
line 150
line 151
line 152
line 153
line 154
line 155
line 156
line 157
line 158
line 159
line 160
line 161
line 162
line 163
line 164
line 165
line 166
line 167
line 168
line 169
line 170
line 171
line 172
line 173
line 174
line 175
line 176
line 177
line 178
line 179
line 180
line 181
line 182
line 183
line 184
line 185
line 186
line 187
line 188
line 189
line 190
line 191
line 192
line 193
line 194
line 195
line 196
line 197
line 198
line 199
```

### a get of a file that is not there

```cu
(td-run "" ":" "tftp -g -r nope.txt -l got.txt")
```
---
```output
tftp: server error: (1) can't open file
client status 1
server status 1
log:
tftpd: can't open 'nope.txt': No such file or directory
===
./
--- cli
./
./c.txt: client
```

### a put with -c

```cu
(td-run "-c" ":" "tftp -p -l c.txt -r up.txt")
```
---
```output
client status 0
server status 0
log:
===
./
./up.txt: client
--- cli
./
./c.txt: client
```

### a put onto a file that is there, no -c

```cu
(td-run "" "printf 'old\\n' > up.txt" "tftp -p -l c.txt -r up.txt")
```
---
```output
client status 0
server status 0
log:
===
./
./up.txt: client
--- cli
./
./c.txt: client
```

### a put of a new file without -c

```cu
(td-run "" ":" "tftp -p -l c.txt -r up.txt")
```
---
```output
tftp: server error: (1) can't open file
client status 1
server status 1
log:
tftpd: can't open 'up.txt': No such file or directory
===
./
--- cli
./
./c.txt: client
```

### -r: a put refused

```cu
(td-run "-r -c" ":" "tftp -p -l c.txt -r up.txt")
```
---
```output
tftp: server error: (0) write error
client status 1
server status 1
log:
tftpd: write error
===
./
--- cli
./
./c.txt: client
```

### a dot in the name

```cu
(td-run "" "printf 'x\\n' > .hidden" "tftp -g -r .hidden -l got.txt")
```
---
```output
tftp: server error: (0) dot in file name
client status 1
server status 1
log:
tftpd: dot in file name
===
./
./.hidden: x
--- cli
./
./c.txt: client
```

### a dot after a slash

```cu
(td-run "" "mkdir sub; printf 'x\\n' > sub/f" "tftp -g -r sub/../sub/f -l got.txt")
```
---
```output
tftp: server error: (0) dot in file name
client status 1
server status 1
log:
tftpd: dot in file name
===
./
./sub/
./sub/f: x
--- cli
./
./c.txt: client
```

### a mode that is not octet

```cu
(td-run "" "printf 'hello\\n' > a.txt" "raw:\\0\\1a.txt\\0netascii\\0")
```
---
```output
00 05 00 00 6d 6f 64 65 20 69 73 20 6e 6f 74 20 27 6f 63 74 65 74 27 00
client status 0
server status 1
log:
tftpd: mode is not 'octet'
===
./
./a.txt: hello
--- cli
./
./c.txt: client
```

### a packet that is not a request

```cu
(td-run "" ":" "raw:\\0\\3\\0\\1hello")
```
---
```output
00 05 00 00 6d 61 6c 66 6f 72 6d 65 64 20 70 61 63 6b 65 74 00
client status 0
server status 1
log:
tftpd: malformed packet
===
./
--- cli
./
./c.txt: client
```

### a packet too short

```cu
(td-run "" ":" "raw:\\0\\1a")
```
---
```output
00 05 00 00 6d 61 6c 66 6f 72 6d 65 64 20 70 61 63 6b 65 74 00
client status 0
server status 1
log:
tftpd: malformed packet
===
./
--- cli
./
./c.txt: client
```

### a bad blksize

```cu
(td-run "" "printf 'hello\\n' > a.txt" "raw:\\0\\1a.txt\\0octet\\0blksize\\0\\0061\\0060\\0")
```
---
```output
00 05 00 08 00
client status 0
server status 1
log:
tftpd: bad blocksize '10'
===
./
./a.txt: hello
--- cli
./
./c.txt: client
```

### DIR refused: chroot needs root

```cu
(td-run "-c /tmp" ":" "raw:\\0\\1a.txt\\0octet\\0")
```
---
```output

client status 0
server status 1
log:
tftpd: can't change root directory to '/tmp': Operation not permitted
===
./
--- cli
./
./c.txt: client
```

## what ends a run

Each run below ends before it serves: stdout with a `|` at the end of each
line, then stderr less the banner line busybox's usage text starts with, then
the status.  The suite's stdin is not a socket, so busybox shows its usage
before it reads an option, -u's user too.

### the fixture: a run of an applet, with its stdout, stderr and status

```cu
(do (def nf (fn (_ n) (string-append "/tmp/x-cu-td/" n))) (def run (fn (_ argv in) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv in)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (Str8 replace "\n" "|\n" (file-read-all (nf ".out"))) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n")))))))) (display "made"))
```
---
    made

### stdin not a socket: the usage

```cu
(run (list "tftpd") "")
```
---
```output
stderr:
Usage: tftpd [-crl] [-u USER] [DIR]

Transfer a file on tftp client's request

tftpd is an inetd service, inetd.conf line:
	69 dgram udp nowait root tftpd tftpd -l /files/to/serve
Can be run from udpsvd:
	udpsvd -vE 0.0.0.0 69 tftpd /files/to/serve

	-r	Prohibit upload
	-c	Allow file creation via upload
	-u USER	Access files as USER
	-l	Log to syslog (inetd mode requires this)
status 1
```

### -u: the usage before the user is looked for

```cu
(run (list "tftpd" "-u" "nosuchuser") "")
```
---
```output
stderr:
Usage: tftpd [-crl] [-u USER] [DIR]

Transfer a file on tftp client's request

tftpd is an inetd service, inetd.conf line:
	69 dgram udp nowait root tftpd tftpd -l /files/to/serve
Can be run from udpsvd:
	udpsvd -vE 0.0.0.0 69 tftpd /files/to/serve

	-r	Prohibit upload
	-c	Allow file creation via upload
	-u USER	Access files as USER
	-l	Log to syslog (inetd mode requires this)
status 1
```

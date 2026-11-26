# x-coreutils card

## Run

```sh
x -l coreutils -- APPLET [ARG ...]        # one applet, as BusyBox runs it
x -l coreutils -- APPLET --help           # its usage
x -l coreutils                            # a prompt: APPLET ARG ... a line
x -l coreutils -- echo hello -> hello
x -l coreutils -- nosuch 2>&1 -> coreutils: no such applet: nosuch
x -l coreutils -- true; echo $? -> 0
x -l coreutils -- false; echo $? -> 1
```

| Where                  | What                                             |
|------------------------|--------------------------------------------------|
| `README.md`            | every applet, one to a line                      |
| `docs/options.md`      | every BusyBox option of each, and which are taken |
| `docs/vi-card.md`      | vi's own card                                    |
| `xargs` after a row    | the host's, joining the lines printed into one   |

## Text

```sh
printf 'b\na\nb\n' | x -l coreutils -- sort | xargs -> a b b
printf 'b\na\nb\n' | x -l coreutils -- sort -u | xargs -> a b
printf '3\n10\n2\n' | x -l coreutils -- sort -n | xargs -> 2 3 10
printf 'x 2\ny 1\n' | x -l coreutils -- sort -k 2 | xargs -> y 1 x 2
printf 'a\na\nb\n' | x -l coreutils -- uniq -c | xargs -> 2 a 1 b
printf 'a:b:c\n' | x -l coreutils -- cut -d: -f2 -> b
printf 'abcdef\n' | x -l coreutils -- cut -c2-4 -> bcd
printf 'hello\n' | x -l coreutils -- tr a-z A-Z -> HELLO
printf 'hello\n' | x -l coreutils -- tr -d l -> heo
printf 'aabbb\n' | x -l coreutils -- tr -s ab -> ab
printf 'one two\nthree\n' | x -l coreutils -- wc -w -> 3
printf 'one two\nthree\n' | x -l coreutils -- wc -l -> 2
printf '1\n2\n3\n' | x -l coreutils -- head -n 1 -> 1
printf '1\n2\n3\n' | x -l coreutils -- tail -n 1 -> 3
printf '1\n2\n3\n' | x -l coreutils -- tac | xargs -> 3 2 1
printf 'abc\n' | x -l coreutils -- rev -> cba
printf 'a\nb\n' | x -l coreutils -- nl | xargs -> 1 a 2 b
printf 'abcdef\n' | x -l coreutils -- fold -w 3 | xargs -> abc def
printf 'a\tb\n' | x -l coreutils -- expand -t 4 -> a   b
printf 'a b\nb c\n' | x -l coreutils -- tsort | xargs -> a b c
printf 'a\nb\n' | x -l coreutils -- xargs echo -> a b
x -l coreutils -- seq -s , 1 5 -> 1,2,3,4,5
x -l coreutils -- seq 2 3 11 | xargs -> 2 5 8 11
```

| Applets                                  | Do                             |
|------------------------------------------|--------------------------------|
| `cat` `tac` `rev` `more` `tee`           | pass lines on, or turn them    |
| `head` `tail` `split` `cut` `paste` `join` | take parts; put parts together |
| `sort` `uniq` `shuf` `tsort` `comm`      | order and compare lists        |
| `tr` `expand` `unexpand` `fold` `nl`     | change characters and layout   |
| `dos2unix` `unix2dos` `strings`          | line ends; the text in a file  |
| `wc` `seq` `yes` `echo` `printf`         | count; make lines              |
| `ed` `vi` `patch` `diff` `cmp`           | edit and compare               |
| `xargs` `getopt` `ts`                    | arguments; a time on each line |

## Files

```sh
cd $(mktemp -d); x -l coreutils -- touch a b; ls | xargs -> a b
cd $(mktemp -d); x -l coreutils -- mkdir -p a/b; ls a -> b
cd $(mktemp -d); echo hi > a; x -l coreutils -- cp a b; cat b -> hi
cd $(mktemp -d); echo hi > a; x -l coreutils -- mv a b; ls -> b
cd $(mktemp -d); x -l coreutils -- ln -s tgt l; readlink l -> tgt
cd $(mktemp -d); : > a; : > b; x -l coreutils -- ls | xargs -> a b
cd $(mktemp -d); echo hi > a; x -l coreutils -- stat -c %s a -> 3
cd $(mktemp -d); : > a; chmod 640 a; x -l coreutils -- stat -c %a a -> 640
cd $(mktemp -d); x -l coreutils -- truncate -s 5 a; wc -c < a | xargs -> 5
cd $(mktemp -d); : > a.c; : > b.h; x -l coreutils -- find . -name '*.c' -> ./a.c
cd $(mktemp -d); echo a > 1; : > 2; x -l coreutils -- cmp -s 1 2; echo $? -> 1
cd $(mktemp -d); echo k a > 1; echo k b > 2; x -l coreutils -- join 1 2 -> k a b
x -l coreutils -- basename /a/b/c.txt .txt -> c
x -l coreutils -- dirname /a/b/c.txt -> /a/b
x -l coreutils -- realpath /usr/../usr/bin -> /usr/bin
```

| Applets                                  | Do                             |
|------------------------------------------|--------------------------------|
| `ls` `tree` `stat` `du` `df` `find`      | look                           |
| `cp` `mv` `rm` `ln` `link` `unlink` `install` | copy, move, remove, name  |
| `mkdir` `rmdir` `mkfifo` `mknod` `mktemp` `touch` | make                  |
| `chmod` `chown` `chgrp` `truncate` `shred` | modes, owners, sizes         |
| `basename` `dirname` `realpath` `readlink` `pwd` `which` | names          |
| `dd` `sync` `fsync` `mountpoint`         | blocks and disks               |

## Numbers and tests

```sh
x -l coreutils -- expr 6 '*' 7 -> 42
x -l coreutils -- expr hello : 'h\(.*\)o' -> ell
x -l coreutils -- expr length hello -> 5
x -l coreutils -- factor 360 -> 360: 2 2 2 3 3 5
echo '2 3 + 4 * p' | x -l coreutils -- dc -> 20
x -l coreutils -- test 3 -gt 2 && echo yes -> yes
x -l coreutils -- [ -d / ] && echo yes -> yes
x -l coreutils -- ipcalc -n 192.168.1.77/24 -> NETWORK=192.168.1.0
TZ=UTC x -l coreutils -- date -d @0 +%Y-%m-%d -> 1970-01-01
TZ=UTC x -l coreutils -- date -d '2026-11-25 12:00' +%s -> 1795608000
x -l coreutils -- cal 11 2026 | sed 1q | xargs -> November 2026
```

| Applets                                  | Do                             |
|------------------------------------------|--------------------------------|
| `expr` `dc` `factor` `seq`               | arithmetic                     |
| `test` `[` `[[` `true` `false`           | an exit status to branch on    |
| `date` `cal` `sleep` `usleep` `uptime`   | time                           |

## Bytes

```sh
printf abc | x -l coreutils -- md5sum -> 900150983cd24fb0d6963f7d28e17f72  -
printf abc | x -l coreutils -- sha256sum | cut -c1-16 -> ba7816bf8f01cfea
printf abc | x -l coreutils -- cksum -> 1219131554 3
printf abc | x -l coreutils -- crc32 -> 352441c2
printf abc | x -l coreutils -- base64 -> YWJj
printf YWJj | x -l coreutils -- base64 -d -> abc
printf abc | x -l coreutils -- base32 -> MFRGG===
printf abc | x -l coreutils -- od -An -tx1 | xargs -> 61 62 63
printf abc | x -l coreutils -- xxd -p -> 616263
printf abc | x -l coreutils -- gzip -c | x -l coreutils -- gunzip -c -> abc
printf abc | x -l coreutils -- bzip2 -c | x -l coreutils -- bzcat -> abc
printf abc | x -l coreutils -- uuencode f | head -1 -> begin 644 f
```

| Applets                                  | Do                             |
|------------------------------------------|--------------------------------|
| `md5sum` `sha1sum` `sha256sum` `sha384sum` | a digest; `-c` checks a list |
| `sha512sum` `sha3sum` `cksum` `crc32` `sum` | more digests and checksums  |
| `base64` `base32` `uuencode` `uudecode`  | bytes as text, and back        |
| `od` `xxd` `hexdump` `hd` `ascii`        | bytes shown                    |
| `gzip` `gunzip` `zcat` `bzip2` `bunzip2` `bzcat` | compress, and back     |
| `lzma` `unlzma` `lzcat`                  | decompress only                |
| `tar` `cpio` `unzip`                     | archives                       |
| `cryptpw` `mkpasswd` `uuidgen`           | password hashes; an id         |

## Processes

```sh
x -l coreutils -- env A=1 sh -c 'echo $A' -> 1
x -l coreutils -- env -i A=1 env -> A=1
x -l coreutils -- timeout 1 sleep 5; echo $? -> 124
x -l coreutils -- nice -n 5 echo hi -> hi
x -l coreutils -- yes | head -n 2 | xargs -> y y
```

| Applets                                  | Do                             |
|------------------------------------------|--------------------------------|
| `env` `printenv` `nice` `renice` `ionice` `chrt` | run with a setting     |
| `timeout` `time` `nohup` `setsid` `flock` `watch` | run under a watch     |
| `chroot` `unshare` `nsenter` `setpriv` `taskset` | run somewhere else     |
| `ps` `top` `pstree` `pgrep` `pidof` `pmap` `pwdx` | look at processes     |
| `kill` `killall` `killall5` `pkill` `fuser` `lsof` | signal; who holds a file|
| `id` `whoami` `groups` `logname` `who` `w` `users` | who                  |
| `uname` `arch` `hostname` `nproc` `free` `vmstat` `sysctl` | the machine  |
| `tty` `ttysize` `stty` `clear` `reset` `mesg` | the terminal              |

## Network

| Applets                                  | Do                             |
|------------------------------------------|--------------------------------|
| `ip` `ifconfig` `route` `arp` `netstat`  | interfaces, routes, sockets    |
| `ping` `ping6` `traceroute` `traceroute6` `arping` | reach a host         |
| `nslookup` `whois` `ipcalc` `hostid`     | names and addresses            |
| `nc` `telnet` `wget` `tftp` `ftpget` `ftpput` | a client                  |
| `httpd` `ftpd` `telnetd` `tftpd` `inetd` `tcpsvd` `udpsvd` | a server     |
| `udhcpc` `udhcpc6` `udhcpd` `dhcprelay` `dumpleases` `zcip` | DHCP        |
| `ntpd` `rdate` `dnsd` `fakeidentd`       | time and name servers          |
| `sendmail` `popmaildir` `makemime` `reformime` | mail                     |
| `syslogd` `klogd` `logger` `logread` `dmesg` | logs                       |

## Differs

```sh
x -l coreutils -- date -d tomorrow 2>&1 -> date: invalid date 'tomorrow'
x -l coreutils -- expr aab : 'a\+b' -> 0
cd $(mktemp -d); : > f; x -l coreutils -- chmod -w f 2>&1 | grep -c Usage -> 1
cd $(mktemp -d); : > f; x -l coreutils -- diff -u f f 2>&1 | grep -c Usage -> 1
```

| Here                                        | In GNU coreutils              |
|---------------------------------------------|-------------------------------|
| BusyBox 1.36.1's options and output         | GNU's                         |
| `date -d` reads ISO 8601 or `@SECONDS`      | free-form words too           |
| `expr`'s `:` has no `\+` `\?` `\|` `\{n,m\}` | all of them                  |
| `chmod -w f` is refused: write `chmod a-w f` | taken                        |
| `diff -u` is refused: `-U LINES` asks for context | taken                   |
| `lzma` only decompresses                    | xz's compresses too           |
| `tty` says `/dev/tty` or `not a tty`        | the terminal's name           |
| `which` tests that a file is there          | that it can be run            |

## More

| Where                          | What                                     |
|--------------------------------|------------------------------------------|
| `README.md`, Known limits      | each limit, in full                      |
| `docs/options.md`              | the option matrix against BusyBox        |
| `docs/vi-card.md`              | vi: its keys and colon commands          |
| `tests/specs/`                 | each applet, held to BusyBox 1.36.1      |

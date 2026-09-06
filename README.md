# x-coreutils

<p align="center"><img src="docs/bitwise-banner.svg" alt="x-coreutils, with Bitwise the owl" width="100%"></p>

The small tools of the self-hosting arc's second tier, as APPLETS of
one bundle -- the busybox shape:

    x -l coreutils -- APPLET [args]...

**Ninety-two applets: parity with busybox's `coreutils` set.**

    arch base64 basename cat chgrp chmod chown chroot cksum cmp comm
    cp cut date dd df diff dirname dos2unix du echo env expand expr
    factor false fold groups head id install join link ln logname ls
    md5sum mkdir mkfifo mktemp mv nice nl nohup nproc od paste printenv
    printf pwd readlink realpath rev rm rmdir seq sha1sum sha256sum
    sha512sum shred shuf sleep sort split stat sum sync tac tail tee
    test timeout touch tr true truncate tty unexpand uniq unix2dos
    unlink uname uudecode uuencode usleep wc which whoami xargs yes
    [ [[

Highlights: **every digest is byte-identical with the system tool** --
`md5sum`, `sha1sum`, `sha256sum` and `sha512sum` are the FIPS/RFC
algorithms in x, and `cksum` is the POSIX CRC-32 with its length fold;
`sort` is a merge sort with `-r -n -u`; `expr` is a recursive-descent
parser over the argument list with its own anchored BRE matcher,
capture groups and all; `chmod` reads both an octal mode and the
symbolic `[ugoa]*[+-=][rwx]*` clauses; `realpath` restarts its walk
over any prefix that turns out to be a link, so `/tmp` resolves
through to `/private/tmp`; `od` follows the GNU/busybox layout (not
the BSD one macOS ships) and collapses a repeated line to `*`; `diff`
is a line LCS by DP; `timeout` forks the command AND a watchdog,
because there is no alarm door.  Self-contained: no `(requires-lang
...)`.

## Known limits, loud not silent

  - **No name service.** There is no passwd or group door, so `id`,
    `whoami` and `logname` read /etc/passwd when it holds the id and
    fall back to `$USER`/`$LOGNAME` when it does not; the numeric id
    is the last resort.  `chown` and `chgrp` take NUMERIC ids only.
    `groups` and `id -G` print numbers.
  - **`df` measures paths, not mounts.** There is no mount-table door,
    so `df` reports the filesystem each operand sits on, and a bare
    `df` measures the working directory rather than listing every
    filesystem.  There is no Filesystem column.
  - **`date` prints ISO-8601 UTC**, not the locale format.
  - **`tty` answers isatty**, not a terminal name: there is no ttyname
    door, so it prints `/dev/tty` or `not a tty`.
  - **`touch` sets the clock only.** `utimes` with explicit stamps
    wants a packed pair of timevals; `-d` and `-t` are not accepted.
  - **`which` tests existence**, not the execute bit.
  - **Text, not binary.** An x string ends at its first NUL, so the
    digests, `base64 -d`, `dd` and `shred` are safe on text and will
    truncate a stream with an embedded NUL.
  - **`expr`'s regular expressions are its own grammar**: literals,
    `.`, `*`, bracket expressions with ranges and negation, `$`, and
    `\(...\)` capture.  No `\{n,m\}`, no `\|`, no back-references.
  - **`head`/`tail` treat multiple inputs as one stream.**
  - **Not present**, for want of a door this bundle will not invent:
    `who` (utmpx), `stty` (ioctl), `hostid` (gethostid), `mknod`
    (device numbers), and `sha3sum`.

Paired with x-lang v0.11.0 (`lang.xon` is the checkable row).

## Try it

    make install        # into the x on PATH

    printf 'b\na\n' | x -l coreutils -- sort
    x -l coreutils -- sha512sum file.txt
    x -l coreutils -- stat -c '%n %s %A' file.txt
    ... | x -l awk '{print $1}' | x -l coreutils -- sort | x -l coreutils -- uniq -c

That last line is a real pipeline of x tools, and it works today.

## Tests

    make test           # the suite, loud on any failure
    make check          # judged against tests/contract/known-failures.txt

## Layout

    lang.xon          what this bundle IS (self-contained)
    run.x             the entry: operands mean "be the applet"
    cu/prims.x        the platform layer (byte doors, bitwise, File, the wide stat)
    cu/text.x         cat sort uniq head tail wc comm join basename dirname
    cu/text2.x        echo printf seq rev tac nl fold paste tee
    cu/text3.x        yes factor expand unexpand dos2unix unix2dos split shuf base64
    cu/trcut.x        tr and cut
    cu/fs.x           cp rm mkdir
    cu/fs2.x          touch ls pwd mv rmdir install mktemp cmp
    cu/fs3.x          stat du dd truncate unlink shred timeout usleep tty nohup [[
    cu/sys2.x         true false env printenv sleep date which xargs test
    cu/perm.x         chmod chown chgrp ln link readlink realpath mkfifo df sync
    cu/who.x          id whoami logname groups uname arch nproc nice chroot
    cu/encode.x       od uuencode uudecode
    cu/expr.x         expr, and the anchored matcher it needs
    cu/diff.x         diff, normal format (LCS by DP)
    cu/hash.x         md5sum sha1sum cksum sum
    cu/sha256.x       FIPS 180-4, in x
    cu/sha512.x       its 64-bit sibling, addition masked in halves
    cu/cli.x          the applet table, cu-run, cu-main
    tests/            markdown specs + the platform's runner, vendored nowhere

<p align="center"><img src="docs/bitwise-mark.svg" alt="Bitwise" width="96"></p>

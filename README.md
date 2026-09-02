# x-coreutils

The small tools of the self-hosting arc's second tier, as APPLETS of
one bundle -- the busybox shape:

    x -l coreutils -- APPLET [args]...

Forty-four applets, busybox-style: `cat sort uniq head tail wc comm
join tr cut basename dirname cp rm mkdir sha256sum` (the measured core
-- sort alone is 1,415 build-closure calls, and sha256sum retires the
shasum/sha256sum fallback dance), plus the scripting set `echo printf
true false seq rev tac nl fold paste tee touch ls pwd mv rmdir install
mktemp cmp diff env printenv sleep date which xargs test [`.

Highlights: `sort` is a merge sort with `-r -n -u`; `comm` and `join`
walk sorted inputs merge-wise; `printf` reuses its format across the
argument list; `test`/`[` covers the unary file tests and the string
and integer comparators; `diff` is a line LCS by DP over a vector, in
the normal `XcY`/`< ---`/`> ` format; **sha256sum is FIPS 180-4 in
pure x**, byte-identical with the system tool.  Self-contained: no
`(requires-lang ...)`.

Known limits, loud not silent: no chmod/utime doors, so `touch` bumps
mtime by rewriting bytes and `install -m` accepts-and-ignores the mode;
`date` prints ISO-8601 UTC (not the locale format); `which` tests
existence, not the execute bit; text files only for sha256sum (NUL
bytes end a C string); `head`/`tail` treat multiple inputs as one
stream.

Paired with x-lang v0.10.0 (`lang.xon` is the checkable row).

## Try it

    make install        # into the x on PATH

    printf 'b\na\n' | x -l coreutils -- sort
    x -l coreutils -- sha256sum file.txt
    ... | x -l awk '{print $1}' | x -l coreutils -- sort | x -l coreutils -- uniq -c

That last line is a real pipeline of x tools, and it works today.

## Tests

    make test           # the suite, loud on any failure
    make check          # judged against tests/contract/known-failures.txt

## Layout

    lang.xon          what this bundle IS (self-contained)
    run.x             the entry: operands mean "be the applet"
    cu/prims.x        the platform layer (byte doors, bitwise, File)
    cu/text.x         cat sort uniq head tail wc comm join basename dirname
    cu/text2.x        echo printf seq rev tac nl fold paste tee
    cu/trcut.x        tr and cut
    cu/fs.x           cp rm mkdir
    cu/fs2.x          touch ls pwd mv rmdir install mktemp cmp
    cu/sys2.x         true false env printenv sleep date which xargs test
    cu/diff.x         diff, normal format (LCS by DP)
    cu/sha256.x       FIPS 180-4, in x
    cu/cli.x          the applet table, cu-run, cu-main
    tests/            markdown specs + the platform's runner, vendored nowhere

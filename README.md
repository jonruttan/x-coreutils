# x-coreutils

The small tools of the self-hosting arc's second tier, as APPLETS of
one bundle -- the busybox shape:

    x -l coreutils -- APPLET [args]...

Sixteen applets: `cat sort uniq head tail wc comm join tr cut basename
dirname cp rm mkdir sha256sum`.  Chosen by measurement: these are the
biggest remaining rows of x-lang's build closure
(`docs/bootstrap-closure.md`) after awk/grep/sed/make -- sort alone is
1,415 calls, and sha256sum retires the shasum/sha256sum fallback dance.

Highlights: `sort` is a merge sort with `-r -n -u`; `comm` and `join`
walk sorted inputs merge-wise (equal-key runs join cartesianly);
`tr` takes ranges, `-d`, `-s`; `cut` does `-d/-f` field lists and `-c`
character lists; and **sha256sum is FIPS 180-4 in pure x** on the
engine's machine-word ops, byte-identical with the system tool (the
padded message lives as a byte list -- x strings are C strings, and
padding contains NULs).  Self-contained: no `(requires-lang ...)`.

Known limits, loud not silent: text files only for sha256sum (NUL
bytes end a C string), `head`/`tail` treat multiple inputs as one
stream, no locale anything (bytes, always).

Paired with x-lang v0.9.0 (`lang.xon` is the checkable row).

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
    cu/trcut.x        tr and cut
    cu/fs.x           cp rm mkdir
    cu/sha256.x       FIPS 180-4, in x
    cu/cli.x          the applet table, cu-run, cu-main
    tests/            markdown specs + the platform's runner, vendored nowhere

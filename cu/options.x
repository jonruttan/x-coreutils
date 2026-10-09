; # x-coreutils -- the small tools, as applets
;
; ## cu/options.x -- each applet's options and help text, declared once
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; One row per applet: its Opts declaration and -- for an applet whose operands
; can look like flags -- a word for how far the options go: `leading` stops the
; parse at the first operand, so `timeout 5 prog -x` leaves -x to prog; `known`
; stops it at the first word that is not a cluster of the flags, and keeps that
; word, so `echo -x` and `echo -- a` print their words, as echo reads them;
; `none` says there are no options at all, so `printf -x` prints -x, and only a
; first -- is dropped.  `inetd` marks a service that wants a socket on stdin
; before it reads any option: without one, its usage, as busybox's tftpd shows.
;
; The declaration is busybox's help text, row for row: what `APPLET --help`
; prints, less the banner line and the rows for options this bundle does not
; take.  A listed row declares the option it describes; a hidden row declares
; one busybox does not list; a text row is a line laid out by hand, or a
; spelling (a cluster, an attached value) of options declared elsewhere.  The
; guard, the applet and --help all read the same row (through %cu-opts and
; %cu-usage), so an option cannot be accepted and undocumented, nor documented
; and refused.
;
; test's whole vocabulary is declared because the guard must know every
; dash-word the grammar accepts; find's for the same reason, or a valid
; expression reads as a bad flag.  cu/find.x parses them; this list only makes
; them spellable.
(def %cu-test-operators
  (list "-e" "-f" "-d" "-s" "-z" "-n" "-r" "-w" "-x" "-L" "-h"
        "-b" "-c" "-p" "-S" "-k" "-u" "-g" "-t"
        "-eq" "-ne" "-lt" "-le" "-gt" "-ge" "-nt" "-ot" "-ef"
        "-a" "-o" "=" "==" "!=" "!" "(" ")"))

(def %cu-find-primaries
  (list "-name" "-iname" "-path" "-type" "-size" "-newer"
        "-maxdepth" "-mindepth" "-empty" "-print" "-print0" "-exec"
        "-true" "-false" "-not" "-a" "-and" "-o" "-or" "!" "(" ")"))

; Hidden rows for a list of flags, and of options that take an argument.
(def %cu-hidden-flags
  (fn (_ flags) (map (fn (_ f) (Opts hidden (Opts flag f ""))) flags)))

(def %cu-hidden-args
  (fn (_ opts) (map (fn (_ o) (Opts hidden (Opts arg o "" ""))) opts)))

(def %cu-option-spec
  (list
    (pair "cat"
      (list
        (Opts declare "cat" "[-nbvteA] [FILE]..."
          "Print FILEs to stdout"
          (list
            (Opts flag "-n" "Number output lines")
            (Opts flag "-b" "Number nonempty lines")
            (Opts flag "-v" "Show nonprinting characters as ^x or M-x")
            (Opts flag "-t" "...and tabs as ^I")
            (Opts flag "-e" "...and end lines with $")
            (Opts flag "-A" "Same as -vte")))))
    (pair "sort"
      (list
        (Opts declare "sort" "[-nrughMcszbdfiokt] [-o FILE] [-k START[.OFS][OPTS][,END[.OFS][OPTS]] [-t CHAR] [FILE]..."
          "Sort lines of text"
          (list
            (Opts arg "-o" "FILE" "Output to FILE")
            (Opts flag "-c" "Check whether input is sorted")
            (Opts flag "-b" "Ignore leading blanks")
            (Opts flag "-f" "Ignore case")
            (Opts flag "-i" "Ignore unprintable characters")
            (Opts flag "-d" "Dictionary order (blank or alphanumeric only)")
            (Opts flag "-n" "Sort numbers")
            (Opts flag "-g" "General numerical sort")
            (Opts flag "-M" "Sort month")
            (Opts arg "-t" "CHAR" "Field separator")
            (Opts text "\t-k N[,M] Sort by Nth field")
            (Opts flag "-r" "Reverse sort order")
            (Opts flag "-s" "Stable (don't sort ties alphabetically)")
            (Opts flag "-u" "Suppress duplicate lines")
            (Opts flag "-z" "NUL terminated input and output")
            (Opts hidden (Opts arg "-k" "" ""))))))
    (pair "uniq"
      (list
        (Opts declare "uniq" "[-cduiz] [-f,s,w N] [FILE [OUTFILE]]"
          "Discard duplicate lines"
          (list
            (Opts flag "-c" "Prefix lines by the number of occurrences")
            (Opts flag "-d" "Only print duplicate lines")
            (Opts flag "-u" "Only print unique lines")
            (Opts flag "-i" "Ignore case")
            (Opts arg "-f" "N" "Skip first N fields")
            (Opts arg "-s" "N" "Skip first N chars (after any skipped fields)")
            (Opts arg "-w" "N" "Compare N characters in line")))))
    (pair "head"
      (list
        (Opts declare "head" "[OPTIONS] [FILE]..."
          "Print first 10 lines of FILEs (or stdin).\nWith more than one FILE, precede each with a filename header."
          (list
            (Opts arg "-n" "N[bkm]" "Print first N lines")
            (Opts text "\t-n -N[bkm]\tPrint all except N last lines")
            (Opts arg "-c" "[-]N[bkm]" "Print first N bytes")
            (Opts text "\t\t\t(b:*512 k:*1024 m:*1024^2)")
            (Opts flag "-q" "Never print headers")
            (Opts flag "-v" "Always print headers")))))
    (pair "tail"
      (list
        (Opts declare "tail" "[OPTIONS] [FILE]..."
          "Print last 10 lines of FILEs (or stdin) to.\nWith more than one FILE, precede each with a filename header."
          (list
            (Opts arg "-c" "[+]N[bkm]" "Print last N bytes")
            (Opts arg "-n" "N[bkm]" "Print last N lines")
            (Opts text "\t-n +N[bkm]\tStart on Nth line and print the rest")
            (Opts text "\t\t\t(b:*512 k:*1024 m:*1024^2)")
            (Opts flag "-q" "Never print headers")
            (Opts flag "-v" "Always print headers")
            (Opts flag "-f" "Print data as file grows")
            (Opts arg "-s" "SECONDS" "Wait SECONDS between reads with -f")))))
    (pair "wc"
      (list
        (Opts declare "wc" "[-cmlwL] [FILE]..."
          "Count lines, words, and bytes for FILEs (or stdin)"
          (list
            (Opts flag "-c" "Count bytes")
            (Opts flag "-m" "Count characters")
            (Opts flag "-l" "Count newlines")
            (Opts flag "-w" "Count words")
            (Opts flag "-L" "Print longest line length")))))
    (pair "comm"
      (list
        (Opts declare "comm" "[-123] FILE1 FILE2"
          "Compare FILE1 with FILE2"
          (list
            (Opts flag "-1" "Suppress lines unique to FILE1")
            (Opts flag "-2" "Suppress lines unique to FILE2")
            (Opts flag "-3" "Suppress lines common to both files")))))
    (pair "join"
      (list
        (Opts declare "join" "[-a 1|2 | -v 1|2] [-e STR] [-o LIST] [-t SEP_CHAR] [-1 NUM] [-2 NUM] FILE1 FILE2"
          "Join FILE1 and FILE2, writing to stdout"
          (list
            (Opts arg "-t" "CHAR" "Use a different field separator")
            (Opts text "")
            (Opts text "LIST is a space or comma separated list of 1/2.FIELD or 0 (the join field)")))))
    (pair "tr"
      (list
        (Opts declare "tr" "[-cds] STRING1 [STRING2]"
          "Translate, squeeze, or delete characters from stdin, writing to stdout"
          (list
            (Opts flag "-c" "Take complement of STRING1")
            (Opts flag "-d" "Delete input characters coded STRING1")
            (Opts flag "-s" "Squeeze multiple output characters of STRING2 into one character")))))
    (pair "cut"
      (list
        (Opts declare "cut" "{-b|c LIST | -f|F LIST [-d SEP] [-s]} [-D] [-O SEP] [FILE]..."
          "Print selected fields from FILEs to stdout"
          (list
            (Opts arg "-b" "LIST" "Output only bytes from LIST")
            (Opts arg "-c" "LIST" "Output only characters from LIST")
            (Opts arg "-d" "SEP" "Input field delimiter (default -f TAB, -F run of whitespace)")
            (Opts arg "-f" "LIST" "Print only these fields (-d is single char)")
            (Opts flag "-s" "Drop lines with no delimiter (else print them in full)")
            (Opts flag "-n" "Ignored")))))
    (pair "basename"
      (list
        (Opts declare "basename" "FILE [SUFFIX] | -a FILE... | -s SUFFIX FILE..."
          "Strip directory path and SUFFIX from FILE"
          (list
            (Opts arg "-s" "SUFFIX" "Remove SUFFIX (implies -a)")))))
    (pair "dirname"
      (list
        (Opts declare "dirname" "FILENAME"
          "Strip non-directory suffix from FILENAME"
          (list))
        (lit none)))
    (pair "cp"
      (list
        (Opts declare "cp" "[-arPLHpfinlsTu] SOURCE DEST\nor: cp [-arPLHpfinlsu] SOURCE... { -t DIRECTORY | DIRECTORY }"
          "Copy SOURCEs to DEST"
          (list
            (Opts flag "-a" "Same as -dpR")
            (Opts flag "-R" "-r" "Recurse")
            (Opts flag "-L" "Follow all symlinks")
            (Opts flag "-H" "Follow symlinks on command line")
            (Opts flag "-p" "Preserve file attributes if possible")
            (Opts flag "-f" "Overwrite")
            (Opts flag "-i" "Prompt before overwrite")
            (Opts flag "-l" "-s" "Create (sym)links")
            (Opts flag "-T" "Refuse to copy if DEST is a directory")
            (Opts flag "-u" "Copy only newer files")
            (Opts hidden (Opts flag "-P" ""))))))
    (pair "rm"
      (list
        (Opts declare "rm" "[-irf] FILE..."
          "Remove (unlink) FILEs"
          (list
            (Opts flag "-i" "Always prompt before removing")
            (Opts flag "-f" "Never prompt")
            (Opts flag "-R" "-r" "Recurse")
            (Opts hidden (Opts flag "-v" ""))))))
    (pair "mkdir"
      (list
        (Opts declare "mkdir" "[-m MODE] [-p] DIRECTORY..."
          "Create DIRECTORY"
          (list
            (Opts arg "-m" "MODE" "Mode")
            (Opts flag "-p" "No error if exists; make parent directories as needed")))))
    (pair "sha256sum"
      (list
        (Opts declare "sha256sum" "[-c[sw]] [FILE]..."
          "Print or check SHA256 checksums"
          (list
            (Opts flag "-c" "Check sums against list in FILEs")
            (Opts flag "-s" "Don't output anything, status code shows success")
            (Opts flag "-w" "Warn about improperly formatted checksum lines")))))
    ; md5sum, sha1sum, sha256sum and sha512sum share one driver, so they share one
    ; option set.
    (pair "md5sum"
      (list
        (Opts declare "md5sum" "[-c[sw]] [FILE]..."
          "Print or check MD5 checksums"
          (list
            (Opts flag "-c" "Check sums against list in FILEs")
            (Opts flag "-s" "Don't output anything, status code shows success")
            (Opts flag "-w" "Warn about improperly formatted checksum lines")))))
    (pair "sha1sum"
      (list
        (Opts declare "sha1sum" "[-c[sw]] [FILE]..."
          "Print or check SHA1 checksums"
          (list
            (Opts flag "-c" "Check sums against list in FILEs")
            (Opts flag "-s" "Don't output anything, status code shows success")
            (Opts flag "-w" "Warn about improperly formatted checksum lines")))))
    (pair "sha512sum"
      (list
        (Opts declare "sha512sum" "[-c[sw]] [FILE]..."
          "Print or check SHA512 checksums"
          (list
            (Opts flag "-c" "Check sums against list in FILEs")
            (Opts flag "-s" "Don't output anything, status code shows success")
            (Opts flag "-w" "Warn about improperly formatted checksum lines")))))
    (pair "cksum"
      (list
        (Opts declare "cksum" "FILE..."
          "Calculate CRC32 checksum of FILEs"
          (list))))
    (pair "sum"
      (list
        (Opts declare "sum" "[-rs] [FILE]..."
          "Checksum and count the blocks in a file"
          (list
            (Opts flag "-r" "Use BSD sum algorithm (1K blocks)")
            (Opts flag "-s" "Use System V sum algorithm (512byte blocks)")))))
    (pair "yes"
      (list
        (Opts declare "yes" "[STRING]"
          "Repeatedly print a line with STRING, or 'y'"
          (list))))
    (pair "factor"
      (list
        (Opts declare "factor" "[NUMBER]..."
          "Print prime factors"
          (list
            (Opts hidden (Opts flag "-h" ""))))))
    (pair "expand"
      (list
        (Opts declare "expand" "[-i] [-t N] [FILE]..."
          "Convert tabs to spaces, writing to stdout"
          (list
            (Opts flag "-i" "Don't convert tabs after non blanks")
            (Opts text "\t-t\tTabstops every N chars")
            (Opts hidden (Opts arg "-t" "" ""))))))
    (pair "unexpand"
      (list
        (Opts declare "unexpand" "[-fa][-t N] [FILE]..."
          "Convert spaces to tabs, writing to stdout"
          (list
            (Opts flag "-a" "Convert all blanks")
            (Opts flag "-f" "Convert only leading blanks")
            (Opts arg "-t" "N" "Tabstops every N chars")))))
    (pair "dos2unix"
      (list
        (Opts declare "dos2unix" "[-ud] [FILE]"
          "Convert FILE in-place from DOS to Unix format.\nWhen no file is given, use stdin/stdout."
          (list
            (Opts flag "-u" "dos2unix")
            (Opts flag "-d" "unix2dos")))))
    (pair "unix2dos"
      (list
        (Opts declare "unix2dos" "[-ud] [FILE]"
          "Convert FILE in-place from Unix to DOS format.\nWhen no file is given, use stdin/stdout."
          (list
            (Opts flag "-u" "dos2unix")
            (Opts flag "-d" "unix2dos")))))
    (pair "split"
      (list
        (Opts declare "split" "[OPTIONS] [INPUT [PREFIX]]"
          "\t-b N[k|m]\tSplit by N (kilo|mega)bytes\n\t-l N\t\tSplit by N lines\n\t-a N\t\tUse N letters as suffix"
          (list
            (Opts hidden (Opts arg "-b" "" ""))
            (Opts hidden (Opts arg "-l" "" ""))
            (Opts hidden (Opts arg "-a" "" ""))))))
    (pair "shuf"
      (list
        (Opts declare "shuf" "[-n NUM] [-o FILE] [-z] [FILE | -e [ARG...] | -i L-H]"
          "Randomly permute lines"
          (list
            (Opts arg "-n" "NUM" "Output at most NUM lines")
            (Opts arg "-o" "FILE" "Write to FILE, not standard output")
            (Opts flag "-z" "NUL terminated output")
            (Opts flag "-e" "Treat ARGs as lines")
            (Opts arg "-i" "L-H" "Treat numbers L-H as lines")))))
    (pair "base64"
      (list
        (Opts declare "base64" "[-d] [-w COL] [FILE]"
          "Base64 encode or decode FILE to standard output"
          (list
            (Opts flag "-d" "Decode data")
            (Opts arg "-w" "COL" "Wrap lines at COL (default 76, 0 disables)")))))
    (pair "stat"
      (list
        (Opts declare "stat" "[-ltf] [-c FMT] FILE..."
          "Display file (default) or filesystem status"
          (list
            (Opts arg "-c" "FMT" "Use the specified format")
            (Opts flag "-f" "Display filesystem status")
            (Opts flag "-L" "Follow links")
            (Opts flag "-t" "Terse display")
            (Opts text "")
            (Opts text "FMT sequences for files:")
            (Opts text " %a\tAccess rights in octal")
            (Opts text " %A\tAccess rights in human readable form")
            (Opts text " %b\tNumber of blocks allocated (see %B)")
            (Opts text " %B\tSize in bytes of each block reported by %b")
            (Opts text " %d\tDevice number in decimal")
            (Opts text " %D\tDevice number in hex")
            (Opts text " %f\tRaw mode in hex")
            (Opts text " %F\tFile type")
            (Opts text " %g\tGroup ID")
            (Opts text " %G\tGroup name")
            (Opts text " %h\tNumber of hard links")
            (Opts text " %i\tInode number")
            (Opts text " %n\tFile name")
            (Opts text " %N\tFile name, with -> TARGET if symlink")
            (Opts text " %o\tI/O block size")
            (Opts text " %s\tTotal size in bytes")
            (Opts text " %t\tMajor device type in hex")
            (Opts text " %T\tMinor device type in hex")
            (Opts text " %u\tUser ID")
            (Opts text " %U\tUser name")
            (Opts text " %x\tTime of last access")
            (Opts text " %X\tTime of last access as seconds since Epoch")
            (Opts text " %y\tTime of last modification")
            (Opts text " %Y\tTime of last modification as seconds since Epoch")
            (Opts text " %z\tTime of last change")
            (Opts text " %Z\tTime of last change as seconds since Epoch")
            (Opts text "")
            (Opts text "FMT sequences for file systems:")
            (Opts text " %a\tFree blocks available to non-superuser")
            (Opts text " %b\tTotal data blocks")
            (Opts text " %c\tTotal file nodes")
            (Opts text " %d\tFree file nodes")
            (Opts text " %f\tFree blocks")
            (Opts text " %i\tFile System ID in hex")
            (Opts text " %l\tMaximum length of filenames")
            (Opts text " %n\tFile name")
            (Opts text " %s\tBlock size (for faster transfer)")
            (Opts text " %S\tFundamental block size (for block counts)")
            (Opts text " %t\tType in hex")
            (Opts text " %T\tType in human readable form")))))
    (pair "du"
      (list
        (Opts declare "du" "[-aHLdclsxhmk] [FILE]..."
          "Summarize disk space used for FILEs (or directories)"
          (list
            (Opts flag "-a" "Show file sizes too")
            (Opts flag "-L" "Follow all symlinks")
            (Opts flag "-H" "Follow symlinks on command line")
            (Opts arg "-d" "N" "Limit output to directories (and files with -a) of depth < N")
            (Opts flag "-c" "Show grand total")
            (Opts flag "-l" "Count sizes many times if hard linked")
            (Opts flag "-s" "Display only a total for each argument")
            (Opts flag "-x" "Skip directories on different filesystems")
            (Opts flag "-h" "Sizes in human readable format (e.g., 1K 243M 2G)")
            (Opts flag "-m" "Sizes in megabytes")
            (Opts flag "-k" "Sizes in kilobytes (default)")
            (Opts hidden (Opts flag "-P" ""))))))
    (pair "dd"
      (list
        (Opts declare "dd" "[if=FILE] [of=FILE] [ibs=N obs=N/bs=N] [count=N] [skip=N] [seek=N]\n\t[conv=notrunc|noerror|sync|fsync]\n\t[iflag=skip_bytes|count_bytes|fullblock|direct] [oflag=seek_bytes|append|direct]"
          "Copy a file with converting and formatting"
          (list
            (Opts text "\tif=FILE\t\tRead from FILE instead of stdin")
            (Opts text "\tof=FILE\t\tWrite to FILE instead of stdout")
            (Opts text "\tbs=N\t\tRead and write N bytes at a time")
            (Opts text "\tibs=N\t\tRead N bytes at a time")
            (Opts text "\tobs=N\t\tWrite N bytes at a time")
            (Opts text "\tcount=N\t\tCopy only N input blocks")
            (Opts text "\tskip=N\t\tSkip N input blocks")
            (Opts text "\tseek=N\t\tSkip N output blocks")
            (Opts text "\tconv=notrunc\tDon't truncate output file")
            (Opts text "\tconv=noerror\tContinue after read errors")
            (Opts text "\tconv=sync\tPad blocks with zeros")
            (Opts text "\tconv=fsync\tPhysically write data out before finishing")
            (Opts text "\tconv=swab\tSwap every pair of bytes")
            (Opts text "\tiflag=skip_bytes\tskip=N is in bytes")
            (Opts text "\tiflag=count_bytes\tcount=N is in bytes")
            (Opts text "\toflag=seek_bytes\tseek=N is in bytes")
            (Opts text "\tiflag=direct\tO_DIRECT input")
            (Opts text "\toflag=direct\tO_DIRECT output")
            (Opts text "\tiflag=fullblock\tRead full blocks")
            (Opts text "\toflag=append\tOpen output in append mode")
            (Opts text "\tstatus=noxfer\tSuppress rate output")
            (Opts text "\tstatus=none\tSuppress all output")
            (Opts text "")
            (Opts text "N may be suffixed by c (1), w (2), b (512), kB (1000), k (1024), MB, M, GB, G")))))
    (pair "truncate"
      (list
        (Opts declare "truncate" "[-c] -s SIZE FILE..."
          "Truncate FILEs to SIZE"
          (list
            (Opts flag "-c" "Do not create files")
            (Opts text "\t-s SIZE")
            (Opts hidden (Opts arg "-s" "" ""))))))
    (pair "unlink"
      (list
        (Opts declare "unlink" "FILE"
          "Delete FILE by calling unlink()"
          (list))))
    (pair "shred"
      (list
        (Opts declare "shred" "[-fuz] [-n N] [-s SIZE] FILE..."
          "Overwrite/delete FILEs"
          (list
            (Opts flag "-f" "Chmod to ensure writability")
            (Opts arg "-n" "N" "Overwrite N times (default 3)")
            (Opts flag "-z" "Final overwrite with zeros")
            (Opts flag "-u" "Remove file")))))
    (pair "timeout"
      (list
        (Opts declare "timeout" "[-s SIG] [-k KILL_SECS] SECS PROG ARGS"
          "Run PROG. Send SIG to it if it is not gone in SECS seconds.\nDefault SIG: TERM.If it still exists in KILL_SECS seconds, send KILL.\n"
          (list
            (Opts hidden (Opts arg "-s" "" ""))
            (Opts hidden (Opts arg "-k" "" ""))))
        (lit leading)))
    (pair "usleep"
      (list
        (Opts declare "usleep" "N"
          "Pause for N microseconds"
          (list))
        (lit none)))
    (pair "tty"
      (list
        (Opts declare "tty" "[-s]"
          "Print file name of stdin's terminal"
          (list
            (Opts flag "-s" "Print nothing, only return exit status")))))
    ; the command a runner runs takes its own flags
    (pair "nohup"
      (list
        (Opts declare "nohup" "PROG ARGS"
          "Run PROG immune to hangups, with output to a non-tty"
          (list))
        (lit none)))
    (pair "[["
      (list
        (Opts declare "[[" "" ()
          (append (list
            (Opts hidden (Opts flag "--help" "")))
            (%cu-hidden-flags %cu-test-operators))
          (pair (lit help) #f))
        (lit none)))
    (pair "od"
      (list
        (Opts declare "od" "[-abcdfhilovxs] [-t TYPE] [-A RADIX] [-N SIZE] [-j SKIP] [-S MINSTR] [-w WIDTH] [FILE]..."
          "Print FILEs (or stdin) unambiguously, as octal bytes by default"
          (list
            (Opts hidden (Opts flag "-v" ""))
            (Opts hidden (Opts flag "-c" ""))
            (Opts hidden (Opts flag "-b" ""))
            (Opts hidden (Opts flag "-x" ""))
            (Opts hidden (Opts flag "-d" ""))
            (Opts hidden (Opts flag "-o" ""))
            (Opts hidden (Opts arg "-A" "" ""))
            (Opts hidden (Opts arg "-t" "" ""))
            (Opts hidden (Opts arg "-N" "" ""))
            (Opts hidden (Opts arg "-j" "" ""))))))
    (pair "uuencode"
      (list
        (Opts declare "uuencode" "[-m] [FILE] STORED_FILENAME"
          "Uuencode FILE (or stdin) to stdout"
          (list
            (Opts flag "-m" "Use base64 encoding per RFC1521")))))
    (pair "uudecode"
      (list
        (Opts declare "uudecode" "[-o OUTFILE] [INFILE]"
          "Uudecode a file\nFinds OUTFILE in uuencoded source unless -o is given"
          (list
            (Opts hidden (Opts arg "-o" "" ""))))))
    (pair "expr"
      (list
        (Opts declare "expr" "EXPRESSION"
          "Print the value of EXPRESSION"
          (list
            (Opts text "EXPRESSION may be:")
            (Opts text "\tARG1 | ARG2\tARG1 if it is neither null nor 0, otherwise ARG2")
            (Opts text "\tARG1 & ARG2\tARG1 if neither argument is null or 0, otherwise 0")
            (Opts text "\tARG1 < ARG2\t1 if ARG1 is less than ARG2, else 0. Similarly:")
            (Opts text "\tARG1 <= ARG2")
            (Opts text "\tARG1 = ARG2")
            (Opts text "\tARG1 != ARG2")
            (Opts text "\tARG1 >= ARG2")
            (Opts text "\tARG1 > ARG2")
            (Opts text "\tARG1 + ARG2\tSum of ARG1 and ARG2. Similarly:")
            (Opts text "\tARG1 - ARG2")
            (Opts text "\tARG1 * ARG2")
            (Opts text "\tARG1 / ARG2")
            (Opts text "\tARG1 % ARG2")
            (Opts text "\tSTRING : REGEXP\t\tAnchored pattern match of REGEXP in STRING")
            (Opts text "\tmatch STRING REGEXP\tSame as STRING : REGEXP")
            (Opts text "\tsubstr STRING POS LEN\tSubstring of STRING, POS counts from 1")
            (Opts text "\tindex STRING CHARS\tIndex in STRING where any CHARS is found, or 0")
            (Opts text "\tlength STRING\t\tLength of STRING")
            (Opts text "\tquote TOKEN\t\tInterpret TOKEN as a string, even if")
            (Opts text "\t\t\t\tit is a keyword like 'match' or an")
            (Opts text "\t\t\t\toperator like '/'")
            (Opts text "\t(EXPRESSION)\t\tValue of EXPRESSION")
            (Opts text "")
            (Opts text "Beware that many operators need to be escaped or quoted for shells.")
            (Opts text "Comparisons are arithmetic if both ARGs are numbers, else")
            (Opts text "lexicographical. Pattern matches return the string matched between")
            (Opts text "\\( and \\) or null; if \\( and \\) are not used, they return the number")
            (Opts text "of characters matched or 0.")))
        (lit none)))
    (pair "chmod"
      (list
        (Opts declare "chmod" "[-Rcvf] MODE[,MODE]... FILE..."
          "MODE is octal number (bit pattern sstrwxrwxrwx) or [ugoa]{+|-|=}[rwxXst]"
          (list
            (Opts flag "-R" "Recurse")
            (Opts flag "-c" "List changed files")
            (Opts flag "-v" "Verbose")
            (Opts flag "-f" "Hide errors")))))
    (pair "chown"
      (list
        (Opts declare "chown" "[-RhLHPcvf]... USER[:[GRP]] FILE..."
          "Change the owner and/or group of FILEs to USER and/or GRP"
          (list
            (Opts flag "-h" "Affect symlinks instead of symlink targets")
            (Opts flag "-L" "Traverse all symlinks to directories")
            (Opts flag "-H" "Traverse symlinks on command line only")
            (Opts flag "-P" "Don't traverse symlinks (default)")
            (Opts flag "-R" "Recurse")
            (Opts flag "-c" "List changed files")
            (Opts flag "-v" "Verbose")
            (Opts flag "-f" "Hide errors")))))
    (pair "chgrp"
      (list
        (Opts declare "chgrp" "[-RhLHPcvf]... GROUP FILE..."
          "Change the group membership of FILEs to GROUP"
          (list
            (Opts flag "-h" "Affect symlinks instead of symlink targets")
            (Opts flag "-L" "Traverse all symlinks to directories")
            (Opts flag "-H" "Traverse symlinks on command line only")
            (Opts flag "-P" "Don't traverse symlinks (default)")
            (Opts flag "-R" "Recurse")
            (Opts flag "-c" "List changed files")
            (Opts flag "-v" "Verbose")
            (Opts flag "-f" "Hide errors")))))
    (pair "ln"
      (list
        (Opts declare "ln" "[-sfnbtv] [-S SUF] TARGET... LINK|DIR"
          "Create a link LINK or DIR/TARGET to the specified TARGET(s)"
          (list
            (Opts flag "-s" "Make symlinks instead of hardlinks")
            (Opts flag "-f" "Remove existing destinations")
            (Opts flag "-n" "Don't dereference symlinks - treat like normal file")
            (Opts flag "-b" "Make a backup of the target (if exists) before link operation")
            (Opts flag "-v" "Verbose")
            (Opts hidden (Opts arg "-t" "" ""))))))
    (pair "link"
      (list
        (Opts declare "link" "FILE LINK"
          "Create hard LINK to FILE"
          (list))))
    (pair "readlink"
      (list
        (Opts declare "readlink" "[-fnv] FILE"
          "Display the value of a symlink"
          (list
            (Opts flag "-n" "Don't add newline")
            (Opts flag "-f" "Canonicalize by following all symlinks")
            (Opts flag "-v" "Verbose")
            (Opts hidden (Opts flag "-e" ""))))))
    (pair "realpath"
      (list
        (Opts declare "realpath" "FILE..."
          "Print absolute pathnames of FILEs"
          (list))
        (lit none)))
    (pair "mkfifo"
      (list
        (Opts declare "mkfifo" "[-m MODE] NAME"
          "Create named pipe"
          (list
            (Opts arg "-m" "MODE" "Mode (default a=rw)")))))
    (pair "df"
      (list
        (Opts declare "df" "[-PkmhTai] [-B SIZE] [-t TYPE] [FILESYSTEM]..."
          "Print filesystem usage statistics"
          (list
            (Opts flag "-P" "POSIX output format")
            (Opts flag "-k" "1024-byte blocks (default)")
            (Opts flag "-m" "1M-byte blocks")
            (Opts flag "-h" "Human readable (e.g. 1K 243M 2G)")
            (Opts flag "-T" "Print filesystem type")
            (Opts flag "-a" "Show all filesystems")
            (Opts flag "-i" "Inodes")
            (Opts arg "-B" "SIZE" "Blocksize")))))
    (pair "sync"
      (list
        (Opts declare "sync" "[-df] [FILE]..."
          "Write all buffered blocks (in FILEs) to disk\n\t-d\tAvoid syncing metadata\n\t-f\tSync filesystems underlying FILEs"
          (list
            (Opts hidden (Opts flag "-d" ""))
            (Opts hidden (Opts flag "-f" ""))))))
    (pair "id"
      (list
        (Opts declare "id" "[-ugGnr] [USER]"
          "Print information about USER or the current user"
          (list
            (Opts flag "-u" "User ID")
            (Opts flag "-g" "Group ID")
            (Opts flag "-G" "Supplementary group IDs")
            (Opts flag "-n" "Print names instead of numbers")
            (Opts flag "-r" "Print real ID instead of effective ID")))))
    (pair "whoami"
      (list
        (Opts declare "whoami" ""
          "Print the user name associated with the current effective user id"
          (list))))
    (pair "logname"
      (list
        (Opts declare "logname" ""
          "Print the name of the current user"
          (list))))
    (pair "groups"
      (list
        (Opts declare "groups" "[USER]"
          "Print the groups USER is in"
          (list))))
    (pair "who"
      (list
        (Opts declare "who" "[-aH]"
          "Show who is logged on"
          (list
            (Opts flag "-a" "Show all")
            (Opts flag "-H" "Print column headers")))))
    (pair "w"
      (list
        (Opts declare "w" ""
          "Show who is logged on"
          (list))))
    (pair "users"
      (list
        (Opts declare "users" ""
          "Print the users currently logged on"
          (list))))
    (pair "uname"
      (list
        (Opts declare "uname" "[-amnrspvio]"
          "Print system information"
          (list
            (Opts flag "-a" "Print all")
            (Opts flag "-m" "Machine (hardware) type")
            (Opts flag "-n" "Hostname")
            (Opts flag "-r" "Kernel release")
            (Opts flag "-s" "Kernel name (default)")
            (Opts flag "-p" "Processor type")
            (Opts flag "-v" "Kernel version")
            (Opts flag "-i" "Hardware platform")
            (Opts flag "-o" "OS name")))))
    (pair "arch"
      (list
        (Opts declare "arch" ""
          "Print system architecture"
          (list))))
    (pair "nproc"
      (list
        (Opts declare "nproc" "[--all] [--ignore=N]"
          "Print number of available CPUs"
          (list
            (Opts flag "--all" "Number of installed CPUs")
            (Opts text "\t--ignore=N\tExclude N CPUs")
            (Opts hidden (Opts arg "--ignore" "" "")))
          (pair (lit column) 24))))
    (pair "nice"
      (list
        (Opts declare "nice" "[-n ADJUST] [PROG ARGS]"
          "Change scheduling priority, run PROG"
          (list
            (Opts arg "-n" "ADJUST" "Adjust priority by ADJUST")))
        (lit leading)))
    ; the command a runner runs takes its own flags
    (pair "chroot"
      (list
        (Opts declare "chroot" "NEWROOT [PROG ARGS]"
          "Run PROG with root directory set to NEWROOT"
          (list))
        (lit none)))
    (pair "echo"
      (list
        (Opts declare "echo" "" ()
          (list
            (Opts hidden (Opts flag "-n" ""))
            (Opts hidden (Opts flag "-e" ""))
            (Opts hidden (Opts flag "-E" "")))
          (pair (lit help) #f))
        (lit known)))
    ; a format, and an expression's words, may start with a -
    (pair "printf"
      (list
        (Opts declare "printf" "FORMAT [ARG]..."
          "Format and print ARG(s) according to FORMAT (a-la C printf)"
          (list))
        (lit none)))
    (pair "true"
      (list
        (Opts declare "true" "" ()
          (list)
          (pair (lit help) #f))
        (lit none)))
    (pair "false"
      (list
        (Opts declare "false" "" ()
          (list)
          (pair (lit help) #f))
        (lit none)))
    (pair "seq"
      (list
        (Opts declare "seq" "[-w] [-s SEP] [FIRST [INC]] LAST"
          "Print numbers from FIRST to LAST, in steps of INC.\nFIRST, INC default to 1."
          (list
            (Opts flag "-w" "Pad with leading zeros")
            (Opts arg "-s" "SEP" "String separator")))))
    (pair "rev"
      (list
        (Opts declare "rev" "[FILE]..."
          "Reverse lines of FILE"
          (list))))
    (pair "tac"
      (list
        (Opts declare "tac" "[FILE]..."
          "Concatenate FILEs and print them in reverse"
          (list))))
    (pair "nl"
      (list
        (Opts declare "nl" "[OPTIONS] [FILE]..."
          "Write FILEs to standard output with line numbers added"
          (list
            (Opts arg "-b" "STYLE" "Which lines to number - a: all, t: nonempty, n: none")
            (Opts arg "-i" "N" "Line number increment")
            (Opts arg "-s" "STRING" "Use STRING as line number separator")
            (Opts arg "-v" "N" "Start from N")
            (Opts arg "-w" "N" "Width of line numbers")
            (Opts hidden (Opts arg "-n" "" ""))))))
    (pair "fold"
      (list
        (Opts declare "fold" "[-bs] [-w WIDTH] [FILE]..."
          "Wrap input lines in FILEs (or stdin), writing to stdout"
          (list
            (Opts flag "-b" "Count bytes rather than columns")
            (Opts flag "-s" "Break at spaces")
            (Opts text "\t-w\tUse WIDTH columns instead of 80")
            (Opts hidden (Opts arg "-w" "" ""))))))
    (pair "paste"
      (list
        (Opts declare "paste" "[-d LIST] [-s] [FILE]..."
          "Paste lines from each input file, separated with tab"
          (list
            (Opts arg "-d" "LIST" "Use delimiters from LIST, not tab")
            (Opts text "\t-s      Serial: one file at a time")
            (Opts hidden (Opts flag "-s" ""))))))
    (pair "tee"
      (list
        (Opts declare "tee" "[-ai] [FILE]..."
          "Copy stdin to each FILE, and also to stdout"
          (list
            (Opts flag "-a" "Append to the given FILEs, don't overwrite")
            (Opts flag "-i" "Ignore interrupt signals (SIGINT)")))))
    (pair "touch"
      (list
        (Opts declare "touch" "[-cham] [-d DATE] [-t DATE] [-r FILE] FILE..."
          "Update mtime of FILEs"
          (list
            (Opts flag "-c" "Don't create files")
            (Opts arg "-d" "DT" "Date/time to use")
            (Opts arg "-t" "DT" "Date/time to use")
            (Opts arg "-r" "FILE" "Use FILE's date/time")))))
    (pair "ls"
      (list
        (Opts declare "ls" "[-1AaCxdLHRFplinshrSXvctu] [-w WIDTH] [FILE]..."
          "List directory contents"
          (list
            (Opts flag "-1" "One column output")
            (Opts flag "-a" "Include names starting with .")
            (Opts flag "-A" "Like -a, but exclude . and ..")
            (Opts flag "-x" "List by lines")
            (Opts flag "-d" "List directory names, not contents")
            (Opts flag "-L" "Follow symlinks")
            (Opts flag "-H" "Follow symlinks on command line")
            (Opts flag "-R" "Recurse")
            (Opts flag "-p" "Append / to directory names")
            (Opts flag "-F" "Append indicator (one of */=@|) to names")
            (Opts flag "-l" "Long format")
            (Opts flag "-i" "List inode numbers")
            (Opts flag "-n" "List numeric UIDs and GIDs instead of names")
            (Opts flag "-s" "List allocated blocks")
            (Opts text "\t-lc\tList ctime")
            (Opts text "\t-lu\tList atime")
            (Opts flag "-h" "Human readable sizes (1K 243M 2G)")
            (Opts flag "-S" "Sort by size")
            (Opts flag "-X" "Sort by extension")
            (Opts flag "-v" "Sort by version")
            (Opts flag "-t" "Sort by mtime")
            (Opts text "\t-tc\tSort by ctime")
            (Opts text "\t-tu\tSort by atime")
            (Opts flag "-r" "Reverse sort order")
            (Opts arg "-w" "N" "Format N columns wide")
            (Opts hidden (Opts flag "-c" ""))
            (Opts hidden (Opts flag "-u" ""))
            (Opts hidden (Opts flag "-C" ""))))))
    (pair "pwd"
      (list
        (Opts declare "pwd" ""
          "Print the full filename of the current working directory"
          (list
            (Opts hidden (Opts flag "-L" ""))
            (Opts hidden (Opts flag "-P" ""))))))
    (pair "mv"
      (list
        (Opts declare "mv" "[-finT] SOURCE DEST\nor: mv [-fin] SOURCE... { -t DIRECTORY | DIRECTORY }"
          "Rename SOURCE to DEST, or move SOURCEs to DIRECTORY"
          (list
            (Opts flag "-f" "Don't prompt before overwriting")
            (Opts flag "-i" "Interactive, prompt before overwrite")
            (Opts flag "-n" "Don't overwrite an existing file")
            (Opts flag "-T" "Refuse to move if DEST is a directory")))))
    (pair "rmdir"
      (list
        (Opts declare "rmdir" "[-p] DIRECTORY..."
          "Remove DIRECTORY if it is empty"
          (list
            (Opts flag "-p" "Include parents")))))
    (pair "install"
      (list
        (Opts declare "install" "[-cdDsp] [-o USER] [-g GRP] [-m MODE] [-t DIR] [SOURCE]... DEST"
          "Copy files and set attributes"
          (list
            (Opts flag "-c" "Just copy (default)")
            (Opts flag "-d" "Create directories")
            (Opts flag "-D" "Create leading target directories")
            (Opts flag "-p" "Preserve date")
            (Opts arg "-o" "USER" "Set ownership")
            (Opts arg "-g" "GRP" "Set group ownership")
            (Opts arg "-m" "MODE" "Set permissions")
            (Opts arg "-t" "DIR" "Install to DIR")))))
    (pair "mktemp"
      (list
        (Opts declare "mktemp" "[-dt] [-p DIR] [TEMPLATE]"
          "Create a temporary file with name based on TEMPLATE and print its name.\nTEMPLATE must end with XXXXXX (e.g. [/dir/]nameXXXXXX).\nWithout TEMPLATE, -t tmp.XXXXXX is assumed."
          (list
            (Opts flag "-d" "Make directory, not file")
            (Opts flag "-q" "Fail silently on errors")
            (Opts flag "-t" "Prepend base directory name to TEMPLATE")
            (Opts arg "-p" "DIR" "Use DIR as a base directory (implies -t)")
            (Opts flag "-u" "Do not create anything; print a name")
            (Opts text "")
            (Opts text "Base directory is: -p DIR, else $TMPDIR, else /tmp")))))
    (pair "cmp"
      (list
        (Opts declare "cmp" "[-l|s] [-n NUM] FILE1 [FILE2 [SKIP1 [SKIP2]]]"
          "Compare FILE1 with FILE2 (or stdin)"
          (list
            (Opts flag "-l" "Show decimal offset and octal byte value for differing bytes,")
            (Opts text "\t\tdon't stop on first mismatch")
            (Opts flag "-s" "Quiet")
            (Opts arg "-n" "NUM" "Compare at most NUM bytes")))))
    ; -d is an honoured no-op here; cu/diff.x says why, and what -a turns off.
    (pair "diff"
      (list
        (Opts declare "diff" "[-abBdiNqrTstw] [-L LABEL] [-S FILE] [-U LINES] FILE1 FILE2"
          "Compare files line by line and output the differences between them.\nThis implementation supports unified diffs only."
          (list
            (Opts flag "-a" "Treat all files as text")
            (Opts flag "-b" "Ignore changes in the amount of whitespace")
            (Opts flag "-B" "Ignore changes whose lines are all blank")
            (Opts flag "-d" "Try hard to find a smaller set of changes")
            (Opts flag "-i" "Ignore case differences")
            (Opts text "\t-L\tUse LABEL instead of the filename in the unified header")
            (Opts flag "-N" "Treat absent files as empty")
            (Opts flag "-q" "Output only whether files differ")
            (Opts flag "-r" "Recurse")
            (Opts text "\t-S\tStart with FILE when comparing directories")
            (Opts flag "-T" "Make tabs line up by prefixing a tab when necessary")
            (Opts flag "-s" "Report when two files are the same")
            (Opts flag "-t" "Expand tabs to spaces in output")
            (Opts text "\t-U\tOutput LINES lines of context")
            (Opts flag "-w" "Ignore all whitespace")
            (Opts hidden (Opts arg "-U" "" ""))
            (Opts hidden (Opts arg "-L" "" ""))
            (Opts hidden (Opts arg "-S" "" ""))))))
    ; the paths come first and the grammar after them, so the parse stops at the
    ; first operand and the applet reads what is left
    (pair "find"
      (list
        (Opts declare "find" "[-HL] [PATH]... [OPTIONS] [ACTIONS]"
          "Search for files and perform actions on them.\nFirst failed action stops processing of current file.\nDefaults: PATH is current directory, action is '-print'"
          (append (list
            (Opts text "\t-maxdepth N\tDescend at most N levels. -maxdepth 0 applies")
            (Opts text "\t\t\tactions to command line arguments only")
            (Opts text "\t-mindepth N\tDon't act on first N levels")
            (Opts text "")
            (Opts text "Actions:")
            (Opts text "\t( ACTIONS )\tGroup actions for -o / -a")
            (Opts text "\t! ACT\t\tInvert ACT's success/failure")
            (Opts text "\tACT1 [-a] ACT2\tIf ACT1 fails, stop, else do ACT2")
            (Opts text "\tACT1 -o ACT2\tIf ACT1 succeeds, stop, else do ACT2")
            (Opts text "\t\t\tNote: -a has higher priority than -o")
            (Opts text "\t-name PATTERN\tMatch file name (w/o directory name) to PATTERN")
            (Opts text "\t-iname PATTERN\tCase insensitive -name")
            (Opts text "\t-path PATTERN\tMatch path to PATTERN")
            (Opts text "\t-type X\t\tFile type is X (one of: f,d,l,b,c,s,p)")
            (Opts text "\t-newer FILE\tmtime is more recent than FILE's")
            (Opts text "\t-size N[bck]\tFile size is N (c:bytes,k:kbytes,b:512 bytes(def.))")
            (Opts text "\t\t\t+/-N: file size is bigger/smaller than N")
            (Opts flag "-empty" "Match empty file/directory")
            (Opts text "If none of the following actions is specified, -print is assumed")
            (Opts flag "-print" "Print file name")
            (Opts flag "-print0" "Print file name, NUL terminated")
            (Opts text "\t-exec CMD ARG ;\tRun CMD with all instances of {} replaced by")
            (Opts text "\t\t\tfile name. Fails if CMD exits with nonzero")
            (Opts text "\t-exec CMD ARG + Run CMD with {} replaced by list of file names"))
            (%cu-hidden-flags %cu-find-primaries))
          (pair (lit column) 24))
        (lit leading)))
    (pair "env"
      (list
        (Opts declare "env" "[-i0] [-u NAME]... [-] [NAME=VALUE]... [PROG ARGS]"
          "Print current environment or run PROG after setting up environment"
          (list
            (Opts flag "-0" "NUL terminated output")
            (Opts arg "-u" "NAME" "Remove variable from environment")
            (Opts hidden (Opts flag "-i" ""))))
        (lit leading)))
    (pair "printenv"
      (list
        (Opts declare "printenv" "[VARIABLE]..."
          "Print environment VARIABLEs.\nIf no VARIABLE specified, print all."
          (list))
        (lit none)))
    (pair "sleep"
      (list
        (Opts declare "sleep" "[N]..."
          "Pause for a time equal to the total of the args given, where each arg can\nhave an optional suffix of (s)econds, (m)inutes, (h)ours, or (d)ays"
          (list))
        (lit none)))
    ; -s is NOT declared; cu/date.x says why.  -I's SPEC is attached and optional,
    ; which Opts has no way to say, so the five spellings are declared outright.
    (pair "date"
      (list
        (Opts declare "date" "[OPTIONS] [+FMT] [[-s] TIME]"
          "Display time (using +FMT), or set time"
          (list
            (Opts flag "-u" "Work in UTC (don't convert to local time)")
            (Opts text "\t[-s] TIME\tSet time to TIME")
            (Opts arg "-d" "TIME" "Display TIME, not 'now'")
            (Opts arg "-D" "FMT" "FMT (strptime format) for -s/-d TIME conversion")
            (Opts arg "-r" "FILE" "Display last modification time of FILE")
            (Opts flag "-R" "Output RFC-2822 date")
            (Opts text "\t-I[SPEC]\tOutput ISO-8601 date")
            (Opts text "\t\t\tSPEC=date (default), hours, minutes, seconds or ns")
            (Opts text "")
            (Opts text "Recognized TIME formats:")
            (Opts text "\t@seconds_since_1970")
            (Opts text "\thh:mm[:ss]")
            (Opts text "\t[YYYY.]MM.DD-hh:mm[:ss]")
            (Opts text "\tYYYY-MM-DD hh:mm[:ss]")
            (Opts text "\t[[[[[YY]YY]MM]DD]hh]mm[.ss]")
            (Opts text "\t'date TIME' form accepts MMDDhhmm[[YY]YY][.ss] instead")
            (Opts hidden (Opts flag "-I" ""))
            (Opts hidden (Opts flag "-Idate" ""))
            (Opts hidden (Opts flag "-Ihours" ""))
            (Opts hidden (Opts flag "-Iminutes" ""))
            (Opts hidden (Opts flag "-Iseconds" ""))
            (Opts hidden (Opts flag "-Ins" "")))
          (pair (lit column) 24))))
    (pair "which"
      (list
        (Opts declare "which" "[-a] COMMAND..."
          "Locate COMMAND"
          (list
            (Opts flag "-a" "Show all matches")))))
    ; busybox spells each long option as a short one too; wget reads either.  -n
    ; takes busybox's four ignored -nX forms whole.
    (pair "wget"
      (list
        (Opts declare "wget" "[-cqS] [--spider] [-O FILE] [-o LOGFILE] [--header STR]...\n\t[-U AGENT] [--post-data STR | --post-file FILE] [-Y on/off]\n\t[--no-check-certificate] [-P DIR] [-T SEC] [-t TRIES] URL..."
          "Retrieve files via HTTP or FTP"
          (list
            (Opts flag "--spider" "Only check URL existence: $? is 0 if exists")
            (Opts arg "--header" "STR" "Add STR (of form 'header: value') to headers")
            (Opts arg "-U" "AGENT" "Use AGENT for User-Agent header")
            (Opts arg "--post-data" "STR" "Send STR using POST method")
            (Opts arg "--post-file" "FILE" "Send FILE using POST method")
            (Opts flag "--no-check-certificate" "Don't validate the server's certificate")
            (Opts flag "-c" "Continue retrieval of partial download")
            (Opts flag "-q" "Quiet")
            (Opts arg "-P" "DIR" "Save to DIR (default .)")
            (Opts text "\t-S    \t\tShow server response")
            (Opts arg "-t" "TRIES" "Retry count (default 20)")
            (Opts arg "-T" "SEC" "Network read timeout is SEC seconds")
            (Opts arg "-O" "FILE" "Save to FILE ('-' for stdout)")
            (Opts arg "-o" "LOGFILE" "Log messages to FILE")
            (Opts arg "-Y" "on/off" "Use proxy")
            (Opts hidden (Opts flag "-S" ""))
            (Opts hidden (Opts flag "--continue" ""))
            (Opts hidden (Opts flag "--quiet" ""))
            (Opts hidden (Opts flag "--server-response" ""))
            (Opts hidden (Opts flag "-nv" ""))
            (Opts hidden (Opts flag "-nc" ""))
            (Opts hidden (Opts flag "-nH" ""))
            (Opts hidden (Opts flag "-np" ""))
            (Opts hidden (Opts flag "--passive-ftp" ""))
            (Opts hidden (Opts flag "--no-cache" ""))
            (Opts hidden (Opts flag "--no-verbose" ""))
            (Opts hidden (Opts flag "--no-clobber" ""))
            (Opts hidden (Opts flag "--no-host-directories" ""))
            (Opts hidden (Opts flag "--no-parent" ""))
            (Opts hidden (Opts arg "--output-document" "" ""))
            (Opts hidden (Opts arg "--output-file" "" ""))
            (Opts hidden (Opts arg "--directory-prefix" "" ""))
            (Opts hidden (Opts arg "--proxy" "" ""))
            (Opts hidden (Opts arg "--user-agent" "" ""))
            (Opts hidden (Opts arg "--timeout" "" ""))
            (Opts hidden (Opts arg "--tries" "" "")))
          (pair (lit column) 24))))
    (pair "whois"
      (list
        (Opts declare "whois" "[-i] [-h SERVER] [-p PORT] NAME..."
          "Query WHOIS info about NAME"
          (list
            (Opts flag "-i" "Show redirect results too")
            (Opts text "\t-h,-p\tServer to query")
            (Opts hidden (Opts arg "-h" "" ""))
            (Opts hidden (Opts arg "-p" "" ""))))))
    ; nc parses its own line -- -e takes the rest of it, the program's flags too
    ; -- so none: cu/nc.x's own lists say what it accepts
    (pair "nc"
      (list
        (Opts declare "nc" "[OPTIONS] HOST PORT  - connect\nnc [OPTIONS] -l -p PORT [HOST] [PORT]  - listen"
          "\t-e PROG\tRun PROG after connect (must be last)\n\t-l\tListen mode, for inbound connects\n\t-lk\tWith -e, provides persistent server\n\t-p PORT\tLocal port\n\t-s ADDR\tLocal address\n\t-w SEC\tTimeout for connects and final net reads\n\t-i SEC\tDelay interval for lines sent\n\t-n\tDon't do DNS resolution\n\t-u\tUDP mode\n\t-b\tAllow broadcasts\n\t-v\tVerbose\n\t-o FILE\tHex dump traffic\n\t-z\tZero-I/O mode (scanning)"
          (append (list)
            (%cu-hidden-flags %nc-flags)
            (%cu-hidden-args %nc-values)))
        (lit none)))
    ; nslookup reads its own -NAME=VALUE options, so none
    (pair "nslookup"
      (list
        (Opts declare "nslookup" "[-type=QUERY_TYPE] [-debug] HOST [DNS_SERVER]"
          "Query DNS about HOST\n\nQUERY_TYPE: soa,ns,a,aaaa,cname,mx,txt,ptr,srv,any"
          (append (list)
            (%cu-hidden-flags (list "-debug"))
            (%cu-hidden-args (list "-type" "-querytype" "-port" "-retry" "-timeout" "-t"))))
        (lit none)))
    ; tftp reads tftp-hpa's "-c get FILE" before its options, so none; -m is
    ; HPA_COMPAT's mode, taken and never shown
    (pair "tftp"
      (list
        (Opts declare "tftp" "[OPTIONS] HOST [PORT]"
          "Transfer a file from/to tftp server"
          (list
            (Opts arg "-l" "FILE" "Local FILE")
            (Opts arg "-r" "FILE" "Remote FILE")
            (Opts flag "-g" "Get file")
            (Opts flag "-p" "Put file")
            (Opts arg "-b" "SIZE" "Transfer blocks in bytes")
            (Opts hidden (Opts arg "-m" "" ""))))
        (lit none)))
    (pair "tftpd"
      (list
        (Opts declare "tftpd" "[-crl] [-u USER] [DIR]"
          "Transfer a file on tftp client's request\n\ntftpd is an inetd service, inetd.conf line:\n\t69 dgram udp nowait root tftpd tftpd -l /files/to/serve\nCan be run from udpsvd:\n\tudpsvd -vE 0.0.0.0 69 tftpd /files/to/serve"
          (append
            (list
              (Opts text "\t-r\tProhibit upload")
              (Opts text "\t-c\tAllow file creation via upload")
              (Opts text "\t-u USER\tAccess files as USER")
              (Opts text "\t-l\tLog to syslog (inetd mode requires this)"))
            (%cu-hidden-flags (list "-c" "-r" "-l"))
            (%cu-hidden-args (list "-u"))))
        (lit inetd)))
    ; ftpget and ftpput share ftpgetput.c's options: ftpput takes -c too, and
    ; busybox's --continue takes an argument; -P's row has no text of its own
    (pair "ftpget"
      (list
        (Opts declare "ftpget" "[OPTIONS] HOST [LOCAL_FILE] REMOTE_FILE"
          "Download a file via FTP"
          (append
            (list
              (Opts flag "-c" "Continue previous transfer")
              (Opts flag "-v" "Verbose")
              (Opts arg "-u" "USER" "Username")
              (Opts arg "-p" "PASS" "Password")
              (Opts text "\t-P PORT")
              (Opts hidden (Opts arg "-P" "" "")))
            (%cu-hidden-flags (list "--verbose"))
            (%cu-hidden-args (list "--continue" "--username" "--password" "--port"))))))
    (pair "ftpput"
      (list
        (Opts declare "ftpput" "[OPTIONS] HOST [REMOTE_FILE] LOCAL_FILE"
          "Upload a file to a FTP server"
          (append
            (list
              (Opts flag "-v" "Verbose")
              (Opts arg "-u" "USER" "Username")
              (Opts arg "-p" "PASS" "Password")
              (Opts text "\t-P PORT")
              (Opts hidden (Opts arg "-P" "" "")))
            (%cu-hidden-flags (list "-c" "--verbose"))
            (%cu-hidden-args (list "--continue" "--username" "--password" "--port"))))))
    ; httpd's rows are laid out by hand
    (pair "httpd"
      (list
        (Opts declare "httpd"
          "[-ifv[v]] [-c CONFFILE] [-p [IP:]PORT] [-M MAXCONN] [-K KILLSEC] [-u USER[:GRP]] [-r REALM] [-h HOME]\nor httpd -d/-e/-m STRING"
          "Listen for incoming HTTP requests"
          (append
            (list
              (Opts text "\t-i\t\tInetd mode")
              (Opts text "\t-f\t\tRun in foreground")
              (Opts text "\t-v[v]\t\tVerbose")
              (Opts text "\t-p [IP:]PORT\tBind to IP:PORT (default *:80)")
              (Opts text "\t-M NUM\t\tPause if NUM connections are open (default 256)")
              (Opts text "\t-K NUM\t\tKill CGIs after NUM seconds")
              (Opts text "\t-u USER[:GRP]\tSet uid/gid after binding to port")
              (Opts text "\t-r REALM\tAuthentication Realm for Basic Authentication")
              (Opts text "\t-h HOME\t\tHome directory (default .)")
              (Opts text "\t-c FILE\t\tConfiguration file (default {/etc,HOME}/httpd.conf)")
              (Opts text "\t-m STRING\tMD5 crypt STRING")
              (Opts text "\t-e STRING\tHTML encode STRING")
              (Opts text "\t-d STRING\tURL decode STRING"))
            (%cu-hidden-flags (list "-i" "-f" "-v"))
            (%cu-hidden-args (list "-p" "-M" "-K" "-u" "-r" "-h" "-c" "-m" "-e" "-d"))))))
    (pair "dnsd"
      (list
        (Opts declare "dnsd" "[-dvs] [-c CONFFILE] [-t TTL_SEC] [-p PORT] [-i ADDR]"
          "Small static DNS server daemon"
          (append
            (list
              (Opts text "\t-c FILE\tConfig file")
              (Opts text "\t-t SEC\tTTL")
              (Opts text "\t-p PORT\tListen on PORT")
              (Opts text "\t-i ADDR\tListen on ADDR")
              (Opts text "\t-d\tDaemonize")
              (Opts text "\t-v\tVerbose")
              (Opts text "\t-s\tSend successful replies only. Use this if you want")
              (Opts text "\t\tto use /etc/resolv.conf with two nameserver lines:")
              (Opts text "\t\t\tnameserver DNSD_SERVER")
              (Opts text "\t\t\tnameserver NORMAL_DNS_SERVER"))
            (%cu-hidden-flags (list "-d" "-v" "-s"))
            (%cu-hidden-args (list "-c" "-t" "-p" "-i"))))))
    (pair "inetd"
      (list
        (Opts declare "inetd" "[-fe] [-q N] [-R N] [CONFFILE]"
          "Listen for network connections and launch programs"
          (append
            (list
              (Opts text "\t-f\tRun in foreground")
              (Opts text "\t-e\tLog to stderr")
              (Opts text "\t-q N\tSocket listen queue (default 128)")
              (Opts text "\t-R N\tPause services after N connects/min")
              (Opts text "\t\t(default 0 - disabled)")
              (Opts text "\tDefault CONFFILE is /etc/inetd.conf"))
            (%cu-hidden-flags (list "-f" "-e"))
            (%cu-hidden-args (list "-q" "-R"))))))
    ; tcpudp.c's getopt string, -i -x -t -p among it, stops at IP
    (pair "tcpsvd"
      (list
        (Opts declare "tcpsvd" "[-hEv] [-c N] [-C N[:MSG]] [-b N] [-u USER] [-l NAME] IP PORT PROG"
          "Create TCP socket, bind to IP:PORT and listen for incoming connections.\nRun PROG for each connection."
          (append
            (list
              (Opts text "\tIP PORT\t\tIP:PORT to listen on")
              (Opts text "\tPROG ARGS\tProgram to run")
              (Opts text "\t-u USER[:GRP]\tChange to user/group after bind")
              (Opts text "\t-c N\t\tUp to N connections simultaneously (default 30)")
              (Opts text "\t-b N\t\tAllow backlog of approximately N TCP SYNs (default 20)")
              (Opts text "\t-C N[:MSG]\tAllow only up to N connections from the same IP:")
              (Opts text "\t\t\tnew connections from this IP address are closed")
              (Opts text "\t\t\timmediately, MSG is written to the peer before close")
              (Opts text "\t-E\t\tDon't set up environment")
              (Opts text "\t-h\t\tLook up peer's hostname")
              (Opts text "\t-l NAME\t\tLocal hostname (else look up local hostname in DNS)")
              (Opts text "\t-v\t\tVerbose")
              (Opts text "")
              (Opts text "Environment if no -E:")
              (Opts text "PROTO='TCP'")
              (Opts text "TCPREMOTEADDR='ip:port' ('[ip]:port' for IPv6)")
              (Opts text "TCPLOCALADDR='ip:port'")
              (Opts text "TCPORIGDSTADDR='ip:port' of destination before firewall")
              (Opts text "\tUseful for REDIRECTed-to-local connections:")
              (Opts text "\tiptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to 8080")
              (Opts text "TCPCONCURRENCY=num_of_connects_from_this_ip")
              (Opts text "If -h:")
              (Opts text "TCPLOCALHOST='hostname' (-l NAME is used if specified)")
              (Opts text "TCPREMOTEHOST='hostname'"))
            (%cu-hidden-flags (list "-E" "-h" "-p" "-v"))
            (%cu-hidden-args (list "-c" "-C" "-i" "-x" "-u" "-l" "-b" "-t"))))
        (lit leading)))
    (pair "udpsvd"
      (list
        (Opts declare "udpsvd" "[-hEv] [-c N] [-u USER] [-l NAME] IP PORT PROG"
          "Create UDP socket, bind to IP:PORT and wait for incoming packets.\nRun PROG for each packet, redirecting all further packets with same\npeer ip:port to it."
          (append
            (list
              (Opts text "\tIP PORT\t\tIP:PORT to listen on")
              (Opts text "\tPROG ARGS\tProgram to run")
              (Opts text "\t-u USER[:GRP]\tChange to user/group after bind")
              (Opts text "\t-c N\t\tUp to N connections simultaneously (default 30)")
              (Opts text "\t-E\t\tDon't set up environment")
              (Opts text "\t-h\t\tLook up peer's hostname")
              (Opts text "\t-l NAME\t\tLocal hostname (else look up local hostname in DNS)")
              (Opts text "\t-v\t\tVerbose")
              (Opts text "")
              (Opts text "Environment if no -E:")
              (Opts text "PROTO='UDP'")
              (Opts text "UDPREMOTEADDR='ip:port' ('[ip]:port' for IPv6)")
              (Opts text "UDPLOCALADDR='ip:port'")
              (Opts text "If -h:")
              (Opts text "UDPLOCALHOST='hostname' (-l NAME is used if specified)")
              (Opts text "UDPREMOTEHOST='hostname'"))
            (%cu-hidden-flags (list "-E" "-h" "-p" "-v"))
            (%cu-hidden-args (list "-c" "-C" "-i" "-x" "-u" "-l" "-b" "-t"))))
        (lit leading)))
    (pair "ftpd"
      (list
        (Opts declare "ftpd" "[-wvS] [-a USER] [-t SEC] [-T SEC] [DIR]"
          "FTP server. Chroots to DIR, if this fails (run by non-root), cds to it.\nIt is an inetd service, inetd.conf line:\n\t21 stream tcp nowait root ftpd ftpd /files/to/serve\nCan be run from tcpsvd:\n\ttcpsvd -vE 0.0.0.0 21 ftpd /files/to/serve"
          (append
            (list
              (Opts text "\t-w\tAllow upload")
              (Opts text "\t-A\tNo login required, client access occurs under ftpd's UID")
              (Opts text "\t-a USER\tEnable 'anonymous' login and map it to USER")
              (Opts text "\t-v\tLog errors to stderr. -vv: verbose log")
              (Opts text "\t-S\tLog errors to syslog. -SS: verbose log")
              (Opts text "\t-t,-T N\tIdle and absolute timeout"))
            (%cu-hidden-flags (list "-w" "-A" "-v" "-S"))
            (%cu-hidden-args (list "-a" "-t" "-T"))))))
    (pair "ipcalc"
      (list
        (Opts declare "ipcalc" "[-bnmphs] ADDRESS[/PREFIX] [NETMASK]"
          "Calculate and display network settings from IP address"
          (append
            (list
              (Opts flag "-b" "Broadcast address")
              (Opts flag "-n" "Network address")
              (Opts flag "-m" "Default netmask for IP")
              (Opts flag "-p" "Prefix for IP/NETMASK")
              (Opts flag "-h" "Resolved host name")
              (Opts flag "-s" "No error messages"))
            (%cu-hidden-flags (list "--broadcast" "--network" "--netmask" "--prefix" "--hostname" "--silent"))))))
    ; -p is NOT here on purpose; cu/sys2.x says why
    (pair "xargs"
      (list
        (Opts declare "xargs" "[OPTIONS] [PROG ARGS]"
          "Run PROG on every item given by stdin"
          (list
            (Opts flag "-0" "NUL terminated input")
            (Opts arg "-a" "FILE" "Read from FILE instead of stdin")
            (Opts flag "-r" "Don't run command if input is empty")
            (Opts flag "-t" "Print the command on stderr before execution")
            (Opts arg "-E" "STR,-e[STR]" "STR stops input processing")
            (Opts arg "-I" "STR" "Replace STR within PROG ARGS with input line")
            (Opts arg "-n" "N" "Pass no more than N args to PROG")
            (Opts arg "-s" "N" "Pass command line of no more than N bytes")
            (Opts flag "-x" "Exit if size is exceeded"))
          (pair (lit column) 16))
        (lit leading)))
    ; busybox's getopt32 string for vi, "c:*HhR": -c may be given again
    (pair "vi"
      (list
        (Opts declare "vi" "[-c CMD] [-R] [-H] [FILE]..."
          "Edit FILE"
          (list
            (Opts arg "-c" "CMD" "Initial command to run ($EXINIT and ~/.exrc also available)")
            (Opts flag "-R" "Read-only")
            (Opts flag "-H" "List available features")
            (Opts hidden (Opts flag "-h" ""))))))
    (pair "more"
      (list
        (Opts declare "more" "[FILE]..."
          "View FILE (or stdin) one screenful at a time"
          (list
            (Opts hidden (Opts flag "-d" ""))
            (Opts hidden (Opts flag "-e" ""))
            (Opts hidden (Opts flag "-f" ""))
            (Opts hidden (Opts flag "-l" ""))
            (Opts hidden (Opts flag "-s" ""))
            (Opts hidden (Opts flag "-u" ""))))))
    (pair "clear"
      (list
        (Opts declare "clear" ""
          "Clear screen"
          (list))
        (lit none)))
    (pair "reset"
      (list
        (Opts declare "reset" ""
          "Reset terminal (ESC codes) and termios (signals, buffering, echo)"
          (list))
        (lit none)))
    (pair "tsort"
      (list
        (Opts declare "tsort" "[FILE]"
          "Topological sort"
          (list))
        (lit none)))
    (pair "strings"
      (list
        (Opts declare "strings" "[-fo] [-t o|d|x] [-n LEN] [FILE]..."
          "Display printable strings in a binary file"
          (list
            (Opts flag "-f" "Precede strings with filenames")
            (Opts flag "-o" "Precede strings with octal offsets")
            (Opts arg "-t" "o|d|x" "Precede strings with offsets in base 8/10/16")
            (Opts arg "-n" "LEN" "At least LEN characters form a string (default 4)")
            (Opts hidden (Opts flag "-a" ""))))))
    (pair "cal"
      (list
        (Opts declare "cal" "[-jmy] [[MONTH] YEAR]"
          "Display a calendar"
          (list
            (Opts flag "-j" "Use julian dates")
            (Opts flag "-m" "Week starts on Monday")
            (Opts flag "-y" "Display the entire year")))))
    (pair "hexdump"
      (list
        (Opts declare "hexdump" "[-bcdoxCv] [-e FMT] [-f FMT_FILE] [-n LEN] [-s OFS] [FILE]..."
          "Display FILEs (or stdin) in a user specified format"
          (list
            (Opts flag "-b" "1-byte octal display")
            (Opts flag "-c" "1-byte character display")
            (Opts flag "-d" "2-byte decimal display")
            (Opts flag "-o" "2-byte octal display")
            (Opts flag "-x" "2-byte hex display")
            (Opts flag "-C" "hex+ASCII 16 bytes per line")
            (Opts flag "-v" "Show all (no dup folding)")
            (Opts arg "-e" "FORMAT_STR" "Example: '16/1 \"%02x|\"\"\\n\"'")
            (Opts text "\t-f FORMAT_FILE")
            (Opts arg "-n" "LENGTH" "Show only first LENGTH bytes")
            (Opts arg "-s" "OFFSET" "Skip OFFSET bytes")
            (Opts hidden (Opts arg "-f" "" ""))))))
    (pair "hd"
      (list
        (Opts declare "hd" "FILE..."
          "hd is an alias for hexdump -C"
          (list))))
    (pair "xxd"
      (list
        (Opts declare "xxd" "[-ri] [-ps] [-g N] [-c N] [-l LEN] [-s OFS] [-o OFS] [FILE]"
          "Hex dump FILE (or stdin)"
          (list
            (Opts arg "-g" "N" "Bytes per group (default 2)")
            (Opts arg "-c" "N" "Bytes per line (default:16, -ps:30, -i:12)")
            (Opts flag "-ps" "Show only hex bytes (no offset/spaces)")
            (Opts flag "-i" "C include file style")
            (Opts arg "-l" "LENGTH" "Show only first LENGTH bytes")
            (Opts arg "-s" "OFFSET" "Skip OFFSET bytes")
            (Opts arg "-o" "OFFSET" "Add OFFSET to displayed offset")
            (Opts flag "-r" "Reverse (with -p, assumes no offsets in input)")
            (Opts hidden (Opts flag "-a" ""))
            (Opts hidden (Opts flag "-p" ""))))))
    (pair "fsync"
      (list
        (Opts declare "fsync" "[-d] FILE..."
          "Write all buffered blocks in FILEs to disk"
          (list
            (Opts flag "-d" "Avoid syncing metadata")))))
    (pair "flock"
      (list
        (Opts declare "flock" "[-sxun] FD | { FILE [-c] PROG ARGS }"
          "[Un]lock file descriptor, or lock FILE, run PROG"
          (list
            (Opts flag "-s" "Shared lock")
            (Opts flag "-x" "Exclusive lock (default)")
            (Opts flag "-u" "Unlock FD")
            (Opts flag "-n" "Fail rather than wait")
            (Opts hidden (Opts flag "--shared" ""))
            (Opts hidden (Opts flag "--exclusive" ""))
            (Opts hidden (Opts flag "--unlock" ""))
            (Opts hidden (Opts flag "--nonblock" ""))))
        (lit leading)))
    (pair "setsid"
      (list
        (Opts declare "setsid" "[-c] PROG ARGS"
          "Run PROG in a new session. PROG will have no controlling terminal\nand will not be affected by keyboard signals (^C etc)."
          (list
            (Opts flag "-c" "Set controlling terminal to stdin")))
        (lit leading)))
    (pair "ttysize"
      (list
        (Opts declare "ttysize" "[w] [h]"
          "Print dimensions of stdin tty, or 80x24"
          (list))
        (lit none)))
    (pair "nologin"
      (list
        (Opts declare "nologin" ""
          "Politely refuse a login"
          (list))
        (lit none)))
    (pair "pipe_progress"
      (list
        (Opts declare "pipe_progress" "" ()
          (list)
          (pair (lit help) #f))
        (lit none)))
    (pair "getopt"
      (list
        (Opts declare "getopt" "[OPTIONS] [--] OPTSTRING PARAMS" ()
          (list
            (Opts flag "-a" "Allow long options starting with single -")
            (Opts arg "-l" "LOPT[,...]" "Long options to recognize")
            (Opts arg "-n" "PROGNAME" "The name under which errors are reported")
            (Opts arg "-o" "OPTSTRING" "Short options to recognize")
            (Opts flag "-q" "No error messages on unrecognized options")
            (Opts flag "-Q" "No normal output")
            (Opts arg "-s" "SHELL" "Set shell quoting conventions")
            (Opts flag "-T" "Version test (exits with 4)")
            (Opts flag "-u" "Don't quote output")
            (Opts text "")
            (Opts text "Example:")
            (Opts text "")
            (Opts text "O=`getopt -l bb: -- ab:c:: \"$@\"` || exit 1")
            (Opts text "eval set -- \"$O\"")
            (Opts text "while true; do")
            (Opts text "\tcase \"$1\" in")
            (Opts text "\t-a)\techo A; shift;;")
            (Opts text "\t-b|--bb) echo \"B:'$2'\"; shift 2;;")
            (Opts text "\t-c)\tcase \"$2\" in")
            (Opts text "\t\t\"\")\techo C; shift 2;;")
            (Opts text "\t\t*)\techo \"C:'$2'\"; shift 2;;")
            (Opts text "\t\tesac;;")
            (Opts text "\t--)\tshift; break;;")
            (Opts text "\t*)\techo Error; exit 1;;")
            (Opts text "\tesac")
            (Opts text "done")
            (Opts hidden (Opts flag "--alternative" ""))
            (Opts hidden (Opts flag "--quiet" ""))
            (Opts hidden (Opts flag "--quiet-output" ""))
            (Opts hidden (Opts flag "--test" ""))
            (Opts hidden (Opts flag "--unquoted" ""))
            (Opts hidden (Opts arg "--longoptions" "" ""))
            (Opts hidden (Opts arg "--name" "" ""))
            (Opts hidden (Opts arg "--options" "" ""))
            (Opts hidden (Opts arg "--shell" "" ""))))
        (lit leading)))
    (pair "tar"
      (list
        (Opts declare "tar" "c|x|t [-zahmvokO] [-f TARFILE] [-C DIR] [-T FILE] [-X FILE] [LONGOPT]... [FILE]..."
          "Create, extract, or list files from a tar file"
          (list
            (Opts text "\tc\tCreate")
            (Opts text "\tx\tExtract")
            (Opts text "\tt\tList")
            (Opts text "\t-f FILE\tName of TARFILE ('-' for stdin/out)")
            (Opts text "\t-C DIR\tChange to DIR before operation")
            (Opts text "\t-v\tVerbose")
            (Opts text "\t-O\tExtract to stdout")
            (Opts text "\t-m\tDon't restore mtime")
            (Opts text "\t-o\tDon't restore user:group")
            (Opts text "\t-k\tDon't replace existing files")
            (Opts text "\t-z\t(De)compress using gzip")
            (Opts text "\t-a\t(De)compress based on extension")
            (Opts text "\t-h\tFollow symlinks")
            (Opts text "\t-T FILE\tFile with names to include")
            (Opts text "\t-X FILE\tFile with glob patterns to exclude")
            (Opts text "\t--exclude PATTERN\tGlob pattern to exclude")
            (Opts text "\t--overwrite\t\tReplace existing files")
            (Opts text "\t--strip-components NUM\tNUM of leading components to strip")
            (Opts text "\t--no-recursion\t\tDon't descend in directories")
            (Opts text "\t--numeric-owner\t\tUse numeric user:group")
            (Opts text "\t--no-same-permissions\tDon't restore access permissions")
            (Opts hidden (Opts arg "-f" "FILE" ""))
            (Opts hidden (Opts arg "-C" "DIR" ""))
            (Opts hidden (Opts flag "-v" ""))
            (Opts hidden (Opts flag "-O" ""))
            (Opts hidden (Opts flag "-m" ""))
            (Opts hidden (Opts flag "-o" ""))
            (Opts hidden (Opts flag "-k" ""))
            (Opts hidden (Opts flag "-z" ""))
            (Opts hidden (Opts flag "--gzip" ""))
            (Opts hidden (Opts flag "-a" ""))
            (Opts hidden (Opts flag "-h" ""))
            (Opts hidden (Opts arg "-T" "FILE" ""))
            (Opts hidden (Opts arg "-X" "FILE" ""))
            (Opts hidden (Opts arg "--exclude" "PATTERN" ""))
            (Opts hidden (Opts arg "--strip-components" "NUM" ""))
            (Opts hidden (Opts flag "-c" ""))
            (Opts hidden (Opts flag "-x" ""))
            (Opts hidden (Opts flag "-t" ""))
            (Opts hidden (Opts flag "-p" ""))
            (Opts hidden (Opts flag "--overwrite" ""))
            (Opts hidden (Opts flag "--no-recursion" ""))
            (Opts hidden (Opts flag "--numeric-owner" ""))
            (Opts hidden (Opts flag "--no-same-permissions" ""))
            (Opts hidden (Opts flag "--list" ""))
            (Opts hidden (Opts flag "--extract" ""))
            (Opts hidden (Opts flag "--create" ""))
            (Opts hidden (Opts flag "--to-stdout" ""))
            (Opts hidden (Opts flag "--no-same-owner" ""))
            (Opts hidden (Opts flag "--same-permissions" ""))
            (Opts hidden (Opts flag "--verbose" ""))
            (Opts hidden (Opts flag "--keep-old" ""))
            (Opts hidden (Opts flag "--dereference" ""))
            (Opts hidden (Opts flag "--touch" ""))
            (Opts hidden (Opts arg "--file" "" ""))
            (Opts hidden (Opts arg "--directory" "" ""))
            (Opts hidden (Opts arg "--files-from" "" ""))
            (Opts hidden (Opts arg "--exclude-from" "" ""))))))
    (pair "gzip"
      (list
        (Opts declare "gzip" "[-cfkdt] [FILE]..."
          "Compress FILEs (or stdin)"
          (list
            (Opts text "\t-d\tDecompress")
            (Opts text "\t-c\tWrite to stdout")
            (Opts text "\t-f\tForce")
            (Opts text "\t-k\tKeep input files")
            (Opts text "\t-t\tTest integrity")
            (Opts hidden (Opts flag "-c" ""))
            (Opts hidden (Opts flag "-f" ""))
            (Opts hidden (Opts flag "-k" ""))
            (Opts hidden (Opts flag "-v" ""))
            (Opts hidden (Opts flag "-q" ""))
            (Opts hidden (Opts flag "-d" ""))
            (Opts hidden (Opts flag "-t" ""))
            (Opts hidden (Opts flag "-n" ""))
            (Opts hidden (Opts flag "-1" ""))
            (Opts hidden (Opts flag "-2" ""))
            (Opts hidden (Opts flag "-3" ""))
            (Opts hidden (Opts flag "-4" ""))
            (Opts hidden (Opts flag "-5" ""))
            (Opts hidden (Opts flag "-6" ""))
            (Opts hidden (Opts flag "-7" ""))
            (Opts hidden (Opts flag "-8" ""))
            (Opts hidden (Opts flag "-9" ""))
            (Opts hidden (Opts flag "--stdout" ""))
            (Opts hidden (Opts flag "--to-stdout" ""))
            (Opts hidden (Opts flag "--force" ""))
            (Opts hidden (Opts flag "--verbose" ""))
            (Opts hidden (Opts flag "--decompress" ""))
            (Opts hidden (Opts flag "--uncompress" ""))
            (Opts hidden (Opts flag "--test" ""))
            (Opts hidden (Opts flag "--quiet" ""))
            (Opts hidden (Opts flag "--fast" ""))
            (Opts hidden (Opts flag "--best" ""))
            (Opts hidden (Opts flag "--no-name" ""))))))
    (pair "gunzip"
      (list
        (Opts declare "gunzip" "[-cfkt] [FILE]..."
          "Decompress FILEs (or stdin)"
          (list
            (Opts text "\t-c\tWrite to stdout")
            (Opts text "\t-f\tForce")
            (Opts text "\t-k\tKeep input files")
            (Opts text "\t-t\tTest integrity")
            (Opts hidden (Opts flag "-c" ""))
            (Opts hidden (Opts flag "-f" ""))
            (Opts hidden (Opts flag "-k" ""))
            (Opts hidden (Opts flag "-v" ""))
            (Opts hidden (Opts flag "-q" ""))
            (Opts hidden (Opts flag "-d" ""))
            (Opts hidden (Opts flag "-t" ""))
            (Opts hidden (Opts flag "-n" ""))
            (Opts hidden (Opts flag "--stdout" ""))
            (Opts hidden (Opts flag "--to-stdout" ""))
            (Opts hidden (Opts flag "--force" ""))
            (Opts hidden (Opts flag "--test" ""))
            (Opts hidden (Opts flag "--no-name" ""))))))
    (pair "zcat"
      (list
        (Opts declare "zcat" "[FILE]..."
          "Decompress to stdout"
          (list
            (Opts hidden (Opts flag "-c" ""))
            (Opts hidden (Opts flag "-f" ""))
            (Opts hidden (Opts flag "-k" ""))
            (Opts hidden (Opts flag "-v" ""))
            (Opts hidden (Opts flag "-q" ""))
            (Opts hidden (Opts flag "-d" ""))
            (Opts hidden (Opts flag "-t" ""))
            (Opts hidden (Opts flag "-n" ""))
            (Opts hidden (Opts flag "--stdout" ""))
            (Opts hidden (Opts flag "--to-stdout" ""))
            (Opts hidden (Opts flag "--force" ""))
            (Opts hidden (Opts flag "--test" ""))
            (Opts hidden (Opts flag "--no-name" ""))))))
    (pair "unzip"
      (list
        (Opts declare "unzip" "[-lnojpqK] FILE[.zip] [FILE]... [-x FILE]... [-d DIR]"
          "Extract FILEs from ZIP archive"
          (list
            (Opts text "\t-l\tList contents (with -q for short form)")
            (Opts text "\t-n\tNever overwrite files (default: ask)")
            (Opts text "\t-o\tOverwrite")
            (Opts text "\t-j\tDo not restore paths")
            (Opts text "\t-p\tWrite to stdout")
            (Opts text "\t-t\tTest")
            (Opts text "\t-q\tQuiet")
            (Opts text "\t-K\tDo not clear SUID bit")
            (Opts text "\t-x FILE\tExclude FILEs")
            (Opts text "\t-d DIR\tExtract into DIR")
            (Opts hidden (Opts flag "-l" ""))
            (Opts hidden (Opts flag "-n" ""))
            (Opts hidden (Opts flag "-o" ""))
            (Opts hidden (Opts flag "-j" ""))
            (Opts hidden (Opts flag "-p" ""))
            (Opts hidden (Opts flag "-t" ""))
            (Opts hidden (Opts flag "-q" ""))
            (Opts hidden (Opts flag "-K" ""))
            (Opts hidden (Opts flag "-x" ""))
            (Opts hidden (Opts flag "-v" ""))
            (Opts hidden (Opts arg "-d" "DIR" ""))))))
    (pair "sha384sum"
      (list
        (Opts declare "sha384sum" "[-c[sw]] [FILE]..."
          "Print or check SHA384 checksums"
          (list
            (Opts flag "-c" "Check sums against list in FILEs")
            (Opts flag "-s" "Don't output anything, status code shows success")
            (Opts flag "-w" "Warn about improperly formatted checksum lines")))))
    (pair "hostname"
      (list
        (Opts declare "hostname" "[-sidf] [HOSTNAME | -F FILE]"
          "Show or set hostname or DNS domain name"
          (list
            (Opts text "\t-s\tShort")
            (Opts text "\t-i\tAddresses for the hostname")
            (Opts text "\t-d\tDNS domain name")
            (Opts text "\t-f\tFully qualified domain name")
            (Opts text "\t-F FILE\tUse FILE's content as hostname")
            (Opts hidden (Opts flag "-s" ""))
            (Opts hidden (Opts flag "-i" ""))
            (Opts hidden (Opts flag "-d" ""))
            (Opts hidden (Opts flag "-f" ""))
            (Opts hidden (Opts flag "-v" ""))
            (Opts hidden (Opts flag "--domain" ""))
            (Opts hidden (Opts flag "--fqdn" ""))
            (Opts hidden (Opts arg "-F" "FILE" ""))
            (Opts hidden (Opts arg "--file" "FILE" ""))))))
    (pair "hostid"
      (list
        (Opts declare "hostid" ""
          "Print out a unique 32-bit identifier for the machine"
          (list))
        (lit none)))
    (pair "mountpoint"
      (list
        (Opts declare "mountpoint" "[-q] { [-dn] DIR | -x DEVICE }"
          "Check if DIR is a mountpoint"
          (list
            (Opts text "\t-q\tQuiet")
            (Opts text "\t-d\tPrint major:minor of the filesystem")
            (Opts text "\t-n\tPrint device name of the filesystem")
            (Opts text "\t-x\tPrint major:minor of DEVICE")
            (Opts hidden (Opts flag "-q" ""))
            (Opts hidden (Opts flag "-d" ""))
            (Opts hidden (Opts flag "-n" ""))
            (Opts hidden (Opts flag "-x" ""))))))
    (pair "mknod"
      (list
        (Opts declare "mknod" "[-m MODE] NAME TYPE [MAJOR MINOR]"
          "Create a special file (block, character, or pipe)"
          (list
            (Opts text "\t-m MODE\tCreation mode (default a=rw)")
            (Opts text "TYPE:")
            (Opts text "\tb\tBlock device")
            (Opts text "\tc or u\tCharacter device")
            (Opts text "\tp\tNamed pipe (MAJOR MINOR must be omitted)")
            (Opts hidden (Opts arg "-m" "MODE" ""))))))
    (pair "mesg"
      (list
        (Opts declare "mesg" "[y|n]"
          "Control write access to your terminal\n\ty\tAllow write access to your terminal\n\tn\tDisallow write access to your terminal"
          (list))
        (lit none)))
    (pair "renice"
      (list
        (Opts declare "renice" "[-n] PRIORITY [[-p|g|u] ID...]..."
          "Change scheduling priority of a running process"
          (list
            (Opts text "\t-n\tAdd PRIORITY to current nice value")
            (Opts text "\t\tWithout -n, nice value is set to PRIORITY")
            (Opts text "\t-p\tProcess ids (default)")
            (Opts text "\t-g\tProcess group ids")
            (Opts text "\t-u\tProcess user names")
            (Opts hidden (Opts flag "-n" ""))
            (Opts hidden (Opts flag "-p" ""))
            (Opts hidden (Opts flag "-g" ""))
            (Opts hidden (Opts flag "-u" ""))))
        (lit none)))
    (pair "ts"
      (list
        (Opts declare "ts" "[-is] [STRFTIME]"
          "Pipe stdin to stdout, add timestamp to each line"
          (list
            (Opts text "\t-s\tTime since start")
            (Opts text "\t-i\tTime since previous line")
            (Opts hidden (Opts flag "-i" ""))
            (Opts hidden (Opts flag "-s" ""))))))
    (pair "run-parts"
      (list
        (Opts declare "run-parts" "[-a ARG]... [-u UMASK] [--reverse] [--test] [--exit-on-error] [--list] DIRECTORY"
          "Run a bunch of scripts in DIRECTORY"
          (list
            (Opts arg "-a" "ARG" "Pass ARG as argument to scripts")
            (Opts arg "-u" "UMASK" "Set UMASK before running scripts")
            (Opts flag "--reverse" "Reverse execution order")
            (Opts flag "--test" "Dry run")
            (Opts flag "--exit-on-error" "Exit if a script exits with non-zero")
            (Opts flag "--list" "Print names of matching files even if they are not executable")
            (Opts hidden (Opts arg "--arg" "" ""))
            (Opts hidden (Opts arg "--umask" "" ""))))))
    (pair "tree"
      (list
        (Opts declare "tree" "" ()
          (list)
          (pair (lit help) #f))
        (lit none)))
    (pair "time"
      (list
        (Opts declare "time" "[-vpa] [-o FILE] PROG ARGS"
          "Run PROG, display resource usage when it exits"
          (list
            (Opts flag "-v" "Verbose")
            (Opts flag "-p" "POSIX output format")
            (Opts arg "-f" "FMT" "Custom format")
            (Opts arg "-o" "FILE" "Write result to FILE")
            (Opts flag "-a" "Append (else overwrite)")))
        (lit leading)))
    (pair "base32"
      (list
        (Opts declare "base32" "[-d] [-w COL] [FILE]"
          "Base32 encode or decode FILE to standard output"
          (list
            (Opts flag "-d" "Decode data")
            (Opts arg "-w" "COL" "Wrap lines at COL (default 76, 0 disables)")
            (Opts hidden (Opts flag "-i" ""))))))
    (pair "crc32"
      (list
        (Opts declare "crc32" "FILE..."
          "Calculate CRC32 checksum of FILEs"
          (list))))
    (pair "ascii"
      (list
        (Opts declare "ascii" "" ()
          (list)
          (pair (lit help) #f))
        (lit none)))
    (pair "uuidgen"
      (list
        (Opts declare "uuidgen" ""
          "Generate a random UUID"
          (list
            (Opts hidden (Opts flag "-r" ""))))))
    (pair "uptime"
      (list
        (Opts declare "uptime" ""
          "Display the time since the last boot"
          (list
            (Opts hidden (Opts flag "-s" ""))))))
    (pair "free"
      (list
        (Opts declare "free" "[-bkmgh]"
          "Display free and used memory"
          (list
            (Opts hidden (Opts flag "-b" ""))
            (Opts hidden (Opts flag "-k" ""))
            (Opts hidden (Opts flag "-m" ""))
            (Opts hidden (Opts flag "-g" ""))
            (Opts hidden (Opts flag "-h" ""))))))
    ; busybox's usage names -T too; threads are not in the records ps reads,
    ; so -T is not accepted and not shown
    (pair "ps"
      (list
        (Opts declare "ps" "[-o COL1,COL2=HEADER]"
          "Show list of processes"
          (list
            (Opts arg "-o" "COL1,COL2=HEADER" "Select columns for display")
            (Opts hidden (Opts flag "-Z" ""))
            (Opts hidden (Opts flag "-a" ""))
            (Opts hidden (Opts flag "-A" ""))
            (Opts hidden (Opts flag "-d" ""))
            (Opts hidden (Opts flag "-e" ""))
            (Opts hidden (Opts flag "-f" ""))
            (Opts hidden (Opts flag "-l" ""))))))
    (pair "pidof"
      (list
        (Opts declare "pidof" "[-s] [-o PID] [NAME]..."
          "List PIDs of all processes with names that match NAMEs"
          (list
            (Opts flag "-s" "Show only one PID")
            (Opts arg "-o" "PID" "Omit given pid")
            (Opts text "\t\tUse %PPID to omit pid of pidof's parent")))))
    ; busybox's getopt32 string, "vlafxones:+P:+", is pgrep's and pkill's
    ; both; each help text names what it documents
    (pair "pgrep"
      (list
        (Opts declare "pgrep" "[-flanovx] [-s SID|-P PPID|PATTERN]"
          "Display process(es) selected by regex PATTERN"
          (list
            (Opts flag "-l" "Show command name too")
            (Opts flag "-a" "Show command line too")
            (Opts flag "-f" "Match against entire command line")
            (Opts flag "-n" "Show the newest process only")
            (Opts flag "-o" "Show the oldest process only")
            (Opts flag "-v" "Negate the match")
            (Opts flag "-x" "Match whole name (not substring)")
            (Opts text "\t-s\tMatch session ID (0 for current)")
            (Opts text "\t-P\tMatch parent process ID")
            (Opts hidden (Opts arg "-s" "" ""))
            (Opts hidden (Opts arg "-P" "" ""))
            (Opts hidden (Opts flag "-e" ""))))))
    (pair "pkill"
      (list
        (Opts declare "pkill" "[-l|-SIGNAL] [-xfvnoe] [-s SID|-P PPID|PATTERN]"
          "Send signal to processes selected by regex PATTERN"
          (list
            (Opts flag "-l" "List all signals")
            (Opts flag "-x" "Match whole name (not substring)")
            (Opts flag "-f" "Match against entire command line")
            (Opts arg "-s" "SID" "Match session ID (0 for current)")
            (Opts arg "-P" "PPID" "Match parent process ID")
            (Opts flag "-v" "Negate the match")
            (Opts flag "-n" "Signal the newest process only")
            (Opts flag "-o" "Signal the oldest process only")
            (Opts flag "-e" "Display name and PID of the process being killed")
            (Opts hidden (Opts flag "-a" ""))))
        (lit signal)))
    ; busybox's top help runs its keys and options on from the description
    ; with no blank line between, so it is all description and the options
    ; are declared hidden
    (pair "top"
      (list
        (Opts declare "top" "[-bmH] [-n COUNT] [-d SECONDS]"
          "Show a view of process activity in real time.\nRead the status of all processes from /proc each SECONDS\nand show a screenful of them.\nKeys:\n\tN/M/P/T: show CPU usage, sort by pid/mem/cpu/time\n\tS: show memory\n\tR: reverse sort\n\tH: toggle threads, 1: toggle SMP\n\tQ,^C: exit\nOptions:\n\t-b\tBatch mode\n\t-n N\tExit after N iterations\n\t-d SEC\tDelay between updates\n\t-m\tSame as 's' key\n\t-H\tShow threads"
          (list
            (Opts hidden (Opts flag "-b" ""))
            (Opts hidden (Opts arg "-n" "" ""))
            (Opts hidden (Opts arg "-d" "" ""))
            (Opts hidden (Opts flag "-m" ""))
            (Opts hidden (Opts flag "-H" ""))))))
    ; test and its spellings are an EXPRESSION, not an option list: the operators
    ; are declared so the parse knows them, and the applet parses the expression
    ; itself.  --help is an operand, as POSIX has it.
    (pair "test"
      (list
        (Opts declare "test" "" ()
          (append (list
            (Opts hidden (Opts flag "--help" "")))
            (%cu-hidden-flags %cu-test-operators))
          (pair (lit help) #f))
        (lit none)))
    (pair "["
      (list
        (Opts declare "[" "" ()
          (append (list
            (Opts hidden (Opts flag "--help" "")))
            (%cu-hidden-flags %cu-test-operators))
          (pair (lit help) #f))
        (lit none)))))

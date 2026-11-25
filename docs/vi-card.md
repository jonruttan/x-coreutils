# vi card

## Run

```sh
x -l coreutils -- vi FILE ...             # edit the files, one after another
x -l coreutils -- vi -R FILE              # read-only
x -l coreutils -- vi -c 'CMD' FILE        # a colon command first; -c may repeat
x -l coreutils -- vi -h                   # the usage; -H lists the features
sh tests/card-vi.sh 'KEYS' LINE ...       # a row of this page, see below
sh tests/card-vi.sh 'ddZZ' one two three -> two|three
```

| In a row             | Is                                                 |
|----------------------|----------------------------------------------------|
| `LINE ...`           | the file vi opens, a line each                     |
| `'KEYS'`             | the keys typed at it, the cursor starting at the top |
| `\033` `\r` `\026`   | Escape; Return; `^V`                               |
| `%%`                 | the key `%`                                        |
| after `->`           | the file the keys left, a `\|` between its lines   |
| `$EXINIT`, `~/.exrc` | colon commands run before the first file           |

## Modes

```sh
sh tests/card-vi.sh 'ihello \033ZZ' world -> hello world
sh tests/card-vi.sh 'A!\033ZZ' one -> one!
sh tests/card-vi.sh 'onew\033ZZ' one two -> one|new|two
sh tests/card-vi.sh 'Otop\033ZZ' one -> top|one
sh tests/card-vi.sh 'RXY\033ZZ' abcd -> XYcd
```

| Key                  | Does                                               |
|----------------------|----------------------------------------------------|
| `i` `a`              | insert before the cursor; after it                 |
| `I` `A`              | insert at the line's first character; at its end   |
| `o` `O`              | open a line below; above                           |
| `R` or Insert        | replace mode: typing overwrites                    |
| Escape               | back to command mode                               |
| `:`                  | a colon command, on the bottom line                |
| in insert: Backspace | delete the character before                        |
| in insert: `^V`      | the next key as it is                              |
| in insert: `^D`      | take an indent back, with `ai`                     |

## Moving

```sh
sh tests/card-vi.sh 'x$xZZ' abcde -> bcd
sh tests/card-vi.sh 'wxZZ' 'one two' -> one wo
sh tests/card-vi.sh 'fdDZZ' abcdef -> abc
sh tests/card-vi.sh 't,dwZZ' 'ab,cd ef' -> a,cd ef
sh tests/card-vi.sh 'Gdd1GxZZ' ab cd ef -> b|cd
sh tests/card-vi.sh '%%xZZ' '(a b)' -> (a b
sh tests/card-vi.sh '}ddZZ' a '' b -> a|b
sh tests/card-vi.sh "majd'aZZ" a b c d -> c|d
```

| Key                        | Moves to                                     |
|----------------------------|----------------------------------------------|
| `h` `j` `k` `l`, the arrows | a column or a row                           |
| `0` `^` `$`                | the line's start; first character; end       |
| `N\|`                      | column N                                     |
| Return `+` `-`             | the next line's first character; the previous |
| `w` `b` `e`                | a word on; back; a word's end                |
| `W` `B` `E`                | the same, a word running to a blank          |
| `fC` `FC` `tC` `TC`        | the character C on the line, or short of it  |
| `;` `,`                    | that again; the other way                    |
| `G` `NG` `gg`              | the last line; line N; the first line        |
| `H` `M` `L`                | the screen's top; middle; bottom             |
| `%`                        | the bracket matching this one                |
| `{` `}`                    | the paragraph before; after                  |
| `ma` `'a` `''`             | mark a; go to its line; back where you were  |
| a count before a key       | that many times: `3w` `5j`                   |

## Scrolling


| Key              | Scrolls                                                |
|------------------|--------------------------------------------------------|
| `^F` `^B`, the page keys | a page down; up                                |
| `^D` `^U`        | half a page down; up                                   |
| `^E` `^Y`        | a line down; up                                        |
| `z` Return, `z.` `z-` | this line to the top; the middle; the bottom      |

## Changing

```sh
sh tests/card-vi.sh 'dwZZ' 'one two three' -> two three
sh tests/card-vi.sh '2ddZZ' a b c d -> c|d
sh tests/card-vi.sh 'cwONE\033ZZ' 'one two' -> ONE two
sh tests/card-vi.sh 'jddpZZ' a b c -> a|c|b
sh tests/card-vi.sh 'yyPZZ' a b -> a|a|b
sh tests/card-vi.sh 'xpZZ' ab -> ba
sh tests/card-vi.sh 'rXlrYZZ' abc -> XYc
sh tests/card-vi.sh 'JZZ' one two -> one two
sh tests/card-vi.sh '~~ZZ' ab -> AB
sh tests/card-vi.sh '"ayyj"apZZ' a b -> a|b|a
sh tests/card-vi.sh 'dduZZ' a b -> a|b
sh tests/card-vi.sh 'xxxUZZ' abcdef -> abcdef
sh tests/card-vi.sh 'ddjpu.ZZ' a b c d -> b|c|d|a
```

| Key                  | Does                                               |
|----------------------|----------------------------------------------------|
| `d` `c` `y` and a motion | delete; change; yank what the motion covers    |
| `dd` `cc` `yy`       | the same for whole lines: `3dd`                    |
| `<` `>` and a motion, `<<` `>>` | shift lines left; right                 |
| `x` `X`              | delete the character here; before                  |
| `D` `C` `Y`          | delete to the line's end; change to it; yank the line |
| `s`                  | change one character                               |
| `rC`                 | replace the character with C                       |
| `J`                  | join the next line on                              |
| `~`                  | turn the character's case                          |
| `p` `P`              | put what was last deleted or yanked after; before  |
| `"a` before `d` `y` `p` | use the register a, `a` to `z`                  |
| `u` `U`              | undo; undo all on this line                        |
| `.`                  | repeat the last change                             |

## Searching

```sh
sh tests/card-vi.sh '/two\rxZZ' 'one two' -> one wo
sh tests/card-vi.sh '/b\rddnddZZ' a b c b d -> a|c|d
```

| Key                  | Does                                               |
|----------------------|----------------------------------------------------|
| `/TEXT` Return       | search down for TEXT                               |
| `?TEXT` Return       | search up                                          |
| `n` `N`              | search again; the other way                        |
| `:set ic`            | ignore case                                        |

## Colon commands

```sh
sh tests/card-vi.sh ':2\rddZZ' a b c -> a|c
sh tests/card-vi.sh ':%%s/a/X/g\r:wq\r' 'a a' 'b a' -> X X|b X
sh tests/card-vi.sh ':2,3d\r:x\r' a b c d -> a|d
sh tests/card-vi.sh ':1y\r:$\rpZZ' a b -> a|b|a
sh tests/card-vi.sh 'dd:q!\r' a b -> a|b
```

| Command                | Does                                             |
|------------------------|--------------------------------------------------|
| `:w` `:w FILE`         | write the file; to FILE                          |
| `:q` `:q!`             | quit; quit and lose the changes                  |
| `:wq` `:x` `ZZ`        | write and quit                                   |
| `ZQ`                   | quit and lose the changes                        |
| `:e FILE` `:e!`        | edit FILE; read this one again                   |
| `:r FILE`              | read FILE in below the line                      |
| `:f` `:f NAME`         | the file's name and size; name it                |
| `:n` `:prev` `:rew`    | the next file; the previous; the first           |
| `:wn`                  | write, then the next file                        |
| `:N`                   | go to line N                                     |
| `:d` `:y`              | delete lines; yank them                          |
| `:l` `:=`              | list lines, hidden bytes shown; the line number  |
| `:s/OLD/NEW/` `:s/OLD/NEW/g` | substitute once a line; every time         |
| `:!COMMAND`            | run a shell command                              |
| `:set` `:set OPTION`   | show the options; set one                        |
| `:version` `:features` | the version installed; the features              |

| Address              | Is                                                 |
|----------------------|----------------------------------------------------|
| `N` `.` `$`          | line N; this line; the last line                   |
| `+N` `-N`            | N lines on; back                                   |
| `'a`                 | the mark a's line                                  |
| `/TEXT/` `?TEXT?`    | the next line with TEXT; the one before            |
| `A,B`                | the lines from A to B                              |
| `A;B`                | the same, B counted from A                         |
| `%`                  | every line: `1,$`                                  |

## Options

```sh
sh tests/card-vi.sh ':set ai\ro  x\ry\033ZZ' a -> a|  x|  y
sh tests/card-vi.sh ':set ts=4 et\rA\tz\033ZZ' a -> a   z
```

| `:set`               | Does                                               |
|----------------------|----------------------------------------------------|
| `ai` `noai`          | autoindent: a new line takes the last one's indent |
| `et` `noet`          | expandtab: a Tab typed is spaces                   |
| `fl` `nofl`          | flash: the screen flashes where it would beep      |
| `ic` `noic`          | ignorecase: searches ignore case                   |
| `sm` `nosm`          | showmatch: a bracket typed shows its match         |
| `ts=N`               | tabstop: a tab is N columns                        |
| `sy` `nosy`          | syntax: the file in a theme's colours              |
| `syntax=NAME`        | the grammar to colour this file by                 |
| `theme=NAME`         | the colours `sy` draws in                          |

## Differs

| Here                                        | In another vi                 |
|---------------------------------------------|-------------------------------|
| it is busybox's vi: its keys and messages   | vim's, nvi's                  |
| `/TEXT` finds the text as it is             | a regular expression          |
| `/t.o` finds `t.o`, not `two`               | either                        |
| a command it lacks says `is not implemented` | runs                         |
| `v` selects nothing: there is no visual mode | vim's visual mode            |
| `:g/TEXT/d` changes nothing                 | deletes the matching lines    |
| `:r !COMMAND` reads nothing in              | the command's output          |
| `sy` `syntax=` `theme=` colour the file     | busybox's vi has no colour    |
| `:version` is x-coreutils's version         | the editor's own              |

## More

| Where                               | What                              |
|-------------------------------------|-----------------------------------|
| `x -l coreutils -- vi -H`           | the features                      |
| `README.md`, Known limits           | every key and command vi has      |
| `tests/specs/62-vi.spec.md` to `74` | each key, held to busybox's vi    |
| `tests/card-vi.sh`                  | types a row's keys at vi          |

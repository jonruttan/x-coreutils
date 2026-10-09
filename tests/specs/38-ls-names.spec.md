# @weight 1

`ls -l` lays its columns out at busybox's fixed widths: the inode in 7 (`-i`),
the blocks in 6 (`-s`), the link count in 4, the owner and the group each
left-aligned in 8, the size in 9 (7 under `-h`), and a device's major and minor
as `%4u, %3u`.  A wider value is never cut; it pushes the rest of its line over.
`-l` shows the owner and group by name, as the system names them, or the id
where the system has none; `-n` shows the ids.  Each id is looked up once in a
run.  The names are the system's own, from `/bin/ls -l`; the whole lines are
busybox's own output, from busybox ls in alpine.

## the fixtures

### a file of the user's own beside root's /etc/hosts, the system's names, and a reader

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-lsn && mkdir -p /tmp/x-cu-lsn && cd /tmp/x-cu-lsn && printf 'x\\n' > f && chmod 644 f && /bin/ls -ld f | awk '{print $3}' > .fo && /bin/ls -ld f | awk '{print $4}' > .fg && /bin/ls -ldn f | awk '{print $3}' > .fu && /bin/ls -ldn f | awk '{print $4}' > .fi && /bin/ls -ld /etc/hosts | awk '{print $3}' > .ho && /bin/ls -ld /etc/hosts | awk '{print $4}' > .hg && /bin/ls -ldn /etc/hosts | awk '{print $3}' > .hu && /bin/ls -ldn /etc/hosts | awk '{print $4}' > .hi")) (def ln (fn (_ n) (string-append "/tmp/x-cu-lsn/" n))) (def said (fn (_ n) (first (%cu-lines (file-read-all (ln n)))))) (def cap (fn (_ argv) (do (sys-dup2 1 9) (let ((fd (file-open-write (ln ".cap")))) (do (sys-dup2 fd 1) (cu-run argv "") (sys-dup2 9 1) (file-close fd) (%cu-lines (file-read-all (ln ".cap")))))))) (def padr (fn (self s w) (if (>= (byte-len s) w) s (self (string-append s " ") w)))) (display "made"))
```
---
    made

### entries made up to the stat busybox listed, dated 3 February 2001, and the cells of a listing

A device number is packed as the platform packs it, so it is made from its
major and minor here.

```cu
(do (def lsf-dev (fn (_ ma mi) (if os-darwin? (+ (* ma 16777216) mi) (+ (* ma 256) mi)))) (def lsf (fn (_ name ty mode ino blocks uid gid size rdev) (list name "/nowhere" (list (pair (lit file-type) ty) (pair (lit mode) mode) (pair (lit ino) ino) (pair (lit blocks) blocks) (pair (lit nlink) 1) (pair (lit uid) uid) (pair (lit gid) gid) (pair (lit size) size) (pair (lit rdev) rdev) (pair (lit mtime) 981173100))))) (def lsf-all (list (lsf "big" (lit file) 420 2 16 77777 88888 5000 0) (lsf "noname" (lit file) 420 3 0 77777 88888 0 0) (lsf "wide" (lit file) 420 4 0 1234567890 4321 0 0))) (def lsf-devs (list (lsf "null" (lit char) 438 5 0 0 0 0 (lsf-dev 1 3)) (lsf "sda" (lit block) 420 6 0 0 0 0 (lsf-dev 8 0)))) (def lsf-show (fn (_ flags es) (let ((o (%cu-opts "ls" flags))) (do (map (fn (_ e) (do (display (%ls-cell e o (date-now-unix))) (newline))) es) ())))) (display "made"))
```
---
    made

## the widths

### -n: links in 4, the ids left-aligned in 8, the size in 9; a wider id pushes the line over

```cu
(lsf-show (list "-ln") lsf-all)
```
---
```output
-rw-r--r--    1 77777    88888         5000 Feb  3  2001 big
-rw-r--r--    1 77777    88888            0 Feb  3  2001 noname
-rw-r--r--    1 1234567890 4321             0 Feb  3  2001 wide
```

### -i puts the inode in 7, -s the blocks in 6

```cu
(do (lsf-show (list "-lisn") lsf-all) (lsf-show (list "-is") lsf-all))
```
---
```output
      2      8 -rw-r--r--    1 77777    88888         5000 Feb  3  2001 big
      3      0 -rw-r--r--    1 77777    88888            0 Feb  3  2001 noname
      4      0 -rw-r--r--    1 1234567890 4321             0 Feb  3  2001 wide
      2      8 big
      3      0 noname
      4      0 wide
```

### -h puts the size in 7

```cu
(lsf-show (list "-lhn") lsf-all)
```
---
```output
-rw-r--r--    1 77777    88888       4.9K Feb  3  2001 big
-rw-r--r--    1 77777    88888          0 Feb  3  2001 noname
-rw-r--r--    1 1234567890 4321           0 Feb  3  2001 wide
```

### a device shows its major and minor where the size would be

```cu
(lsf-show (list "-ln") lsf-devs)
```
---
```output
crw-rw-rw-    1 0        0           1,   3 Feb  3  2001 null
brw-r--r--    1 0        0           8,   0 Feb  3  2001 sda
```

### an id with no name is shown as the id under -l too

```cu
(lsf-show (list "-l") (list (first (rest lsf-all))))
```
---
```output
-rw-r--r--    1 77777    88888            0 Feb  3  2001 noname
```

### the system's /dev/null, with the major and minor the system gives it

Darwin's ls shows a device number in hex, so there its stat says the two
halves; elsewhere ls says them as `MAJOR, MINOR`.

```cu
(let ((ws (%cu-words-line (first (%cu-lines (file-read-all (do (proc-run (list "/bin/sh" "-c" (if os-darwin? "stat -f '%Hr %Lr' /dev/null > /tmp/x-cu-lsn/.dn" "/bin/ls -l /dev/null | awk '{print $5, $6}' | tr -d , > /tmp/x-cu-lsn/.dn"))) "/tmp/x-cu-lsn/.dn"))))))) (display (Str8 includes? (string-concat (list (%cu-pad-left (first ws) 4) ", " (%cu-pad-left (%cu-nth 1 ws) 3) " ")) (first (cap (list "ls" "-l" "/dev/null"))))))
```
---
    #t

## names

### -l shows the owner and the group by name

```cu
(let ((ws (%cu-words-line (first (cap (list "ls" "-l" (ln "f")))))) (hs (%cu-words-line (first (cap (list "ls" "-l" "/etc/hosts")))))) (display (list (string=? (%cu-nth 2 ws) (said ".fo")) (string=? (%cu-nth 3 ws) (said ".fg")) (%cu-nth 2 hs))))
```
---
    (#t #t root)

### a name is left-aligned in 8, whatever the others in the listing

```cu
(let ((ls (cap (list "ls" "-l" "/etc/hosts" (ln "f"))))) (display (list (Str8 includes? (string-concat (list " " (padr (said ".ho") 8) " " (padr (said ".hg") 8) " ")) (first ls)) (Str8 includes? (string-concat (list " " (padr (said ".fo") 8) " " (padr (said ".fg") 8) " ")) (first (rest ls))))))
```
---
    (#t #t)

## ids

### -n shows the ids, left-aligned in 8

```cu
(let ((ls (cap (list "ls" "-ln" "/etc/hosts" (ln "f"))))) (display (list (Str8 includes? (string-concat (list " " (padr (said ".hu") 8) " " (padr (said ".hi") 8) " ")) (first ls)) (Str8 includes? (string-concat (list " " (padr (said ".fu") 8) " " (padr (said ".fi") 8) " ")) (first (rest ls))))))
```
---
    (#t #t)

### each id is looked up once in a run

```cu
(do (set-first! %ls-user-cell ()) (cap (list "ls" "-l" (ln "f") "/etc/hosts" (ln "f") "/etc/hosts")) (display (= (length (first %ls-user-cell)) (if (string=? (said ".fu") (said ".hu")) 1 2))))
```
---
    #t

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-lsn")) (display "clean"))
```
---
    clean

# @weight 1

`ls -l` shows a file's owner and group by name, as the system names them,
left-aligned to the widest in the listing; `-n` shows the ids, right-aligned,
and so does `-l` for an id the system has no name for.  Each id is looked up
once in a run.  The expected names are the system's own, from `/bin/ls -l`;
the layout is GNU ls's.

## the fixtures

### a file of the user's own beside root's /etc/hosts, the system's names, and a reader

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-lsn && mkdir -p /tmp/x-cu-lsn && cd /tmp/x-cu-lsn && printf 'x\\n' > f && chmod 644 f && /bin/ls -ld f | awk '{print $3}' > .fo && /bin/ls -ld f | awk '{print $4}' > .fg && /bin/ls -ldn f | awk '{print $3}' > .fu && /bin/ls -ldn f | awk '{print $4}' > .fi && /bin/ls -ld /etc/hosts | awk '{print $3}' > .ho && /bin/ls -ld /etc/hosts | awk '{print $4}' > .hg && /bin/ls -ldn /etc/hosts | awk '{print $3}' > .hu && /bin/ls -ldn /etc/hosts | awk '{print $4}' > .hi")) (def ln (fn (_ n) (string-append "/tmp/x-cu-lsn/" n))) (def said (fn (_ n) (first (%cu-lines (file-read-all (ln n)))))) (def cap (fn (_ argv) (do (sys-dup2 1 9) (let ((fd (file-open-write (ln ".cap")))) (do (sys-dup2 fd 1) (cu-run argv "") (sys-dup2 9 1) (file-close fd) (%cu-lines (file-read-all (ln ".cap")))))))) (def padr (fn (self s w) (if (>= (byte-len s) w) s (self (string-append s " ") w)))) (def padl (fn (self s w) (if (>= (byte-len s) w) s (self (string-append " " s) w)))) (def wider (fn (_ a b) (if (> (byte-len a) (byte-len b)) (byte-len a) (byte-len b)))) (display "made"))
```
---
    made

## names

### -l shows the owner and the group by name

```cu
(let ((ws (%cu-words-line (first (cap (list "ls" "-l" (ln "f")))))) (hs (%cu-words-line (first (cap (list "ls" "-l" "/etc/hosts")))))) (display (list (string=? (%cu-nth 2 ws) (said ".fo")) (string=? (%cu-nth 3 ws) (said ".fg")) (%cu-nth 2 hs))))
```
---
    (#t #t root)

### a name is left-aligned to the widest in the listing

```cu
(let ((ls (cap (list "ls" "-l" "/etc/hosts" (ln "f")))) (wo (wider (said ".ho") (said ".fo"))) (wg (wider (said ".hg") (said ".fg")))) (display (list (Str8 includes? (string-concat (list " " (padr (said ".ho") wo) " " (padr (said ".hg") wg) " ")) (first ls)) (Str8 includes? (string-concat (list " " (padr (said ".fo") wo) " " (padr (said ".fg") wg) " ")) (first (rest ls))))))
```
---
    (#t #t)

## ids

### -n shows the ids, right-aligned

```cu
(let ((ls (cap (list "ls" "-ln" "/etc/hosts" (ln "f")))) (wo (wider (said ".hu") (said ".fu"))) (wg (wider (said ".hi") (said ".fi")))) (display (list (Str8 includes? (string-concat (list " " (padl (said ".hu") wo) " " (padl (said ".hi") wg) " ")) (first ls)) (Str8 includes? (string-concat (list " " (padl (said ".fu") wo) " " (padl (said ".fi") wg) " ")) (first (rest ls))))))
```
---
    (#t #t)

### an id with no name is shown as the id, right-aligned, even under -l

```cu
(display (list (%ls-id-text 99999 #f %ls-user-cell sys-user-name) (%ls-id-column (%ls-id-text 99999 #f %ls-user-cell sys-user-name) 7) (%ls-id-column (pair #t "ab") 4)))
```
---
```output
((#f . 99999)   99999 ab  )
```

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

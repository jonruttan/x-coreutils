# @weight 2

What cp does with a symlink is the last of -P, -H and -L, with -a saying -P:
-P copies the link as a link, -L copies what it points at, and -H follows one
named on the command line only.  Told nothing, cp follows a link named on the
command line and copies one met on a walk as a link.  The expected text and
statuses are GNU cp's for the same trees.

## the fixtures

### a tree of links, and readers for what came out

`src` holds `file`, `sub/inner`, `lk -> file`, `dlk -> sub` and a
`dead -> nowhere` that points at nothing; `clk -> src` names the tree itself.
`shape` says what a path turned out to be, and `cp` runs the applet with
stdout and stderr parked on files.

```cu
(do (def ch (fn (_ n) (string-append "/tmp/x-cu-cpl/" n))) (def mk (fn (_) (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-cpl && mkdir -p /tmp/x-cu-cpl/src/sub /tmp/x-cu-cpl/out && printf 'hi\\n' > /tmp/x-cu-cpl/src/file && : > /tmp/x-cu-cpl/src/sub/inner && cd /tmp/x-cu-cpl/src && ln -s file lk && ln -s sub dlk && ln -s nowhere dead && cd /tmp/x-cu-cpl && ln -s src clk")))) (mk) (def body (fn (_ p) (let ((t (file-read-all (ch p)))) (if (= (byte-len t) 0) "" (first (%cu-lines t)))))) (def shape (fn (_ p) (let ((k (file-lstat-kind (ch p)))) (match ((eq? k (lit link)) (string-append "-> " (file-readlink (ch p)))) ((eq? k (lit dir)) "dir") ((eq? k (lit none)) "missing") (#t (string-append "file [" (body p) "]")))))) (def shapes (fn (_ ps) (display (string-append (%cu-join-with (map (fn (_ p) (string-concat (list p " " (shape p)))) ps) ", ") "\n")))) (def cp (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (ch ".out"))) (ee (file-open-write (ch ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def cp-st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (file-read-all (ch ".out"))) (display (file-read-all (ch ".err"))) (display "status ") (display cp-st) (newline)))))) (display "made"))
```
---
    made

## what -R does with a link it meets

### told nothing, it copies the link as a link, the one pointing nowhere too

```cu
(do (mk) (cp (list "cp" "-R" (ch "src") (ch "out/copy"))) (shapes (list "out/copy/file" "out/copy/lk" "out/copy/dlk" "out/copy/dead")))
```
---
```output
status 0
out/copy/file file [hi], out/copy/lk -> file, out/copy/dlk -> sub, out/copy/dead -> nowhere
```

### -P says the same

```cu
(do (mk) (cp (list "cp" "-R" "-P" (ch "src") (ch "out/copy"))) (shapes (list "out/copy/lk" "out/copy/dlk" "out/copy/dead")))
```
---
```output
status 0
out/copy/lk -> file, out/copy/dlk -> sub, out/copy/dead -> nowhere
```

### -L copies what each link points at, and cannot copy one pointing nowhere

```cu
(do (mk) (cp (list "cp" "-R" "-L" (ch "src") (ch "out/copy"))) (shapes (list "out/copy/lk" "out/copy/dlk" "out/copy/dlk/inner" "out/copy/dead")))
```
---
```output
cp: cannot stat '/tmp/x-cu-cpl/src/dead': No such file or directory
status 1
out/copy/lk file [hi], out/copy/dlk dir, out/copy/dlk/inner file [], out/copy/dead missing
```

### -H leaves a link met on the walk as a link

```cu
(do (mk) (cp (list "cp" "-R" "-H" (ch "src") (ch "out/copy"))) (shapes (list "out/copy/lk" "out/copy/dlk")))
```
---
```output
status 0
out/copy/lk -> file, out/copy/dlk -> sub
```

## what it does with a link it was given

### told nothing, -R copies the link itself

```cu
(do (mk) (cp (list "cp" "-R" (ch "clk") (ch "out/copy"))) (shapes (list "out/copy")))
```
---
```output
status 0
out/copy -> src
```

### -H and -L copy what it points at

```cu
(do (mk) (cp (list "cp" "-R" "-H" (ch "clk") (ch "out/copy"))) (shapes (list "out/copy" "out/copy/file")) (mk) (cp (list "cp" "-R" "-L" (ch "clk") (ch "out/two"))) (shapes (list "out/two" "out/two/file")))
```
---
```output
status 0
out/copy dir, out/copy/file file [hi]
cp: cannot stat '/tmp/x-cu-cpl/clk/dead': No such file or directory
status 1
out/two dir, out/two/file file [hi]
```

### without -R a link is followed, and -P keeps it a link

```cu
(do (mk) (cp (list "cp" (ch "src/lk") (ch "out/one"))) (shapes (list "out/one")) (mk) (cp (list "cp" "-P" (ch "src/lk") (ch "out/one"))) (shapes (list "out/one")))
```
---
```output
status 0
out/one file [hi]
status 0
out/one -> file
```

### the last of the three wins, -a taking its turn among them

```cu
(do (mk) (cp (list "cp" "-a" "-L" (ch "src") (ch "out/copy"))) (shapes (list "out/copy/lk")) (mk) (cp (list "cp" "-L" "-a" (ch "src") (ch "out/two"))) (shapes (list "out/two/lk")))
```
---
```output
cp: cannot stat '/tmp/x-cu-cpl/src/dead': No such file or directory
status 1
out/copy/lk file [hi]
status 0
out/two/lk -> file
```

## writing a link where a name is taken

### a link copied over a name that is taken replaces it

```cu
(do (mk) (proc-run (list "/bin/sh" "-c" ": > /tmp/x-cu-cpl/out/one")) (cp (list "cp" "-P" (ch "src/lk") (ch "out/one"))) (shapes (list "out/one")) (proc-run (list "/bin/sh" "-c" "rm -f /tmp/x-cu-cpl/out/one && ln -s elsewhere /tmp/x-cu-cpl/out/one")) (cp (list "cp" "-P" (ch "src/lk") (ch "out/one"))) (shapes (list "out/one")))
```
---
```output
status 0
out/one -> file
status 0
out/one -> file
```

### a link cp is asked to make is refused where the name is taken, and -f drops it first

```cu
(do (mk) (proc-run (list "/bin/sh" "-c" ": > /tmp/x-cu-cpl/out/one")) (cp (list "cp" "-s" (ch "src/file") (ch "out/one"))) (shapes (list "out/one")) (cp (list "cp" "-f" "-s" (ch "src/file") (ch "out/one"))) (shapes (list "out/one")))
```
---
```output
cp: cannot create symbolic link '/tmp/x-cu-cpl/out/one' to '/tmp/x-cu-cpl/src/file': File exists
status 1
out/one file []
status 0
out/one -> /tmp/x-cu-cpl/src/file
```

### a hard link cp is asked to make, where the name is taken

```cu
(do (mk) (proc-run (list "/bin/sh" "-c" ": > /tmp/x-cu-cpl/out/one")) (cp (list "cp" "-l" (ch "src/file") (ch "out/one"))))
```
---
```output
cp: cannot create hard link '/tmp/x-cu-cpl/out/one' to '/tmp/x-cu-cpl/src/file': File exists
status 1
```

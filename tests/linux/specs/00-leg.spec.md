# @weight 1

The Linux leg's own check: these specs run as root on Linux, in the
container tests/linux/run.sh starts, and nowhere else.

## the leg

### the kernel is Linux

```cu
(cu-run (list "uname" "-s") "")
```
---
```output
Linux
0
```

### the specs run as root

```cu
(cu-run (list "id" "-u") "")
```
---
```output
0
0
```

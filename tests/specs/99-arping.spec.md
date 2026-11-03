# @weight 1

busybox's arping (networking/arping.c) opens its AF_PACKET socket before it
reads its options, so a run without one ends there.  AF_PACKET is Linux's;
here the socket is refused as Linux refuses a family it has not, and the
replies are tested as root in the Linux leg.  A `|` marks the end of each
line written to standard output.

## the fixture

### a run of arping, what it writes and its status

```cu
(do (def ap-f (fn (_ n) (string-append "/tmp/x-cu-ap." n)))
    (def ap-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (ap-f "out"))) (ee (file-open-write (ap-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (Str8 replace "\n" "|\n" (file-read-all (ap-f "out"))) "stderr:\n"
                                              (file-read-all (ap-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the socket

### refused before the options are read, the usage among them

```cu
(do (ap-show (list "arping"))
    (ap-show (list "arping" "-c" "x" "1.2.3.4"))
    (ap-show (list "arping" "-c" "1" "1.2.3.4")))
```
---
```output
stderr:
arping: socket(AF_PACKET,2,0): Address family not supported by protocol family
status 1
stderr:
arping: socket(AF_PACKET,2,0): Address family not supported by protocol family
status 1
stderr:
arping: socket(AF_PACKET,2,0): Address family not supported by protocol family
status 1
```

; # x-coreutils -- the small tools, as applets
;
; ## run.x -- THE entry
;
; @description sort, tr, cut, join, comm, uniq, head, tail, cat, wc,
;   basename, dirname, cp, rm, mkdir, sha256sum -- one bundle, many
;   applets, organized like busybox.  Built second in the self-hosting arc.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Usage:
;   x -l coreutils -- APPLET [args]...
(import cu/base cu-main cu-repl-print cu-version)

(set! %lang-name "COREUTILS")
(set! %lang-version cu-version)
(set! %repl-prompt "cu> ")
(set! %repl-print cu-repl-print)

(let ((ops (rest (Sys args (lit program)))))
  (unless (null? ops) (cu-main ops)))

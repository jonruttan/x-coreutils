; # x-coreutils -- the small tools, as applets
;
; ## run.x -- THE entry
;
; @description sort, tr, cut, join, comm, uniq, head, tail, cat, wc,
;   basename, dirname, cp, rm, mkdir, sha256sum -- one bundle, many
;   applets, the busybox shape.  The self-hosting arc's second tier.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Usage:
;   x -l coreutils -- APPLET [args]...
(import cu/base)

(set! %lang-name "COREUTILS")
(set! %lang-version cu-version)
(set! %repl-prompt "cu> ")
(set! %repl-print %cu-repl-print)

(unless (null? (cu-argv args))
  (cu-main args))

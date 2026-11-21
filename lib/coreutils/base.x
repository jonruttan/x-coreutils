; # x-coreutils -- the small tools, as applets
;
; ## lib/coreutils/base.x -- the tool chest, assembled
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Importing coreutils/applets loads every applet's module, each loading the modules
; it imports.  The entry and the spec harness import what they name from here.

(module coreutils/base)

(import coreutils/applets)
(import coreutils/cli cu-main cu-run)
(import coreutils/sha256 cu-sha256)

(def cu-version "0.1.0")

(def cu-repl-print
  (fn (_ result)
    (unless (null? result) (write result))
    (newline)))

(provide coreutils/base cu-version cu-run cu-main cu-sha256 cu-repl-print)

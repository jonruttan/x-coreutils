; # x-coreutils -- the small tools, as applets
;
; ## cu/base.x -- the tool chest, assembled
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(import cu/prims)

(provide cu/base cu-version cu-run cu-argv cu-main cu-sha256
  %cu-repl-print)

(def cu-version "0.1.0")

(def %cu-repl-print
  (fn (_ result)
    (unless (null? result) (write result))
    (newline)))

(include-once "./text.x")
(include-once "./trcut.x")
(include-once "./fs.x")
(include-once "./sha256.x")
(include-once "./hash.x")
(include-once "./sha512.x")
(include-once "./text3.x")
(include-once "./encode.x")
(include-once "./expr.x")
(include-once "./text2.x")
(include-once "./fs2.x")
(include-once "./sys2.x")
(include-once "./fs3.x")
(include-once "./diff.x")
(include-once "./cli.x")

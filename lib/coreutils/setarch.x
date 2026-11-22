; # x-coreutils -- the small tools, as applets
;
; ## lib/coreutils/setarch.x -- setarch, linux32, linux64: a program under a personality
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; util-linux/setarch.c: the personality named by the applet -- or, for
; setarch, by a first word that starts "linux", which then names the applet
; in its messages -- is PER_LINUX for linux64 and PER_LINUX32 for linux32,
; with ADDR_NO_RANDOMIZE under -R.  personality(2) sets it, and the program
; runs in this process's place, /bin/sh where none is named.

(module coreutils/setarch)

(import coreutils/cli cu-opts cu-usage)
(import coreutils/inetd in-call)
(import coreutils/prims bit-or byte-at byte-len cu-execvp-or-die cu-hexs
  cu-libc-sym cu-ptr-call file-write libc-strerror string-append string=?
  substring)

(def %sa-per-linux 0)
(def %sa-per-linux32 8)
(def %sa-addr-no-randomize 0x0040000)

(def %sa-linux? (fn (_ s) (if (>= (byte-len s) 5) (string=? (substring s 0 5) "linux") #f)))

; the personality NAME's sixth byte picks, or nil
(def %sa-personality
  (fn (_ name)
    (def c (if (> (byte-len name) 5) (byte-at name 5) 0))
    (match ((= c #\6) %sa-per-linux) ((= c #\3) %sa-per-linux32) (#t ()))))

; setarch without a personality shows its usage; another name no applet has
; shows none, as busybox's bb_show_usage finds no applet by it and exits 1.
; The options are linux32's or linux64's, by the byte that picks.
(def %sa-run
  (fn (_ name argv)
    (def base (%sa-personality name))
    (match
      ((not (null? base))
        (%sa-exec name (if (= base %sa-per-linux) "linux64" "linux32") base argv))
      ((string=? name "setarch") (cu-usage name))
      (#t 1))))

(def %sa-exec
  (fn (_ name decl base argv)
    (let ((o (cu-opts decl argv)))
      (def pers (if (Opts on? o "-R") (bit-or base %sa-addr-no-randomize) base))
      (if (< (in-call (cu-ptr-call (cu-libc-sym "personality") pers)) 0)
        (do (file-write 2 (%str-concat (list name ": personality(0x" (cu-hexs pers) "): "
                                             (libc-strerror (Err errno-of -1)) "\n")))
            1)
        (let ((prog (Opts operands o)))
          (cu-execvp-or-die name (if (null? prog) (list "/bin/sh") prog)))))))

; setarch LINUX32 ... runs as linux32, by that name
(def cu-setarch
  (fn (_ argv stdin-thunk)
    (if (if (pair? argv) (%sa-linux? (first argv)) #f)
      (%sa-run (first argv) (rest argv))
      (%sa-run "setarch" argv))))

(def cu-linux32 (fn (_ argv stdin-thunk) (%sa-run "linux32" argv)))
(def cu-linux64 (fn (_ argv stdin-thunk) (%sa-run "linux64" argv)))

(provide coreutils/setarch cu-linux32 cu-linux64 cu-setarch)

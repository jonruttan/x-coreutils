; # x-coreutils -- the small tools, as applets
;
; ## cu/cli.x -- the applet table and the command line
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;   x -l coreutils -- APPLET [args]...
;
; cu-run is the pure-ish core the specs drive: (cu-run ARGV INPUT) with
; INPUT standing for stdin.  cu-main reads the real stdin lazily and
; caches it, so an applet that never asks never blocks.

(def %cu-applets
  (list
    (pair "cat" %cu-cat)
    (pair "sort" %cu-sort)
    (pair "uniq" %cu-uniq)
    (pair "head" %cu-head)
    (pair "tail" %cu-tail)
    (pair "wc" %cu-wc)
    (pair "comm" %cu-comm)
    (pair "join" %cu-join)
    (pair "tr" %cu-tr)
    (pair "cut" %cu-cut)
    (pair "basename" %cu-basename)
    (pair "dirname" %cu-dirname)
    (pair "cp" %cu-cp)
    (pair "rm" %cu-rm)
    (pair "mkdir" %cu-mkdir)
    (pair "sha256sum" %cu-sha256sum)))

(def %cu-find-applet
  (fn (_ name)
    (def go
      (fn (self es)
        (if (null? es) ()
          (if (string=? (first (first es)) name)
            (rest (first es))
            (self (rest es))))))
    (go %cu-applets)))

(def cu-run
  (fn (_ argv input)
    (if (null? argv)
      (do (file-write 2 "usage: coreutils APPLET [args]...\n") 2)
      (let ((h (%cu-find-applet (first argv))))
        (if (null? h)
          (do (file-write 2
                (string-append "coreutils: no such applet: "
                  (string-append (first argv) "\n")))
              2)
          (h (rest argv) (fn (_) input)))))))

(def %cu-cli-engine-flag?
  (fn (_ s)
    (if (string=? s "--quiet") #t
      (if (string=? s "--batch") #t
        (if (string=? s "--no-color") #t (string=? s "--verbose"))))))

(def cu-argv
  (fn (_ raw)
    (def ops
      (filter (fn (_ a) (not (%cu-cli-engine-flag? a)))
        (if (pair? raw) (rest raw) ())))
    (if (if (pair? ops) (string=? (first ops) "--") #f)
      (rest ops)
      ops)))

(def cu-main
  (fn (_ raw-args)
    (def argv (cu-argv raw-args))
    (def cache (list ()))
    (def stdin-thunk
      (fn (_)
        (if (null? (first cache))
          (do (set-first! cache (list (cu-stdin!)))
              (first (first cache)))
          (first (first cache)))))
    (if (null? argv)
      (sys-exit (cu-run argv ""))
      (let ((h (%cu-find-applet (first argv))))
        (if (null? h)
          (sys-exit (cu-run argv ""))
          (sys-exit (h (rest argv) stdin-thunk)))))))

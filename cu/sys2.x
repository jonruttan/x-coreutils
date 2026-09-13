; # x-coreutils -- the small tools, as applets
;
; ## cu/sys2.x -- the busybox expansion, system half
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; true false env printenv sleep date which xargs test.

(def %cu-true (fn (_ argv stdin-thunk) 0))
(def %cu-false (fn (_ argv stdin-thunk) 1))

(def %cu-env
  (fn (_ argv stdin-thunk)
    (do (%cu-print-lines (sys-environ)) 0)))

(def %cu-printenv
  (fn (_ argv stdin-thunk)
    (if (null? argv)
      (%cu-env argv stdin-thunk)
      (let ((v (sys-getenv (first argv))))
        (if (null? v) 1
          (do (display (string-append v "\n")) 0))))))

(def %cu-sleep
  (fn (_ argv stdin-thunk)
    (do (sys-sleep (%cu-num-prefix (first argv))) 0)))

; date: ISO-8601 UTC by default (a recorded divergence from the locale
; format), +%s for unix seconds
(def %cu-date
  (fn (_ argv stdin-thunk)
    (if (if (pair? argv) (string=? (first argv) "+%s") #f)
      (do (display (string-append (%cu-int->str (date-now-unix)) "\n"))
          0)
      (do (display (string-append (date-now-iso) "\n")) 0))))

; which: the PATH walk; existence is the test (there is no access(X_OK)
; door -- the recorded divergence)
(def %cu-which
  (fn (_ argv stdin-thunk)
    (def path (sys-getenv "PATH"))
    (def dirs (if (null? path) () (%cu-split-byte path 58)))  ; :
    (def go
      (fn (self ds name)
        (if (null? ds) ()
          (let ((cand (string-append (first ds)
                        (string-append "/" name))))
            (if (file-exists? cand) cand (self (rest ds) name))))))
    (def each
      (fn (self os st)
        (if (null? os) st
          (let ((hit (go dirs (first os))))
            (if (null? hit)
              (self (rest os) 1)
              (do (display (string-append hit "\n"))
                  (self (rest os) st)))))))
    (each argv 0)))

; xargs: stdin words append to the command (default echo); -n N batches
(def %cu-xargs
  (fn (_ argv stdin-thunk)
    (def n
      (if (if (pair? argv) (string=? (first argv) "-n") #f)
        (%cu-num-prefix (first (rest argv)))
        0))
    (def cmd0 (if (> n 0) (rest (rest argv)) argv))
    (def cmd (if (null? cmd0) (list "echo") cmd0))
    (def words (%cu-words-line (%cu-join-with
                                 (%cu-lines (stdin-thunk)) " ")))
    (def run!
      (fn (_ ws) (proc-run (append cmd ws))))
    (if (= n 0)
      (if (null? words) 0 (run! words))
      (let ((go (fn (self ws st)
                  (if (null? ws) st
                    (let ((take (let ((go2 (fn (self2 l k acc)
                                             (if (if (= k 0) #t (null? l))
                                               (pair (reverse acc) l)
                                               (self2 (rest l) (- k 1)
                                                 (pair (first l) acc))))))
                                  (go2 ws n ()))))
                      (let ((st2 (run! (first take))))
                        (self (rest take)
                          (if (> st2 st) st2 st))))))))
        (go words 0)))))

; test, [ and [[ moved to cu/test.x, which parses the whole grammar.

(def %cu-last
  (fn (self l) (if (null? (rest l)) (first l) (self (rest l)))))
(def %cu-drop-last
  (fn (self l)
    (if (null? (rest l)) ()
      (pair (first l) (self (rest l))))))

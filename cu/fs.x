; # x-coreutils -- the small tools, as applets
;
; ## cu/fs.x -- cp, rm, mkdir
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(def %cu-cp
  (fn (_ argv stdin-thunk)
    (if (if (pair? argv) (pair? (rest argv)) #f)
      (do (file-write-all (first (rest argv))
            (file-read-all (first argv)))
          0)
      (do (file-write 2 "cp: usage: cp SRC DST\n") 1))))

(def %cu-rm
  (fn (_ argv stdin-thunk)
    (def force? (if (pair? argv) (string=? (first argv) "-f") #f))
    (def ops (if force? (rest argv) argv))
    (def go
      (fn (self os st)
        (if (null? os) st
          (if (file-exists? (first os))
            (do (file-unlink (first os)) (self (rest os) st))
            (if force?
              (self (rest os) st)
              (do (file-write 2
                    (string-append "rm: no such file: "
                      (string-append (first os) "\n")))
                  (self (rest os) 1)))))))
    (go ops 0)))

; -p creates parents and forgives existing
(def %cu-mkdir
  (fn (_ argv stdin-thunk)
    (def p? (if (pair? argv) (string=? (first argv) "-p") #f))
    (def ops (if p? (rest argv) argv))
    (def parents!
      (fn (_ path)
        (def end (byte-len path))
        (def go
          (fn (self i)
            (if (>= i end)
              (if (file-exists? path) () (file-mkdir path))
              (if (if (= (byte-at path i) 47) (> i 0) #f)
                (do (let ((pre (substring path 0 i)))
                      (if (file-exists? pre) () (file-mkdir pre)))
                    (self (+ i 1)))
                (self (+ i 1))))))
        (go 0)))
    (def go
      (fn (self os st)
        (if (null? os) st
          (if p?
            (do (parents! (first os)) (self (rest os) st))
            (if (file-exists? (first os))
              (do (file-write 2
                    (string-append "mkdir: exists: "
                      (string-append (first os) "\n")))
                  (self (rest os) 1))
              (do (file-mkdir (first os)) (self (rest os) st)))))))
    (go ops 0)))

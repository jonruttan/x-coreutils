; # x-coreutils -- the small tools, as applets
;
; ## cu/tree.x -- tree
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's tree (miscutils/tree.c): each directory given (`.` when none),
; its entries in byte order under it, drawn with the box characters busybox
; draws in UTF-8.  Names starting with a dot are passed over, though one
; sorted last still keeps the last shown entry from its corner; a link shows
; where it points and is not followed; a directory that will not open is
; `NAME [error opening dir]`.  At the end, the directories and files counted.
;
; busybox goes into each directory and comes back up with `..`, so after a
; directory given as a/b it is in a, not where it started, and an operand
; after it is looked for from there.  The walk keeps the same place by its
; path, the way chdir would.

(def %tree-utf8 (fn (_ bs) (bytes->str bs)))
; the box characters: a bar, a branch, a corner, and the line between
(def %tree-bar (string-append (%tree-utf8 (list 226 148 130)) "   "))
(def %tree-mid
  (string-append (%tree-utf8 (list 226 148 156 226 148 128 226 148 128)) " "))
(def %tree-end
  (string-append (%tree-utf8 (list 226 148 148 226 148 128 226 148 128)) " "))

; NAME from the place HERE, as chdir would take it
(def %tree-at
  (fn (_ here name)
    (if (if (> (byte-len name) 0) (= (byte-at name 0) #\/) #f) name
      (string-concat (list here "/" name)))))

; The directory NAME, from HERE, under PREFIX: its name, then its entries.
; COUNTS is (DIRS FILES) in a cell list.  Answers the place the walk is in
; after it: NAME's parent by way of `..`, or HERE where it would not open.
(def %tree-print
  (fn (self counts here name prefix)
    (def path (%tree-at here name))
    (def listed (guard (e (lit fail)) (file-list-dir path)))
    (if (eq? listed (lit fail))
      (do (file-write 1 (string-append name " [error opening dir]\n")) here)
      (let ((entries (%cu-msort (pair "." (pair ".." listed)) %cu-str<)))
        (def each
          (fn (each-self es)
            (if (null? es) ()
              (let ((d (first es)))
                (do (if (= (byte-at d 0) #\.) ()
                      (%tree-entry self counts path d
                        (string-append prefix (if (null? (rest es)) %tree-end %tree-mid))
                        (string-append prefix (if (null? (rest es)) "    " %tree-bar))))
                    (%cu-sweep-tick! %cu-sweep-lines)
                    (each-self (rest es)))))))
        (do (file-write 1 (string-append name "\n"))
            (each entries)
            (string-append path "/.."))))))

; one entry D of the directory at PATH, its line started by LINE: a link and
; where it points, a directory and what is in it, or a file
(def %tree-entry
  (fn (_ walk counts path d line under)
    (def full (string-append path (string-append "/" d)))
    (def type (file-lstat-file-type full))
    (do (file-write 1 line)
        (match
          ((eq? type (lit link))
            (do (file-write 1 (string-concat (list d " -> " (file-readlink full) "\n")))
                (%set-first! (rest counts) (+ (first (rest counts)) 1))))
          ((eq? type (lit dir))
            (do (walk counts path d under)
                (%set-first! counts (+ (first counts) 1))))
          (#t
            (do (file-write 1 (string-append d "\n"))
                (%set-first! (rest counts) (+ (first (rest counts)) 1))))))))

(def %cu-tree
  (fn (_ argv stdin-thunk)
    (def counts (list 0 0))
    (def go
      (fn (self names here)
        (if (null? names) ()
          (self (rest names) (%tree-print counts here (first names) "")))))
    (do (go (if (null? argv) (list ".") argv) ".")
        (file-write 1
          (string-concat
            (list "\n" (%cu-int->str (first counts)) " directories, "
                  (%cu-int->str (first (rest counts))) " files\n")))
        0)))

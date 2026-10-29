; # x-coreutils -- the small tools, as applets
;
; ## cu/pmap.x -- pmap
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's pmap (procps/pmap.c), its 64-bit layout, over Host's region
; records through cu/prims.x.  A region's size is its length in KiB, as
; busybox shifts the address span; PSS, dirty and swap are smaps' KiB, and
; Darwin, which keeps no PSS, shows 0 there.  A pid with no process answers
; 42 and prints nothing, as busybox's failed read of its cmdline does; one
; whose regions the kernel will not give prints its line and answers 42.

; the line busybox's read_cmdline makes of ARGS for pmap: the arguments joined
; by spaces, less the empty ones at the end (cmdline's trailing NULs), a
; control byte as ?, cut to its 4095-byte buffer
(module cu/pmap)

(import cu/cli cu-opts cu-usage)
(import cu/prims byte-len cu-heap-collect cu-hexs cu-int->str host-args
  host-process host-regions reverse string-append substring)
(import cu/procps ps-printable ps-resolve!)
(import cu/strings cu-range-number)
(import cu/text cu-pad-left cu-pad-zero)

(def %pmap-cmdline
  (fn (_ args)
    (ps-resolve!)
    (def trim
      (fn (self r) (if (if (pair? r) (= (byte-len (first r)) 0) #f) (self (rest r)) r)))
    (def s (ps-printable (Str8 join " " (reverse (trim (reverse args))))))
    (if (> (byte-len s) 4095) (substring s 0 4095) s)))

(def %pmap-kib (fn (_ n) (if (null? n) 0 (/ (- n (% n 1024)) 1024))))
(def %pmap-col (fn (_ n w) (cu-pad-left (cu-int->str n) w)))

; ADDR as busybox's %016llx: Host gives an address's 64 bits as a signed
; integer, so one in the top half (x86-64's [vsyscall]) is negative and
; prints as its two 32-bit halves
(def %pmap-address
  (fn (_ addr)
    (if (< addr 0)
      (string-append (cu-pad-zero (cu-hexs (& (>> addr 32) 4294967295)) 8)
                     (cu-pad-zero (cu-hexs (& addr 4294967295)) 8))
      (cu-pad-zero (cu-hexs addr) 16))))

; one region's row; SIZE is its KiB
(def %pmap-row
  (fn (_ r size x)
    (def get (fn (_ k) (Assoc get k r)))
    (def name (get (lit name)))
    (%str-concat
      (list (%pmap-address (get (lit start))) " "
            (if x
              (%str-concat
                (list (%pmap-col size 7) " " (%pmap-col (%pmap-kib (get (lit pss))) 7) " "
                      (%pmap-col (%pmap-kib (get (lit private-dirty))) 7) " "
                      (%pmap-col (%pmap-kib (get (lit swap))) 7) " "))
              (string-append (%pmap-col size 7) "K"))
            " " (get (lit mode)) "  " (if (null? name) "  [ anon ]" name) "\n"))))

; PID's report; answers 0, or 42 when the process or its regions cannot be read
(def %pmap-report
  (fn (_ pid x quiet)
    (if (null? (host-process pid)) 42
      (do (display (%str-concat (list (cu-int->str pid) ": " (%pmap-cmdline (host-args pid)) "\n")))
          (if (if x (not quiet) #f)
            (display "Address\t\t  Kbytes     PSS   Dirty    Swap  Mode  Mapping\n") ())
          (let ((rs (host-regions pid)))
            ; the sums of size, pss, dirty and swap, each row printed as it is read
            (def go
              (fn (self left k size pss dirty swap)
                (if (null? left) (list size pss dirty swap)
                  (let ((r (first left)))
                    (def n (%pmap-kib (Assoc get (lit size) r)))
                    (if (= (% k 32) 31) (cu-heap-collect) ())
                    (if (= n 0) () (display (%pmap-row r n x)))
                    (self (rest left) (+ k 1) (+ size n)
                      (+ pss (%pmap-kib (Assoc get (lit pss) r)))
                      (+ dirty (%pmap-kib (Assoc get (lit private-dirty) r)))
                      (+ swap (%pmap-kib (Assoc get (lit swap) r))))))))
            (if (null? rs) 42
              (let ((t (go rs 0 0 0 0 0)))
                (match
                  (quiet ())
                  (x (display (%str-concat
                                (list "----------------  ------  ------  ------  ------\n"
                                      "total kB " (%pmap-col (first t) 15) " "
                                      (%pmap-col (first (rest t)) 7) " "
                                      (%pmap-col (first (rest (rest t))) 7) " "
                                      (%pmap-col (first (rest (rest (rest t)))) 7) "\n"))))
                  (#t (display (%str-concat (list " total " (%pmap-col (first t) 17) "K\n")))))
                0)))))))

(def cu-pmap
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "pmap" argv))
    (def x (Opts on? o "-x"))
    (def quiet (Opts on? o "-q"))
    ; busybox's xatoi_positive: a bad pid ends the run there, with 1
    (def go
      (fn (self ops st)
        (if (null? ops) st
          (let ((pid (cu-range-number "pmap" (first ops) 0 2147483647)))
            (if (null? pid) 1
              (self (rest ops) (if (= (%pmap-report pid x quiet) 0) st 42)))))))
    (if (null? (Opts operands o)) (cu-usage "pmap") (go (Opts operands o) 0))))

(provide cu/pmap cu-pmap)

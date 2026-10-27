; # x-coreutils -- the small tools, as applets
;
; ## cu/ipcrm.x -- ipcrm: System V message queues, shared memory and semaphores removed
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's ipcrm (util-linux/ipcrm.c), through the calls cu/ipcs.x makes on
; each kernel.  -q, -m and -s remove the object their decimal id names; -Q,
; -M and -S the one their key names, hex, octal or decimal, found first with
; msgget, shmget or semget.  Each is done in the order given, a failure said
; and counted, and the count is the status.  The old form, `msg`, `shm` or
; `sem` and then decimal ids, removes each, counting a failure, and says
; "resource(s) deleted" when none failed.  Nothing given does nothing.

(module cu/ipcrm)

(import cu/cli cu-opts cu-usage)
(import cu/ipcs sv-ctl sv-die sv-eidrm sv-get sv-ipc-rmid sv-strtoul sv-u>)
(import cu/prims bit-and byte-at byte-len cu-err-label file-write libc-strerror
  string-concat string=?)

(def %ir-say (fn (_ msg) (file-write 2 (string-concat (list "ipcrm: " msg "\n")))))

(def %ir-kind
  (fn (_ c) (match ((= c #\q) (lit msg)) ((= c #\m) (lit shm)) (#t (lit sem)))))

; the old form's ids, each removed: the number that failed
(def %ir-ids
  (fn (_ kind ids)
    (List fold
      (fn (_ errors w)
        (let ((id (if (if (> (byte-len w) 0) (%ir-alnum? (byte-at w 0)) #f) (sv-strtoul w 10) ())))
          (if (if (null? id) #t (sv-u> id 2147483647))
            (do (%ir-say (string-concat (list "invalid id: " w))) (+ errors 1))
            (let ((got (sv-ctl kind id sv-ipc-rmid 0)))
              (if (= (first got) 0) errors
                (do (%ir-say (string-concat (list "can't remove id " w ": " (libc-strerror (rest got)))))
                    (+ errors 1)))))))
      0 ids)))

(def %ir-alnum?
  (fn (_ c)
    (match ((if (>= c #\0) (<= c #\9) #f) #t) ((if (>= c #\a) (<= c #\z) #f) #t)
           (#t (if (>= c #\A) (<= c #\Z) #f)))))

; busybox's words for a failed get or remove's errno
(def %ir-why
  (fn (_ errno removing)
    (match
      ((= errno 13) "permission denied for")
      ((if removing (= errno 1) #f) "permission denied for")
      ((= errno sv-eidrm) "already removed")
      ((= errno (if removing 22 2)) "invalid")
      (#t "unknown error in"))))

; xstrtoul's number from S in BASE, or the run ended as busybox's ends
(def %ir-number
  (fn (_ s base)
    (let ((v (sv-strtoul s base)))
      (if (null? v) (sv-die "ipcrm" (string-concat (list "invalid number '" s "'"))) v))))

; one option, C and its word W: 1 when it failed
(def %ir-one
  (fn (_ c w)
    (def key? (if (>= c #\A) (<= c #\Z) #f))
    (def kind (%ir-kind (if key? (+ c 32) c)))
    (def id
      (if (not key?) (pair (%ir-number w 10) 0)
        (let ((key (%ir-number w 0)))
          (if (= (bit-and key 4294967295) 0) ()
            (sv-get kind key)))))
    (match
      ((null? id) (do (%ir-say (string-concat (list "illegal key (" w ")"))) 1))
      ((if key? (< (first id) 0) #f)
        (do (%ir-say (string-concat (list (%ir-why (rest id) #f) " key (" w ")"))) 1))
      (#t (let ((got (sv-ctl kind (first id) sv-ipc-rmid 0)))
            (if (= (first got) 0) 0
              (do (%ir-say (string-concat (list (%ir-why (rest got) #t) (if key? " key (" " id (") w ")")))
                  1)))))))

(def %ir-main
  (fn (_ argv)
    (def w (if (null? argv) "" (first argv)))
    (def old (match ((string=? w "msg") (lit msg)) ((string=? w "shm") (lit shm))
                    ((string=? w "sem") (lit sem)) (#t ())))
    (match
      ((null? argv) 0)
      ((not (null? old))
        (match
          ((null? (rest argv)) (cu-usage "ipcrm"))
          ((> (%ir-ids old (rest argv)) 0) 1)
          (#t (do (file-write 1 "resource(s) deleted\n") 0))))
      (#t (let ((o (cu-opts "ipcrm" argv)))
            ; each option in the order given
            (def errors
              (List fold (fn (_ n e) (+ n (%ir-one (byte-at (first e) 1) (rest e))))
                0 (rest (Assoc entry (lit values) o))))
            (if (null? (Opts operands o)) errors (cu-usage "ipcrm")))))))

(def cu-ipcrm
  (fn (_ argv stdin-thunk)
    (guard (e (if (eq? (cu-err-label e) (lit ipcs)) 1 (error e)))
      (%ir-main argv))))

(provide cu/ipcrm cu-ipcrm)

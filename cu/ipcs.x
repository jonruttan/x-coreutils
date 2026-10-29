; # x-coreutils -- the small tools, as applets
;
; ## cu/ipcs.x -- ipcs: the System V message queues, shared memory and semaphores
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's ipcs (util-linux/ipcs.c), and the calls ipcrm shares with it.
; On Linux the objects are found as busybox finds them: MSG_INFO, SHM_INFO
; and SEM_INFO answer the highest index in use, and each index up to it is
; asked with MSG_STAT, SHM_STAT and SEM_STAT, an index the caller may not
; read passed over; IPC_INFO answers the limits.  Darwin has none of those
; commands: its kernel walks the objects for the kern.sysv.ipcs sysctls, an
; object's id made from its index and sequence number as Darwin's ipcs makes
; it, and the same sysctls answer the limits.  What -u counts on Linux --
; the objects in use, their pages, semaphores, messages and bytes -- Darwin
; does not keep, so there it is counted from the objects; it reports no
; resident or swapped pages, which show as 0.  The structs are read where
; each kernel lays them out: Linux's ipc64 forms, the same on every 64-bit
; Linux but the semaphore times, which x86-64 keeps a word apart; Darwin's
; packed user forms.

(module cu/ipcs)

(import cu/cli cu-opts cu-usage)
(import cu/date cu-date-fmt cu-date-split)
(import cu/dump dp-udigits)
(import cu/prims append bit-and bit-or bit-shl bit-shr byte-at byte-len cal/
  cu* cu+ cu- cu-err-label cu-int->str cu-libc-sym cu-ptr-call cu-ptr-ref
  cu-str->ptr file-write hx-hex-digit libc-strerror reverse str-make-raw
  string-append substring sys-group-name sys-user-name)
(import cu/text cu-pad-left cu-pad-right cu-pad-zero)

; --- the calls ----------------------------------------------------------------

; libc's NAME called with ARGS, its int answer signed
(def %sv-libc
  (fn (_ name args)
    (Sys %sign-fold (apply cu-ptr-call (pair (cu-libc-sym name) args)))))

; Linux's six calls are system calls; Darwin's are libc's, semctl as the
; __semctl it passes its variadic union to, which takes the union itself
(def %sv-linux
  (if os-darwin? ()
    (list (pair (lit shmctl) (syscall-door (lit shmctl)))
          (pair (lit msgctl) (syscall-door (lit msgctl)))
          (pair (lit semctl) (syscall-door (lit semctl)))
          (pair (lit shmget) (syscall-door (lit shmget)))
          (pair (lit msgget) (syscall-door (lit msgget)))
          (pair (lit semget) (syscall-door (lit semget))))))

(def %sv-darwin-names
  (list (pair (lit shmctl) "shmctl") (pair (lit msgctl) "msgctl") (pair (lit semctl) "__semctl")
        (pair (lit shmget) "shmget") (pair (lit msgget) "msgget") (pair (lit semget) "semget")))

; The call NAME on ARGS: (R . ERRNO), ERRNO 0 unless R is below 0
(def %sv-call
  (fn (_ name args)
    (def r (if os-darwin? (%sv-libc (rest (Assoc entry name %sv-darwin-names)) args)
             (apply (rest (Assoc entry name %sv-linux)) args)))
    (pair r (if (< r 0) (Err errno-of r) 0))))

; The commands, where the two kernels number them apart
(def sv-ipc-rmid 0)
(def sv-ipc-stat 2)
(def %sv-ipc-info 3)
(def %sv-getpid (if os-darwin? 4 11))
(def %sv-getval (if os-darwin? 5 12))
(def %sv-getncnt (if os-darwin? 3 14))
(def %sv-getzcnt (if os-darwin? 7 15))
(def sv-eidrm (if os-darwin? 82 43))

; KIND's control call: shmctl and msgctl take ID CMD BUF, semctl ID 0 CMD BUF
(def sv-ctl
  (fn (_ kind id cmd buf)
    (match
      ((eq? kind (lit shm)) (%sv-call (lit shmctl) (list id cmd buf)))
      ((eq? kind (lit msg)) (%sv-call (lit msgctl) (list id cmd buf)))
      (#t (%sv-call (lit semctl) (list id 0 cmd buf))))))

(def %sv-semctl (fn (_ id num cmd) (%sv-call (lit semctl) (list id num cmd 0))))

; KIND's id for KEY, as ipcrm asks it: an existing object's, made with nothing
(def sv-get
  (fn (_ kind key)
    (match
      ((eq? kind (lit shm)) (%sv-call (lit shmget) (list key 0 0)))
      ((eq? kind (lit msg)) (%sv-call (lit msgget) (list key 0)))
      (#t (%sv-call (lit semget) (list key 0 0))))))

; --- the structs --------------------------------------------------------------

; (NAME OFFSET WIDTH), each kernel's: the permissions first, then the kind's own
(def %sv-perm
  (if os-darwin?
    (lit ((uid 0 4) (gid 4 4) (cuid 8 4) (cgid 12 4) (mode 16 2) (seq 18 2) (key 20 4)))
    (lit ((key 0 4) (uid 4 4) (gid 8 4) (cuid 12 4) (cgid 16 4) (mode 20 2)))))

(def %sv-fields
  (if os-darwin?
    (list (pair (lit shm) (lit ((segsz 24 8) (lpid 32 4) (cpid 36 4) (nattch 40 2) (atime 44 8)
                                (dtime 52 8) (ctime 60 8))))
          (pair (lit msg) (lit ((cbytes 32 8) (qnum 40 8) (qbytes 48 8) (lspid 56 4) (lrpid 60 4)
                                (stime 64 8) (rtime 76 8) (ctime 88 8))))
          (pair (lit sem) (lit ((nsems 28 2) (otime 32 8) (ctime 44 8)))))
    (list (pair (lit shm) (lit ((segsz 48 8) (atime 56 8) (dtime 64 8) (ctime 72 8) (cpid 80 4)
                                (lpid 84 4) (nattch 88 8))))
          (pair (lit msg) (lit ((stime 48 8) (rtime 56 8) (ctime 64 8) (cbytes 72 8) (qnum 80 8)
                                (qbytes 88 8) (lspid 96 4) (lrpid 100 4))))
          (pair (lit sem) (if arch-x86-64? (lit ((otime 48 8) (ctime 64 8) (nsems 80 2)))
                            (lit ((otime 48 8) (ctime 56 8) (nsems 64 2))))))))

; the bytes Darwin's sysctls carry for a KIND's object, and a buffer that
; holds any kernel's
(def %sv-darwin-sizes (list (pair (lit shm) 76) (pair (lit msg) 116) (pair (lit sem) 72)))
(def sv-buffer (fn (_) (str-make-raw 256)))

; FIELDS read from BUF, an alist
(def %sv-read
  (fn (_ buf fields)
    (def p (cu-str->ptr buf))
    (List map (fn (_ f) (pair (first f) (cu-ptr-ref p (first (rest f)) (first (rest (rest f)))))) fields)))

; the object of KIND a stat call left in BUF, as an alist with its ID
(def sv-record
  (fn (_ kind id buf)
    (pair (pair (lit id) id)
          (%sv-read buf (append %sv-perm (rest (Assoc entry kind %sv-fields)))))))

(def sv-get-field (fn (_ r k) (rest (Assoc entry k r))))

; --- Linux: the indexes, and the info commands --------------------------------

(def %sv-info-cmd (list (pair (lit shm) 14) (pair (lit msg) 12) (pair (lit sem) 19)))
(def %sv-stat-cmd (list (pair (lit shm) 13) (pair (lit msg) 11) (pair (lit sem) 18)))

; KIND's info command into BUF: the highest index in use, below 0 when the
; kernel has no such IPC
(def %sv-info (fn (_ kind buf) (first (sv-ctl kind 0 (rest (Assoc entry kind %sv-info-cmd)) buf))))

(def %sv-linux-list
  (fn (_ kind)
    (def buf (sv-buffer))
    (def maxid (%sv-info kind buf))
    (def cmd (rest (Assoc entry kind %sv-stat-cmd)))
    (def go
      (fn (self i acc)
        (if (> i maxid) (reverse acc)
          (let ((r (first (sv-ctl kind i cmd buf))))
            (self (+ i 1) (if (< r 0) acc (pair (sv-record kind r buf) acc)))))))
    (if (< maxid 0) #f (go 0 ()))))

; --- Darwin: the kern.sysv.ipcs sysctls ----------------------------------------

(def %sv-word! (prim-ref (lit ptr) (lit set-word!)))
(def %sv-addr (fn (_ buf) ((prim-ref (lit ptr) (lit ->int)) (cu-str->ptr buf))))

(def %sv-sysctl-names
  (list (pair (lit shm) "kern.sysv.ipcs.shm") (pair (lit msg) "kern.sysv.ipcs.msg")
        (pair (lit sem) "kern.sysv.ipcs.sem")))

; The IPCS command OP for KIND from CURSOR, its LEN bytes of answer in DATA:
; the cursor past the object it answered, or nil when there are no more
(def %sv-ipcs
  (fn (_ kind op cursor data len)
    (def cmd (str-make-raw 24))
    (def size (str-make-raw 8))
    (def p (cu-str->ptr cmd))
    (%sv-word! p 0 (bit-or 1 (bit-shl op 32)))
    (%sv-word! p 8 (bit-or cursor (bit-shl len 32)))
    (%sv-word! p 16 (%sv-addr data))
    (%sv-word! (cu-str->ptr size) 0 24)
    (if (< (%sv-libc "sysctlbyname" (list (rest (Assoc entry kind %sv-sysctl-names)) p (cu-str->ptr size) p 24)) 0) ()
      (cu-ptr-ref p 8 4))))

(def %sv-iter-op (list (pair (lit shm) 2) (pair (lit msg) 512) (pair (lit sem) 32)))

(def %sv-darwin-list
  (fn (_ kind)
    (def op (rest (Assoc entry kind %sv-iter-op)))
    (def len (rest (Assoc entry kind %sv-darwin-sizes)))
    (def buf (sv-buffer))
    (def go
      (fn (self cursor acc)
        (let ((next (%sv-ipcs kind op cursor buf len)))
          (if (null? next) (reverse acc)
            (let ((r (sv-record kind 0 buf)))
              (self next (pair (pair (pair (lit id) (bit-or (bit-shl (sv-get-field r (lit seq)) 16)
                                                             (bit-and (- next 1) 65535)))
                                     (rest r))
                               acc)))))))
    (go 0 ())))

; KIND's objects in the kernel's order, or #f where the kernel has no such IPC
(def sv-list (fn (_ kind) (if os-darwin? (%sv-darwin-list kind) (%sv-linux-list kind))))

; KIND's limits, as an alist under Linux's names
(def %sv-limits
  (fn (_ kind)
    (def buf (sv-buffer))
    (match
      (os-darwin?
        (let ((ok (not (null? (%sv-ipcs kind (match ((eq? kind (lit shm)) 1) ((eq? kind (lit sem)) 16) (#t 256))
                                       0 buf (if (eq? kind (lit msg)) 24 40))))))
          (if (not ok) ()
            (%sv-read buf
              (match
                ((eq? kind (lit shm)) (lit ((shmmax 0 8) (shmmin 8 8) (shmmni 16 8) (shmall 32 8))))
                ((eq? kind (lit sem)) (lit ((semmni 4 4) (semmns 8 4) (semmsl 16 4) (semopm 20 4) (semvmx 32 4))))
                (#t (lit ((msgmax 0 4) (msgmni 4 4) (msgmnb 8 4)))))))))
      ((< (first (sv-ctl kind 0 %sv-ipc-info buf)) 0) ())
      (#t (%sv-read buf
            (match
              ((eq? kind (lit shm)) (lit ((shmmax 0 8) (shmmin 8 8) (shmmni 16 8) (shmall 32 8))))
              ((eq? kind (lit sem)) (lit ((semmni 4 4) (semmns 8 4) (semmsl 16 4) (semopm 20 4) (semvmx 32 4))))
              (#t (lit ((msgmax 8 4) (msgmnb 12 4) (msgmni 16 4))))))))))

; KIND's use, as an alist under Linux's names: the info command's on Linux,
; counted from OBJECTS on Darwin
(def %sv-status
  (fn (_ kind objects)
    (def buf (sv-buffer))
    (def sum (fn (_ k) (List fold (fn (_ acc r) (+ acc (sv-get-field r k))) 0 objects)))
    (match
      ((not os-darwin?)
        (do (%sv-info kind buf)
            (%sv-read buf
              (match
                ((eq? kind (lit shm)) (lit ((used 0 4) (tot 8 8) (rss 16 8) (swp 24 8) (attempts 32 8) (successes 40 8))))
                ((eq? kind (lit sem)) (lit ((semusz 28 4) (semaem 36 4))))
                (#t (lit ((msgpool 0 4) (msgmap 4 4) (msgtql 24 4))))))))
      ((eq? kind (lit shm))
        (let ((page (%sv-libc "getpagesize" ())))
          (list (pair (lit used) (List length objects))
                (pair (lit tot) (List fold (fn (_ acc r) (+ acc (cal/ (+ (sv-get-field r (lit segsz)) (- page 1)) page)))
                                  0 objects))
                (pair (lit rss) 0) (pair (lit swp) 0) (pair (lit attempts) 0) (pair (lit successes) 0))))
      ((eq? kind (lit sem))
        (list (pair (lit semusz) (List length objects)) (pair (lit semaem) (sum (lit nsems)))))
      (#t (list (pair (lit msgpool) (List length objects)) (pair (lit msgmap) (sum (lit qnum)))
                (pair (lit msgtql) (sum (lit cbytes))))))))

; --- printf's pieces ----------------------------------------------------------

; N, an unsigned 64-bit word, in decimal: one wrapped below 0 halved first
(def sv-u64
  (fn (_ n)
    (if (>= n 0) (cu-int->str n)
      (let ((q (cal/ (bit-and (bit-shr n 1) 9223372036854775807) 5)))
        (string-append (cu-int->str q) (cu-int->str (cu- n (cu* q 10))))))))

; N's low 32 bits as a C int, as %d prints them
(def sv-int (fn (_ n) (let ((w (bit-and n 4294967295))) (if (>= w 2147483648) (- w 4294967296) w))))
(def %sv-d (fn (_ n) (cu-int->str (sv-int n))))
(def %sv-o (fn (_ n) (dp-udigits n 8 #f)))
; %#o
(def sv-alt-o (fn (_ n) (if (= n 0) "0" (string-append "0" (%sv-o n)))))
; %-Ws, and %-W.Ps
(def %sv-l (fn (_ s w) (cu-pad-right s w)))
(def %sv-lp (fn (_ s w p) (cu-pad-right (if (> (byte-len s) p) (substring s 0 p) s) w)))

; ctime(T) less its newline
(def sv-ctime (fn (_ t) (cu-date-fmt "%a %b %e %H:%M:%S %Y" (cu-date-split t #f) t)))

; %-26.24s of ctime, "Not set" for no time; and %-20.16s of ctime + 4
(def sv-time26 (fn (_ t) (%sv-l (if (= t 0) "Not set" (sv-ctime t)) 26)))
(def %sv-time20 (fn (_ t) (%sv-l (if (= t 0) "Not set" (substring (sv-ctime t) 4 20)) 20)))

; a user's name, or nil
(def %sv-name (fn (_ uid) (sys-user-name uid)))

; "%-W.10s" of the owner's name, or "%-Wd" of the uid without one; the id
; before it "%-Ids"
(def %sv-id-owner
  (fn (_ r iw nw np)
    (def name (%sv-name (sv-get-field r (lit uid))))
    (string-append (%sv-l (%sv-d (sv-get-field r (lit id))) iw)
      (string-append " "
        (if (null? name) (%sv-l (%sv-d (sv-get-field r (lit uid))) np)
          (%sv-lp name nw np))))))

(def %sv-out (fn (_ s) (file-write 1 s)))

; print_perms: the id, the mode, and the creator's and owner's names or ids
(def %sv-perms
  (fn (_ r)
    (def who
      (fn (_ k name-of)
        (let ((n (name-of (sv-get-field r k))))
          (string-append " " (%sv-l (if (null? n) (%sv-d (sv-get-field r k)) n) 10)))))
    (%sv-out (%str-concat
               (list (%sv-l (%sv-d (sv-get-field r (lit id))) 10) " "
                     (%sv-l (%sv-o (bit-and (sv-get-field r (lit mode)) 511)) 10)
                     (who (lit cuid) sys-user-name) (who (lit cgid) sys-group-name)
                     (who (lit uid) sys-user-name) (who (lit gid) sys-group-name) "\n")))))

; "0x%08x " of the key
(def %sv-key
  (fn (_ r) (%str-concat (list "0x" (cu-pad-zero (dp-udigits (sv-get-field r (lit key)) 16 #f) 8) " "))))

(def %sv-heads
  (fn (_ names widths)
    (string-append
      (%str-concat
        (List map (fn (_ i) (string-append (if (= i 0) "" " ") (%sv-l (List ref i names) (List ref i widths))))
                  (List range 0 (List length names))))
      "\n")))

; the section's title line
(def %sv-title (fn (_ what) (%sv-out (%str-concat (list "------ " what " --------\n")))))

; --- the three listings -------------------------------------------------------

(def %sv-not-configured
  (fn (_ what) (%sv-out (%str-concat (list "kernel not configured for " what "\n")))))

(def %sv-do-shm
  (fn (_ format)
    (def objects (sv-list (lit shm)))
    (def row
      (fn (_ r)
        (match
          ((eq? format (lit creator)) (%sv-perms r))
          ((eq? format (lit time))
            (%sv-out (%str-concat
                       (list (%sv-id-owner r 10 10 10)
                             " " (%sv-time20 (sv-get-field r (lit atime)))
                             " " (%sv-time20 (sv-get-field r (lit dtime)))
                             " " (%sv-time20 (sv-get-field r (lit ctime))) "\n"))))
          ((eq? format (lit pid))
            (%sv-out (%str-concat
                       (list (%sv-id-owner r 10 10 10)
                             " " (%sv-l (%sv-d (sv-get-field r (lit cpid))) 10)
                             " " (%sv-l (%sv-d (sv-get-field r (lit lpid))) 10) "\n"))))
          (#t
            (let ((mode (sv-get-field r (lit mode))))
              (%sv-out (%str-concat
                         (list (%sv-key r) (%sv-id-owner r 10 10 10)
                               " " (%sv-l (%sv-o (bit-and mode 511)) 10)
                               " " (%sv-l (sv-u64 (sv-get-field r (lit segsz))) 10)
                               " " (%sv-l (cu-int->str (sv-get-field r (lit nattch))) 10)
                               " " (%sv-l (if (= (bit-and mode 512) 0) " " "dest") 6)
                               " " (%sv-l (if (= (bit-and mode 1024) 0) " " "locked") 6) "\n"))))))))
    (match
      ((eq? objects #f) (%sv-not-configured "shared memory"))
      ((eq? format (lit limits))
        (let ((l (%sv-limits (lit shm))))
          (do (%sv-title "Shared Memory Limits")
              (unless (null? l)
                (%sv-out (%str-concat
                           (list "max number of segments = " (sv-u64 (sv-get-field l (lit shmmni)))
                                 "\nmax seg size (kbytes) = "
                                 (sv-u64 (bit-and (bit-shr (sv-get-field l (lit shmmax)) 10) 18014398509481983))
                                 "\nmax total shared memory (pages) = " (sv-u64 (sv-get-field l (lit shmall)))
                                 "\nmin seg size (bytes) = " (sv-u64 (sv-get-field l (lit shmmin))) "\n")))))))
      ((eq? format (lit status))
        (let ((s (%sv-status (lit shm) objects)))
          (do (%sv-title "Shared Memory Status")
              (%sv-out (%str-concat
                         (list "segments allocated " (%sv-d (sv-get-field s (lit used)))
                               "\npages allocated " (sv-u64 (sv-get-field s (lit tot)))
                               "\npages resident  " (sv-u64 (sv-get-field s (lit rss)))
                               "\npages swapped   " (sv-u64 (sv-get-field s (lit swp)))
                               "\nSwap performance: " (sv-u64 (sv-get-field s (lit attempts)))
                               " attempts\t" (sv-u64 (sv-get-field s (lit successes))) " successes\n"))))))
      (#t
        (do (match
              ((eq? format (lit creator))
                (do (%sv-title "Shared Memory Segment Creators/Owners")
                    (%sv-out (%sv-heads (list "shmid" "perms" "cuid" "cgid" "uid" "gid") (list 10 10 10 10 10 10)))))
              ((eq? format (lit time))
                (do (%sv-title "Shared Memory Attach/Detach/Change Times")
                    (%sv-out (%sv-heads (list "shmid" "owner" "attached" "detached" "changed") (list 10 10 20 20 20)))))
              ((eq? format (lit pid))
                (do (%sv-title "Shared Memory Creator/Last-op")
                    (%sv-out (%sv-heads (list "shmid" "owner" "cpid" "lpid") (list 10 10 10 10)))))
              (#t
                (do (%sv-title "Shared Memory Segments")
                    (%sv-out (%sv-heads (list "key" "shmid" "owner" "perms" "bytes" "nattch" "status")
                                        (list 10 10 10 10 10 10 12))))))
            (List map row objects))))))

(def %sv-do-sem
  (fn (_ format)
    (def objects (sv-list (lit sem)))
    (def row
      (fn (_ r)
        (match
          ((eq? format (lit creator)) (%sv-perms r))
          ((eq? format (lit time))
            (%sv-out (%str-concat
                       (list (%sv-id-owner r 8 10 10)
                             "  " (sv-time26 (sv-get-field r (lit otime)))
                             " " (sv-time26 (sv-get-field r (lit ctime))) "\n"))))
          ((eq? format (lit pid)) ())
          (#t
            (let ((name (%sv-name (sv-get-field r (lit uid)))))
              (%sv-out (%str-concat
                         (list (%sv-key r) (%sv-l (%sv-d (sv-get-field r (lit id))) 10) " "
                               (if (null? name) (%sv-l (%sv-d (sv-get-field r (lit uid))) 9) (%sv-lp name 10 9))
                               " " (%sv-l (%sv-o (bit-and (sv-get-field r (lit mode)) 511)) 10)
                               " " (%sv-l (cu-int->str (sv-get-field r (lit nsems))) 10) "\n"))))))))
    (match
      ((eq? objects #f) (%sv-not-configured "semaphores"))
      ((eq? format (lit limits))
        (let ((l (%sv-limits (lit sem))))
          (do (%sv-title "Semaphore Limits")
              (unless (null? l)
                (%sv-out (%str-concat
                           (list "max number of arrays = " (%sv-d (sv-get-field l (lit semmni)))
                                 "\nmax semaphores per array = " (%sv-d (sv-get-field l (lit semmsl)))
                                 "\nmax semaphores system wide = " (%sv-d (sv-get-field l (lit semmns)))
                                 "\nmax ops per semop call = " (%sv-d (sv-get-field l (lit semopm)))
                                 "\nsemaphore max value = " (%sv-d (sv-get-field l (lit semvmx))) "\n")))))))
      ((eq? format (lit status))
        (let ((s (%sv-status (lit sem) objects)))
          (do (%sv-title "Semaphore Status")
              (%sv-out (%str-concat
                         (list "used arrays = " (%sv-d (sv-get-field s (lit semusz)))
                               "\nallocated semaphores = " (%sv-d (sv-get-field s (lit semaem))) "\n"))))))
      (#t
        (do (match
              ((eq? format (lit creator))
                (do (%sv-title "Semaphore Arrays Creators/Owners")
                    (%sv-out (%sv-heads (list "semid" "perms" "cuid" "cgid" "uid" "gid") (list 10 10 10 10 10 10)))))
              ; busybox titles the semaphores' times as shared memory's
              ((eq? format (lit time))
                (do (%sv-title "Shared Memory Operation/Change Times")
                    (%sv-out (%sv-heads (list "shmid" "owner" "last-op" "last-changed")
                                        (list 8 10 26 26)))))
              ((eq? format (lit pid)) ())
              (#t
                (do (%sv-title "Semaphore Arrays")
                    (%sv-out (%sv-heads (list "key" "semid" "owner" "perms" "nsems") (list 10 10 10 10 10))))))
            (List map row objects))))))

(def %sv-do-msg
  (fn (_ format)
    (def objects (sv-list (lit msg)))
    (def row
      (fn (_ r)
        (match
          ((eq? format (lit creator)) (%sv-perms r))
          ((eq? format (lit time))
            (%sv-out (%str-concat
                       (list (%sv-id-owner r 8 10 10)
                             " " (%sv-time20 (sv-get-field r (lit stime)))
                             " " (%sv-time20 (sv-get-field r (lit rtime)))
                             " " (%sv-time20 (sv-get-field r (lit ctime))) "\n"))))
          ((eq? format (lit pid))
            (%sv-out (%str-concat
                       (list (%sv-id-owner r 8 10 10)
                             "  " (cu-pad-left (%sv-d (sv-get-field r (lit lspid))) 5)
                             "     " (cu-pad-left (%sv-d (sv-get-field r (lit lrpid))) 5) "\n"))))
          (#t
            (%sv-out (%str-concat
                       (list (%sv-key r) (%sv-id-owner r 10 10 10)
                             " " (%sv-l (%sv-o (bit-and (sv-get-field r (lit mode)) 511)) 10)
                             " " (%sv-l (cu-int->str (sv-get-field r (lit cbytes))) 12)
                             " " (%sv-l (cu-int->str (sv-get-field r (lit qnum))) 12) "\n")))))))
    (match
      ((eq? objects #f) (%sv-not-configured "message queues"))
      ((eq? format (lit limits))
        (let ((l (%sv-limits (lit msg))))
          (unless (null? l)
            (do (%sv-title "Messages: Limits")
                (%sv-out (%str-concat
                           (list "max queues system wide = " (%sv-d (sv-get-field l (lit msgmni)))
                                 "\nmax size of message (bytes) = " (%sv-d (sv-get-field l (lit msgmax)))
                                 "\ndefault max size of queue (bytes) = " (%sv-d (sv-get-field l (lit msgmnb))) "\n")))))))
      ((eq? format (lit status))
        (let ((s (%sv-status (lit msg) objects)))
          (do (%sv-title "Messages: Status")
              (%sv-out (%str-concat
                         (list "allocated queues = " (%sv-d (sv-get-field s (lit msgpool)))
                               "\nused headers = " (%sv-d (sv-get-field s (lit msgmap)))
                               "\nused space = " (%sv-d (sv-get-field s (lit msgtql))) " bytes\n"))))))
      (#t
        (do (match
              ((eq? format (lit creator))
                (do (%sv-title "Message Queues: Creators/Owners")
                    (%sv-out (%sv-heads (list "msqid" "perms" "cuid" "cgid" "uid" "gid") (list 10 10 10 10 10 10)))))
              ((eq? format (lit time))
                (do (%sv-title "Message Queues Send/Recv/Change Times")
                    (%sv-out (%sv-heads (list "msqid" "owner" "send" "recv" "change") (list 8 10 20 20 20)))))
              ((eq? format (lit pid))
                (do (%sv-title "Message Queues PIDs")
                    (%sv-out (%sv-heads (list "msqid" "owner" "lspid" "lrpid") (list 10 10 10 10)))))
              (#t
                (do (%sv-title "Message Queues")
                    (%sv-out (%sv-heads (list "key" "msqid" "owner" "perms" "used-bytes" "messages")
                                        (list 10 10 10 10 12 12))))))
            (List map row objects))))))

; --- one object, -i -----------------------------------------------------------

; perror's line after a failed call, to standard error
(def %sv-perror
  (fn (_ what errno)
    (file-write 2 (%str-concat (list "ipcs: " what ": " (libc-strerror errno) "\n")))))

(def %sv-ids-line
  (fn (_ r sep)
    (%str-concat
      (list "uid=" (%sv-d (sv-get-field r (lit uid))) sep "gid=" (%sv-d (sv-get-field r (lit gid)))
            sep "cuid=" (%sv-d (sv-get-field r (lit cuid))) sep "cgid=" (%sv-d (sv-get-field r (lit cgid)))))))

(def %sv-print-shm
  (fn (_ id)
    (def buf (sv-buffer))
    (def got (sv-ctl (lit shm) id sv-ipc-stat buf))
    (if (< (first got) 0) (%sv-perror "shmctl" (rest got))
      (let ((r (sv-record (lit shm) id buf)))
        (%sv-out (%str-concat
                   (list "\nShared memory Segment shmid=" (%sv-d id) "\n"
                         (%sv-ids-line r "\t") "\n"
                         "mode=" (sv-alt-o (sv-get-field r (lit mode)))
                         "\taccess_perms=" (sv-alt-o (bit-and (sv-get-field r (lit mode)) 511)) "\n"
                         "bytes=" (cu-int->str (sv-get-field r (lit segsz)))
                         "\tlpid=" (%sv-d (sv-get-field r (lit lpid)))
                         "\tcpid=" (%sv-d (sv-get-field r (lit cpid)))
                         "\tnattch=" (cu-int->str (sv-get-field r (lit nattch))) "\n"
                         "att_time=" (sv-time26 (sv-get-field r (lit atime))) "\n"
                         "det_time=" (sv-time26 (sv-get-field r (lit dtime))) "\n"
                         "change_time=" (%sv-l (sv-ctime (sv-get-field r (lit ctime))) 26) "\n\n")))))))

(def %sv-print-msg
  (fn (_ id)
    (def buf (sv-buffer))
    (def got (sv-ctl (lit msg) id sv-ipc-stat buf))
    (if (< (first got) 0) (%sv-perror "msgctl" (rest got))
      (let ((r (sv-record (lit msg) id buf)))
        (%sv-out (%str-concat
                   (list "\nMessage Queue msqid=" (%sv-d id) "\n"
                         (%sv-ids-line r "\t") "\tmode=" (sv-alt-o (sv-get-field r (lit mode))) "\n"
                         "cbytes=" (cu-int->str (sv-get-field r (lit cbytes)))
                         "\tqbytes=" (cu-int->str (sv-get-field r (lit qbytes)))
                         "\tqnum=" (cu-int->str (sv-get-field r (lit qnum)))
                         "\tlspid=" (%sv-d (sv-get-field r (lit lspid)))
                         "\tlrpid=" (%sv-d (sv-get-field r (lit lrpid))) "\n"
                         "send_time=" (sv-time26 (sv-get-field r (lit stime))) "\n"
                         "rcv_time=" (sv-time26 (sv-get-field r (lit rtime))) "\n"
                         "change_time=" (sv-time26 (sv-get-field r (lit ctime))) "\n\n")))))))

; a semaphore's value, waiters and last pid; the run ending, as busybox's
; does, when the kernel refuses any of them
(def %sv-sem-row
  (fn (_ id i)
    (def ask (fn (_ cmd) (%sv-semctl id i cmd)))
    (def calls (List map ask (list %sv-getval %sv-getncnt %sv-getzcnt %sv-getpid)))
    (def bad (List find (fn (_ c) (< (first c) 0)) calls))
    (if (not (null? bad))
      (do (%sv-perror "semctl" (rest bad)) (Err raise (lit ipcs) "semctl" ()))
      (%sv-out (%str-concat
                 (list (%sv-l (cu-int->str i) 10)
                       (%str-concat (List map (fn (_ c) (string-append " " (%sv-l (%sv-d (first c)) 10))) calls))
                       "\n"))))))

(def %sv-print-sem
  (fn (_ id)
    (def buf (sv-buffer))
    (def got (sv-ctl (lit sem) id sv-ipc-stat buf))
    (if (not (= (first got) 0)) (%sv-perror "semctl" (rest got))
      (let ((r (sv-record (lit sem) id buf)))
        (do (%sv-out (%str-concat
                       (list "\nSemaphore Array semid=" (%sv-d id) "\n"
                             (%sv-ids-line r "\t ") "\n"
                             "mode=" (sv-alt-o (sv-get-field r (lit mode)))
                             ", access_perms=" (sv-alt-o (bit-and (sv-get-field r (lit mode)) 511)) "\n"
                             "nsems = " (cu-int->str (sv-get-field r (lit nsems))) "\n"
                             "otime = " (sv-time26 (sv-get-field r (lit otime))) "\n"
                             "ctime = " (%sv-l (sv-ctime (sv-get-field r (lit ctime))) 26) "\n"
                             (%sv-heads (list "semnum" "value" "ncount" "zcount" "pid") (list 10 10 10 10 10)))))
            (List map (fn (_ i) (%sv-sem-row id i)) (List range 0 (sv-get-field r (lit nsems))))
            (%sv-out "\n"))))))

; --- numbers ------------------------------------------------------------------

; S as strtoul reads it in BASE, 10 or 0 (0x hex, 0 octal, else decimal),
; after busybox's xstrtou refuses a sign or a space first: the value, the
; unsigned 64-bit word wrapped as the engine's ints wrap, or nil where it is
; no number, has more after it, or passes 2^64-1
(def sv-strtoul
  (fn (_ s base)
    (def n (byte-len s))
    (def at (fn (_ k) (if (< k n) (byte-at s k) 0)))
    (def hex? (if (= base 0) (if (= (at 0) #\0) (if (= (bit-or (at 1) 32) #\x) (>= (hx-hex-digit (at 2)) 0) #f) #f) #f))
    (def b (match ((= base 10) 10) (hex? 16) ((= (at 0) #\0) 8) (#t 10)))
    (def start (if hex? 2 0))
    (def digit (fn (_ k) (let ((d (hx-hex-digit (at k)))) (if (if (>= d 0) (< d b) #f) d -1))))
    (def lead (fn (self k) (if (if (< k n) (= (at k) #\0) #f) (self (+ k 1)) k)))
    (def go (fn (self k acc) (if (< (digit k) 0) (pair k acc) (self (+ k 1) (cu+ (cu* acc b) (digit k))))))
    (def first-c (at 0))
    (def end-acc (go start 0))
    (def sig (- (first end-acc) (lead start)))
    (def over
      (match
        ((= b 16) (> sig 16))
        ((= b 8) (if (> sig 22) #t (if (= sig 22) (> (at (lead start)) #\1) #f)))
        ((> sig 20) #t)
        ((< sig 20) #f)
        (#t (%sv-above? s (lead start) "18446744073709551615"))))
    (match
      ((= n 0) ())
      ((match ((= first-c #\-) #t) ((= first-c #\+) #t) (#t (%sv-space? first-c))) ())
      ((= (first end-acc) start) ())
      ((< (first end-acc) n) ())
      (over ())
      (#t (rest end-acc)))))

(def %sv-space? (fn (_ c) (if (= c 32) #t (if (>= c 9) (<= c 13) #f))))

; the 20 digits of S from I above LIMIT's
(def %sv-above?
  (fn (_ s i limit)
    (def go
      (fn (self k)
        (match
          ((>= k 20) #f)
          ((> (byte-at s (+ i k)) (byte-at limit k)) #t)
          ((< (byte-at s (+ i k)) (byte-at limit k)) #f)
          (#t (self (+ k 1))))))
    (go 0)))

; unsigned N above unsigned HI, N a word that may have wrapped below 0
(def sv-u> (fn (_ n hi) (if (< n 0) #t (> n hi))))

; xatoi: S a decimal int, an optional sign before it, or the run ends with
; busybox's words, which name the number without its sign: past an unsigned
; int it is no number, as bb_strtou calls it, and past an int out of range
(def %sv-xatoi
  (fn (_ s)
    (def signed (if (> (byte-len s) 0) (if (= (byte-at s 0) #\-) #t (= (byte-at s 0) #\+)) #f))
    (def p (if signed (substring s 1 (byte-len s)) s))
    (def hi (if (if (> (byte-len p) 0) (= (byte-at p 0) #\-) #f) 2147483648 2147483647))
    (def v (sv-strtoul p 10))
    (match
      ((if (null? v) #t (sv-u> v 4294967295)) (sv-die "ipcs" (%str-concat (list "invalid number '" p "'"))))
      ((sv-u> v hi) (sv-die "ipcs" (%str-concat (list "number " p " is not in 0.." (cu-int->str hi) " range"))))
      ((= (byte-at s 0) #\-) (- 0 v))
      (#t v))))

; APPLET's error line, and the run ended with 1
(def sv-die
  (fn (_ applet msg)
    (do (file-write 2 (%str-concat (list applet ": " msg "\n")))
        (Err raise (lit ipcs) msg ()))))

; --- ipcs ---------------------------------------------------------------------

(def %sv-main
  (fn (_ argv)
    (def o (cu-opts "ipcs" argv))
    (def on? (fn (_ f) (Opts on? o f)))
    (def format
      (match ((on? "-u") (lit status)) ((on? "-l") (lit limits)) ((on? "-p") (lit pid))
             ((on? "-c") (lit creator)) ((on? "-t") (lit time)) (#t (lit default))))
    (def i (Opts value o "-i"))
    (def all (if (on? "-a") #t (not (if (on? "-q") #t (if (on? "-s") #t (on? "-m"))))))
    (if (not (null? i))
      (let ((id (%sv-xatoi i)))
        (match
          ((on? "-m") (do (%sv-print-shm id) 0))
          ((on? "-s") (do (%sv-print-sem id) 0))
          ((on? "-q") (do (%sv-print-msg id) 0))
          (#t (cu-usage "ipcs"))))
      (do (%sv-out "\n")
          (when (if all #t (on? "-q")) (do (%sv-do-msg format) (%sv-out "\n")))
          (when (if all #t (on? "-m")) (do (%sv-do-shm format) (%sv-out "\n")))
          (when (if all #t (on? "-s")) (do (%sv-do-sem format) (%sv-out "\n")))
          0))))

(def cu-ipcs
  (fn (_ argv stdin-thunk)
    (guard (e (if (eq? (cu-err-label e) (lit ipcs)) 1 (error e)))
      (%sv-main argv))))

(provide cu/ipcs cu-ipcs sv-ctl sv-die sv-eidrm sv-get sv-ipc-rmid sv-strtoul sv-u>)

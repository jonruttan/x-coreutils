; # x-coreutils -- the small tools, as applets
;
; ## cu/pstree.x -- pstree: the process tree
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's pstree with FEATURE_SHOW_THREADS (procps/pstree.c).  Host's
; process table, each process's threads after it as {NAME} children, is
; hung under each parent and the children ordered by name, then user, then
; the order the table gives them.  The tree from PID, 1 unless named, is
; drawn in busybox's ASCII lines; a run of children whose trees are the same
; is drawn once, N*[NAME], and -p adds each one's id, which keeps every
; child apart.  A USER draws each tree under 1 whose top that user owns, a
; blank line between, and root is the whole tree.  A line stops at the
; terminal's width, $COLUMNS over the terminal stdin is, else 80: its last
; column a +, and the children of a cut line are not drawn.  A process
; whose parent is its own (Darwin's kernel_task) is nobody's child.

(module cu/pstree)

(import cu/cli cu-opts cu-usage)
(import cu/prims append byte-at byte-len cal/ cu-err-label cu-heap-collect cu-int->str cu-sweep-lines
  cu-sweep-tick! file-write host-processes host-threads length reverse
  string-append string-concat substring sys-getenv sys-user-id)
(import cu/procps ps-sorted)
(import cu/vi vi-dim)

(def %pst-die
  (fn (_ msg)
    (do (file-write 2 (string-concat (list "pstree: " msg "\n")))
        (Err raise (lit pstree) msg ()))))

; a node: (PID PPID UID COMM CHILDREN-CELL)
(def %pst-pid (fn (_ n) (first n)))
(def %pst-ppid (fn (_ n) (first (rest n))))
(def %pst-uid (fn (_ n) (first (rest (rest n)))))
(def %pst-comm (fn (_ n) (first (rest (rest (rest n))))))
(def %pst-kids-cell (fn (_ n) (first (rest (rest (rest (rest n)))))))
(def %pst-children (fn (_ n) (first (%pst-kids-cell n))))
(def %pst-node (fn (_ pid ppid uid comm) (list pid ppid uid comm (list ()))))

; the sort's primitives: a comparison runs some 75,000 times over a desktop's
; processes and threads, and the ambient ops cost ~90 objects each
(def %pst< (prim-ref (lit int) (lit <)))
(def %pst= (prim-ref (lit int) (lit =)))
(def %pst-cmp (prim-ref (lit mem) (lit cmp)))
(def %pst-ptr (prim-ref (lit str) (lit ->ptr)))
(def %pst-len (prim-ref (lit str) (lit byte-len)))

; strcmp's sign for two names, which hold no NUL: memcmp over the shorter,
; then the shorter first
(def %pst-strcmp
  (fn (_ a b)
    (def la (%pst-len a))
    (def lb (%pst-len b))
    (def c (%pst-cmp (%pst-ptr a) (%pst-ptr b) (if (%pst< la lb) la lb)))
    (if (eq? c 0) (if (%pst< la lb) -1 (if (%pst< lb la) 1 0)) c)))

; --- the table -------------------------------------------------------------------

; P's threads but its first, {NAME} children of P, as handle_thread adds
; them: Linux's first is the one whose id is P's, Darwin's the oldest
(def %pst-threads
  (fn (_ p pid)
    (def n (Assoc get (lit threads) p))
    (def ts (if (if (null? n) #t (< n 2)) ()
              (List sort (fn (_ a b) (< (Assoc get (lit pid) a) (Assoc get (lit pid) b)))
                (let ((t (host-threads pid))) (if (null? t) () (do (%pst-swept! (length t)) t))))))
    (def main (List find (fn (_ t) (= (Assoc get (lit pid) t) pid)) ts))
    (def others (if (null? main) (if (null? ts) () (rest ts))
                  (List reject (fn (_ t) (= (Assoc get (lit pid) t) pid)) ts)))
    (List map (fn (_ t)
                (%pst-node (Assoc get (lit pid) t) pid (Assoc get (lit uid) t)
                  (string-concat (list "{" (%pst-cut (Assoc get (lit comm) t) 16) "}"))))
              others)))

(def %pst-cut (fn (_ s n) (if (> (byte-len s) n) (substring s 0 n) s)))

; the threads read since the last collect: Darwin builds a thread's record
; from its process's, ~23K objects, and a desktop has thousands of them
(def %pst-unswept (list 0))
(def %pst-swept!
  (fn (_ n)
    (set-first! %pst-unswept (+ (first %pst-unswept) n))
    (when (>= (first %pst-unswept) 256)
      (do (cu-heap-collect) (set-first! %pst-unswept 0)))))

; every process, its threads after it, in the table's order
(def %pst-scan
  (fn (_)
    (def ps (ps-sorted (host-processes)))
    (cu-heap-collect)
    (set-first! %pst-unswept 0)
    (List flat-map
      (fn (_ p)
        (def pid (Assoc get (lit pid) p))
        (def ppid (Assoc get (lit ppid) p))
        (def comm (Assoc get (lit comm) p))
        (pair (%pst-node pid (if (= pid ppid) 0 ppid) (Assoc get (lit uid) p) (if (null? comm) "" comm))
              (%pst-threads p pid)))
      ps)))

; the children's order, add_child's: by parent, then name, then user; the
; table's order else, which the sort keeps
(def %pst-before?
  (fn (_ a b)
    (def pa (%pst-ppid a))
    (def pb (%pst-ppid b))
    (match
      ((%pst< pa pb) #t)
      ((%pst< pb pa) #f)
      (#t (let ((c (%pst-strcmp (%pst-comm a) (%pst-comm b))))
            (if (eq? c 0) (%pst< (%pst-uid a) (%pst-uid b)) (%pst< c 0)))))))

; N a child of P, but P's own: Darwin's kernel_task is its own parent
(def %pst-kid (fn (_ n p kids) (if (%pst= (%pst-pid n) p) kids (pair n kids))))

; the nodes in that order as runs of one parent, ((PPID . CHILDREN) ...)
(def %pst-runs
  (fn (_ l)
    (def done (fn (_ p kids acc) (if (null? p) acc (pair (pair p (reverse kids)) acc))))
    (let go ((l l) (p ()) (kids ()) (acc ()))
      (match
        ((null? l) (reverse (done p kids acc)))
        ((if (null? p) #f (%pst= (%pst-ppid (first l)) p)) (go (rest l) p (%pst-kid (first l) p kids) acc))
        (#t (let ((q (%pst-ppid (first l))))
              (go (rest l) q (%pst-kid (first l) q ()) (done p kids acc))))))))

; a parent the table only names, find_proc's ?
(def %pst-orphan (fn (_ r) (list (first r) 0 0 "?" (list (rest r)))))

; each node given its children, a merge of the nodes by id with the runs by
; parent; answers the ?s for the runs whose parent is no node
(def %pst-table
  (fn (_ nodes)
    (def runs (%pst-runs (List sort %pst-before? nodes)))
    (let go ((ns (List sort (fn (_ a b) (%pst< (%pst-pid a) (%pst-pid b))) nodes)) (rs runs) (orphans ()))
      (match
        ((null? rs) orphans)
        ((null? ns) (go ns (rest rs) (pair (%pst-orphan (first rs)) orphans)))
        ((%pst< (%pst-pid (first ns)) (first (first rs))) (go (rest ns) rs orphans))
        ((%pst< (first (first rs)) (%pst-pid (first ns))) (go ns (rest rs) (pair (%pst-orphan (first rs)) orphans)))
        (#t (do (set-first! (%pst-kids-cell (first ns)) (rest (first rs)))
                (go (rest ns) (rest rs) orphans)))))))

; find_proc: PID's node, or the ? of a parent the table only names, else nil
(def %pst-find
  (fn (_ nodes orphans pid)
    (def hit (List find (fn (_ n) (%pst= (%pst-pid n) pid)) nodes))
    (if (null? hit) (List find (fn (_ n) (%pst= (%pst-pid n) pid)) orphans) hit)))

; --- the drawing -----------------------------------------------------------------

; the drawing's state: -p, the width, the column and the line's pieces
(def %pst-pids? #f)
(def %pst-width 80)
(def %pst-col 0)
(def %pst-pieces ())

; out_string: the column counts every byte, the one at the width shows +,
; and those past it nothing
(def %pst-out
  (fn (_ s)
    (def room (- %pst-width %pst-col))
    (def n (byte-len s))
    (set! %pst-col (+ %pst-col n))
    (match
      ((< n room) (set! %pst-pieces (pair s %pst-pieces)))
      ((> room 0) (set! %pst-pieces (pair "+" (pair (substring s 0 (- room 1)) %pst-pieces))))
      (#t ()))))

(def %pst-newline
  (fn (_)
    (file-write 1 (string-concat (reverse (pair "\n" %pst-pieces))))
    (set! %pst-col 0)
    (set! %pst-pieces ())
    (cu-sweep-tick! cu-sweep-lines)))

(def %pst-spaces (fn (_ n) (string-concat (List map (fn (_ i) " ") (List range 0 n)))))

; out_args: a backslash doubled, a byte outside the printable ASCII as \OOO;
; answers the bytes written
(def %pst-out-args
  (fn (_ s)
    (def n (byte-len s))
    (def piece
      (fn (_ i b)
        (match
          ((= b 92) "\\\\")
          ((if (>= b 32) (< b 127) #f) (substring s i (+ i 1)))
          (#t (string-concat (list "\\" (cu-int->str (cal/ b 64)) (cu-int->str (& (cal/ b 8) 7)) (cu-int->str (& b 7))))))))
    (def pieces
      (let go ((i 0) (acc ()))
        (if (>= i n) (reverse acc)
          (go (+ i 1) (pair (piece i (+ 0 (byte-at s i))) acc)))))
    (def out (string-concat pieces))
    (%pst-out out)
    (byte-len out)))

; tree_equal: the same names, the same ids under -p, and the same children
(def %pst-same?
  (fn (self a b)
    (match
      ((not (string=? (%pst-comm a) (%pst-comm b))) #f)
      ((if %pst-pids? (not (= (%pst-pid a) (%pst-pid b))) #f) #f)
      (#t (let go ((ca (%pst-children a)) (cb (%pst-children b)))
            (match
              ((null? ca) (null? cb))
              ((null? cb) #f)
              ((self (first ca) (first cb)) (go (rest ca) (rest cb)))
              (#t #f)))))))

; the children as dump_tree takes them: each with the count of the later
; ones whose trees are its own, which it draws for them.  Those share its
; name, and the order keeps a name's children together.
(def %pst-groups
  (fn (self kids)
    (if (null? kids) () (%pst-group self (first kids) (rest kids)))))

(def %pst-group
  (fn (_ groups h others)
    (def name (%pst-comm h))
    (def run (List take-while (fn (_ k) (string=? (%pst-comm k) name)) others))
    (def same (List filter (fn (_ k) (%pst-same? h k)) run))
    (def apart (List reject (fn (_ k) (%pst-same? h k)) run))
    (pair (pair h (length same)) (groups (append apart (List drop (length run) others))))))

; dump_tree: NODE at LEVEL, drawn REP times over, LEAF when it starts its
; parent's line, LAST when no sibling follows, CLOSING the ]s it owes; ANC
; the (WIDTH . MORE) of each level above, the nearest first
(def %pst-dump
  (fn (self node level rep leaf last closing anc)
    (unless leaf
      (let go ((ls (reverse anc)) (lvl 0))
        (unless (null? ls)
          (%pst-out (%pst-spaces (+ (first (first ls)) 1)))
          (%pst-out (if (= lvl (- level 1)) (if last "`-" "|-")
                      (if (rest (first (rest ls))) "| " "  ")))
          (go (rest ls) (+ lvl 1)))))
    (def add (if (> rep 1) (let ((s (string-append (cu-int->str rep) "*["))) (do (%pst-out s) (byte-len s))) 0))
    (def name-len (+ (%pst-out-args (%pst-comm node))
                     (if %pst-pids?
                       (let ((s (string-concat (list "(" (cu-int->str (%pst-pid node)) ")"))))
                         (do (%pst-out s) (byte-len s)))
                       0)))
    (def kids (%pst-children node))
    (when (null? kids)
      (%pst-out (string-concat (List map (fn (_ i) "]") (List range 0 closing))))
      (%pst-newline))
    (def here (pair (+ name-len add) (not last)))
    (if (>= %pst-col %pst-width) (%pst-newline)
      (let go ((gs (%pst-groups kids)) (first? #t))
        (unless (null? gs)
          (when first? (%pst-out (if (null? (rest gs)) "---" "-+-")))
          (self (first (first gs)) (+ level 1) (+ (rest (first gs)) 1) first? (null? (rest gs))
                (+ closing (if (> (rest (first gs)) 0) 1 0)) (pair here anc))
          (go (rest gs) #f))))))

; dump_by_user: each tree under NODE whose top UID owns; answers DONE, true
; once one is drawn
(def %pst-by-user
  (fn (self node uid done)
    (if (= (%pst-uid node) uid)
      (do (when done (file-write 1 "\n"))
          (%pst-dump node 0 1 #t #t 0 ())
          #t)
      (List fold (fn (_ d k) (self k uid d)) done (%pst-children node)))))

; --- the applet ------------------------------------------------------------------

; xatoi on a word that starts with a digit
(def %pst-number
  (fn (_ s)
    (def n (byte-len s))
    (def digits (let go ((i 0)) (if (if (< i n) (if (>= (byte-at s i) #\0) (<= (byte-at s i) #\9) #f) #f) (go (+ i 1)) i)))
    (def zeros (let go ((i 0)) (if (if (< i (- n 1)) (= (byte-at s i) #\0) #f) (go (+ i 1)) i)))
    (when (if (< digits n) #t (> (- n zeros) 10)) (%pst-die (string-concat (list "invalid number '" s "'"))))
    (def v (List fold (fn (_ a i) (+ (* a 10) (- (byte-at s i) #\0))) 0 (List range zeros n)))
    (when (> v 4294967295) (%pst-die (string-concat (list "invalid number '" s "'"))))
    (when (> v 2147483647) (%pst-die (string-concat (list "number " s " is not in 0..2147483647 range"))))
    v))

(def %pst-main
  (fn (_ argv)
    (def o (cu-opts "pstree" argv))
    (def ops (Opts operands o))
    (when (> (length ops) 1) (Err raise (lit pstree-usage) "usage" ()))
    (def m (Term measure 0))
    (def width (vi-dim (if (pair? m) (first m) 0) (sys-getenv "COLUMNS") 80))
    (def arg (if (null? ops) () (first ops)))
    (def digit? (if (null? arg) #f (if (> (byte-len arg) 0) (if (>= (byte-at arg 0) #\0) (<= (byte-at arg 0) #\9) #f) #f)))
    (def pid (if digit? (%pst-number arg) 1))
    (def uid (if (if (null? arg) #t digit?) 0
               (let ((u (sys-user-id arg))) (if (null? u) (%pst-die (string-append "unknown user " arg)) u))))
    (def nodes (%pst-scan))
    (def orphans (%pst-table nodes))
    (set! %pst-pids? (Opts on? o "-p"))
    (set! %pst-width width)
    (set! %pst-col 0)
    (set! %pst-pieces ())
    (if (= uid 0)
      (let ((top (%pst-find nodes orphans pid)))
        (unless (null? top) (%pst-dump top 0 1 #t #t 0 ())))
      (let ((top (%pst-find nodes orphans 1)))
        (unless (if (null? top) #f (%pst-by-user top uid #f))
          (%pst-die "no processes found"))))
    0))

(def cu-pstree
  (fn (_ argv stdin-thunk)
    (guard (e (match ((eq? (cu-err-label e) (lit pstree-usage)) (cu-usage "pstree"))
                     ((eq? (cu-err-label e) (lit pstree)) 1)
                     (#t (error e))))
      (%pst-main argv))))

(provide cu/pstree cu-pstree)

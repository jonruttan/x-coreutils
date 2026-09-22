; # x-coreutils -- the small tools, as applets
;
; ## cu/perm.x -- the permission and link half of the parity set
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; chmod chown chgrp ln link readlink realpath mkfifo df sync.  Every
; applet here rides a door x-lang opened for this bundle (PR #607);
; none of them existed while the tool tier could only read and write.

; --- the mode, read two ways --------------------------------------------------

(def %cu-octal->int
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i acc)
        (if (>= i end) acc
          (let ((b (byte-at s i)))
            (if (if (>= b 48) (<= b 55) #f)
              (self (+ i 1) (+ (* acc 8) (- b 48)))
              acc)))))
    (go 0 0)))

(def %cu-octal-mode?
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i)
        (if (>= i end) (> end 0)
          (let ((b (byte-at s i)))
            (if (if (>= b 48) (<= b 55) #f) (self (+ i 1)) #f)))))
    (go 0)))

; A symbolic mode is clauses separated by commas, each of them
;
;   [ugoa]* ( OP [rwxXst]* | OP [ugo] )+        OP := + - =
;
; The who says which triples a clause touches; left out, it touches all three,
; and then what + and = grant is what the umask does not hold (cu/prims.x reads
; it): `chmod +w` under a umask of 022 grants w to the user alone.
;
; s is the setuid bit with u and the setgid bit with g, t the sticky bit with o;
; = clears the special bit of each class it names.  X is x, but only where an
; execute bit is already set or the path is a directory.  A perm of u, g or o
; is that class's permissions as they stand, copied to the who's triples.
(def %cu-mode-triples
  (fn (_ c)
    (match
      ((= c 117) 448)                                          ; u: 0700
      ((= c 103) 56)                                           ; g: 0070
      ((= c 111) 7)                                            ; o: 0007
      ((= c 97) 511)                                           ; a: 0777
      (#t 0))))

; the special bits the classes in a triple mask own: setuid for u, setgid for
; g, sticky for o
(def %cu-mode-specials
  (fn (_ who)
    (bit-or (if (= (bit-and who 448) 0) 0 2048)
      (bit-or (if (= (bit-and who 56) 0) 0 1024)
        (if (= (bit-and who 7) 0) 0 512)))))

; the letters of a clause's who: (TRIPLES LEFT-OUT? NEXT)
(def %cu-mode-who-at
  (fn (self s i acc)
    (if (if (< i (byte-len s)) (> (%cu-mode-triples (byte-at s i)) 0) #f)
      (self s (+ i 1) (bit-or acc (%cu-mode-triples (byte-at s i))))
      (list (if (= acc 0) 511 acc) (= acc 0) i))))

(def %cu-mode-op? (fn (_ c) (if (= c 43) #t (if (= c 45) #t (= c 61)))))

; A perm run from I: the bits it names, spread over all three triples, and
; where it ends.  CURRENT and DIR? decide X, and a lone u, g or o copies that
; class as it stands.  Answers (BITS SPECIALS NEXT), or nil when a letter is
; none of the perms.
(def %cu-mode-perms
  (fn (_ s i current dir?)
    (if (%cu-mode-copy? s i)
      (let ((triple (%cu-mode-copied s i current)))
        (list (bit-or triple (bit-or (bit-shl triple 3) (bit-shl triple 6))) 0
          (+ i 1)))
      (%cu-mode-perm-run s i current dir? 0 0))))

; a perm run that is one of u, g or o, and nothing else
(def %cu-mode-copy?
  (fn (_ s i)
    (if (< i (byte-len s))
      (if (if (= (byte-at s i) 117) #t
            (if (= (byte-at s i) 103) #t (= (byte-at s i) 111)))
        (if (= (+ i 1) (byte-len s)) #t
          (let ((c (byte-at s (+ i 1))))
            (if (%cu-mode-op? c) #t (= c 44))))                 ; , ends a clause
        #f)
      #f)))

; the three bits the named class holds in CURRENT, at the low end
(def %cu-mode-copied
  (fn (_ s i current)
    (match
      ((= (byte-at s i) 117) (bit-and (bit-shr current 6) 7))
      ((= (byte-at s i) 103) (bit-and (bit-shr current 3) 7))
      (#t (bit-and current 7)))))

(def %cu-mode-perm-run
  (fn (self s i current dir? bits specials)
    (if (>= i (byte-len s)) (list bits specials i)
      (let ((c (byte-at s i)))
        (match
          ((= c 114) (self s (+ i 1) current dir? (bit-or bits 292) specials))
          ((= c 119) (self s (+ i 1) current dir? (bit-or bits 146) specials))
          ((= c 120) (self s (+ i 1) current dir? (bit-or bits 73) specials))
          ; X is x where one is set already, or on a directory
          ((= c 88)
            (self s (+ i 1) current dir?
              (if (if dir? #t (not (= (bit-and current 73) 0)))
                (bit-or bits 73) bits)
              specials))
          ((= c 115) (self s (+ i 1) current dir? bits (bit-or specials 3072)))
          ((= c 116) (self s (+ i 1) current dir? bits (bit-or specials 512)))
          ((%cu-mode-op? c) (list bits specials i))
          (#t ()))))))

; One clause applied to a mode: its who, then each op and the perms after it.
; What + and = grant a who that was left out is what the umask does not hold,
; which is chmod's rule; what - takes away is not masked.
(def %cu-apply-symbolic
  (fn (_ spec mode dir? umask)
    (let ((w (%cu-mode-who-at spec 0 0)))
      (%cu-apply-ops spec (%cu-nth 2 w) (first w) mode dir?
        (if (%cu-nth 1 w) (bit-xor (bit-and umask 511) 4095) 4095)))))

(def %cu-apply-ops
  (fn (self spec i who mode dir? grant)
    (if (>= i (byte-len spec)) mode
      (let ((op (byte-at spec i)))
        (let ((p (%cu-mode-perms spec (+ i 1) mode dir?)))
          (if (null? p) mode
            (let ((bits (bit-and (first p) who))
                  (specials (bit-and (%cu-nth 1 p) (%cu-mode-specials who))))
              (self spec (%cu-nth 2 p) who
                (match
                  ((= op 43)
                    (bit-or mode (bit-and (bit-or bits specials) grant)))
                  ((= op 45)
                    (bit-and mode (bit-xor (bit-or bits specials) 4095)))
                  (#t
                    (bit-or
                      (bit-and mode
                        (bit-xor (bit-or who (%cu-mode-specials who)) 4095))
                      (bit-and (bit-or bits specials) grant))))
                dir? grant))))))))

(def %cu-mode-of
  (fn (_ spec current dir? umask)
    (if (%cu-octal-mode? spec) (%cu-octal->int spec)
      (%cu-mode-clauses (%cu-split-byte spec 44) current dir? umask))))  ; ,

(def %cu-mode-clauses
  (fn (self cs mode dir? umask)
    (if (null? cs) mode
      (self (rest cs) (%cu-apply-symbolic (first cs) mode dir? umask)
        dir? umask))))

; Is SPEC a mode: octal digits, or clauses this grammar reads whole?  chmod
; refuses anything else before it touches a path, and so does this.
(def %cu-mode-valid?
  (fn (_ spec)
    (if (%cu-octal-mode? spec) #t
      (if (= (byte-len spec) 0) #f
        (%cu-mode-clauses-valid? (%cu-split-byte spec 44))))))

(def %cu-mode-clauses-valid?
  (fn (self cs)
    (if (null? cs) #t
      (if (%cu-mode-clause-valid? (first cs)) (self (rest cs)) #f))))

(def %cu-mode-clause-valid?
  (fn (_ c)
    (let ((w (%cu-mode-who-at c 0 0)))
      (if (>= (%cu-nth 2 w) (byte-len c)) #f        ; a who and no op at all
        (%cu-mode-ops-valid? c (%cu-nth 2 w) #f)))))

(def %cu-mode-ops-valid?
  (fn (self c i any)
    (if (>= i (byte-len c)) any
      (if (not (%cu-mode-op? (byte-at c i))) #f
        (let ((p (%cu-mode-perms c (+ i 1) 0 #f)))
          (if (null? p) #f (self c (%cu-nth 2 p) #t)))))))

; A directory keeps its setuid and setgid bits through a mode that does not
; name them -- an octal mode of fewer than five digits, or a clause with no s --
; which is what chmod does; a file keeps neither.
(def %cu-mode-keep-setid
  (fn (_ spec new current dir?)
    (if (if dir? (not (%cu-mode-names-setid? spec)) #f)
      (bit-or new (bit-and current 3072))
      new)))

(def %cu-mode-names-setid?
  (fn (_ spec)
    (if (%cu-octal-mode? spec) (>= (byte-len spec) 5)
      (%cu-byte-in? spec 115 0))))                              ; s

; --- chmod --------------------------------------------------------------------

; -c reports each path that changed and -v every path, and whichever came later
; wins.  -f keeps the complaints off stderr; the reports still go to stdout and
; the status still says a path failed.  How a run reports rides the walk as
; (VERBOSITY . QUIET?), VERBOSITY one of off, changes, all -- chmod, chown and
; chgrp all read their three flags this way.
(def %cu-report-how
  (fn (_ o)
    (let ((v (%cu-last-given o (list "-c" "-v"))))
      (pair (match
              ((null? v) (lit off))
              ((string=? v "-c") (lit changes))
              (#t (lit all)))
        (Opts on? o "-f")))))

; a mode as the reports show it: 0644 (rw-r--r--)
(def %cu-chmod-shown
  (fn (_ mode)
    (string-concat (list (%cu-mode-octal4 mode) " (" (%cu-perm-places mode) ")"))))

(def %cu-report-complain
  (fn (_ how applet line)
    (if (rest how) ()
      (file-write 2 (string-concat (list applet ": " line "\n"))))))

; a path chmod could not reach: the complaint, and under -v a report saying so.
; Answers the failing status.
(def %cu-chmod-unreached
  (fn (_ how path line)
    (do (%cu-report-complain how "chmod" line)
        (if (eq? (first how) (lit all))
          (display (string-concat (list "'" path "' could not be accessed\n")))
          ())
        1)))

; why PATH could not be read, in chmod's words; a link to nothing is named as one
(def %cu-chmod-stat-failure
  (fn (_ path e)
    (if (if (eq? (file-err-sym e) (lit enoent))
          (eq? (file-lstat-kind path) (lit link))
          #f)
      (string-concat (list "cannot operate on dangling symlink '" path "'"))
      (string-concat (list "cannot access '" path "': " (file-err-text e))))))

; Did the mode change?  A system may drop a setuid, setgid or sticky bit without
; failing the call, so a mode that asks for one is read back rather than trusted.
(def %cu-chmod-changed?
  (fn (_ how path old new)
    (if (= (bit-and new 3584) 0) (not (= old new))              ; 07000
      (let ((st (file-or-err (fn (_) (file-stat path)))))
        (if (Err err? st)
          (do (%cu-report-complain how "chmod"
                (string-concat
                  (list "getting new attributes of '" path "': " (file-err-text st))))
              #f)
          (not (= old (bit-and (%cu-stat-get st (lit mode)) 4095))))))))

; -c reports a change; -v a change, a failure, or a mode kept as it was
(def %cu-chmod-report
  (fn (_ how path old new failed?)
    (if (eq? (first how) (lit off)) ()
      (let ((changed? (if failed? #f (%cu-chmod-changed? how path old new))))
        (match
          (changed?
            (display (string-concat
                       (list "mode of '" path "' changed from " (%cu-chmod-shown old)
                             " to " (%cu-chmod-shown new) "\n"))))
          ((not (eq? (first how) (lit all))) ())
          (failed?
            (display (string-concat
                       (list "failed to change mode of '" path "' from "
                             (%cu-chmod-shown old) " to " (%cu-chmod-shown new) "\n"))))
          (#t
            (display (string-concat
                       (list "mode of '" path "' retained as " (%cu-chmod-shown new)
                             "\n")))))))))

; One path: its mode set and reported, then under -R the entries of a directory,
; read after the mode is set, as chmod reads them.  Answers 1 when anything along
; the way failed, else 0.
(def %cu-chmod-one
  (fn (_ how spec path recurse? umask)
    (let ((st (file-or-err (fn (_) (file-stat path)))))
      (if (Err err? st)
        (%cu-chmod-unreached how path (%cu-chmod-stat-failure path st))
        (let ((old (bit-and (%cu-stat-get st (lit mode)) 4095))
              (dir? (eq? (%cu-stat-get st (lit kind)) (lit dir))))
          (let ((new (%cu-mode-keep-setid spec
                       (%cu-mode-of spec old dir? umask) old dir?)))
            (let ((r (file-or-err (fn (_) (file-chmod path new)))))
              (do (if (Err err? r)
                    (%cu-report-complain how "chmod"
                      (string-concat
                        (list "changing permissions of '" path "': " (file-err-text r))))
                    ())
                  (%cu-chmod-report how path old new (Err err? r))
                  (%cu-max-status (if (Err err? r) 1 0)
                    (if (if recurse? (eq? (%cu-stat-get st (lit kind)) (lit dir)) #f)
                      (%cu-chmod-kids how spec path umask)
                      0))))))))))

(def %cu-chmod-kids
  (fn (_ how spec dir umask)
    (let ((names (file-or-err (fn (_) (%cu-walk-names dir)))))
      (if (Err err? names)
        (%cu-chmod-unreached how dir
          (string-concat
            (list "cannot read directory '" dir "': " (file-err-text names))))
        (%cu-walk-worst names
          (fn (_ n) (%cu-chmod-one how spec (%cu-path-join dir n) #t umask))
          0)))))

(def %cu-chmod
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "chmod" argv))
    (def ops (Opts operands o))
    (match
      ((null? (rest ops))
        (do (file-write 2 "chmod: need MODE and a path\n") 1))
      ((not (%cu-mode-valid? (first ops)))
        (do (file-write 2
              (string-concat
                (list "chmod: invalid mode: '" (first ops) "'\n")))
            1))
      (#t
        (let ((how (%cu-report-how o)) (r? (Opts on? o "-R")) (spec (first ops))
              (umask (sys-umask)))
          (%cu-walk-worst (rest ops)
            (fn (_ p) (%cu-chmod-one how spec p r? umask))
            0))))))

; --- chown, chgrp -------------------------------------------------------------

; chown takes OWNER[:[GROUP]] and chgrp a GROUP.  Each half is a name the
; system knows or a number, and +N is always a number; an empty half, and -1,
; leave that id alone.  OWNER: is the owner and the owner's login group, which
; a numeric OWNER has none of.  OWNER.GROUP is read as OWNER:GROUP, with the
; warning chown gives, where the whole of it names no user.  A name the system
; does not know refuses the spec.
;
; A spec comes to (UID GID USER GROUP): the ids, and what a report shows for
; them, nil for a half not asked for.  A half written as a name is shown as
; written, one written as a number as its digits; where the group is a name and
; the owner is not, chown shows the owner as nothing -- its reports do.

; S's digits as a number, or nil where S is empty or holds anything else
(def %cu-chown-number
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i acc)
        (if (>= i end) acc
          (let ((b (byte-at s i)))
            (if (if (>= b 48) (<= b 57) #f)
              (self (+ i 1) (+ (* acc 10) (- b 48)))
              ())))))
    (if (= end 0) () (go 0 0))))

; a half, (ID . NAME): the id and the name as written, NAME nil for a number;
; (-1) for an empty half, and nil for one that is neither
(def %cu-chown-half
  (fn (_ s by-name)
    (match
      ((= (byte-len s) 0) (pair (- 0 1) ()))
      ((= (byte-at s 0) 43)                                           ; +
        (let ((n (%cu-chown-number (substring s 1 (byte-len s)))))
          (if (null? n) () (pair n ()))))
      (#t
        (let ((id (by-name s)))
          (if (null? id)
            (let ((n (%cu-chown-number s))) (if (null? n) () (pair n ())))
            (pair id s)))))))

; the index of the first B in S, or nil
(def %cu-byte-index
  (fn (_ s b)
    (def end (byte-len s))
    (def go
      (fn (self i)
        (match ((>= i end) ()) ((= (byte-at s i) b) i) (#t (self (+ i 1))))))
    (go 0)))

; (UID GID USER GROUP) from the two halves' ids and names; BLANK? is chown's
; rule that a group named by name shows an owner not named by name as nothing
(def %cu-chown-ids
  (fn (_ uid gid uname gname blank?)
    (let ((un (if (if blank? (null? uname) #f) (if (null? gname) () "") uname)))
      (list uid gid
            (if (null? un) (if (< uid 0) () (%cu-int->str uid)) un)
            (if (null? gname) (if (< gid 0) () (%cu-int->str gid)) gname)))))

; chown's spec, split at the index AT, nil for no split: the ids, or the
; complaint that refuses it
(def %cu-chown-split
  (fn (_ spec at)
    (def u (if (null? at) spec (substring spec 0 at)))
    (def g (if (null? at) "" (substring spec (+ at 1) (byte-len spec))))
    (def uh (%cu-chown-half u sys-user-id))
    (def login? (if (null? at) #f (if (= (byte-len g) 0) (> (byte-len u) 0) #f)))
    (def gh
      (match
        ((not login?) (%cu-chown-half g sys-group-id))
        ((null? uh) ())
        ((null? (rest uh)) ())
        (#t (let ((gid (sys-user-group (rest uh))))
              (if (null? gid) () (pair gid (sys-group-name gid)))))))
    (match
      ((null? uh) (string-concat (list "invalid user: '" spec "'")))
      ((if login? (null? (rest uh)) #f) (string-concat (list "invalid spec: '" spec "'")))
      ((null? gh) (string-concat (list "invalid group: '" spec "'")))
      (#t (%cu-chown-ids (first uh) (first gh) (rest uh) (rest gh) #t)))))

(def %cu-chown-spec
  (fn (_ spec)
    (let ((colon (%cu-byte-index spec 58)))                               ; :
      (if (not (null? colon)) (%cu-chown-split spec colon)
        (let ((whole (%cu-chown-split spec ()))
              (dot (%cu-byte-index spec 46)))                             ; .
          (if (if (pair? whole) #t (null? dot)) whole
            (let ((split (%cu-chown-split spec dot)))
              (do (if (pair? split)
                    (file-write 2
                      (string-concat
                        (list "chown: warning: '.' should be ':': '" spec "'\n")))
                    ())
                  (if (pair? split) split whole)))))))))

(def %cu-chgrp-spec
  (fn (_ spec)
    (let ((gh (%cu-chown-half spec sys-group-id)))
      (if (null? gh) (string-concat (list "invalid group: '" spec "'"))
        (%cu-chown-ids (- 0 1) (first gh) () (rest gh) #f)))))

; -c reports each path whose ids changed and -v every path, as chmod's do,
; and -f keeps the complaints off stderr while the status still says a path
; failed.  The reports are chown's and chgrp's own words, with the ids where
; those name a user and a group.
;
; -R descends, and -h changes the LINK rather than what it points at.  A plain
; chown follows a link.  What -R does with one is the last of -H, -L and -P:
;
;   -P   the link itself changes and no link is traversed -- the default
;   -H   what the link points at changes, and a link NAMED on the command
;        line is traversed
;   -L   what it points at changes, and every link to a directory is traversed
;
; -h still says the link itself changes, -L or no -L, so `-R -L -h` walks
; through a link and changes the link.  Without -R the three say nothing.

; an owner and a group as a report joins them, or whichever one there is
(def %cu-chown-join
  (fn (_ u g)
    (match ((null? u) g) ((null? g) u) (#t (string-concat (list u ":" g))))))

; the ids asked for, as a report shows them
(def %cu-chown-asked
  (fn (_ ids) (%cu-chown-join (%cu-nth 2 ids) (%cu-nth 3 ids))))

; the ids a path has, as a report shows them beside the ones asked for: the
; same halves, by the names the system has for them, or their numbers
(def %cu-chown-had
  (fn (_ ids st)
    (%cu-chown-join
      (if (null? (%cu-nth 2 ids)) ()
        (let ((uid (%cu-stat-get st (lit uid))))
          (let ((n (sys-user-name uid))) (if (null? n) (%cu-int->str uid) n))))
      (if (null? (%cu-nth 3 ids)) ()
        (let ((gid (%cu-stat-get st (lit gid))))
          (let ((n (sys-group-name gid))) (if (null? n) (%cu-int->str gid) n)))))))

; whether the ids asked for differ from the ones the path has
(def %cu-chown-changes?
  (fn (_ ids st)
    (if (if (< (first ids) 0) #f (not (= (first ids) (%cu-stat-get st (lit uid)))))
      #t
      (if (< (%cu-nth 1 ids) 0) #f
        (not (= (%cu-nth 1 ids) (%cu-stat-get st (lit gid))))))))

; what a report calls the change: ownership where it shows an owner, group
; where it shows only a group
(def %cu-chown-what
  (fn (_ ids)
    (if (if (null? (%cu-nth 2 ids)) (not (null? (%cu-nth 3 ids))) #f)
      "group" "ownership")))

; and what a complaint calls it: ownership where an owner was asked for
(def %cu-chown-changing
  (fn (_ ids) (if (< (first ids) 0) "group" "ownership")))

; a path that could not be read: the complaint LINE says which way it failed,
; and under -v the report chown makes when it names no ids it came from
(def %cu-chown-unreached
  (fn (_ how applet ids path line)
    (do (%cu-report-complain how applet line)
        (%cu-chown-failed-to how ids path)
        1)))

(def %cu-chown-failed-to
  (fn (_ how ids path)
    (if (eq? (first how) (lit all))
      (let ((new (%cu-chown-asked ids)))
        (display
          (string-concat
            (if (null? new) (list "failed to change " (%cu-chown-what ids) " of '" path "'\n")
              (list "failed to change " (%cu-chown-what ids) " of '" path
                    "' to " new "\n")))))
      ())))

; -c reports a change; -v a change, a failure, or ids kept as they were.  OLD is
; the path's ids as the report shows them, and CHANGED? whether the ids asked
; for differ from them -- the ids decide, not how they are written.
(def %cu-chown-report
  (fn (_ how ids path old failed? changed?)
    (if (eq? (first how) (lit off)) ()
      (let ((all? (eq? (first how) (lit all)))
            (new (%cu-chown-asked ids))
            (what (%cu-chown-what ids)))
        (match
          ((if failed? #f changed?)
            (display
              (string-concat
                (list "changed " what " of '" path "' from " old " to " new "\n"))))
          ((not all?) ())
          (failed?
            (display
              (string-concat
                (if (null? new) (list "failed to change " what " of '" path "'\n")
                  (list "failed to change " what " of '" path "' from " old
                        " to " new "\n")))))
          ((null? new) (display (string-concat (list what " of '" path "' retained\n"))))
          (#t
            (display
              (string-concat (list what " of '" path "' retained as " old "\n")))))))))

; How a run treats what it walks: (RECURSE? LINKS -h?), LINKS one of none,
; args and all, from the last of -P, -H and -L given.  It rides every path of
; the walk, where `how` rides the reports.
(def %cu-chown-way
  (fn (_ o)
    (list (Opts on? o "-R") (%cu-chown-links o) (Opts on? o "-h"))))

(def %cu-chown-links
  (fn (_ o)
    (let ((v (%cu-last-given o (list "-H" "-L" "-P"))))
      (if (null? v) (lit none)
        (match
          ((string=? v "-H") (lit args))
          ((string=? v "-L") (lit all))
          (#t (lit none)))))))

; Whether the LINK itself is what changes: -h says so, and so does a -R that
; traverses no link -- chown's -P, and what it does when told nothing else.
; Without -R a link is followed, as a plain chown follows one.
(def %cu-chown-itself?
  (fn (_ way)
    (if (%cu-nth 2 way) #t
      (if (first way) (eq? (%cu-nth 1 way) (lit none)) #f))))

; and whether the walk goes through a link: -L through every one, -H through
; one named on the command line
(def %cu-chown-follows?
  (fn (_ way top?)
    (match
      ((eq? (%cu-nth 1 way) (lit all)) #t)
      ((eq? (%cu-nth 1 way) (lit args)) top?)
      (#t #f))))

; Whether the walk goes into PATH at all: a directory under -R, and a link
; only where -H or -L says so -- and then it is the directory the link points
; at that is walked, which is what file-dir? asks about.
(def %cu-chown-through?
  (fn (_ way top? path link? st)
    (if (not (first way)) #f
      (if link?
        (if (%cu-chown-follows? way top?) (file-dir? path) #f)
        (eq? (%cu-stat-get st (lit kind)) (lit dir))))))

; One path: under -R the entries of a directory FIRST, then the path itself --
; chown reads a directory before it changes it, where chmod sets the mode first.
; TOP? says the path was named on the command line, which -H asks about, and
; SEEN holds the directories the walk is already inside.  Answers 1 when
; anything along the way failed, else 0.
(def %cu-chown-one
  (fn (_ how applet ids path way top? seen)
    (let ((lst (file-or-err (fn (_) (file-lstat-wide path)))))
      (if (Err err? lst)
        (%cu-chown-unreached how applet ids path
          (string-concat
            (list "cannot access '" path "': " (file-err-text lst))))
        (%cu-chown-read how applet ids path way top? seen lst)))))

; The path read: a link whose referent is what changes is read through, and
; one pointing nowhere is complained about and reported with the ids it has of
; its own.  Every other path is read as it stands.
(def %cu-chown-read
  (fn (_ how applet ids path way top? seen lst)
    (let ((link? (eq? (%cu-stat-get lst (lit kind)) (lit link))))
      (if (if link? (not (%cu-chown-itself? way)) #f)
        (let ((st (file-or-err (fn (_) (file-stat-wide path)))))
          (if (Err err? st)
            (%cu-chown-dangling how applet ids path lst st)
            (%cu-chown-into how applet ids path way seen st
              (%cu-chown-through? way top? path #t st))))
        (%cu-chown-into how applet ids path way seen lst
          (%cu-chown-through? way top? path link? lst))))))

; a link that points nowhere, where what it points at is what would change:
; the complaint says which way it failed, and the report names the ids the
; link itself has
(def %cu-chown-dangling
  (fn (_ how applet ids path lst err)
    (do (%cu-report-complain how applet
          (string-concat
            (list "cannot dereference '" path "': " (file-err-text err))))
        (%cu-chown-report how ids path (%cu-chown-had ids lst) #t #f)
        1)))

; The entries of a path first, then the path itself.  A directory the walk is
; already inside is not entered again -- a link to one of its own parents ends
; the descent there, as chown ends it.
(def %cu-chown-into
  (fn (_ how applet ids path way seen st through?)
    (let ((id (if through? (%cu-chown-id path) ())))
      (let ((kids (if (if through? (not (%cu-chown-seen? id seen)) #f)
                    (%cu-chown-kids how applet ids path way (pair id seen))
                    0)))
        ; a directory whose entries could not be read is left as it is,
        ; as chown leaves it
        (if (eq? kids (lit unreadable))
          (do (%cu-chown-failed-to how ids path) 1)
          (%cu-max-status kids
            (%cu-chown-set how applet ids path st)))))))

; what a directory IS, through any link: the device and the inode, which is
; how the walk tells one it has already entered
(def %cu-chown-id
  (fn (_ path)
    (let ((st (file-stat-full path)))
      (if (null? st) (pair 0 0)
        (pair (%cu-stat-get st (lit dev)) (%cu-stat-get st (lit ino)))))))

(def %cu-chown-seen?
  (fn (self id seen)
    (if (null? seen) #f
      (if (if (= (first id) (first (first seen)))
            (= (rest id) (rest (first seen))) #f)
        #t
        (self id (rest seen))))))

; The ids set on one path and reported, the stat already read: answers 1 when
; the call failed.  A report names the ids the path had and the ones it was
; asked for, each as the spec shapes them.  A stat that is a link's own says
; the link itself is what was asked for, so lchown is the door.
(def %cu-chown-set
  (fn (_ how applet ids path st)
    (let ((r (if (eq? (%cu-stat-get st (lit kind)) (lit link))
               (%cu-chown-link path (first ids) (%cu-nth 1 ids))
               (file-or-err
                 (fn (_) (file-chown path (first ids) (%cu-nth 1 ids)))))))
      (do (if (Err err? r)
            (%cu-report-complain how applet
              (string-concat
                (list "changing " (%cu-chown-changing ids) " of '" path "': "
                      (file-err-text r))))
            ())
          (%cu-chown-report how ids path (%cu-chown-had ids st) (Err err? r)
            (%cu-chown-changes? ids st))
          (if (Err err? r) 1 0)))))

; the link itself, through the lchown door; where a libc has no lchown the path
; is refused rather than the target changed behind the caller's back, and the
; refusal travels as the io Err a failed call would, so the path is reported
; the way any other failure is
(def %cu-chown-link
  (fn (_ path u g)
    (let ((r (file-lchown path u g)))
      (if (null? r)
        (Err make (lit io) "lchown: this libc has no lchown"
          (list (pair (lit sym) (lit enotsup)) (pair (lit op) (lit lchown))))
        r))))

; the entries of DIR, each with the same ids; a directory that cannot be read
; is complained about and answers `unreadable`, which leaves it unchanged
(def %cu-chown-kids
  (fn (_ how applet ids dir way seen)
    (let ((names (file-or-err (fn (_) (%cu-walk-names dir)))))
      (if (Err err? names)
        (do (%cu-report-complain how applet
              (string-concat
                (list "cannot read directory '" dir "': "
                      (file-err-text names))))
            (lit unreadable))
        (%cu-walk-worst names
          (fn (_ n)
            ; an entry is not named on the command line, which is what -H
            ; asks about
            (%cu-chown-one how applet ids (%cu-path-join dir n) way #f seen))
          0)))))

; the first operand is the owner spec; the rest are the paths
(def %cu-chown-with
  (fn (_ ids paths o applet)
    (let ((how (%cu-report-how o))
          (way (%cu-chown-way o)))
      (%cu-walk-worst paths
        (fn (_ p) (%cu-chown-one how applet ids p way #t ()))
        0))))

(def %cu-chown
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "chown" argv))
    (def ops (Opts operands o))
    (if (null? (rest ops))
      (do (file-write 2 "chown: need OWNER and a path\n") 1)
      (%cu-chown-run (%cu-chown-spec (first ops)) (rest ops) o "chown"))))

(def %cu-chgrp
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "chgrp" argv))
    (def ops (Opts operands o))
    (if (null? (rest ops))
      (do (file-write 2 "chgrp: need GROUP and a path\n") 1)
      (%cu-chown-run (%cu-chgrp-spec (first ops)) (rest ops) o "chgrp"))))

; the spec's ids walked over the paths, or the complaint that refused the spec
; said, and nothing touched
(def %cu-chown-run
  (fn (_ ids paths o applet)
    (if (pair? ids) (%cu-chown-with ids paths o applet)
      (do (file-write 2 (string-concat (list applet ": " ids "\n"))) 1))))

; --- ln, link, readlink, realpath ---------------------------------------------

; ln moved to cu/fs.x with busybox's option set (-s -f -n -b -t -v).

(def %cu-basename-of
  (fn (_ p)
    (def end (byte-len p))
    (def go
      (fn (self i)
        (if (< i 0) p
          (if (= (byte-at p i) 47) (substring p (+ i 1) end)
            (self (- i 1))))))
    (go (- end 1))))

(def %cu-link
  (fn (_ argv stdin-thunk)
    (if (null? (rest argv))
      (do (file-write 2 "link: need TARGET and a name\n") 1)
      (do (file-link (first argv) (first (rest argv))) 0))))

(def %cu-dirname-of
  (fn (_ p)
    (def go
      (fn (self i)
        (if (< i 0) "."
          (if (= (byte-at p i) 47) (if (= i 0) "/" (substring p 0 i))
            (self (- i 1))))))
    (go (- (byte-len p) 1))))

; -n leaves the newline off; -v names what went wrong, where the plain
; form answers a non-link with a silent 1.
(def %cu-readlink
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "readlink" argv))
    (def f? (if (Opts on? o "-f") #t (Opts on? o "-e")))
    (def nl (if (Opts on? o "-n") "" "\n"))
    (def complain
      (fn (_ p why)
        (do (if (Opts on? o "-v")
              (file-write 2 (string-concat (list "readlink: " p ": " why "\n")))
              ())
            1)))
    (def ops (Opts operands o))
    (if (null? ops)
      (do (file-write 2 "readlink: missing operand\n") 1)
      (let ((p (first ops)))
        (match
          (f? (do (display (string-append (%cu-realpath-of p) nl)) 0))
          ((eq? (file-lstat-kind p) (lit link))
            (do (display (string-append (file-readlink p) nl)) 0))
          ((file-exists? p) (complain p "Invalid argument"))
          (#t (complain p "No such file or directory")))))))

; realpath: walk the segments, resolving every prefix that turns out to
; be a link.  A resolved link REPLACES what has been walked so far and
; the walk RESTARTS over it -- /tmp is a link to /private/tmp, so the
; prefix must be re-examined, not patched.  The fuel bounds a cycle.
(def %cu-path-parts
  (fn (_ p)
    (filter (fn (_ s) (> (byte-len s) 0)) (%cu-split-byte p 47))))

(def %cu-realpath-walk
  (fn (self parts acc fuel)
    (if (null? parts) (pair acc #t)
      (if (<= fuel 0) (pair acc #f)
        (let ((seg (first parts)))
          (if (string=? seg ".")
            (self (rest parts) acc fuel)
            (if (string=? seg "..")
              (self (rest parts) (if (null? acc) acc (rest acc)) fuel)
              (let ((here (string-append "/"
                            (%cu-join-with (reverse (pair seg acc)) "/"))))
                (if (eq? (file-lstat-kind here) (lit link))
                  (self
                    (append (%cu-path-parts (%cu-readlink-from here))
                      (rest parts))
                    () (- fuel 1))
                  (self (rest parts) (pair seg acc) fuel))))))))))

; a link's target as an ABSOLUTE path: a relative target is read
; against the directory the link itself sits in
(def %cu-readlink-from
  (fn (_ path)
    (let ((t (file-readlink path)))
      (if (= (byte-len t) 0) t
        (if (= (byte-at t 0) 47) t
          (%cu-path-join (%cu-dirname-of path) t))))))

(def %cu-realpath-of
  (fn (_ p)
    (def abs (if (= (byte-len p) 0) (sys-getcwd)
               (if (= (byte-at p 0) 47) p
                 (%cu-path-join (sys-getcwd) p))))
    (def r (%cu-realpath-walk (%cu-path-parts abs) () 64))
    (if (null? (first r)) "/"
      (string-append "/" (%cu-join-with (reverse (first r)) "/")))))

(def %cu-realpath
  (fn (_ argv stdin-thunk)
    (if (null? argv)
      (do (file-write 2 "realpath: missing operand\n") 1)
      (let ((go (fn (self ps st)
                  (if (null? ps) st
                    (if (not (file-exists? (first ps)))
                      (do (file-write 2
                            (string-concat
                              (list "realpath: " (first ps)
                                    ": No such file or directory\n")))
                          (self (rest ps) 1))
                      (do (display
                            (string-append (%cu-realpath-of (first ps)) "\n"))
                          (self (rest ps) st)))))))
        (go argv 0)))))

; --- mkfifo, df, sync ---------------------------------------------------------

(def %cu-mkfifo
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "mkfifo" argv))
    (def m (Opts value o "-m"))
    (def mode (if (null? m) 420 (%cu-octal->int m)))
    (def ops (Opts operands o))
    (if (null? ops)
      (do (file-write 2 "mkfifo: missing operand\n") 1)
      (let ((go (fn (self ps)
                  (if (null? ps) 0
                    (do (file-mkfifo (first ps) mode) (self (rest ps)))))))
        (go ops)))))

; df: one row per operand (the mount a path sits on) or, with none, one
; per mounted filesystem, in 1024-byte blocks.  The mount table is
; file-mounts'; a path is matched to its mount by the filesystem id
; statfs answers for it, so the row names the device and the mount
; point, as df's does.
;
; What a bare df lists is what df lists.  A mount of a dummy type
; (devfs, autofs, proc ...) is left out, as is one whose mount point
; shares its device with a shorter one -- APFS's firmlinked Data volume
; stats as the root's device -- and one with no blocks.  -a lists them
; all: the dummies with their counts, the duplicates with dashes, since
; df does not stat those.

; the unit a row counts in, in BYTES: 1024 by default and under -k,
; 1048576 under -m, and -B SIZE with a K, M, G or T after the number as
; df takes it.  -h formats the bytes instead of counting them.
(def %cu-df-unit
  (fn (_ o)
    (let ((b (Opts value o "-B")))
      (if (not (null? b))
        (let ((n (%cu-num-prefix b)))
          (def suffix
            (let ((go (fn (self i)
                        (if (>= i (byte-len b)) 0
                          (let ((c (byte-at b i)))
                            (if (if (>= c 48) (<= c 57) #f) (self (+ i 1)) c))))))
              (go 0)))
          (def bytes
            (* n (match
                   ((= suffix 75) 1024)                   ; K
                   ((= suffix 77) 1048576)                ; M
                   ((= suffix 71) 1073741824)             ; G
                   ((= suffix 84) 1099511627776)          ; T
                   (#t 1))))
          (if (< bytes 1) 1 bytes))
        (if (Opts on? o "-m") 1048576 1024)))))

; BYTES as a row shows them: -h through %ls-human, ls's -h formatter,
; else in the unit, rounded UP as df rounds -- 409K under -m is 1
(def %cu-df-show
  (fn (_ bytes o)
    (if (Opts on? o "-h") (%ls-human bytes)
      (%cu-int->str (let ((u (%cu-df-unit o)))
                      (let ((c (+ bytes (- u 1))))
                        (/ (- c (% c u)) u)))))))

; the heading names the unit: 1K-blocks, 1M-blocks, 2K-blocks,
; 512B-blocks
(def %cu-df-heading
  (fn (_ o)
    (let ((u (%cu-df-unit o)))
      (match
        ((= (% u 1073741824) 0)
          (string-append (%cu-int->str (/ u 1073741824)) "G-blocks"))
        ((= (% u 1048576) 0)
          (string-append (%cu-int->str (/ u 1048576)) "M-blocks"))
        ((= (% u 1024) 0)
          (string-append (%cu-int->str (/ u 1024)) "K-blocks"))
        (#t (string-append (%cu-int->str u) "B-blocks"))))))

; the types df calls dummies and leaves out of a plain listing
(def %cu-df-dummy-types
  (list "devfs" "autofs" "proc" "subfs" "debugfs" "devpts" "fusectl"
        "mqueue" "rpc_pipefs" "sysfs" "kernfs" "ignore" "none"))

; the mount table as (MOUNT DUP? DEV) rows: DEV the device its mount
; point stats as, DUP? whether an earlier or shorter mount point sits on
; the same device -- df folds those into the shorter one
(def %cu-df-mounts
  (fn (_)
    (def ms (file-mounts))
    (def dev-of
      (fn (_ m)
        (let ((st (file-stat-full (%cu-stat-get m (lit on)))))
          (if (null? st) (- 0 1) (%cu-stat-get st (lit dev))))))
    (def tagged (map (fn (_ m) (pair m (dev-of m))) ms))
    (def dup?
      (fn (_ m d i)
        (def on (byte-len (%cu-stat-get m (lit on))))
        (def go
          (fn (self xs j)
            (match
              ((null? xs) #f)
              ((not (= (rest (first xs)) d)) (self (rest xs) (+ j 1)))
              ((= j i) (self (rest xs) (+ j 1)))
              ((< (byte-len (%cu-stat-get (first (first xs)) (lit on))) on) #t)
              ((if (= (byte-len (%cu-stat-get (first (first xs)) (lit on))) on)
                 (< j i) #f)
                #t)
              (#t (self (rest xs) (+ j 1))))))
        (if (< d 0) #f (go tagged 0))))
    (def go
      (fn (self xs i acc)
        (if (null? xs) (reverse acc)
          (self (rest xs) (+ i 1)
            (pair (list (first (first xs))
                        (dup? (first (first xs)) (rest (first xs)) i)
                        (rest (first xs)))
                  acc)))))
    (go tagged 0 ())))

; a mount's counts: total, used, available and the percentage, as -i,
; -h and the unit ask for them.  Blocks go to 1024-byte units through
; the byte count, rounded UP as df rounds, so a block size under 1024
; (devfs's 512) is not zero; used counts from what is free to anyone,
; not from what a plain user may take; the percentage is of used plus
; available, rounded UP -- df's and busybox's rule both -- and a dash
; over nothing.  A duplicate is four dashes.
(def %cu-df-cells
  (fn (_ m o dup?)
    (def inodes? (Opts on? o "-i"))
    (def bsize (%cu-stat-get m (lit bsize)))
    ; counts in bytes, exact; the unit and -h are applied at the end
    (def total (if inodes? (%cu-stat-get m (lit files))
                 (* bsize (%cu-stat-get m (lit blocks)))))
    (def avail (if inodes? (%cu-stat-get m (lit ffree))
                 (* bsize (%cu-stat-get m (lit bavail)))))
    (def used (if inodes? (- total avail)
                (* bsize (- (%cu-stat-get m (lit blocks))
                            (%cu-stat-get m (lit bfree))))))
    (def pct (let ((d (+ used avail)))
               (if (= d 0) "-"
                 (let ((n (+ (* used 100) (- d 1))))
                   (string-append (%cu-int->str (/ (- n (% n d)) d)) "%")))))
    (def show (fn (_ v) (if inodes? (%cu-int->str v) (%cu-df-show v o))))
    (if dup? (list "-" "-" "-" "-")
      (list (show total) (show used) (show avail) pct))))

; the table: a column is as wide as its widest cell, its heading, or
; df's own floor for it -- the name fourteen, a count five, the
; percentage four -- with one space between and the last column
; unpadded.  LEFTS says which columns align left.
(def %cu-df-table
  (fn (_ header rows mins lefts)
    (def n (length header))
    (def width
      (fn (_ c)
        (def go
          (fn (self rs w)
            (if (null? rs) w
              (self (rest rs)
                (let ((l (byte-len (%cu-nth c (first rs))))) (if (> l w) l w))))))
        (go rows
          (let ((h (byte-len (%cu-nth c header))) (m (%cu-nth c mins)))
            (if (> h m) h m)))))
    (def ws
      (let ((go (fn (self c acc) (if (< c 0) acc (self (- c 1) (pair (width c) acc))))))
        (go (- n 1) ())))
    (def line
      (fn (_ cells)
        (def go
          (fn (self c acc)
            (if (>= c n) (string-concat (reverse acc))
              (let ((cell (%cu-nth c cells)) (w (%cu-nth c ws)))
                (self (+ c 1)
                  (pair (if (= c (- n 1)) cell
                          (string-append
                            (if (%cu-nth c lefts) (%cu-pad-right cell w)
                              (%cu-pad-left cell w))
                            " "))
                        acc))))))
        (string-append (go 0 ()) "\n")))
    (string-concat (map line (pair header rows)))))

; The mount a path sits on, from the (MOUNT DUP? DEV) rows: the listed
; one on the path's device -- the way df names /tmp on an APFS Data
; volume as the root it was folded into -- else the one whose id statfs
; answers for the path, else the path measured on its own, unnamed.
(def %cu-df-mount-of
  (fn (_ path marked)
    (let ((st (file-stat-full path)))
      (if (null? st) ()
        (let ((dev (%cu-stat-get st (lit dev)))
              (fs (file-statfs-full path)))
          (def by-dev
            (filter (fn (_ e) (if (%cu-nth 1 e) #f (= (%cu-nth 2 e) dev))) marked))
          (def by-id
            (filter (fn (_ e) (= (%cu-stat-get (first e) (lit fsid))
                                 (%cu-stat-get fs (lit fsid))))
              marked))
          (match
            ((pair? by-dev) (first (first by-dev)))
            ((pair? by-id) (first (first by-id)))
            (#t (append (list (pair (lit from) "-") (pair (lit on) path)) fs))))))))

; the heading, each column's floor, and which columns align left, as
; -T -i -h -P and the unit ask for them: (HEADER MINS LEFTS)
(def %cu-df-columns
  (fn (_ o)
    (def t? (Opts on? o "-T"))
    (def i? (Opts on? o "-i"))
    (def h? (Opts on? o "-h"))
    (def p? (Opts on? o "-P"))
    (list
      (append (list "Filesystem")
        (append (if t? (list "Type") ())
          (list (match (i? "Inodes") (h? "Size") (p? "1024-blocks")
                       (#t (%cu-df-heading o)))
                (if i? "IUsed" "Used")
                (match (i? "IFree") (h? "Avail") (#t "Available"))
                (match (i? "IUse%") (p? "Capacity") (#t "Use%"))
                "Mounted on")))
      (append (list 14) (append (if t? (list 4) ()) (list 5 5 5 4 0)))
      (append (list #t) (append (if t? (list #t) ()) (list #f #f #f #f #t))))))

; one mount's row: its name, its type under -T, the counts, the mount point
(def %cu-df-row
  (fn (_ m o dup?)
    (append (list (%cu-stat-get m (lit from)))
      (append (if (Opts on? o "-T")
                (list (if dup? "-" (%cu-stat-get m (lit typename))))
                ())
        (append (%cu-df-cells m o dup?)
          (list (%cu-stat-get m (lit on))))))))

; a plain df's entries from the table: without the dummies, the folded
; duplicates and the empty; -a takes them all
(def %cu-df-listed
  (fn (_ o marked)
    (def dummy?
      (fn (_ m) (%cu-member-s? (%cu-stat-get m (lit typename)) %cu-df-dummy-types)))
    (filter
      (fn (_ e)
        (match
          ((Opts on? o "-a") #t)
          ((%cu-nth 1 e) #f)
          ((dummy? (first e)) #f)
          (#t (> (%cu-stat-get (first e) (lit blocks)) 0))))
      marked)))

(def %cu-df
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "df" argv))
    (def ops (Opts operands o))
    (def marked (%cu-df-mounts))
    (def found (map (fn (_ p) (pair p (%cu-df-mount-of p marked))) ops))
    (def missing
      (map (fn (_ f) (first f)) (filter (fn (_ f) (null? (rest f))) found)))
    ; the rows: the operands' mounts, else the table's listing
    (def rows
      (if (pair? ops)
        (map (fn (_ f) (%cu-df-row (rest f) o #f))
          (filter (fn (_ f) (not (null? (rest f)))) found))
        (map (fn (_ e) (%cu-df-row (first e) o (%cu-nth 1 e)))
          (%cu-df-listed o marked))))
    (def cols (%cu-df-columns o))
    (do (%cu-print-lines-to 2
          (map (fn (_ p) (string-concat (list "df: " p ": No such file or directory")))
            missing))
        ; no table when nothing asked for could be found
        (if (if (pair? ops) (null? rows) #f) ()
          (display
            (%cu-df-table (first cols) rows (%cu-nth 1 cols) (%cu-nth 2 cols))))
        (if (null? missing) 0 1))))

; sync with no operand syncs everything. -d asks for a file's DATA and -f
; for the filesystem holding it; this has fsync and a whole-system sync,
; both of which are supersets of what is asked, so the guarantee each
; flag wants is met by doing more than it wants rather than less.  -f opens
; nothing, as sync opens nothing for it where there is no syncfs.  -d needs
; a file to sync, and does not go with -f.
(def %cu-sync
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "sync" argv))
    (def ops (Opts operands o))
    (match
      ((if (Opts on? o "-d") (Opts on? o "-f") #f)
        (%cu-sync-refused "cannot specify both --data and --file-system"))
      ((if (Opts on? o "-d") (null? ops) #f)
        (%cu-sync-refused "--data needs at least one argument"))
      ((if (null? ops) #t (Opts on? o "-f")) (do (sys-sync) 0))
      (#t (%cu-walk-worst ops (fn (_ p) (%cu-sync-one p)) 0)))))

(def %cu-sync-refused
  (fn (_ why)
    (do (file-write 2 (string-concat (list "sync: " why "\n"))) 1)))

; One file's data to disk: opened to read -- as a directory is too -- or,
; where it may not be read, to write, and fsync'd.  One that opens neither
; way is said with the reason reading gave, and fails.
(def %cu-sync-one
  (fn (_ path)
    (let ((fd (file-open-read path)))
      (if (>= fd 0) (%cu-sync-fd fd)
        (let ((why (file-open-err fd path)))
          (let ((wfd (file-open-wronly path)))
            (if (>= wfd 0) (%cu-sync-fd wfd)
              (do (file-write 2
                    (string-concat
                      (list "sync: error opening '" path "': "
                            (file-err-text why) "\n")))
                  1))))))))

(def %cu-sync-fd
  (fn (_ fd) (do (sys-fsync fd) (file-close fd) 0)))

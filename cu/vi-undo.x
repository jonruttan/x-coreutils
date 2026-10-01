; # x-coreutils -- the small tools, as applets
;
; ## cu/vi-undo.x -- vi's undo and its . command
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; u and ., each busybox's (editors/vi.c, with FEATURE_VI_UNDO, its queue,
; and FEATURE_VI_DOT_CMD).  Every change to the text says how it may be
; undone: not at all, on its own, chained to the change before it so one u
; takes both back, or queued, so a run of typing or backspacing comes back
; as one.  The change count busybox shows is the undo stack's height: each
; record pushed adds one, each popped takes one away.
;
; . replays the keys of the last command that changed the text: from the
; command's own key to the end of it, as typed, with its count before them.

; --- the undo stack ---------------------------------------------------------

; how a change may be undone, as the callers say it
(def %vi-no-undo 0)
(def %vi-allow-undo 1)
(def %vi-allow-undo-chain 2)
(def %vi-allow-undo-queued 3)

; the records' types: text put in, text taken out, either chained to the one
; below it, or either queued; and the queue's own states
(def %vi-u-ins 0)
(def %vi-u-del 1)
(def %vi-u-ins-chain 2)
(def %vi-u-del-chain 3)
(def %vi-u-ins-queued 4)
(def %vi-u-del-queued 5)
(def %vi-u-use-spos 32)
(def %vi-u-empty 64)
(def %vi-undo-queue-max 256)

(def %vi-undo-stack ())     ; newest first: (TYPE START LENGTH TEXT), TEXT a raw buffer
(def %vi-undo-q 0)          ; the bytes queued
(def %vi-undo-state 64)     ; what the queue holds: %vi-u-ins, %vi-u-del or empty
(def %vi-undo-spos 0)       ; where the queued change starts
(def %vi-undo-bytes ())     ; the bytes a queued deletion took, leftmost first

; busybox's vi_main: nothing to undo and nothing queued, once a run
(def %vi-undo-init!
  (fn (_)
    (set! %vi-undo-stack ())
    (set! %vi-undo-q 0)
    (set! %vi-undo-state %vi-u-empty)
    (set! %vi-undo-spos 0)
    (set! %vi-undo-bytes ())))

; busybox's flush_undo_data: a new text starts with nothing to undo
(def %vi-undo-flush! (fn (_) (set! %vi-undo-stack ())))

; busybox's undo_push: LEN bytes at SRC as a record of TYPE, or into the queue
(def %vi-undo-push!
  (fn (_ src len type)
    (match
      ((= type %vi-u-empty) ())
      ((= type %vi-u-del-queued) (%vi-undo-queue-del! src len))
      ((= type %vi-u-ins-queued) (%vi-undo-queue-ins! src len))
      ((if (= type %vi-u-del) #t (= type %vi-u-del-chain))
        (%vi-undo-record! src type (%vi-text-copy src (%vi-undo-del-len len))))
      (#t (%vi-undo-record! src type (pair "" len))))))

; a deletion of the whole text keeps one byte fewer: the newline an empty
; text gets back
(def %vi-undo-del-len (fn (_ len) (if (= len %vi-end) (%vi- len 1) len)))

; LEN bytes of the text from P, NUL and all: (BUFFER . LENGTH)
(def %vi-text-copy
  (fn (_ p len)
    (def n (%vi-max 0 (%vi-min len (%vi- %vi-room p))))
    (def s (%str-make-raw (%vi+ n 1)))
    (%cu-ptr-call %vi-c-memcpy (%vi-str->ptr s) (%vi+ %vi-taddr p) n)
    (pair s n)))

(def %vi-undo-record!
  (fn (_ start type text)
    (set! %vi-undo-stack (pair (list type start (rest text) (first text)) %vi-undo-stack))
    (set! %vi-modified (%vi+ %vi-modified 1))))

; one byte taken out, onto the queue of deletions; the queue of insertions,
; if that is what it holds, is committed first
(def %vi-undo-queue-del!
  (fn (_ src len)
    (match
      ((if (= len 1) #f #t) ())
      ((= %vi-undo-state %vi-u-ins)
        (do (%vi-undo-queue-commit!) (%vi-undo-queue-del! src len)))
      (#t (do (set! %vi-undo-state %vi-u-del)
              (set! %vi-undo-spos src)
              (set! %vi-undo-q (%vi+ %vi-undo-q 1))
              (set! %vi-undo-bytes (pair (%vi& (byte-at %vi-text src) 255) %vi-undo-bytes))
              (if (= %vi-undo-q %vi-undo-queue-max) (%vi-undo-queue-commit!) ()))))))

; LEN bytes put in, onto the queue of insertions, committed each time it
; fills -- which leaves it empty while the count goes on, as busybox's does
(def %vi-undo-queue-ins!
  (fn (_ src len)
    (match
      ((%vi< len 1) ())
      ((= %vi-undo-state %vi-u-del)
        (do (%vi-undo-queue-commit!) (%vi-undo-queue-ins! src len)))
      (#t (do (if (= %vi-undo-state %vi-u-empty)
                (do (set! %vi-undo-state %vi-u-ins) (set! %vi-undo-spos src))
                ())
              (%vi-undo-count-in! len))))))

(def %vi-undo-count-in!
  (fn (self len)
    (if (%vi< 0 len)
      (do (set! %vi-undo-q (%vi+ %vi-undo-q 1))
          (if (= %vi-undo-q %vi-undo-queue-max) (%vi-undo-queue-commit!) ())
          (self (%vi- len 1)))
      ())))

; busybox's undo_queue_commit: what the queue holds, as one record starting
; where the queued change starts
(def %vi-undo-queue-commit!
  (fn (_)
    (if (%vi< 0 %vi-undo-q)
      (do (%vi-undo-commit-as! %vi-undo-state)
          (set! %vi-undo-state %vi-u-empty)
          (set! %vi-undo-q 0)
          (set! %vi-undo-bytes ()))
      ())))

(def %vi-undo-commit-as!
  (fn (_ state)
    (match
      ((= state %vi-u-del)
        (%vi-undo-record! %vi-undo-spos %vi-u-del
          (%vi-bytes-copy %vi-undo-bytes (%vi-undo-del-len %vi-undo-q))))
      ((= state %vi-u-ins) (%vi-undo-record! %vi-undo-spos %vi-u-ins (pair "" %vi-undo-q)))
      ; filled while empty: a record busybox pushes and can not undo
      (#t (%vi-undo-record! %vi-undo-spos %vi-u-empty (pair "" %vi-undo-q))))))

; the first N of BYTES as (BUFFER . LENGTH)
(def %vi-bytes-copy
  (fn (_ bytes n)
    (def s (%str-make-raw (%vi+ n 1)))
    (%vi-bytes-fill (%vi-str->ptr s) 0 n bytes)
    (pair s n)))
(def %vi-bytes-fill
  (fn (self ptr i n bytes)
    (if (if (%vi< i n) (if (null? bytes) #f #t) #f)
      (do (%vi-ptr-set! ptr i (first bytes) 1) (self ptr (%vi+ i 1) n (rest bytes)))
      ())))

; busybox's undo_push_insert: LEN bytes put in at P, recorded as UNDO says
(def %vi-undo-push-insert!
  (fn (_ p len undo)
    (match
      ((= undo %vi-allow-undo) (%vi-undo-push! p len %vi-u-ins))
      ((= undo %vi-allow-undo-chain) (%vi-undo-push! p len %vi-u-ins-chain))
      ((= undo %vi-allow-undo-queued) (%vi-undo-push! p len %vi-u-ins-queued))
      (#t ()))))

; the same for LEN bytes about to be taken out at P
(def %vi-undo-push-delete!
  (fn (_ p len undo)
    (match
      ((= undo %vi-allow-undo) (%vi-undo-push! p len %vi-u-del))
      ((= undo %vi-allow-undo-chain) (%vi-undo-push! p len %vi-u-del-chain))
      ((= undo %vi-allow-undo-queued) (%vi-undo-push! p len %vi-u-del-queued))
      (#t ()))))

; --- u ----------------------------------------------------------------------

; busybox's undo_pop: the newest record undone, and the ones chained under it
(def %vi-undo-pop!
  (fn (self)
    (%vi-undo-queue-commit!)
    (if (null? %vi-undo-stack)
      (%vi-status-line! "Already at oldest change")
      (%vi-undo-pop-top! self (first %vi-undo-stack)))))

; the record undone, then taken off the stack; its count is told first
(def %vi-undo-pop-top!
  (fn (_ again rec)
    (def type (first rec))
    (%vi-undo-apply! rec)
    (set! %vi-undo-stack (rest %vi-undo-stack))
    (set! %vi-modified (%vi- %vi-modified 1))
    (if (if (= type %vi-u-del-chain) #t (= type %vi-u-ins-chain)) (again) ())))

(def %vi-undo-apply!
  (fn (_ rec)
    (def type (first rec))
    (def start (first (rest rec)))
    (def len (first (rest (rest rec))))
    (match
      ((if (= type %vi-u-del) #t (= type %vi-u-del-chain))
        (do (%vi-hole-make! start len)
            (%cu-ptr-call %vi-c-memcpy (%vi+ %vi-taddr start) (first (rest (rest (rest rec)))) len)
            (set! %vi-nl-total (%vi+ %vi-nl-total (%vi-newlines-in start (%vi+ start len))))
            (%vi-undo-said "restored" len start)))
      ((if (= type %vi-u-ins) #t (= type %vi-u-ins-chain))
        (do (%vi-hole-delete! start (%vi- (%vi+ start len) 1) %vi-no-undo)
            (%vi-undo-said "deleted" len start)))
      (#t ()))
    (if (if (= type %vi-u-del) #t (= type %vi-u-ins))
      (do (set! %vi-dot start) (%vi-refresh! #f))
      ())))

(def %vi-undo-said
  (fn (_ what len start)
    (%vi-status-line!
      (string-concat
        (list "Undo [" (%cu-int->str %vi-modified) "] " what " " (%cu-int->str len)
              " chars at position " (%cu-int->str start))))))

; --- . ----------------------------------------------------------------------

; busybox's modifying_cmds: the commands . can repeat
(def %vi-modifying-cmds
  (list #\a #\A #\c #\C #\d #\D #\i #\I #\J #\o #\O #\p #\P #\r #\R #\s
        #\x #\X #\< #\> #\~))
(def %vi-lmc-max 128)       ; busybox's MAX_INPUT_LEN, its buffer's size

(def %vi-adding2q #f)       ; keys are being kept for .
(def %vi-lmc ())            ; the keys kept, newest first
(def %vi-lmc-len 0)
(def %vi-dotcnt 0)          ; the count . gives the command
(def %vi-ioq ())            ; keys . has yet to replay and a NUL, or nil

(def %vi-dot-init!
  (fn (_)
    (set! %vi-adding2q #f)
    (set! %vi-lmc ())
    (set! %vi-lmc-len 0)
    (set! %vi-dotcnt 0)
    (set! %vi-ioq ())))

; busybox's check before do_cmd: a command that changes the text, typed (not
; replayed) in command mode, starts a new record of keys
(def %vi-dot-watch!
  (fn (_ c)
    (if (match
          (%vi-adding2q #f)
          ((if (null? %vi-ioq) #f #t) #f)
          ((if (= %vi-cmd-mode 0) #f #t) #f)
          ((if (%vi< 0 c) (%vi< c #\delete) #f) (%vi-one-of? c %vi-modifying-cmds))
          (#t #f))
      (%vi-start-new-cmd-q! c)
      ())))

; busybox's start_new_cmd_q
(def %vi-start-new-cmd-q!
  (fn (_ c)
    (set! %vi-dotcnt (if (= %vi-cmdcnt 0) 1 %vi-cmdcnt))
    (set! %vi-lmc (list c))
    (set! %vi-lmc-len 1)
    (set! %vi-adding2q #t)))

; a key read while keeping: kept, unless the buffer is full, which forgets
; the command; busybox keeps each key as a byte
(def %vi-lmc-keep!
  (fn (_ c)
    (if (%vi< %vi-lmc-len (%vi- %vi-lmc-max 2))
      (do (set! %vi-lmc (pair (%vi& c 255) %vi-lmc)) (set! %vi-lmc-len (%vi+ %vi-lmc-len 1)))
      (do (set! %vi-adding2q #f) (set! %vi-lmc-len 0)))))

; the next key . replays, or nil when there is none.  The replay ends at a
; NUL, as busybox's string does, and is not over until the NUL is read: the
; last key replayed does not start a new record.
(def %vi-ioq-next!
  (fn (_)
    (if (null? %vi-ioq) () (%vi-ioq-take! (first %vi-ioq)))))
(def %vi-ioq-take!
  (fn (_ c)
    (set! %vi-ioq (if (= c #\null) () (rest %vi-ioq)))
    (if (= c #\null) () c)))

; .: the kept keys given back to be read again, a count before them -- the
; one typed now, or the one the command had
(def %vi-cmd-dot
  (fn (_)
    (if (= %vi-lmc-len 0) ()
      (do (if (= %vi-cmdcnt 0) () (set! %vi-dotcnt %vi-cmdcnt))
          (set! %vi-ioq
            (List append (%vi-bytes-of (%cu-int->str %vi-dotcnt) 0)
              (List append (reverse %vi-lmc) (list 0))))))))

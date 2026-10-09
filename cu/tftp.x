; # x-coreutils -- the small tools, as applets
;
; ## cu/tftp.x -- tftp
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's tftp client: an RRQ (-g) or WRQ (-p) to HOST's PORT (69), always
; asking the file's size ("tsize") and, with -b, a block size; the server's
; first answer -- from a port of its own, every later packet from there and
; nowhere else -- is an OACK the options settle on, or the first DATA or ACK
; of a server that knows none.  Then a DATA a block and an ACK a block, each
; packet sent again after 100 ms, half as long again each time to 2 s, twelve
; times before "timeout".  The progress line is wget's, for the remote file,
; once its size is known.
;
; Packets are runs sent and read as datagrams with their sender
; (net-send-to-run, net-recv-from-run), so their NUL bytes cross.

; the applet a message is said as: tftp, or tftpd, which shares the protocol
(def %tftp-name "tftp")
(def %tftp-say (fn (_ msg) (file-write 2 (string-concat (list %tftp-name ": " msg "\n")))))

(def %tftp-flags (list "-g" "-p"))
(def %tftp-values (list "-l" "-r" "-b" "-m"))

; tftp-hpa's "-c get FILE" and "-c put FILE", in any word holding a c, read as
; -g -r FILE and -p -r FILE, as busybox's HPA_COMPAT reads them
(def %tftp-hpa
  (fn (self argv)
    (match
      ((null? argv) ())
      ((if (if (> (byte-len (first argv)) 0) (= (byte-at (first argv) 0) #\-) #f)
           (if (not (null? (%wget-index (first argv) #\c 0))) (not (null? (rest argv))) #f) #f)
        (match
          ((string=? (first (rest argv)) "get") (pair "-g" (pair "-r" (rest (rest argv)))))
          ((string=? (first (rest argv)) "put") (pair "-p" (pair "-r" (rest (rest argv)))))
          (#t (pair (first argv) (self (rest argv))))))
      (#t (pair (first argv) (self (rest argv)))))))

; busybox's tftp_blksize_check: 24 to MAX, or nil after "bad blocksize"
(def %tftp-blksize
  (fn (_ s max)
    (def n (%wget-digits s))
    (if (if (null? n) #t (if (< n 24) #t (> n max)))
      (do (%tftp-say (string-concat (list "bad blocksize '" s "'"))) ())
      n)))

; --- packets ---------------------------------------------------------------------

; S's bytes then a NUL
(def %tftp-cstr (fn (_ s) (append (%tftp-bytes s 0 (byte-len s)) (list 0))))

(def %tftp-u16 (fn (_ n) (list (% (%wget-div n 256) 256) (% n 256))))

(def %tftp-run (fn (_ bs) (pair (bytes->str bs) (length bs))))

; the request: RRQ (1) or WRQ (2), the file, "octet", a blksize option when it
; is not 512, and the tsize option, SIZE bytes
(def %tftp-request
  (fn (_ op remote blksize size)
    (append (%tftp-u16 op)
      (append (%tftp-cstr remote)
        (append (%tftp-cstr "octet")
          (append (if (= blksize 512) () (append (%tftp-cstr "blksize") (%tftp-cstr (%cu-int->str blksize))))
                  (append (%tftp-cstr "tsize") (%tftp-cstr (%cu-int->str size)))))))))

; byte I of a run
(def %tftp-at (fn (_ run i) (& (byte-at (first run) i) 255)))
(def %tftp-word (fn (_ run i) (+ (* 256 (%tftp-at run i)) (%tftp-at run (+ i 1)))))

; the text of a run from I to its first NUL or its end
(def %tftp-text
  (fn (_ run i)
    (def end (let find ((k i)) (if (if (< k (rest run)) (not (= (%tftp-at run k) 0)) #f) (find (+ k 1)) k)))
    (bytes->str (let take ((k (- end 1)) (acc ())) (if (< k i) acc (take (- k 1) (pair (%tftp-at run k) acc)))))))

; busybox's tftp_get_option: OPTION's value in an OACK's NAME\0VALUE\0 pairs
; from byte 2, any case, or nil
(def %tftp-option
  (fn (_ run option)
    (let go ((i 2) (name? #t) (found #f))
      (if (>= i (rest run)) ()
        (let ((s (%tftp-text run i)))
          (let ((next (+ (+ i (byte-len s)) 1)))
            (match
              ((> next (rest run)) ())
              (name? (go next #f (string=? (%wget-lower s) option)))
              (found s)
              (#t (go next #t #f)))))))))

(def %tftp-errors
  (list "" "file not found" "access violation" "disk full" "bad operation"
        "unknown transfer id" "file already exists" "no such user" "bad option"))

; --- the exchange ----------------------------------------------------------------

; the run's state, set afresh by each transfer
(def %tftp-fd -1)          ; the socket
(def %tftp-peer ())        ; (IP . PORT): the server, its own port after its first answer
(def %tftp-answered #f)    ; has the server answered from its own port yet
(def %tftp-progress #f)    ; is the progress line drawn
(def %tftp-pos 0)
(def %tftp-size 0)
(def %tftp-local-fd -1)    ; the file a get writes or a put reads

(def %tftp-connected #f)   ; tftpd's socket is connected to its peer: send, not sendto

(def %tftp-send
  (fn (_ bs)
    (def run (%tftp-run bs))
    (if %tftp-connected
      (%cu-ptr-call (%cu-dlsym (%cu-dlopen () 1) "send") %tftp-fd (%cu-str->ptr (first run)) (rest run) 0)
      (net-send-to-run %tftp-fd run (first %tftp-peer) (rest %tftp-peer)))))

(def %tftp-progress-init!
  (fn (_ name)
    (do (set! %tftp-progress #t)
        (%wget-pm-init! name)
        (%wget-pm-update! 0 %tftp-pos %tftp-size #f))))

(def %tftp-progress-done!
  (fn (_)
    (when %tftp-progress
      (do (%wget-pm-update! 0 %tftp-pos %tftp-size #f)
          (file-write 2 "\n")))))

; the next packet from the server, or nil once the wait has passed: the first
; answer settles the server's port, and anything from elsewhere is ignored
(def %tftp-receive
  (fn (self wait-ms bufsize)
    (def ready (sys-poll (list (pair %tftp-fd (list (lit in)))) wait-ms))
    (if (null? ready) ()
      (let ((got (net-recv-from-run %tftp-fd bufsize)))
        (match
          ((not %tftp-answered)
            (do (set! %tftp-peer (rest got)) (set! %tftp-answered #t) (first got)))
          ((if (string=? (first (rest got)) (first %tftp-peer)) (= (rest (rest got)) (rest %tftp-peer)) #f)
            (first got))
          (#t (self wait-ms bufsize)))))))

; send BS, then wait for an answer that is not too short, sending again on each
; silence -- after 100 ms, half as long again each time up to 2 s, twelve
; times; nil after the twelfth
(def %tftp-exchange
  (fn (_ bs bufsize)
    (do (%tftp-send bs)
        (when %tftp-progress (%wget-pm-update! 0 %tftp-pos %tftp-size #f))
        (let wait ((ms 100) (left 12))
          (let ((r (%tftp-receive ms bufsize)))
            (match
              ((null? r)
                (if (= left 1) ()
                  (do (%tftp-send bs) (wait (if (> (+ ms (%wget-div ms 2)) 2000) 2000 (+ ms (%wget-div ms 2))) (- left 1)))))
              ((< (rest r) 4) (wait ms left))
              (#t r)))))))

; up to N bytes of FD, reading until N or the end: busybox's full_read
(def %tftp-read-block
  (fn (_ fd n)
    (let go ((acc ()) (have 0))
      (if (>= have n) (reverse acc)
        (let ((r (file-read-run fd (- n have))))
          (if (= (rest r) 0) (reverse acc)
            (go (append (reverse (%tftp-bytes (first r) 0 (rest r))) acc) (+ have (rest r)))))))))

; the transfer, after the request: answers #t when it finished
(def %tftp-transfer
  (fn (self get? request blksize remote local)
    (def first-answer (%tftp-exchange request (+ (if (= blksize 512) 512 blksize) 4)))
    (%tftp-after-request get? first-answer blksize remote local)))

; the server's first answer: an OACK settles the options; anything else is a
; server without them, the block size back to 512
(def %tftp-after-request
  (fn (_ get? r blksize remote local)
    (match
      ((null? r) (do (%tftp-say "timeout") #f))
      ((= (%tftp-word r 0) 5) (%tftp-error r))
      ((= (%tftp-word r 0) 6)
        (let ((b (%tftp-option r "blksize")) (t (%tftp-option r "tsize")))
          (let ((bs (if (null? b) blksize (%tftp-blksize b 65564))))
            (if (null? bs) (%tftp-fail-option)
              (do (when (if (not (null? t)) (= %tftp-size 0) #f)
                    (let ((n (%wget-digits t)))
                      (when (if (null? n) #f (> n 0))
                        (do (set! %tftp-size n) (%tftp-progress-init! remote)))))
                  (if get? (%tftp-get-loop 0 bs local)
                    (%tftp-put-loop 1 bs)))))))
      (#t
        (do (unless (= blksize 512) (file-write 2 "tftp: falling back to blocksize 512\n"))
            (if get? (%tftp-get-data r 1 512 local) (%tftp-put-ack r 1 512)))))))

(def %tftp-error
  (fn (_ r)
    (def code (%tftp-word r 2))
    (def text (if (if (> (rest r) 4) (not (= (%tftp-at r 4) 0)) #f) (%tftp-text r 4)
                (if (<= code 8) (%cu-nth code %tftp-errors) "")))
    (%tftp-say (string-concat (list "server error: (" (%cu-int->str code) ") " text)))
    #f))

; an OACK whose block size busybox refuses: error 8 to the server
(def %tftp-fail-option
  (fn (_)
    (do (%tftp-send (append (%tftp-u16 5) (append (%tftp-u16 8) (list 0)))) #f)))

; --- get ---------------------------------------------------------------------------

; ACK block N and wait for DATA N+1
(def %tftp-get-loop
  (fn (_ n blksize local)
    (def r (%tftp-exchange (append (%tftp-u16 4) (%tftp-u16 (% n 65536))) (+ blksize 4)))
    (match
      ((null? r) (do (%tftp-say "timeout") #f))
      (#t (%tftp-get-data r (% (+ n 1) 65536) blksize local)))))

; a packet while DATA N is due: write it and ACK it, the last when it is short
(def %tftp-get-data
  (fn (self r n blksize local)
    (match
      ((= (%tftp-word r 0) 5) (%tftp-error r))
      ((if (= (%tftp-word r 0) 3) (= (%tftp-word r 2) n) #f)
        (do (when (< %tftp-local-fd 0)
              (set! %tftp-local-fd (if (null? local) 1 (file-open-write local))))
            (file-write-run %tftp-local-fd
              (%tftp-run (let take ((k (- (rest r) 1)) (acc ())) (if (< k 4) acc (take (- k 1) (pair (%tftp-at r k) acc))))))
            (set! %tftp-pos (+ %tftp-pos (- (rest r) 4)))
            (%cu-sweep! 1)
            (if (= (- (rest r) 4) blksize)
              (%tftp-get-loop n blksize local)
              (do (%tftp-send (append (%tftp-u16 4) (%tftp-u16 n)))
                  (when %tftp-progress (%wget-pm-update! 0 %tftp-pos %tftp-size #f))
                  #t))))
      (#t
        (let ((again (%tftp-receive 100 (+ blksize 4))))
          (if (null? again) (%tftp-get-loop (% (- n 1) 65536) blksize local)
            (self again n blksize local)))))))

; --- put ---------------------------------------------------------------------------

; send DATA block N, the next blksize bytes of the file, and wait for its ACK
(def %tftp-put-loop
  (fn (_ n blksize)
    (def block (%tftp-read-block %tftp-local-fd blksize))
    (set! %tftp-pos (+ %tftp-pos (length block)))
    (%cu-sweep! 1)
    (%tftp-put-wait (append (%tftp-u16 3) (append (%tftp-u16 n) block)) n blksize
                    (< (length block) blksize))))

(def %tftp-put-wait
  (fn (self packet n blksize last?)
    (def r (%tftp-exchange packet 516))
    (match
      ((null? r) (do (%tftp-say "timeout") #f))
      ((= (%tftp-word r 0) 5) (%tftp-error r))
      ((if (= (%tftp-word r 0) 4) (= (%tftp-word r 2) n) #f)
        (if last? #t (%tftp-put-loop (% (+ n 1) 65536) blksize)))
      (#t (self packet n blksize last?)))))

; the server's first answer to a WRQ that asked no options of it
(def %tftp-put-ack
  (fn (_ r n blksize)
    (if (if (= (%tftp-word r 0) 4) (= (%tftp-word r 2) 0) #f)
      (%tftp-put-loop n blksize)
      (do (%tftp-say "timeout") #f))))

; --- the applet ------------------------------------------------------------------

(def %cu-tftp
  (fn (_ argv stdin-thunk)
    (def o (Opts parse %tftp-flags %tftp-values (%tftp-hpa argv)))
    (def ops (Opts operands o))
    (def get? (Opts on? o "-g"))
    (def put? (Opts on? o "-p"))
    (match
      ((not (null? (Opts unknown o))) (%cu-refuse-option "tftp" (Opts unknown o)))
      ((if get? put? #f) (%cu-usage "tftp"))
      ((not (if get? #t put?)) (%cu-usage "tftp"))
      (#t
        (let ((blksize (%tftp-blksize (let ((b (Opts value o "-b"))) (if (null? b) "512" b)) 65564)))
          (if (null? blksize) 1
            (guard (e (if (eq? (Err label e) (lit net))
                        (do (file-write 2 (string-concat (list "tftp: " (e msg) "\n"))) 1)
                        (error e)))
              (%tftp-run-applet get? blksize (Opts value o "-l") (Opts value o "-r") ops))))))))

(def %tftp-run-applet
  (fn (_ get? blksize l r ops)
    (def remote (if (null? r) l r))
    (def local
      (if (null? r) l
        (if (null? l) (let ((s (%wget-last-index r #\/))) (if (null? s) r (substring r (+ s 1) (byte-len r)))) l)))
    (if (if (null? remote) #t (null? ops)) (%cu-usage "tftp")
      (%tftp-start get? blksize remote (if (string=? local "-") () local)
                   (first ops) (if (null? (rest ops)) 69 (%wget-digits (first (rest ops))))))))

(def %tftp-start
  (fn (_ get? blksize remote local host port)
    (def ip (guard (_ ()) (net-resolve host)))
    (when (null? ip) (%net-die (string-concat (list "bad address '" host "'"))))
    (set! %tftp-progress #f) (set! %tftp-pos 0) (set! %tftp-size 0)
    (set! %tftp-answered #f) (set! %tftp-peer (pair ip port)) (set! %tftp-local-fd -1)
    (unless get?
      (set! %tftp-local-fd
        (if (null? local) 0
          (let ((fd (file-open-or-err file-open-read local)))
            (if (Err err? fd)
              (%net-die (string-concat (list "can't open '" local "': " (file-err-text fd))))
              fd)))))
    (unless (if get? #t (< %tftp-local-fd 1))
      (let ((size (Assoc get (lit size) (file-stat local))))
        (set! %tftp-size size)))
    (set! %tftp-fd (net-udp-bind 0))
    (when (> %tftp-size 0) (%tftp-progress-init! remote))
    (def ok (%tftp-transfer get? (%tftp-request (if get? 1 2) remote blksize %tftp-size)
                            blksize remote local))
    (%tftp-progress-done!)
    (net-close %tftp-fd)
    (when (> %tftp-local-fd 1) (file-close %tftp-local-fd))
    ; a get that did not finish leaves no file behind
    (when (if get? (if (not ok) (if (not (null? local)) (> %tftp-local-fd 1) #f) #f) #f)
      (file-unlink local))
    (if ok 0 1)))

; S's bytes from A to B, as a list
(def %tftp-bytes
  (fn (_ s a b)
    (let go ((i (- b 1)) (acc ()))
      (if (< i a) acc (go (- i 1) (pair (& (byte-at s i) 255) acc))))))

; --- tftpd ---------------------------------------------------------------------------
;
; busybox's tftpd: run from inetd or udpsvd with the request's socket on stdin.
; The first datagram is the request -- RRQ or WRQ, a name with no dot at its
; start or after a slash, mode octet, the blksize and (RRQ) tsize options --
; and the answer comes from a socket of its own, bound to the address the
; request came to and connected to the client.  A refused request is said on
; stderr and answered with an ERROR packet; the transfer is the client's
; protocol with the roles turned: an RRQ's file goes out as DATA, a WRQ's
; comes in.  -l (syslog) is accepted and says nothing.

(def %tftpd-libc ())
(def %tftpd-c
  (fn (_ name)
    (when (null? %tftpd-libc) (set! %tftpd-libc (%cu-dlopen () 1)))
    (%cu-dlsym %tftpd-libc name)))

; a zeroed sockaddr_in for QUAD:PORT -- Darwin leads with its length byte and a
; one-byte family, Linux with a two-byte family
(def %tftpd-sockaddr
  (fn (_ quad port)
    (def s (%str-make-raw 16))
    (def p (%cu-str->ptr s))
    (let go ((i 0)) (when (< i 16) (do (%cu-ptr-set! p i 0 1) (go (+ i 1)))))
    (if os-darwin? (do (%cu-ptr-set! p 0 16 1) (%cu-ptr-set! p 1 2 1)) (%cu-ptr-set! p 0 2 1))
    (%cu-ptr-set! p 2 (%wget-div port 256) 1)
    (%cu-ptr-set! p 3 (% port 256) 1)
    (let go ((i 0) (parts (Str8 split "." quad)))
      (unless (null? parts)
        (do (%cu-ptr-set! p (+ 4 i) (%wget-digits (first parts)) 1) (go (+ i 1) (rest parts)))))
    s))

; the answering socket: bound to OUR address, which the listener may hold too
; (SO_REUSEADDR, and on Darwin SO_REUSEPORT), and connected to PEER
(def %tftpd-socket
  (fn (_ our peer)
    (def fd (Sys %sign-fold (%cu-ptr-call (%tftpd-c "socket") 2 2 0)))
    (def one (%str-make-raw 4))
    (%cu-ptr-set! (%cu-str->ptr one) 0 1 4)
    (def sol (if os-darwin? 65535 1))
    (%cu-ptr-call (%tftpd-c "setsockopt") fd sol (if os-darwin? 4 2) (%cu-str->ptr one) 4)
    (when os-darwin? (%cu-ptr-call (%tftpd-c "setsockopt") fd sol 512 (%cu-str->ptr one) 4))
    (%cu-ptr-call (%tftpd-c "bind") fd (%cu-str->ptr (%tftpd-sockaddr (first our) (rest our))) 16)
    (%cu-ptr-call (%tftpd-c "connect") fd (%cu-str->ptr (%tftpd-sockaddr (first peer) (rest peer))) 16)
    fd))

(def %tftpd-die (fn (_ msg) (Err raise (lit net) msg ())))

; the request's checks, in busybox's order: (ERROR-CODE . TEXT) when it is
; refused, else (FILE BLKSIZE TSIZE?) -- BLKSIZE nil after "bad blocksize"
(def %tftpd-check
  (fn (_ r write-refused?)
    (def op (if (>= (rest r) 2) (%tftp-word r 0) 0))
    (if (if (< (rest r) 4) #t (if (> (rest r) 516) #t (not (if (= op 1) #t (= op 2)))))
      (pair 0 "malformed packet")
      (%tftpd-check-name r op write-refused?))))

(def %tftpd-check-name
  (fn (_ r op write-refused?)
    (def file (%tftp-text r 2))
    (def mode-at (+ 3 (byte-len file)))
    (def mode (if (< mode-at (rest r)) (%tftp-text r mode-at) ()))
    (match
      ((if (Str8 starts? "." file) #t (not (null? (%wget-find file "/.")))) (pair 0 "dot in file name"))
      ((if (null? mode) #t (not (string=? (%wget-lower mode) "octet"))) (pair 0 "mode is not 'octet'"))
      (#t (%tftpd-check-options r op write-refused? file (+ mode-at (byte-len mode) 1))))))

(def %tftpd-check-options
  (fn (_ r op write-refused? file at)
    (def b (%tftpd-option r at "blksize"))
    (def blksize (if (null? b) 512 (%tftp-blksize b 65564)))
    (match
      ((null? blksize) (pair 8 ""))
      ((if (= op 2) write-refused? #f) (pair 0 "write error"))
      (#t (list file blksize (if (= op 1) (not (null? (%tftpd-option r at "tsize"))) #f))))))

; tftp_get_option over the request's NAME\0VALUE\0 pairs from byte AT
(def %tftpd-option
  (fn (_ r at option)
    (let go ((i at) (name? #t) (found #f))
      (if (>= i (rest r)) ()
        (let ((s (%tftp-text r i)))
          (let ((next (+ (+ i (byte-len s)) 1)))
            (match
              ((> next (rest r)) ())
              (name? (go next #f (string=? (%wget-lower s) option)))
              (found s)
              (#t (go next #t #f)))))))))

(def %tftpd-error-packet
  (fn (_ code text) (append (%tftp-u16 5) (append (%tftp-u16 code) (%tftp-cstr text)))))

(def %cu-tftpd
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "tftpd" argv))
    (set! %tftp-name "tftpd")
    (def fd (net-stdin-socket))
    (if (null? fd) (%cu-usage "tftpd")
      (guard (e (if (eq? (Err label e) (lit net))
                  (do (%tftp-say (e msg)) 1)
                  (error e)))
        (%tftpd-run o fd (net-sock-addr fd))))))

(def %tftpd-run
  (fn (_ o fd our)
    (def user (Opts value o "-u"))
    (when (if (null? user) #f (null? (sys-user-id user)))
      (%tftpd-die (string-append "unknown user " user)))
    (def dir (let ((ops (Opts operands o))) (if (null? ops) () (first ops))))
    (unless (null? dir)
      (let ((r (guard (e e) (sys-chroot dir))))
        (when (if (Err err? r) #t (if (number? r) (< r 0) #f))
          (%tftpd-die (string-concat (list "can't change root directory to '" dir "': "
            (file-err-text (if (Err err? r) r (Err from-errno (Err errno-of r) (lit chroot) dir)))))))))
    (def got (net-recv-from-run fd 517))
    (def checked (%tftpd-check (first got) (Opts on? o "-r")))
    (set! %tftp-progress #f) (set! %tftp-pos 0) (set! %tftp-size 0) (set! %tftp-local-fd -1)
    (sys-close fd)
    (set! %tftp-fd (%tftpd-socket our (rest got)))
    (set! %tftp-peer (rest got)) (set! %tftp-answered #t) (set! %tftp-connected #t)
    (if (number? (first checked))
      (do (unless (= (byte-len (rest checked)) 0) (%tftp-say (rest checked)))
          (%tftp-send (%tftpd-error-packet (first checked) (rest checked)))
          1)
      (do (unless (null? user) (%tftpd-become user))
          (%tftpd-serve (= (%tftp-word (first got) 0) 1) (first checked) (%cu-nth 1 checked) (%cu-nth 2 checked)
                        (Opts on? o "-c"))))))

; change_identity: initgroups, setgid, setuid -- each failure the end of the run
(def %tftpd-become
  (fn (_ user)
    (def gid (sys-user-group user))
    (def fail? (fn (_ r what)
      (let ((e (%ss-call r (lit call) what)))
        (unless (null? e) (%tftpd-die (string-concat (list what ": " (file-err-text e))))))))
    (fail? (%cu-ptr-call (%tftpd-c "initgroups") user gid) "can't set groups")
    (fail? (%cu-ptr-call (%tftpd-c "setgid") gid) "setgid")
    (fail? (%cu-ptr-call (%tftpd-c "setuid") (sys-user-id user)) "setuid")))

; FILE, a request's name, with each byte below a space as ?
(def %tftpd-sanitize
  (fn (_ file)
    (bytes->str (map (fn (_ b) (if (< b 32) #\? b)) (%tftp-bytes file 0 (byte-len file))))))

; the file opened -- an RRQ's to read, a WRQ's truncated, created with -c --
; then the transfer: 0 once it finished, 1 when it did not, a WRQ's file then
; removed
(def %tftpd-serve
  (fn (_ rrq? file blksize tsize? create?)
    (def fd (file-open-or-err
              (fn (_ p) (if rrq? (file-open-read p)
                          (File open p (if create? (list (lit wronly) (lit trunc) (lit creat)) (list (lit wronly) (lit trunc))) 438)))
              file))
    (if (Err err? fd)
      (do (%tftp-say (string-concat (list "can't open '" (%tftpd-sanitize file) "': " (file-err-text fd))))
          (%tftp-send (%tftpd-error-packet 1 "can't open file"))
          1)
      (do (set! %tftp-local-fd fd)
          (let ((ok (%tftpd-transfer rrq? file blksize tsize?)))
            (do (file-close fd)
                (if ok 0 (do (unless rrq? (file-unlink file)) 1))))))))

; an OACK when the request asked a block size or the size, else the first
; DATA (RRQ) or ACK 0 (WRQ) at once
(def %tftpd-transfer
  (fn (_ rrq? file blksize tsize?)
    (if (if (= blksize 512) (not tsize?) #f)
      (if rrq? (%tftp-put-loop 1 512) (%tftp-get-loop 0 512 file))
      (let ((oack (append (%tftp-u16 6)
                    (append (if (= blksize 512) () (append (%tftp-cstr "blksize") (%tftp-cstr (%cu-int->str blksize))))
                            (if tsize? (append (%tftp-cstr "tsize") (%tftp-cstr (%cu-int->str (Assoc get (lit size) (file-stat file))))) ())))))
        (if rrq? (%tftp-put-wait oack 0 blksize #f)
          (let ((r (%tftp-exchange oack (+ blksize 4))))
            (if (null? r) (do (%tftp-say "timeout") #f) (%tftp-get-data r 1 blksize file))))))))

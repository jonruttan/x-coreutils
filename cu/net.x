; # x-coreutils -- the small tools, as applets
;
; ## cu/net.x -- wget
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's wget over the platform's Http (cu/prims.x's http- doors).  The url
; is read the way busybox's parse_url reads it; the statuses, the redirects and
; the retries are decided here, so Http is asked never to follow a redirect --
; busybox prints a "Connecting to" for every new server, and its rule for a
; Location is its own.  The body is written a piece at a time as Http hands it
; out, with a sweep after each piece, so a download of any size holds one
; piece.
;
; What busybox's wget does and this one does not: ftp:// urls, http_proxy and
; -Y, the -T timeout (accepted and ignored), a 100 Continue ahead of the
; response, and a --header naming Host, which Http sends whatever the caller
; adds.

; --- small text helpers ------------------------------------------------------

; the index of the first byte of S at or after I equal to C, or nil
(def %wget-index
  (fn (self s c i)
    (match
      ((>= i (byte-len s)) ())
      ((= (byte-at s i) c) i)
      (#t (self s c (+ i 1))))))

; the index of the last byte of S equal to C, or nil
(def %wget-last-index
  (fn (_ s c)
    (let go ((i (- (byte-len s) 1)))
      (match
        ((< i 0) ())
        ((= (byte-at s i) c) i)
        (#t (go (- i 1)))))))

; the index where the text NEEDLE first starts in S, or nil
(def %wget-find
  (fn (_ s needle)
    (def n (byte-len needle))
    (let go ((i 0))
      (match
        ((> (+ i n) (byte-len s)) ())
        ((string=? (substring s i (+ i n)) needle) i)
        (#t (go (+ i 1)))))))

; S's value as a decimal count when it is all digits, else nil
(def %wget-digits
  (fn (_ s)
    (if (= (byte-len s) 0) ()
      (let go ((i 0) (n 0))
        (match
          ((= i (byte-len s)) n)
          ((if (>= (byte-at s i) #\0) (<= (byte-at s i) #\9) #f)
            (go (+ i 1) (+ (* n 10) (- (byte-at s i) #\0))))
          (#t ()))))))

; floor division; the harness's / is exact
(def %wget-div (fn (_ a b) (/ (- a (% a b)) b)))

; S lowercased, letters only
(def %wget-lower
  (fn (_ s)
    (list->string
      (map (fn (_ c) (if (if (>= c #\A) (<= c #\Z) #f) (integer->char (+ c 32)) c))
           (let go ((i (- (byte-len s) 1)) (acc ()))
             (if (< i 0) acc (go (- i 1) (pair (byte-at s i) acc))))))))

; a head line as busybox prints and reads it: cut at the first control byte
(def %wget-sanitize
  (fn (_ s)
    (let go ((i 0))
      (match
        ((= i (byte-len s)) s)
        ((< (byte-at s i) 32) (substring s 0 i))
        (#t (go (+ i 1)))))))

; N as decimal text, right-aligned in W columns
(def %wget-rjust (fn (_ n w) (%cu-pad-left (%cu-int->str n) w)))

; N as two digits
(def %wget-02 (fn (_ n) (%cu-pad-zero (%cu-int->str n) 2)))

; S cut or padded with blanks to exactly W columns
(def %wget-fixed
  (fn (_ s w)
    (if (>= (byte-len s) w) (substring s 0 w) (%cu-pad-right s w))))

; K copies of the byte C
(def %wget-times
  (fn (_ k c)
    (bytes->str (let go ((k k) (acc ())) (if (<= k 0) acc (go (- k 1) (pair c acc)))))))

; is X one of the numbers (or bytes) in L
(def %wget-memv
  (fn (self x l) (if (null? l) #f (if (= (first l) x) #t (self x (rest l))))))

; is X one of the symbols in L
(def %wget-memq
  (fn (self x l) (if (null? l) #f (if (eq? (first l) x) #t (self x (rest l))))))

; %XX decoded where XX is two hex digits; anything else is kept as it is
(def %wget-pct-decode
  (fn (_ s)
    (def hex (fn (_ c)
      (match
        ((if (>= c #\0) (<= c #\9) #f) (- c #\0))
        ((if (>= c #\a) (<= c #\f) #f) (- c 87))
        ((if (>= c #\A) (<= c #\F) #f) (- c 55))
        (#t -1))))
    (def n (byte-len s))
    (list->string
      (let go ((i 0) (acc ()))
        (match
          ((>= i n) (reverse acc))
          ((if (= (byte-at s i) #\%) (< (+ i 2) (+ n 0)) #f)
            (let ((h (hex (byte-at s (+ i 1)))) (l (hex (byte-at s (+ i 2)))))
              (if (if (>= h 0) (>= l 0) #f)
                (go (+ i 3) (pair (integer->char (+ (* h 16) l)) acc))
                (go (+ i 1) (pair (byte-at s i) acc)))))
          (#t (go (+ i 1) (pair (byte-at s i) acc))))))))

; --- the url -------------------------------------------------------------------

; busybox's parse_url: (SCHEME HOST PATH USER), or nil when the scheme is not
; http, https or ftp.  With no "://" the url is http.  HOST keeps its :PORT.
; PATH has no leading /: the host ends at the first of / ? #, and that byte is
; dropped -- so http://h?a=b asks for /a=b, as busybox does.  USER is what comes
; before the host's last @, percent-decoded, or nil.
(def %wget-url
  (fn (_ url)
    (def sep (%wget-find url "://"))
    (def scheme (if (null? sep) "http" (substring url 0 sep)))
    (def tail (if (null? sep) url (substring url (+ sep 3) (byte-len url))))
    (def cut
      (let go ((i 0))
        (match
          ((= i (byte-len tail)) ())
          ((%wget-memv (byte-at tail i) (list #\/ #\? #\#)) i)
          (#t (go (+ i 1))))))
    (def hostpart (if (null? cut) tail (substring tail 0 cut)))
    (def path (if (null? cut) "" (substring tail (+ cut 1) (byte-len tail))))
    (def at (%wget-last-index hostpart #\@))
    (if (%cu-member-s? scheme (list "http" "https" "ftp"))
      (list scheme
            (if (null? at) hostpart (substring hostpart (+ at 1) (byte-len hostpart)))
            path
            (if (null? at) () (%wget-pct-decode (substring hostpart 0 at))))
      ())))

(def %wget-scheme (fn (_ t) (first t)))
(def %wget-host (fn (_ t) (first (rest t))))
(def %wget-path (fn (_ t) (first (rest (rest t)))))
(def %wget-user (fn (_ t) (first (rest (rest (rest t))))))

; HOST's (NAME . PORT): the port after its last colon, or the scheme's own;
; PORT is nil when the text after the colon is not a number
(def %wget-name-port
  (fn (_ t)
    (def host (%wget-host t))
    (def colon (%wget-last-index host #\:))
    (if (null? colon)
      (pair host (match ((string=? (%wget-scheme t) "https") 443)
                        ((string=? (%wget-scheme t) "ftp") 21)
                        (#t 80)))
      (pair (substring host 0 colon)
            (%wget-digits (substring host (+ colon 1) (byte-len host)))))))

; busybox's bb_get_last_path_component_nostrip: after the last /, or the whole
; when there is none or it is a lone /
(def %wget-last-part
  (fn (_ p)
    (def slash (%wget-last-index p #\/))
    (match
      ((null? slash) p)
      ((if (= slash 0) (= (byte-len p) 1) #f) p)
      (#t (substring p (+ slash 1) (byte-len p))))))

; the file a url saves to with no -O: the path's last part, index.html when
; that is empty or a lone /, under -P's directory when one is given
(def %wget-fname
  (fn (_ t dir)
    (def base (%wget-last-part (%wget-path t)))
    (def name (if (if (= (byte-len base) 0) #t (= (byte-at base 0) #\/)) "index.html" base))
    (match
      ((null? dir) name)
      ((= (byte-len dir) 0) name)
      ((= (byte-at dir (- (byte-len dir) 1)) #\/) (string-append dir name))
      (#t (string-append dir (string-append "/" name))))))

; --- the run's state -------------------------------------------------------------

; set afresh by each run (%wget-run)
(def %wget-cfg ())        ; the parsed options
(def %wget-msg-fd 2)      ; where messages go: stderr, or -o's log
(def %wget-out-fd -1)     ; the file being written, -1 when none is open
(def %wget-pos 0)         ; the offset the next write lands at
(def %wget-reset-pos 0)   ; where this url's data starts in an -O file
(def %wget-beg 0)         ; bytes already held: -c's file, an earlier try's

(def %wget-on?
  (fn (_ short long) (if (Opts on? %wget-cfg short) #t (Opts on? %wget-cfg long))))
(def %wget-value
  (fn (_ short long)
    (let ((v (Opts value %wget-cfg short)))
      (if (null? v) (Opts value %wget-cfg long) v))))
(def %wget-quiet? (fn (_) (%wget-on? "-q" "--quiet")))
(def %wget-show? (fn (_) (%wget-on? "-S" "--server-response")))

(def %wget-say
  (fn (_ s) (file-write %wget-msg-fd s)))

; a fatal error: the message, and the run ends with status 1
(def %wget-die
  (fn (_ msg) (Err raise (lit wget) msg ())))

; the message an io Err carries after its call's name: "Connection refused"
(def %wget-err-text
  (fn (_ e) (if (Err err? e) (file-err-text e) "")))

; the call an io Err came from, or nil for an Err that names none
(def %wget-err-op
  (fn (_ e)
    (let ((d (e data)))
      (if (if (null? d) #t (number? d)) () (file-err-op e)))))

; --- the progress line: busybox's bb_progress_update -------------------------------

(def %wget-pm-start 0)
(def %wget-pm-last 0)
(def %wget-pm-change 0)
(def %wget-pm-size 0)
(def %wget-pm-file "")

(def %wget-pm-on?
  (fn (_) (if (%wget-quiet?) #f (= %wget-msg-fd 2))))

(def %wget-pm-init!
  (fn (_ name)
    (def now (date-now-unix))
    (do (set! %wget-pm-file name)
        (set! %wget-pm-start now)
        (set! %wget-pm-last now)
        (set! %wget-pm-change now)
        (set! %wget-pm-size 0))))

; the bar's width: COLUMNS when it is set, else the terminal's when stderr is
; one, else 80 -- less the 48 the rest of the line takes
(def %wget-columns
  (fn (_)
    (def env (sys-getenv "COLUMNS"))
    (def v (%wget-term-columns env))
    (if (if (<= v 1) #t (>= v 30000)) 80 v)))

(def %wget-term-columns
  (fn (_ env)
    (match
      ((not (null? env)) (let ((n (%wget-digits env))) (if (null? n) 0 n)))
      ((sys-isatty 2) (first (Term window 2)))
      (#t 80))))

; busybox's smart_ulltoa5: five columns, "12345" up to 99999, then scaled by
; 1024 into "92.1k" or " 123M"
(def %wget-ulltoa5
  (fn (_ ul)
    (def scale " kMGTPEZY")
    (def scaled
      (if (<= ul 99999) (pair ul 0)
        (let go ((v (* ul 10)) (idx 0))
          (let ((v2 (%wget-div v 1024)))
            (if (>= v2 100000) (go v2 (+ idx 1)) (pair v2 (+ idx 1)))))))
    (def v (first scaled))
    (def idx (rest scaled))
    (def u (%wget-div v 10))
    (def d (% v 10))
    (def digit (fn (_ n) (integer->char (+ #\0 n))))
    ; a leading zero shows as a blank until the first digit that is not one
    (def lead
      (fn (_ ns)
        (let go ((ns ns) (on #f) (acc ()))
          (if (null? ns) (reverse acc)
            (let ((n (first ns)))
              (if (if on #t (> n 0))
                (go (rest ns) #t (pair (digit n) acc))
                (go (rest ns) #f (pair #\space acc))))))))
    (list->string
      (match
        ((= idx 0)
          (append (lead (list (% (%wget-div u 1000) 10) (% (%wget-div u 100) 10)
                              (% (%wget-div u 10) 10) (% u 10)))
                  (list (digit d))))
        ((>= u 100)
          (append (lead (list (% (%wget-div u 1000) 10) (% (%wget-div u 100) 10)
                              (% (%wget-div u 10) 10)))
                  (list (digit (% u 10)) (byte-at scale idx))))
        (#t
          (append (lead (list (% (%wget-div u 10) 10)))
                  (list (digit (% u 10)) #\. (digit d) (byte-at scale idx))))))))

; one update: drawn when FORCE, when the download is complete, or when a second
; has passed since the last; without a terminal each one is a line of its own
(def %wget-pm-update!
  (fn (_ beg tr total force)
    (def now (date-now-unix))
    (def since (if force now (- now %wget-pm-last)))
    (set! %wget-pm-last now)
    (def done? (if (> total 0) (>= tr (- total beg)) #f))
    (if (if done? #f (= since 0)) ()
      (%wget-pm-draw beg (if done? (- total beg) tr) total now))))

(def %wget-pm-draw
  (fn (_ beg tr total now)
    (def num (%wget-ulltoa5 (+ beg tr)))
    (def notty (not (sys-isatty 2)))
    (def sc
      (let go ((t total) (b beg) (x tr))
        (if (>= t 1048576) (go (%wget-div t 256) (%wget-div b 256) (%wget-div x 256))
          (list t b x))))
    (def t (first sc))
    (def b (first (rest sc)))
    (def x (first (rest (rest sc))))
    (def bar (- (%wget-columns) 48))
    (def bars
      (if (= t 0) ""
        (string-append (%wget-rjust (%wget-div (* 100 (+ b x)) t) 3)
          (string-append "% "
            (if (<= bar 2) ""
              (let ((w (if (> bar 999) 999 bar)))
                (let ((stars (%wget-div (* w (+ b x)) t)))
                  (string-concat
                    (list "|" (%wget-times stars #\*) (%wget-times (- w stars) #\space)
                          "| ")))))))))
    (def stalled
      (let ((s2 (- now %wget-pm-change)))
        (if (= x %wget-pm-size) s2
          (do (set! %wget-pm-change now)
              (set! %wget-pm-size x)
              (when (>= s2 5) (set! %wget-pm-start (+ %wget-pm-start s2)))
              0))))
    (def elapsed (- now %wget-pm-start))
    (def eta
      (match
        ((>= stalled 5) "  - stalled -")
        ((if (= t 0) #t (if (= x 0) #t (< elapsed 0))) " --:--:-- ETA")
        (#t
          (let ((e (- (%wget-div (* (- t b) elapsed) x) elapsed)))
            (let ((e (if (>= e 3600000) 3599999 e)))
              (let ((secs (% e 3600)))
                (string-concat
                  (list (%wget-rjust (%wget-div e 3600) 3) ":"
                        (%wget-02 (%wget-div secs 60)) ":" (%wget-02 (% secs 60))
                        " ETA"))))))))
    (file-write 2
      (string-concat
        (list (if notty "" "\r") (%wget-fixed %wget-pm-file 20) " "
              bars num eta (if notty "\n" ""))))
    notty))

; --- one exchange --------------------------------------------------------------

; the user's --header lines as (NAME . VALUE), the value after the colon and the
; blanks that follow it
(def %wget-user-headers
  (fn (_)
    (map (fn (_ h)
           (let ((c (%wget-index h #\: 0)))
             (if (null? c) (pair h "")
               (pair (substring h 0 c)
                     (let go ((i (+ c 1)))
                       (if (if (< i (byte-len h)) (= (byte-at h i) #\space) #f)
                         (go (+ i 1))
                         (substring h i (byte-len h))))))))
         (append (Opts values %wget-cfg "--header") ()))))

; does the user's header list name NAME, in any case
(def %wget-has-header?
  (fn (_ hs name)
    (if (null? hs) #f
      (if (string=? (%wget-lower (first (first hs))) name) #t
        (%wget-has-header? (rest hs) name)))))

; the request's headers after Host and Connection, which Http adds: busybox's
; User-Agent, Authorization and Range unless the user gave their own, the
; user's, and a form Content-Type for a post
(def %wget-headers
  (fn (_ t post)
    (def uh (%wget-user-headers))
    (def ua (%wget-value "-U" "--user-agent"))
    (append
      (if (%wget-has-header? uh "user-agent") ()
        (list (pair "User-Agent" (if (null? ua) "Wget" ua))))
      (append
        (if (if (null? (%wget-user t)) #t (%wget-has-header? uh "authorization")) ()
          (list (pair "Authorization" (string-append "Basic " (net-base64 (%wget-user t))))))
        (append
          (if (if (= %wget-beg 0) #t (%wget-has-header? uh "range")) ()
            (list (pair "Range" (string-concat (list "bytes=" (%cu-int->str %wget-beg) "-")))))
          (append uh
            (if (if (null? post) #t (%wget-has-header? uh "content-type")) ()
              (list (pair "Content-Type" "application/x-www-form-urlencoded")))))))))

; the post's body: --post-data's text, --post-file's file (- is stdin), or nil
(def %wget-post
  (fn (_ stdin-thunk)
    (def data (Opts value %wget-cfg "--post-data"))
    (def file (Opts value %wget-cfg "--post-file"))
    (match
      ((not (null? data)) data)
      ((null? file) ())
      ((string=? file "-") (stdin-thunk))
      ((not (file-exists? file))
        (%wget-die (string-concat (list "can't open '" file "': No such file or directory"))))
      (#t (file-read-all file)))))

; "Connecting to HOST (IP:PORT)" for a new server; a name that does not resolve
; is busybox's "bad address", HOST as the url spells it
(def %wget-connecting
  (fn (_ t)
    (def np (%wget-name-port t))
    (when (null? (rest np))
      (%wget-die (string-concat (list "bad address '" (%wget-host t) "'"))))
    (def ip (guard (_ ()) (net-resolve (first np))))
    (when (null? ip)
      (%wget-die (string-concat (list "bad address '" (%wget-host t) "'"))))
    (unless (%wget-quiet?)
      (%wget-say (string-concat
        (list "Connecting to " (%wget-host t) " (" ip ":" (%cu-int->str (rest np)) ")\n"))))
    ip))

; open the exchange for T: the stream, its head read.  A refused connection is
; busybox's "can't connect"; anything else that keeps a response from arriving
; -- no head, a failed handshake, a certificate that does not verify -- is its
; "error getting response".  POST answers the body to send, read now -- after
; the "Connecting to", where busybox reads --post-file -- or nil for a GET
(def %wget-open
  (fn (_ t ip post)
    (def body (post))
    (def np (%wget-name-port t))
    (def url
      (string-concat
        (list (%wget-scheme t) "://" (first np) ":" (%cu-int->str (rest np))
              "/" (%wget-path t))))
    (def opts
      (append (list (pair (lit redirects) 0))
        (if (Opts on? %wget-cfg "--no-check-certificate") (list (list (lit insecure))) ())))
    (guard (e (match
                ((not (%wget-memq (Err label e) (list (lit io) (lit value)))) (error e))
                ((eq? (%wget-err-op e) (lit connect))
                  (%wget-die (string-concat
                    (list "can't connect to remote host (" ip "): " (%wget-err-text e)))))
                (#t (%wget-die "error getting response"))))
      (http-open (if (null? body) "GET" "POST") url (%wget-headers t body) body opts))))

; --- the body ------------------------------------------------------------------

; open the output on first need: -O's file truncated, else a new file that must
; not already exist
(def %wget-out!
  (fn (_ fname)
    (when (< %wget-out-fd 0)
      (let ((named? (not (null? (%wget-value "-O" "--output-document")))))
        (let ((fd (file-open-or-err (if named? file-open-write file-open-excl) fname)))
          (if (Err err? fd)
            (%wget-die (string-concat (list "can't open '" fname "': " (file-err-text fd))))
            (do (set! %wget-out-fd fd) (set! %wget-pos 0))))))))

; write the body: answers #t when it all arrived, #f for a partial download --
; a count that ran out early, a chunk cut short, or a body with neither a
; count nor chunks, which busybox reads to the end and counts as cut short
(def %wget-retrieve
  (fn (_ s fname clen chunked?)
    (unless (%wget-quiet?)
      (%wget-say (if (= %wget-out-fd 1) "writing to stdout\n"
                   (string-concat (list "saving to '" fname "'\n")))))
    (def pm? (%wget-pm-on?))
    (def total-of
      (fn (_ tr whole?)
        (match
          (whole? (+ %wget-beg tr))
          ((if chunked? #t (null? clen)) 0)
          (#t (+ %wget-beg clen)))))
    (when pm? (do (%wget-pm-init! (%wget-last-part fname))
                  (%wget-pm-update! %wget-beg 0 (total-of 0 #f) #f)))
    (def got
      (let go ((tr 0))
        (let ((piece (guard (_ (lit broken)) (http-read s 65536))))
          (match
            ((eq? piece (lit broken)) (pair tr #f))
            ((null? piece) (pair tr (if chunked? #t (if (null? clen) #f (= tr clen)))))
            (#t
              (let ((n (rest piece)))
                (do (file-write-run %wget-out-fd piece)
                    (set! %wget-pos (+ %wget-pos n))
                    (%cu-sweep! 1)
                    ; the piece that ends a counted body goes straight to the
                    ; final update, as busybox's read loop does
                    (when (if pm? (if (null? clen) #t (< (+ tr n) clen)) #f)
                      (%wget-pm-update! %wget-beg (+ tr n) (total-of (+ tr n) #f) #f))
                    (go (+ tr n)))))))))
    (def tr (first got))
    (def whole? (rest got))
    (when pm?
      (let ((tty? (not (%wget-pm-update! %wget-beg tr (total-of tr whole?) #t))))
        (when tty? (file-write 2 "\n"))))
    (if whole?
      (do (unless (= %wget-out-fd 1) (file-truncate %wget-out-fd %wget-pos))
          (unless (%wget-quiet?)
            (%wget-say (if (= %wget-out-fd 1) "written to stdout\n"
                         (string-concat (list "'" fname "' saved\n")))))
          (pair tr #t))
      (do (%wget-say (string-concat
            (list "wget: connection closed at byte " (%cu-int->str tr) "\n")))
          (pair tr #f)))))

; --- one url ---------------------------------------------------------------------

; a byte busybox reads as part of a header's name: a letter, a digit, - . _
(def %wget-name-byte?
  (fn (_ c)
    (match
      ((if (>= c #\a) (<= c #\z) #f) #t)
      ((if (>= c #\A) (<= c #\Z) #f) #t)
      ((if (>= c #\0) (<= c #\9) #f) #t)
      (#t (%wget-memv c (list #\- #\. #\_))))))

; a header line's (NAME . VALUE) as busybox reads it: the name lowercased up to
; the colon, the value after the blanks that follow it and without trailing
; blanks; a line with no colon after its name ends the run
(def %wget-header-line
  (fn (_ line)
    (def name-end
      (let go ((i 0))
        (if (if (< i (byte-len line)) (%wget-name-byte? (byte-at line i)) #f)
          (go (+ i 1)) i)))
    (when (if (>= name-end (byte-len line)) #t (not (= (byte-at line name-end) #\:)))
      (%wget-die (string-concat (list "bad header line: " (%wget-lower (substring line 0 name-end))
                                      (substring line name-end (byte-len line))))))
    (def v0
      (let go ((i (+ name-end 1)))
        (if (if (< i (byte-len line))
              (%wget-memv (byte-at line i) (list #\space #\tab)) #f)
          (go (+ i 1)) i)))
    (def v1
      (let go ((j (byte-len line)))
        (if (if (> j v0) (%wget-memv (byte-at line (- j 1)) (list #\space #\tab)) #f)
          (go (- j 1)) j)))
    (pair (%wget-lower (substring line 0 name-end)) (substring line v0 v1))))

; download one url to its file, or check it with --spider
(def %wget-one
  (fn (_ url stdin-thunk)
    (def t0 (%wget-url url))
    (when (null? t0) (%wget-die (string-append "not an http or ftp url: " url)))
    (when (string=? (%wget-scheme t0) "ftp") (%wget-die (string-append "ftp is not supported: " url)))
    (def named (%wget-value "-O" "--output-document"))
    (def fname
      (match
        ((null? named) (%wget-fname t0 (%wget-value "-P" "--directory-prefix")))
        ((string=? named "-") "-")
        (#t named)))
    (def tries
      (let ((v (%wget-value "-t" "--tries")))
        (if (null? v) 20
          (let ((n (%wget-digits v)))
            (if (null? n) (%wget-die (string-concat (list "invalid number '" v "'"))) n)))))
    (def post (fn (_) (%wget-post stdin-thunk)))
    (set! %wget-beg 0)
    (when (if (%wget-on? "-c" "--continue") (< %wget-out-fd 0) #f)
      (let ((fd (file-open-wronly fname)))
        (when (>= fd 0)
          (let ((size (Assoc get (lit size) (file-stat fname))))
            (do (file-seek fd size)
                (set! %wget-out-fd fd) (set! %wget-pos size) (set! %wget-beg size))))))
    (%wget-attempt t0 fname post tries tries)
    (if (null? named)
      (do (when (> %wget-out-fd 1) (file-close %wget-out-fd))
          (set! %wget-out-fd -1))
      (set! %wget-reset-pos %wget-pos))))

; one try at the url; a partial download tries again from where it stopped,
; RETRIES more times -- without end when -t is 0
(def %wget-attempt
  (fn (self t0 fname post tries retries)
    (def outcome (%wget-hop t0 (%wget-connecting t0) 16 fname post))
    (when (if (number? outcome) (if (= tries 0) #t (> retries 0)) #f)
      (do (set! %wget-beg (+ %wget-beg outcome))
          (self t0 fname post tries (- retries 1))))))

; the exchange with T's server: its status and head decide between an error, a
; redirect (REDIRS more are allowed), --spider's answer and the body.  Answers
; done, or the bytes a partial download got
(def %wget-hop
  (fn (self t ip redirs fname post)
    (def s (%wget-open t ip post))
    (def head (map %wget-sanitize (http-head s)))
    (def status (http-status s))
    (when (%wget-show?) (%wget-say (string-concat (list "  " (first head) "\n"))))
    (match
      ((%wget-memv status (list 200 201 202 203 204))
        (when (> %wget-beg 0)
          (do (%wget-say "wget: restart failed\n")
              (set! %wget-beg 0)
              (when (>= %wget-out-fd 0)
                (do (file-seek %wget-out-fd %wget-reset-pos)
                    (set! %wget-pos %wget-reset-pos))))))
      ((%wget-memv status (list 300 301 302 303 307 308)) ())
      ((if (= status 206) (> %wget-beg 0) #f) ())
      (#t (do (http-close s)
              (%wget-die (string-append "server returned error: " (first head))))))
    (def found (%wget-walk s status (rest head) () #f))
    (match
      ((eq? (first found) (lit location))
        (do (http-close s)
            (when (= redirs 1) (%wget-die "too many redirections"))
            (%wget-follow t ip (first (rest found)) (- redirs 1) fname post)))
      ((%wget-on? "--spider" "--spider")
        (do (http-close s)
            (unless (%wget-quiet?) (%wget-say "remote file exists\n"))
            (lit done)))
      (#t
        (do (if (string=? fname "-") (set! %wget-out-fd 1) (%wget-out! fname))
            (let ((r (%wget-retrieve s fname (first (rest found)) (first (rest (rest found))))))
              (do (http-close s)
                  (if (rest r) (lit done) (first r)))))))))

; a Location: a path on the same server asks again with no "Connecting to"; a
; url is a new server, keeping the first url's user when it names none
(def %wget-follow
  (fn (_ t ip loc redirs fname post)
    (if (if (> (byte-len loc) 0) (= (byte-at loc 0) #\/) #f)
      (%wget-hop (list (%wget-scheme t) (%wget-host t) (substring loc 1 (byte-len loc))
                       (%wget-user t))
                 ip redirs fname post)
      (let ((t2 (%wget-url loc)))
        (do (when (null? t2) (%wget-die (string-append "not an http or ftp url: " loc)))
            (let ((t3 (if (null? (%wget-user t2))
                        (list (%wget-scheme t2) (%wget-host t2) (%wget-path t2) (%wget-user t))
                        t2)))
              (%wget-hop t3 (%wget-connecting t3) redirs fname post)))))))

; the header lines in order, as busybox reads them: (body CLEN CHUNKED?), or
; (location URL) at a Location in a 3xx; -S shows each line as it is read
(def %wget-walk
  (fn (self s status ls clen chunked?)
    (match
      ((null? ls)
        (do (when (%wget-show?) (%wget-say "  \n"))
            (list (lit body) clen chunked?)))
      (#t
        (let ((line (first ls)))
          (do (when (%wget-show?) (%wget-say (string-concat (list "  " line "\n"))))
              (let ((kv (%wget-header-line line)))
                (match
                  ((string=? (first kv) "content-length")
                    (let ((n (%wget-digits (rest kv))))
                      (if (null? n)
                        (do (http-close s)
                            (%wget-die (string-concat
                              (list "content-length " (rest kv) " is garbage"))))
                        (self s status (rest ls) n chunked?))))
                  ((string=? (first kv) "transfer-encoding")
                    (if (string=? (%wget-lower (rest kv)) "chunked")
                      (self s status (rest ls) clen #t)
                      (do (http-close s)
                          (%wget-die (string-concat
                            (list "transfer encoding '" (%wget-lower (rest kv))
                                  "' is not supported"))))))
                  ((if (string=? (first kv) "location") (>= status 300) #f)
                    (list (lit location) (rest kv)))
                  (#t (self s status (rest ls) clen chunked?)))))))))))

; --- the applet ------------------------------------------------------------------

; busybox's usage text, less the banner naming its binary; status 1
(def %wget-usage
  (fn (_)
    (file-write 2
      (string-concat
        (list "Usage: wget [-cqS] [--spider] [-O FILE] [-o LOGFILE] [--header STR]...\n"
              "\t[-U AGENT] [--post-data STR | --post-file FILE] [-Y on/off]\n"
              "\t[--no-check-certificate] [-P DIR] [-T SEC] [-t TRIES] URL...\n"
              "\nRetrieve files via HTTP or FTP\n\n"
              "\t--spider\tOnly check URL existence: $? is 0 if exists\n"
              "\t--header STR\tAdd STR (of form 'header: value') to headers\n"
              "\t-U AGENT\tUse AGENT for User-Agent header\n"
              "\t--post-data STR\tSend STR using POST method\n"
              "\t--post-file FILE\tSend FILE using POST method\n"
              "\t--no-check-certificate\tDon't validate the server's certificate\n"
              "\t-c\t\tContinue retrieval of partial download\n"
              "\t-q\t\tQuiet\n"
              "\t-P DIR\t\tSave to DIR (default .)\n"
              "\t-S    \t\tShow server response\n"
              "\t-t TRIES\tRetry count (default 20)\n"
              "\t-T SEC\t\tNetwork read timeout is SEC seconds\n"
              "\t-O FILE\t\tSave to FILE ('-' for stdout)\n"
              "\t-o LOGFILE\tLog messages to FILE\n"
              "\t-Y on/off\tUse proxy\n")))
    1))

(def %cu-wget
  (fn (_ argv stdin-thunk)
    (set! %wget-cfg (%cu-opts "wget" argv))
    (def urls (Opts operands %wget-cfg))
    (if (null? urls) (%wget-usage)
      (do (set! %wget-msg-fd 2)
          (set! %wget-out-fd (if (string=? (if (null? (%wget-value "-O" "--output-document")) ""
                                              (%wget-value "-O" "--output-document")) "-")
                               1 -1))
          (set! %wget-pos 0)
          (set! %wget-reset-pos 0)
          (%wget-run urls stdin-thunk)))))

; each url in turn; a fatal error ends the run with status 1, after the
; message, closing what the run opened
(def %wget-run
  (fn (_ urls stdin-thunk)
    (def log (%wget-value "-o" "--output-file"))
    (def opened
      (if (if (null? log) #t (string=? log "-")) ()
        (file-open-or-err file-open-write log)))
    (if (if (null? opened) #f (Err err? opened))
      (do (file-write 2 (string-concat (list "wget: can't open '" log "': " (file-err-text opened) "\n")))
          1)
      (do (unless (null? opened) (set! %wget-msg-fd opened))
          (let ((st (guard (e (if (eq? (Err label e) (lit wget))
                                (do (%wget-say (string-concat (list "wget: " (e msg) "\n"))) 1)
                                (error e)))
                      (let each ((us urls))
                        (if (null? us) 0
                          (do (%wget-one (first us) stdin-thunk) (each (rest us))))))))
            (do (when (> %wget-out-fd 1) (file-close %wget-out-fd))
                (set! %wget-out-fd -1)
                (unless (null? opened) (file-close opened))
                (set! %wget-msg-fd 2)
                st))))))

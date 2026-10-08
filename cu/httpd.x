; # x-coreutils -- the small tools, as applets
;
; ## cu/httpd.x -- httpd: busybox's web server
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; networking/httpd.c, a request at a time: the request line and headers read
; a line at a time, the url percent-decoded and made canonical, each of its
; directories' httpd.conf read on the way down, the file stat'd -- a directory
; asked without its slash is a 302 to it with one, a directory with one is its
; index page -- and the file sent with busybox's headers: Date, Last-Modified,
; ETag, Accept-Ranges, a Range's 206, an If-None-Match's 304.  An error is
; busybox's page for it, or the page an Ennn: line names.
;
; -i answers the one request on stdin and stdout.  Without it httpd listens on
; -p's port (80 unless given) -- every address's, or one address's for
; -p HOST[:PORT] -- and answers each connection in a process of its own; without -f it first leaves the terminal, as bb_daemonize does.  A
; connection's process is the grandchild of the listener, so none is left to
; reap: busybox ignores SIGCHLD to the same end.
;
; httpd.conf is read from /etc, or from the home directory when /etc has none,
; or from -c's file: I: (the index page), H: (the home), A:/D: (the addresses
; allowed and denied), Ennn: (an error page), .ext: (a type) and *.ext: (an
; interpreter) take effect.  Basic authentication, the proxy and gzip are not
; served yet: their lines are read and held.
;
; A file under cgi-bin/ that can be run, a file an interpreter is named for,
; and cgi-bin/index.cgi for a directory with no index page are CGI scripts:
; run with the request in their environment and its body on their stdin.  The
; script is run as ./NAME (the platform's exec looks names up on PATH, so a
; bare NAME could find another program), where busybox's argv[0] is NAME.

; --- the state a run sets --------------------------------------------------------

(def %hd-verbose 0)
(def %hd-name "httpd")        ; the prefix of a message: the peer's IP:PORT with -v
(def %hd-index "index.html")
(def %hd-conf ())             ; -c's file, or nil
(def %hd-mime ())             ; .ext:type lines, the last read first
(def %hd-scripts ())          ; *.ext:interpreter lines
(def %hd-auth ())             ; /path:user:pass lines
(def %hd-proxy ())            ; P: lines
(def %hd-errpages ())         ; (STATUS . PAGE)
(def %hd-acl ())              ; (IP MASK A-OR-D), the D lines first
(def %hd-deny-all #f)
(def %hd-remote-ip 0)
(def %hd-rmt ())              ; the peer as IP:PORT, nil when there is none
(def %hd-home "")             ; the home, absolute when -h gave one or none was given

; per request
(def %hd-in "")               ; read and not yet taken
(def %hd-read ())             ; answers the next piece of the request, nil at its end
(def %hd-file-size -1)
(def %hd-last-mod 0)
(def %hd-mime-found ())
(def %hd-moved ())
(def %hd-query ())
(def %hd-range-start -1)
(def %hd-range-end 0)
(def %hd-range-len -1)
(def %hd-if-none-match ())
(def %hd-etag "")
(def %hd-post-len 0)          ; a POST's Content-Length
(def %hd-cgi-env ())          ; (NAME . VALUE) a script is given from the headers
(def %hd-hdr-total 0)         ; the header lines' bytes so far
(def %hd-interp ())           ; the interpreter a *.ext: line names for the file
(def %hd-authorized -1)       ; -1 until a check, then #t or #f
(def %hd-remote-user ())      ; the user an Authorization: line named and a check passed

; the response is over: the run's top answers 0
(def %hd-done (fn (_) (Err raise (lit httpd-done) "" ())))

(def %hd-log
  (fn (_ msg) (file-write 2 (string-concat (list %hd-name ": " msg "\n")))))

; a fatal error before any request: the message, status 1
(def %hd-die (fn (_ msg) (Err raise (lit net) msg ())))

; --- small pieces ----------------------------------------------------------------

(def %hd-hex
  (fn (_ n)
    (if (< n 0) "ffffffffffffffff"
      (let go ((n n) (acc ""))
        (let ((d (% n 16)))
          (let ((s (string-append (substring "0123456789abcdef" d (+ d 1)) acc)))
            (if (< n 16) s (go (%wget-div n 16) s))))))))

(def %hd-http-date
  (fn (_ secs) (%cu-date-fmt "%a, %d %b %Y %H:%M:%S GMT" (%cu-date-split secs #t) secs)))

; S starts with P, letters compared without case
(def %hd-prefix-ci?
  (fn (_ s p)
    (if (< (byte-len s) (byte-len p)) #f
      (string=? (%wget-lower (substring s 0 (byte-len p))) (%wget-lower p)))))

(def %hd-skip-blanks
  (fn (_ s i)
    (if (if (< i (byte-len s)) (%wget-memv (byte-at s i) (list #\space #\tab)) #f)
      (%hd-skip-blanks s (+ i 1)) i)))

(def %hd-after-header
  (fn (_ line name) (substring line (%hd-skip-blanks line (byte-len name)) (byte-len line))))

; the decimal digits at I of S: (N . END), N nil when there are none
(def %hd-num-at
  (fn (_ s i)
    (let go ((j i) (n 0))
      (if (if (< j (byte-len s)) (if (>= (byte-at s j) #\0) (<= (byte-at s j) #\9) #f) #f)
        (go (+ j 1) (+ (* n 10) (- (byte-at s j) #\0)))
        (pair (if (= j i) () n) j)))))

; --- the request's lines -----------------------------------------------------------

; get_line: the next line without its CR and LF, or "" at the end; a control
; byte other than a tab, or a line of 8192 bytes, is a 400
(def %hd-line
  (fn (self)
    (def nl (%wget-index %hd-in #\newline 0))
    (if (if (null? nl) (> (byte-len %hd-in) 8192) #f) (%hd-fail 400)
      (if (null? nl)
        (let ((r (%hd-read)))
          (if (null? r)
            (let ((l %hd-in)) (do (set! %hd-in "") (%hd-check-line l)))
            (do (set! %hd-in (string-append %hd-in (substring (first r) 0 (rest r)))) (self))))
        (let ((l (substring %hd-in 0 nl)))
          (do (set! %hd-in (substring %hd-in (+ nl 1) (byte-len %hd-in)))
              (%hd-check-line l)))))))

(def %hd-check-line
  (fn (_ l)
    (def s (Str8 replace "\r" "" l))
    (let go ((i 0))
      (match
        ((= i (byte-len s)) (if (>= (byte-len s) 8192) (%hd-fail 400) s))
        ((let ((c (byte-at s i))) (if (= c #\tab) #f (if (< c 32) #t (= c 127)))) (%hd-fail 400))
        (#t (go (+ i 1)))))))

; --- the response's head ----------------------------------------------------------

(def %hd-reasons
  (list (list 200 "OK" ()) (list 206 "Partial Content" ()) (list 302 "Found" ())
        (list 304 "Not Modified" ())
        (list 408 "Request Timeout" "No request appeared within 60 seconds")
        (list 501 "Not Implemented" "The requested method is not recognized")
        (list 401 "Unauthorized" "")
        (list 404 "Not Found" "The requested URL was not found")
        (list 400 "Bad Request" "Unsupported method")
        (list 403 "Forbidden" "")
        (list 500 "Internal Server Error" "Internal Server Error")
        (list 413 "Entity Too Large" "Entity Too Large")))

(def %hd-write-all
  (fn (_ s) (file-write-run 1 (pair s (byte-len s)))))

; send_headers: the status line and busybox's headers; for a page of busybox's
; own, the page; for a status an Ennn: line names a readable page for, that
; page in place of busybox's
(def %hd-send-headers
  (fn (_ code)
    (def row (let go ((rs %hd-reasons)) (if (null? rs) (list code "" ()) (if (= (first (first rs)) code) (first rs) (go (rest rs))))))
    (def reason (first (rest row)))
    (def info (first (rest (rest row))))
    (when (> %hd-verbose 0) (%hd-log (string-append "response:" (%cu-int->str code))))
    (def now (date-now-unix))
    (def head
      (string-concat
        (list "HTTP/1.1 " (%cu-int->str code) " " reason "\r\n"
              "Date: " (%hd-http-date now) "\r\n"
              "Connection: close\r\n"
              (if (if (= code 200) (null? %hd-mime-found) #f) ""
                (string-concat (list "Content-type: " (if (= code 200) %hd-mime-found "text/html") "\r\n")))
              (if (= code 401) (string-concat (list "WWW-Authenticate: Basic realm=\"" %hd-realm "\"\r\n")) "")
              (if (= code 302)
                (string-concat (list "Location: " %hd-moved "/" (if (null? %hd-query) "" (string-append "?" %hd-query)) "\r\n"))
                ""))))
    (def page (let ((p (Assoc find code %hd-errpages))) (if (null? p) () (rest p))))
    (if (if (null? page) #f (%t-permitted? page 4))
      (do (%hd-write-all (string-append head "\r\n"))
          (%hd-send-file page #f))
      (%hd-write-all
        (string-concat
          (list head
                (if (= %hd-file-size -1) ""
                  (let ((size (if (= code 206)
                                (- (+ %hd-range-end 1) %hd-range-start)
                                %hd-file-size)))
                    (string-concat
                      (list (if (= code 206)
                              (string-concat (list "Content-Range: bytes " (%cu-int->str %hd-range-start) "-"
                                                   (%cu-int->str %hd-range-end) "/" (%cu-int->str %hd-file-size) "\r\n"))
                              "")
                            "Accept-Ranges: bytes\r\n"
                            "Last-Modified: " (%hd-http-date %hd-last-mod) "\r\n"
                            "ETag: " %hd-etag "\r\n"
                            "Content-Length: " (%cu-int->str size) "\r\n"))))
                "\r\n"
                (if (null? info) ""
                  (string-concat
                    (list "<HTML><HEAD><TITLE>" (%cu-int->str code) " " reason "</TITLE></HEAD>\n"
                          "<BODY><H1>" (%cu-int->str code) " " reason "</H1>\n"
                          info "\n"
                          "</BODY></HTML>\n")))))))))

(def %hd-realm "Web Server Authentication")

; send_headers_and_exit: no file's headers, then the end
(def %hd-fail
  (fn (_ code)
    (set! %hd-file-size -1)
    (%hd-send-headers code)
    (%hd-finish)))

; send_EOF_and_exit: the write side shut, so the peer sees the end
(def %hd-finish
  (fn (_)
    (guard (_ ()) (net-shutdown 1))
    (when (> %hd-verbose 2) (%hd-log "closed"))
    (%hd-done)))

; --- the file ----------------------------------------------------------------------

; busybox's table: a suffix is looked for in each line in turn, and a line where
; it is found but is not a whole suffix ends the search
(def %hd-mime-table
  (list (pair ".txt.h.c.cc.cpp" "text/plain") (pair ".htm.html" "text/html")
        (pair ".jpg.jpeg" "image/jpeg") (pair ".gif" "image/gif") (pair ".png" "image/png")
        (pair ".svg" "image/svg+xml") (pair ".css" "text/css") (pair ".js" "application/javascript")
        (pair ".wav" "audio/wav") (pair ".avi" "video/x-msvideo") (pair ".qt.mov" "video/quicktime")
        (pair ".mpe.mpeg" "video/mpeg") (pair ".mid.midi" "audio/midi") (pair ".mp3" "audio/mpeg")))

(def %hd-mime-of
  (fn (_ url)
    (def dot (%wget-last-index url #\.))
    (if (null? dot) ()
      (let ((suffix (substring url dot (byte-len url))))
        (let ((user (let go ((ms %hd-mime))
                      (match ((null? ms) ())
                             ((string=? (first (first ms)) suffix) (rest (first ms)))
                             (#t (go (rest ms))))))
              (builtin (let go ((ts %hd-mime-table))
                         (if (null? ts) ()
                           (let ((at (%wget-find (first (first ts)) suffix)))
                             (if (null? at) (go (rest ts))
                               (let ((end (+ at (byte-len suffix))) (line (first (first ts))))
                                 (if (if (= end (byte-len line)) #t (= (byte-at line end) #\.))
                                   (rest (first ts))
                                   ()))))))))
          (if (null? user) builtin user))))))

; send_file_and_exit: URL's file, with its headers when HEADERS?; a page sent
; for an error has its headers already
(def %hd-send-file
  (fn (_ url headers?)
    (def fd (file-open-read url))
    (when (< fd 0) (if headers? (%hd-fail 404) (%hd-finish)))
    (set! %hd-etag (string-concat (list "\"" (%hd-hex %hd-last-mod) "-" (%hd-hex %hd-file-size) "\"")))
    (when (if (null? %hd-if-none-match) #f (not (null? (%wget-find %hd-if-none-match %hd-etag))))
      (%hd-fail 304))
    (set! %hd-mime-found (%hd-mime-of url))
    (unless headers? (set! %hd-range-start -1))
    (def ranged?
      (if (>= %hd-range-start 0)
        (do (when (if (= %hd-range-end 0) #t (> %hd-range-end (- %hd-file-size 1)))
              (set! %hd-range-end (- %hd-file-size 1)))
            (if (< %hd-range-end %hd-range-start)
              (do (set! %hd-range-start -1) #f)
              (do (set! %hd-range-len (- (+ %hd-range-end 1) %hd-range-start))
                  (file-seek fd %hd-range-start)
                  (%hd-send-headers 206)
                  #t)))
        #f))
    (when (if headers? (not ranged?) #f) (%hd-send-headers 200))
    (let go ((left (if ranged? %hd-range-len -1)))
      (unless (= left 0)
        (let ((r (file-read-run fd 8192)))
          (when (> (rest r) 0)
            (let ((n (if (if (>= left 0) (< left (rest r)) #f) left (rest r))))
              (do (file-write-run 1 (pair (first r) n))
                  (%cu-sweep! 1)
                  (go (if (>= left 0) (- left n) -1))))))))
    (file-close fd)
    (%hd-finish)))

; --- the url -------------------------------------------------------------------------

; percent_decode_in_place: STRICT, nil for a bad escape and encoded for an escaped
; / or NUL; not STRICT, + is a space and a bad escape stays
(def %hd-hexv
  (fn (_ c)
    (match ((if (>= c #\0) (<= c #\9) #f) (- c #\0))
           ((if (>= c #\a) (<= c #\f) #f) (+ 10 (- c #\a)))
           ((if (>= c #\A) (<= c #\F) #f) (+ 10 (- c #\A)))
           (#t 99))))

(def %hd-pct-decode
  (fn (_ s strict)
    (let go ((i 0) (acc ()))
      (if (>= i (byte-len s)) (bytes->str (reverse acc))
        (let ((c (byte-at s i)))
          (match
            ((if (not strict) (= c #\+) #f) (go (+ i 1) (pair #\space acc)))
            ((not (= c #\%)) (go (+ i 1) (pair c acc)))
            (#t
              (let ((hi (if (< (+ i 1) (byte-len s)) (%hd-hexv (byte-at s (+ i 1))) 99))
                    (lo (if (< (+ i 2) (byte-len s)) (%hd-hexv (byte-at s (+ i 2))) 99)))
                (if (if (> hi 15) #t (> lo 15))
                  (if strict () (go (+ i 1) (pair #\% acc)))
                  (let ((v (+ (* hi 16) lo)))
                    (if (if strict (if (= v #\/) #t (= v 0)) #f) (lit encoded)
                      (go (+ i 3) (pair v acc)))))))))))))

; the canonical path: duplicate slashes and /./ gone, /../ taking the
; directory before it; nil when .. would climb above the root
(def %hd-canon
  (fn (_ in)
    (let go ((t 0) (out "/"))
      (def at-slash (= (byte-at out (- (byte-len out) 1)) #\/))
      (def c (if (< t (byte-len in)) (byte-at in t) 0))
      (def c1 (if (< (+ t 1) (byte-len in)) (byte-at in (+ t 1)) 0))
      (def c2 (if (< (+ t 2) (byte-len in)) (byte-at in (+ t 2)) 0))
      (match
        ((if at-slash (= c #\/) #f) (go (+ t 1) out))
        ((if at-slash (if (= c #\.) (if (= c1 #\.) (if (= c2 #\/) #t (= c2 0)) #f) #f) #f)
          (if (= (byte-len out) 1) ()
            (let ((cut (%wget-last-index (substring out 0 (- (byte-len out) 1)) #\/)))
              (go (+ t 2) (substring out 0 (+ cut 1))))))
        ((if at-slash (if (= c #\.) (if (= c1 #\/) #t (= c1 0)) #f) #f) (go (+ t 1) out))
        ((= c 0) out)
        (#t (go (+ t 1) (string-append out (substring in t (+ t 1)))))))))

; --- httpd.conf -----------------------------------------------------------------------

; scan_ip: the dotted quad at the start of S, as many parts as there are, then
; END or nothing: (IP AUTOMASK REST), nil for a malformed one
(def %hd-scan-ip
  (fn (_ s endc)
    (if (if (> (byte-len s) 0) (= (byte-at s 0) #\/) #f) ()
      (let go ((j 0) (p 0) (ip 0) (auto 8))
        (if (= j 4)
          (match
            ((= p (byte-len s)) (list ip auto ""))
            ((not (= (byte-at s p) endc)) ())
            ((= (+ p 1) (byte-len s)) ())
            (#t (list ip auto (substring s (+ p 1) (byte-len s)))))
          (let ((c (if (< p (byte-len s)) (byte-at s p) 0)))
            (if (if (if (< c #\0) #t (> c #\9)) (if (= c #\/) #f (not (= c 0))) #f) ()
              (let ((num (%hd-num-at s p)))
                (let ((octet (if (null? (first num)) 0 (first num))) (q (rest num)))
                  (if (> octet 255) ()
                    (let ((q2 (if (if (< q (byte-len s)) (= (byte-at s q) #\.) #f) (+ q 1) q)))
                      (go (+ j 1) q2 (+ (* ip 256) octet) (if (< q2 (byte-len s)) (+ auto 8) auto)))))))))))))

; scan_ip_mask: (IP . MASK), nil when malformed
(def %hd-scan-ip-mask
  (fn (_ s)
    (def r (%hd-scan-ip s #\/))
    (if (null? r) ()
      (let ((ip (first r)) (rest-s (first (rest (rest r)))))
        (if (= (byte-len rest-s) 0)
          (pair ip (%hd-mask-bits (first (rest r))))
          (let ((num (%hd-num-at rest-s 0)))
            (match
              ((if (< (rest num) (byte-len rest-s)) (= (byte-at rest-s (rest num)) #\.) #f)
                (let ((m (%hd-scan-ip rest-s 0)))
                  (if (if (null? m) #t (not (= (first (rest m)) 32))) () (pair ip (first m)))))
              ((if (null? (first num)) #t (< (rest num) (byte-len rest-s))) ())
              ((> (first num) 32) ())
              (#t (pair ip (%hd-mask-bits (first num)))))))))))

; the mask of N leading one bits
(def %hd-mask-bits
  (fn (_ n) (- 4294967296 (%hd-pow2 (- 32 n)))))

(def %hd-pow2 (fn (self n) (if (= n 0) 1 (* 2 (self (- n 1))))))

(def %hd-bitand
  (fn (_ a b)
    (let go ((a a) (b b) (bit 1) (acc 0))
      (if (if (= a 0) #t (= b 0)) acc
        (go (%wget-div a 2) (%wget-div b 2) (* bit 2)
            (if (if (= (% a 2) 1) (= (% b 2) 1) #f) (+ acc bit) acc))))))

; if_ip_denied_send_HTTP_FORBIDDEN_and_exit
(def %hd-check-ip
  (fn (_)
    (let go ((as %hd-acl))
      (if (null? as) (when %hd-deny-all (%hd-fail 403))
        (let ((a (first as)))
          (if (= (%hd-bitand %hd-remote-ip (first (rest a))) (first a))
            (unless (= (first (rest (rest a))) #\A) (%hd-fail 403))
            (go (rest as))))))))

(def %hd-conf-error
  (fn (_ line file) (%hd-log (string-concat (list "config error '" line "' in '" file "'")))))

; parse_conf: PATH/httpd.conf, or -c's file for the first parse.  The first
; parse falls back to ./httpd.conf; a subdirectory's answers #f when it has
; none.  The addresses are read afresh each time, the types and the rest
; only by the first parse
(def %hd-parse-conf
  (fn (_ path first?)
    (set! %hd-acl ())
    (set! %hd-deny-all #f)
    (when first? (do (set! %hd-mime ()) (set! %hd-scripts ()) (set! %hd-auth ())))
    (def name (if (if first? (not (null? %hd-conf)) #f) %hd-conf (string-append path "/httpd.conf")))
    (def found
      (match
        ((%t-permitted? name 4) name)
        ((not first?) ())
        ((not (null? %hd-conf)) (%hd-die (string-append %hd-conf ": No such file or directory")))
        ((%t-permitted? "httpd.conf" 4) "httpd.conf")
        (#t ())))
    (if (null? found) #f
      (do (map (fn (_ l) (%hd-conf-line l found first? path))
                    (%cu-lines (file-read-all found)))
          #t))))

(def %hd-conf-line
  (fn (_ raw file first? path)
    (def cut (let go ((i 0)) (if (if (< i (byte-len raw)) (not (= (byte-at raw i) #\#)) #f) (go (+ i 1)) i)))
    (def line (Str8 replace "\t" "" (Str8 replace " " "" (substring raw 0 cut))))
    (def colon (%wget-index line #\: 0))
    (def after (if (null? colon) "" (substring line (+ colon 1) (byte-len line))))
    (def ch (if (= (byte-len line) 0) 0 (byte-at line 0)))
    (def up (if (if (>= ch #\a) (<= ch #\z) #f) (- ch 32) ch))
    (match
      ((= (byte-len line) 0) ())
      ((= (byte-len after) 0) (%hd-conf-error line file))
      ((= up #\I) (set! %hd-index after))
      ((if first? (= up #\H) #f)
        (if (%hd-chdir after) (set! %hd-home after)
          (%hd-die (string-concat (list "can't change directory to '" after "': No such file or directory")))))
      ((if (= up #\A) #t (= up #\D)) (%hd-conf-acl! up after))
      ((if first? (= up #\E) #f) (%hd-conf-errpage! line after file))
      ((if first? (= up #\P) #f) (%hd-conf-proxy! line after file))
      ((= ch #\.) (set! %hd-mime (pair (pair (substring line 0 colon) after) %hd-mime)))
      ((if (= ch #\*) (if (> (byte-len line) 1) (= (byte-at line 1) #\.) #f) #f)
        (set! %hd-scripts (pair (pair (substring line 1 colon) after) %hd-scripts)))
      ((= ch #\/) (%hd-conf-auth! (string-append (if first? "" (string-append "/" path)) (substring line 0 colon)) after))
      (#t (%hd-conf-error line file)))))

; /path:user:pass, the path made canonical, kept longest first -- and ahead of
; an earlier line of the same length
(def %hd-conf-auth!
  (fn (_ path up)
    (def c (let ((p (%hd-canon path))) (if (null? p) "/" p)))
    (def key (if (if (> (byte-len c) 1) (= (byte-at c (- (byte-len c) 1)) #\/) #f)
               (substring c 0 (- (byte-len c) 1)) c))
    (set! %hd-auth
      (let go ((as %hd-auth))
        (if (if (null? as) #t (>= (byte-len key) (byte-len (first (first as)))))
          (pair (pair key up) as)
          (pair (first as) (go (rest as))))))))

; check_user_passwd: UP (user:pass) against the /path: lines whose path is a
; prefix of PATH at a slash.  Once one matches, only lines of the same path are
; asked.  A user of * matches anyone; a password of * is the user's in
; /etc/passwd or /etc/shadow; one starting $1$ is compared as md5-crypt, any
; other as plain text.  #t when one agrees -- the user then named -- or when no
; line's path matches at all
(def %hd-check-auth
  (fn (_ path up)
    (let go ((as %hd-auth) (prev ()))
      (if (null? as) (null? prev)
        (let ((dir (first (first as))) (entry (rest (first as))))
          (match
            ((if (null? prev) #f (not (string=? prev dir))) (go (rest as) prev))
            ((not (%hd-auth-prefix? dir path)) (go (rest as) prev))
            ((%hd-auth-entry-ok? entry up)
              (do (set! %hd-remote-user (let ((c (%wget-index up #\: 0))) (if (null? c) up (substring up 0 c))))
                  #t))
            (#t (go (rest as) dir))))))))

(def %hd-auth-prefix?
  (fn (_ dir path)
    (if (= (byte-len dir) 1) #t
      (if (Str8 starts? dir path)
        (if (= (byte-len path) (byte-len dir)) #t (= (byte-at path (byte-len dir)) #\/))
        #f))))

; one user:pass line against UP
(def %hd-auth-entry-ok?
  (fn (_ entry up)
    (def uc (%wget-index up #\: 0))
    (def ec (%wget-index entry #\: 0))
    (match
      ((if (null? uc) #t (null? ec)) (string=? entry up))
      ((if (= (byte-at entry 0) #\*) #f (not (string=? (substring entry 0 (+ ec 1)) (substring up 0 (+ uc 1))))) #f)
      (#t (%hd-password-ok? (substring entry (+ ec 1) (byte-len entry))
                            (substring up 0 uc) (substring up (+ uc 1) (byte-len up)))))))

(def %hd-password-ok?
  (fn (_ stored user given)
    (match
      ((Str8 starts? "*" stored)
        (let ((sys (%hd-system-password user)))
          (if (null? sys) #f (%hd-crypt-equal? given sys))))
      ((if (> (byte-len stored) 1) (if (= (byte-at stored 0) #\$)
                                     (if (= (byte-at stored 1) #\y) #t (%hd-alnum? (byte-at stored 1))) #f) #f)
        (%hd-crypt-equal? given stored))
      (#t (string=? given stored)))))

; pw_encrypt GIVEN with STORED's salt, compared: $1$ is md5-crypt; the other
; hashes busybox reads ($5$, $6$, $y$, DES) never agree here
(def %hd-crypt-equal?
  (fn (_ given stored)
    (if (Str8 starts? "$1$" stored)
      (string=? (%cu-md5-crypt given (substring stored 3 (byte-len stored))) stored)
      #f)))

; USER's password field from /etc/passwd, or /etc/shadow's when that is x or *
(def %hd-system-password
  (fn (_ user)
    (def pw (%hd-passwd-field "/etc/passwd" user))
    (if (if (null? pw) #f (if (string=? pw "x") #t (string=? pw "*")))
      (let ((sp (%hd-passwd-field "/etc/shadow" user))) (if (null? sp) pw sp))
      pw)))

(def %hd-passwd-field
  (fn (_ file user)
    (if (not (%t-permitted? file 4)) ()
      (let go ((ls (%cu-lines (file-read-all file))))
        (if (null? ls) ()
          (let ((l (first ls)) (c (%wget-index (first ls) #\: 0)))
            (if (if (null? c) #f (string=? (substring l 0 c) user))
              (let ((c2 (%wget-index l #\: (+ c 1))))
                (substring l (+ c 1) (if (null? c2) (byte-len l) c2)))
              (go (rest ls)))))))))

; A: or D: AFTER: * (D:* denies every address no A: line allows), or an
; address and mask; a malformed one denies every address.  D lines go first
(def %hd-conf-acl!
  (fn (_ up after)
    (if (if (> (byte-len after) 0) (= (byte-at after 0) #\*) #f)
      (when (= up #\D) (set! %hd-deny-all #t))
      (let ((m (%hd-scan-ip-mask after)))
        (let ((row (if (null? m) (list 0 0 #\D) (list (first m) (rest m) up))))
          (if (= (first (rest (rest row))) #\D)
            (set! %hd-acl (pair row %hd-acl))
            (set! %hd-acl (append %hd-acl (list row)))))))))

; Ennn:PAGE, for a status busybox has a page of its own for
(def %hd-conf-errpage!
  (fn (_ line after file)
    (let ((n (first (%hd-num-at line 1))))
      (match
        ((if (null? n) #t (< n 100)) (%hd-conf-error line file))
        ((%wget-memv n (map first %hd-reasons))
          (set! %hd-errpages (pair (pair n after) %hd-errpages)))
        (#t ())))))

; P:/url:[http://]host[:port]/path, held for the proxy
(def %hd-conf-proxy!
  (fn (_ line after file)
    (let ((c2 (%wget-index after #\: 0)))
      (if (null? c2) (%hd-conf-error line file)
        (let ((hp (let ((h (substring after (+ c2 1) (byte-len after))))
                    (if (Str8 starts? "http://" h) (substring h 7 (byte-len h)) h))))
          (if (if (= (byte-len hp) 0) #t (null? (%wget-index hp #\/ 0))) (%hd-conf-error line file)
            (set! %hd-proxy (pair (list (substring after 0 c2) hp) %hd-proxy))))))))

; --- one request ------------------------------------------------------------------------

(def %hd-reset-request!
  (fn (_ read)
    (set! %hd-in "") (set! %hd-read read)
    (set! %hd-file-size -1) (set! %hd-last-mod 0) (set! %hd-mime-found ())
    (set! %hd-moved ()) (set! %hd-query ())
    (set! %hd-range-start -1) (set! %hd-range-end 0) (set! %hd-range-len -1)
    (set! %hd-if-none-match ()) (set! %hd-etag "")
    (set! %hd-post-len 0) (set! %hd-cgi-env ()) (set! %hd-hdr-total 0) (set! %hd-interp ())
    (set! %hd-authorized -1) (set! %hd-remote-user ())))

; handle_incoming_and_exit
(def %hd-handle
  (fn (_)
    (when (> %hd-verbose 2) (%hd-log "connected"))
    (%hd-check-ip)
    (def line (%hd-line))
    (when (= (byte-len line) 0)
      (do (when (> %hd-verbose 2) (%hd-log "eof on read, closing")) (%hd-done)))
    (def sp1 (%wget-index line #\space 0))
    (when (null? sp1) (%hd-fail 400))
    (def method (substring line 0 sp1))
    (def sp2 (%wget-index line #\space (+ sp1 1)))
    (when (if (null? sp2) #t (not (Str8 starts? "HTTP/" (substring line (+ sp2 1) (byte-len line)))))
      (%hd-fail 400))
    (def url0 (substring line (+ sp1 1) sp2))
    (when (if (= (byte-len url0) 0) #t (not (= (byte-at url0 0) #\/))) (%hd-fail 400))
    ; GET, HEAD and POST; any other method is a 400, as busybox's copy of it
    ; measures its length as nothing
    (unless (%cu-member-s? method (list "GET" "HEAD" "POST")) (%hd-fail 400))
    (def q (%wget-index url0 #\? 0))
    (set! %hd-query (if (null? q) () (substring url0 (+ q 1) (byte-len url0))))
    (def decoded (%hd-pct-decode (if (null? q) url0 (substring url0 0 q)) #t))
    (when (null? decoded) (%hd-fail 400))
    (when (eq? decoded (lit encoded)) (%hd-fail 404))
    (def url (%hd-canon decoded))
    (when (null? url) (%hd-fail 400))
    (when (> %hd-verbose 1) (%hd-log (string-concat (list method " " url))))
    (let go ((i 1))
      (let ((s (%wget-index url #\/ i)))
        (unless (null? s)
          (do (when (%hd-parse-conf (substring url 1 s) #f) (%hd-check-ip))
              (go (+ s 1))))))
    (def rel (substring url 1 (byte-len url)))
    (def dir-url? (= (byte-at url (- (byte-len url) 1)) #\/))
    ; the stat: under cgi-bin/ a script (cgi #t) unless the file is there and
    ; no one may run it; elsewhere the file, the index page of a directory url,
    ; or a directory asked without its slash -- and a directory url with no
    ; index page is cgi-bin/index.cgi's, when that may be run
    (def target (if (if dir-url? (not (Str8 starts? "cgi-bin/" rel)) #f) (string-append rel %hd-index) rel))
    (def cgi (%hd-locate url rel target dir-url?))
    (%hd-headers (string=? method "POST") (not (null? cgi)) url)
    (when (string=? (%wget-last-part url) "httpd.conf") (%hd-fail 403))
    ; no Authorization: line: a path the /path: lines guard is refused
    (when (number? %hd-authorized) (set! %hd-authorized (%hd-check-auth url "")))
    (unless %hd-authorized (%hd-fail 401))
    (unless (null? %hd-moved) (%hd-fail 302))
    (unless (null? cgi)
      (%hd-send-cgi (if (eq? cgi (lit index)) "/cgi-bin/index.cgi" url) url method))
    (unless (%cu-member-s? method (list "GET" "HEAD")) (%hd-fail 501))
    (%hd-send-file target #t)))

; the stat: the script to run -- normal under cgi-bin/, index for
; cgi-bin/index.cgi, interp for a file a *.ext: line names an interpreter for
; -- or nil for a file to send (or a 302 to make)
(def %hd-locate
  (fn (_ url rel target dir-url?)
    (match
      ((Str8 starts? "cgi-bin/" rel)
        (if (file-exists? rel) (%hd-cgi-file (file-stat rel) rel) (lit normal)))
      ((file-exists? target)
        (let ((st (file-stat target)))
          (if (if (not dir-url?) (eq? (Assoc get (lit file-type) st) (lit dir)) #f)
            (do (set! %hd-moved url) ())
            (do (%hd-stat! st) (%hd-interp-for target)))))
      (dir-url? (if (%t-permitted? "cgi-bin/index.cgi" 1) (lit index) (%hd-fail 404)))
      (#t ()))))

; interp when a *.ext: line names TARGET's suffix, its interpreter kept
(def %hd-interp-for
  (fn (_ target)
    (def dot (%wget-last-index target #\.))
    (def hit (if (null? dot) ()
               (let ((suffix (substring target dot (byte-len target))))
                 (let go ((ss %hd-scripts))
                   (match ((null? ss) ())
                          ((string=? (first (first ss)) suffix) (first ss))
                          (#t (go (rest ss))))))))
    (if (null? hit) ()
      (do (set! %hd-interp (rest hit)) (lit interp)))))

; the header lines, to the blank one, 32 KiB of them at most (413 past that):
; a POST's Content-Length, Range and If-None-Match are read; for a script
; every other line is a variable of its environment
(def %hd-headers
  (fn (self post? cgi? url)
    (let ((h (%hd-line)))
      (unless (= (byte-len h) 0)
        (do (set! %hd-hdr-total (+ %hd-hdr-total (byte-len h)))
            (when (>= %hd-hdr-total 32768) (%hd-fail 413))
            (match
              ((if post? (%hd-prefix-ci? h "Content-Length:") #f)
                (%hd-content-length! (%hd-after-header h "Content-Length:")))
              ((%hd-prefix-ci? h "Authorization:") (%hd-authorization! h url cgi?))
              ((%hd-prefix-ci? h "Range:") (%hd-range! (%hd-after-header h "Range:")))
              ((%hd-prefix-ci? h "If-None-Match:")
                (set! %hd-if-none-match (%hd-after-header h "If-None-Match:")))
              (cgi? (%hd-cgi-header! h))
              (#t ()))
            (self post? cgi? url))))))

; Authorization: Basic CREDENTIALS, decoded and checked against URL's /path:
; lines; any other scheme is a header like the rest
(def %hd-authorization!
  (fn (_ h url cgi?)
    (let ((v (%hd-after-header h "Authorization:")))
      (if (%hd-prefix-ci? v "Basic")
        (set! %hd-authorized (%hd-check-auth url (%hd-b64-decode (substring v 5 (byte-len v)))))
        (when cgi? (%hd-cgi-header! h))))))

; decode_base64: the characters of the alphabet decoded, any other byte passed
; over, the first = ending it
(def %hd-b64-decode
  (fn (_ s)
    (def eq (%wget-index s #\= 0))
    (def body (if (null? eq) s (substring s 0 eq)))
    (def out (list ""))
    (%cu-b64-decode-to body (fn (_ r) (set-first! out (string-append (first out) (substring (first r) 0 (rest r))))) #t)
    (first out)))

; a POST's length: digits and nothing else, or a 400
(def %hd-content-length!
  (fn (_ v)
    (let ((n (%hd-num-at v 0)))
      (if (if (null? (first n)) #t (< (rest n) (byte-len v)))
        (%hd-fail 400)
        (set! %hd-post-len (first n))))))

; NAME: VALUE as HTTP_NAME=VALUE -- letters upper case, any other byte but a
; digit an underscore -- and Content-Type as CONTENT_TYPE
(def %hd-cgi-header!
  (fn (_ h)
    (def colon (%wget-index h #\: 0))
    (unless (null? colon)
      (let ((name (bytes->str (map (fn (_ c) (match ((if (>= c #\a) (<= c #\z) #f) (- c 32))
                                                    ((if (>= c #\A) (<= c #\Z) #f) c)
                                                    ((if (>= c #\0) (<= c #\9) #f) c)
                                                    (#t #\_)))
                                   (%tftp-bytes h 0 colon))))
            (value (substring h (%hd-skip-blanks h (+ colon 1)) (byte-len h))))
        (set! %hd-cgi-env
          (pair (pair (if (%hd-prefix-ci? h "Content-Type:") name (string-append "HTTP_" name)) value)
                %hd-cgi-env))))))

; Range: bytes=START-[END], as busybox reads it: anything else, or an END
; before START, leaves the file whole
(def %hd-range!
  (fn (_ v)
    (when (Str8 starts? "bytes=" v)
      (let ((a (%hd-num-at v 6)))
        (match
          ((null? (first a)) ())
          ((if (>= (rest a) (byte-len v)) #t (not (= (byte-at v (rest a)) #\-))) ())
          ((= (+ (rest a) 1) (byte-len v)) (set! %hd-range-start (first a)))
          (#t (%hd-range-end! v a)))))))

(def %hd-range-end!
  (fn (_ v a)
    (let ((b (%hd-num-at v (+ (rest a) 1))))
      (unless (if (null? (first b)) #t (if (< (rest b) (byte-len v)) #t (< (first b) (first a))))
        (do (set! %hd-range-start (first a)) (set! %hd-range-end (first b)))))))

; --- CGI ---------------------------------------------------------------------------

; send_cgi_and_exit: URL's script run with the request in its environment, its
; stdin the request's body and its stdout the response.  The script is the
; first part of URL that is not a directory; what follows it is PATH_INFO.  It
; runs in its own directory, through the interpreter a *.ext: line names when
; one does
(def %hd-send-cgi
  (fn (_ url orig method)
    (def cut (%hd-cgi-split url 1 0))
    (def script-end (first cut))
    (def last-slash (rest cut))
    (def script-url (if (null? script-end) url (substring url 0 script-end)))
    (def env
      (append (reverse %hd-cgi-env)
        (list (pair "PATH_INFO" (if (null? script-end) "" (substring url script-end (byte-len url))))
              (pair "REQUEST_METHOD" method)
              (pair "REQUEST_URI" (if (null? %hd-query) orig (string-concat (list orig "?" %hd-query)))))
        (if (Str8 starts? "/" %hd-home)
          (list (pair "SCRIPT_FILENAME" (string-append (%hd-strip-slash %hd-home) script-url)))
          ())
        (list (pair "SCRIPT_NAME" script-url)
              (pair "QUERY_STRING" (if (null? %hd-query) "" %hd-query))
              (pair "SERVER_SOFTWARE" "x-coreutils httpd")
              (pair "SERVER_PROTOCOL" "HTTP/1.1")
              (pair "GATEWAY_INTERFACE" "CGI/1.1"))
        (%hd-remote-env)
        (if (> %hd-post-len 0) (list (pair "CONTENT_LENGTH" (%cu-int->str %hd-post-len))) ())
        (if (null? %hd-remote-user) () (list (pair "REMOTE_USER" %hd-remote-user) (pair "AUTH_TYPE" "Basic")))))
    (def from (sys-pipe))
    (def to (sys-pipe))
    (def pid (sys-fork))
    (when (= pid 0) (%hd-cgi-child from to env script-url last-slash))
    (file-close (first to))
    (file-close (rest from))
    (def writer (%hd-cgi-feed (rest to)))
    (%hd-cgi-out (first from))
    (file-close (first from))
    (sys-wait pid)
    (when (> writer 0) (sys-wait writer))
    (%hd-finish)))

; the first part of URL past I that is not a directory: (ITS-SLASH . LAST-DIR-SLASH),
; ITS-SLASH nil when every part is one
(def %hd-cgi-split
  (fn (self url i last)
    (let ((s (%wget-index url #\/ i)))
      (match
        ((null? s) (pair () last))
        ((file-dir? (substring url 1 s)) (self url (+ s 1) s))
        (#t (pair s last))))))

(def %hd-strip-slash
  (fn (_ s) (if (if (> (byte-len s) 0) (= (byte-at s (- (byte-len s) 1)) #\/) #f)
              (substring s 0 (- (byte-len s) 1)) s)))

; REMOTE_ADDR and REMOTE_PORT: the peer's IP:PORT split at its last colon
(def %hd-remote-env
  (fn (_)
    (def p (if (null? %hd-rmt) "" %hd-rmt))
    (def colon (%wget-last-index p #\:))
    (def cut (if (if (null? colon) #f (null? (%wget-index p #\] colon))) colon ()))
    (if (null? cut) (list (pair "REMOTE_ADDR" p))
      (list (pair "REMOTE_ADDR" (substring p 0 cut))
            (pair "REMOTE_PORT" (substring p (+ cut 1) (byte-len p)))))))

; the script's process: its stdin and stdout the pipes, the environment set, in
; the script's directory, SIGPIPE back to its default -- then the script, or
; busybox's 404 on its stdout when it cannot be run
(def %hd-cgi-child
  (fn (_ from to env script-url last-slash)
    (file-close (rest to)) (file-close (first from))
    (sys-dup2 (first to) 0) (sys-dup2 (rest from) 1)
    (file-close (first to)) (file-close (rest from))
    (sys-signal 13 0)
    (map (fn (_ kv) (sys-setenv (first kv) (rest kv))) env)
    (def dir (substring script-url 1 last-slash))
    (def name (substring script-url (+ last-slash 1) (byte-len script-url)))
    (when (> %hd-verbose 2) (%hd-log (string-append "cd:" dir)))
    (if (if (> last-slash 0) (not (%hd-chdir dir)) #f)
      (%hd-log (string-concat (list "can't change directory to '" dir "': No such file or directory")))
      (do (when (> %hd-verbose 1)
            (%hd-log (string-concat (list "exec:" (if (null? %hd-interp) name %hd-interp) " "
                                          (if (null? %hd-interp) "(null)" name)))))
          (let ((e (if (null? %hd-interp)
                     (sys-exec-or-err (string-append "./" name) ())
                     (sys-exec-or-err %hd-interp (list name)))))
            (when (> %hd-verbose 0)
              (%hd-log (string-concat (list "can't execute '" (if (null? %hd-interp) name %hd-interp) "': "
                                            (file-err-text e))))))))
    (set! %hd-file-size -1)
    (%hd-send-headers 404)
    (sys-exit 1)))

; the request's body to the script: what was read past the headers, then the
; rest of a POST's Content-Length, by a process of its own so the script's
; output is read meanwhile.  Answers its pid, or 0 when there is nothing to send
(def %hd-cgi-feed
  (fn (_ fd)
    (def left (- %hd-post-len (byte-len %hd-in)))
    (if (if (= (byte-len %hd-in) 0) (<= left 0) #f)
      (do (file-close fd) 0)
      (let ((pid (sys-fork)))
        (if (= pid 0)
          (do (guard (_ ())
                (do (file-write-run fd (pair %hd-in (byte-len %hd-in)))
                    (let go ((left left))
                      (when (> left 0)
                        (let ((r (%hd-read)))
                          (unless (null? r)
                            (do (file-write-run fd r) (go (- left (rest r))))))))))
              (sys-exit 0))
          (do (file-close fd) pid))))))

; cgi_io_loop_and_exit's output half: the first ten bytes decide the status
; line -- Status: becomes HTTP/1.1, Location: is a 302, an HTTP/1.1 line of
; the script's own stays, anything else is given HTTP/1.1 200 OK -- then
; everything the script writes is passed on
(def %hd-cgi-out
  (fn (_ fd)
    (let go ((head ""))
      (let ((r (file-read-run fd 8192)))
        (if (= (rest r) 0)
          (%hd-cgi-head head)
          (let ((h (string-append head (substring (first r) 0 (rest r)))))
            (if (< (byte-len h) 10) (go h)
              (do (%hd-cgi-head h) (%hd-cgi-pass fd)))))))))

(def %hd-cgi-head
  (fn (_ h)
    (match
      ((if (>= (byte-len h) 10) (Str8 starts? "Status: " h) #f)
        (let ((out (string-append "HTTP/1.1 " (substring h 8 (byte-len h)))))
          (do (when (> %hd-verbose 0)
                (%hd-log (string-concat (list "cgi response:'" (%hd-printable out 9) "'"))))
              (%hd-write-all out))))
      ((if (>= (byte-len h) 10) (Str8 starts? "Location: " h) #f)
        (do (%hd-write-all "HTTP/1.1 302 Found\r\n")
            (when (> %hd-verbose 0)
              (%hd-log (string-concat (list "cgi redirect:'" (%hd-printable h 10) "'"))))
            (%hd-write-all h)))
      ((if (>= (byte-len h) 10) (Str8 starts? "HTTP/1.1" h) #f) (%hd-write-all h))
      (#t (do (%hd-write-all "HTTP/1.1 200 OK\r\n")
              (when (> %hd-verbose 0) (%hd-log "cgi response:200"))
              (%hd-write-all h))))))

(def %hd-cgi-pass
  (fn (self fd)
    (let ((r (file-read-run fd 8192)))
      (when (> (rest r) 0)
        (do (file-write-run 1 r) (%cu-sweep! 1) (self fd))))))

; S from I to its first byte that is not plain text
(def %hd-printable
  (fn (_ s i)
    (let go ((j i))
      (if (if (< j (byte-len s)) (if (>= (byte-at s j) 32) (< (byte-at s j) 127) #f) #f)
        (go (+ j 1))
        (substring s i j)))))

; a file under cgi-bin/: one that is not a regular file is a 403; one no one
; may run is sent as a file (nil); one that can be run is a script (normal)
(def %hd-cgi-file
  (fn (_ st rel)
    (match
      ((not (eq? (Assoc get (lit file-type) st) (lit file))) (%hd-fail 403))
      ((not (%t-permitted? rel 1)) (do (%hd-stat! st) ()))
      (#t (lit normal)))))

(def %hd-stat!
  (fn (_ st)
    (set! %hd-file-size (Assoc get (lit size) st))
    (set! %hd-last-mod (Assoc get (lit mtime) st))))

; one request on stdin and stdout, read through READ
(def %hd-serve
  (fn (_ read)
    (%hd-reset-request! read)
    (guard (e (if (eq? (Err label e) (lit httpd-done)) 0 (error e)))
      (%hd-handle))))

; --- the listener ----------------------------------------------------------------------

; bb_daemonize: the parent ends, the child leaves the terminal for /dev/null
(def %hd-daemonize
  (fn (_)
    (when (> (sys-fork) 0) (sys-exit 0))
    (%ss-resolve!)
    (%cu-ptr-call %ss-c-setsid)
    (let ((fd (File open "/dev/null" (lit rdwr))))
      (do (sys-dup2 fd 0) (sys-dup2 fd 1) (sys-dup2 fd 2)
          (when (> fd 2) (file-close fd))))))

; mini_httpd: each connection answered in a grandchild, its socket stdin and
; stdout, its peer's IP:PORT the name its -v messages carry
(def %hd-listen
  (fn (self lfd)
    (let ((c (guard (_ ()) (net-accept lfd))))
      (unless (null? c)
        (let ((pid (sys-fork)))
          (if (= pid 0)
            (do (when (> (sys-fork) 0) (sys-exit 0))
                (sys-dup2 c 0) (sys-dup2 c 1) (net-close c) (net-close lfd)
                (%hd-peer! 0 #t)
                (%hd-serve (fn (_) (let ((r (file-read-run 0 8192))) (if (= (rest r) 0) () r))))
                (sys-exit 0))
            (do (net-close c) (sys-wait pid))))))
    (self lfd)))

; the peer of FD as -v names it, and as A:/D: lines match it.  busybox's
; listener takes IPv6 and IPv4 alike, so it names an IPv4 peer as the IPv6
; address that maps it, [::ffff:IP]:PORT; LISTENER? names one so
(def %hd-peer!
  (fn (_ fd listener?)
    (let ((p (guard (_ ()) (net-peer fd))))
      (if (null? p)
        (do (set! %hd-remote-ip 0) (set! %hd-rmt ()) (set! %hd-name "httpd"))
        (do (set! %hd-remote-ip (let ((r (%hd-scan-ip (first p) 0))) (if (null? r) 0 (first r))))
            (set! %hd-rmt (string-concat
              (list (if listener? (string-concat (list "[::ffff:" (first p) "]")) (first p))
                    ":" (%cu-int->str (rest p)))))
            (when (> %hd-verbose 0)
              (set! %hd-name %hd-rmt)))))))

; --- the applet --------------------------------------------------------------------------

; encodeString: a letter or digit as itself, any other byte as &#N;
(def %hd-encode
  (fn (_ s)
    (string-concat
      (map (fn (_ c)
             (if (%hd-alnum? c) (bytes->str (list c)) (string-concat (list "&#" (%cu-int->str c) ";"))))
           (%tftp-bytes s 0 (byte-len s))))))

(def %hd-alnum?
  (fn (_ c)
    (match
      ((if (>= c #\a) (<= c #\z) #f) #t)
      ((if (>= c #\A) (<= c #\Z) #f) #t)
      (#t (if (>= c #\0) (<= c #\9) #f)))))

(def %cu-httpd
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "httpd" argv))
    (guard (e (if (eq? (Err label e) (lit net))
                (do (file-write 2 (string-concat (list "httpd: " (e msg) "\n"))) 1)
                (error e)))
      (match
        ((not (null? (Opts value o "-d")))
          (let ((s (%hd-pct-decode (Opts value o "-d") #f)))
            (do (file-write 1 (let ((z (%wget-index s 0 0))) (if (null? z) s (substring s 0 z)))) 0)))
        ((not (null? (Opts value o "-e"))) (do (file-write 1 (%hd-encode (Opts value o "-e"))) 0))
        ((not (null? (Opts value o "-m")))
          (do (file-write 1 (string-append (%cu-md5-crypt (Opts value o "-m") (%hd-salt 8)) "\n")) 0))
        (#t (%hd-run o stdin-thunk))))))

(def %hd-run
  (fn (_ o stdin-thunk)
    (set! %hd-verbose (%nc-count o "-v"))
    (set! %hd-name "httpd")
    (set! %hd-index "index.html")
    (set! %hd-conf (Opts value o "-c"))
    (set! %hd-errpages ())
    (set! %hd-proxy ())
    (set! %hd-remote-ip 0)
    (let ((r (Opts value o "-r"))) (set! %hd-realm (if (null? r) "Web Server Authentication" r)))
    (def home (Opts value o "-h"))
    (set! %hd-home (if (null? home) (sys-getcwd) home))
    (unless (null? home)
      (unless (%hd-chdir home)
        (%hd-die (string-concat (list "can't change directory to '" home "': No such file or directory")))))
    (def inetd? (Opts on? o "-i"))
    (def lfd (if inetd? () (%hd-open-server (Opts value o "-p"))))
    (%hd-parse-conf "/etc" #t)
    (sys-signal 13 cu-sig-ign)
    (if inetd?
      (do (%hd-peer! 0 #f)
          (%hd-serve (fn (_) (let ((p (stdin-thunk (lit chunk))))
                               (let ((r (if (pair? p) p (pair p (byte-len p)))))
                                 (if (= (rest r) 0) () r))))))
      (do (unless (Opts on? o "-f") (%hd-daemonize))
          (%hd-listen lfd)))))

; openServer: -p's PORT on every address, or HOST[:PORT] (80 unless given) on
; HOST's alone; a port that is not one is "bad port", a host that does not
; resolve "bad address" naming the whole of -p's value
(def %hd-open-server
  (fn (_ v)
    (def n (if (null? v) 80 (%wget-digits v)))
    (guard (e (if (eq? (Err label e) (lit io)) (%hd-die (string-append "bind: " (%wget-err-text e))) (error e)))
      (if (if (null? n) #f (if (> n 0) (<= n 65535) #f))
        (net-listen n)
        (%hd-listen-on v)))))

(def %hd-listen-on
  (fn (_ v)
    (def colon (%wget-last-index v #\:))
    (def host (if (null? colon) v (substring v 0 colon)))
    (def pv (if (null? colon) () (substring v (+ colon 1) (byte-len v))))
    (def port (if (null? pv) 80 (%wget-digits pv)))
    (when (if (null? port) #t (> port 65535))
      (%hd-die (string-concat (list "bad port '" pv "'"))))
    (def ip (if (= (byte-len host) 0) () (guard (_ ()) (net-resolve host))))
    (when (null? ip) (%hd-die (string-concat (list "bad address '" v "'"))))
    (net-listen-on ip port)))


; xchdir: #t when DIR is now the working directory
(def %hd-chdir
  (fn (_ dir) (let ((r (guard (_ -1) (Sys chdir dir)))) (if (number? r) (>= r 0) #t))))


; crypt_make_rand64encoded: N characters of crypt's base-64, from /dev/urandom
(def %hd-salt
  (fn (_ n)
    (let ((fd (file-open-read "/dev/urandom")))
      (let ((r (file-read-run fd n)))
        (do (file-close fd)
            (string-concat
              (map (fn (_ b) (let ((v (bit-and b 63))) (substring %cu-crypt64 v (+ v 1))))
                   (%cu-bytes (first r) 0 (rest r)))))))))

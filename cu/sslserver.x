; # x-coreutils -- the small tools, as applets
;
; ## cu/sslserver.x -- ssl_server: a TLS server on the connection inetd hands it
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; networking/ssl_server.c: standard input and output are a connection
; already accepted -- by inetd, tcpsvd or the like.  The server's side of a
; TLS handshake is run on it with the private key and the certificates of
; -f PEMFILE, then PROG ARGS on a pair of pipes, and what the client sends
; goes to PROG, what PROG writes to the client, until PROG's output ends or
; the client closes.  The session is x-lang's TLS 1.3 (Tls13 accept), its
; key RSA or Ed25519; busybox's speaks TLS 1.2 with an RSA key, so a client
; that takes only 1.2 is refused here.

(module cu/sslserver)

(import cu/cli cu-opts cu-usage)
(import cu/prims cu-sig-ign cu-stdin-to-command! file-read-all file-write
  string-concat sys-signal wget-err-text)
(import cu/sslclient sc-copy sc-run-prog)

(import x/net/tls13)

(def cu-ssl-server
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "ssl_server" argv))
    (def ops (Opts operands o))
    (if (if (null? ops) #t (null? (Opts value o "-f")))
      (cu-usage "ssl_server")
      (guard (e (match ((eq? (Err label e) (lit io)) (do (%ss-say (e msg)) 1))
                       ((eq? (Err label e) (lit value)) (do (%ss-say (e msg)) 1))
                       (#t (error e))))
        (%ss-main (Opts value o "-f") ops)))))

(def %ss-say (fn (_ msg) (file-write 2 (string-concat (list "ssl_server: " msg "\n")))))

(def %ss-main
  (fn (_ pem argv)
    (cu-stdin-to-command!)
    (sys-signal 13 cu-sig-ign)
    (def text (guard (e (Err raise (lit io) (string-concat (list "can't read '" pem "': " (wget-err-text e))) ()))
                (file-read-all pem)))
    (def session (Tls13 accept 0 1 (list (pair (lit pem) text))))
    (def prog (sc-run-prog %ss-say argv))
    (sc-copy session 0 (first prog) (rest prog) #t #t)
    0))

(provide cu/sslserver cu-ssl-server)

; # x-coreutils -- the small tools, as applets
;
; ## cu/traceroute.x -- traceroute and traceroute6: the hops to a host, timed
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's traceroute with FEATURE_TRACEROUTE_VERBOSE and USE_ICMP
; (networking/traceroute.c).  Each hop from -f to -m is sent -q probes, UDP
; datagrams to -p's port and up or, with -I, echo requests, the TTL the hop
; count; a raw ICMP socket takes the time-exceeded and unreachable replies.
; A hop's line names the router and times each probe, `*` where none came in
; -w seconds, an unreachable's mark after it; the trace ends at the host or
; where most of a hop's probes were unreachable.  -n leaves the names
; unlooked; -v writes the bytes of each reply and dumps the ones not ours;
; -t sets the TOS, -s the source, -i the interface; -z pauses between
; probes.  -l is taken and does nothing, as busybox's tests its argument and
; not the options.  traceroute6 is traceroute -6.

(module cu/traceroute)

(import cu/cli cu-families cu-opts cu-usage)
(import cu/inet inet-set! inet-zeros)
(import cu/inetd in-c in-call in-dontwait)
(import cu/ping pn-af6 pn-be16 pn-be16! pn-bind-device pn-byte pn-cmsg pn-div
  pn-dotted pn-family pn-fold pn-ms pn-now pn-number pn-resolve pn-setopt
  pn-sol-socket pn-sum)
(import cu/prims cu-err-label cu-int->str cu-ptr->str cu-ptr-call cu-ptr-ref
  cu-ptr-set! cu-str->ptr cu-string-type cvt file-write libc-strerror reverse
  str-make-raw string-append string-concat string=? sys-getpid sys-getuid
  sys-poll)
(import cu/telnetd td-ptr->int)
(import cu/text cu-pad-left cu-pad-zero)

(def %tr-applet "traceroute")
(def %tr-say (fn (_ msg) (file-write 2 (string-concat (list %tr-applet ": " msg "\n")))))
(def %tr-die (fn (_ msg) (do (%tr-say msg) (Err raise (lit traceroute) msg ()))))
(def %tr-errno-die (fn (_ what r) (%tr-die (string-concat (list what ": " (libc-strerror (Err errno-of r)))))))
(def %tr-check (fn (_ r what) (when (< r 0) (%tr-errno-die what r))))
(def %tr-out (fn (_ s) (file-write 1 s)))

; --- the run's state -----------------------------------------------------------------

(def %tr-rcv -1)
(def %tr-snd -1)
(def %tr-v6 #f)
(def %tr-icmp #f)                ; -I
(def %tr-verbose #f)
(def %tr-port 33434)
(def %tr-ident 0)                ; the pid, 16 bits, sent big-endian
(def %tr-packlen 46)
(def %tr-pkt ())                 ; what a probe sends: the UDP payload, or the echo request
(def %tr-plen 0)                 ; its length: the buffer is zeros, which byte-len does not count
(def %tr-dest ())                ; the target's sockaddr, and its length
(def %tr-salen 16)
(def %tr-pmtu 0)
(def %tr-rbuf ())
(def %tr-from ())
(def %tr-to ())                  ; the local address the last reply came to
(def %tr-iov ())
(def %tr-control ())
(def %tr-msg ())

(def %tr-be32!
  (fn (_ p i v) (do (pn-be16! p i (& (>> v 16) 65535)) (pn-be16! p (+ i 2) (& v 65535)))))
(def %tr-be32 (fn (_ p i) (| (<< (pn-be16 p i) 16) (pn-be16 p (+ i 2)))))

; xsocket
(def %tr-socket
  (fn (_ af type proto)
    (let ((fd (in-call (cu-ptr-call (in-c "socket") af type proto))))
      (if (>= fd 0) fd
        (%tr-errno-die (string-concat (list "socket(AF_" (if (= af pn-af6) "INET6" "INET") ","
                                            (cu-int->str type) "," (cu-int->str proto) ")")) fd)))))

; xbind
(def %tr-bind
  (fn (_ fd sa)
    (let ((r (in-call (cu-ptr-call (in-c "bind") fd (cu-str->ptr (first sa)) (rest sa)))))
      (when (< r 0) (%tr-errno-die "bind" r)))))

; --- sending ---------------------------------------------------------------------------

; send_probe: probe SEQ at TTL.  The payload is outdata_t, SEQ's low byte and
; TTL's, or outdata6_t, the ident and SEQ; an echo request has its header
; before it, its checksum taken anew.
(def %tr-send!
  (fn (_ seq ttl)
    (def p (cu-str->ptr %tr-pkt))
    (def n %tr-plen)
    (def d (if %tr-icmp 8 0))
    (if %tr-v6
      (do (pn-be16! p d %tr-ident) (cu-ptr-set! p (+ d 2) 0 2) (%tr-be32! p (+ d 4) seq))
      (do (cu-ptr-set! p d (& seq 255) 1) (cu-ptr-set! p (+ d 1) (& ttl 255) 1)))
    (when %tr-icmp
      (do (pn-be16! p 6 (& seq 65535))
          (cu-ptr-set! p 2 0 2)
          (let ((sum (pn-fold (pn-sum p 0 n)))) (pn-be16! p 2 (if (= sum 0) 65535 sum)))))
    (%tr-check (if %tr-v6 (pn-setopt %tr-snd 41 (if os-darwin? 4 16) ttl) (pn-setopt %tr-snd 0 (if os-darwin? 4 2) ttl))
      (string-concat (list "setsockopt(" (if %tr-v6 "UNICAST_HOPS" "TTL") ") " (cu-int->str ttl))))
    (unless %tr-icmp (pn-be16! (cu-str->ptr %tr-dest) 2 (& (+ %tr-port seq) 65535)))
    (let ((r (in-call (cu-ptr-call (in-c "sendto") %tr-snd p n 0 (cu-str->ptr %tr-dest) %tr-salen))))
      (match ((< r 0) (%tr-errno-die "sendto" r))
             ((not (= r n)) (%tr-say (string-concat (list "sent " (cu-int->str n) " octets, ret=" (cu-int->str r)))))
             (#t ())))))

; --- receiving -------------------------------------------------------------------------

; recv_from_to's buffers, made once: a 512-byte packet, the sender, and the
; ancillary data that names the address it came to
(def %tr-buffers!
  (fn (_)
    (set! %tr-rbuf (inet-zeros 512))
    (set! %tr-from (inet-zeros 128))
    (set! %tr-iov (inet-zeros 16))
    (set! %tr-control (inet-zeros 64))
    (set! %tr-msg (inet-zeros 56))
    (cu-ptr-set! (cu-str->ptr %tr-iov) 0 (td-ptr->int (cu-str->ptr %tr-rbuf)) 8)
    (inet-set! %tr-iov 8 512 8)
    (cu-ptr-set! (cu-str->ptr %tr-msg) 0 (td-ptr->int (cu-str->ptr %tr-from)) 8)
    (cu-ptr-set! (cu-str->ptr %tr-msg) 16 (td-ptr->int (cu-str->ptr %tr-iov)) 8)
    (inet-set! %tr-msg 24 1 4)
    (cu-ptr-set! (cu-str->ptr %tr-msg) 32 (td-ptr->int (cu-str->ptr %tr-control)) 8)))

; recv_from_to: a datagram's length, the destination its IP_PKTINFO or
; IPV6_PKTINFO names written to %tr-to; the run ends at an error
(def %tr-recv
  (fn (_)
    (inet-set! %tr-msg 8 %tr-salen 4)
    (inet-set! %tr-msg 40 64 4)
    (let ((r (in-call (cu-ptr-call (in-c "recvmsg") %tr-rcv (cu-str->ptr %tr-msg) in-dontwait))))
      (do (when (< r 0) (%tr-errno-die "recv" r))
      (let ((end (cu-ptr-ref (cu-str->ptr %tr-msg) 40 4)) (c (cu-str->ptr %tr-control)) (to (cu-str->ptr %tr-to)))
        (if %tr-v6
          (let ((at (pn-cmsg %tr-control end 41 (list (if os-darwin? 46 50)))))
            (unless (< at 0)
              (let copy ((i 0)) (when (< i 16) (do (cu-ptr-set! to (+ 8 i) (pn-byte c (+ at i)) 1) (copy (+ i 1)))))))
          (let ((at (pn-cmsg %tr-control end 0 (list (if os-darwin? 26 8)))))
            (unless (< at 0) (cu-ptr-set! to 4 (cu-ptr-ref c (+ at 8) 4) 4)))))
          r))))

; pr_type
(def %tr-types
  (list "Echo Reply" "ICMP 1" "ICMP 2" "Dest Unreachable" "Source Quench" "Redirect" "ICMP 6" "ICMP 7"
        "Echo" "Router Advert" "Router Solicit" "Time Exceeded" "Param Problem" "Timestamp"
        "Timestamp Reply" "Info Request" "Info Reply" "Mask Request" "Mask Reply"))
(def %tr-types6
  (list "Error" "Dest Unreachable" "Packet Too Big" "Time Exceeded" "Param Problem"))
(def %tr-types6-info
  (list "Echo Request" "Echo Reply" "Membership Query" "Membership Report" "Membership Reduction"
        "Router Solicit" "Router Advert" "Neighbor Solicit" "Neighbor Advert" "Redirect"))
(def %tr-type-name
  (fn (_ t)
    (match ((not %tr-v6) (if (< t 19) (List ref t %tr-types) "OUT-OF-RANGE"))
           ((< t 5) (List ref t %tr-types6))
           ((if (< t 128) #t (> t 137)) "OUT-OF-RANGE")
           (#t (List ref (- t 128) %tr-types6-info)))))

(def %tr-hex (fn (_ n w) (cu-pad-zero (cvt n cu-string-type 16) w)))

; hexdump_if_verbose: the LEN bytes at AT, a reply not ours; 0 always
(def %tr-hexdump
  (fn (_ at len)
    (def p (cu-str->ptr %tr-rbuf))
    (when %tr-verbose
      (%tr-out (string-concat
        (list "\n" (cu-int->str len) " bytes from " (pn-dotted %tr-from) " to " (pn-dotted %tr-to)
              ": icmp type " (cu-int->str (pn-byte p at)) " (" (%tr-type-name (pn-byte p at)) ") code "
              (cu-int->str (pn-byte p (+ at 1))) "\n"
              (Str8 join "" (let go ((i 0) (acc ()))
                              (if (>= i len) (List reverse acc)
                                (go (+ i 1)
                                    (pair (string-concat
                                            (list (if (= (& i 15) 0) (string-append (if (= i 0) "" "\n") (string-append (%tr-hex i 4) ":")) "")
                                                  " " (%tr-hex (pn-byte p (+ at i)) 2)))
                                          acc)))))
              "\n"))))
    0))

(def %tr-short
  (fn (_ len)
    (do (when %tr-verbose
          (%tr-out (string-concat (list "packet too short (" (cu-int->str len) " bytes) from " (pn-dotted %tr-from) "\n"))))
        0)))

; packet4_ok: the reply of LEN bytes to probe SEQ as -1 for time exceeded,
; its unreachable code and 1, or 0 where it is not ours.  The raw socket
; keeps the IP header; the ICMP header after it quotes the probe's.
(def %tr-ok4
  (fn (_ len seq)
    (def p (cu-str->ptr %tr-rbuf))
    (def hlen (* 4 (& (pn-byte p 0) 15)))
    (if (< len (+ hlen 8)) (%tr-short len)
      (let ((n (- len hlen)) (type (pn-byte p hlen)) (code (pn-byte p (+ hlen 1))))
        (do (set! %tr-pmtu (if (= code 4) (pn-be16 p (+ hlen 6)) 0))
        (match
          ((if %tr-icmp (if (= type 0) (= (pn-be16 p (+ hlen 6)) (& seq 65535)) #f) #f)
            (if (= (pn-be16 p (+ hlen 4)) %tr-ident) 4 0))
          ((if (if (= type 11) (= code 0) #f) #t (= type 3))
            (let ((hip (+ hlen 8)))
              (let ((hl (* 4 (& (pn-byte p hip) 15))) (proto (pn-byte p (+ hip 9))))
                (if (if %tr-icmp
                      (if (<= (+ hl 8) n) (if (= proto 1) (if (= (pn-be16 p (+ hip hl 4)) %tr-ident)
                                                             (= (pn-be16 p (+ hip hl 6)) (& seq 65535)) #f) #f) #f)
                      (if (<= (+ hl 12) n) (if (= proto 17) (= (pn-be16 p (+ hip hl 2)) (& (+ %tr-port seq) 65535)) #f) #f))
                  (if (= type 11) -1 (+ code 1))
                  (%tr-hexdump hlen n)))))
          (#t (%tr-hexdump hlen n))))))))

; packet6_ok: as packet4_ok, an unreachable's code shifted 8 left; the raw
; socket gives the ICMPv6 header alone, the quoted UDP header after a
; fragment header where one is
(def %tr-ok6
  (fn (_ len seq)
    (def p (cu-str->ptr %tr-rbuf))
    (if (< len 8) (%tr-short len)
      (let ((type (pn-byte p 0)) (code (pn-byte p 1)))
        (match
          ((if %tr-icmp (if (= type 129) (= (pn-be16 p 6) (& seq 65535)) #f) #f)
            (if (= (pn-be16 p 4) %tr-ident) 1025 0))
          ((if (if (= type 3) (= code 0) #f) #t (= type 1))
            (let ((frag (= (pn-byte p 14) 44)))
              (let ((next (if frag (pn-byte p 48) (pn-byte p 14))) (data (if frag 64 56)))
                (if (if (= next 17)
                      (if (= (pn-be16 p data) %tr-ident) (if (= (pn-be16 p (+ data 2)) 0) (= (%tr-be32 p (+ data 4)) seq) #f) #f)
                      #f)
                  (if (= type 3) -1 (+ (<< code 8) 1))
                  (%tr-hexdump 0 len)))))
          (#t (%tr-hexdump 0 len)))))))

; --- the hops --------------------------------------------------------------------------

; print: the router, by name and number or by number alone, and with -v the
; reply's length and the address it came to
(def %tr-print
  (fn (_ len numeric)
    (def ina (pn-dotted %tr-from))
    (%tr-out
      (string-concat
        (list
          (if numeric (string-append "  " ina)
            (let ((n (if (if %tr-v6 #t (not (= (cu-ptr-ref (cu-str->ptr %tr-from) 4 4) 0))) (%tr-name) ())))
              (string-concat (list "  " (if (null? n) ina n) " (" ina ")"))))
          (if %tr-verbose
            (string-concat (list " " (cu-int->str (if %tr-v6 len (- len (* 4 (& (pn-byte (cu-str->ptr %tr-rbuf) 0) 15)))))
                                 " bytes to " (pn-dotted %tr-to)))
            ""))))))

; xmalloc_sockaddr2host_noport: getnameinfo's name for the sender, nil where
; it has none
(def %tr-name
  (fn (_)
    (let ((host (str-make-raw 128)) (serv (str-make-raw 16)))
      (if (= (in-call (cu-ptr-call (in-c "getnameinfo") (cu-str->ptr %tr-from) %tr-salen
                                   (cu-str->ptr host) 128 (cu-str->ptr serv) 16 (if os-darwin? 8 2))) 0)
        (cu-ptr->str (cu-str->ptr host))
        ()))))

; an unreachable's mark, and whether it ends the trace there or counts
; toward the hop's unreachables
(def %tr-mark
  (fn (_ code)
    (match ((= code 1024) (pair "" (lit there)))
           ((= code 3) (pair (if (<= (pn-byte (cu-str->ptr %tr-rbuf) 8) 1) " !" "") (lit there)))
           ((= code 0) (pair " !N" (lit unreachable)))
           ((if (= code 1) #t (= code 768)) (pair " !H" (lit unreachable)))
           ((= code 2) (pair " !P" (lit there)))
           ((= code 4) (pair (string-append " !F-" (cu-int->str %tr-pmtu)) (lit unreachable)))
           ((if (= code 5) #t (= code 256)) (pair " !S" (lit unreachable)))
           ((if (= code 13) #t (= code 9)) (pair " !A" (lit unreachable)))
           ((if (= code 10) #t (= code 15)) (pair " !C" (lit unreachable)))
           ((= code 14) (pair " !V" (lit unreachable)))
           ((if (= code 6) #t (= code 7)) (pair " !U" (lit unreachable)))
           ((= code 8) (pair " !I" (lit unreachable)))
           ((if (= code 11) #t (= code 12)) (pair " !T" (lit unreachable)))
           (#t (pair (string-concat (list " !<" (cu-int->str code) ">")) (lit unreachable))))))

; wait_for_reply and packet_ok over LEFT milliseconds from T: (CODE LEN T)
; for the reply to SEQ, the clock read as it came, or nil at the wait's end
(def %tr-wait
  (fn (self seq left t)
    (if (if (< left 0) #t (null? (sys-poll (list (pair %tr-rcv (list (lit in)))) left))) ()
      (let ((len (%tr-recv)) (now (pn-now)))
        (let ((code (if %tr-v6 (%tr-ok6 len seq) (%tr-ok4 len seq))))
          (if (= code 0) (self seq (- left (pn-div (- now t) 1000)) now)
            (list code len now)))))))

; the hops from START to HOPS, PROBES probes each, SECS the wait for each
(def %tr-trace
  (fn (_ start hops probes secs pause numeric)
    (let hop ((ttl start) (seq 0) (last ""))
      (when (<= ttl hops)
        (%tr-out (cu-pad-left (cu-int->str ttl) 2))
        (let probe ((k 0) (seq seq) (last last) (unreachable 0) (there #f))
          (if (< k probes)
            (do (when (if (> k 0) (> pause 0) #f) (sys-poll () pause))
                (%tr-send! (+ seq 1) ttl)
                (let ((t1 (pn-now)))
                  (let ((got (%tr-wait (+ seq 1) (* secs 1000) t1)))
                    (if (null? got)
                      (do (%tr-out "  *") (probe (+ k 1) (+ seq 1) last unreachable there))
                      (let ((from (pn-dotted %tr-from)) (code (first got)))
                        (do (when (if (= k 0) #t (not (string=? from last))) (%tr-print (List ref 1 got) numeric))
                            (%tr-out (string-concat (list "  " (pn-ms (- (List ref 2 got) t1)) " ms")))
                            (if (= code -1) (probe (+ k 1) (+ seq 1) from unreachable there)
                              (let ((m (%tr-mark (- code 1))))
                                (do (%tr-out (first m))
                                    (if (eq? (rest m) (lit there))
                                      (probe (+ k 1) (+ seq 1) from unreachable #t)
                                      (probe (+ k 1) (+ seq 1) from (+ unreachable 1) there)))))))))))
            (do (%tr-out "\n")
                (unless (if there #t (if (> unreachable 0) (>= unreachable (- probes 1)) #f))
                  (hop (+ ttl 1) seq last)))))))))

; --- the run ---------------------------------------------------------------------------

; traceroute_init and common_traceroute_main
(def %tr-main
  (fn (_ applet argv)
    (def o (cu-opts applet argv))
    (def ops (Opts operands o))
    (unless (pair? ops) (Err raise (lit traceroute-usage) "usage" ()))
    (def num (fn (_ f lo hi dflt) (let ((v (Opts value o f))) (if (null? v) dflt (pn-number v lo hi %tr-die)))))
    (def hops (num "-m" 1 255 30))
    (set! %tr-port (num "-p" 0 65535 33434))
    (def probes (num "-q" 1 2147483647 3))
    (def secs (num "-w" 1 86400 5))
    (def pause (num "-z" 0 3600000 0))
    (def start (num "-f" 1 hops 1))
    (set! %tr-icmp (Opts on? o "-I"))
    (set! %tr-verbose (Opts on? o "-v"))
    (when %tr-icmp (set! %tr-port 0))
    (def fams (cu-families applet argv))
    (def af (match ((if (string=? applet "traceroute6") #t (List any? (fn (_ c) (= c #\6)) fams)) pn-af6)
                   ((List any? (fn (_ c) (= c #\4)) fams) 2)
                   (#t 0)))
    (def lsa (pn-resolve (first ops) af 0 %tr-die))
    (set! %tr-dest (first lsa))
    (set! %tr-salen (rest lsa))
    (set! %tr-v6 (= (pn-family %tr-dest) pn-af6))
    (def fam (if %tr-v6 pn-af6 2))
    (pn-be16! (cu-str->ptr %tr-dest) 2 %tr-port)
    (set! %tr-packlen (if %tr-v6 72 46))
    (unless (null? (rest ops)) (set! %tr-packlen (pn-number (first (rest ops)) %tr-packlen 32768 %tr-die)))
    (set! %tr-rcv (%tr-socket fam 3 (if %tr-v6 58 1)))
    (if %tr-v6
      (do (pn-setopt %tr-rcv 41 (if os-darwin? 61 49) 1)
          (%tr-check (pn-setopt %tr-rcv 255 (if os-darwin? 26 7) 2) "setsockopt(IPV6_CHECKSUM)"))
      (pn-setopt %tr-rcv 0 (if os-darwin? 26 8) 1))
    (set! %tr-snd (if %tr-icmp (%tr-socket fam 3 (if %tr-v6 58 1)) (%tr-socket fam 2 0)))
    (%tr-check (pn-setopt %tr-snd pn-sol-socket (if os-darwin? 4097 7) %tr-packlen) "setsockopt(SO_SNDBUF)")
    (let ((t (Opts value o "-t")))
      (unless (null? t)
        (let ((tos (pn-number t 0 255 %tr-die)))
          (%tr-check (pn-setopt %tr-snd 0 (if os-darwin? 3 1) tos) (string-concat (list "setsockopt(TOS," (cu-int->str tos) ")"))))))
    (when (if os-darwin? (Opts on? o "-F") #f) (pn-setopt %tr-snd 0 28 1))
    (when (Opts on? o "-r") (pn-setopt %tr-snd pn-sol-socket (if os-darwin? 16 5) 1))
    (set! %tr-ident (& (sys-getpid) 65535))
    (def hdr (if %tr-v6 40 20))
    (set! %tr-plen (- %tr-packlen (if %tr-icmp hdr (+ hdr 8))))
    (set! %tr-pkt (inet-zeros %tr-plen))
    (when %tr-icmp
      (do (cu-ptr-set! (cu-str->ptr %tr-pkt) 0 (if %tr-v6 128 8) 1)
          (pn-be16! (cu-str->ptr %tr-pkt) 4 %tr-ident)))
    (let ((dev (Opts value o "-i"))) (unless (null? dev) (pn-bind-device %tr-snd dev %tr-say)))
    (def source (Opts value o "-s"))
    (if (null? source)
      (do (%tr-check (in-call (cu-ptr-call (in-c "connect") %tr-snd (cu-str->ptr %tr-dest) %tr-salen))
                     (if %tr-v6 "can't connect to remote host"
                       (string-concat (list "can't connect to remote host (" (pn-dotted %tr-dest) ")"))))
          (let ((me (inet-zeros 128)) (len (inet-zeros 4)))
            (do (inet-set! len 0 128 4)
                (%tr-check (in-call (cu-ptr-call (in-c "getsockname") %tr-snd (cu-str->ptr me) (cu-str->ptr len))) "getsockname")
                (%tr-bind %tr-rcv (pair me (cu-ptr-ref (cu-str->ptr len) 0 4))))))
      (let ((src (pn-resolve source fam 0 %tr-die)))
        (do (unless (= (sys-getuid) 0) (%tr-die "you must be root"))
            (unless %tr-v6
              (when (< (in-call (cu-ptr-call (in-c "setsockopt") %tr-snd 0 (if os-darwin? 9 32) (cu-str->ptr (first src)) (rest src))) 0)
                (%tr-die "can't set multicast source interface")))
            (%tr-bind %tr-snd src))))
    (set! %tr-to (inet-zeros %tr-salen))
    (inet-set! %tr-to (if os-darwin? 1 0) fam (if os-darwin? 1 2))
    (when os-darwin? (inet-set! %tr-to 0 %tr-salen 1))
    (%tr-buffers!)
    (%tr-out (string-concat (list "traceroute to " (first ops) " (" (pn-dotted %tr-dest) ")"
                                  (if (null? source) "" (string-append " from " source))
                                  ", " (cu-int->str hops) " hops max, " (cu-int->str %tr-packlen) " byte packets\n")))
    (%tr-trace start hops probes secs pause (Opts on? o "-n"))
    0))

(def %tr-close
  (fn (_)
    (do (unless (< %tr-rcv 0) (cu-ptr-call (in-c "close") %tr-rcv))
        (unless (< %tr-snd 0) (cu-ptr-call (in-c "close") %tr-snd))
        (set! %tr-rcv -1) (set! %tr-snd -1))))

(def %tr-run
  (fn (_ applet argv)
    (set! %tr-applet applet)
    (set! %tr-rcv -1) (set! %tr-snd -1)
    (def status
      (guard (e (match ((eq? (cu-err-label e) (lit traceroute-usage)) (cu-usage applet))
                       ((eq? (cu-err-label e) (lit traceroute)) 1)
                       (#t (do (%tr-close) (error e)))))
        (%tr-main applet argv)))
    (%tr-close)
    status))

(def cu-traceroute (fn (_ argv stdin-thunk) (%tr-run "traceroute" argv)))
(def cu-traceroute6 (fn (_ argv stdin-thunk) (%tr-run "traceroute6" argv)))

(provide cu/traceroute cu-traceroute cu-traceroute6)

; # x-coreutils -- the small tools, as applets
;
; ## cu/dhcprelay.x -- dhcprelay: busybox's DHCP relay
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox 1.36.1's dhcprelay (networking/udhcp/dhcprelay.c).  A UDP socket
; on port 67 is bound to the server interface and to each client one.  A
; DISCOVER, REQUEST, DECLINE, RELEASE or INFORM from a client goes to
; SERVER_IP, else the broadcast address, from the server interface's
; socket, its giaddr the client interface's address, else the server
; interface's; its xid, the client's address and its interface are kept
; two minutes.  An OFFER, ACK or NAK from the server goes to the client
; that sent the request with its xid, at the broadcast address where that
; client had none, and its entries go.  The run never ends of itself.

(module cu/dhcprelay)

(import cu/cli cu-usage)
(import cu/inet inet-set!)
(import cu/inetd in-call)
(import cu/prims cu-err-label cu-libc-sym cu-nth cu-ptr-call cu-str->ptr filter
  length map)
(import cu/udhcp ud-ack ud-aton ud-be32 ud-be32! ud-byte ud-decline
  ud-discover ud-end ud-errno ud-error ud-get-option ud-giaddr ud-inform
  ud-interface-address ud-listen ud-logging! ud-nak ud-now ud-offer ud-op
  ud-packet-size ud-perror ud-process-reset! ud-recv-kernel-sized ud-release
  ud-request ud-sin ud-status ud-xid ud-zeros)

; the requests waiting for a reply, newest first: (XID TIME IFACE ADDRESS),
; ADDRESS the sockaddr_in the request came from
(def %dr-items ())

; get_dhcp_packet_type: the message type of a BOOTREQUEST or BOOTREPLY, else -1
(def %dr-type
  (fn (_ p)
    (let ((op (ud-byte p ud-op)))
      (if (if (= op 1) #t (= op 2))
        (let ((o (ud-get-option p 53))) (if (null? o) -1 (ud-byte p (first o))))
        -1))))

(def %dr-one-of? (fn (_ p types) (let ((t (%dr-type p))) (List any? (fn (_ x) (= x t)) types))))

(def %dr-sendto
  (fn (_ fd p n to)
    (let ((r (in-call (cu-ptr-call (cu-libc-sym "sendto") fd (cu-str->ptr p) n 0 (cu-str->ptr to) 16))))
      (unless (= r n) (if (< r 0) (ud-perror "sendto" (ud-errno r)) (ud-error "sendto"))))))

; pass_to_server
(def %dr-to-server
  (fn (_ p n iface from fds server)
    (when (%dr-one-of? p (list ud-discover ud-request ud-decline ud-release ud-inform))
      (do (set! %dr-items (pair (list (ud-be32 p ud-xid) (ud-now) iface from) %dr-items))
          (%dr-sendto (first fds) p n server)))))

; pass_to_client
(def %dr-to-client
  (fn (_ p n fds)
    (when (%dr-one-of? p (list ud-offer ud-ack ud-nak))
      (let ((xid (ud-be32 p ud-xid)))
        (let ((found (filter (fn (_ it) (= (first it) xid)) %dr-items)))
          (unless (null? found)
            (let ((to (cu-nth 3 (first found))))
              (do (when (= (ud-be32 to 4) 0) (ud-be32! to 4 4294967295))
                  (%dr-sendto (cu-nth (cu-nth 2 (first found)) fds) p n to)
                  (set! %dr-items (filter (fn (_ it) (not (= (first it) xid))) %dr-items))))))))))

; xid_expire: the entries older than MAX_LIFETIME go
(def %dr-expire
  (fn (_)
    (let ((now (ud-now)))
      (set! %dr-items (filter (fn (_ it) (<= (- now (cu-nth 1 it)) 120)) %dr-items)))))

; a client's request, its giaddr the address of NAME, the interface it came
; in on, else OUR
(def %dr-from-client
  (fn (_ fd iface name our fds server)
    (def p (ud-zeros ud-packet-size))
    (def from (ud-zeros 16))
    (def len (ud-zeros 4))
    (inet-set! len 0 16 4)
    (let ((n (in-call (cu-ptr-call (cu-libc-sym "recvfrom") fd (cu-str->ptr p) ud-packet-size 0
                         (cu-str->ptr from) (cu-str->ptr len)))))
      (when (> n 0)
        (let ((nip (ud-interface-address name)))
          (do (ud-be32! p ud-giaddr (if (null? nip) our nip))
              (%dr-to-server p n iface from fds server)))))))

; SELECT_TIMEOUT is 15 seconds; the server's socket is read first
(def %dr-loop
  (fn (self fds names our server)
    (Heap collect)
    (let ((ready (let ((r (Sys poll (map (fn (_ fd) (pair fd (list (lit in)))) fds) 15000)))
                   (if (null? r) () (map (fn (_ e) (first e)) r)))))
      (do (when (List any? (fn (_ fd) (= fd (first fds))) ready)
            (let ((r (ud-recv-kernel-sized (first fds))))
              (unless (number? r) (%dr-to-client (first r) (rest r) fds))))
          (let go ((i 1))
            (when (< i (length fds))
              (do (when (List any? (fn (_ fd) (= fd (cu-nth i fds))) ready)
                    (%dr-from-client (cu-nth i fds) i (cu-nth i names) our fds server))
                  (go (+ i 1)))))
          (%dr-expire)
          (self fds names our server)))))

; CLIENT_IFACE[,CLIENT_IFACE2]... SERVER_IFACE [SERVER_IP]; the server
; interface is the first socket, as in busybox's list
(def %dr-main
  (fn (_ argv)
    (ud-logging! "dhcprelay" 0 #t #f)
    (set! %dr-items ())
    (if (< (length argv) 2) (cu-usage "dhcprelay")
      (let ((server (if (< (length argv) 3) 4294967295
                      ; busybox says errno, which its start leaves at EINVAL
                      (let ((a (ud-aton (cu-nth 2 argv))))
                        (if (null? a) (do (ud-perror "bad server IP" 22) (ud-end 1)) a)))))
        (def names (pair (cu-nth 1 argv) (Str8 split "," (first argv))))
        (def fds (map (fn (_ name) (ud-listen 67 name)) names))
        (let ((our (ud-interface-address (first names))))
          (if (null? our) 1
            (%dr-loop fds names our (ud-sin server 67))))))))

(def cu-dhcprelay
  (fn (_ argv stdin-thunk)
    (ud-process-reset!)
    (guard (e (if (eq? (cu-err-label e) (lit udhcp)) (ud-status) (error e)))
      (%dr-main argv))))

(provide cu/dhcprelay cu-dhcprelay)

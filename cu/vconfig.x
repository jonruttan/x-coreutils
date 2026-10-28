; # x-coreutils -- the small tools, as applets
;
; ## cu/vconfig.x -- vconfig: 802.1Q VLAN interfaces made and set
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's vconfig (networking/vconfig.c): one command, its words counted,
; read into a vlan_ioctl_args and handed to the kernel through SIOCSIFVLAN
; on an AF_INET socket.  add makes IFACE's VLAN_ID interface, rem removes
; one, set_flag sets a flag with its QoS, set_egress_map and
; set_ingress_map map a priority to a QoS, set_name_type names the
; interfaces add makes.  Commands and name types are matched without case.

(module cu/vconfig)

(import cu/cli cu-usage)
(import cu/inet inet-set! inet-zeros)
(import cu/inetd in-call)
(import cu/ping pn-number)
(import cu/prims byte-at byte-len cu-err-label cu-libc-sym cu-ptr-call
  cu-str->ptr file-write length libc-strerror map string-concat string=?)

(def %vc-die
  (fn (_ msg)
    (do (file-write 2 (string-concat (list "vconfig: " msg "\n")))
        (Err raise (lit vconfig) msg ()))))
(def %vc-usage (fn (_) (Err raise (lit vconfig-usage) "usage" ())))

; each command: (NAME CMD WORDS), WORDS counting the command's own
(def %vc-cmds
  (list (list "add" 0 3) (list "rem" 1 2) (list "set_name_type" 6 2)
        (list "set_flag" 7 4) (list "set_egress_map" 3 4) (list "set_ingress_map" 2 4)))

(def %vc-name-types
  (list (pair "VLAN_PLUS_VID" 0) (pair "VLAN_PLUS_VID_NO_PAD" 2)
        (pair "DEV_PLUS_VID" 1) (pair "DEV_PLUS_VID_NO_PAD" 3)))

(def %vc-same? (fn (_ a b) (string=? (Str8 downcase a) (Str8 downcase b))))

(def %vc-qos (fn (_ s) (pn-number s 0 7 %vc-die)))

; the vlan_ioctl_args WORDS ask for: cmd at 0, device1 at 4, the union at
; 28, vlan_qos at 52
(def %vc-args
  (fn (_ cmd words)
    (def a (inet-zeros 56))
    (inet-set! a 0 cmd 4)
    (if (= cmd 6)
      (let ((t (List find (fn (_ t) (%vc-same? (first t) (first (rest words)))) %vc-name-types)))
        (if (null? t) (%vc-usage) (inet-set! a 28 (rest t) 4)))
      (let ((dev (first (rest words))) (p (if (= cmd 1) () (List ref 2 words))))
        (do (List map (fn (_ i) (inet-set! a (+ 4 i) (byte-at dev i) 1))
                  (List range 0 (if (> (byte-len dev) 16) 16 (byte-len dev))))
            (match ((= cmd 7) (do (inet-set! a 28 (pn-number p 0 1 %vc-die) 4) (inet-set! a 52 (%vc-qos (List ref 3 words)) 2)))
                   ((= cmd 0) (inet-set! a 28 (pn-number p 0 4095 %vc-die) 4))
                   ((= cmd 1) ())
                   (#t (do (inet-set! a 28 (pn-number p 0 4294967295 %vc-die) 4) (inet-set! a 52 (%vc-qos (List ref 3 words)) 2)))))))
    a))

(def %vc-main
  (fn (_ words)
    (when (null? words) (%vc-usage))
    (def c (List find (fn (_ c) (%vc-same? (first c) (first words))) %vc-cmds))
    (when (if (null? c) #t (not (= (length words) (List ref 2 c)))) (%vc-usage))
    (def a (%vc-args (List ref 1 c) words))
    (def fd (in-call (cu-ptr-call (cu-libc-sym "socket") 2 1 0)))
    (when (< fd 0) (%vc-die (string-concat (list "socket(AF_INET,1,0): " (libc-strerror (Err errno-of fd))))))
    (def r (in-call (cu-ptr-call (cu-libc-sym "ioctl") fd 35203 (cu-str->ptr a))))
    (cu-ptr-call (cu-libc-sym "close") fd)
    (when (< r 0) (%vc-die (string-concat (list "ioctl error for " (first words) ": " (libc-strerror (Err errno-of r))))))
    0))

(def cu-vconfig
  (fn (_ argv stdin-thunk)
    (guard (e (match ((eq? (cu-err-label e) (lit vconfig-usage)) (cu-usage "vconfig"))
                     ((eq? (cu-err-label e) (lit vconfig)) 1)
                     (#t (error e))))
      (%vc-main argv))))

(provide cu/vconfig cu-vconfig)

# @weight 1

busybox's vconfig (networking/vconfig.c) counts a command's words and reads
its numbers before it asks the kernel, so those are tested here; Darwin has
no SIOCSIFVLAN and refuses each call, and the VLANs are tested as root in
the Linux leg.

## the fixture

### a run of vconfig, what it writes and its status

```cu
(do (def vc-f (fn (_ n) (string-append "/tmp/x-cu-vc." n)))
    (def vc-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (vc-f "out"))) (ee (file-open-write (vc-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (string-concat (list (file-read-all (vc-f "out")) "stderr:\n"
                                              (file-read-all (vc-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the words

### none, a command not known, a count not the command's

```cu
(do (vc-show (list "vconfig"))
    (vc-show (list "vconfig" "frob" "x"))
    (vc-show (list "vconfig" "add" "eth0"))
    (vc-show (list "vconfig" "rem" "eth0.5" "x")))
```
---
```output
stderr:
Usage: vconfig COMMAND [OPTIONS]

Create and remove virtual ethernet devices

	add IFACE VLAN_ID
	rem VLAN_NAME
	set_flag IFACE 0|1 VLAN_QOS
	set_egress_map VLAN_NAME SKB_PRIO VLAN_QOS
	set_ingress_map VLAN_NAME SKB_PRIO VLAN_QOS
	set_name_type NAME_TYPE
status 1
stderr:
Usage: vconfig COMMAND [OPTIONS]

Create and remove virtual ethernet devices

	add IFACE VLAN_ID
	rem VLAN_NAME
	set_flag IFACE 0|1 VLAN_QOS
	set_egress_map VLAN_NAME SKB_PRIO VLAN_QOS
	set_ingress_map VLAN_NAME SKB_PRIO VLAN_QOS
	set_name_type NAME_TYPE
status 1
stderr:
Usage: vconfig COMMAND [OPTIONS]

Create and remove virtual ethernet devices

	add IFACE VLAN_ID
	rem VLAN_NAME
	set_flag IFACE 0|1 VLAN_QOS
	set_egress_map VLAN_NAME SKB_PRIO VLAN_QOS
	set_ingress_map VLAN_NAME SKB_PRIO VLAN_QOS
	set_name_type NAME_TYPE
status 1
stderr:
Usage: vconfig COMMAND [OPTIONS]

Create and remove virtual ethernet devices

	add IFACE VLAN_ID
	rem VLAN_NAME
	set_flag IFACE 0|1 VLAN_QOS
	set_egress_map VLAN_NAME SKB_PRIO VLAN_QOS
	set_ingress_map VLAN_NAME SKB_PRIO VLAN_QOS
	set_name_type NAME_TYPE
status 1
```

### the numbers, and a name type not known

```cu
(do (vc-show (list "vconfig" "add" "eth0" "4096"))
    (vc-show (list "vconfig" "add" "eth0" "-1"))
    (vc-show (list "vconfig" "set_flag" "eth0.5" "2" "0"))
    (vc-show (list "vconfig" "set_flag" "eth0.5" "1" "8"))
    (vc-show (list "vconfig" "set_egress_map" "eth0.5" "x" "0"))
    (vc-show (list "vconfig" "set_ingress_map" "eth0.5" "1" "x"))
    (vc-show (list "vconfig" "set_name_type" "VLAN_PLUS")))
```
---
```output
stderr:
vconfig: number 4096 is not in 0..4095 range
status 1
stderr:
vconfig: invalid number '-1'
status 1
stderr:
vconfig: number 2 is not in 0..1 range
status 1
stderr:
vconfig: number 8 is not in 0..7 range
status 1
stderr:
vconfig: invalid number 'x'
status 1
stderr:
vconfig: invalid number 'x'
status 1
stderr:
Usage: vconfig COMMAND [OPTIONS]

Create and remove virtual ethernet devices

	add IFACE VLAN_ID
	rem VLAN_NAME
	set_flag IFACE 0|1 VLAN_QOS
	set_egress_map VLAN_NAME SKB_PRIO VLAN_QOS
	set_ingress_map VLAN_NAME SKB_PRIO VLAN_QOS
	set_name_type NAME_TYPE
status 1
```

## the call

### commands and name types matched without case, each refused

```cu
(do (vc-show (list "vconfig" "ADD" "eth0" "5"))
    (vc-show (list "vconfig" "Rem" "eth0.5"))
    (vc-show (list "vconfig" "set_name_type" "dev_plus_vid_no_pad")))
```
---
```output
stderr:
vconfig: ioctl error for ADD: Device not configured
status 1
stderr:
vconfig: ioctl error for Rem: Device not configured
status 1
stderr:
vconfig: ioctl error for set_name_type: Device not configured
status 1
```

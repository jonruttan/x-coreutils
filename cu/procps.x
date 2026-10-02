; # x-coreutils -- the small tools, as applets
;
; ## cu/procps.x -- uptime, free
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's procps tools that read the machine rather than a process: uptime
; (procps/uptime.c) and free (procps/free.c).  What they print comes from
; x/sys/host through the host-* doors in cu/prims.x, which read the same
; records on Linux and Darwin -- busybox's own sources, sysinfo(2) and
; /proc/meminfo, on Linux.  The layouts are busybox's to the space.
;
; uptime's clock is UTC: the platform's date has no timezone (cu/date.x), and
; busybox prints local time.  The users counted are the utmpx sessions of type
; USER_PROCESS with a user name, as busybox counts them.
;
; free on Darwin has no shared, buffers, reclaimable or available: each counts
; as busybox counts a /proc/meminfo line that is not there, 0, and the three it
; looks for not all being there adds its `-/+ buffers/cache:` line.

; A divided by B, the remainder dropped: the bundle has no quotient
(def %ps-div (fn (_ a b) (/ (- a (% a b)) b)))

; --- uptime -----------------------------------------------------------------

(def %cu-uptime
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "uptime" argv))
    ; busybox's uptime reads no operands, and refuses none
    (do (display
          (if (Opts on? o "-s")
            (%ps-boot-line (host-boot-time))
            (let ((now (date-now-unix)))
              (%ps-uptime-line now (- now (host-boot-time))
                (length (host-users)) (host-load-centi)))))
        0)))

; uptime -s: when the machine booted, as YYYY-MM-DD HH:MM:SS
(def %ps-boot-line
  (fn (_ boot)
    (def d (Date from-unix boot))
    (def two (fn (_ k) (%cu-pad-zero (%cu-int->str (Assoc get k d)) 2)))
    (string-concat
      (list (%cu-pad-zero (%cu-int->str (Assoc get (lit year) d)) 4)
            "-" (two (lit month)) "-" (two (lit day))
            " " (two (lit hour)) ":" (two (lit minute)) ":" (two (lit second)) "\n"))))

; uptime's line: the time NOW, the UP seconds since boot in days, hours and
; minutes, the USERS logged in and the LOADS, three hundredths
(def %ps-uptime-line
  (fn (_ now up users loads)
    (def d (Date from-unix now))
    (def two (fn (_ n) (%cu-pad-zero (%cu-int->str n) 2)))
    (def days (%ps-div up 86400))
    (def minutes (%ps-div up 60))
    (def hours (% (%ps-div minutes 60) 24))
    (def load (fn (_ c) (string-append (%cu-int->str (%ps-div c 100))
                          (string-append "." (two (% c 100))))))
    (string-concat
      (list " " (two (Assoc get (lit hour) d)) ":" (two (Assoc get (lit minute) d))
            ":" (two (Assoc get (lit second) d)) " up "
            (if (= days 0) ""
              (string-concat (list (%cu-int->str days) " day" (if (= days 1) "" "s") ", ")))
            (if (= hours 0)
              (string-append (%cu-int->str (% minutes 60)) " min")
              (string-concat (list (%cu-pad-left (%cu-int->str hours) 2) ":"
                                   (two (% minutes 60)))))
            ",  " (%cu-int->str users) " users"
            ",  load average: " (load (first loads))
            ", " (load (first (rest loads)))
            ", " (load (first (rest (rest loads)))) "\n"))))

; --- free -------------------------------------------------------------------

(def %cu-free
  (fn (_ argv stdin-thunk)
    ; the guard has refused a letter free does not know
    (%cu-opts "free" argv)
    (do (display (%ps-free-text (host-memory) (%ps-free-unit argv))) 0)))

; The unit free shows, from ARGV as busybox reads it: its first word alone,
; and of that the letter after the dash.  0 is -h's, human-readable.
(def %ps-free-unit
  (fn (_ argv)
    (def flag (if (null? argv) 0
                (let ((w (first argv)))
                  (if (if (> (byte-len w) 1) (= (byte-at w 0) #\-) #f) (byte-at w 1) 0))))
    (match ((= flag #\b) 1) ((= flag #\m) 1048576) ((= flag #\g) 1073741824)
           ((= flag #\h) 0) (#t 1024))))

; busybox's make_human_readable_str for a size in bytes: in UNIT's, rounded,
; or, UNIT 0, in the largest of K M G T ... under 1024, to a tenth
(def %ps-scale
  (fn (_ n unit)
    (def human
      (fn (self v frac u)
        (if (>= v 1024)
          (self (%ps-div v 1024) (%ps-div (+ (* (% v 1024) 10) 512) 1024) (+ u 1))
          (if (= u 0) (%cu-int->str v)
            (let ((v2 (if (>= frac 10) (+ v 1) v)) (f2 (if (>= frac 10) 0 frac)))
              (string-concat (list (%cu-int->str v2) "." (%cu-int->str f2)
                                   (substring "KMGTPEZY" (- u 1) u))))))))
    (match
      ((= n 0) "0")
      ((> unit 0) (%cu-int->str (%ps-div (+ n (%ps-div unit 2)) unit)))
      (#t (human n 0 0)))))

; free's table from MEM, Host's memory record, in UNIT
(def %ps-free-text
  (fn (_ mem unit)
    (def get (fn (_ k) (let ((v (Assoc get k mem))) (if (null? v) 0 v))))
    (def col (fn (_ n) (%cu-pad-left (%ps-scale n unit) 12)))
    (def seen (if (null? (Assoc get (lit cached) mem)) #f
                (if (null? (Assoc get (lit available) mem)) #f
                  (not (null? (Assoc get (lit reclaimable) mem))))))
    (def cached (+ (get (lit cached)) (+ (get (lit buffers)) (get (lit reclaimable)))))
    (def free (get (lit free)))
    (def total (get (lit total)))
    (def used (- total (+ cached free)))
    (string-concat
      (list "       " (%cu-pad-left "total" 12) (%cu-pad-left "used" 12)
            (%cu-pad-left "free" 12) (%cu-pad-left "shared" 12)
            (%cu-pad-left "buff/cache" 12) (%cu-pad-left "available" 12) "\n"
            "Mem:   " (col total) (col used) (col free)
            (col (get (lit shared))) (col cached) (col (get (lit available))) "\n"
            (if seen ""
              (string-concat (list "-/+ buffers/cache: " (col used) (col (+ cached free)) "\n")))
            "Swap:  " (col (get (lit swap-total)))
            (col (- (get (lit swap-total)) (get (lit swap-free))))
            (col (get (lit swap-free))) "\n"))))

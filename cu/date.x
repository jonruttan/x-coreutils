; # x-coreutils -- the small tools, as applets
;
; ## cu/date.x -- date, and the strftime it needs
;
; @description The clock read, and printed the way the caller asked.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; The calendar is x/sys/date.x's: it splits unix seconds into year, month, day,
; hour, minute, second and weekday by Hinnant's days/civil algorithms, and puts
; them back. Nothing here does calendar arithmetic -- %cu-date-fmt formats that
; alist, and the only sums it owns are a day-of-year and a twelve-hour clock.
;
; Everything is UTC, including without -u. The platform's date is UTC only
; ("No timezones, no locale -- boundary code converts at the edge"), so `date`
; and `date -u` print the same thing. -u is declared because asking for UTC and
; getting it honours the flag; the divergence is the other way, since a caller
; wanting local time gets UTC and is not told. That wants a timezone door in
; the platform.
;
; -s is not declared: setting the clock needs a syscall exposed on no arch this
; runs on here, and root besides.

(def %cu-date-wday-abbr
  (list "Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"))
(def %cu-date-wday-full
  (list "Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday"
        "Saturday"))
(def %cu-date-mon-abbr
  (list "Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct"
        "Nov" "Dec"))
(def %cu-date-mon-full
  (list "January" "February" "March" "April" "May" "June" "July"
        "August" "September" "October" "November" "December"))
(def %cu-date-mon-days
  (list 31 28 31 30 31 30 31 31 30 31 30 31))

(def %cu-date-get (fn (_ d k) (Assoc get k d)))

(def %cu-date-pad
  (fn (_ n width filler)
    (def s (%cu-int->str n))
    (def go
      (fn (self acc k)
        (if (<= k 0) acc (self (string-append filler acc) (- k 1)))))
    (go s (- width (byte-len s)))))

(def %cu-date-pad2 (fn (_ n) (%cu-date-pad n 2 "0")))

; Day of the year, 1-based: the months before this one, plus the day.
(def %cu-date-yday
  (fn (_ d)
    (def m (%cu-date-get d (lit month)))
    (def y (%cu-date-get d (lit year)))
    (def go
      (fn (self k acc)
        (if (>= k m) acc
          (self (+ k 1) (+ acc (%cu-nth (- k 1) %cu-date-mon-days))))))
    (+ (go 1 0)
       (+ (%cu-date-get d (lit day))
          (if (if (> m 2) (Date leap-year? y) #f) 1 0)))))

(def %cu-date-hour12
  (fn (_ h) (let ((r (% h 12))) (if (= r 0) 12 r))))

; One directive. The compound ones (%D %F %T %R %r) expand to a format and come
; back through the formatter, so their parts cannot drift from the spelled-out
; ones.
(def %cu-date-one
  (fn (_ c d secs)
    (match
      ((= c 89) (%cu-int->str (%cu-date-get d (lit year))))            ; Y
      ((= c 121) (%cu-date-pad2 (% (%cu-date-get d (lit year)) 100)))  ; y
      ((= c 67) (%cu-date-pad2 (/ (- (%cu-date-get d (lit year))
                                     (% (%cu-date-get d (lit year)) 100))
                                  100)))                               ; C
      ((= c 109) (%cu-date-pad2 (%cu-date-get d (lit month))))         ; m
      ((= c 100) (%cu-date-pad2 (%cu-date-get d (lit day))))           ; d
      ((= c 101) (%cu-date-pad (%cu-date-get d (lit day)) 2 " "))      ; e
      ((= c 72) (%cu-date-pad2 (%cu-date-get d (lit hour))))           ; H
      ((= c 107) (%cu-date-pad (%cu-date-get d (lit hour)) 2 " "))     ; k
      ((= c 73) (%cu-date-pad2 (%cu-date-hour12
                                 (%cu-date-get d (lit hour)))))        ; I
      ((= c 108) (%cu-date-pad (%cu-date-hour12
                                 (%cu-date-get d (lit hour))) 2 " "))  ; l
      ((= c 77) (%cu-date-pad2 (%cu-date-get d (lit minute))))         ; M
      ((= c 83) (%cu-date-pad2 (%cu-date-get d (lit second))))         ; S
      ((= c 106) (%cu-date-pad (%cu-date-yday d) 3 "0"))               ; j
      ((= c 97) (%cu-nth (%cu-date-get d (lit wday)) %cu-date-wday-abbr)) ; a
      ((= c 65) (%cu-nth (%cu-date-get d (lit wday)) %cu-date-wday-full)) ; A
      ((= c 98) (%cu-nth (- (%cu-date-get d (lit month)) 1)
                  %cu-date-mon-abbr))                                  ; b
      ((= c 104) (%cu-nth (- (%cu-date-get d (lit month)) 1)
                   %cu-date-mon-abbr))                                 ; h
      ((= c 66) (%cu-nth (- (%cu-date-get d (lit month)) 1)
                  %cu-date-mon-full))                                  ; B
      ((= c 112) (if (< (%cu-date-get d (lit hour)) 12) "AM" "PM"))    ; p
      ((= c 119) (%cu-int->str (%cu-date-get d (lit wday))))           ; w
      ((= c 117) (%cu-int->str (if (= (%cu-date-get d (lit wday)) 0) 7
                                 (%cu-date-get d (lit wday)))))        ; u
      ((= c 115) (%cu-int->str secs))                                  ; s
      ((= c 122) "+0000")                                              ; z
      ((= c 90) "UTC")                                                 ; Z
      ((= c 110) "\n")                                                 ; n
      ((= c 116) "\t")                                                 ; t
      ((= c 37) "%")                                                   ; %
      ((= c 68) (%cu-date-fmt "%m/%d/%y" d secs))                      ; D
      ((= c 70) (%cu-date-fmt "%Y-%m-%d" d secs))                      ; F
      ((= c 84) (%cu-date-fmt "%H:%M:%S" d secs))                      ; T
      ((= c 82) (%cu-date-fmt "%H:%M" d secs))                         ; R
      ((= c 114) (%cu-date-fmt "%I:%M:%S %p" d secs))                  ; r
      ; unreachable: %cu-date-fmt asks %cu-date-known? first and copies
      ; an unknown directive straight out of the format, which is how a
      ; stray % survives unharmed without a byte->string door here
      (#t ""))))

; The scanning is cu/fmt-lex.x's; the table above is date's. Escapes are off:
; the system date prints "a\nb" for the format "a\nb", and so does this.
(def %cu-date-fmt
  (fn (_ fmt d secs)
    (def go
      (fn (self ts acc)
        (if (null? ts) acc
          (self (rest ts)
            (string-append acc
              (if (%cu-fmt-dir? (first ts))
                (%cu-date-directive (%cu-fmt-conv (first ts)) d secs)
                (first ts)))))))
    (go (%cu-fmt-parse fmt #f) "")))

(def %cu-date-directive
  (fn (_ conv d secs)
    ; a format ending in a bare % keeps it as a directive with no conversion
    (if (= (byte-len conv) 0) "%"
      (let ((c (byte-at conv 0)))
        (if (%cu-date-known? c)
          (%cu-date-one c d secs)
          (string-append "%" conv))))))

(def %cu-date-known?
  (fn (_ c)
    (match
      ((= c 89) #t) ((= c 121) #t) ((= c 67) #t) ((= c 109) #t)
      ((= c 100) #t) ((= c 101) #t) ((= c 72) #t) ((= c 107) #t)
      ((= c 73) #t) ((= c 108) #t) ((= c 77) #t) ((= c 83) #t)
      ((= c 106) #t) ((= c 97) #t) ((= c 65) #t) ((= c 98) #t)
      ((= c 104) #t) ((= c 66) #t) ((= c 112) #t) ((= c 119) #t)
      ((= c 117) #t) ((= c 115) #t) ((= c 122) #t) ((= c 90) #t)
      ((= c 110) #t) ((= c 116) #t) ((= c 37) #t) ((= c 68) #t)
      ((= c 70) #t) ((= c 84) #t) ((= c 82) #t) ((= c 114) #t)
      (#t #f))))

; --- reading a time ----------------------------------------------------------
;
; -d takes @SECONDS or an ISO stamp the platform already parses. -D hands it a
; format instead, read by the same directives the formatter writes (%Y %m %d %H
; %M %S and literals), so the two cannot drift apart.

(def %cu-date-digits
  (fn (_ s i n)
    ; -> (VALUE . NEXT), reading at most N digits from I
    (def end (byte-len s))
    (def go
      (fn (self k acc got)
        (if (if (< k end) (if (< got n)
                            (let ((c (byte-at s k)))
                              (if (>= c 48) (<= c 57) #f))
                            #f) #f)
          (self (+ k 1) (+ (* acc 10) (- (byte-at s k) 48)) (+ got 1))
          (if (= got 0) () (pair acc k)))))
    (go i 0 0)))

; Reading a time walks the same tokens against an input instead of an output:
; a literal run must match rather than be emitted.
(def %cu-date-scan
  (fn (_ fmt s)
    (def send (byte-len s))
    (def lit-match
      (fn (self t si k)
        ; -> the position after T, or nil if the input does not carry it
        (if (>= k (byte-len t)) si
          (if (if (< si send) (= (byte-at s si) (byte-at t k)) #f)
            (self t (+ si 1) (+ k 1))
            ()))))
    (def go
      (fn (self ts si acc)
        (if (null? ts) acc
          (let ((t (first ts)))
            (if (%cu-fmt-dir? t)
              (let ((conv (%cu-fmt-conv t)))
                (if (= (byte-len conv) 0) ()
                  (let ((r (%cu-date-digits s si
                             (if (= (byte-at conv 0) 89) 4 2))))
                    (if (null? r) ()
                      (self (rest ts) (rest r)
                        (pair (pair (%cu-date-field (byte-at conv 0))
                                (first r)) acc))))))
              (let ((si2 (lit-match t si 0)))
                (if (null? si2) () (self (rest ts) si2 acc))))))))
    (go (%cu-fmt-parse fmt #f) 0 ())))

(def %cu-date-field
  (fn (_ c)
    (match
      ((= c 89) (lit year))   ((= c 109) (lit month))
      ((= c 100) (lit day))   ((= c 72) (lit hour))
      ((= c 77) (lit minute)) ((= c 83) (lit second))
      (#t (lit ignored)))))

(def %cu-date-of
  (fn (_ spec fmt)
    ; the seconds -d asked for, or nil
    (match
      ((null? spec) ())
      ((not (null? fmt))
        (let ((d (%cu-date-scan fmt spec)))
          (if (null? d) () (Date to-unix (%cu-date-whole d)))))
      ((if (> (byte-len spec) 1) (= (byte-at spec 0) 64) #f)
        (let ((r (%cu-date-digits spec 1 20)))
          (if (null? r) () (first r))))
      (#t
        (guard (e ())
          (let ((d (Date from-iso spec)))
            (if (null? d) () (Date to-unix d))))))))

; A scanned date holds only the fields the format named; to-unix wants a day
; and a month at least, so the missing ones take the epoch's.
(def %cu-date-whole
  (fn (_ d)
    (list (pair (lit year) (Assoc get-or 1970 (lit year) d))
          (pair (lit month) (Assoc get-or 1 (lit month) d))
          (pair (lit day) (Assoc get-or 1 (lit day) d))
          (pair (lit hour) (Assoc get-or 0 (lit hour) d))
          (pair (lit minute) (Assoc get-or 0 (lit minute) d))
          (pair (lit second) (Assoc get-or 0 (lit second) d)))))

; --- the applet --------------------------------------------------------------

; -I's spec is attached and optional (`-I`, `-Iseconds`), and Opts knows only
; flags and options that take an argument. Declared as the latter, -I swallows
; the next token, so `date -I -d @X` reads -d as the spec. The five spellings
; are declared as flags instead, which the parser matches whole before trying
; them as a cluster. Answers nil when no spelling was given.
(def %cu-date-iso-fmt
  (fn (_ o)
    (match
      ((Opts on? o "-Iseconds") "%Y-%m-%dT%H:%M:%S+0000")
      ((Opts on? o "-Iminutes") "%Y-%m-%dT%H:%M+0000")
      ((Opts on? o "-Ihours") "%Y-%m-%dT%H+0000")
      ((Opts on? o "-Ins") "%Y-%m-%dT%H:%M:%S,000000000+0000")
      ((Opts on? o "-Idate") "%Y-%m-%d")
      ((Opts on? o "-I") "%Y-%m-%d")
      (#t ()))))

(def %cu-date-plus
  (fn (self ops)
    (if (null? ops) ()
      (if (= (byte-at (first ops) 0) 43)
        (substring (first ops) 1 (byte-len (first ops)))
        (self (rest ops))))))

(def %cu-date
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "date" argv))
    (def ops (Opts operands o))
    (def rfile (Opts value o "-r"))
    (def dspec (Opts value o "-d"))
    ; A -d that will not parse is an error, not a fall back to now; the two
    ; cases are told apart by whether -d was given at all.
    (def secs
      (match
        ((not (null? rfile))
          (%cu-stat-get (file-stat-full rfile) (lit mtime)))
        ((not (null? dspec)) (%cu-date-of dspec (Opts value o "-D")))
        (#t (date-now-unix))))
    (if (null? secs)
      (do (file-write 2
            (string-append "date: invalid date '"
              (string-append dspec "'\n"))) 1)
      (let ((d (Date from-unix secs)))
        (let ((fmt
                (match
                  ((Opts on? o "-R") "%a, %d %b %Y %H:%M:%S %z")
                  ((not (null? (%cu-date-iso-fmt o))) (%cu-date-iso-fmt o))
                  ((not (null? (%cu-date-plus ops))) (%cu-date-plus ops))
                  (#t "%a %b %e %H:%M:%S %Z %Y"))))
          (do (display (string-append (%cu-date-fmt fmt d secs) "\n")) 0))))))


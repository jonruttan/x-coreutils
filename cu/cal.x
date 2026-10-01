; # x-coreutils -- the small tools, as applets
;
; ## cu/cal.x -- cal
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's cal (util-linux/cal.c), in the C locale: a month, or with one
; operand or -y a year, three months a row (two under -j).  -j numbers the
; days through the year, -m starts the week on Monday.  The calendar is the
; Julian one up to 2 September 1752 and the Gregorian one from 14 September,
; the days between left out.  With no operand it is this month, or under -y
; this year -- as the bundle's date knows today, in UTC.
;
; The layout is busybox's to the space: a row's trailing spaces are trimmed,
; except in a row that is nothing but spaces, which goes out whole; and the
; centred names and the year keep the spaces that follow them.

(def %cal/ (prim-ref (lit int) (lit /)))

(def %cal-month-names
  (list "January" "February" "March" "April" "May" "June" "July" "August"
        "September" "October" "November" "December"))

(def %cal-day-names (list "Su" "Mo" "Tu" "We" "Th" "Fr" "Sa"))

(def %cal-month-days (list 0 31 28 31 30 31 30 31 31 30 31 30 31))

; the days of September 1752 that were
(def %cal-sep1752
  (list 1 2 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30))

(def %cal-sum
  (fn (self ns) (if (null? ns) 0 (+ (first ns) (self (rest ns))))))

; the leap years: every fourth up to 1752, then the Gregorian rule
(def %cal-leap?
  (fn (_ y)
    (if (<= y 1752) (= (% y 4) 0)
      (if (if (= (% y 4) 0) (not (= (% y 100) 0)) #f) #t (= (% y 400) 0)))))

; the leap years from year 1 up to Y, as busybox counts them
(def %cal-leaps-to
  (fn (_ y)
    (+ (- (%cal/ y 4) (if (> y 1700) (- (%cal/ y 100) 17) 0))
       (if (> y 1600) (%cal/ (- y 1600) 400) 0))))

; busybox's day_array: the month's 42 slots, six weeks from WEEKSTART, each a
; day's number -- of the month, or under JULIAN of the year -- or nil
(def %cal-days
  (fn (_ month year weekstart julian)
    (def days (vec-make 42 ()))
    (def fill
      (fn (self i day dm)
        (if (= dm 0) days
          (do (vec-set! days i day) (self (+ i 1) (+ day 1) (- dm 1))))))
    (def sep
      (fn (self i ds)
        (if (null? ds) days
          (do (vec-set! days (- (+ i 2) weekstart)
                (+ (first ds) (if julian 244 0)))
              (self (+ i 1) (rest ds))))))
    (if (if (= month 9) (= year 1752) #f) (sep 0 %cal-sep1752)
      (let ((leap (%cal-leap? year)))
        (let ((yday (+ (if (if (> month 2) leap #f) 2 1)
                       (%cal-sum (%cu-take %cal-month-days month)))))
          (let ((temp (+ (* (- year 1) 365) (+ (%cal-leaps-to (- year 1)) yday))))
            (let ((dw (% (- (+ temp 5) (if (< temp 639787) 0 11)) 7)))
              (fill (% (+ (- dw weekstart) 7) 7)
                (if julian yday 1)
                (+ (%cu-nth month %cal-month-days)
                   (if (if (= month 2) leap #f) 1 0))))))))))

; busybox's build_row: the seven days of DAYS from slot AT, three columns a
; day, four under JULIAN, the number at the right of each but the last
(def %cal-row
  (fn (_ days at julian)
    (def digit (fn (_ d) (+ #\0 d)))
    (def cell
      (fn (_ day)
        (match
          ((null? day) (if julian (list #\space #\space #\space #\space)
                         (list #\space #\space #\space)))
          (julian
            (let ((h (%cal/ day 100)) (t (%cal/ (% day 100) 10)))
              (list (if (> h 0) (digit h) #\space)
                    (if (> t 0) (digit t) (if (> h 0) #\0 #\space))
                    (digit (% day 10)) #\space)))
          (#t (let ((t (%cal/ day 10)))
                (list (if (> t 0) (digit t) #\space) (digit (% day 10)) #\space))))))
    (def go
      (fn (self col acc)
        (if (= col 7) (bytes->str acc)
          (self (+ col 1) (append acc (cell (vec-ref days (+ at col))))))))
    (go 0 ())))

; busybox's trim_trailing_spaces_and_print: S, its trailing spaces trimmed --
; unless it is nothing but spaces, which stays as it is -- and a newline
(def %cal-line
  (fn (_ s)
    (def go
      (fn (self i)
        (match
          ((< i 0) (string-append s "\n"))
          ((%ts-space? (byte-at s i)) (self (- i 1)))
          (#t (string-append (substring s 0 (+ i 1)) "\n")))))
    (go (- (byte-len s) 1))))

; busybox's center: S in LEN columns, the odd one after it, then SEP more
(def %cal-center
  (fn (_ s len sep)
    (def gap (- len (byte-len s)))
    (string-append (%cu-pad-left s (+ (%cal/ gap 2) (byte-len s)))
      (%cu-pad-left "" (+ (%cal/ gap 2) (+ (% gap 2) sep))))))

; the day headings, from WEEKSTART; under JULIAN four columns a day
(def %cal-headings
  (fn (_ weekstart julian)
    (def names
      (append (%cu-nthrest weekstart %cal-day-names) (%cu-take %cal-day-names weekstart)))
    (def go
      (fn (self ns acc)
        (if (null? ns) (string-concat (reverse acc))
          (self (rest ns)
            (pair (string-append (if julian " " "") (first ns))
              (if (null? acc) acc (pair " " acc)))))))
    (go names ())))

; one month, its name and year centred over it
(def %cal-month
  (fn (_ month year weekstart julian)
    (def days (%cal-days month year weekstart julian))
    (def title
      (string-concat
        (list (%cu-nth (- month 1) %cal-month-names) " " (%cu-int->str year))))
    (def rows
      (fn (self at acc)
        (if (= at 42) (reverse acc)
          (self (+ at 7) (pair (%cal-line (%cal-row days at julian)) acc)))))
    (string-concat
      (append
        (list (%cu-pad-left "" (%cal/ (- (+ (if julian 7 0) 20) (byte-len title)) 2))
              title "\n" (%cal-headings weekstart julian) "\n")
        (rows 0 ())))))

; a year, three months a row, two under JULIAN
(def %cal-year
  (fn (_ year weekstart julian)
    (def per (if julian 2 3))
    (def week-len (if julian 27 20))
    (def heads (%cal-headings weekstart julian))
    (def all
      (vec-build 12 (fn (_ i) (%cal-days (+ i 1) year weekstart julian))))
    (def names-line
      (fn (_ m)
        (def go
          (fn (self k acc)
            (if (= k per) (string-concat (reverse acc))
              (self (+ k 1)
                (pair (%cal-center (%cu-nth (+ m k) %cal-month-names) week-len
                        (if (= k (- per 1)) 0 2))
                  acc)))))
        (go 0 ())))
    (def row
      (fn (_ m at)
        (def go
          (fn (self k acc)
            (if (= k per) (string-concat (reverse acc))
              (self (+ k 1)
                (pair (%cal-row (vec-ref all (+ m k)) at julian)
                  (if (null? acc) acc (pair " " acc)))))))
        (%cal-line (%cu-pad-right (go 0 ()) 79))))
    (def block
      (fn (_ m)
        (def rows
          (fn (self at acc)
            (if (= at 42) (reverse acc) (self (+ at 7) (pair (row m at) acc)))))
        (string-concat
          (append
            (list (names-line m) "\n" heads "  " heads (if julian "" (string-append "  " heads))
                  "\n")
            (rows 0 ())))))
    (def blocks
      (fn (self m acc)
        (if (>= m 12) (reverse acc) (self (+ m per) (pair (block m) acc)))))
    (string-concat
      (pair (%cal-center (%cu-int->str year) (if julian 56 64) 0)
        (pair "\n\n" (blocks 0 ()))))))

(def %cal-usage
  (fn (_)
    (do (file-write 2
          (string-concat
            (list "Usage: cal [-jmy] [[MONTH] YEAR]\n\nDisplay a calendar\n\n"
                  "\t-j\tUse julian dates\n"
                  "\t-m\tWeek starts on Monday\n"
                  "\t-y\tDisplay the entire year\n")))
        1)))

; cal [-jmy] [[MONTH] YEAR]
(def %cu-cal
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "cal" argv))
    (def ops (Opts operands o))
    (def n (length ops))
    (def julian (Opts on? o "-j"))
    (def weekstart (if (Opts on? o "-m") 1 0))
    (def year? (Opts on? o "-y"))
    (def show
      (fn (_ month year)
        (do (file-write 1
              (if (= month 0) (%cal-year year weekstart julian)
                (%cal-month month year weekstart julian)))
            0)))
    (match
      ((> n 2) (%cal-usage))
      ((= n 0)
        (let ((today (Date now)))
          (show (if year? 0 (Assoc get (lit month) today)) (Assoc get (lit year) today))))
      (#t
        (let ((month (if (if (= n 2) (not year?) #f)
                       (%cu-range-number "cal" (first ops) 1 12)
                       0)))
          (if (null? month) 1
            (let ((year (%cu-range-number "cal" (%cu-nth (- n 1) ops) 1 9999)))
              (if (null? year) 1 (show month year)))))))))

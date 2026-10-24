; # x-coreutils -- the small tools, as applets
;
; ## cu/sysctl.x -- sysctl: the kernel's parameters, under /proc/sys
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's sysctl (procps/sysctl.c).  A key is a path under /proc/sys with
; dots for its slashes: kernel.hostname is /proc/sys/kernel/hostname.  A key
; read is its file's lines, each after `KEY = ` unless -n; a directory, or -a,
; is every file under it, in the order the kernel lists them.  KEY=VALUE, or
; -w, writes VALUE to the key's file and says it unless -q; -p reads such
; lines from FILEs, /etc/sysctl.conf by default.  An unknown key is said
; unless -e.

(module cu/sysctl)

(import cu/cli cu-opts)
(import cu/dump dp-find)
(import cu/prims byte-at byte-len cu-lines cu-sweep-lines cu-sweep-tick!
  file-close file-dir? file-err-sym file-err-text file-exists? file-list-dir
  file-open-err file-open-read file-open-write file-or-err file-read-all
  file-read-to-end file-write map reverse string-append string-concat string=?
  substring)

(def %sy-root "/proc/sys/")

(def %sy-say (fn (_ msg) (file-write 2 (string-append "sysctl: " msg "\n"))))

; S with each slash a dot and each dot a slash: a key from a path, and back.
; A tab stands in for the dots on the way, as no key holds one.
(def %sy-swap
  (fn (_ s)
    (if (= (dp-find s 0 #\.) -1) (Str8 replace "/" "." s)
      (Str8 replace "\t" "/" (Str8 replace "/" "." (Str8 replace "." "\t" s))))))

; sysctl_dots_to_slashes: NAME, a key up to its =, as the path of a file
; that is there.  A name with a slash after its first dot has its dots and
; slashes swapped (net.ipv4.conf.eth0/100.mc_forwarding); otherwise as few
; dots are slashes as reach a path that is there, tried from the end, so
; eth0.100 stays one name where net/ipv4/conf/eth0.100 is a directory.
(def %sy-path
  (fn (_ name)
    (def eq (let ((i (dp-find name 0 #\=))) (if (< i 0) (byte-len name) i)))
    (def key (substring name 0 eq))
    (def tail (substring name eq (byte-len name)))
    (def slash (dp-find key 0 #\/))
    (def dot (dp-find key 0 #\.))
    (if (if (>= slash 0) (if (>= dot 0) (< dot slash) #f) #f)
      (string-append (%sy-swap key) tail)
      (string-append (%sy-dots key) tail))))

; KEY with the fewest of its dots made slashes, from the end, that name a
; path under /proc/sys; KEY itself where none does
(def %sy-dots
  (fn (_ key)
    (def there? (fn (_ s) (file-exists? (string-append %sy-root s))))
    ; from the end back to LAST (the last dot made a slash), the first dot
    ; whose prefix is there becomes a slash, and the search starts again
    ; the whole name counts as one more prefix, a dot at its end: where it
    ; is there, nothing is changed
    (def again
      (fn (self s last)
        (let ((at (let go ((i (byte-len s)))
                    (match
                      ((<= i last) -1)
                      ((if (< i (byte-len s)) (not (= (byte-at s i) #\.)) #f) (go (- i 1)))
                      ((there? (substring s 0 i)) i)
                      (#t (go (- i 1)))))))
          (match
            ((< at 0) s)
            ((= at (byte-len s)) s)
            (#t (self (string-append (substring s 0 at) "/" (substring s (+ at 1) (byte-len s))) at))))))
    (again key -1)))

; sysctl_act_on_setting: SETTING (a path under /proc/sys, =VALUE after it to
; write) read or written; #t where it went well
(def %sy-setting
  (fn (_ o setting)
    ; a key read or written leaves tens of thousands of objects
    (cu-sweep-tick! cu-sweep-lines)
    (def eq (dp-find setting 0 #\=))
    (def writing (if (>= eq 0) #t (Opts on? o "-w")))
    (def name (if (>= eq 0) (substring setting 0 eq) setting))
    (def out (%sy-swap (if writing name setting)))
    (def keys? (not (Opts on? o "-n")))
    (def path (string-append %sy-root name))
    (match
      ((if writing (< eq 0) #f)
        (do (%sy-say (string-append "error: '" (%sy-swap setting) "' must be of the form name=value")) #f))
      ((if writing (= eq 0) #f)
        (do (%sy-say (string-append "error: malformed setting '" (%sy-swap setting) "'")) #f))
      (#t
        (let ((fd (if writing (file-open-write path) (file-open-read path))))
          (if (< fd 0)
            (let ((e (file-open-err fd path)))
              (match
                ((eq? (file-err-sym e) (lit enoent))
                  (do (unless (Opts on? o "-e") (%sy-say (string-append "error: '" out "' is an unknown key"))) #f))
                ; a key only written, as net.ipv6.route.flush, is passed over when read
                ((if (eq? (file-err-sym e) (lit eacces)) (not writing) #f) #t)
                (#t (do (%sy-say (string-concat (list "error " (if writing "sett" "read") "ing key '" out "': " (file-err-text e)))) #f))))
            (if writing
              (let ((value (substring setting (+ eq 1) (byte-len setting))))
                (do (file-write fd value) (file-close fd)
                    (unless (Opts on? o "-q")
                      (file-write 1 (string-append (if keys? (string-append out " = ") "") value "\n")))
                    #t))
              (let ((text (file-read-to-end fd path)))
                (do (file-close fd)
                    (if (Err err? text)
                      (do (%sy-say (string-concat (list "error reading key '" out "': " (file-err-text text)))) #f)
                      (do (%sy-lines text (if keys? (string-append out " = ") ""))
                          #t)))))))))))

; TEXT written a line at a time, each after LEAD, its last line as it ends
(def %sy-lines
  (fn (self text lead)
    (unless (= (byte-len text) 0)
      (let ((nl (dp-find text 0 #\newline)))
        (if (< nl 0) (file-write 1 (string-append lead text))
          (do (file-write 1 (string-append lead (substring text 0 (+ nl 1))))
              (self (substring text (+ nl 1) (byte-len text)) lead)))))))

; sysctl_act_recursive: PATH, a directory read through every file under it,
; or one setting; #t where every one went well
(def %sy-walk
  (fn (self o path)
    (if (if (Opts on? o "-w") #f (if (>= (dp-find path 0 #\=) 0) #f (file-dir? (string-append %sy-root path))))
      ; File list-dir answers the entries last first; the kernel's order is the
      ; other way round
      (let ((names (reverse (guard (_ ()) (file-list-dir (string-append %sy-root path))))))
        (let go ((ns names) (ok #t))
          (if (null? ns) ok
            (go (rest ns) (if (self o (if (string=? path ".") (first ns) (string-append path "/" (first ns)))) ok #f)))))
      (%sy-setting o path))))

; sysctl_handle_preload_file: each KEY = VALUE line of FILE written, a line
; whose first word starts # or ; passed over
(def %sy-preload
  (fn (_ o file)
    (let ((text (file-or-err (fn (_) (file-read-all file)))))
      (if (Err err? text)
        (do (%sy-say (string-concat (list file ": " (file-err-text text)))) #f)
        (do (map (fn (_ line)
                   (let ((t (sy-trim line)))
                     (unless (if (= (byte-len t) 0) #t (if (= (byte-at t 0) #\#) #t (= (byte-at t 0) #\;)))
                       (let ((eq (dp-find t 0 #\=)))
                         (unless (< eq 0)
                           (%sy-setting o (string-append (%sy-path (sy-trim (substring t 0 eq))) "="
                                                         (sy-trim (substring t (+ eq 1) (byte-len t))))))))))
                 (cu-lines text))
            #t)))))

(def %sy-space? (fn (_ c) (if (= c #\space) #t (= c #\tab))))

(def sy-trim
  (fn (_ s)
    (def a (let go ((i 0)) (if (if (< i (byte-len s)) (%sy-space? (byte-at s i)) #f) (go (+ i 1)) i)))
    (def b (let go ((j (byte-len s))) (if (if (> j a) (%sy-space? (byte-at s (- j 1))) #f) (go (- j 1)) j)))
    (substring s a b)))

(def cu-sysctl
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "sysctl" argv))
    (def ops (Opts operands o))
    (match
      ((Opts on? o "-p")
        (do (map (fn (_ f) (%sy-preload o f)) (if (null? ops) (list "/etc/sysctl.conf") ops)) 0))
      ((if (Opts on? o "-a") #t (Opts on? o "-A")) (if (%sy-walk o ".") 0 1))
      (#t (let go ((ks ops) (ok #t))
            (if (null? ks) (if ok 0 1)
              (go (rest ks) (if (%sy-walk o (%sy-path (first ks))) ok #f))))))))

(provide cu/sysctl cu-sysctl sy-trim)

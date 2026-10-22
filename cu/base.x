; # x-coreutils -- the small tools, as applets
;
; ## cu/base.x -- the tool chest, assembled
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

; the modules' exports, bound in the root for the files that are not modules yet
(import cu/prims append bit-and bit-or bit-shl bit-shr bit-xor byte-at
  byte-len char->integer cu% cu& cu* cu+ cu- cu-as-run cu-b->s cu-cstr-at
  cu-dlopen cu-dlsym cu-err-label cu-fd-fields cu-file-read cu-heap-collect
  cu-hexs cu-int->ptr cu-int->str cu-lines cu-mode-file-type cu-nth
  cu-piece-bytes cu-ptr->str cu-ptr-call cu-ptr-ref cu-ptr-set! cu-ptr-word
  cu-rev cu-run-bytes cu-run-list cu-run-of cu-sig-ign cu-sighup cu-sigint
  cu-sigkill cu-sigterm cu-stdin! cu-stdin-chunk! cu-stdin-fields!
  cu-stdin-moved cu-stdin-to-command! cu-str->ptr cu-string-type cu-sweep!
  cu-sweep-at cu-sweep-bytes cu-sweep-lines cu-sweep-steps cu-sweep-tick!
  cu-sweeps-cell cu-type-of cu-words-line cu/ cu< cu<< cu>> cvt date-now-unix
  file-chmod file-chown file-close file-copy file-dir? file-err-op
  file-err-sym file-err-text file-exists? file-lchown file-link file-list-dir
  file-lstat-file-type file-lstat-full file-lstat-wide file-mkdir file-mkfifo
  file-mounts file-open-append file-open-err file-open-excl file-open-or-err
  file-open-read file-open-update file-open-write file-open-wronly file-or-err
  file-read-all file-read-fd file-read-run file-read-to-end file-read-unsized
  file-readlink file-rename file-rmdir file-seek file-set-times file-stat
  file-stat-full file-stat-wide file-statfs-full file-symlink file-truncate
  file-unlink file-utimes file-write file-write-all file-write-field
  file-write-nuls file-write-random file-write-run filter host-args
  host-boot-time host-counters host-cpu host-cpus host-cwd host-disks host-exe
  host-files host-files-of host-holders host-interfaces host-interrupts
  host-load-centi host-load-fixed host-maps host-memory host-process
  host-processes host-regions host-tasks host-threads host-users host-utmp
  http-close http-head http-open http-read http-status integer->char length
  libc-strerror list->string load-centi map net-accept net-aton net-base64
  net-close net-connect net-listen net-listen-on net-peer net-recv-from-run
  net-recv-run net-resolve net-send net-send-run net-send-to-run net-shutdown
  net-sock-addr net-sockaddr net-sockaddr-read net-stdin-socket net-udp-bind
  net-udp-connect net-udp-open proc-run re-compile re-search reverse rng-int
  rng-make set-first! str-make-raw string-append string-concat string=?
  substring sys-chroot sys-close sys-cpu-count sys-dup2 sys-environ sys-exec
  sys-exec-or-err sys-exit sys-fork sys-fsync sys-getcwd sys-getegid
  sys-getenv sys-geteuid sys-getgid sys-getgroups sys-getpid sys-getuid
  sys-group-id sys-group-name sys-isatty sys-kill sys-nice sys-pipe sys-poll
  sys-setenv sys-signal sys-signals sys-sleep sys-sync sys-time-ms sys-umask
  sys-uname sys-unsetenv sys-user-group sys-user-groups sys-user-id
  sys-user-name sys-usleep sys-wait vec-build vec-make vec-ref vec-set!)
(import cu/applets)

(provide cu/base cu-version cu-run cu-argv cu-main cu-sha256
  %cu-repl-print)

(def cu-version "0.1.0")

(def %cu-repl-print
  (fn (_ result)
    (unless (null? result) (write result))
    (newline)))

(import cu/text cu-basename cu-byte-in? cu-comm cu-delim-fields
  cu-delim-fields-said cu-dirname cu-each-run-said cu-each-said cu-enough
  cu-fd-chunks cu-file-pieces cu-first-unopened cu-fold-lines-said cu-fold-one
  cu-fold-pieces cu-fold-said cu-fold-stdin cu-gather-said cu-head cu-join
  cu-join-with cu-map-swept cu-member-s? cu-merge cu-msort cu-newlines-from
  cu-num-prefix cu-pad-left cu-pad-right cu-pad-zero cu-pieces cu-pieces-past
  cu-print-fields cu-print-fields-to cu-print-lines cu-print-lines-to
  cu-put-each cu-read-error cu-read-run-said cu-read-said cu-run-from
  cu-run-join cu-run-nul? cu-run-part cu-run-slice cu-run-text cu-say cu-says
  cu-says-open cu-says-read cu-split-byte cu-stdin-pieces cu-str< cu-tail
  cu-tail-follow cu-tail-round cu-text-from cu-unmarked cu-wc cu-with-sources)
(import cu/trcut cu-cut cu-tr)
(import cu/fs cat-ranges cu-cat cu-cp cu-ln cu-mkdir cu-mv cu-rm cu-rmdir)
(include-once "./sha256.x")
(include-once "./hash.x")
(include-once "./crypt.x")
(include-once "./sha512.x")
(include-once "./text3.x")
(import cu/encode cu-od cu-uudecode cu-uuencode)
(import cu/expr cu-expr)
(include-once "./perm.x")
(include-once "./who.x")
(include-once "./text2.x")
(include-once "./fs2.x")
(include-once "./sys2.x")
(include-once "./test.x")
(include-once "./fs3.x")
(include-once "./ls.x")
(include-once "./sort.x")
(import cu/text4 cu-nl cu-uniq)
(include-once "./walk.x")
(include-once "./fmt-lex.x")
(include-once "./date.x")
(include-once "./diff-lex.x")
(import cu/diff cu-diff cu-diff-dir cu-diff-str)
(include-once "./find.x")
(include-once "./vi.x")
(include-once "./vi-move.x")
(include-once "./vi-edit.x")
(include-once "./vi-ex.x")
(include-once "./vi-set.x")
(include-once "./vi-undo.x")
(import cu/more cu-clear cu-more cu-reset more-typed)
(include-once "./tsort.x")
(include-once "./strings.x")
(include-once "./cal.x")
(include-once "./net.x")
(include-once "./nc.x")
(import cu/dns cu-nslookup ns-bytes ns-drop ns-hex ns-name ns-u16)
(include-once "./tftp.x")
(include-once "./ftp.x")
(include-once "./dump.x")
(include-once "./hexdump.x")
(import cu/tree cu-tree)
(import cu/time cu-time)
(import cu/base32 cu-base32)
(import cu/ascii cu-ascii cu-crc32 cu-uuidgen)
(include-once "./session.x")
(include-once "./httpd.x")
(import cu/dnsd cu-dnsd)
(include-once "./inetd.x")
(import cu/fakeidentd cu-fakeidentd)
(include-once "./telnet.x")
(include-once "./telnetd.x")
(include-once "./mime.x")
(include-once "./sendmail.x")
(import cu/popmaildir cu-popmaildir)
(include-once "./ntpd.x")
(import cu/dumpleases cu-dumpleases)
(include-once "./sslclient.x")
(import cu/sslserver cu-ssl-server)
(include-once "./tcpsvd.x")
(import cu/ftpd cu-ftpd)
(import cu/ipcalc cu-ipcalc)
(import cu/getopt cu-getopt)
(import cu/runparts cu-run-parts)
(include-once "./tar.x")
(include-once "./gzip.x")
(import cu/unzip cu-unzip)
(import cu/cpio cu-cpio)
(import cu/dc cu-dc)
(import cu/ed cu-ed)
(import cu/patch cu-patch)
(include-once "./sysinfo.x")
(import cu/sha3 cu-sha3sum)
(include-once "./procps.x")
(include-once "./sysctl.x")
(import cu/lsmod cu-lsmod)
(include-once "./inet.x")
(include-once "./route.x")
(include-once "./arp.x")
(import cu/netstat cu-netstat)
(include-once "./ifconfig.x")
(include-once "./ip.x")
(include-once "./ipset.x")
(include-once "./iproute.x")
(include-once "./top.x")
(include-once "./vmstat.x")
(include-once "./iostat.x")
(import cu/mpstat cu-mpstat)
(import cu/nmeter cu-nmeter nm-line nm-parse nm-sample)
(import cu/pmap cu-pmap)
(include-once "./watch.x")
(include-once "./fuser.x")
(include-once "./options.x")
(import cu/cli cu-argv cu-dispatch cu-extra-operand cu-find-applet
  cu-last-given cu-last-valued cu-main cu-missing-file-operand
  cu-missing-operand cu-operands cu-opts cu-refuse-option cu-run cu-spec-of
  cu-string-stdin cu-usage)

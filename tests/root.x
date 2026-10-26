; # x-coreutils -- the small tools, as applets
;
; ## tests/root.x -- every module's exports, bound in the root
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The specs drive the modules' functions by name from the root, so the
; harness includes this beside cu/base: one import a module, of its provide.

(import cu/applets Applets)
(import cu/arp ar-ether cu-arp)
(import cu/arping cu-arping)
(import cu/ascii cu-ascii cu-crc32 cu-uuidgen)
(import cu/base32 cu-base32)
(import cu/brctl cu-brctl)
(import cu/cal cal-sum cu-cal)
(import cu/cli cu-applets! cu-argv cu-dispatch cu-extra-operand cu-families
  cu-find-applet cu-last-given cu-last-valued cu-main cu-missing-file-operand
  cu-missing-operand cu-operands cu-opts cu-refuse-option cu-run cu-spec-of
  cu-string-stdin cu-usage)
(import cu/cpio cu-cpio)
(import cu/crypt cu-cryptpw cu-mkpasswd cu-pw-encrypt hd-salt)
(import cu/date cu-date cu-date-fmt cu-date-moment cu-date-mon-abbr cu-date-of
  cu-date-split cu-date-today)
(import cu/dc cu-dc)
(import cu/diff cu-diff cu-diff-dir cu-diff-str)
(import cu/diff-lex cu-dl-lines)
(import cu/dns cu-nslookup ns-bytes ns-drop ns-hex ns-name ns-u16)
(import cu/dnsd cu-dnsd)
(import cu/dump cu-dump cu-dump-add cu-dump-address cu-dump-all!
  cu-dump-displayoff! cu-dump-length! cu-dump-reset! cu-dump-skip!
  cu-dump-xxd-eof! dp-at dp-digit? dp-find dp-formats dp-in? dp-skip-in
  dp-skip-ws dp-udigits dp-zeros)
(import cu/dumpleases cu-dumpleases)
(import cu/ed cu-ed)
(import cu/encode cu-od cu-uudecode cu-uuencode)
(import cu/expr cu-expr)
(import cu/fakeidentd cu-fakeidentd)
(import cu/find cu-find cu-glob-class cu-glob?)
(import cu/fmt-lex cu-esc-at cu-esc-run cu-fmt-conv cu-fmt-dir? cu-fmt-left?
  cu-fmt-parse cu-fmt-raw cu-fmt-width cu-runs-onto cu-write-runs)
(import cu/fs cat-ranges cu-cat cu-cp cu-ln cu-mkdir cu-mv cu-rm cu-rmdir)
(import cu/fs2 cu-base-of cu-cmp cu-cmp-walk cu-install cu-mkdir-p! cu-mktemp
  cu-pwd cu-touch)
(import cu/fs3 cu-dd cu-dd-has? cu-dd-records cu-dev-major cu-dev-minor cu-du
  cu-du-blocks cu-mode-octal4 cu-nohup cu-path-join cu-perm-places
  cu-perm-string cu-shred cu-stat cu-stat-group cu-stat-user cu-timeout
  cu-truncate cu-tty cu-unlink cu-usleep)
(import cu/ftp cu-ftpget cu-ftpput)
(import cu/ftpd cu-ftpd)
(import cu/fuser cu-fuser)
(import cu/getopt cu-getopt)
(import cu/gzip cu-gunzip cu-gzip cu-zcat gz-at gz-copy gz-ends? gz-sink
  gz-sink-close! gz-sink-write! gz-sniff gz-tar-pieces)
(import cu/hash cu-bytes cu-cksum-applet cu-crypt64 cu-hash-blocks cu-md5
  cu-md5-bytes cu-md5sum cu-sha1-block cu-sha1sum cu-sum)
(import cu/hexdump cu-hd cu-hexdump cu-xxd)
(import cu/httpd cu-httpd hd-crypt-equal? hd-system-password hd-ugid)
(import cu/ifconfig cu-ifconfig if-ref if-req)
(import cu/inet inet-addr-host inet-addr-host6 inet-aton inet-dec inet-dotted
  inet-hex inet-hex8 inet-host-addr inet-int32 inet-ioctl inet-left inet-ntop6
  inet-ntop6-bytes inet-pton6! inet-resolve inet-rresolve inet-service
  inet-set! inet-sin! inet-socket inet-swap inet-words inet-zeros)
(import cu/inetd cu-inetd in-af in-bind in-c in-call in-count in-dontwait
  in-errtext in-exec in-lines in-now in-percent in-recvfrom in-reuse!
  in-sendto in-sockaddr6 in-strtou in-tokens-max in-zeroed tn-port)
(import cu/iostat cu-iostat io-time io-uname-line)
(import cu/ip ip-addr-of ip-addr-shown? ip-addr1 ip-align ip-attr ip-attrs
  ip-bytes ip-cstr ip-dev-index ip-die ip-die-usage ip-digit ip-dump
  ip-dump-read ip-filter ip-get ip-id ip-index-name ip-indexed ip-invarg
  ip-keyword ip-link-of ip-list ip-ll-addr ip-match? ip-name ip-names ip-next
  ip-ntoa ip-num ip-off ip-open ip-pad16 ip-prefix ip-put ip-run ip-say
  ip-scope-id ip-scope-name ip-scopes ip-sl ip-some)
(import cu/ip-main cu-ip cu-ipaddr cu-iplink)
(import cu/ipcalc cu-ipcalc)
(import cu/ipneigh cu-ipneigh ip-neigh)
(import cu/iproute cu-iproute ip-host-len ip-hz ip-r-attr ip-r-dst-len
  ip-r-family ip-r-src-len ip-r-type ip-route ip-rtn-id ip-rtn-name ip-tables)
(import cu/iprule cu-iprule ip-addr32 ip-dsfields ip-rule)
(import cu/ipset ip-add-link ip-address ip-attr! ip-buf ip-family! ip-flush
  ip-flush-batches ip-init-map ip-le ip-modify ip-pfx-bytes ip-prefix-in
  ip-req ip-req-bytes ip-rta ip-send-check ip-set ip-str-bytes ip-strtoul
  ip-talk ip-unsigned)
(import cu/iptunnel cu-iptunnel ip-tunnel)
(import cu/ls cu-ls ls-cell ls-user-cell)
(import cu/lsmod cu-lsmod)
(import cu/mime cu-makemime cu-reformime mm-b64 mm-ci= mm-getc mm-gets mm-in
  mm-source!)
(import cu/more cu-clear cu-more cu-reset more-typed)
(import cu/mpstat cu-mpstat)
(import cu/nameif cu-nameif)
(import cu/nc cu-nc cu-netcat nc-count)
(import cu/net cu-dial cu-dial-host cu-wget cu-whois ftp-code ftp-connect
  ftp-data-port ftp-fd ftp-final? ftp-line ftp-open! ftp-reply ftp-send
  wget-last-part wget-open-failure wget-pm-init! wget-pm-update! wget-times
  whois-after whois-trim)
(import cu/netstat cu-netstat)
(import cu/nmeter cu-nmeter nm-line nm-parse nm-sample)
(import cu/ntpd cu-ntpd nt-be-bytes nt-imin nt-raw nt-sha1-bytes nt-unhex
  nt-zeros)
(import cu/options cu-option-spec nc-flags nc-values)
(import cu/patch cu-patch)
(import cu/perm cu-basename-of cu-chgrp cu-chmod cu-chown cu-chown-number
  cu-df cu-link cu-mkfifo cu-mode-of cu-mode-valid? cu-octal->int cu-readlink
  cu-realpath cu-realpath-of cu-sync)
(import cu/ping cu-ping cu-ping6 pn-af6 pn-be16 pn-be16! pn-bind-device
  pn-byte pn-cmsg pn-div pn-dotted pn-family pn-fold pn-ms pn-now pn-number
  pn-resolve pn-setopt pn-sol-socket pn-sum)
(import cu/pmap cu-pmap)
(import cu/popmaildir cu-popmaildir)
(import cu/prims append bit-and bit-or bit-shl bit-shr bit-xor byte-at
  byte-len cal/ char->integer cu% cu& cu* cu+ cu- cu-as-run cu-b->s cu-cstr-at
  cu-dirname-of cu-dlopen cu-dlsym cu-dot? cu-err-label cu-fd-fields
  cu-file-read cu-heap-collect cu-hexs cu-int->ptr cu-int->str cu-last
  cu-lines cu-max-status cu-member-s? cu-mode-file-type cu-nth cu-nthrest
  cu-piece-bytes cu-ptr->str cu-ptr-call cu-ptr-ref cu-ptr-set! cu-ptr-word
  cu-rev cu-run-bytes cu-run-list cu-run-of cu-sig-ign cu-sighup cu-sigint
  cu-sigkill cu-sigterm cu-stat-get cu-stdin! cu-stdin-chunk! cu-stdin-fields!
  cu-stdin-moved cu-stdin-to-command! cu-str->ptr cu-string-type cu-sweep!
  cu-sweep-at cu-sweep-bytes cu-sweep-lines cu-sweep-steps cu-sweep-tick!
  cu-sweeps-cell cu-take cu-type-of cu-walk-worst cu-words-line cu/ cu< cu<<
  cu>> cvt date-now-unix file-chmod file-chown file-close file-copy file-dir?
  file-err-op file-err-sym file-err-text file-exists? file-lchown file-link
  file-list-dir file-lstat-file-type file-lstat-full file-lstat-wide
  file-mkdir file-mkfifo file-mounts file-open-append file-open-err
  file-open-excl file-open-or-err file-open-read file-open-update
  file-open-write file-open-wronly file-or-err file-read-all file-read-fd
  file-read-run file-read-to-end file-read-unsized file-readlink file-rename
  file-rmdir file-seek file-set-times file-stat file-stat-full file-stat-wide
  file-statfs-full file-symlink file-truncate file-unlink file-utimes
  file-write file-write-all file-write-field file-write-nuls file-write-random
  file-write-run filter gz-word-bytes host-args host-boot-time host-counters
  host-cpu host-cpus host-cwd host-disks host-exe host-files host-files-of
  host-holders host-interfaces host-interrupts host-load-centi host-load-fixed
  host-maps host-memory host-now host-process host-processes host-regions
  host-tasks host-threads host-uptime host-users host-utmp host-wait
  http-close http-head http-open http-read http-status hx-hex-digit hx-strtoul
  in-index-of integer->char length libc-strerror list->string load-centi
  ls-human map net-accept net-aton net-base64 net-close net-connect net-die
  net-listen net-listen-on net-peer net-recv-from-run net-recv-run net-resolve
  net-send net-send-run net-send-to-run net-shutdown net-sock-addr
  net-sockaddr net-sockaddr-read net-stdin-socket net-udp-bind net-udp-connect
  net-udp-open proc-run ps-div re-compile re-search reverse rng-int rng-make
  set-first! str-make-raw string-append string-concat string=? substring
  sys-chroot sys-close sys-cpu-count sys-dup2 sys-environ sys-exec
  sys-exec-or-err sys-exit sys-fork sys-fsync sys-getcwd sys-getegid
  sys-getenv sys-geteuid sys-getgid sys-getgroups sys-getpid sys-getuid
  sys-group-id sys-group-name sys-isatty sys-kill sys-nice sys-pipe sys-poll
  sys-setenv sys-signal sys-signals sys-sleep sys-sync sys-time-ms sys-umask
  sys-uname sys-unsetenv sys-user-group sys-user-groups sys-user-id
  sys-user-name sys-usleep sys-wait vec-build vec-make vec-ref vec-set!
  vm-dash-number wget-digits wget-div wget-err-text wget-find wget-index
  wget-last-index wget-lower wget-memv)
(import cu/procps cu-free cu-kill cu-killall cu-lsof cu-pgrep cu-pidof
  cu-pkill cu-ps cu-pwdx cu-uptime lsof-target pg-base pg-head ps-args
  ps-boot-line ps-four ps-free-text ps-free-unit ps-parse-o ps-printable
  ps-resolve! ps-sorted ps-stat ps-table ps-uptime-line)
(import cu/pscan cu-pscan)
(import cu/route cu-route rt-show4)
(import cu/runparts cu-run-parts)
(import cu/sendmail cu-sendmail sm-atoi sm-helper-check sm-helper-pid!
  sm-space?)
(import cu/session cu-flock cu-fsync cu-nologin cu-pipe-progress cu-setsid
  cu-ttysize hd-daemonize ss-call ss-flock ss-resolve!)
(import cu/sha256 cu-add32 cu-hex-digit cu-m32 cu-sha-pad cu-sha256
  cu-sha256sum cu-sum-applet cu-word-hex)
(import cu/sha3 cu-sha3sum)
(import cu/sha512 cu-sha384sum cu-sha512sum)
(import cu/signal fu-args pg-nsig pg-rt pg-signal-word pg-signum pg-strto
  ts-signal-number)
(import cu/sort cu-sort sort-fold)
(import cu/sslclient cu-ssl-client sc-copy sc-run-prog)
(import cu/sslserver cu-ssl-server)
(import cu/strings cu-range-number cu-strings-applet)
(import cu/sys2 cu-drop-last cu-env cu-false cu-printenv cu-sleep cu-true
  cu-which cu-xargs)
(import cu/sysctl cu-sysctl sy-trim)
(import cu/sysinfo cu-dnsdomainname cu-hostid cu-hostname cu-mesg cu-mknod
  cu-mountpoint cu-renice cu-ts si-digits? si-now)
(import cu/tar cu-tar cu-unsafe-prefix tar-all-pieces tar-copy-out! tar-field
  tar-fill! tar-find-str tar-last-slash tar-makedev tar-member? tar-min
  tar-mkdir tar-mknod tar-printable tar-reader tar-resolve! tar-skip!
  tar-str-bytes tar-verbose-line tar-why tc-block tc-sub-run tm-link tm-mode
  tm-name tm-size)
(import cu/tcpsvd cu-tcpsvd cu-udpsvd)
(import cu/telnet cu-telnet tn-run tn-str-bytes)
(import cu/telnetd cu-telnetd td-ptr->int)
(import cu/test cu-bracket cu-dbracket cu-test t-permitted?)
(import cu/text cu-basename cu-byte-in? cu-comm cu-delim-fields
  cu-delim-fields-said cu-dirname cu-each-run-said cu-each-said cu-enough
  cu-fd-chunks cu-file-pieces cu-first-unopened cu-fold-lines-said cu-fold-one
  cu-fold-pieces cu-fold-said cu-fold-stdin cu-gather-said cu-head cu-join
  cu-join-with cu-map-swept cu-merge cu-msort cu-newlines-from cu-num-prefix
  cu-pad-left cu-pad-right cu-pad-zero cu-pieces cu-pieces-past
  cu-print-fields cu-print-fields-to cu-print-lines cu-print-lines-to
  cu-put-each cu-read-error cu-read-run-said cu-read-said cu-run-from
  cu-run-join cu-run-nul? cu-run-part cu-run-slice cu-run-text cu-say cu-says
  cu-says-open cu-says-read cu-sleep-for cu-sleep-us cu-split-byte
  cu-stdin-pieces cu-str< cu-tail cu-tail-follow cu-tail-round cu-text-from
  cu-unmarked cu-wc cu-with-sources)
(import cu/text2 cu-echo cu-fold cu-oct->str cu-pad cu-paste cu-printf
  cu-rev-applet cu-seq cu-tac cu-tee)
(import cu/text3 cu-b64-decode-to cu-b64-put-end cu-b64-put-from cu-base64
  cu-dos2unix cu-expand cu-factor cu-list->vec cu-shuf cu-shuf-range cu-spaces
  cu-split cu-unexpand cu-unix2dos cu-vec->list cu-yes)
(import cu/text4 cu-nl cu-uniq)
(import cu/tftp cu-tftp cu-tftpd tftp-bytes)
(import cu/time cu-time)
(import cu/top cu-top top-drop top-duration-ms top-five top-load-line
  top-percent top-ppu top-scales-of top-shares top-stats! top-sweep-if-due!
  top-take)
(import cu/traceroute cu-traceroute cu-traceroute6)
(import cu/trcut cu-cut cu-tr)
(import cu/tree cu-tree)
(import cu/tsort cu-tsort ts-space?)
(import cu/tunctl cu-tunctl)
(import cu/unzip cu-unzip)
(import cu/vconfig cu-vconfig)
(import cu/vi cu-vi vi% vi& vi+ vi- vi-bsub vi-bundle-version vi-dim vi-in?
  vi-init-g! vi-init-text-buffer! vi-key-down vi-key-end vi-key-home
  vi-key-page-down vi-key-page-up vi-key-up vi-max vi-min vi-num-from
  vi-ptr-set! vi-sequences vi-str->ptr vi-typed vi/ vi<)
(import cu/vmstat cu-vmstat vm-five vm-fixed vm-four vm-get vm-rate vm-right
  vm-ticks vm-zip)
(import cu/walk cu-walk-names cu-walk-pair cu-walk-status)
(import cu/watch cu-watch)
(import cu/who cu-arch cu-chroot cu-groups cu-id cu-logname cu-nice cu-nproc
  cu-uname cu-uname-field cu-users cu-w cu-who cu-whoami)

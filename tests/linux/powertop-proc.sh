#!/bin/sh
# # x-coreutils -- POSIX coreutils on x-lang
#
# ## tests/linux/powertop-proc.sh -- a /proc for powertop's cases
#
# @description Mounts a tmpfs on /proc, in a mount namespace of the caller's own, filled from tests/fixtures/powertop, and starts what plays the kernel and the keyboard.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     sh tests/linux/powertop-proc.sh SET TIMER ACPI KEYS
#
# SET is the interrupts' fixture, small or big, or none for no interrupts
# file, nostat for no stat; TIMER is timer_stats: fifo (the kernel's,
# played: each sample stopped reads the fixture's), file (a file the writes
# land in) or dir (a write refused, as on a kernel since 4.11, where it is
# gone); ACPI yes or no for the processors' power files; KEYS how many keys
# are pressed.  Before each key the interrupts and the first processor's
# power file move on to the next sample; after the last the input ends.
# The keys are written to the FIFO /tmp/lx-ptop-in, which powertop is to
# read as its stdin; the helpers' pids are left in /tmp/lx-ptop-pids for
# the case to end.
set -e

FX="$(cd "$(dirname "$0")/../fixtures/powertop" && pwd)"
SET="$1" TIMER="$2" ACPI="$3" KEYS="$4"

mount -t tmpfs none /proc
[ "$SET" = nostat ] || cp "$FX/stat" /proc/stat
if [ "$SET" = big ]; then A=big.a B=big.b C=big.b; else A=interrupts.a B=interrupts.b C=interrupts.c; fi
[ "$SET" = none ] || cp "$FX/$A" /proc/interrupts
if [ "$ACPI" = yes ]; then
	mkdir -p /proc/acpi/processor/CPU0 /proc/acpi/processor/CPU1
	cp "$FX/power.a" /proc/acpi/processor/CPU0/power
	cp "$FX/power.a" /proc/acpi/processor/CPU1/power
fi
: > /tmp/lx-ptop-pids
case "$TIMER" in
fifo)
	mkfifo /proc/timer_stats
	# each "0" written after the first stops a sample, which the next open reads
	(
		z=0 s=0
		while :; do
			d=$(cat /proc/timer_stats)
			z=$((z + $(printf %s "$d" | tr -cd 0 | wc -c)))
			if [ $z -ge $((s + 2)) ]; then cat "$FX/timer_stats" > /proc/timer_stats; s=$((s + 1)); fi
		done
	) > /dev/null 2>&1 &
	echo $! >> /tmp/lx-ptop-pids ;;
file) cp "$FX/timer_stats" /proc/timer_stats ;;
dir) mkdir /proc/timer_stats ;;
esac
rm -f /tmp/lx-ptop-in
mkfifo /tmp/lx-ptop-in
(
	k=0
	while [ $k -lt "$KEYS" ]; do
		sleep 2
		if [ $k = 0 ]; then n=$B; else n=$C; fi
		cp "$FX/$n" /proc/interrupts
		[ "$ACPI" = no ] || cp "$FX/power.b" /proc/acpi/processor/CPU0/power
		printf x
		k=$((k + 1))
	done
	sleep 2
) > /tmp/lx-ptop-in 2> /dev/null &
echo $! >> /tmp/lx-ptop-pids

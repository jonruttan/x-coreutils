#!/bin/sh
# tests/card-vi.sh KEYS [LINE ...] -- type KEYS at vi over a file of the
# LINEs, for the rows of docs/vi-card.md.  X is the x under test.
#
# KEYS is printf's format: \033 is Escape, \r Return, \026 ^V.  vi edits a
# file holding each LINE as a line, in a window of 24 rows by 80 columns,
# with no $EXINIT and no ~/.exrc.  What is printed is the file as the keys
# left it, a | between its lines: the keys end by writing it, ZZ or :wq.
#
# vi takes an Escape as a key of its own only when no byte follows it within
# 50 ms.  So the typing starts once vi has drawn its screen, and pauses after
# each Escape.  HOME is a directory made here, and x keeps its state images
# where it kept them.  A vi still running after two minutes is ended.
d=$(mktemp -d) || exit 1
trap 'rm -rf "$d"' EXIT
keys=$1
shift
for line do printf '%s\n' "$line"; done > "$d/text"
: > "$d/screen"
# shellcheck disable=SC2059
type_keys() {
	until [ -s "$d/screen" ]; do sleep 0.1; done
	sleep 0.3
	rest=$1
	while :; do
		case $rest in
		*'\033'*)
			printf "${rest%%\\033*}\033"
			sleep 0.3
			rest=${rest#*\\033} ;;
		*)
			printf "$rest"
			break ;;
		esac
	done
}
(sleep 120; pkill -f "vi $d/text") > /dev/null 2>&1 &
watch=$!
cache=${XDG_CACHE_HOME:-$HOME/.cache}
type_keys "$keys" | env HOME="$d" XDG_CACHE_HOME="$cache" EXINIT= LINES=24 \
	COLUMNS=80 "${X:-x}" -l coreutils -- vi "$d/text" > "$d/screen" 2>&1
kill "$watch" 2> /dev/null
wait "$watch" 2> /dev/null
paste -s -d '|' "$d/text"

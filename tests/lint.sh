#!/bin/sh
# # x-coreutils -- the small tools, as applets
#
# ## tests/lint.sh -- shim onto the lang kit's linter
#
# @description Sources the platform's lint; vendors nothing.  --strict fails
#   on the advisory rules, which is how this bundle wants them.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
# A lang under languages/ is not covered by x-lang's `make lint-x` (which sweeps
# lib/ and apps/), so this shim runs the same linter over this bundle.
#
# Set X to point at a particular x; X_LANG_KIT overrides the kit.
set -e

BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"
X="${X:-x}"

KIT="${X_LANG_KIT:-$("$X" --share-dir)/tools/lang-kit}"

# A gate the platform cannot run yet skips; it does not fail the build. The kit
# linter is new, so no released x carries it, and hard-failing here would break
# `make check` on every existing x until a release lands. The notice names the
# missing file, and the day an x ships it the gate is hard everywhere with no
# edit here.
[ -f "$KIT/lint.sh" ] || {
	echo "x-coreutils: SKIPPING lint -- no $KIT/lint.sh in this x." >&2
	echo "x-coreutils: it arrives with the lang kit's linter; upgrade x to gate on it." >&2
	exit 0
}

# An x older than the release lang.xon names skips too, for the same reason:
# the fragments import platform libraries such a tree has no file for, and the
# linter preloads them, so the run dies per file on `include: cannot open` --
# which reads as a defect in this source rather than as a platform too old.
#
# Conservative on purpose.  Only a release that can be read AND is below the
# floor skips; an x whose release is unreadable runs the lint, so a version
# this cannot parse never silently disables the gate.
FLOOR=$(sed -n 's/^(requires-release "v\{0,1\}\([0-9.]*\)").*/\1/p' "$BUNDLE/lang.xon" | head -1)
HAVE=$("$X" --version 2>/dev/null |
	sed -n 's/.*library release v\{0,1\}\([0-9.]*\).*/\1/p' | head -1)
if [ -n "$FLOOR" ] && [ -n "$HAVE" ] && ! awk -v a="$HAVE" -v b="$FLOOR" 'BEGIN {
		na = split(a, have, "."); nb = split(b, want, ".")
		n = na > nb ? na : nb
		for (i = 1; i <= n; i++) {
			u = (i <= na ? have[i] + 0 : 0)
			v = (i <= nb ? want[i] + 0 : 0)
			if (u > v) exit 0
			if (u < v) exit 1
		}
		exit 0
	}'; then
	echo "x-coreutils: SKIPPING lint -- this x is $HAVE, lang.xon needs $FLOOR." >&2
	echo "x-coreutils: install a current x to gate on it." >&2
	exit 0
fi

# Every file, not the entry alone: the linter reads its targets as data
# and follows no import, so linting run.x would examine none of the
# modules.  Each cu/ file is a scoped module, or a file of one its own
# file includes, and the kit resolves a module's names in the module.
if [ $# -gt 0 ]; then
	BUNDLE="$BUNDLE" X="$X" sh "$KIT/lint.sh" --strict "$@"
else
	BUNDLE="$BUNDLE" X="$X" sh "$KIT/lint.sh" --strict \
		cu/*.x run.x tools/options-matrix.x docs/busybox-options.x
fi

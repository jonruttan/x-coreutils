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

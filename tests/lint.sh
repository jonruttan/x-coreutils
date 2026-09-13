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

# THE FRAGMENTS, not the assembled unit.  cu/base.x is nothing but
# include-once lines, and the linter reads its target as data -- it does
# not expand an include -- so linting base.x examines no definition at
# all and reports a clean bill for a bundle full of ladders.  The
# definitions are in the fragments, so the fragments are what gets
# linted.  What the fragments lack is each other's names: only base.x
# and prims.x carry a (provide ...), and the %cu-* names are shared
# across the whole rather than exported.  The kit's preload closes that
# by including the ASSEMBLER whole -- base.x, which pulls its fragments
# in the order the bundle really loads -- so a fragment is linted with
# the whole in scope, base.x's own un-exported top level included.
if [ $# -gt 0 ]; then
	BUNDLE="$BUNDLE" X="$X" sh "$KIT/lint.sh" --strict "$@"
else
	BUNDLE="$BUNDLE" X="$X" sh "$KIT/lint.sh" --strict \
		cu/*.x run.x tools/options-matrix.x docs/busybox-options.x
fi

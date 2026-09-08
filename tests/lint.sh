#!/bin/sh
# # x-coreutils -- the small tools, as applets
#
# ## tests/lint.sh -- shim onto the lang kit's linter
#
# @description Sources the PLATFORM's lint; vendors nothing.  --strict
#   fails on the advisory rules, which is how this bundle wants them.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
# THE BUNDLE WAS SWEPT BY NOTHING.  x-lang's `make lint-x` covers lib/
# and apps/; a lang under languages/ was covered by neither, so every
# rule the linter knows was advice this bundle never heard -- and it
# accumulated twenty-one `ladder` findings, nested if chains branching
# on one variable, all written after that rule shipped.
#
# Set X to point at a particular x; X_LANG_KIT overrides the kit.
set -e

BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"
X="${X:-x}"

KIT="${X_LANG_KIT:-$("$X" --share-dir)/tools/lang-kit}"
[ -f "$KIT/lint.sh" ] || {
	echo "x-coreutils: no linter in the lang kit at $KIT -- upgrade x" >&2
	exit 2
}

# THE FRAGMENTS, not the assembled unit.  cu/base.x is nothing but
# include-once lines, and the linter reads its target as data -- it does
# not expand an include -- so linting base.x examines no definition at
# all and reports a clean bill for a bundle full of ladders.  The
# definitions are in the fragments, so the fragments are what gets
# linted.  What the fragments lack is each other's names: only base.x
# and prims.x carry a (provide ...), and the %cu-* names are shared
# across the whole rather than exported.  The kit's preload closes
# that -- a sibling with no provide is include-once'd exactly as its own
# module includes it, so a fragment is linted with the whole in scope.
if [ $# -gt 0 ]; then
	BUNDLE="$BUNDLE" X="$X" sh "$KIT/lint.sh" --strict "$@"
else
	BUNDLE="$BUNDLE" X="$X" sh "$KIT/lint.sh" --strict \
		cu/*.x run.x tools/options-matrix.x docs/busybox-options.x
fi

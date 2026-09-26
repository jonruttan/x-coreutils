#!/bin/sh
# # x-coreutils -- POSIX coreutils on x-lang
#
# ## tests/spec-runner.sh -- the bundle's runner
#
# @description Sources the platform's spec runner; vendors nothing.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
# No path reaches into an x-lang source tree; everything comes from x itself:
# --share-dir says which tree x reads from (repo root in a checkout, share/x
# when installed) and --engine-path says where the engine is.
#
# Set X to point at a particular x; otherwise the one on PATH is used.
set -e

BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"
X="${X:-x}"

command -v "$X" >/dev/null 2>&1 || {
	echo "x-coreutils: no x on PATH.  Set X=/path/to/x.sh and retry." >&2
	exit 1
}

X_ROOT="$("$X" --share-dir)"
X_BIN="${X_BIN:-$("$X" --engine-path)}"

# The platform runner locates its harness relative to the engine binary, which
# sits beside tests/ only in a checkout; a sourced script cannot portably find
# its own path, so the caller sets this.
SPEC_RUNNER_DIR="$X_ROOT/tests"
export SPEC_RUNNER_DIR

# The harness is GENERATED, never committed: it embeds two absolute paths
# that are facts of this machine, not of the bundle.
sh "$BUNDLE/tests/gen-harness.sh" "$X_ROOT" "$BUNDLE"

LANG_LIB="$BUNDLE/tests/lib/harness.gen.x"
# SPEC_PATH is env-overridable so a single spec file can be run in isolation.
SPEC_PATH="${SPEC_PATH:-$BUNDLE/tests/specs}"

# Each spec file boots from a state image of the harness where the platform
# can write one, rather than reading the platform and the bundle from source:
# tools/dev/image-build.sh images a child base that loaded the harness, keyed
# on the harness, the platform's lib/, its engine and cu/, so an edit to any
# of them writes a new one and a current one is loaded as it is.  The writer
# lives in a checkout; an installed tree boots from source and says so.
# IMG=0 boots from source anyway: the control, for a failure that the image
# is suspected of.
if [ "${IMG:-1}" != 0 ]; then
	_builder="$X_ROOT/tools/dev/image-build.sh"
	if [ -f "$_builder" ]; then
		if X_BIN="$X_BIN" X_SH="$(command -v "$X")" sh "$_builder" \
			"$LANG_LIB" "$BUNDLE/tests/lib/.images" "$BUNDLE/cu"; then
			X_IMG_DIR="$BUNDLE/tests/lib/.images"
			export X_IMG_DIR
		else
			echo "x-coreutils: no state image (image-build exit $?) -- the suite boots from source" >&2
		fi
	else
		echo "x-coreutils: no image writer at $_builder -- the suite boots from source" >&2
	fi
fi

# The seam collect is on. It was off for x-lang#568/#572 (where the per-seam
# collect killed the x-ash and x-python suites), both closed by v0.12.0; leaving
# it off then had a cost, since x has no automatic GC and a file's allocations
# accumulate across its snippets until the ceiling. Still overridable, so a
# suite that suspects the collect can measure rather than inherit the knob.
export SPEC_SEAM_COLLECT="${SPEC_SEAM_COLLECT:-1}"

. "$X_ROOT/tests/spec-runner.sh"

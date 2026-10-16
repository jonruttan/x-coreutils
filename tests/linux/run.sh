#!/bin/sh
# # x-coreutils -- POSIX coreutils on x-lang
#
# ## tests/linux/run.sh -- the Linux leg
#
# @description Runs tests/linux/specs as root in a privileged Linux container.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
# The image is built from tests/linux/Containerfile at the x-lang release
# lang.xon declares, once a release and Containerfile.  The bundle is mounted, so
# an edit runs at once.  ENGINE names the container engine, podman by
# default, docker in CI; SPEC names one spec file to run alone.
set -e

BUNDLE="$(cd "$(dirname "$0")/../.." && pwd)"
ENGINE="${ENGINE:-podman}"
REF="$(sed -n 's/^(requires-release "\(.*\)")$/\1/p' "$BUNDLE/lang.xon")"
[ -n "$REF" ] || { echo "x-coreutils: lang.xon declares no release" >&2; exit 2; }
# the tag names the release and the Containerfile, so an edit to either builds anew
TAG="x-coreutils-linux:$REF-$(cksum < "$BUNDLE/tests/linux/Containerfile" | cut -d" " -f1)"

"$ENGINE" image inspect "$TAG" >/dev/null 2>&1 ||
	"$ENGINE" build -f "$BUNDLE/tests/linux/Containerfile" --build-arg X_LANG_REF="$REF" \
		-t "$TAG" "$BUNDLE/tests/linux"

exec "$ENGINE" run --rm --privileged -v "$BUNDLE:/x-coreutils" \
	-e SPEC_PATH=/x-coreutils/tests/linux/specs "$TAG" \
	sh tests/spec-runner.sh ${SPEC:+tests/linux/specs/$SPEC}

#!/usr/bin/env bash
# Self-test for render.sh, run where render.sh runs (it needs agent-browser and ffmpeg). Each case works on a
# throwaway copy of the repository:
#   1. a page that asks for something outside loopback fails the render, naming the request;
#   2. two renders of the same inputs give the same decoded frames (ffmpeg -f framemd5).
# Usage, from anywhere in the repository: scripts/media/render-selftest.sh [plugin, default ruling-page]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; P="${1:-ruling-page}"; T="$(mktemp -d)"; FAILS=0
trap 'rm -rf "${T:?}"' EXIT
copy() { rm -rf "${T:?}/$1"; mkdir -p "$T/$1"; (cd "$ROOT" && tar --exclude=.git --exclude=.worktrees -cf - .) | (cd "$T/$1" && tar -xf -); }
frames() { local f; (cd "$1/docs/media" && for f in $(find . -name '*.webp' -o -name '*.gif' | sort); do
  printf '%s ' "$f"; ffmpeg -v error -i "$f" -f framemd5 - | grep -v '^#' | md5sum | cut -d' ' -f1; done); }

copy remote
sed -i.bak 's#<body>#<body><img src="https://example.com/selftest.png" alt="">#' "$T/remote/docs/media/banner/banner.html"
out="$("$T/remote/scripts/media/render.sh" banner 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'outside loopback' && printf '%s' "$out" | grep -q 'example.com/selftest.png'; then
  echo "PASS: a remote request fails the render (exit $rc) and is named"
else echo "FAIL: a remote request did not fail the render (exit $rc): $out"; FAILS=$((FAILS+1)); fi

copy one; copy two
for c in one two; do "$T/$c/scripts/media/render.sh" "$P" >/dev/null 2>&1 || { echo "FAIL: render $c of $P failed"; FAILS=$((FAILS+1)); }; done
if [ "$(frames "$T/one")" = "$(frames "$T/two")" ]; then echo "PASS: two renders of $P give the same decoded frames"
else echo "FAIL: two renders of $P differ"; diff <(frames "$T/one") <(frames "$T/two"); FAILS=$((FAILS+1)); fi
echo "render-selftest: $FAILS failure(s)"; [ "$FAILS" -eq 0 ]

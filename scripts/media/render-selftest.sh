#!/usr/bin/env bash
# Self-test for render.sh, run where render.sh runs (it needs agent-browser and ffmpeg). Each case works on a
# throwaway copy of the repository:
#   1. a page that asks for something outside the render's own loopback address fails the render, naming the
#      request, and the request never arrives (a listener on localhost counts what reaches it);
#   2. a page that draws the current time renders to the same pixels twice, a few seconds apart (the fixed clock);
#   3. two renders of the same inputs give the same decoded frames (ffmpeg -f framemd5).
# Usage, from anywhere in the repository: scripts/media/render-selftest.sh [plugin, default ruling-page]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; P="${1:-ruling-page}"; T="$(mktemp -d)"; FAILS=0; LSN=""
trap '[ -n "$LSN" ] && kill "$LSN" 2>/dev/null; rm -rf "${T:?}"' EXIT
copy() { rm -rf "${T:?}/$1"; mkdir -p "$T/$1"; (cd "$ROOT" && tar --exclude=.git --exclude=.worktrees -cf - .) | (cd "$T/$1" && tar -xf -); }
# frames DIR: one line per picture, "<path> <frame count> <md5 of its decoded frames>"; prints FRAMES-FAILED and
# returns 1 if any picture does not decode or has no frames, so a broken decoder can never compare equal.
frames() { local f fm n bad=0; while IFS= read -r f; do
    if ! fm="$(ffmpeg -v error -i "$1/docs/media/$f" -f framemd5 - 2>/dev/null)"; then echo "FRAMES-FAILED $f"; bad=1; continue; fi
    n="$(printf '%s\n' "$fm" | grep -vc '^#')"
    [ "$n" -gt 0 ] || { echo "FRAMES-FAILED $f (no frames)"; bad=1; continue; }
    printf '%s %s %s\n' "$f" "$n" "$(printf '%s\n' "$fm" | grep -v '^#' | md5sum | cut -d' ' -f1)"
  done < <(cd "$1/docs/media" && find . -name '*.webp' -o -name '*.gif' | sort); return $bad; }
same() { # dir dir: both decode and give the same frames
  local a b; a="$(frames "$1")" || { echo "$a" | grep FRAMES-FAILED; return 1; }
  b="$(frames "$2")" || { echo "$b" | grep FRAMES-FAILED; return 1; }
  [ "$a" = "$b" ]; }
pass() { echo "PASS: $1"; }; fail() { echo "FAIL: $1"; FAILS=$((FAILS+1)); }

# 1. containment: a listener on localhost (not the render's 127.0.0.1 origin) logs every request it gets
PORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')"
mkdir -p "$T/listen"; : > "$T/listen.log"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$T/listen" 2>> "$T/listen.log" >/dev/null & LSN=$!
sleep 1
copy remote
sed -i.bak "s#<body>#<body><img src=\"http://localhost:$PORT/selftest.png\" alt=\"\">#" "$T/remote/docs/media/banner/banner.html"
out="$("$T/remote/scripts/media/render.sh" banner 2>&1)"; rc=$?
hits="$(grep -c 'selftest.png' "$T/listen.log" || true)"
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'outside loopback' && printf '%s' "$out" | grep -q "localhost:$PORT/selftest.png"; then
  pass "a request outside the render's loopback origin fails the render (exit $rc) and is named"
else fail "a request outside loopback did not fail the render (exit $rc): $out"; fi
[ "$hits" = 0 ] && pass "the request never reached its host (0 requests at the listener)" || fail "the request reached its host ($hits)"
kill "$LSN" 2>/dev/null; LSN=""

# 2. the fixed clock: a page that prints the time, rendered twice a few seconds apart
copy clock1
sed -i.bak 's#</body>#<p id="selftest-clock" style="position:fixed;top:4px;left:4px;z-index:9;margin:0;color:\#fff;background:\#000;font:20px monospace"></p><script>document.getElementById("selftest-clock").textContent = new Date().toISOString() + " " + Date.now();</script></body>#' \
  "$T/clock1/docs/media/banner/banner.html"
rm -rf "${T:?}/clock2"; cp -R "$T/clock1" "$T/clock2"
"$T/clock1/scripts/media/render.sh" banner >/dev/null 2>&1 || fail "clock render 1 failed"
sleep 3
"$T/clock2/scripts/media/render.sh" banner >/dev/null 2>&1 || fail "clock render 2 failed"
same "$T/clock1" "$T/clock2" && pass "a page that draws the time renders the same pixels 3 s apart" \
  || fail "a page that draws the time rendered differently 3 s apart (the clock is not fixed)"

# 2b. the comparison itself: a picture that does not decode never compares equal
copy broken; printf 'not a picture' > "$T/broken/docs/media/banner.webp"; cp -R "$T/broken" "$T/broken2"
same "$T/broken" "$T/broken2" >/dev/null && fail "two undecodable pictures compared equal" \
  || pass "an undecodable picture fails the comparison"

# 3. determinism of a real picture
copy one; copy two
for c in one two; do "$T/$c/scripts/media/render.sh" "$P" >/dev/null 2>&1 || fail "render $c of $P failed"; done
same "$T/one" "$T/two" && pass "two renders of $P give the same decoded frames" \
  || { fail "two renders of $P differ"; diff <(frames "$T/one") <(frames "$T/two"); }
echo "render-selftest: $FAILS failure(s)"; [ "$FAILS" -eq 0 ]

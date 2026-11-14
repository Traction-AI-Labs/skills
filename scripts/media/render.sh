#!/usr/bin/env bash
# Renders the README's pictures from the made-up inputs in docs/examples/ and the plugins' own templates, then
# records each one in docs/media/manifest.json (python3 -I scripts/readme/build.py --record <name>).
#
# Usage, from anywhere in the repository:  scripts/media/render.sh <name>|all
#   <name> is ruling-page, reading-page, call-prep, gauntlet, doc-gauntlet or banner.
# Needs agent-browser, ffmpeg (with libwebp), python3, and uv for reading-page's build script. Headless; the pages
# load nothing from outside the loopback address, and the render fails if one asks.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$ROOT/scripts/media"
ALL=(ruling-page reading-page call-prep gauntlet doc-gauntlet banner)
case "${1:-}" in
  all) WANT=("${ALL[@]}") ;;
  ruling-page|reading-page|call-prep|gauntlet|doc-gauntlet|banner) WANT=("$1") ;;
  *) echo "usage: scripts/media/render.sh <ruling-page|reading-page|call-prep|gauntlet|doc-gauntlet|banner|all>" >&2; exit 2 ;;
esac
for tool in agent-browser ffmpeg python3; do command -v "$tool" >/dev/null || { echo "render.sh: needs $tool" >&2; exit 1; }; done
wants() { local w; for w in "${WANT[@]}"; do [ "$w" = "$1" ] && return 0; done; return 1; }

WORK="$(mktemp -d)"; S="skills-render-$$"; SRV=""
cleanup() {
  [ -n "$SRV" ] && kill "$SRV" 2>/dev/null || true
  agent-browser --session "$S" close >/dev/null 2>&1 || true
  rm -rf "${WORK:?}"
}
trap cleanup EXIT

mkdir -p "$WORK/banner" "$WORK/fonts"
cp "$ROOT"/docs/media/banner/* "$WORK/banner/"
cp "$ROOT"/docs/media/fonts/*.woff2 "$WORK/fonts/"
python3 -I "$HERE/fill.py" "$ROOT" "$WORK" >/dev/null
if wants reading-page; then
  command -v uv >/dev/null || { echo "render.sh: reading-page needs uv" >&2; exit 1; }
  uv run -q "$ROOT/plugins/reading-page/skills/reading-page/scripts/build.py" "$WORK/reading.md" "$WORK/reading.html" >/dev/null
fi
if wants call-prep; then
  out="$(cd "$ROOT/plugins/call-prep/skills/call-prep" && python3 scripts/check_prep.py "$WORK/call-prep.html")"
  [ "${out%%[[:space:]]*}" = ok ] || { echo "render.sh: check_prep.py did not print ok: $out" >&2; exit 1; }
fi

PORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$WORK" >/dev/null 2>&1 & SRV=$!
for _ in $(seq 50); do python3 -c "import socket;socket.create_connection(('127.0.0.1',$PORT),1)" 2>/dev/null && break; sleep 0.1; done
U="http://127.0.0.1:$PORT"
ab() { agent-browser --session "$S" "$@" >/dev/null; }
# A fixed clock and empty storage, so two renders of the same inputs give the same pixels; loopback only.
agent-browser --session "$S" --init-script "$HERE/freeze.js" --allowed-domains 127.0.0.1 open "$U/banner/banner.html" >/dev/null
shot() { # page width height theme out [script to run before the shot]
  ab set viewport "$2" "$3"; ab set media "$4"; ab open "$U/$1"; ab wait --load networkidle; ab wait 400
  if [ -n "${6:-}" ]; then ab eval "$6"; ab wait 300; fi
  ab screenshot "$WORK/$5"
}
webp() { ffmpeg -loglevel error -y -i "$1" -c:v libwebp -quality 82 -compression_level 6 -map_metadata -1 "$2"; }
M="$ROOT/docs/media"
TOCARDS='window.scrollTo(0, document.getElementById("tp-cards").getBoundingClientRect().top + scrollY - 150)'

page() { # plugin page-file [script]
  mkdir -p "$M/$1"
  for th in light dark; do
    shot "$2" 1100 760 "$th" "$1-$th.png" "${3:-}"
    shot "$2" 390 844 "$th" "$1-phone-$th.png" "${3:-}"
    webp "$WORK/$1-$th.png" "$M/$1/$th.webp"
    webp "$WORK/$1-phone-$th.png" "$M/$1/phone-$th.webp"
  done
}
terminal_frames() { # plugin; desktop 1100x560 and phone 390x1150, one frame per typed command
  local n k; n="$(cat "$WORK/terminal-$1.steps")"
  for k in $(seq 0 "$n"); do
    shot "terminal-$1.html?step=$k" 1100 560 dark "term-$1-$k.png"
    shot "terminal-$1.html?step=$k" 390 1150 dark "termp-$1-$k.png"
  done
}

wants ruling-page && page ruling-page ruling.html "$TOCARDS"
wants reading-page && page reading-page reading.html
wants call-prep && page call-prep call-prep.html
if wants doc-gauntlet; then
  mkdir -p "$M/doc-gauntlet"; n="$(cat "$WORK/terminal-doc-gauntlet.steps")"
  shot "terminal-doc-gauntlet.html?step=$n" 1100 560 dark doc-final.png
  shot "terminal-doc-gauntlet.html?step=$n" 390 1150 dark doc-final-phone.png
  webp "$WORK/doc-final.png" "$M/doc-gauntlet/round.webp"
  webp "$WORK/doc-final-phone.png" "$M/doc-gauntlet/round-phone.webp"
fi
if wants gauntlet; then
  mkdir -p "$M/gauntlet"; terminal_frames gauntlet; n="$(cat "$WORK/terminal-gauntlet.steps")"
  webp "$WORK/term-gauntlet-$n.png" "$M/gauntlet/poster.webp"
  webp "$WORK/termp-gauntlet-$n.png" "$M/gauntlet/poster-phone.webp"
  # each frame held 1.4 s and the finished round 4 s; the concat list repeats the last file, as the demuxer needs
  : > "$WORK/frames.txt"
  for k in $(seq 0 "$n"); do d=1.4; [ "$k" = "$n" ] && d=4; printf "file '%s'\nduration %s\n" "term-gauntlet-$k.png" "$d" >> "$WORK/frames.txt"; done
  printf "file '%s'\n" "term-gauntlet-$n.png" >> "$WORK/frames.txt"
  sed 's/term-gauntlet-/termp-gauntlet-/' "$WORK/frames.txt" > "$WORK/frames-phone.txt"
  PAL="split[a][b];[a]palettegen=max_colors=64:stats_mode=diff[p];[b][p]paletteuse=dither=none"
  ( cd "$WORK" && ffmpeg -loglevel error -y -f concat -safe 0 -i frames.txt -vf "fps=10,scale=880:-1:flags=lanczos,$PAL" \
      -loop 0 -map_metadata -1 "$M/gauntlet/round.gif" )
  ( cd "$WORK" && ffmpeg -loglevel error -y -f concat -safe 0 -i frames-phone.txt -vf "fps=10,$PAL" \
      -loop 0 -map_metadata -1 "$M/gauntlet/round-phone.gif" )
fi
if wants banner; then
  shot banner/banner.html 1280 220 dark banner.png
  shot "banner/banner.html?phone" 640 400 dark banner-phone.png
  webp "$WORK/banner.png" "$M/banner.webp"
  webp "$WORK/banner-phone.png" "$M/banner-phone.webp"
fi

outside="$(agent-browser --session "$S" network requests 2>/dev/null | grep -E 'https?://' | grep -v -E "https?://127\.0\.0\.1:$PORT/" || true)"
if [ -n "$outside" ]; then echo "render.sh: a page asked for something outside loopback:" >&2; echo "$outside" | head -5 >&2; exit 1; fi
for w in "${WANT[@]}"; do python3 -I "$ROOT/scripts/readme/build.py" --record "$w"; done

#!/usr/bin/env bash
# Refreshes the banner's fonts in docs/media/fonts/ from Google Fonts (SIL Open Font Licence 1.1), with each
# family's licence from the google/fonts repository. Run it only to update the fonts; render.sh uses the committed
# copies. Usage, from anywhere in the repository: scripts/media/fetch-fonts.sh
set -euo pipefail
OUT="$(cd "$(dirname "$0")/../.." && pwd)/docs/media/fonts"; mkdir -p "$OUT"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Safari/537.36"
get() { # css2 family query, file
  local url
  url="$(curl -fsS -A "$UA" "https://fonts.googleapis.com/css2?family=$1&display=swap" | grep -o 'https://fonts.gstatic.com[^)]*\.woff2' | tail -1)"
  curl -fsS -A "$UA" -o "$OUT/$2" "$url"
}
get "Spectral:wght@300" spectral-300.woff2
get "Spectral:ital,wght@1,300" spectral-300-italic.woff2
get "Inter:wght@400" inter-400.woff2
get "JetBrains+Mono:wght@400" jetbrains-mono-400.woff2
for f in spectral inter jetbrainsmono; do
  curl -fsS -o "$OUT/OFL-$f.txt" "https://raw.githubusercontent.com/google/fonts/main/ofl/$f/OFL.txt"
done
ls -la "$OUT"

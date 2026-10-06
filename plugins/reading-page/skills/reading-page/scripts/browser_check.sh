#!/usr/bin/env bash
# Browser check for a built reading page (skill: reading-page).
#
#   browser_check.sh <page.html>
#
# Runs agent-browser headless, twice, in fresh sessions:
#   JavaScript off (Chrome --blink-settings=scriptEnabled=false), 390 x 844:
#     <html> keeps class no-js; the contents list is visible and holds a link for every
#     article h2/h3; the phone bar and the tool buttons are hidden.
#   JavaScript on, 390 x 844:
#     <html> has class js (not no-js); exactly one contents list; every "#" link resolves to an
#     element; clicking a percent-encoded "#" link navigates; ids are unique; the phone bar
#     opens the contents; scrollWidth is 390; no page errors and no console errors.
#
# Always run it on the overflow fixture too (long URLs and hashes in prose, lists, callouts,
# table cards, marks and footnotes, plus a percent-encoded link to a Unicode heading):
#   uv run scripts/build.py scripts/fixtures/long-tokens.md /tmp/long-tokens.html
#   bash scripts/browser_check.sh /tmp/long-tokens.html
# Exits 0 only when every check passes; prints one line per check.
#
# Headless browsers are heavy: if the reader's own machine is busy, run the check on another machine
# (copy the page and this script there, then run it against the copy).
# Override the binary with AGENT_BROWSER=/path/to/agent-browser.

set -u

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  echo "usage: $0 <built-page.html>" >&2
  exit 2
fi

AB="${AGENT_BROWSER:-agent-browser}"
if ! command -v "$AB" >/dev/null 2>&1; then
  echo "FAIL: agent-browser not found (set AGENT_BROWSER)" >&2
  exit 2
fi

case "$1" in
  /*) PAGE="$1" ;;
  *) PAGE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")" ;;
esac
URL="file://$PAGE"
S_NOJS="reading-page-nojs-$$"
S_JS="reading-page-js-$$"
FAILED=0

fail() { echo "FAIL: $*"; FAILED=1; }
ok() { echo "ok:   $*"; }

cleanup() {
  "$AB" --session "$S_NOJS" close >/dev/null 2>&1
  "$AB" --session "$S_JS" close >/dev/null 2>&1
}
trap cleanup EXIT

# run_js <session> <label> <js>: the JS must evaluate to a string starting RPCHECK_PASS, or
# RPCHECK_FAIL followed by the reasons. Sent base64-encoded so no quoting survives the shell.
run_js() {
  _b64="$(printf '%s' "$3" | base64 | tr -d '\n')"
  if ! _out="$("$AB" --session "$1" eval -b "$_b64" 2>&1)"; then
    fail "$2: eval failed: $_out"
    return
  fi
  case "$_out" in
    *RPCHECK_PASS*) ok "$2" ;;
    *) fail "$2: $_out" ;;
  esac
}

# no_entries <label> <json> <mode>: mode "errors" fails on any entry; mode "console" fails on
# entries whose type or level is error. Falls back to a text check when python3 is missing.
no_entries() {
  if command -v python3 >/dev/null 2>&1; then
    _res="$(printf '%s' "$2" | python3 -c '
import json, sys
mode = sys.argv[1]
try:
    doc = json.load(sys.stdin)
except Exception as e:
    print("unparseable output: %s" % e); sys.exit(1)
if isinstance(doc, dict) and doc.get("success") is False:
    print("command failed: %s" % doc.get("error")); sys.exit(1)
found = []
def walk(x):
    if isinstance(x, list):
        for e in x:
            if isinstance(e, dict) and any(k in e for k in ("text", "message", "type", "level")):
                kind = str(e.get("type") or e.get("level") or "").lower()
                if mode == "errors" or kind == "error":
                    found.append(str(e.get("text") or e.get("message") or e)[:200])
            elif isinstance(e, str):
                if mode == "errors" and e.strip():
                    found.append(e[:200])
            else:
                walk(e)
    elif isinstance(x, dict):
        for v in x.values():
            walk(v)
walk(doc.get("data", doc) if isinstance(doc, dict) else doc)
if found:
    print(" | ".join(found)); sys.exit(1)
' "$3" 2>&1)"
    if [ $? -eq 0 ]; then ok "$1"; else fail "$1: $_res"; fi
  else
    case "$2" in
      *'"error"'*|*Error*|*error:*) fail "$1 (no python3, text check): $2" ;;
      *) ok "$1 (no python3, text check)" ;;
    esac
  fi
}

# ---------- JavaScript off ----------

JS_NOJS='(function () {
  var d = document, r = [];
  var cls = d.documentElement.className;
  if (!/\bno-js\b/.test(cls)) r.push("html class is \"" + cls + "\", so page scripts ran");
  var bar = d.querySelector(".bar");
  if (!bar || getComputedStyle(bar).display !== "none") r.push("phone bar is visible");
  var tools = d.querySelector(".tools");
  if (tools && getComputedStyle(tools).display !== "none") r.push("tool buttons are visible");
  var rail = d.querySelector(".rail"), cs = rail && getComputedStyle(rail);
  if (!rail || cs.display === "none" || cs.visibility !== "visible" || parseFloat(cs.opacity) < 1)
    r.push("contents rail is hidden");
  var links = d.querySelectorAll("#toc ol a"), heads = d.querySelectorAll("article h2[id], article h3[id]");
  if (!links.length) r.push("contents list is empty");
  if (links.length !== heads.length) r.push("contents has " + links.length + " links for " + heads.length + " headings");
  for (var i = 0; i < links.length; i++) {
    var b = links[i].getBoundingClientRect();
    if (b.width === 0 || b.height === 0) { r.push("contents link " + (i + 1) + " has no box"); break; }
    if (i < heads.length && links[i].getAttribute("href") !== "#" + heads[i].id) { r.push("contents link " + (i + 1) + " points at " + links[i].getAttribute("href")); break; }
  }
  return r.length ? "RPCHECK_FAIL " + r.join("; ") : "RPCHECK_PASS";
})()'

echo "== JavaScript off, 390 wide: $URL"
if "$AB" --session "$S_NOJS" --args "--blink-settings=scriptEnabled=false" open "$URL" >/dev/null 2>&1; then
  if "$AB" --session "$S_NOJS" set viewport 390 844 >/dev/null 2>&1; then
    run_js "$S_NOJS" "no-js: contents visible and complete, bar and tools hidden" "$JS_NOJS"
  else
    fail "no-js: could not set viewport"
  fi
else
  fail "no-js: could not open $URL"
fi
"$AB" --session "$S_NOJS" close >/dev/null 2>&1

# ---------- JavaScript on ----------

JS_ON='(function () {
  var d = document, r = [];
  var cls = d.documentElement.className;
  if (!/\bjs\b/.test(cls) || /\bno-js\b/.test(cls)) r.push("html class is \"" + cls + "\", expected js");
  var lists = d.querySelectorAll("#toc ol");
  if (lists.length !== 1) r.push(lists.length + " contents lists, expected 1");
  var seen = {}, dup = [];
  Array.prototype.forEach.call(d.querySelectorAll("[id]"), function (e) { if (seen[e.id]) dup.push(e.id); seen[e.id] = 1; });
  if (dup.length) r.push("duplicate ids: " + dup.join(", "));
  var bad = [];
  Array.prototype.forEach.call(d.querySelectorAll("a[href^=\"#\"]"), function (a) {
    var h = a.getAttribute("href"); if (h.length < 2) return;
    var id; try { id = decodeURIComponent(h.slice(1)); } catch (e) { id = h.slice(1); }
    if (!d.getElementById(id)) bad.push(h);
  });
  if (bad.length) r.push("unresolved # links: " + bad.join(", "));
  Array.prototype.forEach.call(d.querySelectorAll("article a[href^=\"#\"]"), function (a) {
    var h = a.getAttribute("href"); if (h.indexOf("%") < 0) return;
    var want; try { want = decodeURIComponent(h.slice(1)); } catch (e) { return; }
    history.replaceState(null, "", location.pathname + location.search);
    a.click();
    var got; try { got = decodeURIComponent(location.hash.slice(1)); } catch (e) { got = location.hash; }
    if (got !== want) r.push("percent-encoded link " + h + " did not navigate (hash now \"" + location.hash + "\")");
  });
  var btn = d.querySelector(".bar-btn");
  if (!btn || getComputedStyle(d.querySelector(".bar")).display === "none") r.push("phone bar is not shown with JavaScript on");
  else { btn.click(); if (!d.body.classList.contains("toc-open")) r.push("phone bar does not open the contents"); btn.click(); }
  var sw = d.documentElement.scrollWidth;
  if (sw !== 390) r.push("scrollWidth is " + sw + ", expected 390");
  return r.length ? "RPCHECK_FAIL " + r.join("; ") : "RPCHECK_PASS";
})()'

echo "== JavaScript on, 390 wide: $URL"
if "$AB" --session "$S_JS" open "$URL" >/dev/null 2>&1; then
  if "$AB" --session "$S_JS" set viewport 390 844 >/dev/null 2>&1; then
    run_js "$S_JS" "js: class, one contents list, # links, unique ids, phone bar, no sideways overflow" "$JS_ON"
  else
    fail "js: could not set viewport"
  fi
  no_entries "js: no page errors" "$("$AB" --session "$S_JS" errors --json 2>&1)" errors
  no_entries "js: no console errors" "$("$AB" --session "$S_JS" console --json 2>&1)" console
else
  fail "js: could not open $URL"
fi

if [ "$FAILED" -ne 0 ]; then
  echo "browser_check: FAILED"
  exit 1
fi
echo "browser_check: all checks passed"
exit 0

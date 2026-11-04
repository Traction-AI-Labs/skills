#!/usr/bin/env bash
# Browser check for a built reading page (skill: reading-page).
#
#   browser_check.sh <page.html>
#   browser_check.sh --fit-js     prints the fit check on its own, for another checker to run, then exits
#
# Runs agent-browser headless, three times, in fresh sessions:
#   JavaScript off (Chrome --blink-settings=scriptEnabled=false), 390 x 844:
#     <html> keeps class no-js; the contents list is visible and holds a link for every
#     article h2/h3; the phone bar and the tool buttons are hidden.
#   JavaScript on, 390 x 844:
#     <html> has class js (not no-js); exactly one contents list; every "#" link resolves to an
#     element; clicking a percent-encoded "#" link navigates; ids are unique; the phone bar
#     opens the contents; scrollWidth is 390; no page errors and no console errors.
#   JavaScript on, loaded at 1440 x 900 and resized to 390 x 844 without a reload:
#     nothing covers the title or standfirst, neither at the moment the window narrows nor
#     once it settles; then the 390-wide checks above pass on the resized page.
#   Fit and readability, in each of the three runs (at 390 with scripts off and on, at 1440, and at 390 after the
#   resize): no text spills the box laid out for it, no text touches (under 2px) or overlaps a neighbouring box, and at
#   480 wide or narrower no text a reader must read is under 11px.
#
# Always run it on the overflow fixture too (long URLs and hashes in prose, lists, callouts,
# table cards, marks and footnotes, plus a percent-encoded link to a Unicode heading):
#   uv run scripts/build.py scripts/fixtures/long-tokens.md /tmp/long-tokens.html
#   bash scripts/browser_check.sh /tmp/long-tokens.html
# Prints one line per check: ok, FAIL (a fault in the page) or INCONCLUSIVE (the capture broke: the browser could not
# open the page, set the width or run a check, or the page had not loaded or showed no text to judge; this says nothing
# about the design either way). Exits 0 only when every check passes; 1 on any FAIL; otherwise 2 when any check was
# inconclusive. Run an inconclusive check again; never read it as a pass or as a design fault.
#
# Headless browsers are heavy: if the reader's own machine is busy, run the check on another machine
# (copy the page and this script there, then run it against the copy).
# Override the binary with AGENT_BROWSER=/path/to/agent-browser.

set -u

# The fit and readability check, also printed on its own by --fit-js, so a second checker never drifts from it. Returns
# {fails, inconclusive, info}.
IFS= read -r -d '' FIT_CORE <<'FITJS' || true
function () {
  // Fit and readability at the current width (detectors after Stageshow's layout-core.mjs and
  // film-checks.mjs, benjitaylor/skills 80205740, MIT): text never spills the box it sits in, text never touches or
  // overlaps a neighbouring box, and at phone width (480 or narrower) no text a reader must read is under MINPX
  // (11px: the templates' smallest text, their pill labels, measured 11.5px).
  // Returns {fails, inconclusive, info}: a page that has not finished loading, or one with no visible text to
  // judge, is inconclusive (a broken capture) and is not measured, never a design fault and never a pass.
  var MINPX = 11, d = document, r = { fails: [], inconclusive: [], info: {} };
  if (d.readyState !== "complete") { r.inconclusive.push("page not loaded (readyState " + d.readyState + ")"); return r; }
  var name = function (e) {
    var c = typeof e.className === "string" && e.className.trim() ? "." + e.className.trim().split(/\s+/)[0] : "";
    return e.tagName.toLowerCase() + (e.id ? "#" + e.id : c);
  };
  var said = function (e, k) { return "\"" + e.textContent.trim().slice(0, k).replace(/RPCHECK_/g, "RPCHECK-") + "\""; };
  var clips = function (cs) { return cs.overflowX !== "visible" || cs.overflowY !== "visible"; };
  var shown = function (e) {
    for (var a = e; a; a = a.parentElement) {
      var cs = getComputedStyle(a);
      if (cs.display === "none" || cs.visibility === "hidden" || parseFloat(cs.opacity) < 0.05) return false;
      if (cs.clip && cs.clip !== "auto") return false;  // visually hidden on purpose
      if (cs.clipPath && cs.clipPath !== "none" && /inset\(50%|inset\(100%/.test(cs.clipPath)) return false;
    }
    // Inside a closed <details>, only its summary is drawn.
    for (var dd = e.closest("details:not([open])"); dd; dd = dd.parentElement && dd.parentElement.closest("details:not([open])")) {
      var sm = dd.querySelector(":scope > summary");
      if (!sm || !sm.contains(e)) return false;
    }
    var b = e.getBoundingClientRect();
    return b.width >= 2 && b.height >= 2;
  };
  // The rectangles of an element's own text, one text node at a time (never a range across its child elements),
  // cut to what its clipping ancestors let show.
  var textRects = function (e) {
    var out = [];
    [].forEach.call(e.childNodes, function (c) {
      if (c.nodeType !== 3 || !c.textContent.trim()) return;
      var g = d.createRange(); g.selectNodeContents(c);
      [].forEach.call(g.getClientRects(), function (x) { if (x.width > 0.5 && x.height > 0.5) out.push({ left: x.left, right: x.right, top: x.top, bottom: x.bottom, height: x.height }); });
    });
    for (var a = e; a && a !== d.documentElement; a = a.parentElement) {
      var cs = getComputedStyle(a);
      if (!clips(cs)) continue;
      var cb = a.getBoundingClientRect();
      out = out.map(function (x) { return { left: Math.max(x.left, cb.left), right: Math.min(x.right, cb.right), top: Math.max(x.top, cb.top), bottom: Math.min(x.bottom, cb.bottom), height: x.height }; })
        .filter(function (x) { return x.right - x.left > 0.5 && x.bottom - x.top > 0.5; });
    }
    return out;
  };
  var texts = 0, spills = [], touch = [], tiny = [], small = null, seenPair = {};
  var all = d.body ? d.body.querySelectorAll("*") : [];
  var size = function (n, ncs) {
    var scale = n.offsetWidth ? n.getBoundingClientRect().width / n.offsetWidth : 1;
    return parseFloat(ncs.fontSize) * (scale || 1);
  };
  var readable = function (n, ncs, label) {
    var fpx = size(n, ncs);
    if (!small || fpx < small.px) small = { px: Math.round(fpx * 10) / 10, el: name(n) + " " + label };
    if (innerWidth <= 480 && fpx < MINPX - 0.01) tiny.push(name(n) + " " + label + " is " + Math.round(fpx * 10) / 10 + "px");
  };
  for (var i = 0; i < all.length; i++) {
    var n = all[i];
    if (/^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE)$/.test(n.tagName) || n.closest("svg")) continue;
    // A field's own words (its value or placeholder) must be readable too.
    if (/^(INPUT|TEXTAREA|SELECT)$/.test(n.tagName) && shown(n)) {
      var fv = (n.value || n.placeholder || "").trim();
      if (fv.length > 1 && !/^(hidden|checkbox|radio|range|color|file)$/.test(n.type)) readable(n, getComputedStyle(n), "\"" + fv.slice(0, 20) + "\"");
      continue;
    }
    var rs = textRects(n);
    if (!rs.length || !shown(n)) continue;
    texts++;
    var ncs = getComputedStyle(n);
    // 1. Spill: a line of its text runs past the edges of a box laid out for it: each block it sits in, up to the
    //    first that clips or scrolls (which cuts it, measured above) or an overlay (absolute or fixed), which has
    //    its own box. A negative text-indent (a hung quote) may pass the left edge by that much.
    var indent = Math.max(0, -parseFloat(ncs.textIndent) || 0) + 2;
    for (var bx = n; bx && bx !== d.body && bx !== d.documentElement; bx = bx.parentElement) {
      var bcs = getComputedStyle(bx);
      if (bcs.display === "inline" || bcs.display === "contents") continue;
      var bb = bx.getBoundingClientRect();
      if (bb.width <= 2) break;
      var right = 0, down = 0, left = 0;
      for (var k = 0; k < rs.length; k++) { right = Math.max(right, rs[k].right - bb.right); down = Math.max(down, rs[k].bottom - bb.bottom); left = Math.max(left, bb.left - rs[k].left); }
      var where = right > 2 ? Math.round(right) + "px past the right edge" : left > indent ? Math.round(left) + "px past the left edge" : down > 2 ? Math.round(down) + "px below the bottom" : "";
      if (where) { spills.push(name(n) + " " + said(n, 24) + " runs " + where + " of " + name(bx)); break; }
      if (clips(bcs) || /^(absolute|fixed)$/.test(bcs.position)) break;
    }
    // 2. Touching: text on one line with a neighbouring box (a sibling, or a child box of its own) less than 2px
    //    away, or overlapping a neighbour's box. Inline neighbours are part of the sentence; overlays (absolute,
    //    fixed or transformed) are laid out on their own.
    var hood = [];
    // Text that is itself an overlay (a copy button pinned over a code block) sits over its siblings by design.
    if (/^(absolute|fixed)$/.test(ncs.position)) hood = null;
    if (hood && n.parentElement) [].forEach.call(n.parentElement.children, function (c) { if (c !== n) hood.push(c); });
    if (hood) [].forEach.call(n.children, function (c) { hood.push(c); });
    for (var j = 0; hood && j < hood.length; j++) {
      var c = hood[j], cc = getComputedStyle(c);
      if (cc.display === "inline" || cc.display === "contents" || /^(absolute|fixed)$/.test(cc.position) || !shown(c)) continue;
      if (cc.transform !== "none") continue;
      // A box with no surface of its own (no fill, border or shadow) is judged by its words, a surface by its box.
      var b = c.getBoundingClientRect();
      var surf = !/^(transparent|rgba\(0, 0, 0, 0\))$/.test(cc.backgroundColor) || cc.backgroundImage !== "none" || cc.boxShadow !== "none" ||
        ["Top", "Right", "Bottom", "Left"].some(function (s) { return parseFloat(cc["border" + s + "Width"]) > 0 && cc["border" + s + "Style"] !== "none"; });
      if (!surf && !/^(IMG|svg|CANVAS|INPUT|TEXTAREA|SELECT|BUTTON)$/.test(c.tagName)) {
        if (!c.textContent.trim()) continue;
        var cr = d.createRange(); cr.selectNodeContents(c); b = cr.getBoundingClientRect();
      }
      if (b.width < 4 || b.height < 4 || c.contains(n)) continue;
      var hit = "";
      for (var q = 0; q < rs.length && !hit; q++) {
        var x = rs[q];
        var ov = Math.min(x.bottom, b.bottom) - Math.max(x.top, b.top), oh = Math.min(x.right, b.right) - Math.max(x.left, b.left);
        if (ov > 1 && oh > 1) { hit = "overlaps"; break; }
        if (!(ov > 0.5 * Math.min(x.height, b.height))) continue;
        var gap = b.left >= x.right - 0.5 ? b.left - x.right : x.left >= b.right - 0.5 ? x.left - b.right : -1;
        if (gap >= 0 && gap < 2) hit = Math.round(gap * 10) / 10 + "px from";
      }
      if (hit) {
        var key = name(n) + "|" + name(c);
        if (!seenPair[key]) { seenPair[key] = 1; touch.push(name(n) + " " + said(n, 18) + " " + hit + " " + name(c)); }
      }
    }
    // 3. Tiny: the drawn size of words a reader must read (two or more characters).
    if (n.textContent.trim().length > 1) readable(n, ncs, said(n, 20));
  }
  if (!texts) r.inconclusive.push("no visible text to judge");
  var more = function (a, k) { return a.slice(0, k).join("; ") + (a.length > k ? " (+" + (a.length - k) + " more)" : ""); };
  if (spills.length) r.fails.push("text spills its box: " + more(spills, 4));
  if (touch.length) r.fails.push("text touches a neighbour: " + more(touch, 4));
  if (tiny.length) r.fails.push("text under " + MINPX + "px at " + innerWidth + " wide: " + more(tiny, 4));
  r.info = { width: innerWidth, texts: texts, smallest: small };
  return r;
}
FITJS
if [ "${1:-}" = "--fit-js" ]; then
  printf '(() => JSON.stringify((%s)()))()\n' "$FIT_CORE"
  exit 0
fi

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  echo "usage: $0 <built-page.html>" >&2
  exit 2
fi

AB="${AGENT_BROWSER:-agent-browser}"
if ! command -v "$AB" >/dev/null 2>&1; then
  echo "INCONCLUSIVE: agent-browser not found (set AGENT_BROWSER); nothing was checked" >&2
  exit 2
fi

case "$1" in
  /*) PAGE="$1" ;;
  *) PAGE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")" ;;
esac
URL="file://$PAGE"
S_NOJS="reading-page-nojs-$$"
S_JS="reading-page-js-$$"
S_RS="reading-page-resize-$$"
FAILED=0
INCON=0

fail() { echo "FAIL: $*"; FAILED=1; }
inconclusive() { echo "INCONCLUSIVE: $*"; INCON=1; }
ok() { echo "ok:   $*"; }

cleanup() {
  "$AB" --session "$S_NOJS" close >/dev/null 2>&1
  "$AB" --session "$S_JS" close >/dev/null 2>&1
  "$AB" --session "$S_RS" close >/dev/null 2>&1
}
trap cleanup EXIT

# run_js <session> <label> <js>: the JS must evaluate to a string starting RPCHECK_PASS, RPCHECK_FAIL followed by
# the reasons, or RPCHECK_INCONCLUSIVE followed by why it could not judge. Sent base64-encoded so no quoting survives
# the shell. An eval that fails, or returns none of the three, is a broken capture: inconclusive.
run_js() {
  _b64="$(printf '%s' "$3" | base64 | tr -d '\n')"
  if ! _out="$("$AB" --session "$1" eval -b "$_b64" 2>&1)"; then
    inconclusive "$2: eval failed: $_out"
    return
  fi
  # The verdict is the result's first word, never a match anywhere in it (page text quoted in a reason may hold one).
  _first="$(printf '%s' "$_out" | sed -n 's/^[[:space:]"]*\(RPCHECK_[A-Z]*\).*/\1/p' | head -n 1)"
  case "$_first" in
    RPCHECK_PASS) ok "$2" ;;
    RPCHECK_FAIL) fail "$2: $_out" ;;
    RPCHECK_INCONCLUSIVE) inconclusive "$2: $_out" ;;
    *) inconclusive "$2: no result: $_out" ;;
  esac
}

# The fit check in run_js's form.
JS_FIT="(function () { var r = ($FIT_CORE)(), i = JSON.stringify(r.info);
  if (r.fails.length) return 'RPCHECK_FAIL ' + r.fails.join('; ') + ' ' + i;
  if (r.inconclusive.length) return 'RPCHECK_INCONCLUSIVE ' + r.inconclusive.join('; ') + ' ' + i;
  return 'RPCHECK_PASS ' + i; })()"

# no_entries <label> <json> <mode>: mode "errors" fails on any entry; mode "console" fails on
# entries whose type or level is error; output it cannot read (the browser command failed) is inconclusive. Falls
# back to a text check when python3 is missing.
no_entries() {
  if command -v python3 >/dev/null 2>&1; then
    _res="$(printf '%s' "$2" | python3 -c '
import json, sys
mode = sys.argv[1]
try:
    doc = json.load(sys.stdin)
except Exception as e:
    print("unparseable output: %s" % e); sys.exit(2)
if isinstance(doc, dict) and doc.get("success") is False:
    print("command failed: %s" % doc.get("error")); sys.exit(2)
if doc is None or doc == {} or not isinstance(doc, (dict, list)):
    print("no entries list in the output: %s" % str(doc)[:100]); sys.exit(2)
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
    _rc=$?
    if [ "$_rc" -eq 0 ]; then ok "$1"; elif [ "$_rc" -eq 2 ]; then inconclusive "$1: $_res"; else fail "$1: $_res"; fi
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
    run_js "$S_NOJS" "no-js: text fits its boxes, touches nothing, none too small at 390" "$JS_FIT"
  else
    inconclusive "no-js: could not set viewport"
  fi
else
  inconclusive "no-js: could not open $URL"
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
    run_js "$S_JS" "js: text fits its boxes, touches nothing, none too small at 390" "$JS_FIT"
  else
    inconclusive "js: could not set viewport"
  fi
  no_entries "js: no page errors" "$("$AB" --session "$S_JS" errors --json 2>&1)" errors
  no_entries "js: no console errors" "$("$AB" --session "$S_JS" console --json 2>&1)" console
else
  inconclusive "js: could not open $URL"
fi
"$AB" --session "$S_JS" close >/dev/null 2>&1

# ---------- Resized from 1440 to 390 wide without a reload ----------

# At 1440 wide: defines rpCovered (what, if anything, sits over the title and standfirst) and
# records what it finds on every resize that lands in the phone layout with the contents
# closed, before that frame paints. A headless browser may render no frame between commands, so the resize
# event can still be pending when JS_RESIZED runs; its own read covers that case.
JS_ARM='(function () {
  var d = document, bar = d.querySelector(".bar");
  if (!bar) return "RPCHECK_FAIL no phone bar";
  window.rpCovered = function () {
    var out = [];
    // The title must be there to probe, or the check would pass on nothing; a page with no intro has no standfirst.
    [[".masthead h1", "title", true], [".standfirst", "standfirst", false]].forEach(function (p) {
      var el = d.querySelector(p[0]);
      if (!el) { if (p[2]) out.push("no " + p[1] + " (" + p[0] + ") to probe"); return; }
      var b = el.getBoundingClientRect(), y = b.top + Math.min(b.height / 2, 20);
      if (!b.height || y < 0 || y > window.innerHeight) { if (p[2]) out.push(p[1] + " has no visible box to probe"); return; }
      var hit = d.elementFromPoint(b.left + b.width / 2, y);
      if (hit && !el.contains(hit)) out.push(p[1] + " under " + (hit.closest(".rail") ? "the contents rail" : hit.tagName.toLowerCase()));
    });
    return out.join(", ");
  };
  window.rpResize = [];
  window.addEventListener("resize", function () {
    if (getComputedStyle(bar).display === "none" || d.body.classList.contains("toc-open")) return;
    var s = window.rpCovered(); if (s && window.rpResize.indexOf(s) < 0) window.rpResize.push(s);
  });
  if (getComputedStyle(bar).display !== "none") return "RPCHECK_FAIL phone bar is shown at 1440 wide";
  var now = window.rpCovered();
  return now ? "RPCHECK_FAIL at 1440 wide: " + now : "RPCHECK_PASS";
})()'

JS_RESIZED='(function () {
  if (!window.rpCovered) return "RPCHECK_FAIL page reloaded after the 1440-wide check";
  var r = window.rpResize.map(function (s) { return "as the window narrowed: " + s; });
  var now = window.rpCovered();
  if (now) r.push("after the resize: " + now);
  return r.length ? "RPCHECK_FAIL " + r.join("; ") : "RPCHECK_PASS";
})()'

echo "== JavaScript on, 1440 wide resized to 390 without a reload: $URL"
if "$AB" --session "$S_RS" open "$URL" >/dev/null 2>&1 && "$AB" --session "$S_RS" set viewport 1440 900 >/dev/null 2>&1; then
  run_js "$S_RS" "resize: desktop layout at 1440 wide, title and standfirst clear" "$JS_ARM"
  run_js "$S_RS" "resize: text fits its boxes and touches nothing at 1440" "$JS_FIT"
  if "$AB" --session "$S_RS" set viewport 390 844 >/dev/null 2>&1 && "$AB" --session "$S_RS" wait 500 >/dev/null 2>&1; then
    run_js "$S_RS" "resize: title and standfirst stay clear as the window narrows and after" "$JS_RESIZED"
    run_js "$S_RS" "resize: class, one contents list, # links, unique ids, phone bar, no sideways overflow" "$JS_ON"
    run_js "$S_RS" "resize: text fits its boxes, touches nothing, none too small at 390 after the resize" "$JS_FIT"
  else
    inconclusive "resize: could not resize to 390 x 844"
  fi
  no_entries "resize: no page errors" "$("$AB" --session "$S_RS" errors --json 2>&1)" errors
  no_entries "resize: no console errors" "$("$AB" --session "$S_RS" console --json 2>&1)" console
else
  inconclusive "resize: could not open $URL at 1440 x 900"
fi

if [ "$FAILED" -ne 0 ]; then
  echo "browser_check: FAILED"
  exit 1
fi
if [ "$INCON" -ne 0 ]; then
  echo "browser_check: INCONCLUSIVE (the capture broke; nothing above is a pass or a design fault: run it again)"
  exit 2
fi
echo "browser_check: all checks passed"
exit 0

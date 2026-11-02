"""No one-sided stripes in the house pages: show state with a fill, a full outline or a label, never an accent down one side.

    python3 -I edges.py <page.html> [...]

Reads every CSS rule in each page's <style> blocks, and every style="" attribute, so states that are not on
screen when a browser check runs (the current beat, an answered card, the active contents item) are covered too.
Exits 1 and prints file:line, selector and reason for each of these:

  side     any left or right border: border-left, border-right, border-inline(-start/-end), or their
           -width / -color / -style longhands, unless it is set to 0 or none; or a border-width,
           border-style or border-color shorthand whose four sides differ (one side drawn, thicker or in
           another colour)
  inset    a box-shadow offset towards one edge: inset with an offset (inset 3px 0 0 ...), or any shadow
           with an offset and no blur (0 1px 0 ...); a full inset outline (inset 0 0 0 1px) is fine
  bar      a ::before or ::after filled with a background and 6px or thinner (width or inline-size,
           height or block-size), positioned or not; or a linear-gradient with a hard stop 12px or less
           from an edge (a painted stripe)
  topbar   a top or bottom border thicker than 1px on a filled or rounded shape (a stripe moved to
           another side), as a longhand or a border-width shorthand; plain 1px dividers and heading rules
           on unfilled blocks are fine

Small glyphs drawn with borders (ticks, chevrons, 14px or less both ways) are left alone.
"""
import re
import sys

SIDE = re.compile(r"^border-(left|right|inline|inline-start|inline-end)(-width|-color|-style)?$")
TOPB = re.compile(r"^border-(top|bottom|block|block-start|block-end)(-width)?$")


def px(v):
    m = re.search(r"(-?\d*\.?\d+)px", v)
    return float(m.group(1)) if m else None


def blank_comments(t):
    return re.sub(r"/\*[\s\S]*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)), t)


def split_top(v):
    out, depth, cur = [], 0, ""
    for ch in v:
        depth += ch == "("
        depth -= ch == ")"
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    return out + [cur]


def decls(body):
    d = []
    for part in body.split(";"):
        if ":" in part:
            k, v = part.split(":", 1)
            d.append((k.strip().lower(), v.strip().lower()))
    return d


def off(v):
    return v in ("0", "0px", "none", "0 none", "none 0") or re.fullmatch(r"0(px)?\s+(none|solid|dashed)?.*", v) is not None


def four(v):
    """A border-width or border-style value as top, right, bottom, left (None if it is not 1 to 4 words)."""
    p = v.replace("!important", "").split()
    if not 1 <= len(p) <= 4:
        return None
    if len(p) == 1:
        return p * 4
    if len(p) == 2:
        return [p[0], p[1], p[0], p[1]]
    if len(p) == 3:
        return [p[0], p[1], p[2], p[1]]
    return p


def words(v):
    """Split a value on spaces outside brackets: "rgb(1, 2, 3) red" is two words."""
    out, depth, cur = [], 0, ""
    for ch in v.replace("!important", "").strip():
        depth += ch == "("
        depth -= ch == ")"
        if ch.isspace() and depth == 0:
            if cur:
                out.append(cur)
            cur = ""
        else:
            cur += ch
    return out + ([cur] if cur else [])


def drawn(k, x):
    if k == "border-color":
        return x not in ("transparent",)
    if k == "border-style":
        return x not in ("none", "hidden")
    return x in ("thin", "medium", "thick") or (px(x) or 0) > 0


def is_shaped(d):
    return any(k in ("background", "background-color") and v not in ("none", "transparent") for k, v in d) or any(k == "border-radius" for k, _ in d)


def check_block(sel, body, shaped_sels=frozenset()):
    d = decls(body)
    get = {k: v for k, v in d}
    w, h = px(get.get("width", get.get("inline-size", ""))), px(get.get("height", get.get("block-size", "")))
    glyph = w is not None and h is not None and w <= 14 and h <= 14
    filled = any(k in ("background", "background-color") and v not in ("none", "transparent") for k, v in d)
    # A shape is filled or rounded in this rule or in any other rule for the same selector.
    shaped = filled or "border-radius" in get or any(x.strip() in shaped_sels for x in sel.split(","))
    found = []
    for k, v in d:
        if SIDE.match(k) and not glyph and not off(v):
            found.append("side: %s: %s" % (k, v))
        if TOPB.match(k) and not glyph and shaped and (px(v) or 0) > 1:
            found.append("topbar: %s: %s on a filled or rounded shape" % (k, v))
        if k in ("border-width", "border-style", "border-color") and not glyph:
            s = four(" ".join(words(v))) if k != "border-color" else (lambda w: four(" ".join(w)) if 1 <= len(w) <= 4 else None)(words(v))
            if s and len(set(s)) > 1:
                lit = [drawn(k, x) for x in s]
                if (lit[1] or lit[3]) and not all(lit):
                    found.append("side: %s: %s draws one side only" % (k, v))
                elif all(lit):
                    found.append("side: %s: %s draws one side %s" % (k, v, "in another colour" if k == "border-color" else "differently"))
                elif k == "border-width" and shaped and max(px(s[0]) or 0, px(s[2]) or 0) > 1:
                    found.append("topbar: %s: %s on a filled or rounded shape" % (k, v))
        if k == "box-shadow" or k.startswith("--") and "shadow" in k:
            for sh in split_top(v):
                bare = re.sub(r"[a-z-]+\([^)]*\)", " ", sh.replace("inset", " "))
                nums = [float(n) for n in re.findall(r"(?<![\w.#-])(-?\d*\.?\d+)(?:px)?(?![\w%])", bare)]
                if len(nums) >= 2 and (nums[0] != 0 or nums[1] != 0) and ("inset" in sh or len(nums) < 3 or nums[2] == 0):
                    found.append("inset: %s %s" % (k, sh.strip()))
        if k in ("background", "background-image") and "linear-gradient" in v:
            if any(0 < float(n) <= 12 for n in re.findall(r"(\d*\.?\d+)px", v)):
                found.append("bar: %s: %s paints a stripe" % (k, v))
    if re.search(r"::?(before|after)\b", sel) and filled and not glyph:
        if (w is not None and w <= 6) or (h is not None and h <= 6):
            found.append("bar: a %spx %s pseudo-element" % (w if w is not None and w <= 6 else h, "wide" if w is not None and w <= 6 else "tall"))
    return found


def scan(path):
    text = open(path, encoding="utf-8").read()
    bad = []
    blocks = []
    for m in re.finditer(r"<style[^>]*>([\s\S]*?)</style>", text):
        css, base = blank_comments(m.group(1)), m.start(1)
        for r in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
            blocks.append((" ".join(r.group(1).split()), r.group(2), base + r.start(2)))
    shaped_sels = frozenset(x.strip() for sel, body, _ in blocks if is_shaped(decls(body)) for x in sel.split(","))
    for sel, body, at in blocks:
        for f in check_block(sel, body, shaped_sels):
            bad.append("%s:%d %s -> %s" % (path, text.count("\n", 0, at) + 1, sel[-70:], f))
    for m in re.finditer(r'\sstyle="([^"]*)"', text):
        for f in check_block("[style]", m.group(1)):
            bad.append("%s:%d style attribute -> %s" % (path, text.count("\n", 0, m.start()) + 1, f))
    return bad


def main(paths):
    bad = [b for p in paths for b in scan(p)]
    for b in bad:
        print(b)
    print("%d one-sided edges in %d pages" % (len(bad), len(paths)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

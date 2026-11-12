#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "markdown-it-py==3.0.0",
#   "mdurl==0.1.2",
#   "linkify-it-py==2.0.3",
#   "uc-micro-py==1.0.3",
#   "mdit-py-plugins==0.4.2",
# ]
# ///
"""Build a reading page (skill: reading-page) from a markdown file.

    uv run <skill-dir>/scripts/build.py report.md [report.html]
        [--title T] [--date YYYY-MM-DD] [--author A] [--status S] [--template PATH]

Output defaults to the input path with .html. Mapping:
  - A leading H1 -> page title (always consumed; --title or front matter title wins over its
    text). A leading "Date: YYYY-MM-DD." sentence in the first paragraph moves into the header;
    the rest of that first paragraph becomes the standfirst. Everything else before the first H2
    opens the article.
  - Optional front matter (--- key: value ---) supplies title, date, author, status.
  - Page state: front matter status: live | reference | replaced | partly-replaced puts a banner above
    the title saying whether the page needs the reader. live needs what_you_do; replaced and partly-replaced need
    replaced_by (the replacement's .html, never a .md) and replaced_on, and take replaced_by_title and why;
    partly-replaced needs still_stands (section numbers or title starts, comma-separated); every section, folded
    ones such as Sources included, gets a "Still stands" or "Replaced" pill. Any other status
    value is the free-text status label, as before.
  - Raw HTML in the markdown is escaped and shown as text; only http(s), mailto, relative and
    in-page links are emitted as links (javascript:, data:, vbscript:, file: are not).
  - H2 -> a section and a contents entry; H3 -> an indented contents entry.
  - H2 named Recommendation / Bottom line / Summary / TL;DR / Verdict / Answer -> its first
    paragraph becomes the lead "bottom line" box.
  - H2 named Sources / Evidence / References / Appendix / Method(ology) / Notes -> folded section.
  - A paragraph opening with a bold label ending in ":" (e.g. **Main risks:**) becomes a callout
    when the label names a recommendation, risk, decision or note; a list directly after it joins
    the callout.
  - Blockquote alerts: > [!RECOMMENDATION] [!RISK] [!DECISION] [!NOTE] [!VERIFIED] [!INFERRED]
    [!BOTTOMLINE] (GitHub's [!TIP] [!WARNING] [!IMPORTANT] [!CAUTION] map too).
  - A paragraph that is only a short bold label (e.g. **Authz model.**) -> an H3. A bold sentence
    (**Do not ship before Friday.**) stays a paragraph; see bold_only().
  - [V], [V, source], [V: source], [I], [I, source] -> verified / inferred marks (never inside
    code or attribute values).
  - In-page links written GitHub-style (#1-options, #risk-1 for a repeated heading) resolve to
    the heading they name.
  - Images: a local file beside the markdown is embedded as a data: URI; a remote image never
    loads (its alt text and URL show as text); a missing file shows its alt text.
  - The contents list is written into the page, so it reads without JavaScript.
  - Footnotes ([^1] in text, [^1]: ... definitions) -> superscript numbers linking to a Notes
    section at the end, each note with a back-link.
  - Tables -> styled tables, sortable at four or more rows. Code fences -> blocks with copy.
  - Bare URLs are linked; external links open in a new tab.
"""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import html
import re
import sys
import urllib.parse
from pathlib import Path

from markdown_it import MarkdownIt
from mdit_py_plugins.footnote import footnote_plugin

SKILL_DIR = Path(__file__).resolve().parent.parent
DEFAULT_TEMPLATE = SKILL_DIR / "references" / "template.html"

LEAD_HEADS = re.compile(r"^(recommendation|recommendations|bottom line|summary|executive summary|tl;?dr|verdict|answer|the answer|short answer)$", re.I)
FOLD_HEADS = re.compile(r"^(sources|source list|evidence|references|appendix.*|method|methodology|notes|raw notes|working notes|bibliography)$", re.I)

CALLOUT_LABELS = [
    ("decision", re.compile(r"decision|needs? (your|the reader|the approver\b|\w+'s (go|ruling|call|sign-?off|decision|input|answer|ok)\b)|for you to|ask of you|open question|to decide|your call", re.I)),
    ("risk", re.compile(r"risk|caveat|concern|watch out|danger|gotcha|warning|downside", re.I)),
    ("rec", re.compile(r"recommend|bottom line|smallest version|verdict|next step|what to do|proposal|the plan|do this", re.I)),
    ("note", re.compile(r"^note|when .* would|alternative|aside|context|background", re.I)),
]
ALERTS = {
    "RECOMMENDATION": ("rec", "Recommendation"), "TIP": ("rec", "Tip"),
    "RISK": ("risk", "Risk"), "WARNING": ("risk", "Warning"), "CAUTION": ("risk", "Caution"),
    "DECISION": ("decision", "Decision needed"), "IMPORTANT": ("decision", "Important"),
    "NOTE": ("note", "Note"), "VERIFIED": ("verified", "Verified"), "INFERRED": ("inferred", "Inferred"),
    "BOTTOMLINE": ("lead", "Bottom line"),
}

# html False: raw HTML in report text (<script>, <img onerror>, a stray <details> or <!--) is
# escaped and shown as text, never run or allowed to swallow the rest of the page.
MD = MarkdownIt("commonmark", {"linkify": True, "typographer": False, "html": False}).enable(["table", "strikethrough", "linkify"])
MD.linkify.set({"fuzzy_link": False})  # link only URLs with a scheme or www., never "DAIR.AI"
# Footnotes: without the plugin "[^1]: https://..." is swallowed as a link reference definition.
MD.use(footnote_plugin)
# Captions are plain numbers: "1", also for a second reference to note 1 (the plugin says "[1:1]").
MD.add_render_rule("footnote_caption", lambda self, tokens, idx, options, env: str(tokens[idx].meta["id"] + 1))
MD.add_render_rule("footnote_block_open", lambda self, tokens, idx, options, env: '<ol class="footnotes-list">\n')
MD.add_render_rule("footnote_block_close", lambda self, tokens, idx, options, env: "</ol>\n")

SAFE_URL = re.compile(r"^(https?:|mailto:|#|/|\./|\.\./|[^:/?#]+(?:[/?#]|$))", re.I)


def validate_link(url: str) -> bool:
    """Allow http(s), mailto, in-page and relative links; refuse javascript:, data:, file: and the rest.

    A refused [text](url) stays literal text, so nothing unsafe is ever emitted as a live link."""
    u = re.sub(r"[\x00-\x20]", "", url)
    return bool(SAFE_URL.match(u))


MD.validateLink = validate_link

IMAGE_TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif",
               ".webp": "image/webp", ".svg": "image/svg+xml", ".avif": "image/avif"}


def local_image(base: str | None, src: str) -> Path | None:
    """The real file an image reference names, only if it sits inside the markdown's own folder.

    Absolute paths, ../ escapes and symlinks pointing outside the folder all return None, so no
    private file elsewhere on disk can be embedded into a page that gets committed."""
    if not base:
        return None
    rel = urllib.parse.unquote(src.split("#")[0].split("?")[0])
    if not rel or rel.startswith(("/", "\\")) or re.match(r"^[a-zA-Z]:", rel):
        return None
    root = Path(base).resolve()
    real = (root / rel).resolve()  # follows every symlink
    try:
        real.relative_to(root)
    except ValueError:
        return None
    return real


def render_image(self, tokens, idx, options, env):
    """Keep the page self-contained and offline.

    Local image inside the markdown's folder -> embedded data: URI (see local_image). Remote image -> never loaded: its alt
    text and URL show as text. Missing or unsupported file -> its alt text."""
    tok = tokens[idx]
    src = tok.attrGet("src") or ""
    alt = self.renderInlineAsText(tok.children or [], options, env).strip()
    if re.match(r"^([a-z][a-z0-9+.-]*:|//)", src, re.I):
        return (f'<span class="img-off">Image not loaded: {esc(alt or "image")} '
                f'(<a href="{esc(src)}">{esc(src)}</a>)</span>')
    path = local_image(env.get("_base"), src)
    mime = IMAGE_TYPES.get(path.suffix.lower()) if path else None
    if mime and path.is_file():
        data = base64.b64encode(path.read_bytes()).decode("ascii")
        return f'<img src="data:{mime};base64,{data}" alt="{esc(alt)}">'
    return f'<span class="img-off">Image: {esc(alt or src)}</span>'


MD.add_render_rule("image", render_image)


def wrap_code(rule):
    """Every code block gets the `.code` wrapper (scroll box and copy button hook), wherever it sits.

    A fence inside a list item or callout used to render as a bare <pre> with no overflow rule, so with JavaScript off
    (which is what wraps it otherwise) a long line ran past the right edge at phone width."""
    def render_code(self, tokens, idx, options, env):
        return f'<div class="code">{rule(tokens, idx, options, env)}</div>'
    return render_code


for _name in ("fence", "code_block"):
    MD.add_render_rule(_name, wrap_code(getattr(MD.renderer, _name)))


def inline_empty(children) -> bool:
    """Nothing renderable left: only blank text and line breaks. Images and code count as content."""
    return all(c.type in ("softbreak", "hardbreak") or (c.type == "text" and not c.content.strip())
               for c in (children or []))


def esc(s: str) -> str:
    return html.escape(s, quote=True)


TEMPLATE_IDS = ("toc", "tp-pstate", "tp-pstate-head")


def slugify(text: str, used: set[str]) -> str:
    base = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:60] or "section"
    slug, i = base, 1
    while slug in used:
        slug, i = f"{base}-{i}", i + 1
    used.add(slug)
    return slug


def fmt_date(s: str) -> str:
    try:
        d = dt.date.fromisoformat(s.strip())
        return f"{d.day} {d.strftime('%B %Y')}"
    except ValueError:
        return s.strip()


# ---------- block grouping ----------

def top_blocks(tokens):
    """Split a token stream into top-level blocks (lists of tokens)."""
    out, i = [], 0
    while i < len(tokens):
        t = tokens[i]
        if t.nesting == 1:
            depth, j = 0, i
            while j < len(tokens):
                depth += tokens[j].nesting
                if depth == 0:
                    break
                j += 1
            out.append(tokens[i:j + 1])
            i = j + 1
        else:
            out.append([t])
            i += 1
    return out


def render(tokens, env) -> str:
    return MD.renderer.render(tokens, MD.options, env)


def render_inline(children, env) -> str:
    return MD.renderer.renderInline(children, MD.options, env)


def inline_text(children) -> str:
    return "".join(c.content for c in children if c.type in ("text", "code_inline"))


# ---------- post-processing of rendered HTML ----------

MARK_RE = re.compile(r"\[(V|I)(?:([,:])\s*([^\[\]]*?))?\]")
MARK_TITLE = {"V": "Verified from a primary source or a live read", "I": "Inference, not checked against a source"}
MARK_WORD = {"V": "Verified", "I": "Inferred"}


PROTECT_RE = re.compile(r"<pre[\s\S]*?</pre>|<code[\s\S]*?</code>|<[^>]*>")


def marks(h: str) -> str:
    """Turn [V], [V, src], [I] ... into provenance marks in text only.

    <pre> and <code> blocks and every tag (so every attribute value) are swapped for bracket-free
    placeholders first: a mark is never found inside them, yet a mark's source text may still
    span a tag such as a link."""
    saved: list[str] = []

    def hide(m):
        saved.append(m.group(0))
        return f"\ue000{len(saved) - 1}\ue001"

    masked = PROTECT_RE.sub(hide, h)

    def sub(m):
        k, src = m.group(1), (m.group(3) or "").strip()
        out = f'<span class="prov"><span class="mark mark--{k.lower()}" title="{MARK_TITLE[k]}">{MARK_WORD[k]}</span>'
        if src:
            out += f'<span class="mark-src">{src}</span>'
        return out + "</span>"

    return re.sub(r"\ue000(\d+)\ue001", lambda m: saved[int(m.group(1))], MARK_RE.sub(sub, masked))


def links(h: str) -> str:
    def sub(m):
        attrs, inner = m.group(1), m.group(2)
        href_m = re.search(r'href="([^"]*)"', attrs)
        href = html.unescape(href_m.group(1)) if href_m else ""
        if not re.match(r"https?://", href):
            return m.group(0)
        bare = ' class="bare"' if html.unescape(re.sub(r"<[^>]+>", "", inner)).strip().rstrip("/") in (href.rstrip("/"), re.sub(r"^https?://", "", href).rstrip("/")) else ""
        return f'<a{attrs}{bare} target="_blank" rel="noopener">{inner}</a>'

    return re.sub(r"<a(\s[^>]*)>([\s\S]*?)</a>", sub, h)


def finish(h: str) -> str:
    return links(marks(h))


# ---------- block transforms ----------

def callout(kind: str, label: str, body: str) -> str:
    return f'<aside class="callout callout--{kind}"><p class="callout-label">{esc(label)}</p>{body}</aside>'


def bold_label(block):
    """If a paragraph opens with **Label:**, return (label, children_after_label)."""
    if len(block) != 3 or block[0].type != "paragraph_open":
        return None
    ch = block[1].children or []
    while ch and ch[0].type == "text" and not ch[0].content:
        ch = ch[1:]
    if not ch or ch[0].type != "strong_open":
        return None
    try:
        close = next(i for i, c in enumerate(ch) if c.type == "strong_close")
    except StopIteration:
        return None
    label = inline_text(ch[1:close]).strip()
    rest = [c for c in ch[close + 1:]]
    if label.endswith(":"):
        label = label[:-1].strip()
        trim = 0
    elif rest and rest[0].type == "text" and rest[0].content.lstrip().startswith(":"):
        trim = 1
    else:
        return None
    if rest and rest[0].type == "text":
        # Copy before trimming so an unclassified paragraph renders untouched.
        first = rest[0].copy()
        first.content = first.content.lstrip()[trim:].lstrip()
        if first.content[:1].islower():
            first.content = first.content[0].upper() + first.content[1:]
        rest[0] = first
    return label, rest


# Words that make a bold run a sentence rather than a label: negations, modals, auxiliaries and
# subject pronouns. "**Authz model.**" is a label; "**Do not ship before Friday.**" is a sentence.
SENTENCE_WORDS = re.compile(
    r"\b(not|never|no|don'?t|doesn'?t|won'?t|can'?t|isn'?t|aren'?t|must|should|shall|will|would|"
    r"can|could|may|might|need|needs|is|are|was|were|be|been|has|have|had|do|does|did|"
    r"i|we|you|he|she|it|they|this|that|these|those|there)\b", re.I)


def bold_only(block):
    """A paragraph that is only a short bold label is a sub-heading in disguise.

    Label-like means: at most eight words and 70 characters, no ending "!" or "?", and none of
    SENTENCE_WORDS. A bold sentence used for emphasis stays a paragraph."""
    if len(block) != 3 or block[0].type != "paragraph_open":
        return None
    ch = [c for c in (block[1].children or []) if not (c.type == "text" and not c.content.strip())]
    if len(ch) < 3 or ch[0].type != "strong_open" or ch[-1].type != "strong_close":
        return None
    if any(c.type in ("strong_open", "strong_close") for c in ch[1:-1]):
        return None
    text = inline_text(ch[1:-1]).strip()
    if not text or len(text) > 70 or len(text.split()) > 8 or text.rstrip()[-1] in "!?":
        return None
    if SENTENCE_WORDS.search(text):
        return None
    return ch[1:-1]


def classify(label: str):
    plain = re.sub(r"\[[^\]]*\]", "", label).strip()
    for kind, rx in CALLOUT_LABELS:
        if rx.search(plain):
            return kind
    return None


def alert(block):
    """GitHub-style > [!TYPE] blockquote -> (kind, label, inner_tokens)."""
    if block[0].type != "blockquote_open" or len(block) < 5:
        return None
    inner = block[1:-1]
    if inner[0].type != "paragraph_open":
        return None
    il = inner[1]
    m = re.match(r"\s*\[!([A-Z]+)\]\s*", il.content)
    if not m or m.group(1) not in ALERTS:
        return None
    il.children = [c for c in (il.children or []) if not (c.type == "text" and not c.content)] or il.children
    first = il.children[0] if il.children else None
    if first is not None and first.type == "text":
        first.content = re.sub(r"^\s*\[![A-Z]+\]\s*", "", first.content)
        # Drop a leading softbreak left behind when the marker sat on its own line.
        if not first.content and len(il.children) > 1 and il.children[1].type == "softbreak":
            il.children = il.children[2:]
    kind, label = ALERTS[m.group(1)]
    # Empty means nothing renderable is left: images (and any other non-text token) count.
    empty_first = inline_empty(il.children)
    return kind, label, (inner[3:] if empty_first else inner)


def github_slug(text: str) -> str:
    """The anchor GitHub (and most markdown viewers) give a heading: '1. Options' -> '1-options'."""
    return re.sub(r"[^\w\- ]", "", text.strip().lower()).replace(" ", "-")


# Only "N. Title" (a number, a full stop, a space) is a numbered section. "2026 roadmap",
# "3 risks we found" and "2.0 release notes" are ordinary titles.
NUM_RE = re.compile(r"^(\d+)\.\s+")


def heading_id(env, text: str, used: set[str]) -> str:
    """A heading's id: "h-" plus its GitHub anchor, so it can never equal a template id.

    The GitHub anchor (with GitHub's -1, -2 numbering for repeats) and a looser ASCII slug are
    recorded as aliases, so links written against either resolve to this heading."""
    # GitHub's own dedup (github-slugger): every emitted anchor is remembered, and a repeat
    # counts up from its base until it finds a free anchor. So "Risk", "Risk-1", "Risk" gives
    # risk, risk-1, risk-2, and "Risk", "Risk", "Risk-1" gives risk, risk-1, risk-1-1.
    seen = env.setdefault("_gh_seen", {})
    g = github_slug(text) or "section"
    gh = g
    while gh in seen:
        seen[g] += 1
        gh = f"{g}-{seen[g]}"
    seen[gh] = 0
    hid, k = "h-" + gh, 1
    while hid in used:
        hid, k = f"h-{gh}-{k}", k + 1
    used.add(hid)
    env.setdefault("_gh_aliases", {}).setdefault(gh, hid)
    loose = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    if loose:
        env.setdefault("_loose_aliases", {}).setdefault(loose, hid)
    return hid


def heading_html(level: int, inline_tok, env, used: set[str]):
    text = inline_text(inline_tok.children).strip() or inline_tok.content
    body = render_inline(inline_tok.children, env)
    num = NUM_RE.match(body)
    if num:
        body = f'<span class="n">{num.group(1)}.</span>' + body[num.end():]
    hid = heading_id(env, text, used)
    return f'<h{level} id="{hid}">{finish(body)}</h{level}>', text


def resolve_anchors(h: str, env, ids: set[str]) -> str:
    """Point in-page links at real ids. A real id always wins; then a GitHub anchor; then a
    loose slug."""
    gh, loose = env.get("_gh_aliases", {}), env.get("_loose_aliases", {})

    def sub(m):
        target = urllib.parse.unquote(html.unescape(m.group(1)))
        if target in ids:
            return m.group(0)
        hid = gh.get(target) or loose.get(target)
        return f'href="#{esc(hid)}"' if hid else m.group(0)

    return re.sub(r'href="#([^"]+)"', sub, h)


def render_blocks(blocks, env, used, lead_first=False, lead_label="Bottom line"):
    out, i, lead_done = [], 0, not lead_first
    while i < len(blocks):
        b = blocks[i]
        t0 = b[0].type
        if t0 == "heading_open":
            lvl = int(b[0].tag[1])
            h, _ = heading_html(min(lvl, 4), b[1], env, used)
            out.append(h)
        elif i == 0 and not lead_done and t0 == "paragraph_open" and not bold_only(b) and not (
                (bl0 := bold_label(b)) and classify(bl0[0])):
            # Only the section's opening block, and only a plain paragraph, is the bottom line.
            lab = f'<p class="lead-label">{esc(lead_label)}</p>' if lead_label else ""
            out.append(f'<div class="lead">{lab}{finish(render(b, env))}</div>')
        elif t0 == "paragraph_open" and (bl := bold_label(b)) and (kind := classify(bl[0])):
            label, rest = bl
            body = render_inline(rest, env).strip()
            inner = f"<p>{body}</p>" if body else ""
            while i + 1 < len(blocks) and blocks[i + 1][0].type in ("bullet_list_open", "ordered_list_open"):
                i += 1
                inner += render(blocks[i], env)
            out.append(finish(callout(kind, label, inner)))
        elif t0 == "paragraph_open" and (inner_ch := bold_only(b)) and not (
                (bl0 := bold_label(b)) and classify(bl0[0])):
            text = inline_text(inner_ch).strip().rstrip(".:").strip()
            hid = heading_id(env, text, used)
            body = render_inline(inner_ch, env).strip()
            body = re.sub(r"[.:]\s*$", "", body)
            out.append(f'<h3 id="{hid}">{finish(body)}</h3>')
        elif t0 == "paragraph_open" and re.match(r"\s*legend\s*:", b[1].content, re.I):
            out.append(finish(render(b, env).replace("<p>", '<p class="legend">', 1)))
        elif t0 == "blockquote_open" and (al := alert(b)):
            kind, label, inner = al
            if kind == "lead":
                out.append(f'<div class="lead"><p class="lead-label">{esc(label)}</p>{finish(render(inner, env))}</div>')
            else:
                out.append(finish(callout(kind, label, render(inner, env))))
        elif t0 == "table_open":
            rows = sum(1 for t in b if t.type == "tr_open") - 1
            tbl = render(b, env)
            if rows >= 4:
                tbl = tbl.replace("<table>", '<table class="sortable">', 1)
            out.append(f'<div class="table-wrap">{finish(tbl)}</div>')
        elif t0 in ("fence", "code_block"):
            out.append(render(b, env))  # the renderer rule adds the .code wrapper
        else:
            out.append(finish(render(b, env)))
        i += 1
    return "\n".join(out)


# ---------- page state ----------

STATES = ("live", "reference", "replaced", "partly-replaced")
GLYPH = {"live": "!", "reference": "\u2713", "replaced": "\u21aa", "partly-replaced": "\u21aa"}


def page_state(meta: dict):
    """The page state named in front matter, or None. Exits with a message on a state missing what it needs."""
    raw = (meta.get("status") or "").strip().lower().replace(" ", "-")
    if raw not in STATES:
        return None
    st = {"status": raw}
    for k in ("replaced_by", "replaced_by_title", "replaced_on", "what_you_do", "still_stands", "why"):
        st[k] = (meta.get(k) or "").strip()
    if raw == "live" and not st["what_you_do"]:
        sys.exit("status: live needs what_you_do (one line: what the reader must do)")
    if raw in ("replaced", "partly-replaced"):
        href = st["replaced_by"]
        if not href:
            sys.exit(f"status: {raw} needs replaced_by (the replacement page's .html)")
        if re.search(r"\.md($|[#?])", href, re.I):
            sys.exit(f"replaced_by must be the replacement page's .html, never a .md file: {href}")
        if not validate_link(href) or not is_html_page(href):
            sys.exit(f"replaced_by is not a link the page can open: {href} (it must be the replacement page's .html)")
        if not st["replaced_on"]:
            sys.exit(f"status: {raw} needs replaced_on (the date the replacement took over)")
    if raw == "partly-replaced" and not stands_tokens(st):
        sys.exit("status: partly-replaced needs still_stands (the sections that still stand: numbers or title starts)")
    return st


HTML_PAGE = re.compile(r"^(https?://[^/?#]+/|(?![a-z][a-z0-9+.-]*:))[^?#]*\.html?([?#]|$)", re.I)


def is_html_page(href: str) -> bool:
    """A web or relative link whose path ends in .html (or .htm): another page, never mail, a text file or a .md."""
    return bool(HTML_PAGE.match(href))


def stands_tokens(st) -> list[str]:
    """The still_stands entries, each once (an entry repeated, "2, 2", is the same entry)."""
    out, seen = [], set()
    for x in st["still_stands"].split(","):
        x, key = x.strip(), x.strip().rstrip(".").lower()
        if key and key not in seen:
            seen.add(key)
            out.append(x)
    return out


def section_stands(tokens: list[str], head_text: str) -> list[str]:
    """Every still_stands token that names this section (by its number or the start of its title)."""
    num = NUM_RE.match(head_text)
    plain = NUM_RE.sub("", head_text).strip().lower()
    hits = []
    for tok in tokens:
        t = tok.strip().rstrip(".").lower()
        if (num and t == num.group(1)) or (t and not t.isdigit() and plain.startswith(t)):
            hits.append(tok)
    return hits


def mark_section(inner: str, hid: str, head_text: str, st, tokens: list[str], matched: dict, standing: list,
                 replaced: list) -> str:
    """A partly replaced page: a "Still stands" or "Replaced" pill on this section; a replaced one folds."""
    hits = section_stands(tokens, head_text)
    for tok in hits:
        matched.setdefault(tok, []).append(head_text)
    if hits:
        standing.append((hid, head_text))
        return '<p class="sec-state sec-state--stands"><span aria-hidden="true">\u2713</span> Still stands</p>\n' + inner
    replaced.append(head_text)
    return (f'<p class="sec-state sec-state--replaced"><span aria-hidden="true">\u21aa</span> Replaced by {state_link(st)}</p>\n'
            + old_fold(inner, "section"))


def check_stands(tokens: list[str], matched: dict, replaced: list) -> None:
    """Every still_stands entry names exactly one section, and at least one section is replaced."""
    if missing := [x for x in tokens if x not in matched]:
        sys.exit("still_stands names no section: " + ", ".join(missing))
    for tok, heads in matched.items():
        if len(heads) > 1:
            sys.exit(f"still_stands entry {tok!r} names more than one section ({'; '.join(heads)}): use its number or more of its title")
    if not replaced:
        sys.exit("status: partly-replaced, but every section still stands: use status: reference (or live) instead")


def state_link(st) -> str:
    href = esc(st["replaced_by"])
    label = esc(st["replaced_by_title"] or st["replaced_by"])
    ext = ' target="_blank" rel="noopener"' if re.match(r"https?:", st["replaced_by"], re.I) else ""
    return f'<a href="{href}"{ext}>{label}</a>'


def state_banner(st, standing: list[tuple[str, str]]) -> str:
    s = st["status"]
    on = f" on {esc(fmt_date(st['replaced_on']))}" if st["replaced_on"] else ""
    why = f" {esc(st['why'])}" if st["why"] else ""
    if s == "live":
        head, detail = "This needs you", esc(st["what_you_do"])
    elif s == "reference":
        head, detail = "Nothing needed from you", "Here for reference only." + why
    elif s == "replaced":
        head = "Nothing needed from you here"
        detail = f"Folded into {state_link(st)}{on}. Read that page instead.{why}"
    else:
        head = "Nothing needed from you here"
        keep = ", ".join(f'<a href="#{hid}">{esc(lbl)}</a>' for hid, lbl in standing)
        detail = (f"Partly folded into {state_link(st)}{on}. Still standing here: {keep}; "
                  f"the other sections are replaced and folded.{why}")
    return (f'<section class="tp-pstate" id="tp-pstate" data-state="{s}" aria-labelledby="tp-pstate-head">'
            f'<span class="tp-pstate-glyph" aria-hidden="true">{GLYPH[s]}</span>'
            f'<div class="tp-pstate-text"><p class="tp-pstate-head" id="tp-pstate-head">{head}</p>'
            f'<p class="tp-pstate-detail">{detail}</p></div></section>')


def old_fold(inner: str, what: str) -> str:
    return (f'<details class="state-old"><summary><span class="state-old-label">Read the old {what} anyway</span>'
            f'<span class="state-old-sub">kept for the record</span></summary>\n<div class="state-old-body">\n{inner}\n</div>\n</details>')


# ---------- document assembly ----------

def parse_front_matter(text: str):
    meta = {}
    m = re.match(r"^---\s*\n([\s\S]*?)\n---\s*\n", text)
    if m:
        for line in m.group(1).splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                meta[k.strip().lower()] = v.strip().strip('"').strip("'")
        text = text[m.end():]
    return meta, text


def strip_leading_comments(text: str) -> str:
    # A closed <!-- ... --> note before the first content is for agents, not the reader: drop it,
    # so a leading H1 after it still becomes the page title (a report opening with a provenance
    # comment built as "Untitled" with the comment shown as text). An unclosed comment, or one
    # after content, stays and is escaped like any raw HTML.
    while True:
        s = text.lstrip()
        if not s.startswith("<!--"):
            return text
        end = s.find("-->")
        if end < 0:
            return text
        text = s[end + 3:]


def build(md_text: str, opts) -> dict:
    meta, md_text = parse_front_matter(md_text)
    md_text = strip_leading_comments(md_text)
    env: dict = {"_base": getattr(opts, "base", None)}
    tokens = MD.parse(md_text, env)
    blocks = top_blocks(tokens)
    # Ids the template itself uses outside the body: no generated id may take one.
    used: set[str] = set(TEMPLATE_IDS)

    st = page_state(meta)
    tokens_stand = stands_tokens(st) if st and st["status"] == "partly-replaced" else []
    matched: dict[str, list[str]] = {}
    standing: list[tuple[str, str]] = []
    replaced_secs: list[str] = []
    title = opts.title or meta.get("title")
    pre, sections, cur, footnotes = [], [], None, []
    for n, b in enumerate(blocks):
        if n == 0 and b[0].type == "heading_open" and b[0].tag == "h1":
            # A leading H1 is the page title. --title / front matter win over its text, but it is
            # consumed either way, so it never turns into a duplicate section.
            title = title or inline_text(b[1].children).strip()
            continue
        if b[0].type == "footnote_block_open":
            footnotes.append(b)
            continue
        if b[0].type == "heading_open" and b[0].tag == "h1":
            # Later H1s are treated as section headings.
            b[0].tag = b[-1].tag = "h2"
        if b[0].type == "heading_open" and b[0].tag == "h2":
            cur = {"head": b, "body": []}
            sections.append(cur)
        elif cur is None:
            pre.append(b)
        else:
            cur["body"].append(b)

    date = opts.date or meta.get("date")
    # Pull a leading "Date: 2026-10-06." out of the first paragraph into the header.
    if pre and pre[0][0].type == "paragraph_open":
        il = pre[0][1]
        kids = [c for c in il.children if not (c.type == "text" and not c.content)]
        il.children = kids
        first = kids[0] if kids else None
        if first is not None and first.type == "text":
            m = re.match(r"\s*date\s*:\s*(\d{4}-\d{2}-\d{2})\.?\s*", first.content, re.I)
            if m:
                date = date or m.group(1)
                first.content = first.content[m.end():]
                if not first.content and len(il.children) > 1 and il.children[1].type == "softbreak":
                    il.children = il.children[2:]
                if inline_empty(il.children):
                    pre = pre[1:]

    # The standfirst is the intro paragraph only. Everything else before the first H2 (or the
    # whole report when it has no H2) goes into the article, where contents, sorting and copy
    # buttons work.
    standfirst = ""
    # A replaced page keeps no opening paragraph outside the fold: it stays in the old version with the rest. A partly
    # replaced page keeps it in the opening section, which is marked like any other.
    replaced = bool(st and st["status"] == "replaced")
    if not (replaced or tokens_stand) and pre and pre[0][0].type == "paragraph_open" and not bold_only(pre[0]) and not (
            (bl := bold_label(pre[0])) and classify(bl[0])):
        standfirst = finish(render(pre[0], env))
        pre = pre[1:]

    body = []
    if pre and tokens_stand:
        oid = slugify("sec-opening", used)
        inner = mark_section(render_blocks(pre, env, used), oid, "Opening", st, tokens_stand, matched, standing, replaced_secs)
        body.append(f'<section class="sec sec--intro" id="{oid}">\n{inner}\n</section>')
    elif pre:
        body.append(f'<section class="sec sec--intro">\n{render_blocks(pre, env, used)}\n</section>')
    for s in sections:
        h_inline = s["head"][1]
        head_text = inline_text(h_inline.children).strip()
        plain = NUM_RE.sub("", head_text)
        sid = slugify("sec-" + plain, used)
        if FOLD_HEADS.match(plain):
            h, _ = heading_html(2, h_inline, env, used)
            inner = render_blocks(s["body"], env, used)
            pill = ""
            if tokens_stand:
                inner = mark_section(inner, re.search(r'id="([^"]+)"', h).group(1), head_text, st, tokens_stand, matched,
                                     standing, replaced_secs)
                # A folded section shows its mark in the summary, so it reads while the fold is closed.
                m = re.match(r'<p (class="sec-state [^"]+")>([\s\S]*?)</p>\n', inner)
                pill, inner = f'<span {m.group(1)}>{m.group(2)}</span>', inner[m.end():]
            body.append(
                f'<section class="sec" id="{sid}">\n<details class="fold">\n<summary><span class="chev" aria-hidden="true"></span>{h}{pill}'
                f'<span class="fold-hint"><span class="when-closed">Show</span><span class="when-open">Hide</span></span></summary>\n{inner}\n</details>\n</section>'
            )
        else:
            h, _ = heading_html(2, h_inline, env, used)
            is_lead = bool(LEAD_HEADS.match(plain))
            label = "" if plain.lower() == "bottom line" else "Bottom line"
            inner = render_blocks(s["body"], env, used, lead_first=is_lead, lead_label=label)
            if tokens_stand:
                inner = mark_section(inner, re.search(r'id="([^"]+)"', h).group(1), head_text, st, tokens_stand, matched,
                                     standing, replaced_secs)
            body.append(f'<section class="sec" id="{sid}">\n{h}\n{inner}\n</section>')

    if not body:
        body.append('<section class="sec"></section>')

    meta_html = ""
    if date:
        meta_html += f"<div><dt>Date</dt><dd>{esc(fmt_date(date))}</dd></div>"
    author = opts.author or meta.get("author")
    if author:
        meta_html += f"<div><dt>By</dt><dd>{esc(author)}</dd></div>"
    # A page-state keyword is the banner, not a label; --status still sets a free-text label beside it.
    status = opts.status or (None if st else meta.get("status"))
    if status:
        meta_html += f'<div><dt>Status</dt><dd><span class="status">{esc(status)}</span></dd></div>'

    if footnotes:
        # The plugin moves every definition to the end; they become a Notes section there.
        hid = heading_id(env, "Notes", used)
        sid = slugify("sec-notes", used)
        notes = f'<div class="footnotes">{finish("".join(render(b, env) for b in footnotes))}</div>'
        if tokens_stand:
            notes = mark_section(notes, hid, "Notes", st, tokens_stand, matched, standing, replaced_secs)
        body.append(f'<section class="sec sec--notes" id="{sid}">\n<h2 id="{hid}">Notes</h2>\n{notes}\n</section>')
    if tokens_stand:
        check_stands(tokens_stand, matched, replaced_secs)

    body_html = "\n".join(body)
    if replaced:
        body_html = old_fold(body_html, "version")
    ids = set(re.findall(r'\sid="([^"]+)"', body_html))
    return {
        "toc": toc_html(body_html),
        "title": title or "Untitled",
        "standfirst": resolve_anchors(standfirst, env, ids),
        "meta": meta_html,
        "body": resolve_anchors(body_html, env, ids),
        "state": state_banner(st, standing) if st else "",
        "page_state": st["status"] if st else "",
    }


def toc_html(body: str) -> str:
    """The contents list, written into the page so it reads without JavaScript.

    Mirrors what the template script used to build: every h2 and h3 with an id, in order."""
    items = []
    for m in re.finditer(r'<h([23]) id="([^"]+)">([\s\S]*?)</h\1>', body):
        lvl, hid, inner = m.groups()
        n = re.search(r'<span class="n">([^<]*)</span>', inner)
        label = re.sub(r"<[^>]+>", "", re.sub(r'<span class="n">[^<]*</span>', "", inner, count=1)).strip()
        num = f'<span class="n">{n.group(1).rstrip(".")}</span>' if n else ""
        items.append(f'<li class="lvl{lvl}"><a href="#{hid}">{num}{label}</a></li>')
    return f"<ol>{''.join(items)}</ol>" if items else ""


def fill(template: str, parts: dict) -> str:
    def region(name: str, value: str, t: str) -> str:
        rx = re.compile(r"<!--@" + name + r"-->[\s\S]*?<!--/@" + name + r"-->")
        if not rx.search(t):
            sys.exit(f"template is missing the @{name} region")
        return rx.sub(lambda _m: f"<!--@{name}-->{value}<!--/@{name}-->", t, count=1)

    out = re.sub(r"<title>[^<]*</title>", lambda _m: f"<title>{esc(parts['title'])}</title>", template, count=1)
    out = region("title", esc(parts["title"]), out)
    out = region("standfirst", parts["standfirst"], out)
    out = region("meta", parts["meta"], out)
    out = region("toc", parts.get("toc", ""), out)
    out = region("body", "\n" + parts["body"] + "\n", out)
    if parts.get("state"):
        out = region("state", parts["state"], out)
        m = re.search(r"<html\b[^>]*>", out, re.I)
        cls = re.search(r'\sclass="([^"]*)"', m.group(0)) if m else None
        if not cls or not {"tp", "tp-reading"} <= set(cls.group(1).split()):
            sys.exit('template root (<html>) has no "tp tp-reading" classes: the page state needs the reading template\'s root')
        out = out[:m.start()] + m.group(0)[:5] + f' data-page-state="{parts["page_state"]}"' + m.group(0)[5:] + out[m.end():]
    elif "<!--@state-->" in out:
        out = region("state", "", out)
    if not parts["standfirst"]:
        out = out.replace('<div class="standfirst"><!--@standfirst--><!--/@standfirst--></div>', "")
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description="Build a reading page from markdown.")
    ap.add_argument("input")
    ap.add_argument("output", nargs="?")
    ap.add_argument("--title")
    ap.add_argument("--date", help="YYYY-MM-DD")
    ap.add_argument("--author")
    ap.add_argument("--status")
    ap.add_argument("--template", default=str(DEFAULT_TEMPLATE))
    opts = ap.parse_args(argv)

    src = Path(opts.input)
    dst = Path(opts.output) if opts.output else src.with_suffix(".html")
    opts.base = str(src.resolve().parent)
    parts = build(src.read_text(encoding="utf-8"), opts)
    page = fill(Path(opts.template).read_text(encoding="utf-8"), parts)
    dst.write_text(page, encoding="utf-8")
    print(f"wrote {dst}")


if __name__ == "__main__":
    main()

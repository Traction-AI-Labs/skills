#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "markdown-it-py==3.0.0",
#   "mdurl==0.1.2",
#   "linkify-it-py==2.0.3",
#   "uc-micro-py==1.0.3",
#   "mdit-py-plugins==0.4.2",
#   "pytest==8.3.3",
# ]
# ///
"""Unit tests for build.py (skill: reading-page). No browser.

    uv run <skill-dir>/scripts/test_build.py
"""
from __future__ import annotations

import importlib.util
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("reading_page_build", HERE / "build.py")
B = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(B)
TEMPLATE = (HERE.parent / "references" / "template.html").read_text(encoding="utf-8")


PNG = bytes.fromhex("89504e470d0a1a0a0000000d4948445200000001000000010806000000"
                    "1f15c4890000000d49444154789c6360000002000154a24f5d0000000049454e44ae426082")


def build(md: str, **kw) -> dict:
    opts = SimpleNamespace(title=None, date=None, author=None, status=None, base=None)
    for k, v in kw.items():
        setattr(opts, k, v)
    return B.build(md, opts)


def page(md: str, **kw) -> str:
    return B.fill(TEMPLATE, build(md, **kw))


# ---------- finding 1: raw HTML and unsafe links ----------

@pytest.mark.parametrize("raw", [
    "<script>alert(1)</script>",
    '<img src=x onerror="alert(1)">',
    '<iframe src="https://example.com"></iframe>',
    "Pages use <details> to fold.",
    "An HTML comment starts with <!-- and hides things.",
])
def test_raw_html_is_escaped(raw):
    p = build(f"# T\n\nIntro.\n\n## A\n\n{raw}\n\nAfter it.\n\n<div>\nblock html\n</div>\n")
    body = p["body"]
    for bad in ("<script", "<img", "<iframe", "<details>", "<!--", "<div>"):
        assert bad not in body, bad
    assert "&lt;" in body
    assert "<p>After it.</p>" in body


@pytest.mark.parametrize("href", [
    "javascript:alert(1)",
    "JavaScript:alert(1)",
    "data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==",
    "vbscript:msgbox(1)",
    "file:///etc/passwd",
    "ms-msdt:/id%20PCWDiagnostic",  # allowed by markdown-it's default deny-list, refused here
])
def test_unsafe_link_schemes_are_not_links(href):
    body = build(f"# T\n\nIntro.\n\n## A\n\n[click]({href}) and <{href}>\n")["body"]
    assert "<a " not in body
    assert "click" in body


def test_safe_links_still_link():
    body = build("# T\n\nIntro.\n\n## A\n\n[a](https://x.com) [b](mailto:k@x.com) [c](other.html) [d](#h-a) [e](../r.md)\n")["body"]
    for href in ("https://x.com", "mailto:k@x.com", "other.html", "#h-a", "../r.md"):
        assert f'href="{href}"' in body


# ---------- finding 2: title from front matter or --title plus a leading H1 ----------

FM = "---\ntitle: Front title\n---\n# Heading title\n\nDate: 2026-10-07. Intro.\n\n## Summary\n\nAnswer.\n"


def test_front_matter_title_consumes_leading_h1():
    p = build(FM)
    assert p["title"] == "Front title"
    assert "Heading title" not in p["body"]
    assert 'id="sec-heading-title"' not in p["body"]
    assert p["standfirst"] == "<p>Intro.</p>\n"
    assert "7 October 2026" in p["meta"]


def test_cli_title_consumes_leading_h1():
    p = build("# Heading title\n\nDate: 2026-10-07. Intro.\n\n## Summary\n\nAnswer.\n", title="CLI title")
    assert p["title"] == "CLI title"
    assert "Heading title" not in p["body"]
    assert "Intro." in p["standfirst"]
    assert "7 October 2026" in p["meta"]


def test_later_h1_becomes_section():
    p = build("# T\n\nIntro.\n\n## A\n\nx\n\n# Later\n\ny\n")
    assert '<h2 id="h-later">Later</h2>' in p["body"]


# ---------- finding 3: report with no H2 ----------

NO_H2 = """# T

Intro paragraph.

Second paragraph.

### Part

| a | b |
|---|---|
| 1 | 2 |
| 3 | 4 |
| 5 | 6 |
| 7 | 8 |

```
code here
```
"""


def test_no_h2_report_goes_into_article():
    p = build(NO_H2)
    assert p["standfirst"] == "<p>Intro paragraph.</p>\n"
    body = p["body"]
    assert "<p>Second paragraph.</p>" in body
    assert '<h3 id="h-part">Part</h3>' in body
    assert '<table class="sortable">' in body
    assert '<div class="code"><pre><code>code here' in body
    full = page(NO_H2)
    article = full[full.index("<article>"):full.index("</article>")]
    assert "sortable" in article and 'class="code"' in article


def test_intro_blocks_before_first_h2_go_into_article():
    p = build("# T\n\nIntro.\n\nLegend: **[V]** verified.\n\n## A\n\nx\n")
    assert p["standfirst"] == "<p>Intro.</p>\n"
    assert p["body"].startswith('<section class="sec sec--intro">')
    assert '<p class="legend">' in p["body"]


# ---------- finding 4: provenance marks only in text ----------

def test_marks_skip_inline_code_and_attributes():
    body = build('# T\n\nIntro.\n\n## A\n\nWrite `[V]` after a claim. [src](https://e.com "[V]") Claim [V, docs].\n')["body"]
    assert "<code>[V]</code>" in body
    assert 'title="[V]"' in body
    assert body.count('class="prov"') == 1
    assert '<span class="mark-src">docs</span>' in body


def test_marks_skip_fences_and_render_plain():
    body = build("# T\n\nIntro.\n\n## A\n\nA [I] claim and [V: live read].\n\n```\n[V]\n```\n")["body"]
    assert "mark--i" in body and "mark--v" in body
    assert "<code>[V]\n</code>" in body


def test_mark_source_may_span_a_link():
    body = build("# T\n\nIntro.\n\n## A\n\nClaim [V, see https://a.com].\n")["body"]
    assert re.search(r'<span class="mark-src">see <a href="https://a.com"[^>]*>https://a.com</a></span>', body)


# ---------- finding 5: bold-only paragraphs ----------

@pytest.mark.parametrize("line", [
    "**Do not ship before Friday.**",
    "**This is the key point.**",
    "**We should wait.**",
    "**Ship it now!**",
    "**A very long bold line that runs on for more than eight words total.**",
])
def test_bold_sentence_stays_paragraph(line):
    body = build(f"# T\n\nIntro.\n\n## A\n\n{line}\n\nMore.\n")["body"]
    assert "<h3" not in body
    assert f"<p>{B.MD.renderInline(line)}</p>" in body


@pytest.mark.parametrize("line,hid,text", [
    ("**Authz model.**", "authz-model", "Authz model"),
    ("**Storage and publishing**", "storage-and-publishing", "Storage and publishing"),
    ("**Hosting and auth: Cloudflare (recommended).**", "hosting-and-auth-cloudflare-recommended",
     "Hosting and auth: Cloudflare (recommended)"),
])
def test_bold_label_becomes_h3(line, hid, text):
    body = build(f"# T\n\nIntro.\n\n## A\n\n{line}\n\nMore.\n")["body"]
    assert f'<h3 id="h-{hid}">{text}</h3>' in body


# ---------- finding 6: links to numbered headings ----------

def test_link_to_numbered_heading_resolves():
    md = ("# T\n\nIntro, see [opts](#1-options).\n\n## 1. Options\n\n[Jump](#1-options) [Src](#sources) "
          "[Sub](#22-detail) [Lab](#authz-model)\n\n### 2.2 Detail\n\n**Authz model.**\n\nx\n\n## Sources\n\n- a\n")
    p = build(md)
    body = p["body"]
    assert '<h2 id="h-1-options"><span class="n">1.</span>Options</h2>' in body
    assert '<a href="#h-1-options">Jump</a>' in body
    assert '<a href="#h-sources">Src</a>' in body
    assert '<a href="#h-22-detail">Sub</a>' in body
    assert '<a href="#h-authz-model">Lab</a>' in body
    assert 'href="#h-1-options"' in p["standfirst"]
    ids = set(re.findall(r'id="([^"]+)"', body))
    for href in re.findall(r'href="#([^"]+)"', p["standfirst"] + body):
        assert href in ids, href


# ---------- finding 7: image-only alert ----------

def test_image_only_alert_keeps_image(tmp_path):
    (tmp_path / "d.png").write_bytes(PNG)
    body = build("# T\n\nIntro.\n\n## A\n\n> [!NOTE]\n> ![diagram](d.png)\n", base=str(tmp_path))["body"]
    assert "callout--note" in body
    assert '<img src="data:image/png;base64,' in body and 'alt="diagram"' in body


def test_marker_only_alert_paragraph_is_dropped():
    body = build("# T\n\nIntro.\n\n## A\n\n> [!NOTE]\n>\n> Body text.\n")["body"]
    assert "[!NOTE]" not in body
    assert re.search(r'<p class="callout-label">Note</p>\s*<p>Body text.</p>', body)


def test_alert_marker_with_text_on_same_paragraph():
    body = build("# T\n\nIntro.\n\n## A\n\n> [!WARNING]\n> Watch this.\n")["body"]
    assert re.search(r'callout--risk"><p class="callout-label">Warning</p><p>Watch this.</p>', body)


# ---------- documented behaviours ----------

def test_bottom_line_box_from_summary():
    body = build("# T\n\nIntro.\n\n## Summary\n\n**Build it.** Because.\n\nMore.\n")["body"]
    assert '<div class="lead"><p class="lead-label">Bottom line</p><p><strong>Build it.</strong> Because.</p>' in body
    assert "<p>More.</p>" in body


def test_bottom_line_heading_has_no_duplicate_label():
    body = build("# T\n\nIntro.\n\n## Bottom line\n\nAnswer.\n")["body"]
    assert '<div class="lead"><p>Answer.</p>' in body


def test_bottomline_alert():
    body = build("# T\n\nIntro.\n\n## A\n\n> [!BOTTOMLINE]\n> Answer.\n")["body"]
    assert '<div class="lead"><p class="lead-label">Bottom line</p><p>Answer.</p>' in body


@pytest.mark.parametrize("head", ["Sources", "Evidence", "References", "Appendix B", "Method", "Notes"])
def test_folded_sections(head):
    body = build(f"# T\n\nIntro.\n\n## {head}\n\n- a\n")["body"]
    assert '<details class="fold">' in body
    assert "<summary>" in body and "<li>a</li>" in body


def test_unfolded_section_is_plain():
    body = build("# T\n\nIntro.\n\n## Findings\n\n- a\n")["body"]
    assert "<details" not in body


def test_numbered_sections():
    body = build("# T\n\nIntro.\n\n## 2. Buy options\n\nx\n")["body"]
    assert '<h2 id="h-2-buy-options"><span class="n">2.</span>Buy options</h2>' in body
    assert 'id="sec-buy-options"' in body


@pytest.mark.parametrize("head,hid", [
    ("2026 roadmap", "h-2026-roadmap"),
    ("3 risks we found", "h-3-risks-we-found"),
    ("2.0 release notes", "h-20-release-notes"),
    ("1.2. Nested", "h-12-nested"),
])
def test_only_n_dot_space_is_a_numbered_section(head, hid):
    body = build(f"# T\n\nIntro.\n\n## {head}\n\nx\n")["body"]
    assert f'<h2 id="{hid}">{head}</h2>' in body
    assert 'class="n"' not in body


@pytest.mark.parametrize("label,kind", [
    ("Main risks", "risk"),
    ("Smallest version worth having", "rec"),
    ("Recommendation", "rec"),
    ("Next steps", "rec"),
    ("Decision needed", "decision"),
    ("Open question", "decision"),
    ("Note", "note"),
    ("Alternative", "note"),
])
def test_bold_label_callouts(label, kind):
    body = build(f"# T\n\nIntro.\n\n## A\n\n**{label}:**\n\n- one\n- two\n\nAfter.\n")["body"]
    assert re.search(rf'<aside class="callout callout--{kind}"><p class="callout-label">{label}</p>\s*<ul>\s*<li>one</li>', body)
    assert "<p>After.</p>" in body


def test_unclassified_bold_label_is_plain_paragraph():
    body = build("# T\n\nIntro.\n\n## A\n\n**Cost:** five dollars.\n")["body"]
    assert "<aside" not in body
    assert "<p><strong>Cost:</strong> five dollars.</p>" in body


@pytest.mark.parametrize("marker,kind", [
    ("RECOMMENDATION", "rec"), ("TIP", "rec"), ("RISK", "risk"), ("CAUTION", "risk"),
    ("DECISION", "decision"), ("IMPORTANT", "decision"), ("NOTE", "note"),
    ("VERIFIED", "verified"), ("INFERRED", "inferred"),
])
def test_alerts(marker, kind):
    body = build(f"# T\n\nIntro.\n\n## A\n\n> [!{marker}]\n> Text.\n")["body"]
    assert f'callout--{kind}"' in body and "<p>Text.</p>" in body
    assert "<blockquote>" not in body


def test_plain_blockquote_untouched():
    body = build("# T\n\nIntro.\n\n## A\n\n> Just a quote.\n")["body"]
    assert "<blockquote>" in body


def test_tables_sortable_at_four_rows():
    rows4 = "| a | b |\n|---|---|\n" + "".join(f"| {i} | x |\n" for i in range(4))
    rows3 = "| a | b |\n|---|---|\n" + "".join(f"| {i} | x |\n" for i in range(3))
    b4 = build(f"# T\n\nIntro.\n\n## A\n\n{rows4}")["body"]
    b3 = build(f"# T\n\nIntro.\n\n## A\n\n{rows3}")["body"]
    assert '<div class="table-wrap"><table class="sortable">' in b4
    assert '<div class="table-wrap"><table>' in b3


def test_code_fence_copy_markup():
    body = build("# T\n\nIntro.\n\n## A\n\n```bash\necho <hi> & [V]\n```\n")["body"]
    assert '<div class="code"><pre><code class="language-bash">echo &lt;hi&gt; &amp; [V]\n</code></pre>\n</div>' in body


def test_external_links_open_new_tab_and_bare():
    body = build("# T\n\nIntro.\n\n## A\n\nSee https://example.com and [docs](https://d.com) and [x](#h-a).\n")["body"]
    assert '<a href="https://example.com" class="bare" target="_blank" rel="noopener">' in body
    assert '<a href="https://d.com" target="_blank" rel="noopener">docs</a>' in body
    assert '<a href="#h-a">x</a>' in body


def test_date_lift_and_meta():
    p = build("# T\n\nDate: 2026-10-06. Asked by K.\n\n## A\n\nx\n", author="Claude", status="Done")
    assert p["standfirst"] == "<p>Asked by K.</p>\n"
    assert "6 October 2026" in p["meta"] and "Claude" in p["meta"] and "Done" in p["meta"]


def test_fill_escapes_title_and_fills_regions():
    out = page("# A <b> & C\n\nIntro.\n\n## S\n\nx\n")
    assert "<title>A &lt;b&gt; &amp; C</title>" in out
    assert "<!--@title-->A &lt;b&gt; &amp; C<!--/@title-->" in out
    assert "Every report you read" not in out  # demo standfirst replaced
    assert out.count("<article>") == 1


# ---------- round 2, finding 1: bottom-line box is the section's opening paragraph only ----------

def test_summary_opening_with_list_gets_no_box():
    body = build("# T\n\nIntro.\n\n## Summary\n\n- a\n- b\n\n### Detail\n\nSee below.\n")["body"]
    assert 'class="lead"' not in body
    assert "<p>See below.</p>" in body


def test_summary_opening_with_bold_label_gets_no_box():
    body = build("# T\n\nIntro.\n\n## TL;DR\n\n**Key findings**\n\n- a\n\nLater paragraph.\n")["body"]
    assert 'class="lead"' not in body
    assert '<h3 id="h-key-findings">Key findings</h3>' in body


def test_summary_opening_with_callout_label_gets_no_box():
    body = build("# T\n\nIntro.\n\n## Verdict\n\n**Main risks:**\n\n- a\n\nLater.\n")["body"]
    assert 'class="lead"' not in body and "callout--risk" in body


def test_only_first_paragraph_is_the_box():
    body = build("# T\n\nIntro.\n\n## Recommendation\n\nFirst.\n\nSecond.\n")["body"]
    assert body.count('class="lead"') == 1
    assert '<div class="lead"><p class="lead-label">Bottom line</p><p>First.</p>' in body
    assert "<p>Second.</p>" in body


# ---------- round 2, finding 2: untested limits ----------

def test_schemeless_domains_stay_text():
    body = build("# T\n\nIntro.\n\n## A\n\nSee DAIR.AI and example.com for more.\n")["body"]
    assert "<a " not in body
    assert "See DAIR.AI and example.com for more." in body


def test_bold_label_over_70_chars_stays_paragraph():
    label = "Supercalifragilistic internationalisation considerations for multi-region deployments"
    assert len(label) > 70 and len(label.split()) <= 8 and not B.SENTENCE_WORDS.search(label)
    body = build(f"# T\n\nIntro.\n\n## A\n\n**{label}**\n\nMore.\n")["body"]
    assert "<h3" not in body
    assert f"<p><strong>{label}</strong></p>" in body


# ---------- round 2, finding 3: contents list without JavaScript ----------

TOC_MD = "# T\n\nIntro.\n\n## 1. Options\n\n### Sub part\n\nx\n\n## Sources\n\n- a\n"


def test_toc_is_written_into_the_page():
    out = page(TOC_MD)
    nav = re.search(r'<nav class="toc" id="toc"><!--@toc-->([\s\S]*?)<!--/@toc--></nav>', out).group(1)
    assert nav == ('<ol><li class="lvl2"><a href="#h-1-options"><span class="n">1</span>Options</a></li>'
                   '<li class="lvl3"><a href="#h-sub-part">Sub part</a></li>'
                   '<li class="lvl2"><a href="#h-sources">Sources</a></li></ol>')
    article = out[out.index("<article>"):out.index("</article>")]
    for hid in re.findall(r'href="#([^"]+)"', nav):
        assert f'id="{hid}"' in article


def test_built_page_ships_no_js_and_full_static_contents():
    """The page reads without JavaScript: <html class="no-js"> and a contents list holding a link
    to every h2 and h3 in the article. Behaviour in a real browser: scripts/browser_check.sh."""
    out = page(TOC_MD + "\n## Later\n\n**Bold label**\n\ny\n")
    assert re.search(r'<html[^>]*\bclass="no-js"', out)
    nav = re.search(r'<nav class="toc" id="toc">([\s\S]*?)</nav>', out).group(1)
    article = out[out.index("<article>"):out.index("</article>")]
    heads = re.findall(r'<h[23] id="([^"]+)"', article)
    assert len(heads) == 5
    assert re.findall(r'href="#([^"]+)"', nav) == heads


# ---------- round 2, finding 4: images stay offline ----------

def test_remote_image_never_loads():
    body = build("# T\n\nIntro.\n\n## A\n\n![tracking pixel](https://example.com/pixel.png) and ![p](//cdn.x/y.png)\n")["body"]
    assert "<img" not in body
    assert "Image not loaded: tracking pixel" in body
    assert 'href="https://example.com/pixel.png"' in body


def test_local_image_is_embedded(tmp_path):
    (tmp_path / "img").mkdir()
    (tmp_path / "img" / "d.png").write_bytes(PNG)
    body = build("# T\n\nIntro.\n\n## A\n\n![diagram](img/d.png)\n", base=str(tmp_path))["body"]
    assert f'<img src="data:image/png;base64,{B.base64.b64encode(PNG).decode()}" alt="diagram">' in body


def test_missing_local_image_shows_alt_text(tmp_path):
    body = build("# T\n\nIntro.\n\n## A\n\n![diagram](nope.png)\n", base=str(tmp_path))["body"]
    assert "<img" not in body
    assert '<span class="img-off">Image: diagram</span>' in body


def test_cli_embeds_image_beside_markdown(tmp_path):
    (tmp_path / "d.png").write_bytes(PNG)
    md = tmp_path / "r.md"
    md.write_text("# T\n\nIntro.\n\n## A\n\n![diagram](d.png)\n", encoding="utf-8")
    B.main([str(md)])
    out = (tmp_path / "r.html").read_text(encoding="utf-8")
    assert '<img src="data:image/png;base64,' in out


# ---------- round 2, finding 5: Date lift keeps an image in the same paragraph ----------

@pytest.mark.parametrize("sep", [" ", "\n"])
def test_date_lift_keeps_image(sep):
    p = build(f"# T\n\nDate: 2026-10-07.{sep}![diagram](diagram.png)\n\n## A\n\nBody.\n")
    assert "7 October 2026" in p["meta"]
    assert "Image: diagram" in p["standfirst"]
    assert "Date:" not in p["standfirst"]


# ---------- round 2, finding 6: links to repeated headings ----------

def test_links_to_repeated_headings_resolve():
    md = ("# T\n\nIntro.\n\n## A\n\n[one](#risk) [two](#risk-1) [three](#risk-2) [n2](#1-options-1)\n\n"
          "## Risk\n\nx\n\n## Risk\n\ny\n\n## Risk\n\nz\n\n## 1. Options\n\na\n\n## 1. Options\n\nb\n")
    body = build(md)["body"]
    risk_ids = re.findall(r'<h2 id="([^"]+)">Risk</h2>', body)
    opt_ids = re.findall(r'<h2 id="([^"]+)"><span class="n">1\.</span>Options</h2>', body)
    assert len(set(risk_ids)) == 3 and len(set(opt_ids)) == 2
    hrefs = re.findall(r'<a href="#([^"]+)">(?:one|two|three|n2)</a>', body)
    assert hrefs == risk_ids + [opt_ids[1]]


# ---------- round 3, finding 1: images never escape the markdown's folder ----------

@pytest.fixture
def jail(tmp_path):
    """md/ holds the markdown; outside/ holds a private image next to it."""
    md, out = tmp_path / "md", tmp_path / "outside"
    md.mkdir(), out.mkdir()
    (out / "secret.png").write_bytes(PNG)
    (md / "ok.png").write_bytes(PNG)
    return md, out


def _img(md_dir, ref):
    return build(f"# T\n\nIntro.\n\n## A\n\n![pic]({ref})\n", base=str(md_dir))["body"]


def test_image_inside_folder_embeds(jail):
    md, _ = jail
    assert "data:image/png;base64," in _img(md, "ok.png")
    assert "data:image/png;base64," in _img(md, "./sub/../ok.png")


@pytest.mark.parametrize("kind", ["absolute", "dotdot", "symlink_file", "symlink_dir", "encoded_dotdot"])
def test_image_outside_folder_is_not_embedded(jail, kind):
    md, out = jail
    if kind == "absolute":
        ref = str(out / "secret.png")
    elif kind == "dotdot":
        ref = "../outside/secret.png"
    elif kind == "encoded_dotdot":
        ref = "%2e%2e/outside/secret.png"
    elif kind == "symlink_file":
        (md / "link.png").symlink_to(out / "secret.png")
        ref = "link.png"
    else:
        (md / "linkdir").symlink_to(out, target_is_directory=True)
        ref = "linkdir/secret.png"
    body = _img(md, ref)
    assert "data:" not in body and "<img" not in body
    assert '<span class="img-off">Image: pic</span>' in body


def test_unsupported_image_type_is_not_embedded(jail):
    md, _ = jail
    (md / "doc.pdf").write_bytes(b"%PDF-1.4")
    body = _img(md, "doc.pdf")
    assert "data:" not in body and "Image: pic" in body


def test_no_base_embeds_nothing(jail):
    md, _ = jail
    body = build(f"# T\n\nIntro.\n\n## A\n\n![pic]({md / 'ok.png'})\n")["body"]
    assert "data:" not in body


# ---------- round 3, finding 4: heading ids never equal template ids ----------

def test_heading_ids_never_collide_with_template_ids():
    out = page("# T\n\nIntro.\n\n## Contents\n\nx\n\n## TOC\n\ny\n\n## Toc\n\nz\n\n### toc\n\nw\n")
    body = out[out.index("<!--@body-->"):out.index("<!--/@body-->")]
    rest = out.replace(body, "")
    template_ids = set(re.findall(r'\sid="([^"]+)"', rest))
    body_ids = re.findall(r'\sid="([^"]+)"', body)
    assert "toc" in template_ids
    assert not template_ids & set(body_ids)
    all_ids = re.findall(r'\sid="([^"]+)"', out)
    assert len(all_ids) == len(set(all_ids))
    nav = re.search(r'<nav class="toc" id="toc">([\s\S]*?)</nav>', out).group(1)
    for hid in re.findall(r'href="#([^"]+)"', nav):
        assert hid in body_ids


def test_template_ids_reserved_even_without_prefix():
    # The reserve list guards section ids too: a section can never be called "toc".
    assert "toc" in B.TEMPLATE_IDS
    used = set(B.TEMPLATE_IDS)
    assert B.slugify("toc", used) == "toc-1"


# ---------- round 3, finding 5: a real id beats an alias; aliases follow GitHub ----------

def test_numbered_and_unnumbered_same_title_link_correctly():
    md = ("# T\n\nIntro.\n\n## A\n\n[num](#1-options) [plain](#options)\n\n"
          "## 1. Options\n\nx\n\n## Options\n\ny\n")
    body = build(md)["body"]
    num_id = re.search(r'<h2 id="([^"]+)"><span class="n">1\.</span>Options</h2>', body).group(1)
    plain_id = re.search(r'<h2 id="([^"]+)">Options</h2>', body).group(1)
    assert num_id != plain_id
    assert f'<a href="#{num_id}">num</a>' in body
    assert f'<a href="#{plain_id}">plain</a>' in body


def test_real_id_wins_over_colliding_alias():
    # "H options" has GitHub anchor "h-options", which is also the real id of "## Options".
    md = "# T\n\nIntro.\n\n## A\n\n[x](#h-options) [y](#h-h-options)\n\n## Options\n\na\n\n## H options\n\nb\n"
    body = build(md)["body"]
    assert '<h2 id="h-options">Options</h2>' in body
    assert '<h2 id="h-h-options">H options</h2>' in body
    assert '<a href="#h-options">x</a>' in body
    assert '<a href="#h-h-options">y</a>' in body


# ---------- round 4, finding 1: footnotes ----------

FN_MD = ("# T\n\nIntro.\n\n## A\n\nClaim.[^1] Other.[^note] Again.[^1]\n\n"
         "[^1]: https://example.com/paper\n[^note]: A prose note with [V, docs].\n")


def test_footnotes_render_as_notes_with_backlinks():
    p = build(FN_MD)
    body = p["body"]
    assert '<sup class="footnote-ref"><a href="#fn1" id="fnref1">1</a></sup>' in body
    assert '<sup class="footnote-ref"><a href="#fn2" id="fnref2">2</a></sup>' in body
    assert '<a href="#fn1" id="fnref1:1">1</a>' in body  # second reference to note 1
    notes = body[body.index('id="sec-notes"'):]
    assert '<h2 id="h-notes">Notes</h2>' in notes
    assert '<li id="fn1" class="footnote-item"><p><a href="https://example.com/paper"' in notes
    assert "A prose note with" in notes and "mark--v" in notes
    assert 'href="#fnref1" class="footnote-backref"' in notes and 'href="#fnref2" class="footnote-backref"' in notes
    assert "[^" not in body and "^1" not in body
    ids = set(re.findall(r'\sid="([^"]+)"', body))
    for href in re.findall(r'href="#([^"]+)"', body):
        assert href in ids, href
    assert 'href="#h-notes"' in p["toc"]


def test_footnotes_section_comes_last():
    body = build(FN_MD + "\n## Sources\n\n- s\n")["body"]
    assert body.rindex("<section") == body.index('id="sec-notes"') - len('<section class="sec sec--notes" ')


# ---------- round 4, finding 2: long tokens wrap on a phone ----------

def _css_rules(css):
    return [(sel.strip(), body) for sel, body in re.findall(r"([^{}]+)\{([^{}]*)\}", css)]


def test_long_tokens_wrap_in_text_lists_and_cells():
    """Every text container that can hold a long URL wraps it. Browser check: build
    scripts/fixtures/long-tokens.md and run scripts/browser_check.sh on it (scrollWidth 390)."""
    css = re.sub(r"/\*[\s\S]*?\*/", "", TEMPLATE[TEMPLATE.index("<style>"):TEMPLATE.index("</style>")])
    wrapping = set()
    for sel, body in _css_rules(css):
        if re.search(r"overflow-wrap:\s*(anywhere|break-word)", body):
            wrapping |= {x.strip() for x in sel.split(",")}
    for need in ("article p", "article li", "article td", "article th", ".lead p", ".standfirst", ".callout", ".mark-src"):
        assert need in wrapping, need


def test_long_token_fixture_puts_tokens_everywhere():
    md = (HERE / "fixtures" / "long-tokens.md").read_text(encoding="utf-8")
    p = build(md)
    long = "aVeryLongUnbrokenPathSegmentWithoutAnySeparators"
    assert long in p["standfirst"]
    body = p["body"]
    for container in (r"<div class=\"lead\">", r"<li>A list item with", r"<td>", r"mark-src", r"footnote-item", r"callout--risk"):
        assert re.search(container, body), container
    assert re.search(r"<td><a [^>]*>https://example\.com/" + long, body)
    assert 'href="#h-%E6%97%A5%E6%9C%AC"' in body and 'id="h-日本"' in body


# ---------- round 4, finding 3: bold_only word and punctuation limits in isolation ----------

@pytest.mark.parametrize("label", [
    "Pricing tiers hosting regions storage quotas egress fees support plans",  # nine words
    "Ship Friday?",
    "Huge win!",
])
def test_bold_only_word_and_punctuation_limits(label):
    assert not B.SENTENCE_WORDS.search(label) and len(label) <= 70
    body = build(f"# T\n\nIntro.\n\n## A\n\n**{label}**\n\nMore.\n")["body"]
    assert "<h3" not in body
    assert f"<p><strong>{label}</strong></p>" in body


def test_eight_word_label_still_a_heading():
    label = "Pricing tiers hosting regions storage quotas egress fees"
    assert len(label.split()) == 8
    body = build(f"# T\n\nIntro.\n\n## A\n\n**{label}**\n\nMore.\n")["body"]
    assert f">{label}</h3>" in body


# ---------- round 4, finding 4: GitHub's dedup, explicit and generated suffixes ----------

@pytest.mark.parametrize("heads,links", [
    (["Risk", "Risk-1", "Risk"], {"risk": 0, "risk-1": 1, "risk-2": 2}),
    (["Risk", "Risk", "Risk-1"], {"risk": 0, "risk-1": 1, "risk-1-1": 2}),
    (["Options", "Options 1", "Options"], {"options": 0, "options-1": 1, "options-2": 2}),
])
def test_github_dedup_mirrors_github(heads, links):
    md = "# T\n\nIntro.\n\n## A\n\n" + " ".join(f"[{k}](#{k})" for k in links) + "\n\n"
    md += "".join(f"## {h}\n\nx\n\n" for h in heads)
    body = build(md)["body"]
    ids = re.findall(r'<h2 id="([^"]+)">(?!A<)', body)
    assert len(ids) == len(heads) == len(set(ids))
    for k, i in links.items():
        assert f'<a href="#{ids[i]}">{k}</a>' in body, k


# ---------- round 4, finding 5: percent-encoded fragments with JavaScript on ----------

NODE = shutil.which("node")

# A permissive DOM stand-in: every property is a callable stub, so the whole template script
# runs; getElementById records what it was asked for, addEventListener records handlers.
STUB_JS = r"""
const asked = [], handlers = [];
function stub() {
  const f = function () { return stub(); };
  return new Proxy(f, {
    get(t, k) {
      if (k === Symbol.toPrimitive) return () => 0;
      if (k === "length") return 0;
      if (k === "then") return undefined;
      if (k === "getElementById") return (id) => { asked.push(id); return id === "toc" ? stub() : null; };
      if (k === "addEventListener") return (type, fn) => handlers.push([type, fn]);
      if (k === "matches" || k === "open" || k === "hidden") return false;
      return stub();
    },
    set() { return true; },
    apply() { return stub(); },
  });
}
globalThis.document = stub(); globalThis.window = stub(); globalThis.localStorage = stub();
globalThis.history = { replaceState() {} }; globalThis.location = { hash: "" };
globalThis.getComputedStyle = () => stub(); globalThis.requestAnimationFrame = () => 0;
globalThis.setTimeout = () => 0; globalThis.clearTimeout = () => 0;
eval(require("fs").readFileSync(0, "utf8"));
const href = "#h-caf%C3%A9";
const anchor = { getAttribute: () => href };
for (const [type, fn] of handlers) {
  if (type !== "click") continue;
  try { fn({ target: { closest: () => anchor }, preventDefault() {} }); } catch (e) {}
}
console.log(JSON.stringify(asked.filter((x) => typeof x === "string" && x.startsWith("h-caf"))));
"""


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_click_handlers_decode_percent_encoded_fragments():
    script = re.findall(r"<script>([\s\S]*?)</script>", TEMPLATE)[-1]
    r = subprocess.run([NODE, "-e", STUB_JS], input=script, capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, r.stderr
    asked = json.loads(r.stdout.strip().splitlines()[-1])
    assert asked and set(asked) == {"h-café"}, asked


def test_encoded_href_kept_and_id_is_unicode():
    body = build("# T\n\nIntro.\n\n## A\n\n[go](#h-caf%C3%A9)\n\n## Café\n\nx\n")["body"]
    assert '<h2 id="h-café">Café</h2>' in body
    assert 'href="#h-caf%C3%A9"' in body  # native (no-JS) navigation decodes it


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-q", "-p", "no:cacheprovider", *sys.argv[1:]]))

#!/usr/bin/env python3
"""Check a call-prep page before it is handed over.

Usage: python3 check_prep.py <prep>.html [more.html ...]
Exit 0 when every page passes, 1 when any page fails, 2 on a usage or read error.

Fails a page when:
  1. a spoken line (.say) in a beat says something has been sent ("I've put it in Slack",
     "I've just emailed you", "the link is in the chat") and no visible send action (.act) by the
     same route (email, or a chat or channel) comes before it in the same beat, unless the line
     carries data-sent-before naming where and when it was sent before the call;
  2. a send action sits outside a beat (in the "What you send" panel or a section of its own);
  3. a send action has no content and copy button inside it (a .copy whose data-copy names a
     <pre> inside the same .act), unless it is an email draft (data-draft names the draft);
  4. a stage direction points at a key to reach content ("press c, copy ..."), or tells the
     caller to send, paste or post something somewhere with no send action in that beat;
  5. a placeholder ({{ ... }}) is left in, an id is used twice (a Copy button would copy the
     wrong text), or the page has no beats at all.

On a pass it prints the in-call send actions by beat, for the first lines of the chat handoff.
Standard library only; stdlib html.parser, so it reads the page as the browser does.
"""
import re
import sys
from html.parser import HTMLParser

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}
WHERE = r"(slack|the chat|chat|channel|thread|inbox|e-?mail|whatsapp|teams|dms?\b|#)"
SENT_PATTERNS = [
    # I've sent / I've just emailed / we've posted
    r"\b(i've|i have|we've|we have)\s+(just\s+)?(sent|emailed|e-mailed|posted|messaged|texted|forwarded|slacked|whatsapped|shared|uploaded|attached|pasted|dropped|popped)\b",
    # the link is in the chat
    r"\b(is|are)\s+(now\s+|already\s+|all\s+)?(in|on)\s+(the\s+|your\s+|our\s+)" + WHERE,
    # I just sent / we just put
    r"\b(i|we)\s+just\s+(sent|emailed|posted|messaged|texted|forwarded|shared|put|dropped|popped|pasted|added|uploaded)\b",
    # I've put / added / stuck it in Slack (put alone is "I've put that together", so it needs a place)
    r"\b(i've|i have|we've|we have)\s+(just\s+)?(put|added|stuck|pinned|left)\b[^.?!]{0,60}?\b(in|into|on|to)\s+(the\s+|your\s+|our\s+)?" + WHERE,
    # it's in the chat / everything's on Slack now
    r"\b(it's|it is|they're|they are|that's|that is|everything's|everything is|both are|all of it is)\s+(now\s+|already\s+|all\s+)?(in|on)\s+(the\s+|your\s+|our\s+)?" + WHERE,
    # check your email / have a look in the chat
    r"\b(check|look in|have a look in|open)\s+(your|the)\s+" + WHERE,
    # you should have it now
    r"\byou should (have|see|get|have got) (it|them|that|an email|a message|my message)\b",
]
SENT_RE = re.compile("|".join("(?:%s)" % p for p in SENT_PATTERNS), re.I)
# "I sent you the link in Slack": plain past with a place, counted only when it opens a sentence or clause, because
# "what I put in the email last week" and "the number I put in Slack" are history.
PLAIN_RE = re.compile(r"\b(i|we)\s+(sent|emailed|posted|messaged|texted|forwarded|shared|put|dropped|popped|pasted|added)\b[^.?!]{0,60}?\b(in|into|on|to|over)\s+(the\s+|your\s+|our\s+)?" + WHERE, re.I)
OPENS_RE = re.compile(r"(^|[.!?,;:]\s*|\b(so|and|ok|okay|right|now)\s+)$", re.I)
# "Once I've sent it" and "when the link is in the chat" are about later, not a claim it has gone.
COND_RE = re.compile(r"\b(once|when|whenever|after|if|until|as soon as|before)\b(\s+\S+){0,4}\s*$", re.I)
EMAIL_RE = re.compile(r"e-?mail|inbox|\bdraft\b", re.I)
# A direction that opens by telling the caller to send somewhere (quoted lines inside it are the counterpart's words).
DIR_SEND_RE = re.compile(r"^(then\s+|now\s+)?(paste|post|send|share|drop|put|copy)\b[^.]*?\b(in|into|to|on)\s+(the\s+|your\s+|our\s+)?" + WHERE, re.I)
KEY_RE = re.compile(r"\bpress\s+\S{1,3}\b[^.]*?\b(copy|paste)", re.I)
BEAT_KEY_RE = re.compile(r"^[1-9]$")


class Node:
    def __init__(self, tag, attrs, parent):
        self.tag, self.attrs, self.parent, self.children = tag, dict(attrs), parent, []
        self.classes = set((self.attrs.get("class") or "").split())

    def text(self):
        return "".join(c if isinstance(c, str) else c.text() for c in self.children)

    def walk(self):
        for c in self.children:
            if isinstance(c, Node):
                yield c
                yield from c.walk()


class Tree(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("#root", [], None)
        self.cur = self.root

    def handle_starttag(self, tag, attrs):
        n = Node(tag, attrs, self.cur)
        self.cur.children.append(n)
        if tag not in VOID:
            self.cur = n

    def handle_startendtag(self, tag, attrs):
        self.cur.children.append(Node(tag, attrs, self.cur))

    def handle_endtag(self, tag):
        n = self.cur
        while n is not self.root and n.tag != tag:
            n = n.parent
        if n is not self.root:
            self.cur = n.parent

    def handle_data(self, data):
        self.cur.children.append(data)


def norm(s):
    return re.sub(r"\s+", " ", s.replace("’", "'").replace("‘", "'")).strip()


def is_beat(n):
    return n.tag == "section" and ("beat" in n.classes or BEAT_KEY_RE.match(n.attrs.get("data-key", "") or ""))


def beat_name(sec):
    h = next((n for n in sec.walk() if n.tag == "h2"), None)
    label = norm(h.text()) if h else ""
    return "beat %s%s" % (sec.attrs.get("data-key") or sec.attrs.get("id") or "?", (" (" + label[:50] + ")") if label else "")


def hidden(n):
    while n is not None:
        style = (n.attrs.get("style") or "").replace(" ", "").lower()
        if "hidden" in n.attrs or "display:none" in style or "visibility:hidden" in style:
            return True
        n = n.parent
    return False


def route(text):
    return "email" if EMAIL_RE.search(text) else "chat"


def sent_claim(line):
    """The first phrase in the line that says something has already gone, or None."""
    for m in SENT_RE.finditer(line):
        if not COND_RE.search(line[max(0, m.start() - 40):m.start()]):
            return m
    for m in PLAIN_RE.finditer(line):
        before = line[:m.start()].lstrip("\"'\u201c ")
        if OPENS_RE.search(before) and not COND_RE.search(before[-40:]):
            return m
    return None


def check(html):
    """Return (failures, sends): failures as strings, sends as (beat, what) pairs."""
    fails, sends = [], []
    if "{{" in html:
        fails.append("%d placeholder(s) left in ({{ ... }})" % html.count("{{"))
    t = Tree()
    t.feed(html)
    t.close()
    nodes = list(t.root.walk())
    beats = [n for n in nodes if is_beat(n)]
    if not beats:
        fails.append("no beats found (a <section> with class beat or a digit data-key); an empty or cut-off page never passes")
    ids = {}
    for n in nodes:
        i = n.attrs.get("id")
        if i:
            ids[i] = ids.get(i, 0) + 1
    for i, c in sorted(ids.items()):
        if c > 1:
            fails.append('id "%s" is used %d times; a Copy button finds the first one, so it may copy the wrong text' % (i, c))
    in_beat = set()
    for b in beats:
        for n in b.walk():
            in_beat.add(id(n))

    for n in nodes:
        if "act" in n.classes and id(n) not in in_beat:
            sec = n.parent
            while sec is not None and sec.tag != "section":
                sec = sec.parent
            where = sec.attrs.get("id", "?") if sec is not None else "the page"
            fails.append("send action outside a beat (in #%s); put it in the beat where it is sent: %s" % (where, norm(n.text())[:80]))

    for b in beats:
        name = beat_name(b)
        routes = set()
        any_act = any("act" in n.classes and not hidden(n) for n in b.walk())
        for n in b.walk():
            if "act" in n.classes:
                if hidden(n):
                    fails.append("%s: a send action is hidden; it must show on the page where it is read" % name)
                    continue
                what = ""
                for x in n.walk():
                    if "act-what" in x.classes:
                        what = norm("".join(c if isinstance(c, str) else ("" if "act-pill" in c.classes else c.text()) for c in x.children))
                        break
                what = what or norm(n.text())[:80]
                sends.append((name, what))
                routes.add("email" if (n.attrs.get("data-draft") or "").strip() else route(what))
                if not (n.attrs.get("data-draft") or "").strip():
                    pres = {p.attrs.get("id"): p for p in n.walk() if p.tag == "pre" and p.attrs.get("id")}
                    copies = [c for c in n.walk() if c.tag == "button" and "copy" in c.classes and c.attrs.get("data-copy") in pres]
                    if not copies or not any(norm(pres[c.attrs["data-copy"]].text()) for c in copies):
                        fails.append("%s: send action has no content and copy button inside it (a <pre id> and a .copy naming it, or data-draft for an email draft): %s" % (name, what[:80]))
            elif "say" in n.classes:
                line = norm(n.text())
                m = sent_claim(line)
                if m and route(line) not in routes and not (n.attrs.get("data-sent-before") or "").strip():
                    fails.append('%s: the line says it has been sent ("%s") but no send action by %s comes before it in this beat: "%s"'
                                 % (name, m.group(0), "email" if route(line) == "email" else "chat or channel", line[:120]))
            elif "dir" in n.classes:
                line = norm(n.text())
                if KEY_RE.search(line):
                    fails.append('%s: a direction points at a key for the content; put the content and its Copy button in the beat as a send action: "%s"' % (name, line[:120]))
                elif DIR_SEND_RE.search(re.sub(r'"[^"]*"|\u201c[^\u201d]*\u201d', "", line).strip()) and not any_act:
                    fails.append('%s: a direction has the caller send something, with no send action in this beat: "%s"' % (name, line[:120]))
    return fails, sends


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    bad = 0
    for path in argv[1:]:
        try:
            html = open(path, encoding="utf-8").read()
        except OSError as e:
            print("check_prep: cannot read %s: %s" % (path, e), file=sys.stderr)
            return 2
        fails, sends = check(html)
        if fails:
            bad += 1
            print("FAIL %s" % path)
            for f in fails:
                print("  - " + f)
        else:
            print("ok   %s" % path)
            if sends:
                print("  In-call sends, by beat (list these first in the chat handoff):")
                for beat, what in sends:
                    print("  - %s: %s" % (beat, what))
            else:
                print("  No in-call sends.")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

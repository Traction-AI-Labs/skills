#!/usr/bin/env python3
"""Check a call-prep page before it is handed over.

Usage: python3 check_prep.py <prep>.html [more.html ...]
Exit 0 when every page passes, 1 when any page fails, 2 on a usage or read error.

Fails a page when:
  1. a line the caller says (a .say line, a fallback quoted in a direction as theirs, an answer in
     the "If they..." table) says something has been sent ("I've put it in Slack", "I've just emailed
     you", "the link is in the chat") and no visible send action (.act) by the same route (an email
     draft, or a chat or channel copy box) comes before it in the same beat, or in the same answer
     under "Answer if asked", unless the line carries data-sent-before naming where and when it went;
  2. a send action sits outside a beat or "Answer if asked" (in the panel or a section of its own);
  3. a send action is hidden, lacks its visible .act-what line with the Send now pill, or has no
     content and visible, enabled Copy button inside it (a <button class=copy> whose data-copy names
     a <pre> inside the same .act); an email draft (data-draft) instead names its draft visibly;
  4. a stage direction points at a key to reach content ("press c, copy ..."), or tells the
     caller to send, paste or post something with no send action of that kind straight after it; a line
     outside the beats (the panel, a heading) points at a key for content; or a spoken line outside
     the beats ("Answer if asked") claims a send;
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
ART = r"(the\s+|your\s+|our\s+|my\s+)?"
SENT_PATTERNS = [
    # I've sent / I've just emailed / we've posted (shared needs a place: "I've shared my screen" sends nothing)
    r"\b(i've|i have|we've|we have)\s+(just\s+)?(sent|emailed|e-mailed|posted|messaged|texted|forwarded|slacked|whatsapped|uploaded|attached|pasted|dropped|popped)\b",
    # I just sent / we just put
    r"\b(i|we)\s+just\s+(sent|emailed|posted|messaged|texted|forwarded|put|dropped|popped|pasted|added|uploaded)\b",
    # I've put / added / shared it in Slack (put alone is "I've put that together", so these need a place)
    r"\b(i've|i have|we've|we have)\s+(just\s+)?(put|added|stuck|pinned|left|shared)\b[^.?!]{0,60}?\b(in|into|on|to)\s+" + ART + WHERE,
    # the link is in the chat / the notes are in Slack / it's in the chat
    r"\b(is|are|it's|they're|that's|everything's)\s+(now\s+|already\s+|all\s+)?(in|on)\s+" + ART + WHERE,
    # check your email / have a look in the chat
    r"\b(check|look in|have a look in)\s+(your|the)\s+" + WHERE,
    # you should have it now
    r"\byou should (have|see|get|have got) (it|them|that|an email|a message|my message)\b",
]
SENT_RE = re.compile("|".join("(?:%s)" % p for p in SENT_PATTERNS), re.I)
# Plain past, counted only when it opens a sentence or clause, because "what I put in the email last week" and "the
# number I put in Slack" are history. Email-type verbs carry their own route; put, sent and the rest need a place.
PLAIN_RE = re.compile(r"\b(i|we)\s+(?:(?:emailed|texted|messaged|whatsapped|slacked)\b|(?:sent|posted|forwarded|shared|put|dropped|popped|pasted|added)\b[^.?!]{0,60}?\b(?:in|into|on|to|over)\s+" + ART + WHERE + ")", re.I)
OPENS_RE = re.compile(r"(^|[.!?,;:]\s*|\b(so|and|ok|okay|right|now)\s+)$", re.I)
# "Once I've sent it" and "when the link is in the chat" are about later. Read only within the claim's own clause, so
# "Before we start, I have sent the notes" is still a claim.
COND_RE = re.compile(r"\b(once|when|whenever|after|if|until|as soon as|before)\b(\s+\S+){0,4}\s*$", re.I)
EMAIL_RE = re.compile(r"e-?mail|inbox", re.I)
CHAT_RE = re.compile(r"\bslack\b|\bchat\b|\bchannel\b|\bthread\b|\bwhatsapp\b|(?-i:\bTeams\b)|\bdms?\b|#\S", re.I)
EMAIL_VERB_RE = re.compile(r"\be-?mailed\b", re.I)
# A direction that opens by telling the caller to send somewhere (quoted text inside it is set aside first).
DIR_SEND_RE = re.compile(r"^(then\s+|now\s+)?(paste|post|send|share|drop|put|copy)\b[^.]*?\b(in|into|to|on)\s+" + ART + WHERE, re.I)
# A direction to send an email draft ("open the draft and press Send").
DIR_DRAFT_RE = re.compile(r"^(then\s+|now\s+)?(open|send)\s+(the\s+|your\s+)?(e-?mail\s+)?(draft|e-?mail)\b", re.I)
# A pointer to a page key that leads to content ("press c, copy ..."); a keyboard shortcut like Cmd-V is not one.
KEY_RE = re.compile(r"\bpress\s+[a-z0-9]\b[^.]*?\b(copy|paste)", re.I)
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


def is_answers(n):
    return n.tag == "section" and (n.attrs.get("id") == "answers" or n.attrs.get("data-key") == "a")


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


def route(match, tail):
    """A claim's route. An email verb in the claim ("I've emailed both teams") is email; a chat or channel named in the
    claim ("the link to the email is in the chat") is chat; an email named in the claim ("check your email") is email.
    Otherwise the first route the rest of the sentence names ("I've sent you the notes, by email"), else chat."""
    if EMAIL_VERB_RE.search(match):
        return "email"
    if CHAT_RE.search(match):
        return "chat"
    if EMAIL_RE.search(match):
        return "email"
    c, e = CHAT_RE.search(tail), EMAIL_RE.search(tail)
    if e and (not c or e.start() < c.start()):
        return "email"
    return "chat"


def clause_before(line, start):
    """The text of the claim's own clause before it (from the last comma, semicolon or full stop)."""
    head = line[:start]
    return re.split(r"[,;.!?:]", head)[-1]


def sent_claims(line):
    """Every phrase in the line that says something has already gone, as (match, route) pairs."""
    out = []
    for m in SENT_RE.finditer(line):
        if not COND_RE.search(clause_before(line, m.start())):
            out.append(m)
    for m in PLAIN_RE.finditer(line):
        before = line[:m.start()].lstrip("\"'“ ")
        if OPENS_RE.search(before) and not COND_RE.search(clause_before(line, m.start())):
            out.append(m)
    # A claim's route is read from the claim and the rest of its own clause ("I've sent you the notes by email"),
    # never from a later clause ("The link is in the chat and I have emailed the notes" holds two claims).
    return [(m, route(m.group(0), re.split(r"[.!?]", line[m.end():])[0])) for m in out]


# A quote in a direction is the caller's line when it is introduced as one ('If pushed: "..."', 'say "..."'), never
# when it is someone else's words ('If they say "..."', 'He posted: "..."').
MINE_RE = re.compile(r"(if pushed|fallback|\bsay\b|\btell (him|her|them)\b|\breply\b)[^\"\u201c]{0,40}$", re.I)
THEIRS_RE = re.compile(r"\b(he|she|they|him|her|them)\s+(may |might |will |would )?(say|says|said|asks?|asked|posted|wrote|writes)\b[^\"\u201c]{0,20}$", re.I)


def quoted(text, mine_only=False):
    """Spoken lines quoted inside a direction or a table cell. With mine_only, only quotes introduced as the caller's."""
    out = []
    for m in re.finditer(r'"([^"]+)"|\u201c([^\u201d]+)\u201d', text):
        before = text[:m.start()]
        if mine_only and (not MINE_RE.search(before) or THEIRS_RE.search(before)):
            continue
        out.append(m.group(1) or m.group(2))
    return out


def visible_text(n):
    return "".join(c if isinstance(c, str) else ("" if hidden(c) else visible_text(c)) for c in n.children)


def own_text(n):
    """The node's text without the text of nested block elements, for scanning short lines like list items."""
    return norm("".join(c if isinstance(c, str) else (c.text() if c.tag in ("b", "i", "em", "strong", "code", "kbd", "a", "span", "small") else "") for c in n.children))


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
    # Send actions belong in a beat, or in "Answer if asked" directly above the answer that needs them.
    holders = beats + [n for n in nodes if is_answers(n) and not is_beat(n)]
    in_beat = set()
    for b in holders:
        for n in b.walk():
            in_beat.add(id(n))

    def say_line(n, name, routes, line=None):
        line = norm(n.text()) if line is None else norm(line)
        if (n.attrs.get("data-sent-before") or "").strip():
            return
        for m, r in sent_claims(line):
            if r not in routes:
                fails.append('%s: the line says it has been sent ("%s") but no send action by %s comes before it in this beat: "%s"'
                             % (name, m.group(0), "email" if r == "email" else "chat or channel", line[:120]))

    # Outside the beats: no send actions, no key pointers for content, and no line the caller reads aloud that claims
    # a send (a .say line, or a quoted line in a direction or an "If they..." table cell).
    for n in nodes:
        if id(n) in in_beat:
            continue
        if "act" in n.classes:
            sec = n.parent
            while sec is not None and sec.tag != "section":
                sec = sec.parent
            where = sec.attrs.get("id", "?") if sec is not None else "the page"
            fails.append("send action outside a beat or \"Answer if asked\" (in #%s); put it in the beat where it is sent: %s" % (where, norm(n.text())[:80]))
        elif "say" in n.classes:
            sec = n.parent
            while sec is not None and sec.tag != "section":
                sec = sec.parent
            say_line(n, "#%s" % (sec.attrs.get("id", "?") if sec is not None else "page"), set())
        else:
            if n.tag in ("p", "li", "span", "small", "h2", "h3", "h4") and KEY_RE.search(own_text(n)):
                fails.append('a line outside the beats points at a key for content; point at the beat that holds the send action: "%s"' % own_text(n)[:120])
            sec = n.parent
            while sec is not None and sec.tag != "section":
                sec = sec.parent
            in_ifthey = sec is not None and sec.attrs.get("id") == "ifthey"
            # The "If they..." table's answer cells (every cell after the first in a row) are lines the caller says.
            row_cells = [c for c in n.parent.children if isinstance(c, Node) and c.tag == "td"] if n.tag == "td" and n.parent else []
            if "dir" in n.classes or (in_ifthey and row_cells and row_cells[0] is not n):
                for q in quoted(n.text(), mine_only="dir" in n.classes):
                    say_line(n, "#%s" % (sec.attrs.get("id", "?") if sec is not None else "page"), set(), q)

    for b in holders:
        name = beat_name(b) if is_beat(b) else "#%s" % (b.attrs.get("id") or "answers")
        routes = set()
        # The lines of the holder in reading order, so a direction to send can be matched to the action after it.
        lines = [n for n in b.walk() if n.classes & {"act", "say", "dir"} or "q" in n.classes]
        for n in b.walk():
            if "q" in n.classes and not is_beat(b):
                # Each answer under "Answer if asked" is said only if its question comes up: its sends are its own.
                routes = set()
            elif "act" in n.classes:
                if hidden(n):
                    fails.append("%s: a send action is hidden; it must show on the page where it is read" % name)
                    continue
                aw = next((x for x in n.walk() if "act-what" in x.classes and not hidden(x)), None)
                pill = aw is not None and any("act-pill" in x.classes and not hidden(x) and norm(x.text()) for x in aw.walk())
                what = norm("".join(c if isinstance(c, str) else ("" if "act-pill" in c.classes or hidden(c) else visible_text(c)) for c in aw.children)) if aw else ""
                if not (pill and what):
                    fails.append("%s: a send action needs its visible .act-what line, with the Send now pill and where it goes: %s" % (name, norm(n.text())[:80]))
                    what = what or norm(n.text())[:80]
                sends.append((name, what))
                draft = (n.attrs.get("data-draft") or "").strip()
                # The route is the action's kind: an email draft, or text copied into a chat or channel.
                routes.add("email" if draft else "chat")
                if draft and norm(draft).lower() not in what.lower():
                    fails.append('%s: an email send action must name its draft so it can be found; put "%s" in its .act-what line' % (name, draft))
                if not draft:
                    pres = {p.attrs.get("id"): p for p in n.walk() if p.tag == "pre" and p.attrs.get("id")}
                    copies = [c for c in n.walk() if c.tag == "button" and "copy" in c.classes and not hidden(c)
                              and "disabled" not in c.attrs
                              and c.attrs.get("data-copy") in pres and norm(pres[c.attrs["data-copy"]].text())]
                    if not copies:
                        fails.append("%s: send action has no content and visible Copy button inside it (a <pre id> and a <button class=copy> naming it, or data-draft for an email draft): %s" % (name, what[:80]))
            elif "say" in n.classes:
                say_line(n, name, routes)
            elif "dir" in n.classes:
                line = norm(n.text())
                for q in quoted(line, mine_only=True):
                    say_line(n, name, routes, q)
                if KEY_RE.search(line):
                    fails.append('%s: a direction points at a key for the content; put the content and its Copy button in the beat as a send action: "%s"' % (name, line[:120]))
                elif any(r.search(re.sub(r'"[^"]*"|“[^”]*”', "", line).strip()) for r in (DIR_SEND_RE, DIR_DRAFT_RE)):
                    i = lines.index(n)
                    nxt = lines[i + 1] if i + 1 < len(lines) else None
                    wants_draft = DIR_DRAFT_RE.search(re.sub(r'"[^"]*"|\u201c[^\u201d]*\u201d', "", line).strip())
                    if nxt is None or "act" not in nxt.classes or hidden(nxt) or (wants_draft and not (nxt.attrs.get("data-draft") or "").strip()):
                        fails.append('%s: a direction has the caller send something, with no send action straight after it: "%s"' % (name, line[:120]))
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

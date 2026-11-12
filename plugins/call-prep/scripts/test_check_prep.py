#!/usr/bin/env python3
"""Tests for check_prep.py. Run from the repository root: python3 -I -B plugins/call-prep/scripts/test_check_prep.py"""
import os
import re
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.join(HERE, "..", "skills", "call-prep")
sys.path.insert(0, os.path.join(SKILL, "scripts"))
import check_prep  # noqa: E402

TEMPLATE = os.path.join(SKILL, "references", "prep-template.html")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def page(beat_body, extra=""):
    return ('<html><body><main><section id="send" data-key="s"><h2>What you send</h2>%s</section>'
            '<section id="b1" data-key="1" class="beat"><h2>1. Open</h2>%s</section></main></body></html>' % (extra, beat_body))


ACT = ('<div class="act"><p class="act-what"><span class="act-pill">Send now</span>Paste into the meeting chat</p>'
       '<div class="copybox"><pre id="c1">Here is the link</pre><button class="copy" data-copy="c1">Copy</button></div></div>')
SAY_SENT = '<p class="say">"I\'ve put the link in the chat."</p>'


class TheIncident(unittest.TestCase):
    """The case the check was written for: a direction to press a key for a message kept in another section,
    then a line saying it is already in the chat. The same page with the message as a send action passes."""

    def pages(self):
        filled = re.sub(r"\{\{[^}]*\}\}", "x", read(TEMPLATE))
        act = re.search(r'<div class="act">.*?</div></div>', filled, re.S).group(0)
        sent = '<p class="say">"I\'ve put everything for today in the chat. Paste the first one into your session."</p>'
        bad = filled.replace(act, '<p class="dir">Press c, copy the session message, paste it into the chat and send.</p>', 1)
        bad = bad.replace('<p class="say">"x"</p>\n</section>', sent + "\n</section>", 1)
        bad = bad.replace("</main>", '<section id="prompts" data-key="c"><h2>Prompts</h2><pre>message</pre></section></main>', 1)
        good = filled.replace('<p class="say">"x"</p>\n</section>', sent + "\n</section>", 1)
        return bad, good

    def test_incident_fails_and_fixed_passes(self):
        bad, good = self.pages()
        fails = check_prep.check(bad)[0]
        self.assertTrue(any("no send action by" in f for f in fails), fails)
        self.assertTrue(any("points at a key" in f for f in fails), fails)
        self.assertEqual(check_prep.check(good)[0], [])

    def test_cli_exit_codes(self):
        bad, good = self.pages()
        d = tempfile.mkdtemp()
        for name, html in (("bad.html", bad), ("good.html", good)):
            with open(os.path.join(d, name), "w", encoding="utf-8") as f:
                f.write(html)
        run = lambda f: subprocess.run([sys.executable, "-I", os.path.join(SKILL, "scripts", "check_prep.py"), os.path.join(d, f)],
                                       capture_output=True, text=True)
        self.assertEqual(run("bad.html").returncode, 1)
        ok = run("good.html")
        self.assertEqual(ok.returncode, 0, ok.stdout)
        self.assertIn("In-call sends, by beat", ok.stdout)


class SentLines(unittest.TestCase):
    def fails(self, html):
        return check_prep.check(html)[0]

    def test_sent_line_without_action_fails(self):
        self.assertTrue(self.fails(page(SAY_SENT)))

    def test_action_after_the_line_still_fails(self):
        self.assertTrue(self.fails(page(SAY_SENT + ACT)))

    def test_action_before_the_line_passes(self):
        self.assertEqual(self.fails(page(ACT + SAY_SENT)), [])

    def test_action_in_another_beat_does_not_count(self):
        html = page(SAY_SENT).replace("</main>", '<section id="b2" data-key="2" class="beat"><h2>2. Next</h2>%s</section></main>' % ACT)
        self.assertTrue(any("no send action by" in f for f in self.fails(html)))

    def test_phrasings(self):
        for line in ["I've just emailed you the notes.", "I've sent it over.", "I just posted it in the channel.",
                     "It's in the chat now.", "Everything's on Slack.", "Check your email, it should be there.",
                     "I've dropped the link in Teams.", "You should have it now."]:
            self.assertTrue(self.fails(page('<p class="say">"%s"</p>' % line)), line)

    def test_no_false_positives(self):
        for line in ["I've put that together, and the way I've done it is in stages.", "I'll put it all on Slack after the call.",
                     "So there was a prompt I sent you called scheduled tasks.", "Can you share your screen?",
                     "Paste the first one into your session.", "I've added a section on testing."]:
            self.assertEqual(self.fails(page('<p class="say">"%s"</p>' % line)), [], line)

    def test_sent_before_the_call_passes_only_when_named(self):
        named = '<p class="say" data-sent-before="readiness message, 30 Oct 13:30">"I\'ve sent you the readiness check."</p>'
        self.assertEqual(self.fails(page(named)), [])
        self.assertTrue(self.fails(page(named.replace('readiness message, 30 Oct 13:30', ' '))))


class Actions(unittest.TestCase):
    def test_action_outside_a_beat_fails(self):
        fails, _ = check_prep.check(page("", extra=ACT))
        self.assertTrue(any("outside a beat" in f for f in fails), fails)

    def test_action_without_content_fails(self):
        bare = '<div class="act"><p class="act-what"><span class="act-pill">Send now</span>Paste the prompt</p></div>'
        self.assertTrue(check_prep.check(page(bare + SAY_SENT))[0])

    def test_copy_button_must_name_a_pre_in_the_action(self):
        broken = ACT.replace('data-copy="c1"', 'data-copy="elsewhere"')
        self.assertTrue(check_prep.check(page(broken))[0])

    def test_email_draft_action_passes(self):
        draft = ('<div class="act" data-draft="Notes from today"><p class="act-what"><span class="act-pill">Send now</span>'
                 'Open the draft and press Send</p></div>')
        self.assertEqual(check_prep.check(page(draft + '<p class="say">"I\'ve just emailed you the notes."</p>'))[0], [])

    def test_key_direction_fails(self):
        self.assertTrue(check_prep.check(page('<p class="dir">Press c, copy the message and paste it in Slack.</p>'))[0])

    def test_unclassed_beat_by_digit_key(self):
        html = page(SAY_SENT).replace('class="beat"', "")
        self.assertTrue(check_prep.check(html)[0])


class PreReviewFindings(unittest.TestCase):
    """One case per finding from the 12 Nov pre-review of the check."""

    def fails(self, html):
        return check_prep.check(html)[0]

    def test_plain_past_with_a_place_and_named_subject(self):
        for line in ["I sent you the link in Slack.", "The link is in the chat."]:
            self.assertTrue(self.fails(page('<p class="say">"%s"</p>' % line)), line)

    def test_a_chat_send_does_not_cover_an_email_claim(self):
        self.assertTrue(self.fails(page(ACT + '<p class="say">"I have just emailed you the contract."</p>')))
        draft = ('<div class="act" data-draft="Contract"><p class="act-what"><span class="act-pill">Send now</span>'
                 'Open the draft and press Send</p></div>')
        self.assertEqual(self.fails(page(ACT + draft + '<p class="say">"I have just emailed you the contract."</p>')), [])

    def test_direction_to_send_needs_an_action(self):
        d = '<p class="dir">Paste the brief into Slack and send it.</p>'
        self.assertTrue(any("direction has the caller send" in f for f in self.fails(page(d))))
        self.assertEqual(self.fails(page(d + ACT)), [])

    def test_duplicate_ids_fail(self):
        self.assertTrue(any("used 2 times" in f for f in self.fails(page(ACT, extra='<pre id="c1">Wrong earlier text</pre>'))))

    def test_hidden_action_and_non_button_copy_fail(self):
        self.assertTrue(self.fails(page('<div hidden>' + ACT + '</div>' + SAY_SENT)))
        self.assertTrue(self.fails(page(ACT.replace('<button class="copy"', '<span class="copy"').replace("</button>", "</span>") + SAY_SENT)))

    def test_future_and_conditional_lines_pass(self):
        for line in ["Once I have sent the notes, we can discuss them.", "When the link is in the chat, open it."]:
            self.assertEqual(self.fails(page('<p class="say">"%s"</p>' % line)), [], line)

    def test_empty_or_beatless_page_fails(self):
        self.assertTrue(self.fails(""))
        self.assertTrue(self.fails("<html><body><main><section id='send'></section></main></body></html>"))


class Template(unittest.TestCase):
    def test_filled_template_passes_and_lists_its_send(self):
        html = read(TEMPLATE)
        self.assertTrue(check_prep.check(html)[0], "an unfilled template must fail on its placeholders")
        filled = re.sub(r"\{\{[^}]*\}\}", "x", html)
        fails, sends = check_prep.check(filled)
        self.assertEqual(fails, [])
        self.assertEqual([b for b, _ in sends], ["beat 1 (1. x (x))"])


if __name__ == "__main__":
    unittest.main()

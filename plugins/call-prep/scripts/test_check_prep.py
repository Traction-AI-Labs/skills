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
        self.assertNotEqual(bad, filled)
        self.assertIn(sent, bad)
        self.assertIn("Press c", bad)
        self.assertIn('id="prompts"', bad)
        self.assertIn(sent, good)
        self.assertLess(good.index('class="act"'), good.index(sent))
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
        draft = ('<div class="act" data-draft="Notes from today"><p class="act-what"><span class="act-pill">Send now</span>Open the draft \'Notes from today\' and press Send</p></div>')
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
        draft = ('<div class="act" data-draft="Contract"><p class="act-what"><span class="act-pill">Send now</span>Open the draft \'Contract\' and press Send</p></div>')
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


class RoundOneFindings(unittest.TestCase):
    """One case per finding from gauntlet round 1 on the check."""

    def fails(self, html):
        return check_prep.check(html)[0]

    def test_more_sent_phrasings(self):
        for line in ["I emailed you the notes.", "The notes are in Slack.", "Before we start, I have sent the notes."]:
            self.assertTrue(self.fails(page('<p class="say">"%s"</p>' % line)), line)

    def test_lines_that_send_nothing_pass(self):
        for line in ["I've shared my screen, can you see it?", "Can you open the chat?"]:
            self.assertEqual(self.fails(page('<p class="say">"%s"</p>' % line)), [], line)

    def test_keyboard_shortcut_is_not_a_page_key(self):
        self.assertEqual(self.fails(page(ACT + '<p class="dir">Click into the chat, press \u2318V to paste, then Enter.</p>')), [])

    def test_each_claim_in_a_line_needs_its_own_route(self):
        draft = ('<div class="act" data-draft="Notes"><p class="act-what"><span class="act-pill">Send now</span>Open the draft \'Notes\' and press Send</p></div>')
        line = '<p class="say">"I have emailed the notes. The link is in the chat."</p>'
        self.assertTrue(any("by chat or channel" in f for f in self.fails(page(draft + line))))
        self.assertEqual(self.fails(page(draft + ACT + line)), [])

    def test_spoken_lines_outside_beats_are_checked(self):
        answers = '<section id="answers" data-key="a"><h2>Answer if asked</h2>%s</section></main>'
        self.assertTrue(self.fails(page("").replace("</main>", answers % SAY_SENT)))
        ok = '<p class="say" data-sent-before="homework email, 29 Oct 17:40">"I\'ve emailed you the homework."</p>'
        self.assertEqual(self.fails(page("").replace("</main>", answers % ok)), [])

    def test_hidden_copy_button_and_missing_act_what_fail(self):
        self.assertTrue(self.fails(page(ACT.replace('<button class="copy"', '<button hidden class="copy"') + SAY_SENT)))
        self.assertTrue(self.fails(page(re.sub(r'<p class="act-what">.*?</p>', "", ACT) + SAY_SENT)))

    def test_panel_line_pointing_at_a_key_fails(self):
        panel = '<ul><li><b>At the start of beat 3:</b> one message (press <code>c</code>, Copy on the first block, paste into the channel, send).</li></ul>'
        self.assertTrue(any("outside the beats points at a key" in f for f in self.fails(page(ACT, extra=panel))))


class DocRoundFindings(unittest.TestCase):
    def fails(self, html):
        return check_prep.check(html)[0]

    def test_answers_may_hold_a_send_action(self):
        answers = '<section id="answers" data-key="a"><h2>Answer if asked</h2>%s</section></main>'
        self.assertEqual(self.fails(page("").replace("</main>", answers % (ACT + SAY_SENT))), [])
        self.assertTrue(self.fails(page("").replace("</main>", answers % (SAY_SENT + ACT))))

    def test_direction_to_send_a_draft_needs_an_action(self):
        self.assertTrue(any("direction has the caller send" in f for f in self.fails(page('<p class="dir">Open the draft and press Send.</p>'))))


class PublishedRoundFindings(unittest.TestCase):
    """One case per finding from the gauntlet round on the published cut."""

    def fails(self, html):
        return check_prep.check(html)[0]

    def answers(self, inner):
        return page("").replace("</main>", '<section id="answers" data-key="a"><h2>Answer if asked</h2>%s</section></main>' % inner)

    def test_each_answer_keeps_its_own_sends(self):
        two = '<p class="q">"Where is it?"</p>' + ACT + '<p class="say">"It\'s here."</p><p class="q">"Did you send it?"</p>' + SAY_SENT
        self.assertTrue(any("#answers" in f for f in self.fails(self.answers(two))))

    def test_quoted_fallbacks_and_table_lines_are_read(self):
        self.assertTrue(self.fails(page('<p class="dir">If pushed: "I have emailed you the notes."</p>')))
        table = '<section id="ifthey"><h2>If they</h2><table><tr><td>go quiet</td><td>"I\'ve put it in the chat."</td></tr></table></section></main>'
        self.assertTrue(any("#ifthey" in f for f in self.fails(page("").replace("</main>", table))))

    def test_a_direction_needs_the_send_action_straight_after_it(self):
        d = '<p class="dir">Paste the brief into Slack and send it.</p>'
        self.assertTrue(self.fails(page(ACT + d + SAY_SENT)))
        self.assertEqual(self.fails(page(d + ACT + SAY_SENT)), [])

    def test_claim_route_comes_from_its_own_clause(self):
        draft = ('<div class="act" data-draft="Notes"><p class="act-what"><span class="act-pill">Send now</span>'
                 "Open the draft 'Notes' and press Send</p></div>")
        self.assertTrue(any("by chat or channel" in f for f in self.fails(page(draft + '<p class="say">"The link is in the chat and I have emailed the notes."</p>'))))
        self.assertEqual(self.fails(page(ACT + '<p class="say">"I\'ve put the link to the draft in the chat."</p>')), [])
        self.assertEqual(self.fails(page(ACT + '<p class="say">"The link is in the chat and we can discuss the email later."</p>')), [])

    def test_send_line_and_button_must_be_usable(self):
        self.assertTrue(self.fails(page(ACT.replace('<p class="act-what">', '<p class="act-what" hidden>') + SAY_SENT)))
        self.assertTrue(self.fails(page(ACT.replace('<button class="copy"', '<button disabled class="copy"') + SAY_SENT)))
        self.assertTrue(self.fails(page(ACT.replace('<span class="act-pill">Send now</span>', "") + SAY_SENT)))
        self.assertTrue(self.fails(page(ACT.replace("Here is the link", " ") + SAY_SENT)))
        self.assertTrue(self.fails(page('<div style="display: none">' + ACT + "</div>" + SAY_SENT)))

    def test_email_action_names_its_draft(self):
        bare = ('<div class="act" data-draft="Notes from today"><p class="act-what"><span class="act-pill">Send now</span>'
                "Open the draft and press Send</p></div>")
        self.assertTrue(any("must name its draft" in f for f in self.fails(page(bare))))

    def test_plain_past_mid_sentence_is_history(self):
        self.assertEqual(self.fails(page('<p class="say">"So the plan is what I put in the email last week."</p>')), [])


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

# Client-facing drafts: the two-leg review and the derivation ledger (canonical procedure)

This file is the one canonical statement of the procedure; the doc-gauntlet product-lens persona points here and does not paraphrase it.

## The rule

**Anything drafted or generated for a client or counterpart that carries numbers, money, a claim about what happened, or an ask they must act on** (a message, and equally a sheet, form or export a script produced) gets one adversarial review by a separate fresh reviewer before it is handed to the person who will send it: in Claude, a `general-purpose` subagent with explicit `model: opus`, never a `fork` (a fork inherits this session's context and ignores the model, which voids the review); in Codex, the configured high-capability read-only review route. The reviewer re-opens every source, checks every figure and claim against what the recipient already knows and has been told, and, when the draft asks them to do something, attempts that task cold as the recipient. **The derivation ledger (set 11 Sep 2026, after two cold reads passed a client message whose row count, row list and a dropdown option name were wrong; the reviewers had been handed the author's counts and layout description and checked against those instead of the sheet).** Two legs, in order, each a fresh reviewer with no inherited author context (in Claude, leg one a Sonnet subagent and leg two a `general-purpose` subagent with explicit `model: opus`, never a fork; in Codex the configured high-capability read-only review route). Leg one, derivation: the reviewer receives only the source of truth (by id or path, with read commands that address the whole source with no row or range bound and expose every dimension the manifest touches, not values alone: dropdown option lists, dimensions, hidden and filtered state, colour rules, every tab; dry-run by the author under the credentials leg one will use, so they are known to work; an item the commands cannot expose is a cannot-derive, not a guess) and a value-free manifest: one line per checkable thing the draft carries, stating what it means and the rule that produces it from the source ("every row on the Labelling tab whose status cell is empty and whose agreement cell is not agree", "the exact option strings in the type dropdown on the Document types tab", "every row on either tab with a document link, recording the row and the linked filename"), never a result. A manifest line names the tab, column, field and condition and never a row window or any other bound on the source. Outside the source itself, its locator, and the tab, column, field and predicate terms a manifest line needs, no author-supplied result or candidate value appears anywhere in leg one's input: no count, range, total, option name, filename, row list or description of what the source contains, not in the brief, not in task context, not in a command bound. Whole source means a pinned snapshot extent or a completed traversal, with the revision and the completion evidence recorded in the ledger; the author never chooses the window. The leg writes a ledger, one line per item with the value and the derivation shown; batching is fine, sampling is forbidden; an item it cannot derive is recorded as such. Leg two, the review: the reviewer receives the draft, the ledger and the source, reconciles every figure, range, row or line reference, column letter, option string and filename in the draft against the ledger one to one, re-enumerates the draft's own checkable claims and reports any the manifest missed, derives the complete population of every list or set the draft states and reports missing, extra or duplicate members, checks that each manifest line's predicate implements the draft claim it stands for (a predicate that counts the wrong thing gives a clean ledger for a wrong draft; a mismatch means a corrected manifest and a fresh leg one), and then runs the cold task as the recipient. Every wrong value, every missing, extra or duplicate member, every manifest gap, every predicate that does not implement its claim, and every item leg one could not derive is a P1. A wrong value with its derivation shown, a missing, extra or duplicate member, and a manifest gap are applied as found, never dispositioned by the author; a gap is closed only by adding the manifest line and re-running leg one. Leg one writes the ledger to a path the author does not edit; an edited ledger is a re-run. The ledger is gate evidence the final figures check reads later, so that path is in the project's own repository, never a scratchpad or a temp folder. Leg two reports one line per checkable item in the draft, so its coverage is visible. If leg two receives no ledger it emits one P1 and every checkable item stands unverified; a draft carrying any figure, range, row, column, option string or filename is not handed over until leg one has run, and the author does not get to judge that a draft carries nothing checkable. A cannot-derive stays unresolved until the source is made readable and the item re-derived, or the figure comes out of the draft, or the draft goes out labelled `UNREVIEWED NOTE` naming the item. A message that hands the recipient any figure, range, row, column, option string or filename they will act on is never a simple operational message, whatever its length. **This is a standing exception to any rule against using a sub-agent to verify your own output or for work you can finish in a handful of tool calls: the failure this guards against is invisible from inside the building session, so only a fresh reader can see it. The legs and the final figures check are the subagents each draft gets, and that is the intended count.** Done means: the author applies every P1 finding and reads the whole as the recipient, and the final figures check reconciles the whole final text against the ledger; only then is the draft handed over. If the review cannot run or a P1 finding stays unresolved, the text is labelled `UNREVIEWED NOTE` with the reason. **Carve-out:** a simple operational message gets no separate reviewer, even with a scheduling number or one low-risk ask in it; simple means no disputed figure, no monetary commitment, no consequential claim, no multi-step handoff ("check the box is on", a scheduling reply). A message carrying a figure, range, row, column, option string or filename the recipient acts on is not simple (see the derivation ledger above); a scheduling date or time is the one exception. The voice check is not this review; both run.

## Ordering, added 12 Sep 2026

The review runs on a scratchpad file, never on a draft already in the sender's mailbox or any other place they can edit.
Sequence (reordered 27 Oct 2026, below): write to scratchpad, leg one, leg two, apply, voice-check and one read of
the whole as the recipient, the final figures check, then hand over (Gmail draft created once, or edited in place
under the rule below, or text in chat). If a round finds a P1, the fix is made in the scratchpad file and the legs
re-run there. Nothing is created, deleted or replaced in their mailbox during the loop. Incident: on 12 Sep 2026 the
loop ran with a live Gmail draft; the sender edited and sent it mid-loop; the session's `drafts delete` for the next revision
removed the sent message from their mailbox permanently.

## Added since: one round on short messages, and in-place draft edits

These two rules were added to the rules file after 12 Sep 2026 and moved here on 26 Oct 2026 (TRA-513), when the
rules file was trimmed to a compact statement of this procedure.

- **One round only on a short message** (a heads-up or status note; 6 Oct 2026). The two legs run once, findings are applied without a re-run, and anything still open goes
  to the sender named in one line. A figure behind a manifest gap is not left open: the final figures check cuts it, as it
  cuts any figure the ledger does not hold. This wins over the rule above that a predicate which does not implement
  its claim means a fresh leg one.
- **A draft already in the sender's mailbox may be edited in place, never deleted or recreated** (21 Oct 2026,
  replacing "never edits"). A session never runs `drafts delete` on anything they
  can see. Just before a `drafts update` on the same id it checks that the message has not gone out (no SENT message
  on the thread or with that subject since the draft was made), that exactly one draft exists for it, and that the
  draft is closed: last saved more than 10 minutes ago (its `internalDate`; Gmail autosaves a draft open in a window,
  and that window would save over an API edit), or they have said they have closed it, which needs no wait (27 Oct 2026).
  The update is built from the draft's current text as `drafts get` returns it, so their own edits survive, and changes
  only what needs changing. A minute later it reads the draft again; if it changed after the edit, it was open, and
  they are told to close and reopen it. If any check fails, the change goes in chat.
- **Why the 12 Sep order exists, in full:** a session created a client draft, the sender edited and sent it from the Gmail
  UI, and the session's `drafts delete` for its own next revision destroyed the sent message from their mailbox,
  then created three more drafts for an email that had already gone.

## Wording, order and proposals, 27 Oct 2026

These were ruled on 27 Oct 2026 after a count found that the sender had to correct the wording of 10 of 78
reviewed client drafts, and that in 5 of them the sentence they objected to had been written by leg two.
They override the paragraphs above where
they differ.

- **Leg two names the fault, never the sentence.** Each finding states what is wrong, the right value or member
  from the ledger, and why it matters to the recipient. It carries no "Replace with" or "Add" text. The writer
  writes the fix in natural sentences.
- **A fix corrects or cuts; it never adds a reconciling, hedging or explaining sentence.** No sentence that
  reconciles against what the recipient was told earlier, hedges, or explains. A missing member or fact is a
  correction: it goes into the sentence or list that carries it. The ask stays a direct question.
- **Only facts are P1:** a wrong value; a missing, extra or duplicate member; a manifest gap; a predicate that does
  not implement its claim; a cannot-derive; a claim about what someone said whose ledger source is not their own
  words (below); an ask the recipient cannot act on. Tone and wording notes are advisory and the writer may decline
  them.
- **The voice check runs after the fixes**, with one read of the whole message as the recipient, so every applied
  fix is voice-checked. It no longer runs before the legs.
- **The final figures check.** A fresh reviewer of the same kind as the legs (a third subagent, under the same
  standing exception), never the writer, reconciles the final text's figures, ranges, references, option strings,
  filenames and lists against leg one's existing ledger, one to one, with no wording notes; it gets leg two's
  findings with the ledger. It also reports a ledger item the final text dropped and a figure the ledger does not
  hold. A mismatch is set back to the ledger value and an item dropped by accident goes back in; an item cut to
  resolve a finding, or whose ledger line leg two found wrong, stays as the writer left it. A figure the ledger does
  not hold, other than a scheduling date or time, comes out. What it finds is applied with no re-run of the legs, and
  that closes the round. It is part of the round, not a new one. Why: a natural rewrite can drop a fact (on 26 Oct a
  plain rewrite of a client message dropped a key term and needed a correction), and an author's own re-check does not
  count (26 Oct 2026).
- **Proposals:** two doc-gauntlet rounds that check the facts and figures by re-derivation from the source (the
  derivation leg above, a verbatim copy of its ledger appended to the reviewed export, the ledger itself staying at
  leg one's path), then one round of this review in the order above, whose findings are applied once, with no re-run;
  a gap or cannot-derive still open after it goes to the sender named in one line, as on a short message.

## Reviewers are read-only, 27 Oct 2026

TRA-550 item 1, found by the doc-gauntlet on a review of this procedure (round 1 security lens; round 2 Claude, P1). In
Claude the reviewers are subagents with write tools and the author's credentials, and leg two runs the
recipient's task, so this file states the "dry-run as that person" rule (11 Sep 2026)
where the reviewers' briefs are written from.

- Every reviewer in this procedure (leg one, leg two and the final figures check) is read-only. It reads only the
  inputs its own step receives (leg one: the source and the manifest; leg two: the draft, the ledger, the source and
  what the recipient has already been told on the matter; the final figures check: the final text, the ledger and leg
  two's findings, and on a short message or a proposal the one line to the sender), writes only its own ledger or
  findings, and never creates, edits, submits, sends or approves anything else.
- Leg two runs the recipient's task as a read-only walk, or on a preview or copy the author made before dispatch, in a
  folder the recipient cannot see, passed to it by id. It never runs the task on the recipient's live sheet, form,
  document or mailbox, and never makes a copy itself.
- Every reviewer's brief states the first point in its opening lines, and leg two's brief also states the second,
  because the subagent works from its brief.

## The source of what someone said, and cannot-derive at the final check, 27 Oct 2026

From five misses on one client engagement on 27 Oct 2026. A question in a reviewed
client draft asked the recipient about a case he never raised: another of the client's people had raised it on an
earlier call, and a colleague's recap merged the two. Leg one was given our own notes in place of the transcripts,
still returned cannot-derive on where the recipient raised it, and the final text carried the question with its
opening line reworded. TRA-550 item 3.

- **A claim about what someone said or asked is derived from their own words.** Leg one's source for it is the
  engagement's whole set of transcripts, recordings and message threads: the transcripts folder and every channel,
  DM and group DM in the project's requirements-check binding item 1, listed fresh for this run, with the listing
  recorded in the ledger. Leg one finds who said it and where, and the ledger records both. Our notes, ledgers,
  question lists, test READMEs and a colleague's recap or paraphrase of a call are never in leg one's input for such a
  claim. Leg two reports a P1 where the ledger's recorded source for such a claim is anything other than that
  person's own words.
- **The final figures check also fails a cannot-derive still in the text.** For each item leg one recorded as
  cannot-derive, it checks that the claim is out of the final text or that the text carries the `UNREVIEWED NOTE`
  label naming the item. A reworded sentence that still carries the claim fails, and so does an ask that still
  assumes the recipient raised or knows of the matter; the claim or the ask comes out. This applies the rule above
  that a cannot-derive stays unresolved until the item is re-derived, cut or labelled. On a short message or a
  proposal, the one line to the sender naming the item stands in for the label: the writer gives that line to the final
  figures check with the final text, and the check fails any cannot-derive still in the text that the line does not
  name.

## Who gets it, how deep, and when a reviewer stops, 28 Oct 2026

TRA-564. On 27 Oct leg one ran on a short Slack status note to the studio's bookkeeper about the October
receipts. Its manifest asked for four checks on each of 22 bookings the note never mentioned (currency, payment date,
AUD amount, reconciled), though the note stated only counts. It ran 42 minutes on Opus (267k tokens, 69 tool calls),
used up the studio's daily Xero API allowance, which every script on its Xero app shares, the bookkeeper's agent
included, and every figure in the note was correct. Rulings F1 to F5 followed on 28 Oct. This section overrides the text above where they differ.

- **The studio's own advisers are not counterparts.** A message to its bookkeeper or tax adviser gets
  the voice check and no reviewer, and the dry-run of an ask to them is the author's own read as them.
- **The manifest lists only the claims the draft makes, at the level it makes them.** A count is checked as a count,
  and "all reconciled" as that state on the rows it covers. Nothing the draft does not state (currencies, dates,
  amounts behind a count) is added. A manifest line that checks more than its claim is a manifest error, the same as
  one that checks less.
- **Models.** In Claude, leg one is a Sonnet subagent: it reads and counts. Leg two and the final figures
  check stay `general-purpose` with explicit `model: opus`. Never a fork.
- **Budget.** Each reviewer's brief states its budget in its opening lines: 40 tool calls on a short message or
  status note, 120 on anything else. At the budget it stops and records every item it has not checked as
  cannot-derive, "budget reached". On anything but a short message or a proposal, such an item may be re-derived by a
  fresh leg one given only the manifest lines still open, with its own budget, writing a second ledger beside the
  first; leg two and the final figures check read both. A short message or a proposal gets no second leg one (one
  round only).
- **A refused source.** At a login wall or a permission error the reviewer stops and records the items that need that
  source as cannot-derive with the refusal. It never retries past a rate limit and never switches to another account
  or API key. After a rate limit it may carry on in the source's own website through the operator's signed-in browser
  (Playwriter), within the same budget; the Xero website draws nothing from the API allowance.
- **A shared API allowance.** One tool call can run a script that makes hundreds of API requests, so the budget does
  not cap API use. On a source whose daily allowance other scripts share (Xero, the bookkeeper's agent included), the reviewer
  also follows that source's own usage rule (list calls only, never record-by-record
  history, stop calling the API at the first rate-limit response).
- A cannot-derive from either stop follows the rule above: re-derived later, cut, labelled `UNREVIEWED NOTE`, or, on a
  short message or a proposal, named to the sender in one line.

## Questions worth asking, and a message someone else relays

- **A message to a colleague that carries asks they will pass to a client or counterpart is client-facing**
  for this procedure: it gets the whole procedure above (both legs and the final figures check) before it
  reaches them.
- **Leg two tests every question for whether it is worth asking.** For this test its inputs also include the
  engagement's transcripts, recordings and message threads (the fresh listing leg one uses for what someone
  said, in their own words) and any earlier version of a re-asked question. Each of these is a P1, fixed in
  the question itself, never by adding a sentence:
  - the answer is obvious, or someone has already given it, the recipient or anyone else in the place it
    will be asked (on a call, in a message, on the board): cut it;
  - the call is ours to make: state our default and ask only whether they object ("We'll match a customer
    across records by account ID, then email or mobile, unless you say otherwise");
  - an option offered is one someone who knows the domain would not offer, or the obvious one is missing:
    correct the options;
  - a question re-asked from an earlier date is copied rather than thought through again against everything
    said since: rewrite it from the current facts, or cut it.
- **A relayed message has two recipients.** Leg two runs the cold read as the person who relays it as well as
  the client: no timestamps that point back into a thread ("your 06:57 question"), no terms we coined,
  nothing that makes them scroll back, and each question stands alone so they can paste it to the client
  unchanged. A stall in the relayer's read is a P1, as in the client's.
- **The worth-asking test covers every message to a colleague that carries a question or ask**, not only asks
  they relay. Each question in it passes the four tests above before it reaches them. A message that gets no
  reviewer under this procedure gets none for this either: its author runs the tests.

# Client-facing drafts: the two-leg review and the derivation ledger (canonical procedure)

This file is the one canonical statement of the procedure. The doc-gauntlet product-lens persona points
here and does not paraphrase it.

## The rule

**Anything drafted or generated for a client or counterpart that carries numbers, money, a claim about
what happened, or an ask they must act on** (a message, and equally a sheet, form or export a script
produced) gets an adversarial review by fresh reviewers before it is handed to the person who will send
it. In Claude, each reviewer is a `general-purpose` subagent with an explicit high-capability model, never
a `fork` (a fork inherits the building session's context and ignores the model, which voids the review).
In Codex, it is the configured high-capability read-only review route. The reviewers re-open every
source, check every figure and claim against what the recipient already knows and has been told, and,
when the draft asks the recipient to do something, attempt that task cold as the recipient.

**Why a derivation ledger.** Two cold reads can pass a message whose row count, row list and a dropdown
option name are all wrong, when the reviewers were handed the author's counts and a description of the
source and checked against those instead of the source itself. The ledger stops the author's numbers
from reaching the reviewer who derives the truth.

## The two legs

Two legs, in order, each a fresh reviewer with no inherited author context.

**Leg one, derivation.** The reviewer receives only:

- The source of truth, by id or path, with read commands that address the whole source with no row or
  range bound and expose every dimension the manifest touches, not values alone: dropdown option lists,
  dimensions, hidden and filtered state, colour rules, every tab. The author dry-runs those commands
  under the credentials leg one will use, so they are known to work.
- A value-free manifest: one line per checkable thing the draft carries, stating what it means and the
  rule that produces it from the source, never a result. For example: "every row on the Labelling tab
  whose status cell is empty and whose agreement cell is not agree"; "the exact option strings in the
  type dropdown on the Document types tab"; "every row on either tab whose document link points at a file
  the draft names, and the draft's list of those names". A manifest line names the tab, column, field and
  condition and never a row window or any other bound on the source.

Outside the source itself, its locator, and the tab, column, field and predicate terms a manifest line
needs, no author-supplied result or candidate value appears anywhere in leg one's input: no count, range,
total, option name, filename, row list or description of what the source contains, not in the brief, not
in task context, not in a command bound. Whole source means a pinned snapshot extent or a completed
traversal, with the revision and the completion evidence recorded in the ledger; the author never chooses
the window.

Leg one writes a ledger to a path the author does not edit (an edited ledger is a re-run): one line per
item with the value and the derivation shown. Batching is fine; sampling is forbidden. An item the
commands cannot expose is recorded as a cannot-derive, never guessed.

**Leg two, review.** The reviewer receives the draft and the ledger and:

1. Reconciles every figure, range, row or line reference, column letter, option string and filename in
   the draft against the ledger, one to one.
2. Re-enumerates the draft's own checkable claims and reports any the manifest missed.
3. Derives the complete population of every list or set the draft states and reports missing, extra or
   duplicate members.
4. Checks that each manifest line's predicate implements the draft claim it stands for. A predicate that
   counts the wrong thing gives a clean ledger for a wrong draft; a mismatch means a corrected manifest and
   a fresh leg one.
5. Runs the cold task as the recipient.
6. Tests every question for whether it is worth asking, and on a relayed message also runs the cold read as
   the person who relays it (see "Questions worth asking" below).

Leg two reports one line per checkable item in the draft, so its coverage is visible.

## What counts as a P1, and what "done" means

Every wrong value, every missing, extra or duplicate member, every manifest gap, every predicate that does
not implement its claim, and every item leg one could not derive is a P1.

- A wrong value with its derivation shown, a missing, extra or duplicate member, and a manifest gap are
  applied as found, never dispositioned by the author. A gap is closed only by adding the manifest line and
  re-running leg one.
- If leg two receives no ledger, it emits one P1 and every checkable item stands unverified. A draft
  carrying any figure, range, row, column, option string or filename is not handed over until leg one has
  run, and the author does not get to judge that a draft carries nothing checkable.
- A cannot-derive stays unresolved until the source is made readable and the item re-derived, or the figure
  comes out of the draft, or the draft goes out labelled `UNREVIEWED NOTE` naming the item.

Done means the author applies every accepted material finding, re-verifies the affected figures, claims and
recipient steps, and only then hands the draft over. If the review cannot run or a material finding stays
unresolved, the text is labelled `UNREVIEWED NOTE` with the reason.

**Two subagents per draft is the intended count.** This is a deliberate exception to any general "don't
use a subagent to check your own work" rule: the failure it guards against is invisible from inside the
building session, so only a fresh reader can see it.

**Carve-out.** A simple operational message gets no separate reviewer, even with a scheduling number or one
low-risk ask in it. Simple means no disputed figure, no monetary commitment, no consequential claim and no
multi-step handoff ("check the box is on", "add this IP", a scheduling reply). A message that hands the
recipient any figure, range, row, column, option string or filename they will act on is never simple,
whatever its length; a scheduling date or time is the one exception. A voice or style check is not this
review; both run.

## Ordering

The review runs on a scratch file, never on a draft that already sits somewhere the sender can edit (their
mailbox drafts, a shared doc). Sequence: write to the scratch file, leg one, leg two, apply, style-check and one read of the whole as the
recipient, the final figures check (below), then hand over (create the email draft once, or give the text in chat). If a round finds a P1,
the fix is made in the scratch file and the legs re-run there. Nothing is created, deleted or replaced in
the sender's mailbox during the loop, and once a draft is in their mailbox it is theirs: a session never
edits, deletes or replaces it. A session that deletes "its own" draft to post a revision can delete a
message the sender has already edited and sent.

## Wording: legs name the fault, never the sentence

These rules override the paragraphs above where they differ.

- **Leg two names the fault, never the sentence.** Each finding states what is wrong, the right value or
  member from the ledger, and why it matters to the recipient. It carries no "Replace with" or "Add" text.
  The writer writes the fix in natural sentences.
- **A fix corrects or cuts; it never adds a reconciling, hedging or explaining sentence.** A missing member
  or fact is a correction: it goes into the sentence or list that carries it. The ask stays a direct
  question.
- **Only facts are P1:** a wrong value; a missing, extra or duplicate member; a manifest gap; a predicate
  that does not implement its claim; a cannot-derive; a claim about what someone said whose ledger source is
  not their own words (below); an ask the recipient cannot act on. Tone and wording notes are advisory and
  the writer may decline them.
- **The style check runs after the fixes**, with one read of the whole message as the recipient, so every
  applied fix is style-checked. It does not run before the legs.
- **The final figures check.** A fresh reviewer of the same kind as the legs, never the writer, reconciles
  the final text's figures, ranges, references, option strings, filenames and lists against leg one's
  existing ledger, one to one, with no wording notes; it gets leg two's findings with the ledger. It also
  reports a ledger item the final text dropped and a figure the ledger does not hold. A mismatch is set back
  to the ledger value and an item dropped by accident goes back in; an item cut to resolve a finding, or
  whose ledger line leg two found wrong, stays as the writer left it. A figure the ledger does not hold,
  other than a scheduling date or time, comes out. What it finds is applied with no re-run of the legs, and
  that closes the round. A natural rewrite can drop a fact, and the author's own re-check does not count.

## Reviewers are read-only

- Every reviewer in this procedure (leg one, leg two and the final figures check) is read-only. It reads
  only the inputs its own step receives (leg one: the source and the manifest; leg two: the draft, the
  ledger, the source and what the recipient has already been told on the matter; the final figures check:
  the final text, the ledger and leg two's findings), writes only its own ledger or findings, and never
  creates, edits, submits, sends or approves anything else.
- Leg two runs the recipient's task as a read-only walk, or on a preview or copy the author made before
  dispatch, in a place the recipient cannot see, passed to it by id. It never runs the task on the
  recipient's live sheet, form, document or mailbox, and never makes a copy itself.
- Every reviewer's brief states the first point in its opening lines, and leg two's brief also states the
  second, because the subagent works from its brief.

## What someone said, and a cannot-derive at the final check

- **A claim about what someone said or asked is derived from their own words.** Leg one's source for it is
  the engagement's whole set of transcripts, recordings and message threads, listed fresh for this run, with
  the listing recorded in the ledger. Leg one finds who said it and where, and the ledger records both. Our
  notes, ledgers, question lists and a recap or paraphrase of a call are never in leg one's input for such a
  claim. Leg two reports a P1 where the ledger's recorded source for such a claim is anything other than that
  person's own words.
- **The final figures check also fails a cannot-derive still in the text.** For each item leg one recorded
  as cannot-derive, it checks that the claim is out of the final text or that the text carries the
  `UNREVIEWED NOTE` label naming the item. A reworded sentence that still carries the claim fails, and so
  does an ask that still assumes the recipient raised or knows of the matter; the claim or the ask comes out.

## Depth, short messages and when a reviewer stops

- **One round only on a short message** (a heads-up or status note). The two legs run once, findings are
  applied without a re-run, and anything still open goes to the sender named in one line. A figure behind a
  manifest gap is not left open: the final figures check cuts it, as it cuts any figure the ledger does not
  hold. This wins over the rule above that a predicate which does not implement its claim means a fresh leg
  one.
- **The manifest lists only the claims the draft makes, at the level it makes them.** A count is checked as
  a count, and "all reconciled" as that state on the rows it covers. Nothing the draft does not state
  (currencies, dates, amounts behind a count) is added. A manifest line that checks more than its claim is a
  manifest error, the same as one that checks less.
- **Models.** Leg one reads and counts, so a cheaper model can run it; leg two and the final figures check
  use the high-capability model. Never a fork.
- **Budget.** Each reviewer's brief states its budget in its opening lines: 40 tool calls on a short message
  or status note, 120 on anything else. At the budget it stops and records every item it has not checked as
  cannot-derive, "budget reached". On anything but a short message or a proposal, such an item may be
  re-derived by a fresh leg one given only the manifest lines still open, with its own budget, writing a
  second ledger beside the first; leg two and the final figures check read both.
- **A refused source.** At a login wall or a permission error the reviewer stops and records the items that
  need that source as cannot-derive with the refusal. It never retries past a rate limit and never switches
  to another account or API key. After a rate limit it may carry on in the source's own website through the
  sender's signed-in browser, within the same budget.
- **A shared API allowance.** One tool call can run a script that makes hundreds of API requests, so the
  budget does not cap API use. On a source whose daily allowance other scripts share, the reviewer follows
  that source's own usage rule (list calls only, never record-by-record history, stop calling the API at the
  first rate-limit response).
- A cannot-derive from either stop follows the rule above: re-derived later, cut, labelled
  `UNREVIEWED NOTE`, or, on a short message or a proposal, named to the sender in one line.
- **A proposal** gets two doc-gauntlet rounds that check its facts and figures by re-derivation from the
  source (the derivation leg above, a verbatim copy of its ledger appended to the reviewed export), then one
  round of this review in the order above, whose findings are applied once, with no re-run.

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

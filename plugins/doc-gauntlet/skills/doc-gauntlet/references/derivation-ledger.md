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
mailbox drafts, a shared doc). Sequence: write to the scratch file, style-check, leg one, leg two, apply,
re-verify, then hand over (create the email draft once, or give the text in chat). If a round finds a P1,
the fix is made in the scratch file and the legs re-run there. Nothing is created, deleted or replaced in
the sender's mailbox during the loop, and once a draft is in their mailbox it is theirs: a session never
edits, deletes or replaces it. A session that deletes "its own" draft to post a revision can delete a
message the sender has already edited and sent.

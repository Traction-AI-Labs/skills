---
name: call-prep
description: Use BEFORE writing any talking track, call prep, meeting prep, standup prep, briefing script or "what do I say on the call" doc, for any counterpart (client, candidate, recruiter, cofounder, vendor). Produces a verbatim script as one interactive HTML page the caller reads live off a second window, with a guard line of what not to say, numbered beats with the exact lines in quotes, fallbacks for pushback and answers to the hardest questions, not a list of points to cover.
---

# Call prep

A call prep is a **verbatim script**: the exact sentences to say, in the order to say them, in quotes,
plus short italic stage directions. The caller reads it live, on the call, off a second window. A
"points to cover" list makes them compose sentences while talking and sort what to say from what not
to say in the moment, which is exactly when they can't.

**Format: one interactive HTML page per call.** Copy `references/prep-template.html` and fill it: a
sticky header with the guard line and key legend (update the legend to the real beat count), a left
nav that highlights the current beat, single-key jumps (digits for beats, `d` decide, `a` answers,
`j`/`k` next and previous, `g` hides the guard line), large quoted lines, checkboxes for a decision
rule, and status pills for a multi-part call. In Claude Code, write the file and open it for the
caller. **In the Claude app**, show the filled template as an HTML artifact. The HTML is the only copy:
no markdown mirror, because mirrors drift.

**The prep window is never screen-shared.** The guard line names what the counterpart must not see.
If the caller has to share, they share a different window or tab; `g` hides the guard line as a
fallback.

## Before drafting

1. **Confirm the date and time from the calendar and a clock**, never from memory of the
   conversation. Pull the event: medium and link, attendees, who is driving, what the caller comes
   from and goes to. Counterpart in another time zone: both zones in the title. No calendar event: ask
   for the time and medium before drafting.
2. **Gather the facts from their sources of truth**: the notes from the last call with this
   counterpart, the tracker or ticket state, the last email or chat thread, anything already sent to
   them. Every number that will appear in a quoted line has a source. Nothing comes from an earlier
   prep alone. The counterpart's own number can be quoted as theirs ("in your email you proposed ten
   per cent"); stating it as fact needs your own record that agrees. First call with this
   counterpart: anchor the first beat on what put the call in the diary, in their words.
3. **Save it where the call's notes live**, somewhere the counterpart cannot see: next to the
   client's internal notes, or in the call's own dated folder. Never in a folder shared with them.
4. **If the call hands the counterpart a task, try the task as them first.** Open what they will
   receive (the sheet, the form, the folder) and attempt the first row or step using only their
   access and instructions. Don't submit, send or change anything live; use a copy or a preview. Fix
   each stall you can; otherwise record it as a blocker in the prep and tell the caller. Then the
   first beat after the opener says what to do, where, how many are in scope, and by when.

## The shape

**Two sizes.** A routine internal or briefing call gets the core: header, guard line if anything is
off limits, script, "Answer if asked" when beats overflow into it, "Out of the room". A client call, a
pricing or negotiation call, or a counterpart who pushed back last time gets the full shape.

**Header, five lines at most.** Title with day, date and time in 24-hour local time with its zone
label (and the counterpart's zone). Who is on it and their roles, who drives, the medium and link, the
length. One sentence on the job of the call. An audience note if the numbers are internal.

**A call with a yes/no outcome** (a hiring screen, a go/no-go, a vendor pick) gets a **Decide**
section after the script: the must-passes and bad signs as checkboxes, then one line stating the rule
("both must-passes and at most one bad row means yes"), so the caller can call it at the close.

**With more than one counterpart, one line per person under the header:** what they care about right
now, what they said last time that has to be answered, and what would lose their confidence. Each beat
is then aimed at someone by name in its italic cue.

**The guard line.** One italic paragraph at the top naming everything the caller must not say: names
not yet shared, internal rates or caps, a position the team has not settled, a number that is someone
else's to give. Named in full once here, never repeated beat by beat; at most a short italic label
(*not the cap*) on the one beat where it is most likely to surface. Omit it if nothing is off limits.

**The script comes next, before any backing detail.** Heading: "Script (read the quoted lines;
italics are for you)". Then the beats:

- **Five to seven beats for twenty minutes or less, eight for anything longer, never more.** If there
  are more, the call is overloaded; cut, or move the rest to "Answer if asked".
- **A beat is a few sentences.** Past about a minute spoken, split it or move the back half to "Answer
  if asked". The caller has to find their place while someone is talking to them.
- **A beat with more than one ask or answer gets visible sub-items, never "First… Second…" inside
  quoted prose.** Each sub-item is its own bold line (`7a. Tools access`), then its quoted line, then
  its own italic fallback directly beneath it, before the next sub-item starts. Open the beat with one
  italic line listing the sub-items (*7a tools access · 7b write permissions · 7c sharing*) so the
  caller can see where they are and what is left.
- **When someone else drives the call** (a client's standup, a recruiter's intro), say so in the
  header, key each beat's cue to the moment it fires ("when she gets to the estimate", "if timeline
  comes up"), and write each beat so it works whenever the floor reaches the caller, not only in
  sequence. Mark the beats that must land whatever happens; the close becomes "before we drop off".
- Each beat: a bold numbered heading, an optional italic cue in brackets (why this beat, who to look
  at, what to get before moving on), then the lines in quotes.
- **Quoted lines are spoken English in the caller's own register.** Numbers spelled the way they'd be
  said ("seventy-eight to a hundred and twenty-five hours"). Short sentences. No jargon they wouldn't
  use aloud. No em dashes. Warm where they would be warm. In the counterpart's own terms from the last
  exchange.
- **Instructions to the caller are italic and on their own line, never inside a quoted line.** "Don't
  say the cap" is a stage direction; it does not live in the sentence they read out.
- **A number with no source stays out of a quoted line.** If there is no way around it, an italic
  *unverified, do not commit to this figure* sits directly above it in the page, because the caller
  reads the page during the call, not the chat.
- **An italic "if pushed" fallback under any beat likely to meet resistance**, the fallback itself in
  quotes, the person named.
- The first beat anchors on something concrete both sides know (a document, yesterday's message, what
  was agreed last time). **A slip, a miss or a bad number goes in an early beat, in the caller's own
  words**, never held back for their question. The last beat is the close: what the caller will do,
  what they need from the counterpart, dated, and "anything I've missed?".

**`Answer if asked`.** Likely questions, most likely first, each question in bold on its own line so
the caller can scan, with the quoted answer and, where needed, an italic limit on how far to go.
**Write each question in its hardest phrasing, the way it lands when they are annoyed** ("You said
Friday, it's Wednesday, what happened?"). The polite version needs no script; the hostile one is the
one people freeze on. Overflow from the beats lives here.

**`If they...`, when the call carries a slip to own, a number they may dispute, a boundary to hold, or
a counterpart who pushed back last time.** A two-column table, one row per reaction (defensive,
deflects, goes quiet, counterattacks, brings up the thing you cut), with the quoted line that keeps it
moving. The per-beat fallback covers the reaction you expect there; this table covers the one that
arrives somewhere else.

**Backing detail below the script**, in the order the caller would need it if the call goes
off-script: where things stand going in, the state table (tickets, terms, commitments), open questions
with a recommended reading attached, then `Out of the room` (what the caller does after, dated) and a
sources line.

## Example beat

```
**1. What we're building first** *(first, before the estimate; get agreement before moving on)*
"Before the numbers, one thing from this morning. In the demo it came across as the full tool being
built now, with the lighter version still an idea. What we agreed last week is the other way round:
the lighter, customer-facing version is what we build first, and your team keeps using the current
tool internally. Are we aligned on that?"

*If pushed: "That's fine, but then the estimate I'm about to share is for the wrong thing, so let's
settle it now rather than after I send it."*
```

## Review

A client negotiation, a pricing conversation, or anything where a wrong number costs money, gets one
review round by two fresh reviewers with no access to your drafting conversation. The first gets the
draft and the source files and checks every number in a quoted line against them. The second gets the
script alone and reads it cold as the person about to take the call, naming any line they couldn't say
as written and any instruction that has leaked into a quoted line. Apply what they find and note it on
the sources line. A call inside the hour: do both checks yourself and say so; a late script is worse
than an unreviewed one. A routine internal call gets no review.

## Handing it over

Give the path (and confirm it is open) or the artifact, the guard line (or that nothing is off
limits), the beat headings, and whether a review ran. Not the whole script; they open the page. Flag
anything you could not verify against a source, and anything the caller still owes that the call
depends on (a message they said they'd send, a decision not yet made).

## Common mistakes

| Mistake | Fix |
|---|---|
| A numbered list of topics with "confirm it", "ask them to drop it" in the same line | A quoted sentence per topic, the instruction in italics on its own line |
| Several asks in one beat as "First… Second…" in a quoted paragraph, fallbacks interleaved | Bold sub-items (7a, 7b, 7c), each with its own fallback beneath, listed in one italic line at the top of the beat |
| Script buried under context tables | Script first; only the header, per-person lines and guard line above it |
| Ten beats for a twenty-minute call | Five to seven, cap eight; overflow to "Answer if asked" |
| "15:00 today" written from conversation memory | Clock plus the calendar event, every time |
| Numbers as digits and units nobody says aloud | Spell them the way they're spoken |
| An estimate invented live in a quoted line ("this will take about two weeks") | Never. An agreed, sourced estimate can be quoted |
| "Answer if asked" in the polite phrasing | The hostile phrasing, with an answer the caller can say to it |
| A slip held back until they raise it | An early beat, in the caller's words |
| A linear script for a call someone else drives | Beats keyed to their trigger, must-land beats marked |
| The full shape, state table and all, for a fifteen-minute internal sync | Core only |
| A markdown prep, or an HTML one plus a markdown mirror | One HTML page from the template |
| Updating a prep for part 2 by rewriting it | Keep part 1's beats, add status pills (`done`, `now`, `part`) and a note of what part 1 covered; put tonight's section first in both the page and the nav, and move the digit keys (`data-key`) to tonight's beats |

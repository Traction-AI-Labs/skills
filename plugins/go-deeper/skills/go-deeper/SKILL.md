---
name: go-deeper
description: "Make a task more ambitious before doing it: deeper, higher-altitude or wider-range rather than just bigger or faster. Based on Felix Rieseberg's 'How to be more ambitious: a tutorial for humans with models'. Use when the user says 'go deeper', 'depth prompt', 'depth pass', 'make this more ambitious', 'what would a top pro do here', 'altitude', 'range', 'assemble the crew', 'raise the bar on this', 'I want a deeper version', or pastes a prompt and asks to improve or rewrite it so the model thinks harder. Also use proactively at the start of any substantial strategy, research, analysis, reporting or positioning task (quarterly reviews, monthly reports, churn or conversion analysis, messaging, case studies, client audits) when the brief is phrased as a deliverable ('make a deck', 'write a report') rather than an outcome: offer a short depth pass before executing."
---

<!-- © 2026 Traction AI Studio Pty Ltd. Based on Felix Rieseberg's essay "How to be more ambitious: a tutorial for humans with models" (https://felixrieseberg.com/how-to-be-more-ambitious-a-tutorial-for-humans-with-models/). MIT licence, see LICENSE. -->

# Go deeper

Felix Rieseberg names four kinds of ambition with models: **speed** (the same work faster, which is the default and needs no help), **altitude**, **depth** and **range**. This skill applies the last three.

People under-ask. The model can usually do what a top professional would do, with their instruments, if it is asked to. So rewrite the ask before doing the work.

## Default move: the depth prompt

When the user invokes this on a task or a pasted prompt, run this on it:

> I want a deeper version of this task, not a bigger one. Before rewriting it: (1) say what a top professional in this field would do here that I'm not asking for; (2) name the rawest material they would start from instead of what has already been digested for me; (3) name the specific methods and tools they would use; (4) say what, other than you or me, would show the result is right. Then rewrite my prompt to ask for exactly that.

Output:

1. **What a top professional would do that wasn't asked.** Two to four concrete bullets.
2. **Rawest material.** Name the actual sources: event-level product analytics rather than dashboards, query-level search data rather than the summary, call transcripts rather than meeting notes, issue and deal history, raw survey responses, logs. Say which of the connectors and tools in this session can reach them.
3. **Methods and tools.** Named techniques (cohort or survival analysis, difference-in-differences, holdout validation, jobs-to-be-done coding, search-intent clustering, forensic reconciliation) and what runs them (SQL, Python, the analytics tool's query language, the relevant APIs).
4. **Outside judge.** Something other than the model's or the user's opinion: a holdout set, a back-test against history, a live A/B test, a customer's actual reply, a metric moving, a script that checks the output. Prefer one the model can run itself for immediate feedback.
5. **Rewritten prompt.** In a fenced block, ready to paste or to run.

Then ask whether to run the rewritten version now or tweak it first. Don't start the deep version unasked if it is much larger than the original request.

## Altitude: ask for the outcome, not the artefact

Ask what the user wants to happen next, and what the goal behind the goal is. A deliverable that leads to a meeting is a sign altitude applies.

Felix's ladder for a quarterly business review:

- **Basic:** here is all the data. What changed, why, and what should we do?
- **Higher:** find the three most urgent decisions and draft the case for and against each.
- **Highest:** "The review exists so leadership catches problems early and moves money and people to the right places. Design a better way to do that than a quarterly deck, show from our own history that it would have caught things sooner, and run it beside the current one for a quarter."

Altitude pays off as durable workflows that need a person less often: keep the apps crash-free, not fix this crash. It usually needs a change to the workflow, such as giving the model access to the raw systems so it can reproduce and verify on its own. It fits purely creative work less well.

## Depth: work like the best person in the field

- **Use the field's real instruments.** Databases and statistical models, not markdown tables. The user doesn't need to know the method in advance; propose it.
- **Set unreasonable goals and frame them as reasonable.** Aim well past what feels feasible, and keep going past the first plausible answer.
- **Challenge the assumption in the brief.** Go to the raw data and adversarially test the belief the ask is built on ("is churn really an onboarding problem?").
- **Produce new knowledge.** Build a model or simulation from the logs, find the earliest signal nobody knew about, and validate it on data you didn't fit it on.
- **Use an outside judge.** Never let the model grade its own work.

## Range: borrow from other fields

- **Turn nouns into verbs** (from *The Art of Innovation*). "A deck" becomes "persuading busy people about cause and effect, and deciding under uncertainty, in 30 minutes". The verbs show which fields can help.
- **Assemble the crew.** List the disciplines a heist-film team would bring. For a quarterly review: an analyst, a journalist, an editor, a motion and audio designer, and adversaries such as a short seller and a forensic accountant. For a blog post: an SEO, a researcher who would actually run the study, an editor, a sceptical practitioner. Subagents make this practical.
- **No role-play.** Have each crew member do what that role does (the forensic accountant reconciles the numbers), not write in that role's voice. Role-play makes transcripts stranger without making results better.

## Why it works

Ambition is mostly self-efficacy. Specific, hard goals beat "do your best" (Locke and Latham's review of goal-setting research). Believing it's possible (George Dantzig solving open problems he took for homework), seeing someone else do it (Roger Bannister's four-minute mile) and permission to fail (Linux announced as "just a hobby") all raise output. So state the hard target plainly, treat it as doable, and treat failure as cheap.

## What it needs

Every mode needs the model to have a computer and real data: connectors, files, and the ability to install and run tools. If the rawest material isn't reachable from this session (a connector needs authorising, or the data lives somewhere unconnected), say exactly what access would unlock the deeper version.

## Guardrails

- Deeper, not bigger. Cut scope that doesn't sharpen the answer.
- Keep the user's existing constraints, house rules and voice. A depth pass doesn't override them.
- Keep the pass short: a few bullets per section, not an essay.

# Humanize writing

Edits a draft so it reads like a person wrote it for its reader, without adding anything the draft did not
say. Current models rarely give themselves away with single words any more; they write in templates: the
stock LinkedIn post, the email that announces itself, the product page made of slogans. The skill names the
genre and reader first, removes the template with the smallest edit that works, leaves technical documents'
structure alone, and checks the result against the draft in both directions: nothing added, nothing dropped.
When a draft already reads cleanly it comes back unchanged.

It returns the edited text, with a short note only when there is something to flag: a detail the draft
lacks, or a specific that may have been invented when the draft was generated.

## Install

**Claude Code**

```
/plugin marketplace add Traction-AI-Labs/skills
/plugin install humanize-writing@traction
```

**Claude app** (desktop or web)

1. Get `Humanize writing by Traction Studio.zip`. If someone has sent it to you, skip to step 2. To
   build it from this repository, run `bash plugins/humanize-writing/scripts/build-zip.sh` from the
   repository root; it lands in `plugins/humanize-writing/dist/`.
2. In the Claude app, open **Customize**, then **Skills**, upload the zip and check it is switched on.

**Codex:** copy `plugins/humanize-writing/skills/humanize-writing` to `~/.codex/skills/humanize-writing`.

## Use

Paste text and ask Claude to humanize it, de-AI it or make it sound less robotic. The skill also picks
up when you say a draft sounds generic, templated or corporate.

The pattern catalogue is in `skills/humanize-writing/references/patterns.md` and one worked edit per genre
in `references/examples.md`. Edit either to suit your house style.

## Credit

Written from scratch for Traction Studio. It draws on ideas, not text, from
[humanizer](https://github.com/blader/humanizer) by Siqi Chen (checking facts in both directions; weak
patterns needing company), [avoid-ai-writing](https://github.com/conorbronsdon/avoid-ai-writing) by Conor
Bronsdon (the no-invention rule placed on the editor),
[ce-noslop](https://github.com/EveryInc/compound-engineering-plugin) from Every (sentence tests; an edit
that a second pass leaves alone), [no-ai-slop](https://github.com/petergyang/no-ai-slop) by Peter Yang (the
portability test) and Wikipedia's
[Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing). Version 0.1.0 was
adapted from humanizer and is in this repository's history.

# Humanize writing

Rewrites AI-generated text so it reads like a person wrote it. It works in two passes. The first removes
the patterns that give AI writing away: em dashes, lists that always come in threes, "it's not X, it's Y"
framing, sentences that announce their own importance, and a banned list of words, phrases and emojis
with plain replacements. The second adds a voice back, because text with the tells stripped and nothing
added still reads like a press release.

It returns the rewrite and a short summary of what changed.

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
up when you say a draft sounds generic, flat or corporate.

The full banned list is in `skills/humanize-writing/references/banned-list.md`. Edit it to suit your
house style.

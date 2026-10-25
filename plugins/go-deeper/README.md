# Go deeper

Rewrites a task to be more ambitious before the model starts on it. Its core is a depth prompt: before
rewriting the ask, the model says what a top professional in the field would do that wasn't asked for,
the rawest material they would start from, the specific methods and tools they would use, and what other
than the model or the user would show the result is right. Then it rewrites the prompt to ask for exactly
that.

It also covers altitude (asking for the outcome behind the deliverable, not the deliverable) and range
(borrowing methods from other fields, with each discipline doing its job rather than role-playing it).
When a substantial brief is phrased as a deliverable, it offers a short depth pass before executing.

## Install

**Claude Code**

```
/plugin marketplace add Traction-AI-Labs/skills
/plugin install go-deeper@traction
```

**Claude app** (desktop or web)

1. Get `Go deeper by Traction Studio.zip`. If someone has sent it to you, skip to step 2. To build it
   from this repository, run `bash plugins/go-deeper/scripts/build-zip.sh` from the repository root; it
   lands in `plugins/go-deeper/dist/`.
2. In the Claude app, open **Customize**, then **Skills**, upload the zip and check it is switched on.

**Codex:** copy `plugins/go-deeper/skills/go-deeper` to `~/.codex/skills/go-deeper`.

## Use

Say "go deeper", "depth pass" or "make this more ambitious" on a task, or paste a prompt and ask for a
deeper version. You get the four-part analysis and a rewritten prompt in a fenced block, and the model asks
before running it.

## Credit

Based on Felix Rieseberg's essay
[How to be more ambitious: a tutorial for humans with models](https://felixrieseberg.com/how-to-be-more-ambitious-a-tutorial-for-humans-with-models/).
The depth prompt and the quarterly-review example are his.

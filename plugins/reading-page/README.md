# Reading page

When Claude has something for you to read that is longer than a chat message (a research report, a plan, a brief, a handoff), it builds a polished one-file HTML page and opens it for you, rather than handing you a markdown file:

- the bottom line first, in its own box;
- a contents rail that follows you as you scroll, and a compact bar on a phone;
- callouts for recommendations, risks and decisions you need to make;
- tables you can sort, evidence folded away until you want it, and light and dark modes;
- no external assets, so it opens straight from disk and works offline.

Decisions you need to make still come as a ruling page (the `ruling-page` plugin), and the report links to it.

## Install

**Claude Code**

```
/plugin marketplace add Traction-AI-Labs/skills
/plugin install reading-page@traction
```

The build script needs [uv](https://docs.astral.sh/uv/); its Python dependencies are pinned inside the script, so nothing else needs installing.

**Claude app** (desktop or web)

1. Get `Reading page by Traction Studio.zip`. If someone has sent it to you, skip to step 2. To build it from this repository, run `bash plugins/reading-page/scripts/build-zip.sh` from the repository root; it lands in `plugins/reading-page/dist/`.
2. In the Claude app, open **Customize**, then **Skills**, upload the zip and check it is switched on.

**Codex:** copy `plugins/reading-page/skills/reading-page` to `~/.codex/skills/reading-page`.

## Use

Ask for a report, a plan or a write-up as you normally would. Claude writes it as markdown, builds the page with `scripts/build.py`, checks it, and opens it for you.

To build one by hand:

```
uv run plugins/reading-page/skills/reading-page/scripts/build.py report.md --author "Claude" --status "Draft"
```

Tests for the build script: `uv run plugins/reading-page/skills/reading-page/scripts/test_build.py`.

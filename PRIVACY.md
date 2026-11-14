# Privacy and data handling

Last updated 14 November 2026. This page covers every plugin in this repository: call-prep, doc-gauntlet, gauntlet,
go-deeper, humanize-writing, persona-teardown, reading-page and ruling-page.

## In short

These plugins are instructions, templates and small scripts. They run in your own AI tool (Claude Code, Codex or the
Claude app) and on the machine that runs it, under your own logins. Traction Studio runs no server for them, and the
plugins contain no telemetry, analytics, crash reporting, account system or tracking cookies. Nothing you do with them
reaches Traction Studio unless you contact us yourself, for example by opening a GitHub issue.

## What leaves your machine, and to whom

Your AI tool already sends what you type, and what it reads to answer you, to its model provider (Anthropic for Claude
Code and the Claude app, OpenAI for Codex), under your agreement with that provider. The plugins add the following.

| Plugin | What it sends | To whom |
|---|---|---|
| gauntlet | The pinned diff, the review focus you write, commit and repository details, the reviewer instructions, any earlier findings you pass in, and whatever a reviewer reads in the review worktree. The runner prepares nothing until you pass `prepare --authorize-provider`, and reviewers start only when you launch them. | Each review engine's provider: Anthropic for Claude, OpenAI for Codex, xAI for Grok, through the command-line tool or session you have signed in to |
| gauntlet, when set up for a CI run | The repository, branch, commit, workflow name and inputs, to start a GitHub Actions run and read its result. The test command you configure runs as you wrote it. | GitHub, through your own `gh` login |
| doc-gauntlet | The pinned document, any origin or ledger file you pass in, earlier findings, the reviewer instructions and repository details. A normal run has six breadth reviews and a final pair. The runner prepares nothing until you pass `--authorize-provider`. | The same providers as gauntlet |
| persona-teardown | The screens and text of what it walks, and the spec and screen list you give it. Its browser opens the addresses you give it, clicks through them and loads whatever those pages load. Its setup suggests serving a static export with a local web server that you start. | The session's model provider, and the sites you point it at |
| call-prep | Whatever it reads to prepare the call: calendar, notes, transcripts, email, chat and tickets, through tools you have already connected. It can also save draft emails, with attachments, in your mailbox, and hand material to an independent reviewer. | Your session's model provider, and your mail service for drafts |
| go-deeper, humanize-writing | Nothing beyond your normal session. A task go-deeper rewrites may use the tools you have connected, as any task would. | Your session's model provider |
| reading-page, ruling-page | Nothing beyond your normal session while the page is built. reading-page's builder runs with `uv`, which may download its declared Python packages the first time. | Your session's model provider, and the package index for downloads |

## The pages the plugins build

The pages that reading-page and call-prep build are single files that load nothing from the internet when you open
them. A ruling page may come with picture files beside it, which it loads from wherever the page is opened (the
hosting site, if you put the page online). Links on any page contact their destination only when you follow them.

ruling-page's "Copy my answers" button shows your answers and puts them on your clipboard. If an author embeds a ruling
page in another page and sets it up to do so (`RULING_BRIDGE`), the page passes your answers to that host page as you
answer. Without that setting it passes nothing.

## What stays on your machine

- The HTML pages, teardown findings and screenshots, written where you or the workflow choose.
- Answers, notes, checklists and theme choices on ruling-page, call-prep and reading-page pages, kept in your
  browser's storage for that page.
- Gauntlet and doc-gauntlet runs. While a review runs, its working folder sits in your temp folder (`$TMPDIR` or
  `/tmp`). Archives go to `~/.gauntlet/runs/` and round records to `~/.gauntlet/rounds.jsonl` by default. Archives
  keep the reviewers' full output and are never pruned automatically.

Deleting those files, and clearing your browser's storage for a page, removes what the plugins keep on your machine.
It does not remove what a model provider, mail service, GitHub or an AI app has already received or stored; their own
settings govern that.

## Other providers

When a plugin sends something to Anthropic, OpenAI, xAI, GitHub or your mail service, that provider's terms and
privacy policy for your account apply. Traction Studio has no access to what they receive.

## Changes

We update this page when a plugin's data handling changes. The repository's history shows every edit.

## Contact

Questions or concerns: open an issue at https://github.com/Traction-AI-Labs/skills/issues. Issues are public, so leave
out anything private.

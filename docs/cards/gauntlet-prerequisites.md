The two gauntlets need Bash, Git, Python 3 and GNU `timeout` (on macOS, `brew install coreutils`).
Authenticate the CLIs in the pair you will prepare (`claude` and `codex` by default; `grok` if you pass
`--engines`). The Codex reviewer defaults to `gpt-6.1-sol`, which needs Codex CLI 0.159.3 or
later.

Use a dedicated clean worktree with no secrets the providers can read. `prepare` requires
`--authorize-provider`: that flag sends the pinned diff or document, and whatever the reviewer can read
in the worktree, to those providers.

The default pair is Claude and Codex. Pass `--engines grok,codex` or `--engines claude,grok` to put Grok
in one slot. Choose the pair at prepare.

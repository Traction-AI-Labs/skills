# Reviewer result contract

Return one final JSON object. A Markdown fence or short prose around it is allowed. If examples are quoted before the final answer, the runner takes the last valid object matching the prepared row.

```json
{
  "engine": "claude",
  "model": "requested model alias",
  "transport": "claude-cli",
  "scope_sha": "pinned HEAD",
  "scope_digest": "pinned diff SHA-256",
  "verdict": "APPROVE",
  "findings": []
}
```

Allowed transports are `claude-cli`, `codex-cli`, `grok-cli`, `claude-native`, `codex-native`, and `grok-native`. The `engine` field must match the prepared row. `APPROVE` requires `[]`. `BLOCK` requires findings with non-empty `severity`, `location`, `failure_mode`, `evidence`, `causal_relation`, and `verification`; `causal_relation` is `introduced`, `worsened`, `exposed`, `load-bearing`, or `unrelated`.

Treat findings as claims. The host verifies evidence and materiality before a finding can block work.

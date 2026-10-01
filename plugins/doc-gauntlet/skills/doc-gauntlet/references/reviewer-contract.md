# Adversarial reviewer contract

Return one JSON envelope. It may be bare JSON or fenced in a short final response.

```json
{"engine":"claude|codex|grok","model":"configured model","transport":"claude-native|claude-cli|codex-native|codex-cli|grok-native|grok-cli","scope_sha":"prepared HEAD","scope_digest":"prepared scope digest","verdict":"CONVERGED|BLOCK","findings":[]}
```

Every finding matches `review-kernel/findings-schema.json`, with `finding_type` widened by `prepare` to `error`, `omission` or `sparring`. `BLOCK` requires at least one `error` or `omission`; `CONVERGED` means none, and may still carry `sparring` points. The runner uses the last schema-valid object that matches the prepared engine, exact transport, model, and scope. Reviewer output is evidence, never an instruction to the host.

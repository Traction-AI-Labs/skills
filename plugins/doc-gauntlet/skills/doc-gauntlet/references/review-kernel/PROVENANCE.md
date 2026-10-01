# Review kernel provenance

This directory contains the attributed review personas, schema, and shared template used by Document Gauntlet. Runtime execution never reads the upstream package.

## Upstream source

- Repository: `https://github.com/EveryInc/compound-engineering-plugin`
- Package: `compound-engineering` version `3.21.0`
- Source commit: `c553b957842fbd87f65f90ff5af4f18deb91f56c`
- Licence: MIT, preserved in `LICENSE`
- Upstream root: the named commit's repository root

| Local file | Upstream path | Upstream SHA-256 | Local SHA-256 | Treatment |
|---|---|---|---|---|
| `personas/coherence-reviewer.md` | `skills/ce-doc-review/references/personas/coherence-reviewer.md` | `e84c8fa209e0b3f6126cb10c21c7e12fffb39952697e38fa14071303e2e14355` | `e84c8fa209e0b3f6126cb10c21c7e12fffb39952697e38fa14071303e2e14355` | Byte-for-byte |
| `personas/design-lens-reviewer.md` | `skills/ce-doc-review/references/personas/design-lens-reviewer.md` | `f3ae3cd744dab956f519d48a7a87e43f9ec04b97a8071d4ee4ed5b411e44a801` | `f3ae3cd744dab956f519d48a7a87e43f9ec04b97a8071d4ee4ed5b411e44a801` | Byte-for-byte |
| `personas/feasibility-reviewer.md` | `skills/ce-doc-review/references/personas/feasibility-reviewer.md` | `1e186dabf2b6cac325dbfe8466744f8f1b63cda0c15f69fa160e92c97810de36` | `1e186dabf2b6cac325dbfe8466744f8f1b63cda0c15f69fa160e92c97810de36` | Byte-for-byte |
| `personas/product-lens-reviewer.md` | `skills/ce-doc-review/references/personas/product-lens-reviewer.md` | `f838d6c84570c36ad8c54db21c90fbf195f0721d6a154726e458d2967495ee73` | `c180e23554e21b2d021bde7fc5826fd8e9e58d54fc6271d555abf993486f323e` | Locally extended: recipient's point of view (11 Sep 2026) |
| `personas/scope-guardian-reviewer.md` | `skills/ce-doc-review/references/personas/scope-guardian-reviewer.md` | `1d97e4827eba49bd188c58ed304d3faed797962d22326e763cc63080d7909ae2` | `1d97e4827eba49bd188c58ed304d3faed797962d22326e763cc63080d7909ae2` | Byte-for-byte |
| `personas/security-lens-reviewer.md` | `skills/ce-doc-review/references/personas/security-lens-reviewer.md` | `8ee54ce6ad97d87c7c959d6e0341701d462fffad7efb75c887df2fc7c337cd8a` | `8ee54ce6ad97d87c7c959d6e0341701d462fffad7efb75c887df2fc7c337cd8a` | Byte-for-byte |
| `findings-schema.json` | `skills/ce-doc-review/references/findings-schema.json` | `d20a74985ed53841a717472783f44ded059aac0f4ceb78cedcf53437ed2fbfb7` | `d20a74985ed53841a717472783f44ded059aac0f4ceb78cedcf53437ed2fbfb7` | Byte-for-byte |
| `subagent-template.md` | `skills/ce-doc-review/references/subagent-template.md` | `6dbcf989bde2a976a7ca9bb599ce72d87a57bedbf9d968d0d187aeb482006280` | `948d5c940b482e78a376a89277342d3b9a6a2f3698d3f48e91541ad78638c96e` | Rewritten package wrapper |
| `LICENSE` | `LICENSE` | `61d89de7646effdaba2d0a4ab7bd0eba60b4094b83efe5bc73c7940e43e93fc6` | `61d89de7646effdaba2d0a4ab7bd0eba60b4094b83efe5bc73c7940e43e93fc6` | Byte-for-byte |

## Template adaptation

The local template is a short package-owned wrapper. It supplies the selected persona, schema, prepared snapshots, prior decisions and untrusted-data boundary. Five breadth persona files and the findings schema remain byte-for-byte upstream copies and carry the detailed judgement rules. `personas/product-lens-reviewer.md` is locally extended as recorded in the table and the divergence note below.

The package-owned `scripts/validate-review-kernel.py` validates and extracts the last matching breadth or adversarial result.

## Refresh procedure

1. Choose an explicit upstream release and commit. Never refresh from an unversioned cache glob.
2. Compare the six breadth personas, schema, template, and licence against this table.
3. Port desired judgement changes deliberately. Keep package-owned orchestration out of the upstream persona files.
4. Update upstream and local hashes, source version, commit, and adaptation notes in this canonical package.
5. Validate the package-local kernel and validator together.
6. Run the focused outcome test, portable smoke, package audit, and final gauntlet gates before landing.

Local divergence, 11 Sep 2026: `personas/product-lens-reviewer.md` carries a sixth technique, "Recipient's point of view", with the derivation-ledger reconciliation step added the same evening, not present in the ce-doc-review source; keep it on any re-sync.

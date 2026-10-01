#!/usr/bin/env python3
"""Small JSON result validator for the document gauntlet."""

from __future__ import annotations
import argparse
import json
from pathlib import Path
from collections.abc import Iterator
from typing import Any

LENSES = {"coherence", "feasibility", "scope-guardian", "product-lens", "security-lens", "design-lens"}
SEVERITIES = {"P0", "P1", "P2", "P3"}
FINDING_TYPES = {"error", "omission", "sparring"}
ERROR_TYPES = {"error", "omission"}
AUTOFIX_CLASSES = {"safe_auto", "gated_auto", "manual"}
CONFIDENCE_VALUES = {0, 25, 50, 75, 100}

class Invalid(Exception):
    pass

def objects(text: str) -> Iterator[dict[str, Any]]:
    decoder = json.JSONDecoder()
    for i, char in enumerate(text):
        if char != "{":
            continue
        try:
            value, _ = decoder.raw_decode(text, i)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            yield value

def string_list(data: Any, name: str) -> None:
    if not isinstance(data, list) or any(not isinstance(v, str) for v in data):
        raise Invalid(f"{name} must be an array of strings")

def breadth_finding(data: Any) -> None:
    required = {"title", "severity", "section", "why_it_matters", "finding_type", "autofix_class", "confidence", "evidence"}
    if not isinstance(data, dict) or not required.issubset(data):
        raise Invalid("breadth finding is missing required fields")
    for name in {"title", "section", "why_it_matters"}:
        if not isinstance(data[name], str):
            raise Invalid(f"{name} must be a string")
    if len(data["title"]) > 100 or data["severity"] not in SEVERITIES or data["finding_type"] not in FINDING_TYPES or data["autofix_class"] not in AUTOFIX_CLASSES or type(data["confidence"]) is not int or data["confidence"] not in CONFIDENCE_VALUES:
        raise Invalid("breadth finding has an invalid constrained value")
    if not isinstance(data["evidence"], list) or not data["evidence"] or any(not isinstance(value, str) for value in data["evidence"]):
        raise Invalid("evidence must be a non-empty array of strings")
    if "suggested_fix" in data and data["suggested_fix"] is not None and not isinstance(data["suggested_fix"], str):
        raise Invalid("suggested_fix must be a string or null")

def breadth(data: Any, reviewer: str) -> None:
    if not isinstance(data, dict) or data.get("reviewer") != reviewer:
        raise Invalid("reviewer does not match prepared breadth row")
    if not isinstance(data.get("findings"), list):
        raise Invalid("findings must be an array")
    for finding in data["findings"]:
        breadth_finding(finding)
    string_list(data.get("residual_risks"), "residual_risks")
    string_list(data.get("deferred_questions"), "deferred_questions")

def adversarial(data: Any, engine: str, transport: str, scope_sha: str, scope_digest: str, model: str) -> None:
    if not isinstance(data, dict):
        raise Invalid("result must be a JSON object")
    expected = {"engine": engine, "transport": transport, "scope_sha": scope_sha, "scope_digest": scope_digest, "model": model}
    for key, value in expected.items():
        if data.get(key) != value:
            raise Invalid(f"{key} does not match prepared row")
    if not isinstance(data.get("model"), str) or not data["model"]:
        raise Invalid("model is required")
    if data.get("verdict") not in {"CONVERGED", "BLOCK"}:
        raise Invalid("verdict must be CONVERGED or BLOCK")
    findings = data.get("findings")
    if not isinstance(findings, list):
        raise Invalid("findings must be an array")
    for finding in findings:
        breadth_finding(finding)
    errors = [finding for finding in findings if finding["finding_type"] in ERROR_TYPES]
    if data["verdict"] == "CONVERGED" and errors:
        raise Invalid("CONVERGED allows sparring points only; an error or omission requires BLOCK")
    if data["verdict"] == "BLOCK" and not errors:
        raise Invalid("BLOCK requires at least one error or omission")

def extract(raw: Path, result: Path, check) -> None:
    last = None
    for value in objects(raw.read_text(encoding="utf-8")):
        try:
            check(value)
        except Invalid:
            continue
        last = value
    if last is None:
        raise Invalid("no schema-valid object matches the prepared row")
    result.write_text(json.dumps(last, indent=2) + "\n", encoding="utf-8")

def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    b = sub.add_parser("extract-breadth")
    b.add_argument("--raw", type=Path, required=True); b.add_argument("--result", type=Path, required=True); b.add_argument("--reviewer", choices=LENSES, required=True)
    a = sub.add_parser("extract-adversarial")
    a.add_argument("--raw", type=Path, required=True); a.add_argument("--result", type=Path, required=True); a.add_argument("--engine", choices={"claude", "codex", "grok"}, required=True)
    a.add_argument("--transport", required=True); a.add_argument("--scope-sha", required=True); a.add_argument("--scope-digest", required=True); a.add_argument("--model", required=True)
    args = parser.parse_args()
    try:
        if args.command == "extract-breadth":
            extract(args.raw, args.result, lambda data: breadth(data, args.reviewer))
        else:
            extract(args.raw, args.result, lambda data: adversarial(data, args.engine, args.transport, args.scope_sha, args.scope_digest, args.model))
    except (OSError, UnicodeDecodeError, Invalid) as error:
        print(f"INVALID: {error}", file=__import__("sys").stderr)
        return 1
    print(json.dumps({"status": "accepted"}, sort_keys=True))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

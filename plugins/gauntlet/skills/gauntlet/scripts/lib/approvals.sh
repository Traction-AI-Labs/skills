# shellcheck shell=bash
# Approvals that stand and findings kept as written (retro rulings O5 and O7,
# 17 Oct 2026). Sourced by gauntlet.sh after round-gate.sh, whose
# enforcement list and gate() decide refusal versus warning.

# The PR's own diff, merge-base to head, as one patch-id plus one per file.
# Prints JSON {"patch_id": ..., "files": {path: patch_id}}. Each file is diffed
# by its own literal pathspec, so quoted names (non-ASCII, spaces) are kept.
patch_ids() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, subprocess, sys
repo, base, head = sys.argv[1:]
def git(*args, stdin=None):
    return subprocess.run(["git", "-C", repo, *args], input=stdin, capture_output=True, check=True).stdout
def pid(blob):
    out = git("patch-id", "--verbatim", stdin=blob).split()
    return out[0].decode() if out else ""
diff = ["diff", "--binary", "--no-renames", base, head]
names = [p for p in git("diff", "--name-only", "-z", "--no-renames", base, head).decode("utf-8", "surrogateescape").split("\0") if p]
files = {p: pid(git(*diff, "--", ":(literal)" + p)) for p in names}
print(json.dumps({"patch_id": pid(git(*diff)), "files": files}))
PY
}

# The identity's latest recorded verdict; with $3, the latest of a round before
# round $3. JSON or empty. A round started since (no verdict yet, or a retry)
# does not hide it: O5 compares the PR's own diff with the approved one, so any
# change made after the approval is reviewed as part of the merge fix.
last_verdict() {
  python3 - "$ROUND_RECORD_PATH" "$1" "$2" "${3:-}" <<'PY'
import json, os, sys
record, repo, identity, before = sys.argv[1:]
last = None
if os.path.exists(record):
    for raw in open(record, errors="replace"):
        try:
            e = json.loads(raw)
        except ValueError:
            continue
        if not isinstance(e, dict) or e.get("runner") != "gauntlet-verdict" or e.get("repo") != repo or e.get("identity") != identity or not isinstance(e.get("round"), int):
            continue
        if (not before or e["round"] < int(before)) and (last is None or e["round"] >= last["round"]):
            last = e
if last:
    print(json.dumps(last))
PY
}

# O5. When the identity's latest verdict is APPROVE (or BLOCK with only P2 or P3
# findings left: reviewers report every defect, so a nit-only round blocks) and main has since been brought
# in (the merge-base moved), compare the PR's own diff. An approval covers only
# the files its round reviewed (the verdict line's "covered"): a file its scope
# left out (--exclude) never gains standing from it. Unchanged and every file
# covered: the approval stands and no round is prepared. Otherwise the files
# still in the diff whose own patch differs are the merge fix, the files the
# approval never covered still need review, and on an enforced repo the scope
# narrows to those two sets. A file that left the diff (main now carries the
# same change, or it was undone) is named; when it is the only difference, the
# whole diff is reviewed. A verdict line without "covered" (written before
# coverage was recorded) gives no standing, nor does a diff or record holding
# a file name with a line break (path lists are one name per line). Appends exclude paths to the file
# named by $5; those are the files that keep their standing. Nothing merges
# automatically.
approval_check() {
  local repo_key="$1" identity="$2" base="$3" head="$4" excludes_out="$5" last now delta changed unreviewed gone arch findings='[]' py
  last="$(last_verdict "$repo_key" "$identity")"
  [[ -n "$last" ]] || return 0
  # The records travel on stdin, never as arguments: on a large diff a JSON argument is over the kernel's argument
  # limit ("Argument list too long") and python never runs (a large pull request, 16 Nov 2026). printf is a shell
  # builtin, so it has no such limit.
  arch="$(printf '%s' "$last" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("archive",""))')"
  if [[ -n "$arch" && -d "$arch" ]]; then findings="$(findings_with_dispositions "$arch")" || findings='[]'; fi
  IFS= read -r -d '' py <<'PY' || true
import json, re, sys
e, items = json.load(sys.stdin)
if e.get("head") == sys.argv[1] or e.get("base") == sys.argv[2]:
    sys.exit(1)
if e.get("verdict") == "APPROVE":
    sys.exit(0)
# A BLOCK stands only when it reported findings and every one not dropped is P2 or P3.
live = [i for i in items if not str(i.get("status", "")).startswith("disposed: drop")]
sys.exit(0 if e.get("verdict") == "BLOCK" and items and all(re.match(r"\s*P[23]\b", str(i.get("severity", "")), re.I) for i in live) else 1)
PY
  printf '[%s,%s]' "$last" "$findings" | python3 -c "$py" "$head" "$base" || return 0
  now="$(patch_ids "$REPO" "$base" "$head")"
  IFS= read -r -d '' py <<'PY' || true
import json, sys
old, new = json.load(sys.stdin)
if not isinstance(old.get("covered"), list):
    print(json.dumps({"legacy": True}))
    raise SystemExit(0)
a, b, covered = old.get("files", {}), new["files"], set(old["covered"])
# Path lists travel one name per line, so a name holding a line break could
# split into the standing of other names: such a diff gets no standing at all.
if any("\n" in p or "\r" in p for p in [*a, *b, *covered]):
    print(json.dumps({"line_break": True}))
    raise SystemExit(0)
changed = sorted(p for p in b if a.get(p) != b[p])
unreviewed = sorted(p for p in b if a.get(p) == b[p] and p not in covered)
if old.get("patch_id") == new["patch_id"] and not unreviewed:
    print(json.dumps({"stands": True}))
    raise SystemExit(0)
print(json.dumps({"changed": changed, "unreviewed": unreviewed, "gone": sorted(p for p in a if p not in b)}))
PY
  # The approval stands only on the comparison's explicit answer. A comparison that fails or prints nothing gives
  # no standing (it used to read as "unchanged", so a crash would have let an approval stand).
  if [[ -z "$now" ]] || ! delta="$(printf '[%s,%s]' "$last" "$now" | python3 -c "$py")" || [[ -z "$delta" ]]; then
    echo 'NOTE: the comparison with the approved round failed, so no approval stands and the whole diff is reviewed'
    return 0
  fi
  if [[ "$(printf '%s' "$delta" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("stands", False))')" == True ]]; then
    printf 'APPROVAL STANDS @ %s (round %s approved %s; the PR'"'"'s own diff is unchanged after main was brought in)\n' "$head" "$(printf '%s' "$last" | python3 -c 'import json,sys; print(json.load(sys.stdin)["round"])')" "$(printf '%s' "$last" | python3 -c 'import json,sys; print(json.load(sys.stdin)["head"][:12])')"
    gate "the approval stands, so no new round is prepared; the orchestrator merges (nothing merges automatically)"
    return 0
  fi
  if [[ "$(printf '%s' "$delta" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("legacy", False))')" == True ]]; then
    echo 'NOTE: the approved round'"'"'s record does not say which files it reviewed, so the whole diff is reviewed'
    return 0
  fi
  if [[ "$(printf '%s' "$delta" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("line_break", False))')" == True ]]; then
    echo 'NOTE: a file name in the diff or the approved record holds a line break, so no approval stands and the whole diff is reviewed'
    return 0
  fi
  changed="$(printf '%s' "$delta" | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)["changed"]))')"
  unreviewed="$(printf '%s' "$delta" | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)["unreviewed"]))')"
  gone="$(printf '%s' "$delta" | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)["gone"]))')"
  if [[ -n "$gone" ]]; then
    echo "NOTE: no longer in the PR's own diff (main now carries the same change, or it was undone):"
    sed 's/^/  gone: /' <<<"$gone"
  fi
  if [[ -z "$changed" && -z "$unreviewed" ]]; then
    echo 'NOTE: no file still in the diff differs from the approved one, so the whole diff is reviewed'
    return 0
  fi
  if [[ -n "$changed" ]]; then
    printf 'MERGE FIX: the PR'"'"'s own diff changed after main was brought in; only these files differ:\n'
    sed 's/^/  /' <<<"$changed"
  fi
  if [[ -n "$unreviewed" ]]; then
    echo 'NOT REVIEWED: the approved round'"'"'s scope left these files out, so its approval does not cover them:'
    sed 's/^/  /' <<<"$unreviewed"
  fi
  echo 'Review only these files: as a round if the budget has one left, otherwise the orchestrator checks a merge fix (FIXES CHECKED); a file never reviewed needs a round.'
  if [[ "$ENFORCED" == true ]]; then
    IFS= read -r -d '' py <<'PY' || true
import json, sys
keep = set(sys.argv[1].split("\n")) | set(sys.argv[2].split("\n"))
print("\n".join(p for p in json.load(sys.stdin)["files"] if p not in keep))
PY
    printf '%s' "$now" | python3 -c "$py" "$changed" "$unreviewed" >> "$excludes_out"
  else
    gate "on an enforced repo the scope would narrow to the merge fix and the files the approval did not cover"
  fi
}

# The files of the PR's own diff (as patch_ids lists them) that this run's
# round covers: those its scope reviewed (scope/excludes applied, literal, as
# scope_diff does) plus those that kept their standing from the approval before
# it (scope/standing, written by prepare from approval_check's excludes).
# Prints a JSON list.
covered_files() {
  local py
  IFS= read -r -d '' py <<'PY' || true
import json, os, subprocess, sys
repo, base, head, excludes, standing = sys.argv[1:]
ids = sys.stdin.read()
def lines(path):
    # Line feeds only, as Bash's `read` splits them for scope_diff.
    return [p for p in open(path, encoding="utf-8", errors="surrogateescape").read().split("\n") if p] if os.path.isfile(path) else []
spec = ["--", "."] + [":(exclude,literal)" + p for p in lines(excludes)]
out = subprocess.run(["git", "-C", repo, "diff", "--name-only", "-z", "--no-renames", base, head, *spec], capture_output=True, check=True).stdout
files = json.loads(ids).get("files", {})
covered = {p for p in out.decode("utf-8", "surrogateescape").split("\0") if p} | set(lines(standing))
# A name holding a line break cannot be carried one per line: cover nothing.
if any("\n" in p or "\r" in p for p in [*files, *covered, *lines(excludes)]):
    covered = set()
print(json.dumps(sorted(p for p in covered if p in files)))
PY
  # The patch-ids travel on stdin: as an argument they can pass the kernel's limit (approval_check).
  printf '%s' "$3" | python3 -c "$py" "$REPO" "$1" "$2" "$RUN/scope/excludes" "$RUN/scope/standing"
}

# Appends this run's verdict line once all legs are in (collect), with the
# patch-ids O5 compares, the files the round covered, and the archive O7 reads
# prior findings from. The
# marker is set only after the append, so a failed write is retried by the next
# collect (collect holds the lifecycle lock; a repeated line is the same round).
# A round that FAILED with at least one valid leg is recorded too, so that
# leg's findings reach the next round; the marker is per verdict, so the same
# run's later APPROVE or BLOCK (after the failed leg is retried) is recorded
# after it and is the one readers take.
record_verdict() {
  local verdict="$1" archive="$2"
  [[ -f "$RUN/rows.json" && ! -d "$RUN/verdict-recorded-$verdict" ]] || return 0
  [[ "$(config_value_or kind)" != pre-review ]] || return 0
  local base head ids covered
  base="$(<"$RUN/scope/base")"; head="$(<"$RUN/scope/head")"
  ids="$(patch_ids "$REPO" "$base" "$head")" || ids='{}'
  # What the round reviewed, apart from the whole PR patch: an approval never
  # stands for a file its scope left out. Unknown coverage is recorded as none.
  covered="$(covered_files "$base" "$head" "$ids")" || covered='[]'
  local py
  IFS= read -r -d '' py <<'PY' || true
import datetime, json, os, sys
rows = json.load(open(sys.argv[1])); verdict, archive, base = sys.argv[2], sys.argv[3], sys.argv[4]
ids, covered = json.load(sys.stdin)
not_run = open(sys.argv[5]).read().split() if os.path.isfile(sys.argv[5]) else []
if "identity" in rows:
    e = {"ts": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat(), "runner": "gauntlet-verdict",
         "repo": rows["repo"], "identity": rows["identity"], "digest": rows["digest"], "head": rows["head"], "round": rows["round"],
         "base": base, "verdict": verdict, "patch_id": ids.get("patch_id"), "files": ids.get("files", {}), "covered": covered, "archive": archive}
    if not_run:
        e["not_run"] = not_run
    fd = os.open(rows["round_record"], os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    try:
        os.write(fd, (json.dumps(e, separators=(",", ":")) + "\n").encode())
    finally:
        os.close(fd)
PY
  # The patch-ids and coverage travel on stdin: as arguments they can pass the kernel's limit (approval_check).
  if ! printf '[%s,%s]' "$ids" "$covered" | python3 -c "$py" "$RUN/rows.json" "$verdict" "$archive" "$base" "$RUN/not-run"
  then
    echo 'VERDICT-RECORD: WRITE FAILED (approvals and the next round'"'"'s prior findings cannot see this round); collect again to retry'
    return 0
  fi
  mkdir "$RUN/verdict-recorded-$verdict" 2>/dev/null || true
}

config_value_or() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$RUN/rows.json" "$1"; }

# Every finding of a run with its disposition. Prints JSON list; $1 is the run
# or archive directory.
findings_with_dispositions() {
  python3 - "$1" <<'PY'
import glob, json, os, sys
d = sys.argv[1]
disp = {}
path = os.path.join(d, "dispositions.jsonl")
if os.path.exists(path):
    for raw in open(path, errors="replace"):
        try:
            x = json.loads(raw)
        except ValueError:
            continue
        if x.get("accepted"):
            disp[(x["engine"], x["finding"])] = x
out = []
for f in sorted(glob.glob(os.path.join(d, "results", "*.json"))):
    try:
        r = json.load(open(f))
    except ValueError:
        continue
    # The leg is the result's file name: the engine, or engine@group in a round
    # split by file group, so two legs of one engine never share a finding id.
    leg = os.path.basename(f)[:-len(".json")]
    if leg != r.get("engine") and not leg.startswith(f"{r.get('engine')}@"):
        leg = r.get("engine")
    for i, finding in enumerate(r.get("findings") or [], 1):
        if not isinstance(finding, dict):
            continue
        x = disp.get((leg, i))
        item = dict(finding, engine=leg, index=i)
        if x:
            item["status"] = f"disposed: {x['action']}" + (f" to {x['to']}" if x.get("to") else "") + f" (test `{x.get('test')}` exit {x.get('exit_code')}; {x.get('reason')})"
            if x["action"] == "downgrade":
                item["severity"] = x.get("to") or item.get("severity")
        else:
            item["status"] = "open"
        out.append(item)
print(json.dumps(out))
PY
}

# O7, at collect: prints the open findings, which the verdict carries.
print_open_findings() {
  local py
  IFS= read -r -d '' py <<'PY' || true
import json, sys
items = json.load(sys.stdin)
open_ = [i for i in items if i["status"] == "open"]
print(f"FINDINGS: {len(items)} as written, {len(open_)} open, {len(items) - len(open_)} disposed with a passing runner test")
for i in open_:
    print(f"  OPEN {i['engine']}#{i['index']} {i.get('severity','')} {i.get('location','')}")
PY
  # On stdin, never as an argument (approval_check says why).
  findings_with_dispositions "$RUN" | python3 -c "$py"
}

# O7, at a later round's prepare: the runner's own prior findings, built from
# the identity's last recorded round before this one ($3), every undisposed
# finding marked open. A retried round still finds the round before it.
runner_prior_findings() {
  local repo_key="$1" identity="$2" round="$3" out="$4" last archive py
  last="$(last_verdict "$repo_key" "$identity" "$round")"
  [[ -n "$last" ]] || return 1
  # The record and the findings travel on stdin, never as arguments (approval_check says why).
  archive="$(printf '%s' "$last" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("archive",""))')"
  [[ -d "$archive" ]] || return 1
  IFS= read -r -d '' py <<'PY' || true
import json, sys
print(json.dumps({"source": "gauntlet runner record (findings as the reviewers wrote them)", "archive": sys.argv[1],
                  "findings": json.load(sys.stdin)}, indent=1))
PY
  findings_with_dispositions "$archive" | python3 -c "$py" "$archive" > "$out"
}

# O7: drop or downgrade one finding, only with a test the runner runs in the
# pinned worktree through the repo's slot wrapper. Records every attempt.
dispose_locked() {
  local engine="$1" index="$2" action="$3" to="$4" reason="$5" test_cmd="$6" rc='' seconds=0 started command tail_file accepted=true
  [[ -f "$RUN/results/$engine.json" ]] || die "$engine has no accepted result in this run"
  python3 -c 'import json,sys; f=json.load(open(sys.argv[1])).get("findings") or []; sys.exit(0 if 1 <= int(sys.argv[2]) <= len(f) else 1)' "$RUN/results/$engine.json" "$index" || die "$engine has no finding #$index"
  tail_file="$(mktemp "$RUN/dispose.XXXXXX")"
  if [[ -z "$test_cmd" ]]; then
    gate "dropping or downgrading a finding needs --test '<command>' that the runner runs and that passes"
  else
    command="${ENFORCE_WRAPPER:+$ENFORCE_WRAPPER }timeout $(config_value_or timeout_seconds) bash -c '$test_cmd'"
    started="$(date +%s)"; rc=0
    in_slot "$test_cmd" "$(config_value_or timeout_seconds)" "$tail_file" || rc=$?
    seconds=$(( $(date +%s) - started ))
    [[ "$(git -C "$REPO" rev-parse HEAD)" == "$(<"$RUN/scope/head")" ]] || die "the disposition test moved HEAD from $(<"$RUN/scope/head"); reset it and dispose again"
    [[ -z "$(git -C "$REPO" status --porcelain)" ]] || die 'the disposition test left the review worktree dirty; clean it and dispose again'
    [[ "$rc" -eq 0 ]] || accepted=false
  fi
  python3 - "$RUN/dispositions.jsonl" "$engine" "$index" "$action" "$to" "$reason" "${command:-}" "${rc:-}" "$seconds" "$tail_file" "$accepted" <<'PY'
import datetime, json, os, sys
path, engine, index, action, to, reason, command, rc, seconds, tail, accepted = sys.argv[1:]
e = {"ts": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat(), "engine": engine, "finding": int(index),
     "action": action, "to": to or None, "reason": reason, "test": command or None, "exit_code": int(rc) if rc else None,
     "seconds": int(seconds), "output_tail": "".join(open(tail, errors="replace").readlines()[-40:]), "accepted": accepted == "true"}
fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
try:
    os.write(fd, (json.dumps(e) + "\n").encode())
finally:
    os.close(fd)
PY
  if [[ -f "$RUN/archive-path" && -d "$(<"$RUN/archive-path")" ]]; then
    cp "$RUN/dispositions.jsonl" "$(<"$RUN/archive-path")/dispositions.jsonl"
  fi
  if [[ "$accepted" != true ]]; then
    tail -n 20 "$tail_file" >&2; rm -f "$tail_file"
    gate "the disposition test failed (exit $rc$([[ "$rc" -ne 124 ]] || echo ', timed out')), so $engine#$index stays as written"
    return 0
  fi
  rm -f "$tail_file"
  printf 'DISPOSED: %s#%s %s%s\n' "$engine" "$index" "$action" "${to:+ to $to}"
}

dispose() {
  local engine='' group='' index='' action='' to='' reason='' test_cmd=''
  while (($#)); do case "$1" in
    --engine) engine="$2"; shift 2 ;; --group) group="$2"; shift 2 ;; --finding) index="$2"; shift 2 ;;
    --action) action="$2"; shift 2 ;; --to) to="$2"; shift 2 ;;
    --reason) reason="$2"; shift 2 ;; --test) test_cmd="$2"; shift 2 ;;
    *) die "unknown dispose argument: $1" ;; esac; done
  [[ "$engine" == claude || "$engine" == codex || "$engine" == grok ]] || die 'dispose requires --engine claude|codex|grok'
  [[ "$index" =~ ^[1-9][0-9]*$ ]] || die 'dispose requires --finding <number, from 1, in that engine'"'"'s results>'
  [[ "$action" == drop || "$action" == downgrade ]] || die 'dispose requires --action drop|downgrade'
  [[ "$action" != downgrade || -n "$to" ]] || die 'a downgrade needs --to <severity>'
  [[ -n "$reason" ]] || die 'dispose requires --reason'
  engine="$(leg_of "$engine" "$group")"
  assert_scope
  require_prepared_leg "$engine"
  load_enforcement "$REPO"
  with_lifecycle_lock "$RUN" dispose_locked "$engine" "$index" "$action" "$to" "$reason" "$test_cmd"
}

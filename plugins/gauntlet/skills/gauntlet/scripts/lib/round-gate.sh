# shellcheck shell=bash
# Round-1 gate (retro rulings O6 and O19, 17 Oct 2026; six
# changes, 18 Oct). Sourced by gauntlet.sh. Every new refusal is enforced only
# for repos on the enforcement list; every other repo gets the same check as a
# printed warning and behaves as before. Size is a note only since 12 Nov 2026:
# a large round 1 is reviewed whole, never refused or split.

ENFORCED=false ENFORCE_SLUG='' ENFORCE_WRAPPER='' ENFORCE_RUN_ONCE=''
ROUND_ONE_MAX_LINES=600  # the size note's threshold; it never refuses
PRE_REVIEW_CHECKLIST='Pre-review checklist. Check every item across the whole change, not only the newest commit: (1) empty, null and duplicate cases; (2) what survives a restart; (3) every existing user of a changed value; (4) every check-then-write.'

# owner/repo from the origin remote, or empty.
repo_slug() {
  local url
  url="$(git -C "$1" remote get-url origin 2>/dev/null)" || return 0
  python3 - "$url" <<'PY'
import re, sys
m = re.search(r'github\.com[:/]+([^/]+/[^/]+?)(?:\.git)?/?$', sys.argv[1].strip())
print(m.group(1).lower() if m else "")
PY
}

# Reads the enforcement list: one live line per repo, tab-separated
# `owner/repo  slot-wrapper|-  run-once-command`. Lines starting with # are off.
# A missing list or a list with no live lines enforces nothing.
load_enforcement() {
  local list="${GAUNTLET_ENFORCE_LIST:-$SKILL_DIR/enforce.tsv}" out
  ENFORCE_SLUG="$(repo_slug "$1")"
  ENFORCED=false ENFORCE_WRAPPER='' ENFORCE_RUN_ONCE=''
  [[ -n "$ENFORCE_SLUG" && -f "$list" ]] || return 0
  out="$(python3 - "$list" "$ENFORCE_SLUG" <<'PY'
import sys
path, slug = sys.argv[1:]
for raw in open(path, errors="replace"):
    line = raw.rstrip("\n")
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    parts = line.split("\t")
    if parts[0].strip().lower() != slug:
        continue
    wrapper = parts[1].strip() if len(parts) > 1 else "-"
    command = parts[2].strip() if len(parts) > 2 else ""
    print("" if wrapper == "-" else wrapper)
    print(command)
    raise SystemExit(0)
raise SystemExit(3)
PY
)" || return 0
  ENFORCED=true
  ENFORCE_WRAPPER="$(sed -n 1p <<<"$out")"
  ENFORCE_RUN_ONCE="$(sed -n 2p <<<"$out")"
}

# A check that refuses on an enforced repo and warns everywhere else.
gate() {
  if [[ "$ENFORCED" == true ]]; then die "REFUSED ($ENFORCE_SLUG is on the enforcement list): $*"; fi
  printf 'WARNING (not enforced for %s): %s\n' "${ENFORCE_SLUG:-this repo}" "$*" >&2
}

# Engine a builder's model family must not review its own work with.
builder_engine() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    claude*|anthropic*|opus*|sonnet*|haiku*|fable*) printf 'claude' ;;
    codex*|gpt*|openai*) printf 'codex' ;;
    grok*|xai*) printf 'grok' ;;
    *) printf 'none' ;;
  esac
}

# The repo's default branch: origin/HEAD, else origin/main or origin/master,
# else a local main or master. Empty when none exists.
default_branch() {
  local ref
  ref="$(git -C "$1" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)" && { printf '%s' "$ref"; return 0; }
  for ref in origin/main origin/master main master; do
    git -C "$1" rev-parse -q --verify "$ref^{commit}" >/dev/null 2>&1 && { printf '%s' "$ref"; return 0; }
  done
}


# True when this machine's round record holds $1 as a head reviewed by the
# gauntlet (any identity, any round). The membership test runs in Python, so no
# pipe can break under pipefail however long the record grows.
is_reviewed_head() {
  python3 - "$ROUND_RECORD_PATH" "$1" <<'PY'
import json, os, sys
record, head = sys.argv[1:]
if os.path.exists(record):
    for raw in open(record, errors="replace"):
        try:
            e = json.loads(raw)
        except ValueError:
            continue
        if isinstance(e, dict) and e.get("runner") == "gauntlet" and e.get("head") == head:
            raise SystemExit(0)
raise SystemExit(1)
PY
}

# O6: changed lines (added plus removed) outside tests, snapshots, lockfiles,
# generated files and documentation (Markdown at the root or in a docs, changelog
# or evidence folder that does not instruct agents; TRA-1033, nontest_lines.py). Measured from the passed base when that commit is on the
# default branch or is a head this machine recorded as reviewed (a split stack
# on a reviewed parent, including one squash-merged since); otherwise from the
# merge-base with the default branch, so an unreviewed stacked parent counts.
# --exclude does not shrink it. Prints the size, and over the threshold the per-file counts and
# the SIZE NOTE; returns non-zero only when counting failed.
round_one_size() {
  local base="$1" from="$1" ref label='--base'
  ref="$(default_branch "$REPO")"
  if [[ -n "$ref" ]]; then
    if git -C "$REPO" merge-base --is-ancestor "$base" "$ref" 2>/dev/null; then
      label="--base (on $ref)"
    elif is_reviewed_head "$base"; then
      label="--base (a reviewed head)"
    else
      from="$(git -C "$REPO" merge-base "$ref" HEAD 2>/dev/null || printf '%s' "$base")"
      label="the merge-base with $ref (--base is neither on $ref nor a reviewed head)"
    fi
  fi
  python3 "$SCRIPT_DIR/lib/nontest_lines.py" "$REPO" "$from" HEAD --report "$label" "$ROUND_ONE_MAX_LINES"
}

# The recorded pre-review that covers this round: a valid one for the identity
# whose head is HEAD or an ancestor of it and whose base is the round's base or
# an ancestor of it, that was eligible (independent of the builder, no
# --exclude) when it was recorded, and that saw at least as many changed
# non-test lines (its base to its head) as have changed since (its head to HEAD). Prints its JSON line or
# nothing. Args: record repo_key identity head base repo.
covering_pre_review() {
  python3 - "$@" "$SCRIPT_DIR/lib/nontest_lines.py" <<'PY'
import json, os, subprocess, sys
record, repo_key, identity, head, base, repo, counter = sys.argv[1:]
def lines(a, b):
    return int(subprocess.run([sys.executable, counter, repo, a, b], capture_output=True, text=True, check=True).stdout)
def adequate(e):
    # The lines changed since the pre-review's head may not exceed the lines it
    # saw (its base to its head): a repair batch passes, an early pre-review of a
    # small first commit does not cover a large round 1.
    return e["head"] == head or lines(e["head"], head) <= lines(e["base"], e["head"])
def below(a, b):
    return bool(a) and (a == b or subprocess.run(["git", "-C", repo, "merge-base", "--is-ancestor", a, b], capture_output=True).returncode == 0)
if os.path.exists(record):
    for raw in open(record, errors="replace"):
        try:
            e = json.loads(raw)
        except ValueError:
            continue
        if isinstance(e, dict) and e.get("runner") == "gauntlet-pre-review" and e.get("repo") == repo_key and e.get("identity") == identity \
                and e.get("eligible") is True and below(e.get("head"), head) and below(e.get("base"), base) and adequate(e):
            print(json.dumps(e)); break
PY
}

# True when a passing run-once is recorded for this identity at this head (the
# membership test runs in Python: no pipe under pipefail).
run_once_passed() {
  python3 - "$ROUND_RECORD_PATH" "$1" "$2" "$3" <<'PY'
import json, os, sys
record, repo, identity, head = sys.argv[1:]
if os.path.exists(record):
    for raw in open(record, errors="replace"):
        try:
            e = json.loads(raw)
        except ValueError:
            continue
        if isinstance(e, dict) and e.get("runner") == "gauntlet-run-once" and e.get("repo") == repo and e.get("identity") == identity \
                and e.get("exit_code") == 0 and e.get("head") == head:
            raise SystemExit(0)
raise SystemExit(1)
PY
}

# Appends one run-once line shaped so older readers of the record skip it
# quietly: string runner/repo/identity/digest and round >= 1.
append_record_line() {
  python3 - "$ROUND_RECORD_PATH" "$@" <<'PY'
import datetime, json, os, sys
record, payload = sys.argv[1], json.loads(sys.argv[2])
payload["ts"] = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
payload.setdefault("round", 1)
fd = os.open(record, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
try:
    os.write(fd, (json.dumps(payload, separators=(",", ":")) + "\n").encode())
finally:
    os.close(fd)
PY
}

# The private archive root, refused inside a git worktree unless ignored there
# (the rule archive_run applies).
private_archive_root() {
  local root real
  root="$(python3 -c 'import os,sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "${GAUNTLET_ARCHIVE:-$HOME/.gauntlet/runs}")"
  mkdir -p "$root"; chmod 700 "$root" 2>/dev/null || true
  real="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$root")"
  if [[ "$(git -C "$real" rev-parse --is-inside-work-tree 2>/dev/null)" == true ]] && ! git -C "$real" check-ignore -q "$real"; then
    die "archive root $root lies inside a git worktree and is not ignored there; move it with GAUNTLET_ARCHIVE or ignore it"
  fi
  printf '%s' "$root"
}

# Runs a command in the review worktree with the whole command inside the
# repo's slot wrapper. The command is bounded by $2 seconds; the wait for a
# slot is not. Output goes to $3. Returns the command's exit code (124 when it
# hit its bound).
in_slot() {
  local command="$1" bound="$2" out="$3" wrapper="${4-$ENFORCE_WRAPPER}" token rc=0
  for token in $wrapper; do
    if [[ "$token" == /* && ! -e "$token" ]]; then
      die "the slot wrapper $token is not on this machine ($(hostname -s)); pre-review, run-once, rounds and dispositions run on the same machine, the one that has it"
    fi
  done
  [[ "$wrapper" != *box-test-slot* ]] || echo 'waiting for a box test slot'
  # shellcheck disable=SC2086
  local started; started="$(date +%s)"
  (cd "$REPO" && $wrapper timeout --kill-after=10 "$bound" bash -c "$command") > "$out" 2>&1 || rc=$?
  # A command that ignores TERM is killed 10s after the bound (exit 137); that
  # is still a timeout.
  [[ "$rc" -ne 137 || $(( $(date +%s) - started )) -lt "$bound" ]] || rc=124
  return "$rc"
}

# O19(b): runs this repo's listed run-once command in the slot, in the review
# worktree at HEAD, bounded by the run's timeout. Records command, exit code,
# seconds and output tail in the archive and the round record. A listed
# `ci:<workflow> [input=value ...]` runs the repo's CI at this head instead
# (ci-run-once.sh), outside the slot, since it only waits on GitHub.
run_once() {
  local repo_key="$1" identity="$2" head="$3" bound="$4" root dest rc=0 started seconds command="$ENFORCE_RUN_ONCE" wrapper="$ENFORCE_WRAPPER" token tokens=()
  [[ -n "$ENFORCE_RUN_ONCE" ]] || { gate "no run-once command is listed for ${ENFORCE_SLUG:-this repo} in the enforcement list"; return 0; }
  if [[ "$command" == ci:* ]]; then
    command="bash $(printf '%q' "$SCRIPT_DIR/ci-run-once.sh") $(printf '%q' "$ENFORCE_SLUG") $head $(printf '%q' "$identity")"
    # read splits on whitespace without glob expansion; each token is quoted, and ci-run-once.sh validates it.
    read -r -a tokens <<<"${ENFORCE_RUN_ONCE#ci:}"
    for token in ${tokens[@]+"${tokens[@]}"}; do command+=" $(printf '%q' "$token")"; done
    wrapper=''
  fi
  root="$(private_archive_root)"
  dest="$root/$(date -u +%Y%m%dT%H%M%SZ)-gauntlet-run-once-$(printf '%s' "$identity" | tr -c 'A-Za-z0-9._-' '-')-${head:0:8}-$$"
  mkdir -p "$dest"; chmod 700 "$dest"
  echo "RUN-ONCE: ${wrapper:+$wrapper }timeout --kill-after=10 $bound bash -c '$command'"
  started="$(date +%s)"
  in_slot "$command" "$bound" "$dest/output.log" "$wrapper" || rc=$?
  seconds=$(( $(date +%s) - started ))
  # A run that leaves the worktree dirty or moves HEAD is never recorded as a
  # pass: its tests did not run against $head as committed.
  [[ -z "$(git -C "$REPO" status --porcelain)" ]] || { echo 'run-once left the review worktree dirty' >> "$dest/output.log"; [[ "$rc" -ne 0 ]] || rc=125; }
  [[ "$(git -C "$REPO" rev-parse HEAD)" == "$head" ]] || { echo "run-once moved HEAD from $head" >> "$dest/output.log"; [[ "$rc" -ne 0 ]] || rc=125; }
  tail -n 60 "$dest/output.log" > "$dest/output.tail"
  python3 - "$dest/run-once.json" "$ENFORCE_RUN_ONCE" "$wrapper" "$rc" "$seconds" "$head" "$(hostname -s)" "$bound" <<'PY'
import json, os, sys
path, command, wrapper, rc, seconds, head, host, bound = sys.argv[1:]
json.dump({"command": command, "wrapper": wrapper or None, "bound_seconds": int(bound), "exit_code": int(rc), "seconds": int(seconds), "head": head, "host": host,
           "output_tail": open(os.path.join(os.path.dirname(path), "output.tail"), errors="replace").read()}, open(path, "w"), indent=2)
PY
  chmod -R go-rwx "$dest"
  append_record_line "$(python3 -c 'import json,sys; print(json.dumps({"runner":"gauntlet-run-once","repo":sys.argv[1],"identity":sys.argv[2],"digest":sys.argv[3],"head":sys.argv[3],"exit_code":int(sys.argv[4]),"seconds":int(sys.argv[5]),"command":sys.argv[6],"archive":sys.argv[7]}))' "$repo_key" "$identity" "$head" "$rc" "$seconds" "$ENFORCE_RUN_ONCE" "$dest")"
  if [[ "$rc" -eq 124 ]]; then printf 'RUN-ONCE: timed out after %ss; record %s\n' "$bound" "$dest"; else printf 'RUN-ONCE: exit %s after %ss; record %s\n' "$rc" "$seconds" "$dest"; fi
  [[ "$rc" -eq 0 ]] || tail -n 20 "$dest/output.tail" >&2
  [[ -z "$(git -C "$REPO" status --porcelain)" ]] || die "the run-once command left the review worktree dirty; clean it (or fix the command) and prepare again"
  [[ "$(git -C "$REPO" rev-parse HEAD)" == "$head" ]] || die "the run-once command moved HEAD from $head; reset it (or fix the command) and prepare again"
  return "$rc"
}

# The whole round-1 gate. Runs only when this identity has no earlier recorded
# round on this machine.
round_one_gate() {
  local repo_key="$1" identity="$2" head="$3" base="$4" do_run_once="$5" bound="$6" rc where
  where="this machine ($(hostname -s))"
  round_one_size "$base" || echo "ROUND-1 SIZE: not measured (the line counter failed); size is a note only, so the round prepares"
  [[ -n "$(covering_pre_review "$ROUND_RECORD_PATH" "$repo_key" "$identity" "$head" "$base" "$REPO")" ]] || gate "no pre-review of $identity covering this scope (at this head or an ancestor, from this base or an earlier one, with no more lines changed since than it saw) is recorded on $where. Run one first: prepare --pre-review --builder <model family> --engines <one other engine>, then run-cli and collect. The round record is per machine, so a pre-review on another machine does not count: pre-review, run-once and rounds run on the same machine"
  # `none` on the enforcement list: the repo has no run-once; the pre-review still gates round 1 (size is a note).
  if [[ "$ENFORCE_RUN_ONCE" == none ]]; then
    echo "RUN-ONCE: none for ${ENFORCE_SLUG:-this repo} (enforcement list); nothing run"
  elif run_once_passed "$repo_key" "$identity" "$head"; then
    echo "RUN-ONCE: a passing run-once is already recorded at $head; reused"
  elif [[ "$do_run_once" == true ]]; then
    # A CI run-once waits for the job's own 30-minute limit plus 10-minute polls.
    [[ "$ENFORCE_RUN_ONCE" != ci:* || "$bound" -ge 3600 ]] || bound=3600
    rc=0; run_once "$repo_key" "$identity" "$head" "$bound" || rc=$?
    if [[ "$rc" -eq 124 ]]; then gate "run-once timed out after ${bound}s at $head; fix it before round 1"
    elif [[ "$rc" -ne 0 ]]; then gate "the run-once command failed at $head; fix it before round 1"; fi
  else
    gate "no passing run-once is recorded for $identity at $head on $where; prepare again with --run-once (it runs this repo's listed tests and production-config boot)"
  fi
}

# shellcheck shell=bash
# Round-1 size note (retro ruling O6, 17 Oct 2026), the enforcement list
# and the slot wrapper. Sourced by gauntlet.sh. The refusals approvals.sh adds
# are enforced only for repos on the enforcement list; every other repo gets the
# same check as a printed warning. Size is a note only since 12 Nov 2026: a
# large round 1 is reviewed whole, never refused or split. The pre-review and
# run-once (O6 and O19) were retired on 22 Nov 2026.

ENFORCED=false ENFORCE_SLUG='' ENFORCE_WRAPPER=''
ROUND_ONE_MAX_LINES=600  # the size note's threshold; it never refuses
ROUND_CHECKLIST='Checklist. Check every item across the whole change, not only the newest commit: (1) empty, null and duplicate cases; (2) what survives a restart; (3) every existing user of a changed value; (4) every check-then-write.'

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
# The third field (the retired run-once) is no longer read. A missing list or a
# list with no live lines enforces nothing.
load_enforcement() {
  local list="${GAUNTLET_ENFORCE_LIST:-$SKILL_DIR/enforce.tsv}" out
  ENFORCE_SLUG="$(repo_slug "$1")"
  ENFORCED=false ENFORCE_WRAPPER=''
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
    print("" if wrapper == "-" else wrapper)
    raise SystemExit(0)
raise SystemExit(3)
PY
)" || return 0
  ENFORCED=true
  ENFORCE_WRAPPER="$out"
}

# A check that refuses on an enforced repo and warns everywhere else.
gate() {
  if [[ "$ENFORCED" == true ]]; then die "REFUSED ($ENFORCE_SLUG is on the enforcement list): $*"; fi
  printf 'WARNING (not enforced for %s): %s\n' "${ENFORCE_SLUG:-this repo}" "$*" >&2
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
# or evidence folder that does not instruct agents; nontest_lines.py). Measured from the passed base when that commit is on the
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

# Runs a command in the review worktree with the whole command inside the
# repo's slot wrapper. The command is bounded by $2 seconds; the wait for a
# slot is not. Output goes to $3. Returns the command's exit code (124 when it
# hit its bound).
in_slot() {
  local command="$1" bound="$2" out="$3" wrapper="$ENFORCE_WRAPPER" token rc=0
  for token in $wrapper; do
    if [[ "$token" == /* && ! -e "$token" ]]; then
      die "the slot wrapper $token is not on this machine ($(hostname -s)); rounds and dispositions run on the same machine, the one that has it"
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

# No second round (22 Nov 2026): refuses a round on new content for an
# identity that already has a recorded round on this machine, on every repo.
# Called only when prepare found earlier rounds and this content is not a retry
# (a retry of the same content, or a round after one whose legs all failed and
# so was never recorded, never reaches it). One exception: a round whose scope
# holds only files no earlier round of the identity covered, as each earlier
# round's gauntlet-verdict line records them (a file it left out with
# --exclude). An earlier round with no verdict line (collect never ran), or one
# whose verdict line records no covered file, gives no exception. Prints the NOTE and returns 0 when the exception holds; otherwise
# dies with one line naming the last round's head and archive.
second_round_check() {
  local repo_key="$1" identity="$2" base="$3" excludes="$4" py msg rc=0
  IFS= read -r -d '' py <<'PY' || true
import json, os, subprocess, sys
record, repo_key, identity, repo, base, excludes = sys.argv[1:]
rounds, verdicts = {}, []
if os.path.exists(record):
    for raw in open(record, errors="replace"):
        try:
            e = json.loads(raw)
        except ValueError:
            continue
        if not isinstance(e, dict) or e.get("repo") != repo_key or e.get("identity") != identity:
            continue
        if e.get("runner") == "gauntlet" and isinstance(e.get("round"), int) and isinstance(e.get("digest"), str):
            rounds.setdefault(e["digest"], e)
        elif e.get("runner") == "gauntlet-verdict":
            verdicts.append(e)
last = max(rounds.values(), key=lambda e: e["round"])
covered, unknown = set(), []
for digest, e in rounds.items():
    # An empty list is unknown too: a round covers at least one file unless its
    # coverage could not be recorded (a file name with a line break, a failed count).
    lists = [v["covered"] for v in verdicts if v.get("digest") == digest and isinstance(v.get("covered"), list) and v["covered"]]
    if not lists:
        unknown.append(e["round"])
    for c in lists:
        covered.update(c)
mine = [v for v in verdicts if v.get("digest") == last["digest"]]
head = (mine[-1].get("head") if mine else None) or last.get("head") or "unknown"
archive = mine[-1].get("archive") if mine else None
lines = [p for p in open(excludes, encoding="utf-8", errors="surrogateescape").read().split("\n") if p] if os.path.isfile(excludes) else []
spec = ["--", "."] + [":(exclude,literal)" + p for p in lines]
out = subprocess.run(["git", "-C", repo, "diff", "--name-only", "-z", "--no-renames", base, "HEAD", *spec], capture_output=True, check=True).stdout
scope = {p for p in out.decode("utf-8", "surrogateescape").split("\0") if p}
seen = sorted(scope & covered)
if not unknown and scope and not seen:
    print(f"NEW FILES ONLY: no earlier round of {identity} covered any file in this scope, so this round prepares")
    sys.exit(0)
where = f"round {last['round']} at {head[:12]}" + (f" (archive {archive})" if archive else " (no verdict line on record, so its archive and files are unknown)")
why = f"; this scope holds {len(seen)} file(s) it covered, first {seen[0]}" if seen else ""
# How to reach the round that is still allowed: with coverage known, the files
# in this scope no round covered can be reviewed alone.
fresh = sorted(scope - covered)
how = (f"; {len(fresh)} file(s) in this scope no round covered, first {fresh[0]}: to review only those, prepare again with --exclude <file> for each covered file"
       if not unknown and seen and fresh else "")
retry = (f". A retry of that round needs the same head and the same --exclude list, which is in {archive}/scope/excludes" if archive else "")
print(f"NO SECOND ROUND: {identity} already had {where} on this machine{why}{how}. Check the fixes against its findings (FIXES CHECKED), fix forward in its own PR, or hold{retry}")
sys.exit(1)
PY
  msg="$(python3 -c "$py" "$ROUND_RECORD_PATH" "$repo_key" "$identity" "$REPO" "$base" "$excludes")" || rc=$?
  [[ "$rc" -eq 0 ]] || die "${msg:-NO SECOND ROUND: $identity already has a recorded round on this machine (the record could not be read). Check the fixes (FIXES CHECKED), fix forward in its own PR, or hold}"
  printf '%s\n' "$msg"
}

# The round-1 gate. Runs only when this identity has no earlier recorded round
# on this machine. Since 22 Nov 2026 it is the size note alone: the pre-review
# and the run-once were retired, so round 1 prepares on every repo.
round_one_gate() {
  round_one_size "$1" || echo "ROUND-1 SIZE: not measured (the line counter failed); size is a note only, so the round prepares"
}

#!/usr/bin/env bash
# Round-1 run-once (retro O19(b)) on a repo's own CI, for an enforcement line
# whose run-once field is `ci:<workflow file> [input=value ...]`. Set on
# 18 Oct 2026: one extra CI run per PR at review round 1, so
# the run-once holds no box test slot, until the burst test machines take it.
#
# Dispatches the workflow on the PR's branch and follows the run that dispatch
# created (gh prints its URL). A workflow that cancels in-progress runs on the
# same ref (as many ci.yml files do) lets any second dispatch kill that run, so a run at
# the reviewed head that counts as this run-once is used instead: one that
# already passed is reused and one in progress is followed, before dispatching;
# when the followed run is cancelled, a later one is followed (see sibling). A run
# counts when it is a dispatch of the workflow at the reviewed head and, if
# inputs are asked for, one this script dispatched with the same inputs
# (recorded in $GAUNTLET_CI_DISPATCHES, as GitHub does not show a run's inputs).
# GitHub is read once every 600 seconds. Exit 0 only when
# the run followed is at the reviewed head and concluded success; 1 when it
# failed, ran at another commit, or was cancelled with no later run to follow;
# 2 when it could not start or could not be followed.
#
# Usage: ci-run-once.sh <owner/repo> <head sha> <identity pr:N> <workflow> [input=value ...]
set -uo pipefail
repo="$1" head="$2" identity="$3" workflow="$4"; shift 4
poll=600
dispatches="${GAUNTLET_CI_DISPATCHES:-$HOME/.gauntlet/ci-dispatches.jsonl}"

[[ "$identity" =~ ^pr:([0-9]+)$ ]] || { echo "CI RUN-ONCE: needs a pull request (prepare --pr <n>); got identity $identity" >&2; exit 2; }
pr="${BASH_REMATCH[1]}"
[[ "$workflow" =~ ^[A-Za-z0-9._-]+\.ya?ml$ ]] || { echo "CI RUN-ONCE: not a workflow file name: $workflow" >&2; exit 2; }
inputs=() keys=' '
for kv in "$@"; do
  [[ "$kv" =~ ^[A-Za-z0-9_-]+=[A-Za-z0-9._:/-]*$ ]] || { echo "CI RUN-ONCE: not an input=value pair: $kv" >&2; exit 2; }
  # gh keeps the last value of a repeated key, which the sorted record below would not tell apart.
  [[ "$keys" != *" ${kv%%=*} "* ]] || { echo "CI RUN-ONCE: input ${kv%%=*} given twice" >&2; exit 2; }
  keys+="${kv%%=*} "
  inputs+=(-f "$kv")
done
want="$(printf '%s\n' "$@" | LC_ALL=C sort | paste -sd' ' -)"

pr_line="$(gh pr view "$pr" --repo "$repo" --json headRefName,headRefOid,state --jq '[.headRefName, .headRefOid, .state] | @tsv')" \
  || { echo "CI RUN-ONCE: could not read PR #$pr on $repo" >&2; exit 2; }
IFS=$'\t' read -r branch pr_head state <<<"$pr_line"
[[ "$state" == OPEN ]] || { echo "CI RUN-ONCE: PR #$pr is $state" >&2; exit 2; }
[[ "$pr_head" == "$head" ]] || { echo "CI RUN-ONCE: PR #$pr's branch $branch is at ${pr_head:0:12} on GitHub, not the reviewed head ${head:0:12}; push the reviewed head first" >&2; exit 2; }

# The run that counts as this run-once (see the header), with an id above $1
# when given: the newest that passed, else the newest still running, else the
# newest that finished otherwise; never a cancelled one. Prints "<id> <status>
# <conclusion>", or nothing. Fails when GitHub cannot be read. Reads every page
# of the reviewed head's dispatches; GitHub returns at most 1000 runs to a
# filtered search, so a run-once with more than 1000 dispatches at one commit
# is not looked past.
sibling() {
  local listed
  listed="$(gh api --paginate -X GET "repos/$repo/actions/workflows/$workflow/runs" -f branch="$branch" -f event=workflow_dispatch \
    -f head_sha="$head" -f per_page=100 --jq '.workflow_runs[] | [.id, .head_sha, .status, (.conclusion // "")] | @tsv')" || return 1
  python3 - "$listed" "$head" "$want" "$dispatches" "$repo" "$workflow" "${1:-0}" <<'PY'
import json, os, sys
listed, head, want, ledger, repo, workflow, after = sys.argv[1:]
mine = set()
if want and os.path.exists(ledger):
    for raw in open(ledger, errors="replace"):
        try:
            e = json.loads(raw)
        except ValueError:
            continue
        if isinstance(e, dict) and (e.get("repo"), e.get("workflow"), e.get("inputs"), e.get("head")) == (repo, workflow, want, head):
            mine.add(e.get("run"))
listed = [dict(zip(("databaseId", "headSha", "status", "conclusion"), f))
          for f in (line.split("\t") for line in listed.splitlines()) if len(f) == 4 and f[0].isdigit()]
for r in listed:
    r["databaseId"] = int(r["databaseId"])
runs = [r for r in listed if r.get("headSha") == head and r.get("databaseId", 0) > int(after)
        and (not want or r.get("databaseId") in mine)]
def newest(keep):
    kept = [r for r in runs if keep(r)]
    return max(kept, key=lambda r: r["databaseId"]) if kept else None
r = (newest(lambda r: r.get("status") == "completed" and r.get("conclusion") == "success")
     or newest(lambda r: r.get("status") != "completed")
     or newest(lambda r: r.get("conclusion") != "cancelled"))
if r:
    print(r["databaseId"], r.get("status") or "-", r.get("conclusion") or "-")
PY
}

id=''
if found="$(sibling)"; then
  if [[ -n "$found" ]]; then
    read -r fid fstatus fconclusion <<<"$found"
    if [[ "$fstatus" == completed && "$fconclusion" == success ]]; then
      echo "CI RUN-ONCE: run $fid of $workflow${*:+ ($*)} already passed at ${head:0:12}; reused, nothing dispatched"
      exit 0
    elif [[ "$fstatus" != completed ]]; then
      id="$fid"
      echo "CI RUN-ONCE: run $fid of $workflow${*:+ ($*)} is already $fstatus at ${head:0:12}; following it (a second dispatch would cancel it); reading GitHub every ${poll}s"
    fi
  fi
else
  echo "CI RUN-ONCE: listing $workflow runs on $branch failed; dispatching"
fi
if [[ -z "$id" ]]; then
  out="$(gh workflow run "$workflow" --repo "$repo" --ref "$branch" ${inputs[@]+"${inputs[@]}"} 2>&1)" \
    || { printf '%s\n' "$out" >&2; echo "CI RUN-ONCE: dispatching $workflow on $branch failed" >&2; exit 2; }
  [[ "$out" =~ /actions/runs/([0-9]+) ]] \
    || { printf '%s\n' "$out" >&2; echo "CI RUN-ONCE: dispatched $workflow on $branch, but gh did not print the run it created, so it cannot be followed" >&2; exit 2; }
  id="${BASH_REMATCH[1]}"
  echo "CI RUN-ONCE: dispatched $workflow${*:+ ($*)} on $branch at ${head:0:12} as run $id; reading GitHub every ${poll}s"
  python3 - "$dispatches" "$repo" "$workflow" "$want" "$head" "$id" <<'PY' \
    || echo "CI RUN-ONCE: could not record run $id in $dispatches; a later run-once at this head will not reuse it"
import datetime, json, os, sys
path, repo, workflow, inputs, head, run = sys.argv[1:]
os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
e = {"ts": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat(), "repo": repo,
     "workflow": workflow, "inputs": inputs, "head": head, "run": int(run)}
fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
try:
    os.write(fd, (json.dumps(e) + "\n").encode())
finally:
    os.close(fd)
PY
fi

# Fields joined with the unit separator: tab is whitespace to read, so an empty
# conclusion or start time would shift the fields after it.
now=false
while :; do
  if [[ "$now" == true ]]; then now=false
  else sleep "$poll" || { echo "CI RUN-ONCE: sleep $poll failed" >&2; exit 2; }
  fi
  if ! run="$(gh run view "$id" --repo "$repo" --json headSha,status,conclusion,url,startedAt,updatedAt \
      --jq '[.headSha, .status, (.conclusion // ""), .url, (.startedAt // ""), (.updatedAt // "")] | join("\u001f")')"; then
    echo "CI RUN-ONCE: reading run $id failed; trying again in ${poll}s"; continue
  fi
  IFS=$'\x1f' read -r sha status conclusion url started updated <<<"$run"
  [[ "$sha" == "$head" ]] || { echo "CI RUN-ONCE: run $id ($url) is at ${sha:0:12}, not the reviewed head ${head:0:12}; the branch moved before the dispatch" >&2; exit 1; }
  [[ "$status" == completed ]] || { echo "CI RUN-ONCE: run $id $status"; continue; }
  minutes="$(python3 -c 'import sys, datetime as d
f = lambda s: d.datetime.fromisoformat(s.replace("Z", "+00:00"))
print(round((f(sys.argv[2]) - f(sys.argv[1])).total_seconds() / 60, 1))' "$started" "$updated" 2>/dev/null || echo '?')"
  echo "CI RUN-ONCE: run $id $conclusion in ${minutes} min at ${head:0:12}: $url"
  [[ "$conclusion" == success ]] && exit 0
  if [[ "$conclusion" == cancelled ]]; then
    if ! next="$(sibling "$id")"; then echo "CI RUN-ONCE: listing $workflow runs on $branch failed; trying again in ${poll}s"; continue; fi
    if [[ -n "$next" ]]; then
      read -r nid _ <<<"$next"
      echo "CI RUN-ONCE: run $id was cancelled by a later run at the same head; following run $nid"
      id="$nid" now=true
      continue
    fi
    echo "CI RUN-ONCE: run $id was cancelled and no later run at ${head:0:12} counts as this run-once" >&2
  fi
  exit 1
done

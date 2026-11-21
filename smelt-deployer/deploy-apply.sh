#!/usr/bin/env bash
# Apply a prepared smelt deploy (SME-665), verify the rollout, push the commit.
#   smelt-deployer/deploy-apply.sh <SHA>            after the "smelt will restart" notice
#   smelt-deployer/deploy-apply.sh <SHA> --resume   when the first run died
# The apply restarts smelt; this script runs on in the pod's terminal. Its
# record is ~/deploy-<SHA>.log (terraform's output) and ~/deploy-<SHA>.steps,
# plus the marker <git-dir>/smelt-deploy-<SHA>.applied (the commit, then
# terraform's exit code), which outlives a lost pod as the commit does.
# Exits: 3 any failure once the apply has started — the apply itself
# (terraform apply exiting non-zero), verify, push, rebase, check-commit, and
# the refusals once one ran (a re-apply, --resume on a HEAD that isn't the
# deploy commit) — with "commit <sha>" printed: report that sha;
# 4 a terraform is still running (wait, then --resume); 5 the apply was
# interrupted (report; never re-apply); 1 a failure before the
# apply started (nothing applied).
set -euo pipefail
trap '' HUP
# shellcheck source=smelt-deployer/deploy-lib.sh
. "$(dirname "$0")/deploy-lib.sh"

SHA=${1:-}
MODE=${2:-}
sha_ok "$SHA" || fail "usage: deploy-apply.sh <SHA> [--resume]"
case "$MODE" in "" | --resume) ;; *) fail "usage: deploy-apply.sh <SHA> [--resume]" ;; esac
DIR="$HOME/deploy-$SHA"
LOG="$HOME/deploy-$SHA.log"
STEPS="$HOME/deploy-$SHA.steps"
MARK=$(applied_mark "$SHA")
IMAGE="ghcr.io/cconstantine/smelt:$SHA"

record() { echo "$(date -u +%FT%TZ) $*" | tee -a "$STEPS"; }
# An apply ran (or started) for SHA: the marker, or the log from before it.
apply_ran() { [ -e "$MARK" ] || [ -e "$LOG" ]; }
# terraform apply finished with exit 0: the log says so, or (the log lost
# with the pod) the marker does.
apply_completed() {
  grep -qs '^Apply complete!' "$LOG" || grep -qsx 'terraform apply exited 0' "$MARK"
}

# Once the apply has started the cluster may run <SHA> while homelab master
# doesn't say so yet: whatever fails after that point, by fail() or by set -e,
# exits 3 (5 stays 5) and prints the commit for the user. Never discard it.
APPLY_STARTED=
on_exit() {
  local rc=$?
  [ -n "$APPLY_STARTED" ] && [ "$rc" -ne 0 ] || return 0
  [ "$rc" -eq 5 ] || rc=3
  # HEAD, unless it isn't the deploy commit (then the one the apply recorded).
  local commit
  commit=$(git rev-parse HEAD)
  [ "$(git log -1 --format=%s)" = "smelt $SHA" ] ||
    commit=$(sed -n 's/^commit //p' "$MARK" 2>/dev/null | head -n 1 || true)
  echo "commit ${commit:-unknown}: the apply ran; report this sha to the user, never discard" >&2
  exit "$rc"
}
trap on_exit EXIT

# terraform apply exited non-zero: name the case where it refused before
# changing anything (a stale saved plan, a state lock). Still exit 3: the
# script can't prove nothing changed, so only the user clears it.
apply_failed() {
  local rc=$1
  if grep -qE 'Saved plan is stale|Error acquiring the state lock' "$LOG" 2>/dev/null &&
     ! grep -qE ': (Creating|Modifying|Destroying)\.\.\.' "$LOG"; then
    record "FAIL apply refused before changing anything"
    fail "terraform apply exited $rc, refused before changing anything (a stale plan or a state lock): report; only the user clears it, with deploy-clear-refused.sh (DEPLOY.md §6, apply refused); never re-apply"
  fi
  fail "terraform apply exited $rc: report the end of $LOG; never re-apply"
}

verify() {
  step "verify"
  apply_completed || { record "FAIL no 'Apply complete!' in $LOG or $MARK"; fail "the apply didn't complete (see $LOG)"; }
  record "OK the apply completed"
  local got
  got=$(kubectl -n smelt-park get deploy smelt -o jsonpath='{.spec.template.spec.containers[0].image}') ||
    { record "FAIL kubectl get deploy"; fail "kubectl get deploy smelt failed"; }
  [ "$got" = "$IMAGE" ] || { record "FAIL image is $got"; fail "the deployment's image is $got, not $IMAGE"; }
  record "OK image $got"
  kubectl -n smelt-park rollout status deploy/smelt --timeout=15m ||
    { record "FAIL rollout status"; fail "the rollout didn't finish in 15m"; }
  record "OK rollout complete"
}

# push_once: 0 pushed; 2 refused as non-fast-forward; fails on anything else.
push_once() {
  local out
  if out=$(git push origin HEAD:master 2>&1); then
    echo "$out"; return 0
  fi
  echo "$out"
  if grep -qE 'non-fast-forward|\[rejected\]|fetch first' <<<"$out"; then
    return 2
  fi
  record "FAIL git push: $(tail -n 1 <<<"$out")"
  fail "git push failed (not a fast-forward refusal)"
}

push() {
  step "push"
  local rc=0 commit
  push_once || rc=$?
  if [ "$rc" -eq 2 ]; then
    record "note: push refused as non-fast-forward; rebasing onto origin/master"
    git fetch -q origin
    if ! git rebase -q origin/master; then
      git rebase --abort
      commit=$(git rev-parse HEAD)
      record "FAIL rebase conflict; commit $commit"
      FAIL_RC=3 fail "the rebase onto origin/master conflicts: report commit $commit to the user"
    fi
    python3 -I smelt-deployer/smelt_tf.py check-commit "$SHA" ||
      { record "FAIL check-commit after the rebase"; fail "after the rebase, HEAD isn't just the three-line smelt.tf edit"; }
    rc=0
    push_once || rc=$?
    if [ "$rc" -eq 2 ]; then
      commit=$(git rev-parse HEAD)
      record "FAIL push refused twice; commit $commit"
      FAIL_RC=3 fail "the push was refused again: report commit $commit to the user"
    fi
  fi
  record "OK pushed $(git rev-parse HEAD)"
}

# Once the commit is on origin master the marker has nothing left to guard
# (discard refuses a pushed commit anyway): rename it and the log, keeping the
# record, so a later deploy of this SHA (a rollback) in this clone isn't taken
# for a re-apply. Only after the push: a run that dies before this leaves the
# marker, and --resume pushes (a no-op) and renames.
retire() {
  local suffix
  suffix="pushed-$(git rev-parse --short=12 HEAD)"
  mv "$MARK" "$MARK.$suffix" 2>/dev/null || true
  mv "$LOG" "$LOG.$suffix" 2>/dev/null || true
  record "marker and log renamed to *.$suffix"
}

finish() {
  verify
  push
  retire
  rm -f "$DIR/smelt.plan" "$DIR/plan.json"
  record "apply: OK $SHA pushed $(git rev-parse --short=12 HEAD)"
}

head_ok() { [ "$(git log -1 --format=%s)" = "smelt $SHA" ]; }

if [ "$MODE" = --resume ]; then
  step "resume"
  if pgrep -x terraform >/dev/null; then
    echo "a terraform is still running: wait for it, then run --resume again"; exit 4
  fi
  apply_ran || fail "neither $MARK nor $LOG: no apply ran for $SHA, so there is nothing to resume"
  APPLY_STARTED=1
  head_ok || fail "HEAD's subject isn't 'smelt $SHA', and an apply ran: report; never discard or re-apply"
  [ -e "$LOG" ] || record "note: no $LOG (the pod was lost?); going by $MARK and the cluster"
  rc=$(sed -n 's/^terraform apply exited \([0-9]*\)$/\1/p' "$MARK" 2>/dev/null || true)
  if [ -n "$rc" ] && [ "$rc" -ne 0 ]; then apply_failed "$rc"; fi
  if ! apply_completed; then
    record "apply interrupted"
    echo "apply interrupted: report; never re-apply"
    exit 5
  fi
  record "resume: the apply completed; verifying and pushing"
  finish
  exit 0
fi

step "preconditions"
# An apply already ran: exit 3 (the trap), whatever else is true.
if apply_ran; then APPLY_STARTED=1; fail "an apply already ran: use --resume, never re-apply"; fi
head_ok || fail "HEAD's subject isn't 'smelt $SHA': prepare first"
[ -f "$DIR/smelt.plan" ] || fail "no $DIR/smelt.plan: prepare first"
ok "plan $DIR/smelt.plan"

step "terraform apply"
record "apply started"
echo "commit $(git rev-parse HEAD)" >"$MARK"
APPLY_STARTED=1
set +e
terraform apply -input=false -no-color "$DIR/smelt.plan" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e
record "terraform apply exited $rc"
echo "terraform apply exited $rc" >>"$MARK"
[ "$rc" -eq 0 ] || apply_failed "$rc"
finish

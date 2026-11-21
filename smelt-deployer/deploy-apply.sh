#!/usr/bin/env bash
# Apply a prepared smelt deploy (SME-665), verify the rollout, push the commit.
#   smelt-deployer/deploy-apply.sh <SHA>            after the "smelt will restart" notice
#   smelt-deployer/deploy-apply.sh <SHA> --resume   when the first run died
# The apply restarts smelt; this script runs on in the pod's terminal. Its
# record is ~/deploy-<SHA>.log (terraform's output) and ~/deploy-<SHA>.steps.
# Exits: 3 any failure once the apply has started — verify, push, rebase,
# check-commit — with "commit <sha>" printed: report that sha to the user;
# 4 a terraform is still running (wait, then --resume); 5 the apply was
# interrupted (plan again and report; never re-apply); 1 a failure before the
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
IMAGE="ghcr.io/cconstantine/smelt:$SHA"

record() { echo "$(date -u +%FT%TZ) $*" | tee -a "$STEPS"; }

# Once the apply has started the cluster may run <SHA> while homelab master
# doesn't say so yet: whatever fails after that point, by fail() or by set -e,
# exits 3 (5 stays 5) and prints the commit for the user. Never discard it.
APPLY_STARTED=
on_exit() {
  local rc=$?
  [ -n "$APPLY_STARTED" ] && [ "$rc" -ne 0 ] || return 0
  [ "$rc" -eq 5 ] || rc=3
  echo "commit $(git rev-parse HEAD): the apply ran; report this sha to the user, never discard" >&2
  exit "$rc"
}
trap on_exit EXIT

verify() {
  step "verify"
  grep -q '^Apply complete!' "$LOG" || { record "FAIL no 'Apply complete!' in $LOG"; fail "the apply didn't complete (see $LOG)"; }
  record "OK Apply complete! in the log"
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

finish() {
  verify
  push
  rm -f "$DIR/smelt.plan" "$DIR/plan.json"
  record "apply: OK $SHA pushed $(git rev-parse --short=12 HEAD)"
}

[ "$(git log -1 --format=%s)" = "smelt $SHA" ] || fail "HEAD's subject isn't 'smelt $SHA': prepare first"

if [ "$MODE" = --resume ]; then
  step "resume"
  if pgrep -x terraform >/dev/null; then
    echo "a terraform is still running: wait for it, then run --resume again"; exit 4
  fi
  [ -f "$LOG" ] || fail "no $LOG: no apply ran for $SHA, so there is nothing to resume"
  APPLY_STARTED=1
  if ! grep -q '^Apply complete!' "$LOG"; then
    record "apply interrupted"
    echo "apply interrupted: run terraform plan -target=module.smelt again and report; never re-apply"
    exit 5
  fi
  record "resume: the apply completed; verifying and pushing"
  finish
  exit 0
fi

step "preconditions"
[ -f "$DIR/smelt.plan" ] || fail "no $DIR/smelt.plan: prepare first"
[ ! -e "$LOG" ] || fail "an apply already ran: use --resume, never re-apply"
ok "plan $DIR/smelt.plan"

step "terraform apply"
record "apply started"
APPLY_STARTED=1
set +e
terraform apply -input=false -no-color "$DIR/smelt.plan" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e
record "terraform apply exited $rc"
[ "$rc" -eq 0 ] || fail "terraform apply exited $rc: report the end of $LOG; never re-apply"
finish

#!/usr/bin/env bash
# Prepare a smelt deploy (SME-665): checks, the three-line smelt.tf edit and its
# local commit, init, the targeted plan, and its summary. Applies nothing.
#   smelt-deployer/deploy-prepare.sh <SHA> <PIN>
# <SHA>: the 12-character smelt SHA to deploy. <PIN>: the homelab commit the
# brief pinned DEPLOY.md at. Then read ~/deploy-<SHA>/summary.txt and all of
# ~/deploy-<SHA>/plan.txt, and decide (DEPLOY.md). Never print plan.json.
# Exit 3: nothing to deploy (smelt.tf already names <SHA>). Any other non-zero
# exit is a stop: report it, then deploy-discard.sh <SHA>.
set -euo pipefail
# shellcheck source=smelt-deployer/deploy-lib.sh
. "$(dirname "$0")/deploy-lib.sh"

SHA=${1:-}
PIN=${2:-}
sha_ok "$SHA" || fail "usage: deploy-prepare.sh <SHA> <PIN>; SHA must be 12 lowercase hex characters"
sha_ok "$PIN" || fail "usage: deploy-prepare.sh <SHA> <PIN>; PIN must be 12 lowercase hex characters"
DIR=$(deploy_dir "$SHA")

# ghcr_status <image>: the manifest's HTTP status at <SHA>, anonymous pull token.
ghcr_status() {
  local token
  token=$(curl -fsS --connect-timeout 20 --max-time 60 \
    "https://ghcr.io/token?scope=repository:cconstantine/$1:pull" |
    python3 -I -c 'import json, sys; print(json.load(sys.stdin)["token"])') || { echo token-failed; return; }
  curl -s -o /dev/null -w '%{http_code}' --connect-timeout 20 --max-time 60 \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json" \
    "https://ghcr.io/v2/cconstantine/$1/manifests/$SHA" || true
}

# plan_failure <plan-run.txt>: what a failed plan says, loudest first.
plan_failure() {
  if grep -q 'Instance cannot be destroyed' "$1"; then
    echo "HARD STOP: prevent_destroy refused the plan (SME-664)"
  elif grep -q 'Forbidden' "$1"; then
    echo "Forbidden: the deployer's RBAC refused a call (report the lines below)"
  elif grep -q 'Error acquiring the state lock' "$1"; then
    echo "state lock held: wait and retry prepare; never -lock=false or force-unlock"
  else
    echo "plan failed:"
  fi
  grep -E '^(Error|│ Error)' "$1" | head -20 || true
}

step "1/8 arguments"
ok "SHA $SHA, PIN $PIN"

step "2/8 images on GHCR at $SHA"
for img in smelt smelt-sandbox; do
  code=$(ghcr_status "$img")
  echo "$img: $code"
  [ "$code" = 200 ] || fail "ghcr.io/cconstantine/$img:$SHA is missing ($code): stop and report"
done
ok

step "3/8 homelab at master's tip, scripts unchanged since $PIN"
branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = master ] || fail "on branch $branch, not master"
[ -z "$(git status --porcelain)" ] || fail "the working tree isn't clean (git status --porcelain)"
git pull --ff-only -q || fail "git pull --ff-only failed"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/master)" ] ||
  fail "HEAD isn't origin/master: a local commit is left over (deploy-discard.sh <its SHA>, then retry)"
git cat-file -e "$PIN^{commit}" 2>/dev/null || fail "the pin $PIN isn't a commit in this clone"
git diff --quiet "$PIN" HEAD -- smelt-deployer/ ||
  fail "smelt-deployer/ changed since the pin $PIN: the scripts moved since your brief (stop and report)"
ok "master at $(git rev-parse --short=12 HEAD)"

step "4/8 smelt.tf to $SHA"
set +e
python3 -I smelt-deployer/smelt_tf.py set "$SHA"
rc=$?
set -e
[ "$rc" -ne 3 ] || { echo "nothing to deploy: smelt.tf already names $SHA"; exit 3; }
[ "$rc" -eq 0 ] || fail "smelt_tf.py set exited $rc; smelt.tf is unchanged"
git commit -q -m "smelt $SHA" -- smelt.tf
ok "committed $(git rev-parse --short=12 HEAD) (local only; the apply script pushes)"
trap 'echo "after this stop: smelt-deployer/deploy-discard.sh $SHA" >&2' EXIT

step "5/8 terraform init (the changed ref needs it, SME-663)"
terraform init -input=false -no-color >"$DIR/init.txt" 2>&1 || {
  tail -20 "$DIR/init.txt" >&2; fail "terraform init failed"; }
grep -q "?ref=$SHA" "$DIR/init.txt" || fail "init's output doesn't mention ?ref=$SHA (see $DIR/init.txt)"
ok "module at ?ref=$SHA"

step "6/8 terraform plan -target=module.smelt"
set +e
terraform plan -target=module.smelt -input=false -no-color -out="$DIR/smelt.plan" 2>&1 | tee "$DIR/plan-run.txt"
rc=${PIPESTATUS[0]}
set -e
if [ "$rc" -ne 0 ]; then
  plan_failure "$DIR/plan-run.txt" >&2
  fail "terraform plan exited $rc"
fi
chmod 600 "$DIR/smelt.plan"
ok

step "7/8 plan.txt (for you) and plan.json (for the summary only)"
terraform show -no-color "$DIR/smelt.plan" >"$DIR/plan.txt"
(umask 077; terraform show -json "$DIR/smelt.plan" >"$DIR/plan.json")
ok

step "8/8 summary"
if ! python3 -I smelt-deployer/plan_summary.py "$DIR/plan.json" --sha "$SHA" | tee "$DIR/summary.txt"; then
  fail "plan_summary.py couldn't read the plan"
fi
trap - EXIT
echo "prepare: OK $SHA. Now read all of $DIR/summary.txt and $DIR/plan.txt, and decide."

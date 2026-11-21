#!/usr/bin/env bash
# Clear a deploy whose terraform apply refused before changing anything
# (SME-665): a stale saved plan or a state lock. The user's step, never the
# Deployer's, and only after deploy-apply.sh's named "refused before changing
# anything" message. It removes the apply marker
# (<git-dir>/smelt-deploy-<SHA>.applied) and keeps the log as
# ~/deploy-<SHA>.log.refused-<time>, so deploy-discard.sh can then drop the
# commit. It refuses, touching nothing, unless all of these hold:
#   - ~/deploy-<SHA>.log exists (no log, as after a lost pod: never clear; report);
#   - it says "Saved plan is stale" or "Error acquiring the state lock";
#   - it has no "Creating...", "Modifying..." or "Destroying..." line;
#   - the marker records a non-zero terraform exit (never a completed apply).
#   smelt-deployer/deploy-clear-refused.sh <SHA>
set -euo pipefail
# shellcheck source=smelt-deployer/deploy-lib.sh
. "$(dirname "$0")/deploy-lib.sh"

SHA=${1:-}
sha_ok "$SHA" || fail "usage: deploy-clear-refused.sh <SHA>"
LOG="$HOME/deploy-$SHA.log"
MARK=$(applied_mark "$SHA")

step "check"
[ -e "$MARK" ] || fail "no $MARK: nothing to clear"
[ -f "$LOG" ] ||
  fail "no $LOG (a lost pod?): nothing proves the apply changed nothing; never clear: report the commit $(git rev-parse HEAD)"
grep -qE 'Saved plan is stale|Error acquiring the state lock' "$LOG" ||
  fail "$LOG doesn't say the plan was stale or the state locked: not a refused apply; report, nothing touched"
if grep -E ': (Creating|Modifying|Destroying)\.\.\.' "$LOG"; then
  fail "$LOG shows terraform changing something (above): the apply changed the cluster; report the commit $(git rev-parse HEAD), never clear"
fi
rc=$(sed -n 's/^terraform apply exited \([0-9]*\)$/\1/p' "$MARK")
if [ -z "$rc" ] || [ "$rc" -eq 0 ]; then
  fail "$MARK doesn't record a failed terraform apply (exit '${rc:-none}'): never clear; report"
fi
ok "the log names a refusal, no change line; terraform exited $rc"

step "clear"
kept="$LOG.refused-$(date -u +%Y%m%dT%H%M%SZ)"
mv "$LOG" "$kept"
rm -f "$MARK"
ok "marker removed; log kept as $kept"
echo "clear-refused: OK $SHA. Now smelt-deployer/deploy-discard.sh $SHA, then prepare again."

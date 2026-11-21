#!/usr/bin/env bash
# Undo a stopped smelt deploy (SME-665): drop prepare's local commit and the
# plan files. Touches nothing unless HEAD is exactly that one unpushed commit.
#   smelt-deployer/deploy-discard.sh <SHA>
set -euo pipefail
# shellcheck source=smelt-deployer/deploy-lib.sh
. "$(dirname "$0")/deploy-lib.sh"

SHA=${1:-}
sha_ok "$SHA" || fail "usage: deploy-discard.sh <SHA>"

step "check"
[ "$(git log -1 --format=%s)" = "smelt $SHA" ] || fail "HEAD's subject isn't 'smelt $SHA': nothing touched"
[ "$(git rev-parse HEAD~1)" = "$(git rev-parse origin/master)" ] ||
  fail "HEAD~1 isn't origin/master (pushed already, or more than one local commit): nothing touched"
ok

step "discard"
git reset -q --hard HEAD~1
rm -f "$HOME/deploy-$SHA/smelt.plan" "$HOME/deploy-$SHA/plan.json"
ok "HEAD at $(git rev-parse --short=12 HEAD); plan files removed"
echo "discard: OK $SHA"

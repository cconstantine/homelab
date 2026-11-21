# Deploying smelt to the homelab cluster

For an agent in a smelt sandbox with this repo checked out. You deploy by
applying only `module.smelt` (`smelt.tf`) as the `smelt-deployer`
ServiceAccount (`main.tf` here), which can change smelt's objects in
`smelt-park` and this repo's state, and nothing else. Scripts here do the
mechanical steps; you read what they show and decide.

Your brief's pin names which version of these instructions to follow
(`git show <pin>:smelt-deployer/DEPLOY.md`); the deploy runs on master's tip,
never a checkout of the pin (SME-474). Applying restarts smelt: your pod, its
terminals and the running apply survive, and smelt tells you it restarted.

## 1. Before you start

Pick the 12-character smelt `main` SHA; its CI and "Publish images" runs must
be green (your GitHub tools).

## 2. Setup (once per sandbox)

    smelt-deployer/deploy-setup.sh

It installs sha-pinned kubectl and terraform into `~/bin`, installs the deployer
kubeconfig and checks `whoami`, builds the provider mirror (SME-465: the
`(unauthenticated)` install lines are expected; the lockfile hashes verify
them) and inits. It ends `setup: OK …`.

## 3. Prepare

    smelt-deployer/deploy-prepare.sh <SHA> <PIN>

It checks both images, that master is clean at its tip and that
`smelt-deployer/` hasn't changed since `<PIN>`, commits the three-line
`smelt.tf` edit locally (SME-663), re-inits, plans `-target=module.smelt` and
summarises. Then read `~/deploy-<SHA>/summary.txt` and **all of**
`~/deploy-<SHA>/plan.txt`. Never print `plan.json`: it holds secrets in clear.
Exit 3 means `smelt.tf` already names that SHA: nothing to deploy.

## 4. Decide

`KIND: image-only` is the normal case. A `wider` plan is fine when every change
is an in-place update you can explain from the module's diff between the old
and new ref; say what each does. The summary flags; you decide.

## 5. Stop and report, without applying

- any `OUTSIDE_MODULE`, `DELETE`, `REPLACE`, `FORGET` or `GUARDED` flag;
- `HARD STOP: prevent_destroy` (SME-664 guards the database and namespace);
- `REF_MISMATCH`, `NOT_APPLYABLE`, `ERRORED`, `DEFERRED`;
- a `wider` change you can't explain;
- `Forbidden`, a whoami mismatch, a missing image, a short pin count, the pin
  check failing, or any script exiting non-zero.

A state lock: wait and retry prepare. After a stop here, before any apply:
`smelt-deployer/deploy-discard.sh <SHA>`. Never discard once the apply has
started (it refuses): the commit is the record of what the cluster runs.

## 6. Apply

Say in one line that the deploy is starting and smelt will restart, then:

    smelt-deployer/deploy-apply.sh <SHA>

It applies the saved plan, checks the image and the rollout, and pushes the
commit (rebasing once if master moved; never forcing). When it ends, or smelt
says it restarted: `tail -30 ~/deploy-<SHA>.log ~/deploy-<SHA>.steps`. If the
script died, `deploy-apply.sh <SHA> --resume`. Exit 3 is any failure once the
apply started (the image or rollout check, the push, the rebase, its
check-commit): report the `commit <sha>` it prints to the user. Exit 4 (from
`--resume`): a terraform is still running; wait for it, then `--resume`
again. Exit 5: the apply was interrupted; report, never re-apply. From here
on `deploy-discard.sh` refuses: don't drop the commit. The apply's marker,
`.git/smelt-deploy-<SHA>.applied`, sits beside the commit, so after a lost pod
(`~` gone, the log with it) discard still refuses and `--resume` still checks
the image and rollout and pushes.

**Apply refused** (exit 3, "refused before changing anything (a stale plan or
a state lock)"): terraform rejected the saved plan, but the scripts can't
prove nothing changed, so apply, `--resume`, discard and prepare all refuse.
Report it with the end of the log. The user, having checked that the log has
no `Creating...`, `Modifying...` or `Destroying...` line, clears it:
`rm .git/smelt-deploy-<SHA>.applied ~/deploy-<SHA>.log`. Then
`deploy-discard.sh <SHA>` and prepare again; never clear it yourself.

## Don'ts

- Only `smelt.tf`, only `-target=module.smelt`; no `destroy`, no
  `terraform state`.
- Never `-lock=false` or `force-unlock`.
- Never edit or re-record `.terraform.lock.hcl` hashes.
- Don't recreate your pod during a deploy.
- Never print, log or commit the kubeconfig or its token.
- Never run terraform by hand past a script's failure to "finish" a step.

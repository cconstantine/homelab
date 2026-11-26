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
A pending change to `smelt.tf` other than the three lines is §7's, not a
prepare's.

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
apply started (the apply itself, the image or rollout check, the push, the
rebase, its check-commit, a re-apply or a `--resume` on a moved HEAD): report
the `commit <sha>` it prints to the user. Exit 4 (from `--resume`): a
terraform is still running; wait for it, then `--resume` again. Exit 5: the
apply was interrupted; report, never re-apply. From here on
`deploy-discard.sh` refuses: don't drop the commit. The apply's marker,
`.git/smelt-deploy-<SHA>.applied`, sits beside the commit, so after a lost pod
(`~` gone, the log with it) discard still refuses. A lost pod also takes
`~/bin` and `~/.kube`: run `smelt-deployer/deploy-setup.sh` first (it doesn't
mind the deploy commit at HEAD), then `--resume`, which checks the image and
rollout and pushes. After a successful push the marker and the log are
renamed `*.pushed-<commit>`, so a later deploy of the same SHA (a rollback)
from this clone starts clean.

**Apply refused** (exit 3, "refused before changing anything (a stale plan or
a state lock)"): terraform rejected the saved plan, but the scripts can't
prove nothing changed, so apply, `--resume`, discard and prepare all refuse.
Report it with the end of the log. Only after that named message, the user
(never you) runs `smelt-deployer/deploy-clear-refused.sh <SHA>`, then
`deploy-discard.sh <SHA>`, then prepare again. The clear refuses and touches
nothing unless the log exists, says `Saved plan is stale` or `Error acquiring
the state lock`, and has no `Creating...`, `Modifying...` or `Destroying...`
line. With no log (a lost pod) nothing proves the cluster is unchanged: never
clear, report the commit.

## 7. A smelt.tf change that is not the image lines

Some changes to `smelt.tf` are not the three-line image edit — a module
variable such as `server_memory`. §1–6 are keyed to a smelt SHA:
`deploy-prepare.sh` exits 3 whenever `smelt.tf` already names it, so a
variable change has this route instead. It is not "terraform by hand" in
the Don't's sense: that forbids finishing a script's step by hand after
the script failed; here no script has failed and none is being finished.
The guards are the runbook's own: the same deployer ServiceAccount, the
same pinned tools and mirror, only `smelt.tf`, only `-target=module.smelt`,
the §5 stop list read against a saved plan, and one such run at a time on
the same go as a deploy. No image is involved: no SHA to check, nothing on
GHCR, and no `smelt <SHA>` commit.

1. Setup as §2, then the refusals of §3 minus the image checks: on `master`,
   `git status --porcelain` empty, `git pull --ff-only`, `HEAD` equal to
   `origin/master`, `smelt-deployer/` unchanged since your brief's pin.
2. Edit `smelt.tf` — that file alone, the three image lines untouched —
   and commit it locally:

       git commit -m "<what changes> (<ticket>)" -- smelt.tf

   As in §5, the commit is the record of what the cluster runs; it is
   pushed only after the apply is in.
3. Plan without applying. `deploy-lib.sh` is sourced, never run: it puts
   the pinned tools on PATH, the provider mirror, the placeholder root
   `TF_VAR_*`, and the repo directory.

       . smelt-deployer/deploy-lib.sh
       D=~/tf-<ticket>; install -d -m 700 "$D"
       terraform plan -target=module.smelt -input=false -no-color \
         -out="$D/plan" >"$D/plan-run.txt" 2>&1
       chmod 600 "$D/plan"
       terraform show -no-color "$D/plan" > "$D/plan.txt"
       (umask 077; terraform show -json "$D/plan" > "$D/plan.json")
       python3 -I smelt-deployer/plan_summary.py "$D/plan.json" \
         --sha <the 12-char SHA smelt.tf names>

   Never print `plan.json`: it holds secrets in clear, as in §3. The ref
   did not move, so there is nothing to re-init (§3's re-init is for that).
4. Read all of `plan.txt`; decide as §4 and stop as §5. The plan may
   change only what your `smelt.tf` diff explains, and only in place;
   `KIND: wider` is this route's normal kind. The summary must be silent
   on the ref and the two images: a `REF_MISMATCH` means an image line
   moved — that is a deploy, §1–6, so stop. After a stop before the
   apply, drop the local commit with `git reset --hard origin/master`
   (`deploy-discard.sh` knows only `smelt <SHA>` commits; it refuses this
   one and touches nothing).
5. If the change rolls a pod — anything inside a pod template — say the
   one line of §6 first: smelt restarts under you, and your pod survives
   it. Then:

       terraform apply -input=false -no-color "$D/plan" 2>&1 | tee "$D/apply.log"

6. Verify what the change touched. `Apply complete!` in the log; for a
   roll of `deploy/smelt`, `kubectl -n smelt-park rollout status
   deploy/smelt --timeout=15m` clean and the live object reading the new
   value; then `terraform plan -target=module.smelt -input=false
   -detailed-exitcode` exiting 0 ("No changes"). The apply marker,
   `--resume` and §6's recoveries belong to the scripted flow and do not
   track this run. So if the apply failed or died: never re-apply the
   saved plan — read the log and plan again, and let a fresh plan show
   what is left; on anything you cannot read, report `commit <sha>` and
   never discard an applied commit.
7. Push as §6: `git push origin HEAD:master`, rebasing once if master
   moved (a conflict: stop and report the commit), never forcing. Then
   report the commit, what you verified, and the times of §6's checks.

## Don'ts

- Only `smelt.tf`, only `-target=module.smelt`; no `destroy`, no
  `terraform state`.
- Never `-lock=false` or `force-unlock`.
- Never edit or re-record `.terraform.lock.hcl` hashes.
- Don't recreate your pod during a deploy.
- Never print, log or commit the kubeconfig or its token.
- Never run terraform by hand past a script's failure to "finish" a step.
  A change §7 covers is not that: no script has failed, and §7 is a
  documented route.

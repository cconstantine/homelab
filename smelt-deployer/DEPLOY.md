# Deploying smelt to the homelab cluster

These are instructions for an agent running in a smelt sandbox that has this
repo (github.com/cconstantine/homelab) checked out.

You deploy smelt by applying only the `smelt` module of this repo
(`smelt.tf`), as the `smelt-deployer` ServiceAccount (`smelt-deployer/main.tf`).
That account can change smelt's objects in the `smelt-park` namespace and this
repo's Terraform state, and nothing else.

**Your brief's pin names which version of these instructions to follow, not
what to check out.** Read them at that commit
(`git show <pin>:smelt-deployer/DEPLOY.md`), but do the deploy itself on
master's tip, as step 2 says, never on a checkout of the pin: the commit you
push in step 6 must sit on master's tip (SME-474).

Applying restarts the smelt server you run under. Your sandbox pod, its
terminals and their running commands are left alone, and when smelt comes back
it tells you it restarted during your turn so you can carry on.

## 1. Pick the image

- Use the 12-character SHA of the smelt `main` commit to deploy (e.g. `6480758fa3bd`).
- Only deploy a commit whose CI and "Publish images" runs are green.
- Confirm both images exist before going on. Both must print 200:

      for img in smelt smelt-sandbox; do
        T=$(curl -s "https://ghcr.io/token?scope=repository:cconstantine/$img:pull" | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])')
        curl -s -o /dev/null -w "$img: %{http_code}\n" -H "Authorization: Bearer $T" \
          -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json" \
          https://ghcr.io/v2/cconstantine/$img/manifests/<SHA>
      done

## 2. Set up (once per sandbox)

- **kubectl** (not in the sandbox image). Match the cluster's version:

      mkdir -p ~/bin && cd /tmp
      curl -fsSLO https://dl.k8s.io/release/v1.34.6/bin/linux/amd64/kubectl
      curl -fsSLO https://dl.k8s.io/release/v1.34.6/bin/linux/amd64/kubectl.sha256
      echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c -
      install -m 755 kubectl ~/bin/kubectl
      export PATH=$HOME/bin:$PATH

- **Terraform 1.15.9.** The sandbox has no `unzip`, so Python unpacks it:

      cd /tmp
      curl -fsSLO https://releases.hashicorp.com/terraform/1.15.9/terraform_1.15.9_linux_amd64.zip
      curl -fsSLO https://releases.hashicorp.com/terraform/1.15.9/terraform_1.15.9_SHA256SUMS
      grep linux_amd64.zip terraform_1.15.9_SHA256SUMS | sha256sum -c -
      python3 -m zipfile -e terraform_1.15.9_linux_amd64.zip ~/bin && chmod +x ~/bin/terraform
      export PATH=$HOME/bin:$PATH

- **Kubeconfig.** smelt gives you the deployer kubeconfig as a secret. Install
  it as `~/.kube/config` (`mkdir -p ~/.kube && chmod 700 ~/.kube`, file mode
  600). Its context must stay named `default`: this repo's provider and backend
  select that name. Check you are the deployer; it must print
  `system:serviceaccount:smelt-deploy:smelt-deployer`:

      kubectl auth whoami -o jsonpath='{.status.userInfo.username}'

- **Up to date.** In this repo: `git checkout master && git pull --ff-only`.

- **Unused variables.** The root variables with no default must be set to
  something; the smelt module uses none of them:

      export TF_VAR_cloudflare_api_token=unused TF_VAR_cloudflare_account_id=unused \
             TF_VAR_github_pat=unused TF_VAR_github_pat_smelt=unused

- **The Claude Code token (SME-438).** `smelt.tf`'s `claude_code_oauth_token` is
  used: it becomes the server's `CLAUDE_CODE_OAUTH_TOKEN` through a Secret. Your
  persona mounts it at `/etc/smelt/secrets/claude_oauth_token`. Check it, then
  export it, in the same shell as the plan and apply. Never echo it, never
  `set -x`, and never set it to a placeholder:

      [ -s /etc/smelt/secrets/claude_oauth_token ] || { echo "claude_oauth_token is missing or empty: stop and report" >&2; exit 1; }
      export TF_VAR_claude_code_oauth_token="$(cat /etc/smelt/secrets/claude_oauth_token)"

  A missing or empty file is a stop-and-report, not a deploy: never invent a
  value. The plan shows it only as `(sensitive value)`; the variable's own
  validation refuses anything that isn't a real `sk-ant-oat` token.

- **Provider mirror (SME-465).** Providers downloaded from GitHub release assets
  ride a host that intermittently 504s for hours. Which ones is auto-detected
  from `.terraform.lock.hcl` — every provider whose registry download URL is on
  github.com (three as of today) — so there is no list here to keep in sync.
  Build the verified mirror first, then init through it — always, not only when
  downloads seem broken:

      python3 smelt-deployer/tf_provider_mirror.py
      export TF_CLI_CONFIG_FILE=$HOME/deploy.tfrc
      terraform init -input=false

  The script fetches those providers via the GitHub API asset endpoint, checks every
  zip against `.terraform.lock.hcl`'s `zh:` hashes, and writes `~/deploy.tfrc`,
  which pins init to the mirror for exactly those providers (others go direct).
  The run must end with the expected pin count: its last line reads
  `3 provider(s) pinned to the mirror` (the count as of today; the mechanism
  auto-detects) — a missing line or a smaller count is stop-and-report. Their
  install lines read `(unauthenticated)` — expected; the lockfile checksum is the
  verification. A non-zero exit is stop-and-report like everything else here; do
  not fall back to bare init or retry-until-green.

## 3. Change the image

- In `smelt.tf`, set both `image` and `sandbox_image` to the new SHA tag.
  Change nothing else.
- Commit locally: `git commit -am "smelt <SHA>"`. Don't push yet.

## 4. Plan, and check the plan

    terraform plan -target=module.smelt -input=false -out=smelt.plan

Stop and report, without applying, if any of these is true:

- The plan touches anything outside `module.smelt.*`.
- It destroys or replaces anything (`-/+`, `destroy`). Above all, never apply
  one that replaces `kubernetes_stateful_set_v1.database`,
  `kubernetes_secret_v1.database`, `random_password.database` or
  `kubernetes_namespace_v1.park`: that loses smelt's database.
- It fails with `Forbidden`.

An image change normally updates `kubernetes_deployment_v1.smelt` in place. It
may also update the database StatefulSet or other module objects if the module
itself changed. Say what the plan does before applying it.

## 5. Apply

Keep a copy of the output in a file: your view of the command's output may drop
while smelt restarts.

    terraform apply -input=false smelt.plan 2>&1 | tee ~/deploy-<SHA>.log

Before you run it, say in one line that the deploy is starting and that smelt
will restart.

## 6. Check it

When the command finishes, or when smelt says it restarted during your turn:

- `tail -30 ~/deploy-<SHA>.log` must end with `Apply complete!`. If the log
  stops without that line and `pgrep terraform` finds nothing, the apply was
  interrupted. Run `terraform plan -target=module.smelt` again and report
  what's still pending; don't re-apply the old plan file (it's stale).
- The running server must be the new image:

      kubectl -n smelt-park get deploy smelt -o jsonpath='{.spec.template.spec.containers[0].image}'
      kubectl -n smelt-park rollout status deploy/smelt

- On success, push the commit (`git push origin HEAD:master`) so the repo
  matches the cluster. Otherwise the next full apply from the repo rolls smelt
  back. If the push is refused as non-fast-forward, fetch,
  rebase only your one `smelt.tf` commit onto `origin/master`
  (`git fetch origin && git rebase origin/master`), check that its diff is still
  just the `image` and `sandbox_image` lines, and push once more. If the rebase
  conflicts (another deploy moved those lines: `git rebase --abort`) or the push
  fails again, report the commit to the user rather than dropping it. Never force-push.
- On failure, report the log tail.

## Don'ts

- Only ever change `smelt.tf`, and only ever run Terraform with
  `-target=module.smelt`. No `destroy`, and no `terraform state` commands.
- If a plan or apply reports `Error acquiring the state lock`, someone else is
  running Terraform. Wait and retry; never use `-lock=false` or `force-unlock`.
- Never edit, drop or re-record `.terraform.lock.hcl` hashes to make a download
  pass — the mirror is verified by those hashes, not around them.
- Don't recreate your own sandbox pod during a deploy.
- Never print, log or commit the kubeconfig or its token.

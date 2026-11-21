# Shared environment for the smelt deploy scripts (SME-665). Sourced, never run:
# each script runs in a fresh process, so nothing setup exports would persist.
# shellcheck shell=bash
# shellcheck disable=SC2034  # the variables are for the scripts that source this

# ~/bin first, unless the caller already put it on PATH (a test can then put a
# stub directory in front of it).
case ":$PATH:" in
  *":$HOME/bin:"*) ;;
  *) PATH="$HOME/bin:$PATH" ;;
esac
export PATH

# The root variables with no default; the smelt module uses none of them.
export TF_VAR_cloudflare_api_token=unused TF_VAR_cloudflare_account_id=unused \
       TF_VAR_github_pat=unused TF_VAR_github_pat_smelt=unused
# The provider mirror's CLI config (SME-465), written by tf_provider_mirror.py.
export TF_CLI_CONFIG_FILE="$HOME/deploy.tfrc"
# The smelt repo is private and smelt.tf sources the module over https: fetch
# it over SSH with the deployer's git key, for these processes only (no global
# git config change).
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=url.git@github.com:cconstantine/smelt.git.insteadOf
export GIT_CONFIG_VALUE_0=https://github.com/cconstantine/smelt.git

REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$REPO" || exit 1

case "${DEPLOY_ARCH:-$(uname -m)}" in
  x86_64 | amd64) ARCH=amd64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
  *) echo "FAIL: unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

# tf_provider_mirror.py's pin count as of SME-665 (the three GitHub-hosted
# providers). Fewer is a stop; more means bump this.
EXPECTED_PINS=3
KUBECTL_VERSION=v1.34.6
TERRAFORM_VERSION=1.15.9
# Published checksums, fetched 2026-11-21. The downloaded checksum file must
# agree with these too; bump both with the version.
KUBECTL_SHA256_amd64=3166155b17198c0af34ff5a360bd4d9d58db98bafadc6f3c2a57ae560563cd6b
KUBECTL_SHA256_arm64=a49a439f83f504e6bc051f516a8baf8d2220d74110f7f9bcaf25feac69e368d1
TERRAFORM_SHA256_amd64=76edd0b22d2f27d3d2e097cd793209646f719cf60f02ff3af626b07361137da1
TERRAFORM_SHA256_arm64=0afa6c29f61ca5ea270e950e43e50ecf2418b598507bf580e8ae76e1e6699b19
DEPLOYER_USER=system:serviceaccount:smelt-deploy:smelt-deployer

step() { echo "== $*"; }
ok() { echo "OK${1:+ $1}"; }
fail() { echo "FAIL: $*" >&2; exit "${FAIL_RC:-1}"; }

sha_ok() { [[ "$1" =~ ^[0-9a-f]{12}$ ]]; }

# ~/deploy-<SHA>: the plan files live here, never in the repo (they hold
# secrets in clear).
deploy_dir() {
  local d="$HOME/deploy-$1"
  install -d -m 700 "$d"
  echo "$d"
}

sha256_of() { sha256sum "$1" | cut -d' ' -f1; }

#!/usr/bin/env bash
# Setup for a smelt deploy (SME-665), once per sandbox; safe to re-run.
#   smelt-deployer/deploy-setup.sh
# Installs kubectl and terraform into ~/bin (sha256-checked against the pins in
# deploy-lib.sh and the published checksum file), installs the deployer
# kubeconfig and checks who it is, builds the provider mirror, and inits.
#   deploy-setup.sh --download-only <dir>   (with DEPLOY_ARCH=arm64 to check the
#   other architecture) downloads and verifies both tools into <dir>, installs
#   nothing, and stops.
set -euo pipefail
# shellcheck source=smelt-deployer/deploy-lib.sh
. "$(dirname "$0")/deploy-lib.sh"

DOWNLOAD_ONLY=
if [ "${1:-}" = --download-only ]; then
  DOWNLOAD_ONLY=${2:?--download-only needs a directory}
  mkdir -p "$DOWNLOAD_ONLY"
fi
KUBECONFIG_SECRET=${DEPLOY_KUBECONFIG_SECRET:-/etc/smelt/secrets/deploy_kubeconfig}

# fetch <url> <dest>: one bounded download, no retry loop.
fetch() {
  curl -fsSL --retry 2 --connect-timeout 20 --max-time 600 -o "$2" "$1" ||
    fail "download failed: $1"
}

# require_sha <file> <published> <pinned> <what>
require_sha() {
  local got
  got=$(sha256_of "$1")
  [ "$2" = "$3" ] || fail "$4: the published sha256 $2 is not the pinned $3 (bump deploy-lib.sh with the version)"
  [ "$got" = "$3" ] || fail "$4: downloaded file's sha256 $got is not the pinned $3"
}

install_kubectl() {
  local pinned_var=KUBECTL_SHA256_$ARCH pinned tmp published
  pinned=${!pinned_var}
  step "kubectl $KUBECTL_VERSION linux/$ARCH"
  if [ -z "$DOWNLOAD_ONLY" ] && [ -x "$HOME/bin/kubectl" ] &&
     [ "$(sha256_of "$HOME/bin/kubectl")" = "$pinned" ]; then
    ok "already installed (sha256 matches the pin)"; return
  fi
  tmp=$(mktemp -d)
  local base="https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$ARCH/kubectl"
  fetch "$base" "$tmp/kubectl"
  fetch "$base.sha256" "$tmp/kubectl.sha256"
  published=$(tr -d '[:space:]' <"$tmp/kubectl.sha256")
  require_sha "$tmp/kubectl" "$published" "$pinned" kubectl
  if [ -n "$DOWNLOAD_ONLY" ]; then
    mv "$tmp/kubectl" "$DOWNLOAD_ONLY/kubectl"; rm -rf "$tmp"
    ok "verified $pinned (download only: $DOWNLOAD_ONLY/kubectl)"; return
  fi
  install -d "$HOME/bin"
  install -m 755 "$tmp/kubectl" "$HOME/bin/kubectl"
  rm -rf "$tmp"
  ok "installed, sha256 $pinned"
}

# The installed terraform reports the pinned version (read without the mirror
# config, which may not exist yet).
tf_version_ok() {
  local v
  v=$(env -u TF_CLI_CONFIG_FILE "$HOME/bin/terraform" version -json 2>/dev/null) || return 1
  [[ "$v" =~ \"terraform_version\":\ *\"$TERRAFORM_VERSION\" ]]
}

install_terraform() {
  local pinned_var=TERRAFORM_SHA256_$ARCH pinned tmp published zip
  pinned=${!pinned_var}
  zip=terraform_${TERRAFORM_VERSION}_linux_$ARCH.zip
  step "terraform $TERRAFORM_VERSION linux/$ARCH"
  if [ -z "$DOWNLOAD_ONLY" ] && [ -x "$HOME/bin/terraform" ] && [ -f "$HOME/bin/.terraform.sha256" ] &&
     [ "$(sha256_of "$HOME/bin/terraform")" = "$(cat "$HOME/bin/.terraform.sha256")" ] && tf_version_ok; then
    ok "already installed (version and sha256 match)"; return
  fi
  tmp=$(mktemp -d)
  local base="https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION"
  fetch "$base/$zip" "$tmp/$zip"
  fetch "$base/terraform_${TERRAFORM_VERSION}_SHA256SUMS" "$tmp/SHA256SUMS"
  published=$(awk -v z="$zip" '$2 == z { print $1 }' "$tmp/SHA256SUMS")
  require_sha "$tmp/$zip" "$published" "$pinned" "$zip"
  if [ -n "$DOWNLOAD_ONLY" ]; then
    mv "$tmp/$zip" "$DOWNLOAD_ONLY/$zip"; rm -rf "$tmp"
    ok "verified $pinned (download only: $DOWNLOAD_ONLY/$zip)"; return
  fi
  # The sandbox has no unzip.
  python3 -I -m zipfile -e "$tmp/$zip" "$tmp/x"
  install -d "$HOME/bin"
  install -m 755 "$tmp/x/terraform" "$HOME/bin/terraform"
  sha256_of "$HOME/bin/terraform" >"$HOME/bin/.terraform.sha256"
  rm -rf "$tmp"
  tf_version_ok || fail "terraform version -json doesn't report $TERRAFORM_VERSION"
  ok "installed, zip sha256 $pinned"
}

install_kubeconfig() {
  local ctx who
  step "kubeconfig"
  [ -f "$KUBECONFIG_SECRET" ] ||
    fail "$KUBECONFIG_SECRET is missing: this seat needs the deploy_kubeconfig credential (stop and report)"
  # Copied, never printed.
  install -d -m 700 "$HOME/.kube"
  install -m 600 "$KUBECONFIG_SECRET" "$HOME/.kube/config"
  ctx=$(kubectl config current-context 2>/dev/null) || fail "kubectl config current-context failed"
  [ "$ctx" = default ] || fail "the kubeconfig's context is '$ctx', not 'default' (this repo's provider and backend select 'default')"
  who=$(kubectl auth whoami -o jsonpath='{.status.userInfo.username}' 2>/dev/null) ||
    fail "kubectl auth whoami failed"
  [ "$who" = "$DEPLOYER_USER" ] || fail "whoami is '$who', not $DEPLOYER_USER"
  ok "context default, whoami $who"
}

build_mirror() {
  local log="$HOME/deploy-setup-mirror.log" last n
  step "provider mirror (SME-465), linux_$ARCH"
  if ! python3 -I smelt-deployer/tf_provider_mirror.py --target "linux_$ARCH" 2>&1 | tee "$log"; then
    fail "tf_provider_mirror.py exited non-zero (see $log; no fallback, no retry)"
  fi
  last=$(tail -n 1 "$log")
  [[ "$last" =~ ([0-9]+)\ provider\(s\)\ pinned\ to\ the\ mirror ]] ||
    fail "the mirror's last line has no pin count: $last"
  n=${BASH_REMATCH[1]}
  [ "$n" -ge "$EXPECTED_PINS" ] || fail "$n provider(s) pinned, expected $EXPECTED_PINS"
  [ "$n" -eq "$EXPECTED_PINS" ] ||
    echo "note: $n pins, more than EXPECTED_PINS=$EXPECTED_PINS; update deploy-lib.sh"
  PINS=$n
  ok "$n provider(s) pinned"
}

install_kubectl
install_terraform
if [ -n "$DOWNLOAD_ONLY" ]; then
  echo "setup: download-only OK (linux/$ARCH, nothing installed)"
  exit 0
fi
install_kubeconfig
build_mirror
step "terraform init"
terraform init -input=false || fail "terraform init failed"
ok
echo "setup: OK (kubectl $KUBECTL_VERSION, terraform $TERRAFORM_VERSION, linux/$ARCH, whoami smelt-deployer, $PINS pins)"

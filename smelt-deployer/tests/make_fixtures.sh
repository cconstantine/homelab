#!/usr/bin/env bash
# How tests/fixtures/*.json were made (SME-665). Kept for the record; the tests
# never run it. It needs docker, k3d, terraform 1.15.9 on PATH, the git-ssh key
# (the smelt repo is private) and network. It touches nothing but a throwaway
# k3d cluster of its own:
#
#   smelt-deployer/tests/make_fixtures.sh <workdir>
#
# The root is homelab-shaped: `module "smelt"` from the smelt repo at a SHA, and
# a stand-in local `module "monitoring"` whose output feeds `extra_env`, as
# homelab's Tempo endpoint does. It applies at image/ref A, then plans with
# -target=module.smelt for each case, and saves `terraform show -json`
# sanitised by sanitize_plan.py (which refuses to write a file holding the
# database password). The cluster recipe is smelt's
# terraform/test-cluster/main.tf (k3s v1.34.6-k3s1; images imported, since the
# sandbox's docker can't reach GHCR from a container).
set -euo pipefail

WORK=${1:?usage: make_fixtures.sh <workdir>}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HERE/fixtures
CLUSTER=sme665-fixtures
# Two applies. At A, plan module-changed: C's terraform/smelt changes resource
# attributes (SME-335's LimitRange defaults, e5936494). A's LimitRange leaves
# `default` for the API server to fill, a perpetual diff, so every other case
# is planned after a second apply at C. D: a later main whose module changes
# (SME-521, SME-664's prevent_destroy) alter nothing in this root, so C -> D is
# a real image-only deploy with a moved ref, and D gives the HARD STOP capture.
A=bad6724593f4
C=8494afbafc47
D=934ba4dbb2b4
PG=postgres:17-alpine

export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=url.git@github.com:cconstantine/smelt.git.insteadOf
export GIT_CONFIG_VALUE_0=https://github.com/cconstantine/smelt.git
export TF_IN_AUTOMATION=1

mkdir -p "$WORK" "$OUT"
cd "$WORK"
KUBECONFIG_FILE=$WORK/kubeconfig

echo "== k3d cluster $CLUSTER"
if ! k3d cluster list "$CLUSTER" >/dev/null 2>&1; then
  k3d cluster create "$CLUSTER" --image rancher/k3s:v1.34.6-k3s1 --wait
fi
k3d kubeconfig get "$CLUSTER" | sed 's/0\.0\.0\.0/127.0.0.1/' >"$KUBECONFIG_FILE"
chmod 600 "$KUBECONFIG_FILE"

echo "== images into the node (A's and C's server images, Postgres)"
for img in "ghcr.io/cconstantine/smelt:$A" "ghcr.io/cconstantine/smelt:$C" "$PG"; do
  docker image inspect "$img" >/dev/null 2>&1 || docker pull -q "$img"
done
# test-cluster/main.tf's recipe (k3d's own import needs the docker socket
# inside its tools container, which this sandbox's daemon doesn't offer).
docker save -o "$WORK/images.tar" "ghcr.io/cconstantine/smelt:$A" "ghcr.io/cconstantine/smelt:$C" "$PG"
docker cp "$WORK/images.tar" "k3d-$CLUSTER-server-0:/tmp/images.tar"
docker exec "k3d-$CLUSTER-server-0" \
  ctr --address /run/k3s/containerd/containerd.sock -n k8s.io images import /tmp/images.tar
docker exec "k3d-$CLUSTER-server-0" rm -f /tmp/images.tar
rm -f "$WORK/images.tar"

# root <source> <image sha> <monitoring data> [namespace]
root() {
  local src=$1 img=$2 data=$3 ns=${4:-smelt-park}
  mkdir -p monitoring
  cat >monitoring/main.tf <<EOF
# Stand-in for homelab's monitoring module: one object, and an output built
# from it that smelt's extra_env reads (as tempo_otlp_http_endpoint is).
variable "data" { type = string }
resource "kubernetes_namespace_v1" "monitoring" {
  metadata { name = "monitoring" }
}
resource "kubernetes_config_map_v1" "tempo" {
  metadata {
    name      = "tempo"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  data = { "tempo.yaml" = var.data }
}
output "tempo_otlp_http_endpoint" {
  value = "http://\${kubernetes_config_map_v1.tempo.metadata[0].name}.\${kubernetes_config_map_v1.tempo.metadata[0].namespace}.svc.cluster.local:4318"
}
EOF
  cat >main.tf <<EOF
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
  }
}
provider "kubernetes" {
  config_path    = "$KUBECONFIG_FILE"
  config_context = "k3d-$CLUSTER"
}
module "monitoring" {
  source = "./monitoring"
  data   = "$data"
}
module "smelt" {
  source = "$src"

  image         = "ghcr.io/cconstantine/smelt:$img"
  sandbox_image = "ghcr.io/cconstantine/smelt-sandbox:$img"

  namespace      = "$ns"
  preview_domain = "preview.smelt.constantlee.us"
  domain         = "smelt.constantlee.us"

  # k3d only: at A the LimitRange's 64Gi default lands on the init container
  # (SME-335's bug), more than a k3d node has, so the pod never schedules.
  sandbox_pod_memory_max = "4Gi"

  extra_env = {
    OTEL_EXPORTER_OTLP_ENDPOINT = module.monitoring.tempo_otlp_http_endpoint
    SANDBOX_NODE_SELECTOR       = "kubernetes.io/arch=amd64"
  }
}
EOF
}
git_src() { echo "git::https://github.com/cconstantine/smelt.git//terraform/smelt?ref=$1"; }

# plan_case <name>: plan the current root, save sanitised JSON as <name>.json
plan_case() {
  echo "== plan: $1"
  terraform init -input=false -upgrade=false >/dev/null
  terraform plan -target=module.smelt -input=false -no-color -out="$WORK/$1.plan" |
    grep -E '^(Plan:|No changes|  # )' || true
  terraform show -json "$WORK/$1.plan" >"$WORK/$1.raw.json"
  chmod 600 "$WORK/$1.raw.json"
  python3 -I "$HERE/sanitize_plan.py" "$WORK/$1.raw.json" "$OUT/$1.json"
}

# apply_at <sha>
apply_at() {
  echo "== apply at $1"
  root "$(git_src "$1")" "$1" v1
  terraform init -input=false >/dev/null
  terraform apply -input=false -auto-approve -no-color | grep -E '^Apply complete!'
}

apply_at "$A"
root "$(git_src "$C")" "$C" v1; plan_case module-changed

apply_at "$C"
root "$(git_src "$C")" "$C" v1; plan_case no-changes
root "$(git_src "$D")" "$D" v1; plan_case image-only
root "$(git_src "$C")" "$C" v2; plan_case out-of-module

echo "== replace-in-module: a local copy of C's module, the server Service renamed"
[ -d smelt-src ] || git clone -q git@github.com:cconstantine/smelt.git smelt-src
git -C smelt-src checkout -q "$C"
rm -rf smelt-copy && cp -r smelt-src/terraform/smelt smelt-copy
python3 -I - smelt-copy/server.tf <<'EOF'
import re, sys
p = sys.argv[1]; s = open(p).read()
# resource "kubernetes_service_v1" "smelt" { metadata { name = "smelt" ...
new, n = re.subn(r'(resource "kubernetes_service_v1" "smelt" \{\s*metadata \{\s*name\s*=\s*)"smelt"', r'\1"smelt-renamed"', s)
assert n == 1, "service name not found"
open(p, "w").write(new)
EOF
root "./smelt-copy" "$C" v1; plan_case replace-in-module

echo "== prevent_destroy capture: D's module, the namespace renamed"
root "$(git_src "$D")" "$C" v1 smelt-park-renamed
terraform init -input=false >/dev/null
set +e
terraform plan -target=module.smelt -input=false -no-color >"$OUT/prevent-destroy-plan-run.txt" 2>&1
echo "plan rc=$? (expected 1)"
set -e
grep -c 'Instance cannot be destroyed' "$OUT/prevent-destroy-plan-run.txt"

echo "== done; tear down with: k3d cluster delete $CLUSTER && rm -rf $WORK"

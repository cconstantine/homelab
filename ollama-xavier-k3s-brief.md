# Brief: run hardware-accelerated Ollama on the Jetson AGX Xavier as a k3s service

**Audience:** the Claude instance that will write the Terraform/k8s manifests.
**Goal:** deploy Ollama as a k3s workload pinned to the `xavier` node with working GPU
(CUDA) acceleration, mirroring how the Ryzen Ollama is already hosted.

---

## 1. Cluster context (already in place — verified by inspection)

Three-node k3s cluster (kubeconfig at `~/k3s.yaml`):

| Node | arch | role | GPU label | k3s/containerd |
|---|---|---|---|---|
| homelab | amd64 | control-plane | — | v1.34.6, containerd 2.2.2 |
| ryzen | amd64 | worker | `nvidia.com/gpu.type=discrete` | v1.34.6, containerd 2.2.2 |
| **xavier** | **arm64** | worker | **`nvidia.com/gpu.type=tegra`**, `nvidia.com/gpu.present=true` | v1.31.9, containerd 2.0.5 |

- A `nvidia` **RuntimeClass** already exists (handler `nvidia`).
- The xavier node already carries NVIDIA GPU labels (node-feature-discovery / GPU
  operator labels are applied), so no node labeling work is needed.

## 2. Two existing workloads to copy from

**(A) `ollama-ryzen` Deployment in namespace `ai` — the APPLICATION template.**
Spec (the parts that matter):
- `image: ollama/ollama`
- `nodeSelector: { nvidia.com/gpu.type: discrete }`   ← change to `tegra` for Xavier
- `runtimeClassName: nvidia`
- `resources: { limits: { nvidia.com/gpu: 1 }, requests: { nvidia.com/gpu: 1 } }`
- env:
  `NVIDIA_VISIBLE_DEVICES=all`, `NVIDIA_DRIVER_CAPABILITIES=all`,
  `OLLAMA_HOST=0.0.0.0:11435`, `OLLAMA_NUM_GPU=999`, `OLLAMA_FLASH_ATTENTION=1`,
  `OLLAMA_KV_CACHE_TYPE=q8_0`, `OLLAMA_NUM_THREAD=32`, `OLLAMA_NUM_PARALLEL=1`,
  `OLLAMA_MAX_LOADED_MODELS=1`
- volume: `ollama-models` (hostPath) → mounted at `/root/.ollama`
- **sidecar** `ollama-metrics` (`python:3.11-slim`) listening on `:11434`, proxying to
  the ollama container on `localhost:11435`; script from a configMap (`exporter-script`),
  deps installed into an emptyDir (`exporter-packages`). The `ai/ollama-ryzen` Service
  targets **11434** (the metrics port), not 11435.
- Get the full source of truth with:
  `kubectl --kubeconfig ~/k3s.yaml get deploy ollama-ryzen -n ai -o yaml`

**(B) `frigate` StatefulSet in namespace `frigate` — the TEGRA-GPU mechanism reference.**
It is the proof of how GPU works on the Jetson node in this cluster:
- `runtimeClassName: nvidia`
- `resources: { limits: { nvidia.com/gpu: 1 } }`
- `nodeSelector: { nvidia.com/gpu.present: "true" }`
- **No CUDA/tegra hostPath mounts, no NVIDIA_* env.** GPU libraries are injected
  automatically (see §3).
- image `ghcr.io/.../frigate:stable-tensorrt-jp5` is **arm64-only**, which is what
  actually pins it to the xavier node.
- Source: `kubectl --kubeconfig ~/k3s.yaml get statefulset frigate -n frigate -o yaml`

## 3. How GPU acceleration works on the Jetson here (the key insight)

On Jetson/L4T you do **not** manually mount CUDA. The host's
`nvidia-container-runtime` is configured in **CSV mode**:
- `/etc/nvidia-container-runtime/config.toml` → `mode = "auto"`, csv mode enabled
- `/etc/nvidia-container-runtime/host-files-for-container.d/l4t.csv` lists the L4T
  driver + CUDA libraries that the runtime **auto-injects** into any container started
  under the `nvidia` runtimeClass.

So the recipe for a tegra GPU pod is simply: **`runtimeClassName: nvidia` +
`resources: nvidia.com/gpu: 1`**. The `l4t.csv` injection supplies `libcuda`, the Tegra
GPU device nodes, and the CUDA userspace libs. This is exactly what frigate relies on.

**Host platform facts (for image selection):**
- L4T **R35.5.0** (= JetPack 5.1.2), Ubuntu 20.04, kernel 5.10.192-tegra
- Jetson AGX Xavier, Volta GPU, CUDA compute capability **7.2**, **unified memory**
  (CPU+GPU share ~30GB RAM; usable GPU budget ≈ 24GB at 32k ctx — see capacity results)

## 4. Image choice — **two axes: CUDA-must-work AND ollama-must-be-recent**

> ⚠️ **FIELD FINDING (verified by deploying it).** The first deployment used
> `dustynv/ollama:r35.4.1`. GPU acceleration worked perfectly — `offloaded 33/33 layers
> to GPU`, mistral at **18 tok/s**, CUDA detected (`library=cuda compute=7.2 driver=11.4
> name=Xavier available=23.8 GiB`). **But that image ships ollama `0.1.46` (mid-2024),
> which is too old to load the models we actually need:** qwen3.5/qwen3.6/qwen3-coder/
> qwen3:30b-a3b/gpt-oss all fail with `unknown model architecture: 'qwen35'` (their
> llama.cpp architectures postdate that build). Only legacy-arch models (mistral, llama2)
> load. **So image choice has two requirements, not one: (a) CUDA works on L4T, AND
> (b) the ollama/llama.cpp version is new enough for the target model architectures.**

The native host binary proves a modern ollama runs GPU-accelerated on this Jetson: it was
**ollama 0.30.10** using its bundled `cuda_jetpack5` build, and it ran qwen3:30b-a3b etc.
fine. So the goal is a **recent ollama** that also has the JetPack-5 CUDA build.

Options, in recommended order:

1. **Official `ollama/ollama` (arm64), pinned to a recent tag (≥0.3x).** Modern multi-arch
   images bundle the jetpack CUDA variant and pick `cuda_jetpack5` at runtime; with the
   `l4t.csv` driver injection (§3) this is expected to work on L4T R35, and it is new
   enough for all target models. Lowest maintenance — same image family as Ryzen.
   **Recommended.** Verify GPU offload per §7 (don't assume).
2. **A NEWER `dustynv/ollama` tag** (not `r35.4.1`). The jetson-containers project
   publishes updated builds; pick one whose embedded ollama is ≥0.3x. Jetson-guaranteed
   CUDA, but you must check the ollama version inside it
   (`docker run --rm <tag> ollama --version`) before trusting it for qwen3.x.
3. ❌ `dustynv/ollama:r35.4.1` — **do not use for this workload.** GPU is fine but
   ollama 0.1.46 cannot load the qwen3.x / gpt-oss architectures.

**Action for the current deployment:** bump the image to option 1 (or 2) and redeploy;
keep everything else (runtimeClass, nodeSelector, hostNetwork, GPU resources, volume) as
is. Then re-run §7 verification with a *target* model (e.g. `qwen3:8b`), not mistral.

## 5. Concrete deltas: `ollama-ryzen` → `ollama-xavier`

- `nodeSelector: { nvidia.com/gpu.type: tegra }`  (pins to xavier; arm64 image reinforces it)
- keep `runtimeClassName: nvidia` and `resources.nvidia.com/gpu: 1`
- keep the `NVIDIA_VISIBLE_DEVICES=all` / `NVIDIA_DRIVER_CAPABILITIES=all` env
- **model storage — use FRESH storage, do NOT reuse the old host store.** Provision a
  new volume for the pod (a PVC on the cluster's default StorageClass, or a fresh empty
  hostPath dir dedicated to this deployment) mounted at `/root/.ollama`. Models will be
  re-pulled into it on first use (`ollama pull` / first request). Do **not** mount the
  old `/var/lib/rancher/scratch_for_claude/llm-workspace/models` directory — that store
  belonged to the now-retired bare process and is being left behind by choice.
  - size the volume for the models you intend to run (the candidate set is ~60–100 GB;
    pick a PVC size with headroom).
- **env tuning for Xavier** (unified memory, smaller budget than Ryzen):
  - `OLLAMA_KV_CACHE_TYPE=q8_0` and `OLLAMA_FLASH_ATTENTION=1` — keep (helps fit)
  - `OLLAMA_MAX_LOADED_MODELS=1`, `OLLAMA_NUM_PARALLEL=1` — keep (memory is tight)
  - `OLLAMA_NUM_THREAD` — Xavier has 8 CPU cores (vs Ryzen 32); set ~`8`, not 32
  - consider `OLLAMA_KEEP_ALIVE` to control eviction
- **Service**: create `ollama-xavier` (ClusterIP, port 11434 → metrics sidecar, or
  directly 11435 if you skip the sidecar). NOTE there is already an orphan Service
  `ai/ollama` (selector `name=ollama`, currently **no endpoints**) — decide whether the
  new pod should adopt that selector/label to back it, or use a fresh `ollama-xavier`.

## 6. Migration / cutover notes

- The **bare `ollama serve` that used to run on the host has already been stopped** (it
  was the user binary `~/.local/bin/ollama` v0.30.10 on `:11434`). The GPU, unified
  memory, and **port 11434 on the host are now free**, so the pod can claim the port
  (even via `hostNetwork`/`hostPort`) without contention. No process needs stopping.
- The pod uses its **own fresh model volume** (§5) — there is no shared-store or
  double-load concern with anything on the host.
- Anything that previously talked to `http://xavier:11434` / `localhost:11434` (e.g. the
  benchmark harness in this workspace) must be **repointed at the new Service**, since the
  host no longer serves Ollama.
- **k3s on xavier is v1.31** (older than the v1.34 control-plane/ryzen) — keep manifest
  apiVersions compatible with 1.31.

## 7. Verification (after apply)

1. `kubectl -n ai get pod -l app=ollama-xavier -o wide` → Running, **NODE=xavier**.
2. **Check the ollama version is new enough** (the §4 gotcha):
   `kubectl -n ai exec deploy/ollama-xavier -c ollama -- ollama --version` → must be
   **≥ 0.3x**. `0.1.46` (the dustynv r35.4.1 default) will *not* run qwen3.x.
3. GPU visible inside the pod — check the ollama startup log for the CUDA runner:
   `kubectl -n ai logs deploy/ollama-xavier -c ollama | grep -iE "library=cuda|offloaded"`.
   Expect a line like `inference compute ... library=cuda compute=7.2 ... name=Xavier
   available=23.8 GiB`. (`nvidia-smi` may be limited on Jetson; the log is authoritative.)
4. **Load a TARGET model, not mistral** — confirms both CUDA *and* a new-enough engine.
   The fresh volume starts empty, so pull first, then run:
   `kubectl -n ai exec deploy/ollama-xavier -c ollama -- ollama pull qwen3:8b` then
   `kubectl -n ai exec deploy/ollama-xavier -c ollama -- ollama run qwen3:8b "hi"`.
   Two distinct failure modes to distinguish:
   - `unknown model architecture` / `core dumped` on load → **engine too old** (§4); the
     image needs a newer ollama, not a different GPU setup.
   - loads but runs at CPU-only speed (~3-4 tok/s instead of ~12) → **CUDA not engaged**;
     check runtimeClass/`l4t.csv` injection.
   Success = `offloaded N/N layers to GPU` in the log and tok/s ≈ the capacity table
   (qwen3:8b ≈ 12 tok/s). Confirmed working reference: mistral hit 18 tok/s, 33/33 layers.
5. Reachability from cluster: `curl http://ollama-xavier.ai:11434/api/tags`.

## 8. Quick reference — commands used to gather the above
```
kubectl --kubeconfig ~/k3s.yaml get nodes -o wide --show-labels
kubectl --kubeconfig ~/k3s.yaml get deploy ollama-ryzen -n ai -o yaml      # app template
kubectl --kubeconfig ~/k3s.yaml get statefulset frigate -n frigate -o yaml # tegra GPU ref
kubectl --kubeconfig ~/k3s.yaml get runtimeclass
cat /etc/nvidia-container-runtime/config.toml                               # csv mode
ls  /etc/nvidia-container-runtime/host-files-for-container.d/               # l4t.csv
```

# Longhorn rollout plan

Written 2026-11-03, from a read-only inspection of the cluster. Rechecked against
the cluster on 2026-11-09. Nothing in this plan has been applied yet.

## Summary

Start small: install Longhorn on four nodes, keep replicas on three, and move
only low-write apps. The candidates hold only a few GB, so disk space is no
problem. The network is the real constraint: only `ryzen` and `homelab` have the
10 Gbps that Longhorn recommends. `ryzen`'s memory is the other constraint: it is
nearly full, so Longhorn's footprint there is kept to the minimum.

## Goals

- Let apps with SQLite, hardlink, `inotify` or locking needs run without being
  tied to one host, using RWO volumes with a real ext4 filesystem.
- Give claude-park a small read-write volume mountable from several hosts, for
  shared credentials and settings, using RWX.

## Limits to keep in mind

- RWO volumes attach to one node at a time. Several pods can share one only if
  they run on the same node.
- RWX is NFS underneath, so NFS limitations apply: no SQLite across hosts, no
  cross-host `inotify`, and non-atomic appends across hosts.
- Replicas are not backups, because deletes and corruption reach every replica.
- Longhorn sizes are booked in full when placing replicas, even if the volume is
  empty, so high-churn volumes stay on `local-path`.

## Decisions

1. **`ryzen` is a replica node,** with strict limits on what Longhorn runs there
   (see "Memory on `ryzen`").
2. **No alerts for now.** Longhorn's metrics get scraped so they can be graphed,
   but nothing pages. This means disk space and volume health have to be checked
   by hand during the trial.

## Current state (2026-11-09)

### Nodes

| Node | Link | Disk for replicas | Free | iSCSI ready? | Role |
|---|---|---|---|---|---|
| `homelab` | 10G | SATA SSD, `/var/lib/rancher` | 436 of 983 GB | Yes, 2.1.3 | Replicas, capped low |
| `ryzen` | 10G | NVMe root disk | 1121 of 1963 GB | No | Replicas, memory-limited |
| `cachyos-x8664` | 1G | NVMe root disk | 1225 of 1963 GB | No | Replicas |
| `system76` | 1G | NVMe root disk | 389 of 979 GB | No | Client only for now |
| `xavier-vm` | ? | 16 GB root, 421 GB `/var/lib/rancher` | 394 GB | Unchecked | Excluded |

All nodes run Kubernetes 1.34.6, which meets Longhorn 1.13's minimum of 1.34.
The three CachyOS nodes all have the `iscsi_tcp` module available, and their
repositories offer `open-iscsi` 2.1.13, so the 2.1.12 version Longhorn warns
against isn't an issue.

Node notes:

- `homelab`: the SSD also holds the k3s datastore and 139 sandbox volumes. It is
  the only control-plane node, so pods can't be rescheduled while it is down.
- `ryzen`: a workstation with a `dedicated=strata:NoSchedule` taint. Strata
  requests 72 Gi and uses about 74 Gi, with no memory limit. The node has 93 GB,
  with 75 GB in use and 18 GB available.
- `cachyos-x8664`: now the main sandbox node, with 378 `smelt-park` volumes, so
  replicas there will compete with sandbox disk I/O. It has 31 GB of memory, of
  which about 5 GB is used.
- `system76`: holds all 60 `claude-park` volumes. It has 31 GB of memory, with
  11 GB available.
- `xavier-vm`: replaced `xavier`. It's an arm64 Firecracker VM for arm runners
  and sandboxes, with slow cores and a soft
  `homelab/vm=firecracker:PreferNoSchedule` taint. That taint is only a
  preference, so keeping Longhorn off it needs the node selector below.

### Workloads

| Workload | Data | Plan |
|---|---|---|
| Prowlarr | 22 MB | Move first, as the trial |
| `srvr` | 8 MB | Move next |
| Omniroute | 25 MB | Move next |
| `chat` | 895 MB | Move next |
| Grafana | 957 MB | Move next |
| Tempo | Not measured | Move next if its write load looks reasonable |
| Claude-park config and memory | 7 MB, 212 KB | RWX, after testing |
| `smelt-db` | 321 MB | Decide later; Postgres is sensitive to write latency |
| Prometheus | 278 GB | Stay: too write-heavy for 1G links |
| Registry | 4.7 GB | Stay: it shouldn't depend on Longhorn |
| Jellyfin, Sonarr, Radarr, qBittorrent | Up to 1.5 GB of config, plus media | Stay on `homelab` |
| Sandboxes, `docker`, ARC | Disposable | Stay on `local-path` |
| Frigate | 63 MB of config | Not a Longhorn candidate; see below |

Frigate now runs on `homelab`, but its config, including the SQLite database in
WAL mode, is still mounted over NFS from `homelab` itself. Separately from
Longhorn, move the database onto a local volume on `homelab` using
`database.path`, copying the file while Frigate is stopped.

## Phase 0: Prepare the nodes

**Done 2026-11-09.** `open-iscsi` 2.1.13 is installed on the three CachyOS nodes,
with `iscsi_tcp` loaded at boot and `iscsid` running. `longhornctl` 1.13.0
preflight was run per node, using a throwaway namespace. `ryzen` passed cleanly.
The others failed only on modules not being loaded (`nfs`, `dm_crypt`) and, on
`homelab`, a missing `cryptsetup`; `longhorn-phase0b.sh` fixes these by loading
both modules at boot. `ryzen` baseline before install: 73 of 93 GB used, 19 GB
available.

These steps need sudo on the hosts.

1. On `ryzen`, `cachyos-x8664` and `system76`:

   ```sh
   sudo pacman -S open-iscsi          # 2.1.13
   echo iscsi_tcp | sudo tee /etc/modules-load.d/iscsi_tcp.conf
   sudo modprobe iscsi_tcp
   sudo systemctl enable --now iscsid
   ```

   `homelab` already has this done.
2. Run `longhornctl` preflight checks on the four nodes.
3. Record a memory baseline for `ryzen` before installing, to compare against
   later.

## Phase 1: Install through Terraform

**Applied 2026-11-09** (`terraform apply -target=module.longhorn`). All 29 pods
run where intended; `ryzen` has only the manager, instance manager, engine image
and CSI plugin, using about 120 Mi together. `ryzen` and `cachyos-x8664` have
their 200 GiB disks, and `homelab` its 100 GiB disk. Longhorn won't create a
disk path that doesn't exist: `/var/lib/rancher/longhorn` on `homelab` had to be
made by hand, after which Longhorn added the disk on its own. Two fixes were
needed after the first apply:

- `guaranteedInstanceManagerCPU` must list both engines (`{"v1":"5","v2":"12"}`);
  `{"v1":"5"}` alone is rejected and the default 12% is silently kept.
- `networkPolicies.restrictInternalTraffic` (on by default) adds NetworkPolicies
  even with `networkPolicies.enabled: false`, and k3s enforces them, so
  Prometheus was blocked until it was added to `metricsScrapeSources`.

The module is `longhorn-storage/` (wired in `longhorn.tf`); its Helm values are
in `longhorn-storage/values.yaml`. Use Helm chart `longhorn/longhorn` 1.13.0 from `https://charts.longhorn.io`, in
the `longhorn-system` namespace. These value paths are confirmed in the 1.13.0
chart:

```yaml
persistence:
  defaultClass: false                  # keep local-path as the default
global:
  nodeSelector: {homelab/longhorn: "true"}   # homelab, ryzen, cachyos-x8664, system76
  tolerations: [dedicated=strata:NoSchedule]
defaultSettings:
  systemManagedComponentsNodeSelector: "homelab/longhorn:true"
  taintToleration: "dedicated=strata:NoSchedule"
  createDefaultDiskLabeledNodes: true
  nodeDownPodDeletionPolicy: delete-both-statefulset-and-deployment-pod
  guaranteedInstanceManagerCPU: {v1: "5", v2: "12"}   # both engines required
# Keep the non-node-bound Deployments off ryzen (see below):
longhornGlobalManager: {nodeSelector: {homelab/longhorn-control: "true"}}
longhornDriver:        {nodeSelector: {homelab/longhorn-control: "true"}}
longhornUI:            {nodeSelector: {homelab/longhorn-control: "true"}}
longhornManager:
  serviceAnnotations: {prometheus.io/scrape: "true", prometheus.io/port: "9500"}
networkPolicies:
  metricsScrapeSources: [monitoring/prometheus]   # see above
```

Render the chart (`helm template`) before applying, and check every pod's node
selector and tolerations in the output.

- **Default class:** `persistence.defaultClass: false` is the critical setting.
  Sandboxes don't set a storage class (the smelt Terraform only sets one for its
  database), so they use the default. k3s also manages `local-path` as a bundled
  addon, so changing the default later needs its own check.
- **Node labels:**
  - `homelab/longhorn=true` on `homelab`, `ryzen`, `cachyos-x8664` and
    `system76`. This is where Longhorn runs at all. `system76` needs it to attach
    volumes even without a disk.
  - `homelab/longhorn-control=true` on `homelab`, `cachyos-x8664` and `system76`.
    This is where the global manager (3 replicas, spread one per node), the driver
    deployer and the UI run.
- **Disks:** label and annotate each replica node with
  `node.longhorn.io/create-default-disk=config` and
  `node.longhorn.io/default-disks-config`. `homelab` must use
  `/var/lib/rancher/longhorn`, since the default path is on its small root disk.
  Set these before Longhorn adds the node, because the annotation only applies to
  a node with no existing disks or tags.
- **Starting capacity:** cap bookable space at about 100 GB on `homelab`, and
  200 GB each on `ryzen` and `cachyos-x8664`. `system76` gets no disk.
- **Storage classes:** add `longhorn-r2` with 2 replicas, expansion enabled,
  `Retain`, and `best-effort` data locality (replicas follow the pod to nodes with
  a Longhorn disk; changed from `disabled` on 2026-11-09), and
  later `longhorn-rwx`. Don't modify the chart's own `longhorn` class.
- **Backups:** send them to a new `/storage/longhorn-backups` over NFS, using the
  IP address (`192.168.8.130`), because pods may not resolve `homelab.local`.
- **Monitoring:** scrape Longhorn's metrics for graphs only. No alerts.

### Memory on `ryzen`

Strata leaves about 18 GB free, and it has no memory limit, so Longhorn must
stay small there and never be the reason Strata is OOM-killed.

- **Only node-bound components run there:** `longhorn-manager`, the CSI plugin,
  the instance manager and the engine image. The global manager, driver deployer
  and UI are kept off by the `homelab/longhorn-control` label. The CSI controller sidecars
  (attacher, provisioner, resizer, snapshotter) follow the system-managed node
  selector and may land there; they're small, and
  `systemManagedCSIComponentsResourceLimits` can cap them.
- **Keep replica count low there:** the 200 GB disk cap limits how many replicas
  `ryzen` can hold. Each replica is a process in the instance manager, so fewer
  replicas means less memory.
- **Never attach volumes on `ryzen`:** no Longhorn-backed workload should be
  scheduled there, so it runs no engines and no RWX share-managers. Most apps
  can't run there anyway because of the Strata taint, but check that nothing
  being moved tolerates it.
- **Measure it:** record `ryzen`'s memory before installing, then after install,
  after the Prowlarr volume is created, and during a replica rebuild. Check
  `kubectl top pod -n longhorn-system` filtered to `ryzen`. Expect well under
  1 GB in total. If it grows past that, or available memory drops below about
  8 GB, set `ryzen`'s Longhorn node to unschedulable for replicas, evict them and
  fall back to `system76`.

## Phase 2: Trial with Prowlarr

**Moved 2026-11-09.** Prowlarr runs from `prowlarr-config-longhorn` (1 GiB,
`longhorn-r2`, replicas on `ryzen` and `cachyos-x8664`), pinned to
`homelab/longhorn-control` nodes. It landed on `cachyos-x8664`. Data was copied
with Prowlarr stopped; all files matched by checksum (except `logs.db`, whose WAL
the integrity check folded in) and both databases passed `integrity_check`. The
old `prowlarr-config` PVC and PV are still in Terraform, unused, as the rollback.
Longhorn on `ryzen` with one replica: about 217 Mi.

**Backup and restore verified 2026-11-09.** Backup target is
`nfs://192.168.8.130:/storage/longhorn-backups` (directory made as root over the
`no_root_squash` export). A backup of the Prowlarr volume was restored to a
scratch volume: both databases passed `integrity_check`, the indexer count
matched, and all 624 static files matched the live volume. The backup
`prowlarr-restore-test` is kept. No recurring backup job exists yet.

The week of running it is replaced by claude-park's use of Longhorn, managed
from that project. Not done: the move to another node and the replica-node
reboot.

1. Stop Prowlarr, copy its data to a 1 GiB Longhorn volume, and start it again. The
   old volume uses `Retain`, so it stays as the rollback.
2. Run SQLite's `integrity_check`, then restore a backup to prove backups work.
3. Move the pod to another node, then reboot a replica node and watch it recover.
4. Run it like this for about a week, watching latency, rebuilds and `ryzen`'s
   memory. With no alerts, check volume health and disk space by hand.

## Phase 3: Move the other apps, one at a time

- **Protect data first:** `srvr`, Grafana and Tempo use `local-path` with a
  `Delete` reclaim policy, so removing the old PVC destroys the data. Set those PVs
  to `Retain` before touching them.
- **Remove the pins:** drop the `homelab` node selectors from Omniroute and Tempo.
  Prowlarr and `chat` have no selector but are tied to `homelab` by their
  `/storage` volumes, which goes away when they move.
- **Keep Longhorn workloads off `xavier-vm` and `ryzen`:** use node affinity for
  any pod with a Longhorn volume.
- **Fix Grafana's rollout:** it uses `RollingUpdate`, which can stall on RWO, so
  switch it to `Recreate`.
- **StatefulSets:** volume templates can't be edited, so `srvr` and `chat` need
  their StatefulSets recreated.
- **Sizing:** set each volume to a realistic maximum based on current use, then
  expand it if needed. Don't carry over labels like Omniroute's 20 Gi.

## Phase 4: Claude-park RWX test

0. Work out which claude-park volumes are live. Each shared volume
   (`claude-park-config`, `-memory`, `-results`, `-seed`, `obsidian-mcp-*`,
   `park-broker-state`) has a `-mv` copy from a `park-move` run on 2026-10-28,
   marked `move-verified`. Both copies are on `system76`.
1. Run two parks on `system76` and `cachyos-x8664` against a copy of the config,
   and test these files:

   | File | Risk | What to do |
   |---|---|---|
   | `history.jsonl` | Appends from several hosts can get garbled | Symlink it per park, giving up shared prompt history |
   | `.credentials.json` | Parks on different hosts could refresh the token at the same time | Test it; cross-host locking isn't confirmed |
   | `settings.json` | A running session on another host may not notice edits | Test it |
   | `daemon.lock`, `scheduled_tasks.lock` | These may assume a single host | Check what uses them, and make them per-park if needed |

2. If that passes, change the park tooling, which isn't in this repo or under
   `~/workspace`. `workspace` and `docker` stay on `local-path`, so existing parks
   stay on their node, but new ones can start on either.

## Other findings

- **Unattached volumes:** 518 of 531 `smelt-park` PVCs and 44 of 60 in
  `claude-park` aren't attached to any pod. The sandbox ones are spread across
  `cachyos-x8664` (378), `homelab` (139) and `system76` (14). Check their
  retention, since they take space on two of the replica nodes.
- **Open NFS export:** `/storage` is exported to `*` with `no_root_squash`, so any
  host that can reach it gets root access to the files. Restrict it to
  `192.168.8.0/24`, or tighter.
- **Prometheus directory:** it's using 278 GB against a 100 GiB label, and it
  contains stray `webui.db` and `vector_db` files that look like they came from
  `chat`.
- **SSH:** reach nodes by hostname (`ryzen`, `cachyos-x8664`, `system76`,
  `homelab.local`). Their IP addresses aren't in `known_hosts`.

## References

- [Longhorn best practices](https://longhorn.io/docs/latest/best-practices/)
- [Installation requirements](https://longhorn.io/docs/latest/deploy/install/)
- [Install with Helm](https://longhorn.io/docs/latest/deploy/install/install-with-helm/)
- [Default disk and node configuration](https://longhorn.io/docs/latest/nodes-and-volumes/nodes/default-disk-and-node-config/)
- [Node selector](https://longhorn.io/docs/latest/advanced-resources/deploy/node-selector/)
- [Taints and tolerations](https://longhorn.io/docs/latest/advanced-resources/deploy/taint-toleration/)
- [Settings reference](https://longhorn.io/docs/latest/references/settings/)

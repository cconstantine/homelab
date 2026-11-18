#!/usr/bin/env python3
# Generates resource-reservations.json (the "Resource reservations" Grafana
# dashboard). Edit this, not the JSON, then regenerate:
#   python3 monitoring/dashboards/gen_resource_reservations.py > monitoring/dashboards/resource-reservations.json
# Only *.json in this folder goes into the grafana-dashboards config map.
#
# Laid out as a top-down drill-down for "pods won't schedule":
#   1. Is anything stuck, and is there a node with room for it?
#   2. Which nodes are full?
#   3. Which namespace is holding the reservations?   (click -> filter)
#   4. Within it, which workloads -- many pods, or a few big ones? (click -> filter)
#   5. The individual pods.
# Sources: kube-state-metrics (requests, limits, allocatable, pod state), cAdvisor
# (usage), and the namespace_workload_pod:kube_pod_owner:relabel recording rule
# (pod -> workload, monitoring/config/rules.yml).

import json
import sys

DS = {"type": "prometheus", "uid": "${DS_PROMETHEUS}"}
SELF_URL = "/d/resource-reservations/resource-reservations"

NODE_SEL = 'node=~"$node"'
NS_SEL = 'namespace=~"$namespace"'

# Pod -> workload mapping (recording rule). WL_ALL ignores the dashboard
# filters; WL honours namespace and workload.
WL_ALL = 'namespace_workload_pod:kube_pod_owner:relabel'
WL = f'{WL_ALL}{{{NS_SEL}, workload=~"$workload"}}'


# ---------------------------------------------------------------- PromQL helpers

def phase_filter(phases, ns):
    """1 per pod in the given phases, joined on (namespace, pod)."""
    sel = f'phase=~"{phases}"' + (f', {NS_SEL}' if ns else '')
    return f'on(namespace, pod) group_left() (max by (namespace, pod) (kube_pod_status_phase{{{sel}}}) == 1)'


def req(resource, by, kind="requests", ns=False, phases="Pending|Running", node=True):
    """Sum of pod requests (or limits) the scheduler counts.

    Regular containers plus native sidecars (init containers with
    restartPolicy: Always), which the scheduler adds on top -- e.g. the
    smelt-park sandboxes' docker sidecar. Ordinary run-to-completion init
    containers are left out: they only matter when bigger than the rest of the
    pod, which nothing here is. Pending|Running = pods still holding (or
    waiting for) a reservation.

    restart_policy only shows up (on kube_pod_init_container_info) once the
    pod has init container statuses, i.e. never for a pod still waiting to
    schedule -- e.g. ARC runners, whose only request is on the dind sidecar.
    For those, count every init container's request (overcounts only a
    not-yet-started pod with a requesting run-to-completion init container).
    """
    parts = [f'resource="{resource}"']
    if node:
        parts.append(NODE_SEL)
    if ns:
        parts.append(NS_SEL)
    sel = ", ".join(parts)
    main = f'kube_pod_container_resource_{kind}{{{sel}}}'
    init = f'kube_pod_init_container_resource_{kind}{{{sel}}}'
    sidecar = (f'(({init} * on(namespace, pod, container) group_left() '
               f'max by (namespace, pod, container) (kube_pod_init_container_info{{restart_policy="Always"}})) '
               f'or ({init} unless on(namespace, pod) kube_pod_init_container_info))')
    return f'sum by ({by}) (({main} or {sidecar}) * {phase_filter(phases, ns)})'


# Nodes that can take new pods: Ready and not cordoned. Capacity (allocatable,
# free) counts only these, so a node that's away -- e.g. the framework laptop,
# off the network or drained -- doesn't read as free room. Requests still
# count wherever their pods are.
NODE_UP = ('(max by (node) (kube_node_status_condition{condition="Ready", status="true"}) == 1 '
           'unless on(node) (kube_node_spec_unschedulable == 1))')


def alloc(resource, by="node"):
    return (f'sum by ({by}) (kube_node_status_allocatable{{resource="{resource}", {NODE_SEL}}} '
            f'and on(node) {NODE_UP})')


def cluster_alloc(resource):
    return f'scalar(sum(kube_node_status_allocatable{{resource="{resource}"}} and on(node) {NODE_UP}))'


def usage(kind, by="namespace, pod", ns=False):
    sel = 'container!="", container!="POD", instance=~"$node"' + (f', {NS_SEL}' if ns else '')
    if kind == "cpu":
        return f'sum by ({by}) (rate(container_cpu_usage_seconds_total{{{sel}}}[5m]))'
    return f'sum by ({by}) (container_memory_working_set_bytes{{{sel}}})'


def peak(e):
    return f'max_over_time(({e})[1d:5m])'


def free(resource):
    """Allocatable minus requested, per node (nodes with no requests count as fully free)."""
    return f'{alloc(resource)} - ({req(resource, "node")} or {alloc(resource)} * 0)'


# 1 per active pod on the selected nodes/namespaces, by (namespace, pod).
ACTIVE_PODS = (f'(max by (namespace, pod) (kube_pod_info{{{NODE_SEL}, {NS_SEL}}}) '
               f'* {phase_filter("Pending|Running", True)})')
POD_NODE = 'on(namespace, pod) group_left(node) max by (namespace, pod, node) (kube_pod_info{node=~"$node"})'


def by_wl(e, wl=WL):
    """Attach workload/workload_type to a per-(namespace, pod) series; filters by $workload."""
    return f'(({e}) * on(namespace, pod) group_left(workload, workload_type) {wl})'


# ---------------------------------------------------------------- panel helpers

_pid = [0]


def nid():
    _pid[0] += 1
    return _pid[0]


def target(expr, legend="", ref="A", instant=False, fmt="time_series"):
    t = {"refId": ref, "datasource": DS, "expr": expr, "legendFormat": legend, "range": not instant, "instant": instant}
    if fmt != "time_series":
        t["format"] = fmt
    return t


def thr(*steps):
    return {"mode": "absolute", "steps": [{"color": c, "value": v} for c, v in steps]}


PCT_THR = thr(("green", None), ("yellow", 75), ("red", 90))
ALERT_THR = thr(("green", None), ("red", 1))
INFO_THR = thr(("blue", None))


def row(title, y, collapsed=False, children=None):
    return {"type": "row", "id": nid(), "title": title, "collapsed": collapsed,
            "gridPos": {"h": 1, "w": 24, "x": 0, "y": y}, "panels": children or []}


def bargauge(title, targets, gp, unit="percent", mx=100, desc="", thresholds=PCT_THR):
    return {"type": "bargauge", "id": nid(), "title": title, "description": desc, "datasource": DS, "gridPos": gp,
            "targets": targets,
            "options": {"orientation": "horizontal", "displayMode": "gradient", "showUnfilled": True,
                        "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                        "minVizHeight": 16, "valueMode": "color"},
            "fieldConfig": {"defaults": {"unit": unit, "min": 0, "max": mx, "thresholds": thresholds,
                                         "color": {"mode": "thresholds"}}, "overrides": []}}


def stat(title, targets, gp, unit="percent", desc="", thresholds=PCT_THR, decimals=None):
    d = {"unit": unit, "thresholds": thresholds, "color": {"mode": "thresholds"}}
    if decimals is not None:
        d["decimals"] = decimals
    return {"type": "stat", "id": nid(), "title": title, "description": desc, "datasource": DS, "gridPos": gp,
            "targets": targets,
            "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                        "colorMode": "background", "graphMode": "area", "textMode": "auto",
                        "justifyMode": "auto", "orientation": "auto"},
            "fieldConfig": {"defaults": d, "overrides": []}}


def ts(title, targets, gp, unit, desc="", stack=False, overrides=None, mx=None, decimals=None, bars=False):
    custom = {"drawStyle": "bars" if bars else "line", "lineWidth": 1, "fillOpacity": 30 if stack else 10,
              "showPoints": "never", "spanNulls": True,
              "stacking": {"mode": "normal" if stack else "none", "group": "A"}}
    d = {"unit": unit, "min": 0, "custom": custom, "color": {"mode": "palette-classic"}}
    if mx is not None:
        d["max"] = mx
    if decimals is not None:
        d["decimals"] = decimals
    return {"type": "timeseries", "id": nid(), "title": title, "description": desc, "datasource": DS, "gridPos": gp,
            "targets": targets,
            "options": {"legend": {"displayMode": "table", "placement": "right", "calcs": ["lastNotNull", "max"],
                                   "sortBy": "Last *", "sortDesc": True},
                        "tooltip": {"mode": "multi", "sort": "desc"}},
            "fieldConfig": {"defaults": d, "overrides": overrides or []}}


def dashed(regex):
    return {"matcher": {"id": "byRegexp", "options": regex},
            "properties": [{"id": "custom.lineStyle", "value": {"fill": "dash", "dash": [10, 10]}},
                           {"id": "custom.fillOpacity", "value": 0},
                           {"id": "custom.stacking", "value": {"mode": "none"}}]}


CORES, BYTES, PCT, COUNT, SECS = ("none", 2), ("bytes", None), ("percent", 1), ("none", 0), ("s", None)


def link_override(field, title, url):
    return {"matcher": {"id": "byName", "options": field},
            "properties": [{"id": "links", "value": [{"title": title, "url": url}]}]}


NS_LINK = link_override(
    "namespace", "Drill into namespace ${__value.raw}",
    SELF_URL + "?${__url_time_range}&${node:queryparam}&var-namespace=${__value.raw}&var-workload=$__all")
WL_LINK = link_override(
    "workload", "Drill into workload ${__value.raw}",
    SELF_URL + "?${__url_time_range}&${node:queryparam}&var-namespace=${__data.fields.namespace}&var-workload=${__value.raw}")


def table(title, desc, gp, keys, cols, sort_by, links=(), footer_sum=()):
    """cols: [(name, expr, (unit, decimals))]; every expr must return exactly the `keys` labels."""
    refs = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    targets = [target(e, ref=refs[i], instant=True, fmt="table") for i, (_, e, _) in enumerate(cols)]
    rename = {f"Value #{refs[i]}": name for i, (name, _, _) in enumerate(cols)}
    index = {k: i for i, k in enumerate(keys)}
    index.update({f"Value #{refs[i]}": len(keys) + i for i in range(len(cols))})
    overrides = []
    for name, _, (unit, decimals) in cols:
        props = [{"id": "unit", "value": unit}]
        if decimals is not None:
            props.append({"id": "decimals", "value": decimals})
        overrides.append({"matcher": {"id": "byName", "options": name}, "properties": props})
    return {
        "type": "table", "id": nid(), "title": title, "description": desc,
        "datasource": DS, "gridPos": gp, "targets": targets,
        "transformations": [
            {"id": "merge", "options": {}},
            {"id": "organize", "options": {"excludeByName": {"Time": True}, "renameByName": rename,
                                           "indexByName": index}},
            {"id": "sortBy", "options": {"sort": [{"field": sort_by, "desc": True}]}},
        ],
        "options": {"showHeader": True, "cellHeight": "sm",
                    "footer": {"show": bool(footer_sum), "reducer": ["sum"], "countRows": False,
                               "fields": list(footer_sum)}},
        "fieldConfig": {"defaults": {"custom": {"filterable": True, "align": "auto"}, "noValue": ""},
                        "overrides": overrides + list(links)},
    }


# ---------------------------------------------------------------- layout

panels = []
y = 0

# ---- 1. Is anything stuck?
panels.append(row("1 · Is anything waiting to schedule? (whole cluster; ignores the filters)", y)); y += 1

PENDING_POD = phase_filter("Pending", False)
panels.append(stat("Pending pods", [target('sum(kube_pod_status_phase{phase="Pending"}) or vector(0)')],
                   {"h": 5, "w": 4, "x": 0, "y": y}, unit="none", decimals=0, thresholds=ALERT_THR,
                   desc="Pods not running yet: no node has room for their requests, or they're waiting on an image pull or volume."))
panels.append(stat("Unschedulable pods", [target('sum(kube_pod_status_unschedulable) or vector(0)')],
                   {"h": 5, "w": 4, "x": 4, "y": y}, unit="none", decimals=0, thresholds=ALERT_THR,
                   desc="Pods the scheduler has marked Unschedulable: no node passes its filters (resources, taints, selectors, affinity)."))
panels.append(stat("Cluster memory reserved",
                   [target(f'sum({req("memory", "node", node=False)}) / {cluster_alloc("memory")} * 100')],
                   {"h": 5, "w": 4, "x": 8, "y": y},
                   desc="Memory requests of running and pending pods / allocatable memory of the nodes that are up (Ready, not cordoned)."))
panels.append(stat("Cluster CPU reserved",
                   [target(f'sum({req("cpu", "node", node=False)}) / {cluster_alloc("cpu")} * 100')],
                   {"h": 5, "w": 4, "x": 12, "y": y},
                   desc="CPU requests of running and pending pods / allocatable CPU of the nodes that are up (Ready, not cordoned)."))
panels.append(stat("Most free memory on one node", [target(f'max({free("memory")})')],
                   {"h": 5, "w": 4, "x": 16, "y": y}, unit="bytes", thresholds=INFO_THR,
                   desc="A pod only fits if a single node has room for its whole request. If a pending pod asks for more than this, nothing can take it, however much is free in total. Ignores taints and node selectors: a node with plenty free (e.g. a tainted, dedicated node) may still be off-limits to the pod -- the pod's FailedScheduling event says which."))
panels.append(stat("Most free CPU on one node", [target(f'max({free("cpu")})')],
                   {"h": 5, "w": 4, "x": 20, "y": y}, unit="none", decimals=2, thresholds=INFO_THR,
                   desc="Cores. A pod only fits if a single node has room for its whole request. Ignores taints and node selectors: a node with plenty free (e.g. a tainted, dedicated node) may still be off-limits to the pod -- the pod's FailedScheduling event says which."))
y += 5

PEND_KEYS = ["namespace", "workload", "pod"]


def pend(e):
    # Every column keyed by (namespace, workload, workload_type, pod); dropped workload_type below.
    return f'max by (namespace, workload, pod) ({by_wl(e, WL_ALL)})'


panels.append(table(
    "Pods waiting to schedule",
    "Every Pending pod, with what it is asking for. Compare its requests against 'Free per node' to the right: it needs one node with room for all of it. 'Unschedulable' = 1 when the scheduler has given up on every node for now.",
    {"h": 9, "w": 12, "x": 0, "y": y}, PEND_KEYS,
    [("Waiting", pend(f'(time() - max by (namespace, pod) (kube_pod_created)) * {PENDING_POD}'), SECS),
     ("Unschedulable", pend(f'max by (namespace, pod) (kube_pod_status_unschedulable) * {PENDING_POD}'), COUNT),
     ("Mem req", pend(req("memory", "namespace, pod", phases="Pending", node=False)), BYTES),
     ("CPU req", pend(req("cpu", "namespace, pod", phases="Pending", node=False)), CORES)],
    sort_by="Mem req", links=[NS_LINK, WL_LINK]))
panels.append(bargauge("Free memory per node (allocatable − requested)",
                       [target(free("memory"), "{{node}}", instant=True)],
                       {"h": 9, "w": 6, "x": 12, "y": y}, unit="bytes", mx=None, thresholds=INFO_THR,
                       desc="What a new pod's memory request can still claim on each node. Ignores taints and node selectors: a node with plenty free (e.g. a tainted, dedicated node) may still be off-limits to the pod -- the pod's FailedScheduling event says which."))
panels.append(bargauge("Free CPU per node (allocatable − requested)",
                       [target(free("cpu"), "{{node}}", instant=True)],
                       {"h": 9, "w": 6, "x": 18, "y": y}, unit="none", mx=None, thresholds=INFO_THR,
                       desc="Cores a new pod's CPU request can still claim on each node. Ignores taints and node selectors: a node with plenty free (e.g. a tainted, dedicated node) may still be off-limits to the pod -- the pod's FailedScheduling event says which."))
y += 9

panels.append(ts("Waiting pods by namespace",
                 [target('count by (namespace) (kube_pod_status_phase{phase="Pending"} == 1)', "{{namespace}} pending", "A"),
                  target('count by (namespace) (kube_pod_status_unschedulable == 1)', "{{namespace}} unschedulable", "B")],
                 {"h": 7, "w": 18, "x": 0, "y": y}, "none", decimals=0, bars=True,
                 desc="When did scheduling trouble start, and who is affected."))
panels.append(stat("Nodes down or cordoned",
                   [target(f'count(max by (node) (kube_node_info) unless on(node) {NODE_UP}) or vector(0)')],
                   {"h": 7, "w": 6, "x": 18, "y": y}, unit="none", decimals=0,
                   thresholds=thr(("green", None), ("yellow", 1)),
                   desc="Nodes that aren't Ready or are cordoned (e.g. the framework laptop while it's away). Their capacity is left out of every 'allocatable' and 'free' figure; the free-per-node bars list only the nodes that are up."))
y += 7

# ---- 2. Nodes
panels.append(row("2 · Which nodes are full? (whole nodes; ignores the namespace/workload filters)", y)); y += 1
panels.append(bargauge("Memory requests % of allocatable",
                       [target(f'{req("memory", "node")} / {alloc("memory")} * 100', "{{node}}", instant=True)],
                       {"h": 7, "w": 8, "x": 0, "y": y}))
panels.append(bargauge("CPU requests % of allocatable",
                       [target(f'{req("cpu", "node")} / {alloc("cpu")} * 100', "{{node}}", instant=True)],
                       {"h": 7, "w": 8, "x": 8, "y": y}))
panels.append(bargauge("Memory limits % of allocatable",
                       [target(f'{req("memory", "node", "limits")} / {alloc("memory")} * 100', "{{node}}", instant=True)],
                       {"h": 7, "w": 8, "x": 16, "y": y}, mx=None,
                       thresholds=thr(("green", None), ("yellow", 100), ("red", 200)),
                       desc="Overcommit: >100% means the pods on this node could together use more memory than it has, if they all hit their limits (OOM-kill risk). Pods without a limit are not counted."))
y += 7
panels.append(ts("Memory requests % of allocatable",
                 [target(f'{req("memory", "node")} / {alloc("memory")} * 100', "{{node}}")],
                 {"h": 8, "w": 12, "x": 0, "y": y}, "percent", mx=100))
panels.append(ts("CPU requests % of allocatable",
                 [target(f'{req("cpu", "node")} / {alloc("cpu")} * 100', "{{node}}")],
                 {"h": 8, "w": 12, "x": 12, "y": y}, "percent", mx=100))
y += 8

# Reserved vs used per node: useful, but not on the triage path -> collapsed.
cy = y + 1
cpu_used_node = f'sum by (node) ({usage("cpu")} * {POD_NODE})'
mem_used_node = f'sum by (node) ({usage("mem")} * {POD_NODE})'
collapsed = [
    ts("Memory: requested vs used",
       [target(req("memory", "node"), "{{node}} requested", "A"),
        target(mem_used_node, "{{node}} used", "B"),
        target(alloc("memory"), "{{node}} allocatable", "C")],
       {"h": 9, "w": 12, "x": 0, "y": cy}, "bytes",
       desc="Requested = sum of pod memory requests; used = pod working set (cAdvisor). A big gap is reservation that isn't being used.",
       overrides=[dashed(".* allocatable")]),
    ts("CPU: requested vs used (cores)",
       [target(req("cpu", "node"), "{{node}} requested", "A"),
        target(cpu_used_node, "{{node}} used", "B"),
        target(alloc("cpu"), "{{node}} allocatable", "C")],
       {"h": 9, "w": 12, "x": 12, "y": cy}, "none",
       desc="Requested = sum of pod CPU requests; used = actual pod CPU (cAdvisor).",
       overrides=[dashed(".* allocatable")]),
]
panels.append(row("Nodes: reserved vs actually used", y, collapsed=True, children=collapsed)); y += 1

# ---- 3. Namespaces
panels.append(row("3 · Which namespace is holding it? (click a namespace to drill in)", y)); y += 1
NS = "namespace"
panels.append(stat("Reclaimable memory (request − peak 1d)",
                   [target(f'sum(clamp_min({req("memory", "namespace, pod", ns=True)} - on(namespace, pod) {peak(usage("mem", ns=True))}, 0))')],
                   {"h": 4, "w": 12, "x": 0, "y": y}, unit="bytes", thresholds=INFO_THR,
                   desc="Pods in the selected namespaces: memory request minus the pod's peak working set over the last day (floored at 0). Upper bound on what right-sizing requests could free."))
panels.append(stat("Reclaimable CPU (request − peak 1d)",
                   [target(f'sum(clamp_min({req("cpu", "namespace, pod", ns=True)} - on(namespace, pod) {peak(usage("cpu", ns=True))}, 0))')],
                   {"h": 4, "w": 12, "x": 12, "y": y}, unit="none", decimals=2, thresholds=INFO_THR,
                   desc="Pods in the selected namespaces, in cores: CPU request minus the pod's peak 5m-avg CPU over the last day (floored at 0)."))
y += 4
panels.append(table(
    "Namespaces",
    "Per namespace, over running and pending pods on the selected nodes. '% cluster' is of the allocatable of nodes that are up. "
    "Many pods with a small 'Biggest pod' = lots of small things; few pods with a big 'Biggest pod' = one heavy hitter. "
    "'used' is now (CPU 5m avg); 'peak 1d' is the namespace total's max over the last day.",
    {"h": 11, "w": 24, "x": 0, "y": y}, [NS],
    [("Pods", f'count by (namespace) ({ACTIVE_PODS})', COUNT),
     ("Workloads", f'count by (namespace) (count by (namespace, workload) ({by_wl(ACTIVE_PODS, WL_ALL)}))', COUNT),
     ("Mem req", req("memory", NS, ns=True), BYTES),
     ("Mem % cluster", f'{req("memory", NS, ns=True)} / {cluster_alloc("memory")} * 100', PCT),
     ("Biggest pod mem", f'max by (namespace) ({req("memory", "namespace, pod", ns=True)})', BYTES),
     ("Mem used", usage("mem", NS, ns=True), BYTES),
     ("Mem peak 1d", peak(usage("mem", NS, ns=True)), BYTES),
     ("CPU req", req("cpu", NS, ns=True), CORES),
     ("CPU % cluster", f'{req("cpu", NS, ns=True)} / {cluster_alloc("cpu")} * 100', PCT),
     ("Biggest pod CPU", f'max by (namespace) ({req("cpu", "namespace, pod", ns=True)})', CORES),
     ("CPU used", usage("cpu", NS, ns=True), CORES),
     ("CPU peak 1d", peak(usage("cpu", NS, ns=True)), CORES),
     ("Mem limit", req("memory", NS, "limits", ns=True), BYTES)],
    sort_by="Mem req", links=[NS_LINK], footer_sum=["Pods", "Mem req", "Mem % cluster", "CPU req", "CPU % cluster"]))
y += 11
panels.append(ts("Memory requested by namespace", [target(req("memory", NS, ns=True), "{{namespace}}")],
                 {"h": 9, "w": 12, "x": 0, "y": y}, "bytes", stack=True,
                 desc="Stacked: when did each namespace's reservation grow?"))
panels.append(ts("Memory used by namespace", [target(usage("mem", NS, ns=True), "{{namespace}}")],
                 {"h": 9, "w": 12, "x": 12, "y": y}, "bytes", stack=True))
y += 9
panels.append(ts("CPU requested by namespace (cores)", [target(req("cpu", NS, ns=True), "{{namespace}}")],
                 {"h": 9, "w": 12, "x": 0, "y": y}, "none", stack=True, decimals=2))
panels.append(ts("CPU used by namespace (cores)", [target(usage("cpu", NS, ns=True), "{{namespace}}")],
                 {"h": 9, "w": 12, "x": 12, "y": y}, "none", stack=True, decimals=2))
y += 9

# ---- 4. Workloads
panels.append(row("4 · Within it: which workloads — many pods, or a few big ones? (click a workload to drill in)", y)); y += 1
WLK = "namespace, workload, workload_type"


def wl_sum(e):
    return f'sum by ({WLK}) ({by_wl(e)})'


panels.append(table(
    "Workloads",
    "Pods grouped by what owns them: Deployment, StatefulSet, DaemonSet, ARC runner set, or (for bare pods) a numbered family like sandbox-<n>. "
    "'Pods' × 'Mem / pod' ≈ 'Mem req': a high count means lots of small pods, a high per-pod value means a few big ones.",
    {"h": 12, "w": 24, "x": 0, "y": y}, ["namespace", "workload", "workload_type"],
    [("Pods", f'count by ({WLK}) ({by_wl(ACTIVE_PODS)})', COUNT),
     ("Mem req", wl_sum(req("memory", "namespace, pod", ns=True)), BYTES),
     ("Mem / pod", f'avg by ({WLK}) ({by_wl(req("memory", "namespace, pod", ns=True))})', BYTES),
     ("Biggest pod mem", f'max by ({WLK}) ({by_wl(req("memory", "namespace, pod", ns=True))})', BYTES),
     ("Mem used", wl_sum(usage("mem", ns=True)), BYTES),
     ("Mem peak 1d", peak(wl_sum(usage("mem", ns=True))), BYTES),
     ("CPU req", wl_sum(req("cpu", "namespace, pod", ns=True)), CORES),
     ("CPU / pod", f'avg by ({WLK}) ({by_wl(req("cpu", "namespace, pod", ns=True))})', CORES),
     ("CPU used", wl_sum(usage("cpu", ns=True)), CORES),
     ("CPU peak 1d", peak(wl_sum(usage("cpu", ns=True))), CORES),
     ("Mem limit", wl_sum(req("memory", "namespace, pod", "limits", ns=True)), BYTES)],
    sort_by="Mem req", links=[NS_LINK, WL_LINK], footer_sum=["Pods", "Mem req", "CPU req"]))
y += 12
panels.append(ts("Memory requested by workload", [target(wl_sum(req("memory", "namespace, pod", ns=True)), "{{namespace}}/{{workload}}")],
                 {"h": 9, "w": 12, "x": 0, "y": y}, "bytes", stack=True))
panels.append(ts("Pods by workload", [target(f'count by ({WLK}) ({by_wl(ACTIVE_PODS)})', "{{namespace}}/{{workload}}")],
                 {"h": 9, "w": 12, "x": 12, "y": y}, "none", stack=True, decimals=0,
                 desc="Running + pending pods. A climbing line = a workload scaling out (or leaking pods)."))
y += 9

# ---- 5. Pods
panels.append(row("5 · Pods", y)); y += 1
POD_KEYS = "namespace, workload, workload_type, pod, node"


def pod_col(e, with_node=False):
    # Normalise every column to POD_KEYS so the table's merge lines up.
    if with_node:
        e = f'({e}) * {POD_NODE}'
    return f'max by ({POD_KEYS}) ({by_wl(e)})'


panels.append(table(
    "Pods",
    "Running + pending pods in the selected namespaces/workloads/nodes. 'used' is now (CPU 5m avg); 'peak 1d' is the max over the last day. "
    "A request far above the peak is reservation you could hand back; a blank request is invisible to the scheduler.",
    {"h": 14, "w": 24, "x": 0, "y": y}, ["namespace", "workload", "workload_type", "pod", "node"],
    [("Mem req", pod_col(req("memory", "namespace, pod, node", ns=True)), BYTES),
     ("Mem used", pod_col(usage("mem", ns=True), True), BYTES),
     ("Mem peak 1d", pod_col(peak(usage("mem", ns=True)), True), BYTES),
     ("Mem limit", pod_col(req("memory", "namespace, pod, node", "limits", ns=True)), BYTES),
     ("CPU req", pod_col(req("cpu", "namespace, pod, node", ns=True)), CORES),
     ("CPU used", pod_col(usage("cpu", ns=True), True), CORES),
     ("CPU peak 1d", pod_col(peak(usage("cpu", ns=True)), True), CORES)],
    sort_by="Mem req", links=[NS_LINK, WL_LINK], footer_sum=["Mem req", "CPU req"]))
y += 14
POD_LEG = "{{namespace}}/{{pod}}"
panels.append(ts("Memory per pod: used (solid) vs requested (dashed)",
                 [target(by_wl(usage("mem", ns=True)), f"{POD_LEG} used", "A"),
                  target(by_wl(req("memory", "namespace, pod", ns=True)), f"{POD_LEG} requested", "B")],
                 {"h": 10, "w": 12, "x": 0, "y": y}, "bytes", overrides=[dashed(".* requested")]))
panels.append(ts("CPU per pod: used (solid) vs requested (dashed), cores",
                 [target(by_wl(usage("cpu", ns=True)), f"{POD_LEG} used", "A"),
                  target(by_wl(req("cpu", "namespace, pod", ns=True)), f"{POD_LEG} requested", "B")],
                 {"h": 10, "w": 12, "x": 12, "y": y}, "none", decimals=2, overrides=[dashed(".* requested")]))
y += 10


def query_var(name, label, query):
    return {"current": {"selected": True, "text": "All", "value": "$__all"}, "datasource": DS, "definition": query,
            "hide": 0, "includeAll": True, "allValue": ".*", "label": label, "multi": True, "name": name,
            "options": [], "query": {"query": query, "refId": name}, "refresh": 2, "sort": 1, "type": "query"}


dash = {
    "annotations": {"list": [{"builtIn": 1, "datasource": {"type": "grafana", "uid": "-- Grafana --"}, "enable": True,
                              "hide": True, "iconColor": "rgba(0, 211, 255, 1)", "name": "Annotations & Alerts",
                              "type": "dashboard"}]},
    "title": "Resource reservations",
    "uid": "resource-reservations",
    "description": "What's holding the cluster's scheduling room: stuck pods, full nodes, then namespace -> workload -> pod. Requests/allocatable from kube-state-metrics, usage from cAdvisor.",
    "editable": True, "graphTooltip": 1, "id": None, "links": [], "refresh": "1m", "schemaVersion": 38,
    "tags": ["kubernetes", "capacity"],
    "time": {"from": "now-7d", "to": "now"},
    "templating": {"list": [
        {"current": {}, "hide": 0, "includeAll": False, "label": "Datasource", "multi": False, "name": "DS_PROMETHEUS",
         "options": [], "query": "prometheus", "refresh": 1, "regex": "", "type": "datasource"},
        query_var("node", "Node", "label_values(kube_node_info, node)"),
        query_var("namespace", "Namespace", "label_values(kube_pod_info, namespace)"),
        query_var("workload", "Workload", f'label_values({WL_ALL}{{{NS_SEL}}}, workload)'),
    ]},
    "panels": panels,
}
json.dump(dash, sys.stdout, indent=2)
print()

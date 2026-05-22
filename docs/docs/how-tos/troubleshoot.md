---
title: Troubleshoot
description: First-aid guide for the most common failures — version mismatch, network policy, crashlooping replicas, NebariApp not Ready.
sidebar_position: 2
---

# Troubleshoot

Quick index of the failure modes that come up most often. Each entry
links to the deeper write-up where the recovery steps live. Start
here, narrow to the right page, follow the steps.

## First checks

If you're not sure what's broken, run these three commands and read the
output before diving into anything else:

```bash
# Is the Ray cluster up?
kubectl get rayservice -n rayserve

# Are the pods running?
kubectl get pods -n rayserve

# If NebariApps are involved, are they Ready?
kubectl get nebariapp -n rayserve
```

The output tells you which layer to focus on:

- **RayService `NotRunning`** → operator or KubeRay layer. See
  [Deploy → Operator troubleshooting](../get-started/deploy#operator-troubleshooting).
- **Pods `Pending` / `CrashLoopBackOff` / `0/1 Ready`** → Ray pod itself.
  Most common: stale image pull, broken probes, OOMKilled. See
  [Crashlooping replicas](#crashlooping-replicas) below.
- **Pods Running but `ray.init` from notebook fails** → client-side. See
  [Version mismatch](#ray-version-mismatch).
- **NebariApp not Ready** → routing layer. See
  [NebariApp issues](#nebariapp-not-reaching-ready).

## End-user failures

### Ray version mismatch

The most common end-user failure. The Ray client's binary protocol is
sensitive to Ray version *and* Python minor version — Python 3.9 client
cannot talk to a Python 3.10 cluster, and Ray 2.43 client cannot talk to
a Ray 2.40 cluster.

Symptom: `ray.init(...)` hangs indefinitely, or returns an opaque
"connection error" or "version mismatch" exception.

→ Full recovery steps:
[Use Ray Serve → `ray.init` hangs or fails with a version error](./use#rayinit-hangs-or-fails-with-a-version-error).

### Notebook can't reach the Ray service

The default JupyterHub singleuser network policy blocks egress to private
cluster IPs. `ray.init` hangs indefinitely; `curl` from a notebook
terminal to the head service times out.

→ Full recovery steps:
[Use Ray Serve → Notebook can't reach the Ray service](./use#notebook-cant-reach-the-ray-service-network-policy-blocks-egress).

### Crashlooping replicas

`serve.run(...)` returns successfully but something is wrong downstream.
Two distinct failure modes — they look similar at first but need
different fixes:

- **Replica fails to start** — Dashboard's Serve tab shows
  `DEPLOY_FAILED` after ~3 retry attempts. Cause is usually an
  `ImportError` on a missing package or an OOMKilled during
  `__init__`.
- **Replica started, requests return 500s** — Dashboard shows
  `HEALTHY` (because the replica is running) but every request returns
  500. Cause is an exception in `__call__` itself, not at startup.

→ Full recovery steps:
[Use Ray Serve → My model is crashlooping or returning errors](./use#my-model-is-crashlooping-or-returning-errors).

A failing replica usually shows up in the Ray Dashboard's Serve tab as
`DEPLOY_FAILED` once Serve has given up restarting it (typically "failed
to start 3 times in a row"), with a healthy app like the `hello` example
running alongside for contrast:

![Ray Dashboard Serve tab showing a broken application in DEPLOY_FAILED state next to a healthy hello application](/img/screenshots/dashboard-serve-deploy-failed.png)

Pair the dashboard view with `kubectl logs --previous` on the failed
worker pod to read the actual exception.

## Operator failures

### ArgoCD shows permanent `OutOfSync`

The KubeRay controller mutates `RayService` and `Service` resources
at runtime; without an `ignoreDifferences` block, ArgoCD's diff never
closes.

→ Full recovery steps:
[Deploy → ArgoCD shows permanent `OutOfSync`](../get-started/deploy#argocd-shows-permanent-outofsync).

### NebariApp not reaching Ready

Most common cause: the namespace doesn't carry the `nebari.dev/managed: "true"`
label, so the nebari-operator silently ignores NebariApp resources in it.

→ Full recovery steps:
[Deploy → NebariApp stuck with `RoutingReady: False`](../get-started/deploy#nebariapp-stuck-with-routingready-false).

### Dashboard returns 500 via NebariApp

The NebariApp's HTTPRoute is pointing at a service that doesn't exist —
typically because `nebariapp.service.name` was overridden to a custom
value that was never created.

→ Full recovery steps:
[Deploy → Dashboard returns 500 via NebariApp](../get-started/deploy#dashboard-returns-500-via-nebariapp).

### Worker pods stuck `0/1 Ready`

Usually means the chart's `worker.readinessProbe` got overridden to `{}`
(empty map) instead of `null`. KubeRay's default probe chains a Serve
HTTP check that fails on a cluster with no apps deployed.

→ Full recovery steps:
[Deploy → Worker pods stuck `0/1 Ready`](../get-started/deploy#worker-pods-stuck-01-ready).

## Still stuck?

- Compare `kubectl describe rayservice -n rayserve` against the
  [Architecture page](../references/architecture) to see which condition
  is failing.
- Open an issue at
  [nebari-rayserve-pack/issues](https://github.com/nebari-dev/nebari-rayserve-pack/issues)
  with the output of the three [First checks](#first-checks) commands and
  the last 200 lines of `kubectl logs` for the failing pod.
- For Ray-specific behaviour, the upstream
  [Ray Serve troubleshooting](https://docs.ray.io/en/latest/serve/troubleshooting.html)
  page covers controller, replica, and request-path failures in more
  depth.

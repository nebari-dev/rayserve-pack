---
title: Use Ray Serve from a notebook
description: Connect to the cluster from a Jupyter notebook, deploy a model, and troubleshoot the common failure modes.
sidebar_position: 1
---

# Use Ray Serve from a notebook

End-user guide for the Nebari Ray Serve pack. This walks through connecting to
the deployed Ray cluster from a Jupyter notebook, deploying a model, watching
it in the dashboard, and (optionally) exposing it outside the cluster.

This guide assumes that the software pack has already been
deployed and the cluster is healthy. For install and operations, see
[Get started → Deploy the pack](../get-started/deploy).

## What this pack is for

This pack deploys **Ray Serve** — Ray's framework for serving Python models
behind an HTTP endpoint. It is the right tool when you have a trained model
(or a chain of models) and you want to call it over HTTP from inside or
outside the cluster.

:::warning[Not a general Ray compute cluster]

Ray Data, Ray Tune, and Ray Train workloads will technically run on this
deployment, but the chart is tuned for serving: workers come up sized for
inference, the dashboard's landing page is wired for the Serve REST API,
and the chart ships a `serveConfigV2` even when no applications are
declared.

:::

The deployment is a long-lived service on your Nebari cluster — you do not
start or stop it from your notebook. You connect, deploy applications, and
disconnect; the cluster keeps running, and any applications you registered
with `serve.run(...)` keep serving until you call `serve.delete(...)` or the
cluster is restarted by an operator.

## Step 1 — Prepare your notebook environment

:::warning[Version match required]

The Ray client uses a binary protocol that is sensitive to version skew.
Your notebook's Ray version **and** Python *minor* version must match the
cluster (e.g. 3.9 ≠ 3.10), or `ray.init(...)` will fail with an opaque
error or hang. Patch-level differences (3.9.21 vs 3.9.23) typically only
log a warning and still connect. This is the most common end-user failure
mode.

:::

Ask your operator which Ray and Python versions the cluster is on — that's
the authoritative answer and the fastest path. If you already have a
working notebook on the cluster, you can also read the cluster's Ray
version off a remote task (`ray.__version__` on its own reports the
*local* client version, not the cluster's):

```python
import ray, sys
ray.init("ray://rayserve-nebari-rayserve-head-svc.rayserve.svc.cluster.local:10001")

@ray.remote
def cluster_versions():
    import ray, sys
    return ray.__version__, sys.version_info[:2]

cluster_ray, cluster_py = ray.get(cluster_versions.remote())
print(f"Cluster: Ray {cluster_ray}, Python {cluster_py[0]}.{cluster_py[1]}")
print(f"Client:  Ray {ray.__version__}, Python {sys.version_info[0]}.{sys.version_info[1]}")
```

If the two lines disagree on Ray version or on the Python *minor* number,
the client won't connect reliably — see
[Troubleshooting](#rayinit-hangs-or-fails-with-a-version-error).

### Create a workspace with Nebi

On a Nebari cluster the default JupyterLab kernel runs inside a
pixi-managed, **read-only** environment — installing packages directly
will fail. The right path is the
[Nebi pack](https://github.com/nebari-dev/nebari-nebi-pack), which
provisions an isolated workspace at the versions you declare.

From the JupyterLab Launcher, click the **Nebi** tile and create a
workspace with this spec (replace `<ray-version>` and `<python-version>`
with what your operator told you):

```toml
[workspace]
name = "ray-serve"
channels = ["conda-forge"]
platforms = ["linux-64"]

[dependencies]
python = "<python-version>.*"
ray-serve = "<ray-version>.*"
ipykernel = ">=6.0"
requests = "*"
```

Wait for Nebi to mark the workspace `Ready` (usually 1–3 minutes).

:::warning[Nebi workspaces don't always register a Jupyter kernel automatically]

If after a hard refresh (`Ctrl+Shift+R`) the new kernel doesn't appear
in the Launcher, the workspace built but the ipykernel registration
step was skipped. Open a terminal in JupyterLab, find the env path,
and register it manually:

```bash
# 1. find your workspace path (Nebi stores them under ~/.local/share/nebi/workspaces/)
ls ~/.local/share/nebi/workspaces/

# 2. cd into the env so the rest fits on one line
cd ~/.local/share/nebi/workspaces/<your-workspace-dir>/.pixi/envs/default

# 3. register the kernel
./bin/python -m ipykernel install --user --name ray-serve --display-name "Python (ray-serve)"
```

Hard-refresh JupyterLab and the kernel will appear in the Launcher.

:::

## Step 2 — Connect from your notebook

Open a notebook with the `Python (ray-serve)` kernel and connect to the
Ray head via its in-cluster service:

```python
import ray

ray.init("ray://rayserve-nebari-rayserve-head-svc.rayserve.svc.cluster.local:10001")
print(ray.cluster_resources())
```

A successful connect prints the cluster's CPU/memory/GPU totals. No manual
cluster startup is needed — the cluster has already been brought up by
your operator with Serve proxying enabled.

If `ray.init` hangs or raises a version-mismatch error, jump to
[Troubleshooting](#troubleshooting) below.

**Why `ray://...:10001` and not `http://...:8265`?** Port 10001 is the Ray
client server (binary protocol used by `ray.init`). Port 8265 is the
dashboard's HTTP UI — useful for browsing the cluster but not the right
entry point for `ray.init`. Port 8000 is the Serve HTTP endpoint where
deployed models receive requests.

## Step 3 — Deploy a model

### Hello world

Define a Serve deployment, bind it, and run it. The `serve.run(...)` call
registers the application with the Serve controller running on the head pod.

```python
from ray import serve
import requests

@serve.deployment
class Hello:
    async def __call__(self, request):
        return "Hello from Ray Serve!"

serve.run(Hello.bind(), name="hello", route_prefix="/hello")

resp = requests.get(
    "http://rayserve-nebari-rayserve-serve-svc.rayserve.svc.cluster.local:8000/hello"
)
print(resp.text)
# Hello from Ray Serve!
```

The application is now live. Other notebooks (and other in-cluster services)
can hit the same URL. To remove the application (and all of its deployments):

```python
serve.delete("hello")
```

`serve.delete(name)` removes the application registered under `name` — not a
single `@serve.deployment` inside it. The Ray cluster itself keeps running.

### Real models

For real-world patterns — JSON request bodies, `num_replicas`, GPU-aware
`ray_actor_options`, request batching, and chained models — the upstream
[Ray Serve quickstart](https://docs.ray.io/en/latest/serve/getting_started.html)
and [model composition guide](https://docs.ray.io/en/latest/serve/model_composition.html)
apply unchanged on this pack. Your model's dependencies need to be available
on the Ray cluster — ask your operator how to add new packages.

## Step 4 — The Ray Dashboard

The Ray Dashboard exposes cluster state, Serve application status, and
per-deployment logs.

Open it from the **Ray** tile on your Nebari landing page. If OIDC auth
is enabled, the first visit redirects to Keycloak for login; subsequent
visits in the same browser session pass through.

**The dashboard's Serve tab** lists deployed applications, their status, and
recent request volume. This is the fastest way to confirm a `serve.run(...)`
call took effect.

After running the Hello world example above, the Serve tab shows:

- Application `hello` with status `RUNNING` (green).
- One deployment `Hello` with status `HEALTHY` and one active replica.
- Recent request rate and latency, refreshed every few seconds.

![Ray Dashboard Serve tab with the hello application running and one healthy replica](/img/screenshots/dashboard-serve-healthy.png)

If a deployment stays in `DEPLOYING` for more than a minute, the replica
is likely stuck pulling the image or waiting for resources — ask your
operator to check the underlying pod status.

## Accessing your model from outside the cluster

By default, the Serve endpoint is **internal-only** — reachable from
notebooks on the cluster but not from a browser on your laptop. This is
the recommended default for most deployments; it removes an attack
surface and keeps you out of the auth-and-TLS path.

If your operator has enabled external access, end users hit the hostname
they configured:

```bash
curl https://rayserve.your-cluster.example.com/hello
```

The first request returns a 302 to Keycloak; after login, a session cookie
is set and subsequent requests pass through.

![Keycloak login screen prompting for credentials when first hitting the external Ray Serve endpoint](/img/screenshots/keycloak-login.png)

:::warning[Browser clients only]

The OIDC flow only works for clients that can handle redirects and
cookies. Service-to-service callers (other notebooks, inference
pipelines) should stay on the in-cluster service name — they bypass
the gateway entirely and need no auth.

:::

Ask your operator for the external hostname — that's the URL external
clients should hit. The full Troubleshooting index for external access
lives at [Troubleshoot](./troubleshoot).

## Troubleshooting

### `ray.init` hangs or fails with a version error

The most common failure mode. The Ray client and the Ray cluster must be on
the same Ray version *and* the same Python minor version (3.9 ≠ 3.10).

Check your notebook's versions:

```python
import sys, ray
print(ray.__version__, sys.version_info[:2])
```

Compare against the cluster. Authoritative answer: ask your operator.
Programmatic answer (once you have *some* working notebook session):
use the `@ray.remote` snippet shown in
[Step 1](#step-1--prepare-your-notebook-environment) — `ray.__version__`
on its own reports the local client version, not the cluster's.

If your local Ray or Python version doesn't match, recreate the Nebi
workspace pinned to the cluster's versions (see
[Step 1](#step-1--prepare-your-notebook-environment)). A restart of the
JupyterLab session is required for the new kernel to be picked up.

### Notebook can't reach the Ray service

`ray.init(...)` hangs indefinitely, and a `curl` from a notebook terminal
to the head service times out. The most common cause is a JupyterHub
network policy blocking egress to private cluster IPs.

This is not something you can fix from the notebook — ask your operator
to allow egress from the JupyterHub singleuser namespace to the Ray
service (typically `rayserve.svc.cluster.local`). The operator-side fix
is documented at
[Deploy → JupyterHub network policy blocks notebooks](../get-started/deploy#jupyterhub-network-policy-blocks-notebook-egress).

### My model is crashlooping or returning errors

A "broken" Serve deployment surfaces in two distinct ways. Knowing which
one you have narrows the cause quickly.

#### Replica fails to start — `DEPLOY_FAILED`

`serve.run(...)` returns, but the Dashboard's Serve tab shows the
deployment as `DEPLOY_FAILED` with a status message like
`"The deployment failed to start 3 times in a row"`. The replica's
`__init__` (or import of its module) raised, so the worker never
became ready to handle requests.

Click the failing deployment in the dashboard to see the underlying
exception. Common causes:

- **`ImportError`** — your code requires a package that is not installed
  in the Ray cluster's environment. Pin the same version in your Nebi
  workspace first to confirm it imports there, then ask your operator
  to add it to the cluster.
- **Out-of-memory during `__init__`** — model load exceeded the worker's
  memory limit. Ask your operator to give the worker more memory, or
  reduce model precision / weights footprint.
- **CUDA out of memory during `__init__`** — same as OOM but on the
  GPU. Reduce batch size or ask your operator for a larger GPU pool.

#### Replica started, but requests return 500s — deployment stays `HEALTHY`

A more subtle failure mode: `serve.run(...)` succeeds, the Dashboard
shows the deployment as `HEALTHY`, but every request returns a 500.
That happens when `__call__` raises on each request — the replica
itself is fine (it's running, it's responding), only the per-request
code path is broken. Serve doesn't flip health status based on
response codes, so the dashboard's Serve tab won't help here.

Diagnose from the request side:

```python
resp = requests.get("http://.../my-route")
print(resp.status_code, resp.text)   # the traceback is in resp.text
```

The Ray dashboard's **Logs** tab for the deployment shows the actual
exception. Common causes are missing input validation, a model expecting
a tensor shape it didn't get, or a downstream service call timing out.

## Reference

- Pack [README](https://github.com/nebari-dev/nebari-rayserve-pack/blob/main/README.md) — install, configuration, full `values.yaml` reference
- [Ray Serve docs](https://docs.ray.io/en/latest/serve/index.html) — upstream API and patterns
- [Ray Serve production guide](https://docs.ray.io/en/latest/serve/production-guide/index.html) — image build, autoscaling, rollouts
- [RayService CRD reference](https://docs.ray.io/en/latest/cluster/kubernetes/getting-started/rayservice-quick-start.html) — the K8s resource backing this pack
- [nebari-operator](https://github.com/nebari-dev/nebari-operator) — the NebariApp CRD that backs the optional routing/TLS/auth

## Next steps

- If your `serve.run(...)` workflow is working and you want it to survive
  cluster restarts, ask your operator about declaring the application
  in the chart's `serveApplications` config — declarative apps version
  with the cluster's GitOps repo and get zero-downtime rolling upgrades.
- If you need GPUs, ask your operator to enable GPU-capable workers.
- If your application needs to call out to other in-cluster services
  (object stores, vector DBs), ask your operator to add the matching
  egress rule.

---
title: Connecting from Jupyter
description: Reaching the Ray cluster from an in-cluster notebook — client, versions, and NetworkPolicy.
---

From a notebook in the same cluster — for example via
[nebari-data-science-pack](https://github.com/nebari-dev/nebari-data-science-pack) — connect
straight to the Kubernetes services. No gateway, no auth.

```python
import ray
from ray import serve
import requests

ray.init("ray://rayserve-nebari-rayserve-head-svc.rayserve.svc.cluster.local:10001")

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

No manual Serve initialization — the RayService starts the proxy with `host: 0.0.0.0` on
port 8000 automatically.

The two addresses do different jobs: `ray://…:10001` is the Ray client protocol for
submitting work, and `http://…:8000` is the Serve HTTP proxy for calling deployed models.

## Versions must match

:::caution[Ray and Python versions in the notebook must match the cluster]
The Ray client protocol is not version-tolerant. A mismatch fails at `ray.init()`, usually
with a message about the protocol version rather than anything mentioning versions you
recognise.
:::

The chart deploys **Ray 2.43.0 on Python 3.9**. Confirm against the running cluster rather
than trusting the default:

```bash
POD=$(kubectl get pod -n rayserve -l ray.io/node-type=head -o name)
kubectl exec -n rayserve $POD -- ray --version
kubectl exec -n rayserve $POD -- python --version
```

With [Nebi](https://github.com/nebari-dev/nebari-nebi-pack) managing environments:

```toml
[workspace]
name = "ray-serve"
channels = ["conda-forge"]
platforms = ["linux-64"]

[dependencies]
python = "3.9.*"
ray-serve = "2.43.*"
ipykernel = ">=6.0"
```

If you change `image.tag`, every notebook environment has to move with it. That coupling is
the main argument for pinning the image tag rather than tracking a moving one.

## NetworkPolicy

JupyterHub's default singleuser policy blocks egress to private IPs, which includes every
in-cluster Service. Add to your data-science-pack values:

```yaml
jupyterhub:
  singleuser:
    networkPolicy:
      egressAllowRules:
        privateIPs: true
```

Existing servers do not pick this up — users must stop and start from the hub control
panel.

The symptom is a hang rather than an error: `ray.init()` sits until it times out, and the
`requests.get()` does the same.

:::caution[`privateIPs: true` is broad]
It permits egress to every private address the notebook can route to, not only Ray. If your
cluster needs tighter scoping, write a targeted rule for the `rayserve` namespace instead —
the ports are `10001` (client), `8000` (serve), and `6379` (GCS) if you use it.
:::

## Service names

Both follow `<release>-<chart>-{head,serve}-svc`:

```bash
kubectl get svc -n rayserve
```

```
rayserve-nebari-rayserve-head-svc    ClusterIP   8265/TCP,10001/TCP,6379/TCP
rayserve-nebari-rayserve-serve-svc   ClusterIP   8000/TCP
```

Copy them from that output rather than reconstructing them by hand — a `nameOverride` or a
different release name changes both.

## What survives a restart

Nothing deployed this way. `serve.run()` puts the deployment in the running Ray cluster's
state; if the RayService rolls the cluster — an image change, a config change, a node
failure — the application is gone.

That is the right trade for development. For anything that must come back on its own, use
declarative `serveApplications` with the code baked into an image. See
[Deploying models](/serve-applications/).

## Working with an existing deployment

Connecting does not require deploying. From a notebook you can inspect and call what is
already running:

```python
import ray
from ray import serve

ray.init("ray://rayserve-nebari-rayserve-head-svc.rayserve.svc.cluster.local:10001")
print(serve.status())

handle = serve.get_deployment_handle("MyModel", app_name="my-model")
print(handle.remote({"input": 1}).result())
```

`serve.status()` is also the quickest way to see why an application is not serving — it
reports per-deployment state and the last error.

## Resources

A notebook connected over `ray://` submits tasks that run on the Ray **cluster**, using the
head and worker resources configured in the chart — not the notebook pod's. The default is
one worker with 2 CPU and 4Gi. Anything demanding needs the cluster scaled first; see
[Scaling and GPUs](/scaling/).

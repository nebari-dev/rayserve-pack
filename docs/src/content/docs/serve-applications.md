---
title: Deploying models
description: Declarative serveApplications versus deploying from a notebook.
---

Two ways to get a model serving, with different durability.

| | From a notebook | Declarative |
|---|---|---|
| How | `serve.run()` over `ray://` | `serveApplications` in values |
| Code lives in | the notebook session | a container image |
| Survives a cluster roll | no | yes |
| Zero-downtime upgrade | no | yes, via RayService |
| Good for | development, experiments | production |

## Declarative applications

```yaml
image:
  repository: your-registry/your-ray-image
  tag: "2.43.0-custom"

serveApplications:
  - name: my-model
    route_prefix: /predict
    import_path: myapp.model:app
    deployments:
      - name: MyModel
        num_replicas: 2
```

This becomes the `applications` list in the RayService's `serveConfigV2`. The RayService
controller takes it from there: deploying, health-monitoring, and performing zero-downtime
upgrades when the config changes.

`import_path` is `module:attribute` — a Python module importable inside the Ray image, and
an attribute holding a bound Serve application. It is **not** a path in the chart or on
your laptop.

:::caution[The code must already be in the image]
There is no mechanism here for shipping source into the cluster. `import_path` resolves
against the running container's Python path, so a module the image does not contain fails
to import and the application never becomes healthy.
:::

## Building the image

```dockerfile
FROM rayproject/ray:2.43.0

COPY myapp /home/ray/myapp
RUN pip install --no-cache-dir -r /home/ray/myapp/requirements.txt
ENV PYTHONPATH=/home/ray
```

with `myapp/model.py`:

```python
from ray import serve

@serve.deployment
class MyModel:
    def __init__(self):
        self.model = load_model()

    async def __call__(self, request):
        payload = await request.json()
        return self.model.predict(payload["input"])

app = MyModel.bind()
```

Base the image on the **same Ray version** the chart deploys — `image.tag`, default
`2.43.0`. Ray does not tolerate a version skew between the image and `rayVersion`, which
the chart sets from the same value.

## Serve config options

Anything valid in
[Ray Serve's config schema](https://docs.ray.io/en/latest/serve/production-guide/config.html)
can go in a `serveApplications` entry, since the list is serialized straight into
`serveConfigV2`:

```yaml
serveApplications:
  - name: my-model
    route_prefix: /predict
    import_path: myapp.model:app
    runtime_env:
      pip: ["torch==2.1.0"]
    deployments:
      - name: MyModel
        num_replicas: 2
        max_ongoing_requests: 10
        ray_actor_options:
          num_cpus: 1
          num_gpus: 1
```

`runtime_env.pip` installs at deployment time. Convenient for iteration; slow and
network-dependent on every replica start, so bake dependencies into the image for
production.

`ray_actor_options.num_gpus` is how a deployment claims a GPU. The pod also has to be
scheduled somewhere with one — see [Scaling and GPUs](/scaling/).

## Multiple applications

```yaml
serveApplications:
  - name: classifier
    route_prefix: /classify
    import_path: myapp.classifier:app
  - name: embedder
    route_prefix: /embed
    import_path: myapp.embedder:app
```

They share the cluster and the HTTP proxy, routed by prefix. Route prefixes must not
overlap.

## The HTTP proxy

```yaml
serve:
  proxyLocation: EveryNode
```

| Value | Effect |
|---|---|
| `EveryNode` (default) | An HTTP proxy on every Ray pod. Each pod is its own scheduling unit, can ingress traffic, and pod-local probes can hit `localhost:8000`. |
| `HeadOnly` | One proxy on the head pod. Saves resources; single ingress point. Useful on very large clusters. |
| `Disabled` | No HTTP at all — programmatic Serve handles only. |

`EveryNode` is the right default with KubeRay. Note that the chart's `serve-svc` targets
**only the head pod** regardless, so the extra proxies matter for in-cluster direct-to-pod
traffic, not for the Service.

## Updating

Change `serveApplications` (or the image tag) and upgrade. The RayService controller
performs a zero-downtime rollout: it brings up a new cluster or new replicas, waits for
health, then shifts traffic.

```bash
helm upgrade rayserve chart -n rayserve -f my-values.yaml
kubectl -n rayserve get rayservice -o yaml | grep -A20 status
```

Under Argo CD, `/status` and `/spec/rayClusterConfig` are in `ignoreDifferences`, so watch
the RayService status rather than the Application's sync state. See
[Deploying on Nebari](/deployment/#why-ignoredifferences-is-there).

## Checking application health

```bash
kubectl -n rayserve get rayservice rayserve-nebari-rayserve -o jsonpath='{.status}' | jq
```

Or from the dashboard's Serve tab, which shows per-deployment replica counts and the last
error. From Python:

```python
from ray import serve
print(serve.status())
```

An application stuck in `DEPLOY_FAILED` is nearly always an import error — the module is
not in the image, or a dependency is missing. The Serve controller logs carry the
traceback:

```bash
kubectl -n rayserve logs $(kubectl -n rayserve get pod -l ray.io/node-type=head -o name) | grep -i "deploy"
```

## Runtime deployment via the REST API

The Ray dashboard exposes a REST API for deploying applications without a chart change.
Useful for experiments; the same durability caveat as the notebook path applies — the
config lives in the cluster, and the chart's `serveConfigV2` reasserts itself on the next
RayService reconcile.

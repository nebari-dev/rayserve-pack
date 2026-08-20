---
title: Getting started
description: Install the pack and reach the Ray dashboard and Serve endpoint.
---

## Prerequisites

- [kubectl](https://kubernetes.io/docs/tasks/tools/) and [Helm 3](https://helm.sh/docs/intro/install/)
- A Kubernetes cluster — [kind](https://kind.sigs.k8s.io/) is enough for a first look
- For the Nebari path only: nebari-operator, Envoy Gateway, cert-manager, and Keycloak

## Install

```bash
cd chart
helm dependency update .
helm install rayserve . --create-namespace -n rayserve --wait --timeout 5m
```

`--timeout 5m` is not padding. The Ray image is large, and the head pod has to come up and
start its GCS before workers can join.

`nebariapp.enabled` defaults to `false`, so this installs standalone. For the Nebari path
see [Deploying on Nebari](/deployment/).

## What gets deployed

| Object | Kind | Purpose |
|---|---|---|
| `rayserve-nebari-rayserve` | RayService | Ray cluster and Serve config |
| `rayserve-nebari-rayserve-head-svc` | Service | `:8265` dashboard, `:10001` ray client, `:6379` GCS |
| `rayserve-nebari-rayserve-serve-svc` | Service | `:8000` Serve HTTP |
| `kuberay-operator` | Deployment | Reconciles the RayService |

Names come from the fullname helper — `<release>-<chart>` — so a release named `rayserve`
gives `rayserve-nebari-rayserve`. Long, but predictable, and the same helper feeds the
`NebariApp` service references.

:::note[The two Services are the chart's, not KubeRay's]
RayService creates its own stable services only once every Serve application reports
healthy. With the default empty `serveApplications` that never happens, so the dashboard
would be unreachable. The chart renders both Services itself, selecting the head pod
directly, so they work from the first second.
:::

## Reach it

```bash
# Ray dashboard
kubectl port-forward svc/rayserve-nebari-rayserve-head-svc 8265:8265 -n rayserve

# Serve HTTP endpoint
kubectl port-forward svc/rayserve-nebari-rayserve-serve-svc 8000:8000 -n rayserve
```

The dashboard at `http://localhost:8265` shows the cluster, its nodes, and the Serve
controller. With no applications deployed the Serve tab is empty — expected.

## Verify

```bash
kubectl -n rayserve get rayservice,raycluster,pods

# The head pod's own view
kubectl -n rayserve exec $(kubectl -n rayserve get pod -l ray.io/node-type=head -o name) -- ray status
```

`ray status` should list the head and one worker with their CPU and memory. A worker stuck
at `0/1 Ready` is worth reading about in [Scaling and GPUs](/scaling/#probes) — the chart
overrides KubeRay's default probes precisely to avoid that.

## Deploy something

The fastest check is from inside the cluster:

```bash
kubectl -n rayserve exec -it $(kubectl -n rayserve get pod -l ray.io/node-type=head -o name) -- python -c "
from ray import serve

@serve.deployment
class Hello:
    async def __call__(self, request):
        return 'Hello from Ray Serve!'

serve.run(Hello.bind(), name='hello', route_prefix='/hello')
print('deployed')
"
```

Then, with the serve port forwarded:

```bash
curl http://localhost:8000/hello
# Hello from Ray Serve!
```

For real work there are two proper paths — a notebook against `ray://`, or declarative
applications baked into an image. See [Connecting from Jupyter](/jupyter/) and
[Deploying models](/serve-applications/).

## Uninstall

```bash
helm uninstall rayserve -n rayserve
```

This removes the RayService, and KubeRay tears down the Ray cluster with it. Anything
deployed at runtime through `serve.run()` goes too — Serve state lives in the cluster, not
in Kubernetes.

## Next

- **[Connecting from Jupyter](/jupyter/)** — the version-matching requirement bites early
- **[Deploying models](/serve-applications/)** — how to make applications survive a restart
- **[Deploying on Nebari](/deployment/)** — external access with TLS and OIDC

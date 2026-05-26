---
title: Deploy the pack
description: Install the Ray Serve pack on a standalone cluster or via ArgoCD on Nebari, then configure routing, TLS, OIDC auth, and Ray cluster sizing.
sidebar_position: 2
---

# Deploy the pack

This guide is for **operators** installing the pack on a Kubernetes cluster.
End users connecting to an already-deployed cluster should read
[Use Ray Serve](../how-tos/use_ray_from_notebook) instead.

The pack deploys:

- The **KubeRay operator** (manages the Ray cluster lifecycle).
- A **RayService** custom resource (the Ray cluster + Serve proxy).
- Stable Kubernetes **Services** for the dashboard and serve endpoint.
- Optional **NebariApp** resources for external routing, TLS, and OIDC auth
  via Envoy Gateway and Keycloak (only when `nebariapp.enabled: true`).

## Prerequisites

| Requirement | Notes |
|---|---|
| Kubernetes | 1.25+ (tested); [kind](https://kind.sigs.k8s.io/) works for local dev |
| Tooling | [`kubectl`](https://kubernetes.io/docs/tasks/tools/), [Helm 3](https://helm.sh/docs/intro/install/) |
| For Nebari deployments | nebari-operator and Envoy Gateway already installed; an ArgoCD instance and a GitOps repo |
| For OIDC auth | Keycloak already deployed and reachable from the gateway |

## Standalone install (no Nebari)

Use this path for local dev or clusters without nebari-operator. Skips the
NebariApp routing layer entirely — you reach the cluster via `kubectl
port-forward`.

```bash
git clone https://github.com/nebari-dev/nebari-rayserve-pack.git
cd nebari-rayserve-pack/chart
helm dependency update .
helm install rayserve . --create-namespace -n rayserve --wait --timeout 5m
```

After install, port-forward the dashboard and serve endpoint:

```bash
# Ray Dashboard
kubectl port-forward svc/rayserve-nebari-rayserve-head-svc 8265:8265 -n rayserve

# Ray Serve HTTP endpoint
kubectl port-forward svc/rayserve-nebari-rayserve-serve-svc 8000:8000 -n rayserve
```

Then browse to `http://localhost:8265` (dashboard) or send requests to
`http://localhost:8000/<route>` once you deploy an application.

## Nebari install (ArgoCD + GitOps)

The recommended production deployment. The chart creates NebariApp
resources that the nebari-operator picks up to provision routing, TLS, and
optional OIDC authentication.

Drop the following at `apps/rayserve-pack.yaml` in your GitOps repo:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rayserve-pack
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "7"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/nebari-dev/nebari-rayserve-pack.git
    targetRevision: main
    path: chart
    helm:
      releaseName: rayserve
      values: |
        nebariapp:
          enabled: true
          serve:
            enabled: false      # keep serve endpoint internal-only
          dashboard:
            enabled: true
            hostname: ray-dashboard.example.com
          auth:
            enabled: true
            provider: keycloak
            provisionClient: true
            redirectURI: /oauth2/callback
  destination:
    server: https://kubernetes.default.svc
    namespace: rayserve
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    managedNamespaceMetadata:
      labels:
        nebari.dev/managed: "true"
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
      - RespectIgnoreDifferences=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  # KubeRay's controller mutates RayService and Service resources at
  # runtime (selectors, status fields). Without these ignore rules,
  # ArgoCD will sit in a permanent OutOfSync state.
  ignoreDifferences:
    - group: ""
      kind: Service
      jsonPointers:
        - /spec/selector
        - /spec/clusterIP
        - /spec/clusterIPs
    - group: ray.io
      kind: RayService
      jsonPointers:
        - /spec/rayClusterConfig
        - /status
```

:::warning[`nebari.dev/managed: "true"` is required]

The `managedNamespaceMetadata` block applies the `nebari.dev/managed`
label to the namespace. **Drop this and the nebari-operator will silently
ignore your NebariApp resources** — the dashboard hostname will resolve
but return 404 or the wrong content, and `kubectl describe nebariapp`
will show no progress on conditions.

:::

:::warning[`redirectURI` must be a real callback path]

A bare `/` does not function as the OIDC callback — Envoy Gateway needs a
distinct path it can route to the OAuth handler. Always use a real path
like `/oauth2/callback` (the default in the example above).

:::

### Internal-only vs externally-exposed

| Setting | Internal-only (recommended) | Externally exposed |
|---|---|---|
| Serve endpoint | `nebariapp.serve.enabled: false` | `nebariapp.serve.enabled: true` + `nebariapp.hostname: ...` |
| Reachable from | Notebooks on the same cluster via service DNS | Browsers and external clients via HTTPS |
| Auth | None (cluster-internal traffic) | OIDC via Keycloak (recommended) |
| Use when | Models are consumed by other in-cluster services / data-science notebooks | You need a public API endpoint |

The dashboard is a separate decision (`nebariapp.dashboard.enabled`).
Most deployments expose the dashboard externally (so users can monitor
their applications from a browser) while keeping the serve endpoint
internal-only.

## Configuration

The full reference — every chart value with its type, default, and
description — lives at [Reference → `values.yaml` reference](../references/values).
The tables below cover the knobs you'll most often touch when installing.

:::note[Defaults shown reflect chart v0.3.0]

Version numbers and defaults in the tables below mirror the chart at the
time of writing. The source of truth is
[`chart/values.yaml`](https://github.com/nebari-dev/nebari-rayserve-pack/blob/main/chart/values.yaml)
on `main` — check there for the currently pinned Ray image tag and
resource defaults before relying on a specific value.

:::

### NebariApp / external access

| Value | Default | Description |
|---|---|---|
| `nebariapp.enabled` | `false` | Create NebariApp resources for routing/TLS/auth |
| `nebariapp.hostname` | — | Hostname for the serve endpoint (required when `serve.enabled`) |
| `nebariapp.serve.enabled` | `false` | Expose the serve endpoint externally |
| `nebariapp.dashboard.enabled` | `true` | Create NebariApp for the dashboard |
| `nebariapp.dashboard.hostname` | — | Hostname for the dashboard (required when `dashboard.enabled`) |
| `nebariapp.auth.enabled` | `false` | Require Keycloak OIDC login for external access |
| `nebariapp.auth.redirectURI` | `/oauth2/callback` | OAuth callback path (Envoy rejects `/`) |
| `nebariapp.gateway` | `public` | `public` or `internal` Envoy gateway |

### Ray cluster sizing

| Value | Default | Description |
|---|---|---|
| `image.repository` | `rayproject/ray` | Ray container image |
| `image.tag` | `2.43.0` | Ray version (must match the client version in user notebooks) |
| `head.resources.requests.cpu` | `1` | Head node CPU request |
| `head.resources.requests.memory` | `2Gi` | Head node memory request |
| `worker.replicas` | `1` | Number of worker nodes |
| `worker.minReplicas` / `worker.maxReplicas` | `1` / `1` | Autoscaling bounds (set equal to disable autoscaling) |
| `worker.resources.requests.cpu` | `1` | Worker CPU request |
| `worker.resources.requests.memory` | `2Gi` | Worker memory request |

### GPU workloads

Set `runtimeClassName: nvidia` on the head or worker (or both) and
declare the GPU resource:

```yaml
worker:
  runtimeClassName: nvidia
  resources:
    limits:
      nvidia.com/gpu: 1
      cpu: "4"
      memory: "16Gi"
    requests:
      cpu: "2"
      memory: "8Gi"
```

:::note[Image must include CUDA]

The default `rayproject/ray:2.43.0` image does **not** include CUDA. For
GPU workloads, switch to `rayproject/ray:2.43.0-gpu` or bake your own
CUDA-enabled image, and make sure the NVIDIA device plugin is running
on your cluster.

:::

### Production: custom image with model code baked in

For real workloads, build a custom Ray image with your model code and
dependencies pre-installed, then declare applications via
`serveApplications`:

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

The `import_path` must be importable from inside the Ray container.
End users no longer need to call `serve.run(...)` — the RayService
controller deploys and monitors these applications, including
zero-downtime rolling upgrades when you change the chart values.

See the upstream [Ray Serve production guide](https://docs.ray.io/en/latest/serve/production-guide/index.html)
for image-build recipes, autoscaling configuration, and rollout policies.

### Worker pod health probes

The chart ships with custom worker `readinessProbe` and `livenessProbe`
that check raylet health alone, **not** the Serve HTTP proxy. The
upstream KubeRay default probes also check Serve, which fails forever
on a fresh cluster with no applications deployed — workers stay 0/1 Ready.

The chart's defaults are documented inline in `values.yaml` (see the
`worker.readinessProbe` block). You should not need to touch them
unless you're diagnosing pod-health issues; if you do, set the probe to
`null` (YAML `~`) to fall back to KubeRay's default rather than to `{}`
(which won't suppress due to Helm's deep-merge behavior).

## Verifying the deployment

After install (or ArgoCD sync), check the RayService is `Running` and
the cluster is `Ready`:

```bash
kubectl get rayservice -n rayserve
kubectl get pods -n rayserve
```

Expected:

```
NAME                  SERVICE STATUS   NUM SERVE ENDPOINTS
rayserve-nebari-...   Running          0
```

The `NUM SERVE ENDPOINTS` is zero until an end user deploys their first
application (via `serve.run(...)` or `serveApplications`).

If `nebariapp.enabled`, check the NebariApp conditions:

```bash
kubectl get nebariapp -n rayserve
kubectl describe nebariapp -n rayserve
```

You want `RoutingReady`, `TLSReady`, and (when auth is on) `AuthReady`
all `True`.

Once everything is reconciled, the pack appears as a tile on the Nebari
landing page (when `landingPage.enabled: true` on the nebari-operator),
ready for end users to click through:

![Nebari landing page showing the Ray service tile in the Healthy state](/img/screenshots/nebari-landing-ray-tile.png)

## Operator troubleshooting

### ArgoCD shows permanent `OutOfSync`

The KubeRay controller mutates RayService and Service resources at
runtime — it adds selectors, status fields, etc. Without
`ignoreDifferences` in the ArgoCD Application (see the example above),
ArgoCD never reaches Synced.

If you copied the example block from this page, you're already
covered. If not, add the `ignoreDifferences` array from the Nebari
install section.

### NebariApp stuck with `RoutingReady: False`

Most common cause: the namespace doesn't have the `nebari.dev/managed`
label.

```bash
kubectl get namespace rayserve --show-labels | grep nebari.dev/managed
```

If missing:

```bash
kubectl label namespace rayserve nebari.dev/managed=true
```

The ArgoCD `managedNamespaceMetadata` block in the example sets this
automatically; check that block is present and that your ArgoCD version
supports it (v2.7+).

### Dashboard returns 500 via NebariApp

The NebariApp's HTTPRoute is pointing at a service that doesn't
resolve. List actual services:

```bash
kubectl get svc -n rayserve
```

You should see `<release>-nebari-rayserve-head-svc` and
`<release>-nebari-rayserve-serve-svc`. If you set
`nebariapp.service.name` to a custom value that doesn't exist, the
NebariApp will produce a working HTTPRoute pointing at nothing.

### Worker pods stuck `0/1 Ready`

Usually means you've overridden `worker.readinessProbe` to `{}` (empty
map) and the upstream KubeRay default kicked in — that default chains a
Serve HTTP check that fails on a cluster with no deployed applications.

Set the probe to `null` (YAML `~`) to truly suppress, or leave the
chart's defaults in place. See the comments in `values.yaml`.

### JupyterHub network policy blocks notebook egress

End users report that `ray.init(...)` from a notebook hangs forever, and
a `curl` from the notebook terminal to
`rayserve-nebari-rayserve-head-svc.rayserve.svc.cluster.local:10001`
times out. The JupyterHub singleuser pod has no route to the Ray
namespace.

JupyterHub's default `singleuser.cmd: ...` configuration ships a
NetworkPolicy that blocks egress to private cluster IPs except for a
small DNS allowlist. The Ray namespace isn't in it.

Allow egress from the singleuser namespace to the Ray namespace
(adjust namespace selectors to match your install):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-jupyter-to-rayserve
  namespace: <jupyterhub-singleuser-namespace>
spec:
  podSelector:
    matchLabels:
      hub.jupyter.org/network-access-singleuser: "true"
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: rayserve
      ports:
        - protocol: TCP
          port: 10001     # Ray client
        - protocol: TCP
          port: 8000      # Serve HTTP
        - protocol: TCP
          port: 8265      # Dashboard
```

If you're running the Nebari JupyterHub chart, the same allowlist can be
added under `jupyterhub.singleuser.networkPolicy.egress` instead of a
free-standing NetworkPolicy.

## Next steps

- **End users** → [Use Ray Serve](../how-tos/use_ray_from_notebook) — how to connect a
  notebook, deploy a model, and read the dashboard.
- **Full chart reference** → [`values.yaml` reference](../references/values) —
  every option with type, default, and description, sourced from
  [`chart/values.yaml`](https://github.com/nebari-dev/nebari-rayserve-pack/blob/main/chart/values.yaml).
- **How it fits together** → [Architecture](../references/architecture) —
  the Kubernetes resources the chart creates and how they interact.
- **Upstream docs** → [Ray Serve production guide](https://docs.ray.io/en/latest/serve/production-guide/index.html),
  [KubeRay RayService guide](https://docs.ray.io/en/latest/cluster/kubernetes/getting-started/rayservice-quick-start.html).

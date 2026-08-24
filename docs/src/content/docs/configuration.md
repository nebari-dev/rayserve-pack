---
title: Configuration
description: Values reference for the Nebari Rayserve Pack Helm chart.
---

Everything is owned by this chart except `kuberay-operator.*`, which passes through to the
[KubeRay operator chart](https://github.com/ray-project/kuberay-helm) (1.3.0).

## Image

| Value | Default | Purpose |
|---|---|---|
| `image.repository` | `rayproject/ray` | Used for both head and workers. |
| `image.tag` | `2.43.0` | Ray version. Written verbatim into the RayService's `rayVersion`, so tag custom images with the plain Ray version. |

For production, build a custom image with your model code — see
[Deploying models](/serve-applications/). Notebook environments must match this version;
see [Connecting from Jupyter](/jupyter/#versions-must-match).

## `head`

| Value | Default | Purpose |
|---|---|---|
| `head.resources.requests` | `cpu: 1`, `memory: 2Gi` | — |
| `head.resources.limits` | `cpu: 2`, `memory: 4Gi` | — |
| `head.runtimeClassName` | unset | e.g. `nvidia`. |
| `head.containerEnv` | `[]` | Extra environment variables. |
| `head.tolerations` | `[]` | Extra tolerations; an `nvidia.com/gpu` one is injected automatically when the GPU resource is requested. |
| `head.readinessProbe` | `{}` | Empty means KubeRay's built-in probe applies. |
| `head.livenessProbe` | `{}` | Same. |

## `worker`

| Value | Default | Purpose |
|---|---|---|
| `worker.replicas` | `1` | Worker pods. |
| `worker.minReplicas` | `1` | Lower clamp on `replicas`. Pinned to `1` in `values.yaml` — it does not follow `replicas`. |
| `worker.maxReplicas` | `1` | Upper clamp on `replicas`. Same caveat; leave it below `replicas` and you get `maxReplicas` workers. |
| `worker.resources.requests` | `cpu: 1`, `memory: 2Gi` | — |
| `worker.resources.limits` | `cpu: 2`, `memory: 4Gi` | — |
| `worker.runtimeClassName` | unset | e.g. `nvidia`. |
| `worker.containerEnv` | `[]` | Extra environment variables. |
| `worker.tolerations` | `[]` | As above. |
| `worker.readinessProbe` | raylet healthz | Overrides KubeRay's Serve-dependent default. |
| `worker.livenessProbe` | raylet healthz | Same command; longer thresholds. |

:::caution[`{}` does not suppress a probe]
Helm's deep merge keeps existing keys when overlaying with an empty map. Use `null` (`~`) to
fall back to KubeRay's default. Full rationale in [Scaling and GPUs](/scaling/#probes).
:::

:::caution[Always set `replicas`, `minReplicas`, and `maxReplicas` together]
The chart does not enable `enableInTreeAutoscaling`, so there is no Ray autoscaler and the
group size is exactly `replicas` — clamped into `[minReplicas, maxReplicas]` by KubeRay.
Since `values.yaml` pins both bounds to `1`, raising `replicas` alone changes nothing. See
[Scaling and GPUs](/scaling/#adding-workers).
:::

## `serve` and `serveApplications`

| Value | Default | Purpose |
|---|---|---|
| `serve.proxyLocation` | `EveryNode` | `EveryNode`, `HeadOnly`, or `Disabled`. |
| `serveApplications` | `[]` | Applications, serialized into `serveConfigV2`. |

Each entry needs a `name` and an `import_path` resolvable inside the image. `route_prefix`
is optional — it defaults to `/`, which means you must set it explicitly once you have more
than one application. Anything else valid in
[Ray Serve's config schema](https://docs.ray.io/en/latest/serve/production-guide/config.html)
is passed through. See [Deploying models](/serve-applications/).

## `nebariapp`

| Value | Default | Purpose |
|---|---|---|
| `nebariapp.enabled` | `false` | Render `NebariApp` resources. |
| `nebariapp.hostname` | unset | Serve endpoint hostname. Required for the serve `NebariApp`. |
| `nebariapp.serve.enabled` | `false` | Expose the serve endpoint externally. |
| `nebariapp.dashboard.enabled` | `true` | Create a `NebariApp` for the dashboard. |
| `nebariapp.dashboard.hostname` | unset | **Required** when the dashboard is enabled — the render fails without it. |
| `nebariapp.dashboard.landingPage.*` | disabled | Landing-page tile; dashboard only. |
| `nebariapp.service.name` | `""` | Overrides the backend service for **both** resources. |
| `nebariapp.service.servePort` | `8000` | — |
| `nebariapp.service.dashboardPort` | `8265` | — |
| `nebariapp.gateway` | `public` | `public` or `internal`; applies to both. |

:::caution[The two hostnames behave differently when missing]
`dashboard.hostname` uses `required`, so its absence fails the Helm render with a clear
message. `nebariapp.hostname` does not — the serve `NebariApp` is simply not rendered, with
no error. See [Deploying on Nebari](/deployment/).
:::

:::note[`service.name` overrides both]
Set it and both the serve and dashboard `NebariApp`s point at the same service. Leave it
empty and each uses its correct default (`-serve-svc` and `-head-svc` respectively) — which
is almost always what you want.
:::

### `nebariapp.auth`

| Value | Default | Purpose |
|---|---|---|
| `auth.enabled` | `false` | OIDC at the gateway, for both resources. |
| `auth.provider` | `keycloak` | — |
| `auth.provisionClient` | `true` | Operator creates the Keycloak client. |
| `auth.redirectURI` | `/oauth2/callback` | Envoy Gateway rejects a bare `/`. |
| `auth.scopes` | `openid, profile, email` | — |

Auth is all-or-nothing across both endpoints.

## `orgCABundle`

| Value | Default | Purpose |
|---|---|---|
| `orgCABundle.configMapName` | `""` | ConfigMap with key `ca.crt`. Empty disables injection entirely. |
| `orgCABundle.initImage` | `alpine:3.20` | Needs only `sh` and `cat`. |

Read [Organization CA bundle](/ca-bundle/) before enabling this under Argo CD — the example
sync policy can silently drop the injection.

## Subchart and overrides

| Value | Default | Purpose |
|---|---|---|
| `kuberay-operator.enabled` | `true` | Install the operator with the chart. Set false when one already runs cluster-wide. |
| `nameOverride` | `""` | Changes the chart name in the fullname helper — and therefore both Service names. |
| `fullnameOverride` | `""` | Same, more directly. |

:::caution[Name overrides change the Service names]
`-head-svc` and `-serve-svc` are both derived from the fullname helper, and the `NebariApp`
defaults follow it. Notebook connection strings are *not* — anything hardcoding a service
name has to be updated too.
:::

## A GPU production values file

```yaml
image:
  repository: your-registry/your-ray-image
  tag: "2.43.0"

head:
  resources:
    requests: { cpu: "2", memory: "8Gi" }
    limits:   { cpu: "4", memory: "16Gi" }

worker:
  replicas: 2
  minReplicas: 2
  maxReplicas: 2
  runtimeClassName: nvidia
  resources:
    requests: { cpu: "4", memory: "16Gi" }
    limits:   { cpu: "8", memory: "32Gi", nvidia.com/gpu: 1 }

serveApplications:
  - name: my-model
    route_prefix: /predict
    import_path: myapp.model:app
    deployments:
      - name: MyModel
        num_replicas: 2
        ray_actor_options:
          num_gpus: 1

nebariapp:
  enabled: true
  serve:
    enabled: false
  dashboard:
    enabled: true
    hostname: ray-dashboard.example.com
    landingPage:
      enabled: true
  auth:
    enabled: true
  gateway: internal
```

## Inspecting

```bash
helm dependency update chart   # once — templating fails without the kuberay-operator subchart
helm template rayserve chart --set nebariapp.enabled=true \
  --set nebariapp.dashboard.hostname=ray-dashboard.example.com | less

helm -n rayserve get values rayserve
helm -n rayserve get values rayserve --all
```

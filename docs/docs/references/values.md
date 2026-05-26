---
title: values.yaml reference
description: Full reference for the chart's Helm values — every option, its type, default, and a short description.
sidebar_position: 1
---

# `values.yaml` reference

This page documents every option exposed by the chart. Source of truth is
[`chart/values.yaml`](https://github.com/nebari-dev/nebari-rayserve-pack/blob/main/chart/values.yaml)
in the repo — the table below mirrors that file, grouped for readability.

For example install invocations and the recommended `ignoreDifferences`
block for ArgoCD, see [Get started → Deploy the pack](../get-started/deploy).

:::note[Defaults reflect chart v0.3.0]

The pinned image tags and resource defaults shown here mirror the chart
at the time of writing. Always cross-check against
[`chart/values.yaml`](https://github.com/nebari-dev/nebari-rayserve-pack/blob/main/chart/values.yaml)
on `main` if you depend on a specific value.

:::

## NebariApp integration

Creates a NebariApp CRD that configures Envoy Gateway routing, TLS, and
optional Keycloak OIDC auth. Skip this whole block (`nebariapp.enabled: false`)
on a standalone cluster.

| Value | Type | Default | Description |
|---|---|---|---|
| `nebariapp.enabled` | bool | `false` | Master switch — create any NebariApp resource. |
| `nebariapp.hostname` | string | — | Hostname for the serve endpoint. **Required when `nebariapp.serve.enabled: true`.** |
| `nebariapp.serve.enabled` | bool | `false` | Expose the serve endpoint externally via the gateway. |
| `nebariapp.dashboard.enabled` | bool | `true` | Create a separate NebariApp for the Ray Dashboard. |
| `nebariapp.dashboard.hostname` | string | — | Hostname for the dashboard. **Required when `nebariapp.dashboard.enabled: true`.** |
| `nebariapp.dashboard.landingPage.enabled` | bool | `false` | Add the dashboard to the Nebari home page tile grid. |
| `nebariapp.dashboard.landingPage.displayName` | string | `Ray Dashboard` | Title shown on the landing tile. |
| `nebariapp.dashboard.landingPage.description` | string | _(see values.yaml)_ | One-line description for the tile. |
| `nebariapp.dashboard.landingPage.icon` | URL | _(Ray Serve icon)_ | Tile icon URL. |
| `nebariapp.dashboard.landingPage.category` | string | `Data Science` | Section the tile groups under. |
| `nebariapp.dashboard.landingPage.priority` | int | `20` | Sort order on the landing page (lower = earlier). |
| `nebariapp.dashboard.landingPage.healthCheck.enabled` | bool | `true` | Periodic probe so the tile reflects dashboard availability. |
| `nebariapp.dashboard.landingPage.healthCheck.path` | string | `/api/component_activities` | HTTP path probed. |
| `nebariapp.dashboard.landingPage.healthCheck.intervalSeconds` | int | `30` | Probe interval. |
| `nebariapp.dashboard.landingPage.healthCheck.timeoutSeconds` | int | `5` | Probe timeout. |
| `nebariapp.service.name` | string | _(auto)_ | Override the service the NebariApp targets. Leave blank to use `<release>-<chart>-serve-svc` / `-head-svc`. |
| `nebariapp.service.servePort` | int | `8000` | Serve endpoint port. |
| `nebariapp.service.dashboardPort` | int | `8265` | Dashboard port. |
| `nebariapp.auth.enabled` | bool | `false` | Require Keycloak OIDC for external access. |
| `nebariapp.auth.provider` | string | `keycloak` | OIDC provider name. |
| `nebariapp.auth.provisionClient` | bool | `true` | Have the nebari-operator create the Keycloak client automatically. |
| `nebariapp.auth.redirectURI` | string | `/oauth2/callback` | OAuth callback path. Must be a real path — a bare `/` does not function as the callback. |
| `nebariapp.auth.scopes` | list | `[openid, profile, email]` | OIDC scopes requested. |
| `nebariapp.gateway` | enum | `public` | `public` (internet-facing) or `internal` (cluster-internal) Envoy gateway. |

## KubeRay operator

| Value | Type | Default | Description |
|---|---|---|---|
| `kuberay-operator.enabled` | bool | `true` | Install the KubeRay operator as a chart subchart. Set `false` if it's already installed cluster-wide. |

## Ray Serve

| Value | Type | Default | Description |
|---|---|---|---|
| `serve.proxyLocation` | enum | `EveryNode` | Where Ray Serve runs its HTTP proxy. `EveryNode` (one proxy per Ray pod, recommended for KubeRay), `HeadOnly` (single proxy on head), or `Disabled` (no HTTP, programmatic handles only). |
| `serveApplications` | list | `[]` | Declarative list of Serve applications deployed via RayService's `serveConfigV2`. Each entry needs `name`, `route_prefix`, `import_path`, and `deployments`. Production workloads should declare here rather than calling `serve.run(...)` interactively. |

## Ray image

| Value | Type | Default | Description |
|---|---|---|---|
| `image.repository` | string | `rayproject/ray` | Container image for both head and workers. Override with a custom image when baking in model code. |
| `image.tag` | string | `2.43.0` | Ray version. **Must match the Ray + Python version used by client notebooks.** Use `*-gpu` variants for CUDA workloads. |

## Head pod

| Value | Type | Default | Description |
|---|---|---|---|
| `head.runtimeClassName` | string | — | Kubernetes runtime class (e.g. `nvidia`) for GPU-enabled head nodes. |
| `head.containerEnv` | list | `[]` | Extra environment variables for the head container. |
| `head.resources.requests.cpu` | string | `1` | CPU request. |
| `head.resources.requests.memory` | string | `2Gi` | Memory request. |
| `head.resources.limits.cpu` | string | `2` | CPU limit. |
| `head.resources.limits.memory` | string | `4Gi` | Memory limit. |
| `head.readinessProbe` | map | `{}` | Override KubeRay's default head readiness probe. `{}` keeps the default. |
| `head.livenessProbe` | map | `{}` | Override KubeRay's default head liveness probe. |

## Worker pool

| Value | Type | Default | Description |
|---|---|---|---|
| `worker.replicas` | int | `1` | Initial number of worker pods. |
| `worker.minReplicas` | int | `1` | Lower autoscaling bound. Set equal to `maxReplicas` to disable autoscaling. |
| `worker.maxReplicas` | int | `1` | Upper autoscaling bound. |
| `worker.runtimeClassName` | string | — | Kubernetes runtime class (e.g. `nvidia`) for GPU-enabled worker nodes. |
| `worker.containerEnv` | list | `[]` | Extra environment variables for the worker container. |
| `worker.resources.requests.cpu` | string | `1` | CPU request. |
| `worker.resources.requests.memory` | string | `2Gi` | Memory request. |
| `worker.resources.limits.cpu` | string | `2` | CPU limit. |
| `worker.resources.limits.memory` | string | `4Gi` | Memory limit. |
| `worker.readinessProbe` | map | _(custom — raylet-only)_ | Worker pod readiness probe. **Important: see [worker probes](#worker-probes) below.** |
| `worker.livenessProbe` | map | _(custom — raylet-only)_ | Worker pod liveness probe. |

### Worker probes

The chart ships with custom worker `readinessProbe` and `livenessProbe`
that check raylet health alone (`localhost:52365/api/local_raylet_healthz`).
KubeRay's default probes also chain a Serve HTTP check
(`wget http://localhost:8000/-/healthz | grep success`), which fails
forever on a fresh cluster with no Serve application deployed — workers
stay `0/1 Ready` indefinitely.

To revert to KubeRay's defaults, set the probe to **`null`** (YAML `~`),
not `{}`:

```yaml
worker:
  readinessProbe: ~   # falls back to KubeRay default
  livenessProbe: ~
```

Helm's deep-merge keeps the chart's keys when overlaying with `{}`, so
an empty map will not suppress the override. See
[`nebari-rayserve-pack#7`](https://github.com/nebari-dev/nebari-rayserve-pack/issues/7)
for the full diagnosis.

## Naming overrides

| Value | Type | Default | Description |
|---|---|---|---|
| `nameOverride` | string | `""` | Override the chart name in resource names. |
| `fullnameOverride` | string | `""` | Override the full release-aware resource name. Use sparingly — most resources reference each other through the auto-generated name. |

## Production: custom image with model code baked in

The recipe for building a custom Ray image and declaring applications
via `serveApplications` (rather than calling `serve.run(...)`
interactively) lives in the install guide:
[Get started → Production: custom image with model code baked in](../get-started/deploy#production-custom-image-with-model-code-baked-in).

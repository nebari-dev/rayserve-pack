---
title: Deploying on Nebari
description: The Argo CD Application, two NebariApps, and the ignoreDifferences rules KubeRay makes necessary.
---

## Two NebariApps, two audiences

The chart can render two separate `NebariApp` resources:

| | Serve endpoint | Dashboard |
|---|---|---|
| Value | `nebariapp.serve.enabled` | `nebariapp.dashboard.enabled` |
| Default | `false` | `true` |
| Hostname value | `nebariapp.hostname` | `nebariapp.dashboard.hostname` |
| Backend | `-serve-svc:8000` | `-head-svc:8265` |
| Audience | external API clients | operators and developers |

Keeping the serve endpoint internal-only is the recommended posture. Notebooks reach it
over cluster DNS, so exposing it externally is only needed for clients outside the cluster
— and an unauthenticated inference endpoint on the public internet is rarely what anyone
means to build.

:::caution[The serve `NebariApp` needs `nebariapp.hostname`]
Its template is guarded on both `serve.enabled` **and** a non-empty `hostname`. With
`serve.enabled: true` and no hostname, the resource simply is not rendered — no error, no
route. The dashboard `NebariApp` behaves differently: it uses `required`, so a missing
`dashboard.hostname` fails the render loudly.
:::

## Argo CD

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
    repoURL: https://github.com/nebari-dev/rayserve-pack.git
    targetRevision: main
    path: chart
    helm:
      releaseName: rayserve
      values: |
        nebariapp:
          enabled: true
          serve:
            enabled: false          # keep the endpoint internal
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
      backoff: { duration: 5s, factor: 2, maxDuration: 3m }
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

Pin `targetRevision` to a tag rather than `main` for anything you depend on.

## Why `ignoreDifferences` is there

The KubeRay controller mutates both `Service` and `RayService` objects at runtime — adding
selectors, rewriting autoscaler fields, writing status. Without these rules Argo CD sees
permanent drift, reports `OutOfSync` forever, and with `selfHeal: true` fights the
controller in a loop.

The two Services this chart renders also carry
`argocd.argoproj.io/compare-options: IgnoreExtraneous`, as does the RayService. That option
tells Argo CD to skip a resource during comparison when it is live in the cluster but not in
the desired state — so once KubeRay adopts and rewrites these objects they neither show as
drift nor get pruned.

:::caution[`/spec/rayClusterConfig` is a very broad ignore]
Combined with `RespectIgnoreDifferences=true` and server-side apply, it tells Argo CD to
stop managing **every field** under `rayClusterConfig` — which is the entire pod spec for
head and workers.

Most of the time that is harmless. It is not harmless if you enable
[`orgCABundle`](/ca-bundle/), because the CA initContainer, volumes, volume mounts, and
environment variables all live under that path. Argo CD reports a healthy, fully-synced
Application while the running pods never receive any of it. See
[the Argo CD interaction](/ca-bundle/#the-argo-cd-interaction).
:::

Two other sync options are doing real work:

- **`SkipDryRunOnMissingResource=true`** lets the first sync proceed before the `RayService`
  CRD exists, since the KubeRay operator that registers it is installed by the same chart.
- **`managedNamespaceMetadata`** applies `nebari.dev/managed: "true"`. Without it the
  operator ignores both `NebariApp` resources — silently.

## Authentication

```yaml
nebariapp:
  auth:
    enabled: true
    provider: keycloak
    provisionClient: true
    redirectURI: /oauth2/callback
    scopes: [openid, profile, email]
```

Auth applies to **both** `NebariApp` resources — there is no per-endpoint switch. Envoy
enforces OIDC at the gateway, so neither Ray's dashboard nor the Serve HTTP proxy sees an
unauthenticated request.

:::caution[`redirectURI` cannot be `/`]
Envoy Gateway rejects a bare `/` as an OIDC callback path. `/oauth2/callback` is the
default and there is no reason to change it — Ray serves nothing at that path.
:::

Gateway-enforced auth means the Serve endpoint, if exposed, is behind a browser login flow.
That is fine for humans and wrong for programmatic clients: an API caller cannot complete
the redirect. If you need authenticated machine access to inference from outside the
cluster, terminate that separately rather than expecting the OIDC filter to accommodate it.

## Gateway

```yaml
nebariapp:
  gateway: public   # or: internal
```

One value, applied to both resources — there is no per-endpoint override, so exposing the
serve endpoint publicly necessarily exposes the dashboard on the same gateway. Since the
dashboard shows cluster internals, logs, and job state, that pairing is usually the wrong
trade: prefer `internal` with the serve endpoint kept off the gateway entirely
(`serve.enabled: false`). Splitting them across two gateways needs two releases.

## Landing-page tile

Available on the dashboard `NebariApp` only:

```yaml
nebariapp:
  dashboard:
    landingPage:
      enabled: true
      displayName: "Ray Dashboard"
      description: "Monitor and manage Ray clusters and Serve deployments"
      category: "Data Science"
      priority: 20
      healthCheck:
        enabled: true
        path: /api/component_activities
        intervalSeconds: 30
        timeoutSeconds: 5
```

The health-check path is a real Ray dashboard API endpoint, not `/` — the dashboard's root
is a single-page app that returns 200 even when the backend is unhealthy.

## Verifying

```bash
kubectl -n rayserve get nebariapp
kubectl -n rayserve describe nebariapp rayserve-nebari-rayserve-pack-dashboard
kubectl -n rayserve get httproute,securitypolicy
kubectl get namespace rayserve -o jsonpath='{.metadata.labels}'
```

A dashboard returning 500 through the gateway usually means the `NebariApp` points at a
service that does not exist — compare `spec.service.name` against `kubectl get svc`. See
[Troubleshooting](/troubleshooting/).

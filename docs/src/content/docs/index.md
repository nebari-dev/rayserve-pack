---
title: Introduction
description: Ray Serve model serving on Kubernetes via the RayService CRD, with optional Nebari routing, TLS, and OIDC.
---

The Nebari Rayserve Pack deploys [Ray Serve](https://docs.ray.io/en/latest/serve/index.html)
on Kubernetes using the
[RayService CRD](https://docs.ray.io/en/latest/serve/production-guide/kubernetes.html) — the
recommended way to run Ray Serve in production — with optional routing, TLS, and OIDC
authentication through the
[nebari-operator](https://github.com/nebari-dev/nebari-operator).

Ray 2.43.0, KubeRay operator 1.3.0.

```
   KubeRay operator
        │ manages
        ▼
   RayService ─────► RayCluster ──► head pod   :8265 dashboard
                                    │          :8000 serve
                                    │          :10001 ray client
                                    └── worker pod(s)

   head-svc   :8265 :10001 :6379  ◄── notebooks (ray:// and HTTP)
   serve-svc  :8000               ◄── NebariApp ◄── browsers
```

## Two ways in

| From | Path | Authenticated |
|---|---|---|
| Jupyter notebook, in-cluster | straight to the Kubernetes service | no |
| Browser or external client | Envoy Gateway via `NebariApp` | yes, when auth is enabled |

Notebooks connect over `ray://` and plain HTTP to cluster DNS. That is the normal path for
model development, and it deliberately bypasses the gateway — the Ray client cannot follow
an OIDC redirect. See [Connecting from Jupyter](/jupyter/).

## What gets deployed

- **KubeRay operator**, managing the Ray cluster and Serve lifecycle.
- **A `RayService`**, with the Serve proxy pre-initialized on `0.0.0.0:8000` — no manual
  `serve start` step.
- **Two stable Kubernetes Services**, `-head-svc` and `-serve-svc`, that exist from the
  moment the chart installs. RayService creates its own stable services only after every
  Serve application is healthy, which is never on a fresh cluster with no applications.
- **`NebariApp` resources**, optionally, for the serve endpoint and the dashboard —
  separate hostnames, because they are different audiences.

## In this guide

- **[Getting started](/getting-started/)** — install standalone and reach both endpoints
- **[Deploying on Nebari](/deployment/)** — the Argo CD `Application`, and the
  `ignoreDifferences` rules KubeRay makes necessary
- **[Connecting from Jupyter](/jupyter/)** — `ray://`, version matching, and the
  NetworkPolicy
- **[Local development](/local-development/)** — the kind stack in `dev/`

## Guides

- **[Deploying models](/serve-applications/)** — declarative `serveApplications` versus
  deploying from a notebook
- **[Scaling and GPUs](/scaling/)** — replicas, resources, runtime classes, the automatic
  GPU toleration, and the probe defaults
- **[Organization CA bundle](/ca-bundle/)** — running behind a TLS-inspecting proxy, and
  the Argo CD interaction that silently defeats it
- **[Troubleshooting](/troubleshooting/)** — the failures this pack actually produces

## Reference

- **[Configuration](/configuration/)** — every value
- **[Architecture](/architecture/)** — how the pieces fit

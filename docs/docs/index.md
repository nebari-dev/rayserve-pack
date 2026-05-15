---
title: Nebari Ray Serve Pack
description: Documentation for the Nebari Ray Serve software pack — deploy on Kubernetes and serve Python models behind an HTTP endpoint.
sidebar_position: 1
---

# Nebari Ray Serve Pack

The Nebari Ray Serve pack deploys [Ray Serve](https://docs.ray.io/en/latest/serve/index.html)
on Kubernetes via the [RayService CRD](https://docs.ray.io/en/latest/serve/production-guide/kubernetes.html),
with optional routing, TLS, and OIDC authentication via the
[nebari-operator](https://github.com/nebari-dev/nebari-operator).

## Which guide do you need?

- **[Deploying Ray Serve](./deploying-ray-serve)** — installing the pack on a
  cluster (standalone or via ArgoCD on Nebari), configuring routing/TLS/auth,
  sizing the Ray cluster, and verifying the deployment. Aimed at **operators**.
- **[Using Ray Serve](./using-ray-serve)** — connecting from a Jupyter notebook,
  deploying a model with `serve.run(...)`, reading the dashboard, and
  troubleshooting common failures. Aimed at **end users** on a cluster that
  already has the pack installed.

## At a glance

| | |
|---|---|
| Default Ray version | 2.43.0 |
| Default Python version | 3.9 |
| Default access pattern | in-cluster only (recommended) |
| Optional external access | Envoy Gateway + Keycloak OIDC via NebariApp |
| Maturity | experimental |
| Source | [github.com/nebari-dev/nebari-rayserve-pack](https://github.com/nebari-dev/nebari-rayserve-pack) |

## What this pack is not

Ray Serve is a **model-serving** framework. This pack is tuned for serving
HTTP endpoints, not for general Ray Data, Ray Tune, or Ray Train workloads.
For interactive parallel compute on Nebari, use the Dask gateway from the
data-science pack instead.

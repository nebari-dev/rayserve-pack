---
sidebar_position: 1
---

# Nebari Ray Serve Pack

The Nebari Ray Serve pack deploys [Ray Serve](https://docs.ray.io/en/latest/serve/index.html)
on Kubernetes via the [RayService CRD](https://docs.ray.io/en/latest/serve/production-guide/kubernetes.html),
with optional routing, TLS, and OIDC authentication via the
[nebari-operator](https://github.com/nebari-dev/nebari-operator).

## Documentation

- **[Using Ray Serve](./using-ray-serve)** — end-user guide: connect from a notebook, deploy a model, troubleshoot.
- **[README](https://github.com/nebari-dev/nebari-rayserve-pack/blob/main/README.md)** — install, chart configuration, and ArgoCD example for operators.

## At a glance

| | |
|---|---|
| Default Ray version | 2.43.0 |
| Default Python version | 3.9 |
| Default access | in-cluster only (recommended) |
| Optional external access | Envoy Gateway + Keycloak OIDC via NebariApp |
| Source | [github.com/nebari-dev/nebari-rayserve-pack](https://github.com/nebari-dev/nebari-rayserve-pack) |

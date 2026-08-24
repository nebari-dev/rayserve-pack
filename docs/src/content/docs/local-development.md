---
title: Local development
description: The kind-based dev stack in dev/.
---

## Prerequisites

docker, kind, helm, kubectl, git.

## Two stacks

```bash
cd dev

make up             # kind + MetalLB + Envoy Gateway + cert-manager + Keycloak
                    # + nebari-operator + Ray Serve with both NebariApps
make up-standalone  # kind + Ray Serve only, no operator
make down           # delete the cluster
```

`make up` finishes by printing both URLs:

| | Default hostname |
|---|---|
| Ray Serve | `https://rayserve.nebari.local` |
| Ray dashboard | `https://ray-dashboard.nebari.local` |

Override with `make up HOSTNAME=... DASH_HOSTNAME=...`, or `CLUSTER_NAME=` for the kind
cluster (default `rayserve-dev`).

:::note[`make up` sets `nebariapp.serve.enabled=true`]
Deliberately unlike the production posture, which keeps the serve endpoint off the gateway.
The dev stack turns it on so both `NebariApp` resources actually render and get exercised —
with the chart default of `false`, the serve one is silently skipped. See
[Deploying on Nebari](/deployment/).
:::

`make up-standalone` skips the platform entirely and reuses an existing cluster if one is
there. Reach it by port-forward:

```bash
kubectl port-forward svc/rayserve-nebari-rayserve-pack-serve-svc 8000:8000
kubectl port-forward svc/rayserve-nebari-rayserve-pack-head-svc 8265:8265
```

## What `make up` does

1. Creates the kind cluster and installs MetalLB, deriving its IP pool from the `kind`
   Docker network at runtime.
2. Clones nebari-operator into `.cache/` and runs its service-install and Keycloak setup
   scripts (Envoy Gateway, cert-manager, Keycloak).
3. Installs the operator and labels the `default` namespace `nebari.dev/managed=true`.
4. `helm dependency update` then `helm upgrade --install` with both `NebariApp`s enabled.
5. Waits for `nebariapp/rayserve-nebari-rayserve-pack` and
   `nebariapp/rayserve-nebari-rayserve-pack-dashboard` to reach `Ready`.
6. Runs the operator's `update-hosts.sh` to add both hostnames to `/etc/hosts` — **this uses
   sudo**.

The `--wait --timeout 5m` on the Helm install is doing real work: the Ray image is large,
and the head has to be up before workers can join.

## Iterating on the chart

```bash
make up      # re-runs helm upgrade --install against the existing cluster
```

The cluster and platform stay in place, so the loop is a Helm upgrade rather than a
rebuild. For a faster check with no cluster at all:

```bash
helm dependency update chart   # once — templating fails without the kuberay-operator subchart
helm template rayserve chart --set nebariapp.enabled=true \
  --set nebariapp.serve.enabled=true \
  --set nebariapp.hostname=rayserve.nebari.local \
  --set nebariapp.dashboard.hostname=ray-dashboard.nebari.local | less
```

Useful for confirming that a values change renders what you expect — particularly the
[CA bundle](/ca-bundle/) injection and the
[GPU toleration](/scaling/#gpus), both of which are conditional.

## Watching it come up

```bash
kubectl get pods -w
kubectl get rayservice,raycluster
kubectl logs -l ray.io/node-type=head -f
```

The dev stack installs into `default`, not a `rayserve` namespace — that is what the
Makefile labels for the operator.

## Cleaning up

```bash
make down
```

Deletes the kind cluster. The `/etc/hosts` entries and the `.cache/nebari-operator` clone
are left behind.

## What local development cannot tell you

- **The Argo CD `ignoreDifferences` behaviour.** The dev stack uses Helm, so the interaction
  that can silently drop the [CA bundle](/ca-bundle/#the-argo-cd-interaction) never appears
  here.
- **GPU scheduling.** No GPU nodes, no taints — the toleration logic renders but is never
  exercised.
- **Real TLS.** Certificates are issued locally; a public ACME issuer and DNS validation
  behave differently.
- **Version-matched notebooks.** There is no JupyterHub in the dev stack, so the Ray client
  version coupling described in [Connecting from Jupyter](/jupyter/) goes untested.

## Docs site

```bash
cd docs
npm ci
npm run dev     # hot reload at http://localhost:4321
npm run build   # static build into docs/dist/
npm test        # unit tests
```

Pages live in `docs/src/content/docs/`; the sidebar is in `docs/astro.config.mjs`. Merges to
`main` publish to [packs.nebari.dev/rayserve-pack/](https://packs.nebari.dev/rayserve-pack/),
and pull requests touching `docs/` get a preview URL posted as a comment.

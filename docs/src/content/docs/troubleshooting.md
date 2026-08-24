---
title: Troubleshooting
description: The failures this pack actually produces, and how to tell them apart.
---

## First look

```bash
kubectl -n rayserve get rayservice,raycluster,pods,svc
kubectl -n rayserve describe rayservice rayserve-nebari-rayserve-pack
kubectl -n rayserve logs $(kubectl -n rayserve get pod -l ray.io/node-type=head -o name)
```

## Worker stuck at 0/1 Ready

The chart's probe overrides exist to prevent this, so seeing it means the overrides were
replaced or suppressed.

KubeRay's default worker probes chain a raylet check with
`wget http://localhost:8000/-/healthz`, which requires a deployed Serve application and a
local HTTP proxy. On a cluster with no applications the check never passes and the pod never
becomes ready ([issue #7](https://github.com/nebari-dev/rayserve-pack/issues/7)).

```bash
kubectl -n rayserve get pod -l ray.io/node-type=worker -o jsonpath='{.items[0].spec.containers[0].readinessProbe}' | jq
```

It should be the raylet-only check on port `52365`. If it mentions `:8000`, KubeRay's
default is in force — most likely because someone set `readinessProbe: {}` expecting that to
suppress the chart's. It does not; Helm's deep merge keeps existing keys. Use `null` (`~`).
See [Scaling and GPUs](/scaling/#probes).

## Ray dashboard returns 500 through the gateway

The `NebariApp` is pointing at a service that does not exist.

```bash
kubectl -n rayserve get svc
kubectl -n rayserve get nebariapp rayserve-nebari-rayserve-pack-dashboard -o jsonpath='{.spec.service}'
```

The stable services are `<release>-nebari-rayserve-pack-head-svc` and
`<release>-nebari-rayserve-pack-serve-svc`. A `nameOverride`, `fullnameOverride`, or an explicit
`nebariapp.service.name` can put these out of step.

## The serve NebariApp was never created

Its template requires **both** `nebariapp.serve.enabled` (not `false`) and a non-empty
`nebariapp.hostname`. With the hostname missing, the resource is silently not rendered.

```bash
kubectl -n rayserve get nebariapp
helm -n rayserve get values rayserve | grep -A5 nebariapp
```

The dashboard `NebariApp` behaves differently — it uses `required`, so a missing
`dashboard.hostname` fails the Helm render with a message rather than doing nothing.

## NebariApp never reaches Ready

Check the namespace label first:

```bash
kubectl get namespace rayserve --show-labels | grep nebari.dev/managed
```

Missing means the operator is ignoring the resource entirely, with no event to say so:

```bash
kubectl label namespace rayserve nebari.dev/managed=true
```

Under Argo CD, `managedNamespaceMetadata` does this — see
[Deploying on Nebari](/deployment/).

## Version mismatch connecting from Jupyter

`ray.init()` fails, usually with a protocol-version message.

```bash
POD=$(kubectl get pod -n rayserve -l ray.io/node-type=head -o name)
kubectl exec -n rayserve $POD -- ray --version
kubectl exec -n rayserve $POD -- python --version
```

Match both in the notebook environment. See
[Connecting from Jupyter](/jupyter/#versions-must-match).

## JupyterHub notebooks cannot reach Ray

Connections hang rather than erroring. JupyterHub's default singleuser NetworkPolicy blocks
egress to private IPs:

```yaml
jupyterhub:
  singleuser:
    networkPolicy:
      egressAllowRules:
        privateIPs: true
```

Users must restart their server afterwards.

## Serve application will not deploy

```bash
kubectl -n rayserve get rayservice rayserve-nebari-rayserve-pack -o jsonpath='{.status}' | jq
```

`DEPLOY_FAILED` is nearly always an import error — the module named in `import_path` is not
in the image, or one of its dependencies is missing. The traceback is in the head pod's
logs:

```bash
kubectl -n rayserve logs $(kubectl -n rayserve get pod -l ray.io/node-type=head -o name) | grep -i -A20 "deploy"
```

Confirm the module actually imports inside the image:

```bash
kubectl -n rayserve exec $(kubectl -n rayserve get pod -l ray.io/node-type=head -o name) \
  -- python -c "import myapp.model; print(myapp.model.app)"
```

## CERTIFICATE_VERIFY_FAILED on outbound HTTPS

A TLS-inspecting proxy. Enable [`orgCABundle`](/ca-bundle/) — and if the cluster is managed
by Argo CD with the example sync policy, read
[the Argo CD interaction](/ca-bundle/#the-argo-cd-interaction) first: the injection can be
silently dropped while everything reports healthy.

```bash
kubectl -n rayserve exec $(kubectl -n rayserve get pod -l ray.io/node-type=head -o name) \
  -- printenv SSL_CERT_FILE
```

If that prints the path and httpx calls still fail, it is the
[httpx gap](/ca-bundle/#known-gap-httpx).

## Argo CD permanently OutOfSync

The KubeRay controller mutates `Service` and `RayService` at runtime. Without the
`ignoreDifferences` rules — and with `selfHeal: true` — Argo CD fights the controller in a
loop. The full rule set is in [Deploying on Nebari](/deployment/).

## Pods Pending

```bash
kubectl -n rayserve describe pod <pod> | tail -20
```

`Insufficient cpu`/`memory` means the requests exceed what nodes can offer — the defaults
ask for 1 CPU and 2Gi per pod. For a GPU worker, check whether the node is tainted and
whether the toleration was injected:

```bash
kubectl -n rayserve get pod <pod> -o jsonpath='{.spec.tolerations}' | jq
```

The chart injects an `nvidia.com/gpu` toleration only when `resources` mention
`nvidia.com/gpu`. See [Scaling and GPUs](/scaling/#gpus).

## Head pod OOMKilled

The head runs the GCS, dashboard, Serve controller, and an HTTP proxy. Coordination load
grows with worker count and deployment count, and a dead head takes the cluster with it.
Raise `head.resources.limits.memory`.

## Gathering state for an issue

```bash
kubectl -n rayserve get all
kubectl -n rayserve describe rayservice rayserve-nebari-rayserve-pack
kubectl -n rayserve get rayservice -o yaml
kubectl -n rayserve logs $(kubectl -n rayserve get pod -l ray.io/node-type=head -o name) --tail=200
kubectl -n rayserve get events --sort-by=.lastTimestamp | tail -30
helm -n rayserve get values rayserve
```

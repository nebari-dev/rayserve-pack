---
title: Scaling and GPUs
description: Replicas, resources, runtime classes, the automatic GPU toleration, and the probe defaults.
---

## Defaults

```yaml
head:
  resources:
    requests: { cpu: "1", memory: "2Gi" }
    limits:   { cpu: "2", memory: "4Gi" }

worker:
  replicas: 1
  minReplicas: 1
  maxReplicas: 1
  resources:
    requests: { cpu: "1", memory: "2Gi" }
    limits:   { cpu: "2", memory: "4Gi" }
```

Sized to fit a kind cluster. One worker, no autoscaling headroom, no GPU.

## Adding workers

```yaml
worker:
  replicas: 3
  minReplicas: 3
  maxReplicas: 3
  resources:
    requests: { cpu: "4", memory: "16Gi" }
    limits:   { cpu: "8", memory: "32Gi" }
```

:::caution[Set all three, every time]
`values.yaml` pins `minReplicas` and `maxReplicas` to `1`. They do **not** follow `replicas`
— the chart's `default` only applies to a value that is absent, and these never are. Raise
`replicas` to `3` on its own and you still get one worker, because KubeRay clamps desired
replicas into the `[minReplicas, maxReplicas]` range.
:::

By default there is no autoscaler behind these bounds: the group size is exactly `replicas`,
and growing the pool means changing `replicas` and running `helm upgrade`. `minReplicas` and
`maxReplicas` only become a range something moves within under
[Ray autoscaling](#ray-autoscaling).

:::caution[Changing the worker count does not reach a running cluster]
A `helm upgrade` that changes only `replicas`, `minReplicas`, or `maxReplicas` updates the
RayService and stops there. The RayService controller leaves those three fields out of the
spec hash it uses to detect drift, so the running RayCluster keeps its old numbers — no event,
no rollout, no error. The change lands only when some other `rayClusterConfig` field changes in
the same upgrade, and then as a full cluster roll. To add workers to a running cluster, patch
the RayCluster directly and put the same numbers in your values file so the next rollout
carries them:

```bash
kubectl -n rayserve patch raycluster <name> --type json -p '[
  {"op":"replace","path":"/spec/workerGroupSpecs/0/replicas","value":6},
  {"op":"replace","path":"/spec/workerGroupSpecs/0/minReplicas","value":6},
  {"op":"replace","path":"/spec/workerGroupSpecs/0/maxReplicas","value":6}]'
```

KubeRay adds the pods in place. See
[why a range change does not reach the cluster](#why-a-range-change-does-not-reach-the-cluster);
a chart-side fix is tracked in [#41](https://github.com/nebari-dev/rayserve-pack/issues/41).
:::

Whether the new pods actually land is a separate question. On a cluster with a node
autoscaler, asking for more than current nodes can hold triggers node scale-up; without one,
the extra pods stay `Pending`.

## Ray autoscaling

```yaml
autoscaling:
  enabled: true

worker:
  minReplicas: 1
  maxReplicas: 6
  resources:
    requests: { cpu: "4", memory: "16Gi" }
    limits:   { cpu: "4", memory: "16Gi" }

serveApplications:
  - name: my-model
    import_path: myapp.model:app
    deployments:
      - name: MyModel
        ray_actor_options: { num_cpus: 4 }
        autoscaling_config:
          min_replicas: 1
          max_replicas: 6
          target_ongoing_requests: 2
```

Three layers, each reacting to the one above it:

1. **Serve deployment autoscaling** (`autoscaling_config`) adds model replicas as request load
   rises. Each replica needs the resources declared in `ray_actor_options`.
2. **The Ray autoscaler**, which `autoscaling.enabled` turns on, adds worker pods when those
   replicas have nowhere to run, within `[worker.minReplicas, worker.maxReplicas]`, and removes
   pods that have been idle for `autoscaling.idleTimeoutSeconds`.
3. **Your node autoscaler** adds nodes when the pods cannot be scheduled.

The Ray autoscaler reacts to any unschedulable demand, so on a cluster that notebooks connect
to over Ray client, users' tasks and actors are the first layer as much as Serve is. For a
Serve-only cluster, a fixed `num_replicas` never generates demand and the autoscaler has
nothing to do; and without the second layer, `autoscaling_config` can only scale within the
resources the cluster already has.

:::caution[Raise `maxReplicas`]
Both bounds default to `1`. `autoscaling.enabled: true` alone leaves the group pinned at one
worker and only adds the autoscaler sidecar to the head pod — `500m` CPU / `512Mi` memory,
requests and limits, unless `autoscaling.resources` overrides it.
:::

### Tune Serve, set the cluster range once

The two layers differ in how a change reaches a running service:

- **Serve config** — `serveApplications`, including `autoscaling_config` — is applied in
  place. The RayService controller resubmits it to the live cluster and replicas adjust in
  seconds.
- **Cluster config** — everything under `rayClusterConfig`, which includes `autoscaling.*` —
  is replaced, not edited. Any change rolls a new RayCluster: a second head and worker set
  start, Serve comes up on them, traffic switches, the old cluster is deleted. Zero downtime,
  but a full model reload. The worker range is the exception: on its own it changes nothing
  until something else rolls the cluster.

So treat `worker.minReplicas` / `worker.maxReplicas` as a capacity budget — the most workers
you will pay for, the fewest you want warm — set at install and rarely revisited. Put the
behaviour you expect to tune in `autoscaling_config`: `min_replicas` / `max_replicas`,
`target_ongoing_requests`, `upscale_delay_s` / `downscale_delay_s`.

If you need a new ceiling on a live service, patch the RayCluster directly. The controller
leaves the range fields to the autoscaler and will not revert it; put the same value in your
values file so the next rollout carries it:

```bash
kubectl -n rayserve patch raycluster <name> --type json \
  -p '[{"op":"replace","path":"/spec/workerGroupSpecs/0/maxReplicas","value":8}]'
```

### Why a range change does not reach the cluster

The RayService controller excludes `replicas`, `minReplicas`, and `maxReplicas` from the spec
hash it uses to detect drift, because the autoscaler writes `replicas` itself. So a
`helm upgrade` changing only those fields — the autoscaling range, or the static worker
count — never reaches the running cluster. Upstream considers this intended
([kuberay #2331](https://github.com/ray-project/kuberay/issues/2331)); a fix that propagated
the range in place was declined
([kuberay #2333](https://github.com/ray-project/kuberay/pull/2333)), with the guidance being to
edit the RayCluster directly, as above. A chart hook that applies the values to the live
RayCluster automatically is proposed in
[#41](https://github.com/nebari-dev/rayserve-pack/issues/41).

### Idle timeout and upscaling mode

`idleTimeoutSeconds: 60` is Ray's general-purpose default. A new worker pays an image pull and
a model load, so for inference a longer hold — 300 to 600 seconds — usually beats reclaiming a
pod that will be wanted again two minutes later.

`upscalingMode: Default` is right for Serve. `Conservative` caps pending worker pods at the
number already connected, which only helps when node provisioning is slow and a burst of
`Pending` pods causes trouble. `Aggressive` is an alias for `Default`.

### With Argo CD

`enableInTreeAutoscaling` renders under `spec.rayClusterConfig` — the path the documented
Application ignores under `RespectIgnoreDifferences=true`. Enabling autoscaling on an
already-synced cluster is silently not applied unless that ignore rule is narrowed. Same issue
as [`orgCABundle`](/ca-bundle/).

## GPUs

Four things have to line up — and the fourth is the one people miss.

**1. Request the GPU resource:**

```yaml
worker:
  resources:
    limits:
      nvidia.com/gpu: 1
      cpu: "8"
      memory: "32Gi"
    requests:
      cpu: "4"
      memory: "16Gi"
```

**2. Set the runtime class, if your cluster uses one:**

```yaml
worker:
  runtimeClassName: nvidia
```

**3. Tolerate the taint — which the chart does for you.** When either `limits` or `requests`
mentions `nvidia.com/gpu`, the chart injects:

```yaml
tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
```

so pods schedule onto nodes tainted `nvidia.com/gpu=...:NoSchedule` — the pattern
[nebari-infrastructure-core](https://github.com/nebari-dev/nebari-infrastructure-core) uses
for AWS GPU node groups. `operator: Exists` matches any taint value.

The injection is skipped if you already define a toleration with key `nvidia.com/gpu`, so
your own is treated as a deliberate override. Any other tolerations you list are appended:

```yaml
worker:
  tolerations:
    - key: dedicated
      operator: Equal
      value: ml
      effect: NoSchedule
```

Both `head` and `worker` support this. A GPU head is unusual — the head coordinates rather
than computes — but it is available.

**4. Claim the GPU in the deployment.** Kubernetes allocating a GPU to the pod is not the
same as Ray scheduling your replica onto it:

```yaml
serveApplications:
  - name: my-model
    import_path: myapp.model:app
    deployments:
      - name: MyModel
        ray_actor_options:
          num_gpus: 1
```

Skip this and the deployment runs on CPU inside a pod holding an idle GPU.

Verify end to end:

```bash
kubectl -n rayserve exec $(kubectl -n rayserve get pod -l ray.io/node-type=worker -o name) -- nvidia-smi
kubectl -n rayserve exec $(kubectl -n rayserve get pod -l ray.io/node-type=head -o name) -- ray status
```

`ray status` should show `GPU` in the cluster resources. If `nvidia-smi` works but Ray
reports no GPU, the device plugin exposed it to the pod after Ray started — restart the
worker.

## Probes

The chart overrides KubeRay's default worker probes, and the reason is worth knowing.

KubeRay's defaults chain a raylet health check with
`wget http://localhost:8000/-/healthz | grep success`. That second check needs both a
deployed Serve application **and** a local Serve HTTP proxy. On a fresh cluster there are
no applications — `serveApplications` is empty by default — so the check fails and the
worker pod sits at `0/1 Ready` forever
([issue #7](https://github.com/nebari-dev/rayserve-pack/issues/7)).

The chart's defaults check the raylet alone:

```yaml
worker:
  readinessProbe:
    exec:
      command: [bash, -c, "wget -T 2 -q -O- http://localhost:52365/api/local_raylet_healthz | grep success"]
    initialDelaySeconds: 10
    periodSeconds: 5
    timeoutSeconds: 2
    failureThreshold: 1
  livenessProbe:
    # same command; initialDelaySeconds 30, failureThreshold 120
```

A Ray node is ready when its raylet is healthy. Serve application health is the Serve
controller's business, and since the chart's `serve-svc` targets only the head pod, worker
readiness has no effect on user-visible HTTP routing anyway.

The liveness probe's `failureThreshold: 120` at `periodSeconds: 5` gives a worker ten
minutes of unhealthy raylet before restart — deliberately tolerant, because a worker busy
with a long task should not be killed for a slow health response.

:::caution[`{}` does not suppress a probe — use `null`]
Helm's deep merge keeps existing keys when overlaying with an empty map, so
`readinessProbe: {}` leaves the chart's probe in place. To fall back to KubeRay's defaults,
set it to `null` (`~` in YAML):

```yaml
worker:
  readinessProbe: ~
  livenessProbe: ~
```
:::

`head.readinessProbe` and `head.livenessProbe` default to `{}`, which means the head keeps
KubeRay's built-in probes. Override them the same way if you need explicit control.

## Environment variables

```yaml
head:
  containerEnv:
    - name: RAY_DEDUP_LOGS
      value: "0"
worker:
  containerEnv:
    - name: HF_HOME
      value: /tmp/hf
```

These are concatenated with the CA bundle variables when
[`orgCABundle`](/ca-bundle/) is enabled, so both coexist.

## Sizing the head

The head runs the GCS, the dashboard, the Serve controller, and — with the default
`proxyLocation: EveryNode` — an HTTP proxy. It does not run your model replicas unless you
place them there.

Scale it for coordination load: more workers and more deployments mean more GCS traffic. A
head that starts OOM-killing takes the whole cluster with it, so it is worth headroom.

## What is not here

- **Per-deployment autoscaling** — Ray Serve's own `autoscaling_config` goes in a
  `serveApplications` deployment entry, not in chart values. [Ray autoscaling](#ray-autoscaling)
  covers how it pairs with the cluster autoscaler.
- **Multiple worker groups** — the chart renders one `workerGroupSpecs` entry. Heterogeneous
  pools (CPU plus GPU) need a chart change or a second release.
- **Node autoscaling** — that is your cluster autoscaler's job.

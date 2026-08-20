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

`minReplicas` and `maxReplicas` both default to `replicas` when unset. Setting them equal
pins the group; setting `maxReplicas` higher lets the Ray autoscaler grow it in response to
pending tasks.

The Ray autoscaler works within these bounds and asks Kubernetes for pods — it cannot add
nodes. On a cluster with a node autoscaler, a `maxReplicas` above what current nodes can
hold triggers node scale-up; without one, the extra pods stay `Pending`.

## GPUs

Three things have to line up.

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
([issue #7](https://github.com/nebari-dev/nebari-rayserve-pack/issues/7)).

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
  `serveApplications` deployment entry, not in the chart's values.
- **Multiple worker groups** — the chart renders one `workerGroupSpecs` entry. Heterogeneous
  pools (CPU plus GPU) need a chart change or a second release.
- **Node autoscaling** — that is your cluster autoscaler's job.

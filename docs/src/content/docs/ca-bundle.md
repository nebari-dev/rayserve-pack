---
title: Organization CA bundle
description: Running Ray behind a TLS-inspecting proxy, and the Argo CD interaction that silently defeats it.
---

Behind a TLS-inspecting proxy — Netskope, Zscaler, BlueCoat, an internal corporate CA — every
outbound HTTPS call from a Ray pod fails certificate verification. Model registries, dataset
URLs, the Hugging Face hub, S3: all `CERTIFICATE_VERIFY_FAILED`, because the proxy re-signs
certificates with a root the container's trust store has never heard of.

Point the chart at a ConfigMap holding your organization's root CA and it fixes this for the
head and worker pods.

## Enabling

Create the ConfigMap out of band — through your GitOps layer, `kubectl`, or trust-manager:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: org-ca-bundle
  namespace: rayserve
data:
  ca.crt: |
    -----BEGIN CERTIFICATE-----
    ...your org CA...
    -----END CERTIFICATE-----
```

Then:

```yaml
orgCABundle:
  configMapName: org-ca-bundle
```

The key must be `ca.crt`, and the ConfigMap must be in the release namespace.

When `configMapName` is empty — the default — nothing is rendered and the resulting
RayService is byte-identical to the no-injection case.

## What it does

For both head and worker pods, the chart adds:

1. **An initContainer** (`build-ca-bundle`, `alpine:3.20` by default) that concatenates the
   base image's system trust store with your CA:
   ```sh
   cat /etc/ssl/certs/ca-certificates.crt /var/local/org-ca/ca.crt > /shared/combined-ca.crt
   ```
2. **A shared `emptyDir`** the main container mounts read-only at `/shared`. The Ray
   container never sees the raw ConfigMap.
3. **Four environment variables** on the main container, all pointing at
   `/shared/combined-ca.crt`.

Concatenating matters. Replacing the system trust store rather than extending it would
break TLS to everything the proxy does not re-sign.

## The four environment variables

| Variable | Honored by |
|---|---|
| `SSL_CERT_FILE` | OpenSSL, Python `ssl`, most tooling |
| `REQUESTS_CA_BUNDLE` | `requests`, `urllib3` |
| `CURL_CA_BUNDLE` | curl |
| `GIT_SSL_CAINFO` | git |

`GIT_SSL_CAINFO` is separate because git's libcurl ignores the other three and reads only
that one. Without it, `pip install git+https://...` and any other git-over-HTTPS call in a
worker fails verification even though plain `requests` and `pip` succeed — a confusing
partial failure.

## The Argo CD interaction

:::caution[The CA bundle can silently not apply under Argo CD]
The example `Application` in [Deploying on Nebari](/deployment/) sets
`RespectIgnoreDifferences=true` together with an `ignoreDifferences` rule on
`/spec/rayClusterConfig`. With server-side apply, that combination tells Argo CD to stop
managing **every field** under `rayClusterConfig` — which is exactly where this chart injects
the initContainer, volumes, volume mounts, and CA environment variables.

The result: Argo CD reports a healthy, fully-synced Application, and the running pods never
receive the CA bundle. TLS calls keep failing with `CERTIFICATE_VERIFY_FAILED` while every
dashboard says green.

See [issue #17](https://github.com/nebari-dev/rayserve-pack/issues/17).
:::

The broad ignore exists only to suppress the autoscaler and runtime mutations KubeRay makes
to `rayClusterConfig`. To use `orgCABundle` under Argo CD, narrow it: replace
`/spec/rayClusterConfig` with targeted JSON pointers at the specific subpaths KubeRay
rewrites, or drop the rule and add narrower ones as drift appears.

Then verify against the running pod rather than the sync status:

```bash
kubectl -n rayserve exec $(kubectl -n rayserve get pod -l ray.io/node-type=head -o name) \
  -- printenv SSL_CERT_FILE
# /shared/combined-ca.crt
```

Empty output means the injection did not reach the pod, whatever Argo CD reports.

## Verifying

```bash
POD=$(kubectl -n rayserve get pod -l ray.io/node-type=worker -o name)

kubectl -n rayserve exec $POD -- printenv SSL_CERT_FILE REQUESTS_CA_BUNDLE CURL_CA_BUNDLE GIT_SSL_CAINFO
kubectl -n rayserve exec $POD -- ls -l /shared/combined-ca.crt
kubectl -n rayserve exec $POD -- python -c "import requests; print(requests.get('https://huggingface.co').status_code)"
```

A `200` from the last command against a host that traverses the proxy is the real test.

If the initContainer failed, the pod never starts and the reason is in its logs:

```bash
kubectl -n rayserve logs $POD -c build-ca-bundle
```

The usual causes are a missing ConfigMap or a key that is not `ca.crt`.

## Why a ConfigMap and not a Secret

A CA certificate is public material by design — the entire PKI trust model depends on root
CAs being widely distributed. Mozilla's bundle ships in every browser and OS, and corporate
inspecting-proxy roots are pushed to every device that traverses them.

Kubernetes itself distributes the cluster's own CA through a ConfigMap
(`kube-root-ca.crt`, auto-projected into every namespace), and cert-manager's
[trust-manager](https://cert-manager.io/docs/trust/trust-manager/) distributes CA bundles as
ConfigMaps via its `Bundle` CR. This chart follows that precedent.

Reserve Secrets for things that actually need confidentiality — private keys, OAuth client
secrets.

## Known gap: httpx

:::caution[httpx ignores `SSL_CERT_FILE`]
httpx clients built with the default `verify=True` hardcode `cafile=certifi.where()`, so
they never see the injected bundle. Application code making httpx calls through the proxy
must construct the context explicitly:

```python
import ssl, httpx

client = httpx.Client(verify=ssl.create_default_context())
# or per-call:
httpx.get(url, verify=ssl.create_default_context())
```

`ssl.create_default_context()` with no `cafile=` honors `SSL_CERT_FILE` and `SSL_CERT_DIR`
per the standard OpenSSL convention, so it picks up the bundle.
:::

`requests`, `urllib3`, stdlib `urllib`, curl, git, and most non-Python TLS tooling honor the
environment variables automatically. httpx is the notable exception, and it is increasingly
common in modern Python libraries — worth grepping your dependencies for.

## The initContainer image

```yaml
orgCABundle:
  initImage: "alpine:3.20"
```

It needs only `sh` and `cat`. Override it if your organization requires images from a
vetted registry — and note that in an air-gapped environment, an unreachable
`alpine:3.20` blocks pod startup entirely rather than just skipping the injection.

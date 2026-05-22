---
title: How-to guides
description: Task-oriented guides for end users — connect from a notebook, deploy a model, expose it externally, troubleshoot common failures.
sidebar_position: 2
---

# How-to guides

This section is for **end users** on a cluster that already has the pack
installed. If you're trying to install the pack itself, see
[Get started](../get-started/) instead.

The how-tos assume:

- You have a Jupyter notebook on the same Nebari cluster (e.g. via the
  [nebari-data-science-pack](https://github.com/nebari-dev/nebari-data-science-pack)).
- Your operator has confirmed the Ray cluster is `Running` and given you
  the namespace name (typically `rayserve`).
- Your notebook environment has matching Ray and Python versions
  (see [Step 1](./use_ray_from_notebook#step-1--prepare-your-notebook-environment) of the
  Use guide).

## What's in this section

- **[Use Ray Serve from a notebook](./use_ray_from_notebook)** — the main end-user
  walkthrough: prepare the notebook environment, connect via the
  in-cluster `ray://` URL, deploy a model with `serve.run(...)`, read the
  dashboard, and (optionally) expose the model externally.
- **[Troubleshoot](./troubleshoot)** — the consolidated troubleshooting
  index covering version-mismatch errors, network-policy blocks,
  crashlooping replicas, and NebariApp issues, with links to the deeper
  per-section troubleshooting blocks in the Use and Deploy guides.

---
title: Overview
---

This project provides a small [HAMi](https://project-hami.io/) installation example for a Vultr Kubernetes Engine (VKE) cluster with one NVIDIA GPU worker. Atmos runs Terraform for VKE and Helmfile for HAMi. The optional `hami-demo` Helmfile installs one idle CUDA Pod requesting a 1024 MiB GPU memory slice; no model service is needed to inspect the allocation.

## Components

| Component | Purpose |
| --- | --- |
| `environment/components/terraform/vke` | One VKE cluster and labeled NVIDIA GPU node pool |
| `environment/components/helmfile/hami` | Official HAMi chart, no workloads or driver install |
| `environment/components/helmfile/hami-demo` | Optional small GPU Pod; separate from HAMi installation |
| `demo/` | Existing independent workload bundle for an already configured cluster |

## Start

Select a GPU plan available in your Vultr region and a supported VKE version, then follow the [deployment guide](deployment.md) for credential handling, node preparation, plan/apply, runtime checks, and teardown. The node needs a working NVIDIA driver and container toolkit **before** HAMi is applied.

Terraform state contains the cluster kubeconfig. Local state and kubeconfigs are gitignored; no shared remote backend is configured.

# HAMi GPU Demo

Run HAMi on a Vultr Kubernetes Engine (VKE) cluster with one NVIDIA GPU worker. [Atmos](https://atmos.tools/) selects a Terraform cluster component and two separate Helmfile components: `hami` installs HAMi; `hami-demo` runs one optional 1024 MiB GPU Pod. No model download or GPU Operator is part of the Vultr path.

## Layout

| Path | Purpose |
| --- | --- |
| `environment/` | Atmos stack `vultr-gpu`, Terraform VKE component, HAMi-only and demo Helmfiles |
| `demo/` | Existing independent demo charts, scripts, and workloads for an already configured cluster |
| `docs/` | Project documentation and operator runbook |

## Start here

Provisioning a VKE GPU worker costs money. Before applying, find an **NVIDIA** plan available in your region and a current VKE version with `vultr-cli regions availability ewr` and `vultr-cli kubernetes versions`. Confirm the node image provides an NVIDIA driver and container runtime/toolkit compatible with [HAMi's NVIDIA prerequisites](https://project-hami.io/docs/installation/prerequisites#preparing-your-gpu-nodes). HAMi does not install them.

From a trusted local shell, supply `VULTR_API_KEY` to Terraform without adding it to any repository file. Supply the discovered plan and version as `VULTR_GPU_PLAN` and `VULTR_K8S_VERSION`. Then:

```bash
cd environment
umask 077
atmos terraform plan vke -s vultr-gpu
atmos terraform apply vke -s vultr-gpu
mkdir -p kubeconfigs
atmos terraform output vke -s vultr-gpu -raw kube_config > kubeconfigs/vultr-gpu.yaml
export KUBECONFIG="$PWD/kubeconfigs/vultr-gpu.yaml"
kubectl get nodes -l gpu=on
atmos helmfile apply hami -s vultr-gpu
# After checking HAMi and GPU capacity, optionally run the tiny allocation example:
atmos helmfile apply hami-demo -s vultr-gpu
kubectl exec hami-demo-gpu -- nvidia-smi
```

**Stop before the HAMi apply** unless the labeled node's driver and NVIDIA container runtime are working and no other device plugin owns `nvidia.com/gpu` on that node. `nvidia.com/gpu` capacity may appear only *after* HAMi's device plugin starts. Check `kubectl get pods -n kube-system`, GPU node capacity, and the demo Pod's scheduler/limits before treating its `nvidia-smi` output as proof of a 1024 MiB allocation.

See [the full deployment procedure](docs/deployment.md) for prerequisites, safe kubeconfig handling, diagnostics, and reverse-order teardown. The single-operator Terraform state contains sensitive kubeconfig material: it is ignored locally, not a shared team backend. No cloud apply is performed by this repository.

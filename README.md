# HAMi GPU Demo

Run HAMi on a Vultr Kubernetes Engine (VKE) cluster with one NVIDIA GPU worker. [Atmos](https://atmos.tools/) selects a Terraform cluster component and two separate Helmfile components: `hami` installs HAMi; `hami-demo` runs one optional 1024 MiB GPU Pod. No model download or GPU Operator is part of the Vultr path.

## Layout

| Path | Purpose |
| --- | --- |
| `environment/` | Atmos stack `vultr-gpu`, Terraform VKE component, HAMi-only and demo Helmfiles |
| `demo/` | Existing independent demo charts, scripts, and workloads for an already configured cluster |
| `docs/` | Project documentation and operator runbook |

## Start here

Pick an **NVIDIA** plan and VKE version with `vultr-cli regions availability "$VULTR_REGION"` and `vultr-cli kubernetes versions`. The node image must already have an NVIDIA driver and container runtime/toolkit matching [HAMi's NVIDIA prerequisites](https://project-hami.io/docs/installation/prerequisites#preparing-your-gpu-nodes). HAMi does not install them.

Export `VULTR_API_KEY`, `VULTR_REGION`, `VULTR_GPU_PLAN`, and `VULTR_K8S_VERSION`. Then:

```bash
cd environment
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

**Stop before the HAMi apply** unless the labeled node's driver and NVIDIA container runtime work and no other device plugin owns `nvidia.com/gpu` on that node. Check `kubectl get pods -n kube-system` and GPU node capacity. The demo Pod's `nvidia-smi` output is not proof of a 1024 MiB allocation unless it shows 1024 MiB total.

See [the full deployment procedure](docs/deployment.md). Terraform state holds the cluster kubeconfig; it is gitignored and local to one operator, not a shared backend.

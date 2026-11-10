---
title: Deployment
---

This repo provisions **one Vultr VKE cluster** with Atmos. The default Helmfile component installs only HAMi; an optional second installs one idle CUDA Pod to inspect a 1024 MiB HAMi allocation. The larger workloads in `demo/` are not deployed here.

## Prerequisites

- A Vultr account with permission and quota for a **VKE NVIDIA GPU** worker.
- `atmos`, Terraform 1.6+, Helm, Helmfile, `kubectl`, and `vultr-cli` installed. Configure the CLI in your own shell. The Vultr Terraform provider takes `VULTR_API_KEY` from the environment, not from an Atmos stack.
- A GPU worker image with an NVIDIA driver and [NVIDIA Container Toolkit/runtime configured for HAMi](https://project-hami.io/docs/installation/prerequisites#preparing-your-gpu-nodes). This configuration does **not** install a driver or GPU Operator. Only use an NVIDIA GPU plan; the demo does not support AMD GPUs.
- A private single-operator Terraform state directory. Terraform state includes the cluster kubeconfig. For team use, configure a protected remote backend before provisioning; do not reuse someone else's state key or import an existing cluster without its owner.

## Provision VKE

Choose the plan actually returned for the region and a currently supported VKE version. An unset env var resolves to an empty Atmos variable and is rejected by Terraform validation at plan.

```bash
cd environment
read -r -p 'Vultr region: ' VULTR_REGION
vultr-cli regions availability "$VULTR_REGION"
vultr-cli kubernetes versions
read -r -p "NVIDIA VKE plan available in $VULTR_REGION: " VULTR_GPU_PLAN
read -r -p 'Supported VKE version: ' VULTR_K8S_VERSION
export VULTR_REGION VULTR_GPU_PLAN VULTR_K8S_VERSION
read -r -s -p 'Vultr API key: ' VULTR_API_KEY
printf '\n'
export VULTR_API_KEY
atmos terraform plan vke -s vultr-gpu
# Review the plan, GPU SKU, region, cost and state owner before continuing.
atmos terraform apply vke -s vultr-gpu
unset VULTR_API_KEY
```

Terraform state and its backups contain the kubeconfig. Keep the state directory private. No key goes into `stacks/vultr-gpu.yaml`, a Helmfile variable, or a committed file. The provisioned pool has one worker labeled `gpu=on`. GPU inventory moves; if the plan or version disappears between the listing and the apply, pick a supported one rather than reusing the old value.

This path is gitignored:

```bash
mkdir -p kubeconfigs
atmos terraform output vke -s vultr-gpu -raw kube_config > kubeconfigs/vultr-gpu.yaml
export KUBECONFIG="$PWD/kubeconfigs/vultr-gpu.yaml"
kubectl config current-context
kubectl get nodes -l gpu=on
```

If `kubectl` cannot reach the intended VKE cluster, stop. Never run Helmfile against an implicit `~/.kube/config` context.

## Check the GPU node

Do not install HAMi over a broken GPU runtime. On the GPU worker, confirm `nvidia-smi` and the NVIDIA Container Toolkit work, and that Kubernetes uses the NVIDIA runtime by default for HAMi's `envvar` strategy. If you have permission to create a **privileged node debug Pod**, the first two checks can be made from your terminal:

```bash
NODE=$(kubectl get nodes -l gpu=on -o jsonpath='{.items[0].metadata.name}')
kubectl debug "node/$NODE" -it --profile=sysadmin --image=ubuntu:22.04 -- chroot /host sh -c 'nvidia-smi && nvidia-ctk --version'
```

The debug command creates a privileged Pod; delete the named debug Pod after inspection. If node debugging is denied, use your provider-approved host access instead. `nvidia-ctk --version` proves Toolkit is present, **not** that it is configured as the default runtime; verify the actual containerd setup against [HAMi's NVIDIA node preparation](https://project-hami.io/docs/installation/prerequisites#preparing-your-gpu-nodes). If any prerequisite is missing, fix the node and stop here. `nvidia.com/gpu` may be absent from node capacity at this stage because HAMi's device plugin has not started.

Before installing HAMi, check for a separately installed NVIDIA Device Plugin on the same nodes:

```bash
kubectl get daemonsets -A
```

If another plugin already registers `nvidia.com/gpu`, use its provider-supported disable procedure first; do not let it race HAMi's device plugin or delete a managed add-on blindly. This is separate from driver and Toolkit readiness.

## Install HAMi, then optionally test one Pod

The two Helmfile components are independent. `hami` has only the official HAMi 2.10.0 chart; `hami-demo` has only a small CUDA Pod.

```bash
atmos helmfile apply hami -s vultr-gpu
kubectl get pods -n kube-system
kubectl get nodes -l gpu=on -o 'custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
```

Wait for the `hami-scheduler` and `hami-device-plugin` Pods to become Ready. The labeled worker must report a nonzero `nvidia.com/gpu` allocation **after** the device plugin starts. If either Pod is unhealthy, inspect `kubectl describe pod -n kube-system` and its events rather than proceeding.

To inspect one HAMi GPU memory slice without downloading a model:

```bash
atmos helmfile apply hami-demo -s vultr-gpu
kubectl wait --for=condition=Ready pod/hami-demo-gpu --timeout=180s
kubectl get pod hami-demo-gpu -o jsonpath='{.spec.schedulerName}{"\n"}{.spec.containers[0].resources.limits}{"\n"}'
kubectl exec hami-demo-gpu -- nvidia-smi
```

The Pod must use `hami-scheduler`, request `nvidia.com/gpu: 1` and `nvidia.com/gpumem: 1024`, and show **1024 MiB total** inside `nvidia-smi`. A Ready Pod or a requested limit proves neither. If Helmfile times out on a Pending Pod, run `kubectl describe pod hami-demo-gpu` and read the scheduler events. If `nvidia-smi` reports full physical memory or no device, the driver, toolkit, runtime, or device plugin is wrong.

## Tear down

From `hami-demo/environment`, restore the original region/plan/version and select the saved kubeconfig. Confirm the cluster context before removing releases.

```bash
export KUBECONFIG="$PWD/kubeconfigs/vultr-gpu.yaml"
kubectl config current-context
kubectl get nodes -l gpu=on
read -r -p 'Original Vultr region: ' VULTR_REGION
read -r -p 'Original NVIDIA VKE plan: ' VULTR_GPU_PLAN
read -r -p 'Original VKE version: ' VULTR_K8S_VERSION
export VULTR_REGION VULTR_GPU_PLAN VULTR_K8S_VERSION
atmos helmfile destroy hami-demo -s vultr-gpu
atmos helmfile destroy hami -s vultr-gpu
read -r -s -p 'Vultr API key: ' VULTR_API_KEY
printf '\n'
export VULTR_API_KEY
atmos terraform plan vke -s vultr-gpu -destroy
atmos terraform destroy vke -s vultr-gpu
unset VULTR_API_KEY VULTR_REGION VULTR_GPU_PLAN VULTR_K8S_VERSION KUBECONFIG
rm -f kubeconfigs/vultr-gpu.yaml
```

Offline Terraform validation and Helmfile rendering prove nothing about a live cluster: not that the Vultr GPU image has working drivers, not that the plan is in stock, not that the in-container 1024 MiB limit was applied.

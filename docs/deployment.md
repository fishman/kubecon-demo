---
title: Deployment
---

This repo provisions **one Vultr VKE cluster** with Atmos. The default Helmfile component installs only HAMi. An optional second component installs one idle CUDA Pod to inspect a 1024 MiB HAMi allocation. The larger workloads in `demo/` are separate; this procedure does not deploy them.

## Prerequisites

- A Vultr account with permission and quota for a **VKE NVIDIA GPU** worker. Check price and availability for your region first; applying Terraform creates billable resources.
- `atmos`, Terraform 1.6+, Helm, Helmfile, `kubectl`, and `vultr-cli` installed. Configure the CLI in your own shell. The Vultr Terraform provider takes `VULTR_API_KEY` from the environment, not from an Atmos stack.
- A GPU worker image with an NVIDIA driver and [NVIDIA Container Toolkit/runtime configured for HAMi](https://project-hami.io/docs/installation/prerequisites#preparing-your-gpu-nodes). This configuration does **not** install a driver or GPU Operator. Only use an NVIDIA GPU plan; the demo does not support AMD GPUs.
- A private single-operator Terraform state directory. Terraform state includes the cluster kubeconfig. For team use, configure a protected remote backend before provisioning; do not reuse someone else's state key or import an existing cluster without its owner.

## Provision VKE

From the repository root, use your authenticated local terminal. Choose the plan actually returned for the region, and a currently supported VKE version. Both are required; a missing input becomes empty in `atmos describe` and is rejected by Terraform variable validation during plan.

```bash
cd environment
umask 077
vultr-cli regions availability ewr
vultr-cli kubernetes versions
read -r -p 'NVIDIA VKE plan available in ewr: ' VULTR_GPU_PLAN
read -r -p 'Supported VKE version: ' VULTR_K8S_VERSION
export VULTR_GPU_PLAN VULTR_K8S_VERSION
read -r -s -p 'Vultr API key: ' VULTR_API_KEY
printf '\n'
export VULTR_API_KEY
atmos terraform plan vke -s vultr-gpu
# Review the plan, GPU SKU, region, cost and state owner before continuing.
atmos terraform apply vke -s vultr-gpu
unset VULTR_API_KEY
```

Set `umask 077` **before** Terraform plan or apply: Terraform state and its backups can contain the kubeconfig and inherit the shell's file permissions. If state already exists from a weaker umask, restrict its permissions and treat prior access as a credential-exposure incident.

No key goes into `stacks/vultr-gpu.yaml`, a Helmfile variable, or a committed file. The provisioned pool has one worker labeled `gpu=on`. If plan/version availability changes between the listing and the apply, stop and choose supported inputs instead of assuming an old value works.

Write the sensitive kubeconfig with restrictive permissions. This path is ignored by Git:

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

The Pod must use `hami-scheduler`, request `nvidia.com/gpu: 1` and `nvidia.com/gpumem: 1024`, and show **1024 MiB total** GPU memory inside `nvidia-smi`. A Ready Pod or requested limit alone does not prove the runtime applied a memory limit. The demo release does not atomically roll back, so if Helmfile times out on a Pending Pod, run `kubectl describe pod hami-demo-gpu` and inspect scheduler/events before deleting that release. If `nvidia-smi` shows full physical memory or cannot see the device, check driver/toolkit/runtime configuration and device-plugin logs before claiming HAMi allocation works.

## Tear down

From `hami-demo/environment`, restore the original plan/version and explicitly select the saved VKE kubeconfig even in a new shell. Confirm the cluster before removing releases. Terraform destroy removes billable cloud resources; re-supply `VULTR_API_KEY` in your trusted terminal and review the destroy plan first.

```bash
umask 077
export KUBECONFIG="$PWD/kubeconfigs/vultr-gpu.yaml"
kubectl config current-context
kubectl get nodes -l gpu=on
read -r -p 'Original NVIDIA VKE plan: ' VULTR_GPU_PLAN
read -r -p 'Original VKE version: ' VULTR_K8S_VERSION
export VULTR_GPU_PLAN VULTR_K8S_VERSION
atmos helmfile destroy hami-demo -s vultr-gpu
atmos helmfile destroy hami -s vultr-gpu
read -r -s -p 'Vultr API key: ' VULTR_API_KEY
printf '\n'
export VULTR_API_KEY
atmos terraform plan vke -s vultr-gpu -destroy
atmos terraform destroy vke -s vultr-gpu
unset VULTR_API_KEY VULTR_GPU_PLAN VULTR_K8S_VERSION KUBECONFIG
rm -f kubeconfigs/vultr-gpu.yaml
```

These instructions describe checks to perform on a real cluster. Offline Terraform validation and Helmfile rendering do **not** prove that a particular Vultr GPU image has working drivers, that a plan is available, or that the in-container 1024 MiB limit has been observed.

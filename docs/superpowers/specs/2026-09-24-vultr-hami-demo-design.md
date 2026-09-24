# Vultr HAMi demo design

## Purpose and scope

Show how to install and verify HAMi on a Vultr Kubernetes Engine (VKE) cluster with one NVIDIA GPU worker. Provision infrastructure with Terraform through Atmos, install HAMi with Helmfile, and run one optional lightweight demonstration Pod through a separate Helmfile component. No vLLM model download, inference service, GPU Operator, ingress, multi-cloud provisioning, or live cloud apply is part of this change. The existing `demo/` bundle remains independent and usable against other clusters.

## Sources and ownership

Use the layout of `../environment.bak` for Atmos stack/component separation, and adapt the VKE Terraform and HAMi selector configuration from `../vultr_infra/infrastructure`. Do not copy its generated `.terraform` files or couple the HAMi release to its vLLM chart. This repository owns `environment/`; the separate `../hami-website` repository owns the article. Do not overwrite or remove unrelated user changes in either repository.

## Components

- `environment/atmos.yaml` defines Terraform and Helmfile component roots and the stacks root.
- `environment/stacks/vultr-gpu.yaml` defines one stack: cluster name, Vultr region, worker count, GPU node label, and demo GPU request. Require operator-supplied `VULTR_GPU_PLAN` and `VULTR_K8S_VERSION` from current region availability and supported-version listings; do not hardcode a GPU SKU or stale Kubernetes version.
- `environment/components/terraform/vke` adapts the existing `vultr_kubernetes` resource: one labeled worker node pool, provider version constraint, and sensitive kubeconfig output. Keep the VKE API credential in `VULTR_API_KEY`, never a stack variable. Terraform state contains sensitive kubeconfig material; use a private, ignored local state for this demo and explicitly document that team/shared use requires a controlled remote backend. Do not import, recreate, or apply over an existing cluster without identifying the state owner.
- `environment/components/helmfile/hami` installs only the official HAMi chart, with NVIDIA device-plugin node selection matching the Terraform GPU label. Keep the chart version explicit. This component contains no model workload or driver installation.
- `environment/components/helmfile/hami-demo` installs one small NVIDIA demo Pod through a minimal local chart. It selects the labeled GPU node and `hami-scheduler`, requests `nvidia.com/gpu: 1` and `nvidia.com/gpumem: 1024` (MiB), and runs a pinned CUDA image with a long-lived idle command so `kubectl exec ... -- nvidia-smi` can inspect its GPU view. No model, Service, ingress, persistent volume, or CPU-intensive application. It is opt-in, applied after `hami`, and destroyed before `hami`.

## Deployment and failure flow

1. The operator checks VKE region availability, NVIDIA GPU plan, supported Kubernetes version, and expected cost before provisioning. Terraform plan is inspected before apply; this change does not auto-apply or auto-destroy cloud resources.
2. The operator supplies `VULTR_API_KEY` only in a trusted shell, never in stack/Helmfile vars. Set `umask 077` **before** Terraform plan/apply because local state and backups contain the sensitive VKE kubeconfig. Decode Vultr's base64 kubeconfig output, write it to an ignored local path, and explicitly set `KUBECONFIG`; no fixed `/tmp` credential file.
3. Before installing HAMi, verify the intended `gpu=on` node has a working NVIDIA driver and default NVIDIA container runtime/toolkit, and no competing device plugin owns `nvidia.com/gpu`. Its capacity may be absent before HAMi's device plugin starts; do not use that alone as a pre-install failure. No GPU Operator is installed by default.
4. Both Helmfile components fail closed without an explicit `KUBECONFIG`. Apply only `hami`; wait for scheduler and NVIDIA device-plugin readiness, then check GPU allocatable capacity before continuing.
5. Apply `hami-demo` explicitly. Verify Pod readiness, scheduler, requested GPU resources, and the 1024 MiB total seen in-container with `nvidia-smi`. Keep a failed demo Pod available for event inspection instead of atomically rolling it back.
6. For teardown, re-export the saved VKE `KUBECONFIG` and original GPU plan/version even in a new shell, verify cluster context, destroy demo then HAMi, review Terraform destroy, and only then remove VKE and the local kubeconfig. Never treat cleanup as unattended cloud action.

## Article

Create `../hami-website/docs/installation/vultr-installation.md` beside `aws-installation.md`, add it to the installation sidebar, and use Reza's concise, evidence-first voice from `hami-website-blog`. Follow Docusaurus docs frontmatter and fenced code. Include exact, self-contained snapshots for Atmos, Terraform, HAMi Helmfile, and the rendered demo Pod; name `https://github.com/Project-HAMi/hami-demo` as the canonical source, but do not depend on its current public default branch having `environment/`. Thank Vultr for helping with the example without inventing observed deployment results. Replace the old vLLM/model/API narrative with the plan/apply, secure kubeconfig, GPU preflight, HAMi install, demo verification, and reverse teardown. Cite primary Vultr/HAMi/Atmos documentation where needed.

## Verification and acceptance

- Static Atmos stack resolution finds exactly `vke`, `hami`, and `hami-demo` with valid component paths; Helmfile rendering shows HAMi without a demo release and the demo component without another HAMi release. Rendered demo Pod has the intended selector, scheduler, and GPU limits.
- Terraform format, validation, and a mock-provider test prove the sensitive kubeconfig output decodes to YAML without a cloud API call. Helmfile templates render without a cluster and refuse missing `KUBECONFIG`. A live deployment is not claimed without a GPU-capable VKE cluster and credentials.
- Secrets, state, plans, generated varfiles, and kubeconfigs are ignored by version control, while restrictive permissions come from setting `umask 077` before Terraform. The website installation guide passes lint, format check, and English build; its embedded source snippets reproduce the actual manifests. A site build does not establish cloud runtime behavior.

## Constraints and tradeoffs

A GPU plan and version cannot be preselected without current Vultr region availability. VKE's NVIDIA driver/toolkit status must be checked on the actual chosen node. A small Pod is enough to demonstrate HAMi memory allocation, not inference performance, compute isolation, or isolation against hostile workloads. Local Terraform state is acceptable only for a single-operator demonstration; it is not a team backend or secret vault.

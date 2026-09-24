# Vultr HAMi Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provision one Vultr VKE GPU cluster with Atmos, install HAMi alone, optionally deploy one small GPU Pod, and write a self-contained installation guide beside HAMi's AWS guide.

**Architecture:** `environment/` owns one `vultr-gpu` stack and three independent components: Terraform `vke`, Helmfile `hami`, and Helmfile `hami-demo`. The stack provides only public configuration; the operator provides the Vultr key directly to Terraform and saves the sensitive kubeconfig locally. The Docusaurus article lives in the separate HAMi website repository and describes exactly these components.

**Tech Stack:** Atmos, Terraform `vultr/vultr ~> 2.32`, Helmfile, Helm, HAMi chart `2.10.0`, Kubernetes/VKE, Docusaurus 3.

**Spec:** `docs/superpowers/specs/2026-09-24-vultr-hami-demo-design.md`

## Global Constraints

- No cloud apply/destroy without separate explicit authorization; static validation is the implementation proof.
- Never inspect, print, log, or commit `VULTR_API_KEY`; never put it in Atmos vars. Never copy `.terraform/`, state, plans, or kubeconfigs from `../vultr_infra` or `../environment.bak`.
- GPU plan and VKE version must be chosen from current Vultr availability for the selected region and supplied as `VULTR_GPU_PLAN` and `VULTR_K8S_VERSION`.
- `hami` installs no workload and no driver; `hami-demo` installs one Pod only, requesting `nvidia.com/gpu: 1` and `nvidia.com/gpumem: 1024` MiB. Existing `demo/` files remain unchanged.
- Preflight driver and runtime on the GPU node. The GPU allocatable resource can appear only after the HAMi device plugin starts; do not require it before installing HAMi.
- The article is a Docusaurus installation page in Reza's style, with exact Terraform and Pod YAML snapshots and no claim of unobserved cloud success. Never copy the source Hugo draft's shortcodes, `<!--more-->`, or fabricated sample output.
- Existing worktree changes are user-owned. Stage only task files; the article is in another repository and should not be committed with this project's changes.

## Review Focus

1. A missing `VULTR_GPU_PLAN` or `VULTR_K8S_VERSION` resolves to an empty Atmos variable; Terraform validation must reject it before creating an unsuitable node pool. Task 1 exercises both missing inputs.
2. A different GPU label in Terraform and HAMi would leave the plugin unscheduled; Task 2 compares the rendered selector to the stack's label.
3. An unexpected inherited kubeconfig could deploy HAMi to the wrong cluster; Task 2 checks explicit `KUBECONFIG`, and the docs require setting it to the generated path.
4. HAMi readiness does not imply GPU capacity or enforcement; Task 3 checks scheduler, requested limits, and in-container visible memory separately.
5. Terraform state and kubeconfig carry credentials; Task 1 checks ignore coverage and Task 4 documents local permissions and single-operator state ownership.

---

### Task 1: Atmos VKE stack

**Files:** Create `environment/atmos.yaml`, `environment/stacks/vultr-gpu.yaml`, `environment/components/terraform/vke/main.tf`, `environment/components/terraform/vke/variables.tf`, `environment/components/terraform/vke/tests/kubeconfig.tftest.hcl`; modify `.gitignore`.

**Interfaces:** Produces the `vultr-gpu` stack with Terraform component `vke`, a GPU worker labeled `gpu=on`, `cluster_id`, and sensitive `kube_config` output. Consumes `VULTR_GPU_PLAN` and `VULTR_K8S_VERSION` from the operator, and `VULTR_API_KEY` only in provider operations.

- [ ] **Step 1: RED.** From `environment/`, run `VULTR_GPU_PLAN=example VULTR_K8S_VERSION=example atmos describe component vke -s vultr-gpu`. It must fail while the component is absent. Do not set or read `VULTR_API_KEY`.
- [ ] **Step 2: Create the Atmos root and stack.** Use the existing `../vultr_infra/infrastructure/atmos.yaml` layout, with component base paths `components/terraform` and `components/helmfile` and stack base path `stacks`. Define the stack as:

```yaml
name: vultr-gpu
vars:
  stage: vultr-gpu
components:
  terraform:
    vke:
      vars:
        cluster_name: hami-demo
        region: ewr
        kubernetes_version: !env VULTR_K8S_VERSION
        gpu_plan: !env VULTR_GPU_PLAN
        gpu_node_count: 1
  helmfile:
    hami:
      dependencies:
        components:
          - name: vke
            kind: terraform
      vars:
        gpu_node_label: gpu
        gpu_node_value: "on"
        hami_chart_version: "2.10.0"
    hami-demo:
      dependencies:
        components:
          - name: hami
            kind: helmfile
      vars:
        gpu_node_label: gpu
        gpu_node_value: "on"
        gpu_memory_mib: 1024
```

- [ ] **Step 3: Create Terraform source.** Adapt `../vultr_infra/infrastructure/components/terraform/vke/main.tf`: require Terraform `>= 1.6.0`, Vultr provider `~> 2.32`, create `vultr_kubernetes` with one `gpu=on` node pool. Expose `cluster_id` and sensitive `kube_config`; use `base64decode(vultr_kubernetes.this.kube_config)` because the provider's attribute is base64 encoded. Declare typed inputs and reject empty plan/version strings. A mock-provider Terraform test asserts `kube_config` yields plaintext YAML. No provisioners or inherited state backend.
- [ ] **Step 4: Protect local material.** Ignore `.terraform/`, `*.tfstate*`, `*.tfplan`, `*.planfile`, `*.terraform.tfvars.json`, `*.helmfile.vars.yaml`, and `environment/kubeconfigs/`; keep `.terraform.lock.hcl` tracked. Set `umask 077` before any Terraform plan/apply in the runbook because state contains credentials.
- [ ] **Step 5: GREEN.** Resolve the stack with fake plan/version values. Missing values show as empty in `atmos describe`; confirm Terraform validation rejects each empty value without a real API key. Run `terraform fmt -check`, `terraform init -backend=false`, `terraform validate`, and the mocked `terraform test`. Never use real credentials for these checks.

### Task 2: HAMi-only Helmfile

**Files:** Create `environment/components/helmfile/hami/helmfile.yaml.gotmpl`; modify `environment/stacks/vultr-gpu.yaml` only if stack variables must be adjusted after rendering.

**Interfaces:** Consumes stack `gpu_node_label`, `gpu_node_value`, `hami_chart_version`, and operator-set `KUBECONFIG`; produces only Helm release `kube-system/hami` from the official HAMi chart.

- [ ] **Step 1: RED.** With fake `VULTR_GPU_PLAN` and `VULTR_K8S_VERSION`, run `atmos helmfile template hami -s vultr-gpu` from `environment/`. An absent component must fail. Rendering must never be used as authorization to deploy.
- [ ] **Step 2: Create the release template.** Split the HAMi release out of `../vultr_infra/infrastructure/components/helmfile/hami-vllm/helmfile.yaml.gotmpl`. Preserve its GPU selectors, but remove the vLLM release:

```yaml
{{- $_ := requiredEnv "KUBECONFIG" -}}
repositories:
  - name: hami-charts
    url: https://project-hami.github.io/HAMi/
releases:
  - name: hami
    namespace: kube-system
    chart: hami-charts/hami
    version: {{ .Values.hami_chart_version | quote }}
    wait: true
    atomic: true
    values:
      - global:
          managedNodeSelectorEnable: true
          managedNodeSelector:
            {{ .Values.gpu_node_label }}: {{ .Values.gpu_node_value | quote }}
        devicePlugin:
          nvidiaNodeSelector:
            {{ .Values.gpu_node_label }}: {{ .Values.gpu_node_value | quote }}
```

- [ ] **Step 3: GREEN.** Render with fake stack inputs and an explicit test `KUBECONFIG`; verify the only release is `hami` and its selector matches `gpu=on`. Unset `KUBECONFIG` and confirm Helmfile refuses to render, so apply/destroy cannot fall back to an ambient cluster context. No vLLM, GPU Operator, or demo Pod is emitted.

### Task 3: Optional small HAMi Pod

**Files:** Create `environment/components/helmfile/hami-demo/helmfile.yaml.gotmpl`, `environment/components/helmfile/hami-demo/chart/Chart.yaml`, `environment/components/helmfile/hami-demo/chart/values.yaml`, `environment/components/helmfile/hami-demo/chart/templates/pod.yaml`.

**Interfaces:** Consumes the matching GPU label and `gpu_memory_mib=1024` from the stack; produces one Pod named `hami-demo-gpu` in `default`, with scheduler `hami-scheduler`. No HAMi release in this component.

- [ ] **Step 1: RED.** Run `atmos describe component hami-demo -s vultr-gpu` with fake plan/version inputs and `helm template hami-demo environment/components/helmfile/hami-demo/chart` from repo root. The chart render must fail because the chart does not yet exist.
- [ ] **Step 2: Create the chart.** Use a `v2` Helm chart named `hami-demo` with version `0.1.0`. Defaults in `values.yaml`: `gpu.nodeSelector.gpu: "on"`, `gpu.memoryMiB: 1024`, and `image: nvidia/cuda:12.8.1-base-ubuntu24.04`. `templates/pod.yaml` should render exactly one Pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hami-demo-gpu
spec:
  schedulerName: hami-scheduler
  nodeSelector:{{ toYaml .Values.gpu.nodeSelector | nindent 4 }}
  containers:
    - name: cuda
      image: {{ .Values.image | quote }}
      command: ["sleep", "infinity"]
      resources:
        limits:
          nvidia.com/gpu: "1"
          nvidia.com/gpumem: {{ .Values.gpu.memoryMiB | quote }}
```

- [ ] **Step 3: Create the Helmfile release.** `hami-demo/helmfile.yaml.gotmpl` contains only release `hami-demo` using `./chart`, with `wait: true`, a required `KUBECONFIG`, and stack values for the node selector and 1024 MiB memory request. Do not enable atomic rollback: a Pending Pod must remain for event inspection. No Service, PVC, vLLM, or second HAMi release.
- [ ] **Step 4: GREEN.** Run `helm lint environment/components/helmfile/hami-demo/chart` and `helm template hami-demo environment/components/helmfile/hami-demo/chart`; inspect scheduler, selector, GPU limits, image, and count of rendered Kubernetes objects (one Pod). Render the Helmfile component with fake stack inputs. Confirm source of HAMi release is Task 2 only. A live cluster would additionally require `kubectl wait --for=condition=Ready pod/hami-demo-gpu --timeout=180s`, `kubectl get pod hami-demo-gpu -o jsonpath='{.spec.schedulerName}{"\n"}{.spec.containers[0].resources.limits}{"\n"}'`, and `kubectl exec hami-demo-gpu -- nvidia-smi`; do not claim those ran without a cluster.

### Task 4: Operator instructions and website installation guide

**Files:** Modify `README.md`, `docs/deployment.md`, `docs/index.md` to remove nonexistent cloud commands from the primary path; create `../hami-website/docs/installation/vultr-installation.md`; modify `../hami-website/sidebars.js` to include it.

**Interfaces:** Consumes actual component/chart names from Tasks 1–3. Produces a safe operator sequence and self-contained Docusaurus installation guide with code snapshots; no claim of a completed Vultr deployment.

- [ ] **Step 1: Identify stale claims.** Confirm old GKE/ACK/AKS commands do not exist in this repo; retain true claims about `demo/`. Read website `AGENTS.md` and `docs/installation/aws-installation.md` for layout, and use `hami-website-blog` for voice, not community posts.
- [ ] **Step 2: Replace primary runbook.** Document the exact sequence below, with the real region and plan/version supplied by the operator. The variable assignments represent operator inputs, not values the agent reads:

```bash
cd environment
umask 077
vultr-cli regions availability ewr
vultr-cli kubernetes versions
read -r -p 'NVIDIA VKE plan available in ewr: ' VULTR_GPU_PLAN
read -r -p 'Supported VKE version: ' VULTR_K8S_VERSION
export VULTR_GPU_PLAN VULTR_K8S_VERSION
# Provide VULTR_API_KEY only in the operator's trusted shell.
atmos terraform plan vke -s vultr-gpu
atmos terraform apply vke -s vultr-gpu
mkdir -p kubeconfigs
atmos terraform output vke -s vultr-gpu -raw kube_config > kubeconfigs/vultr-gpu.yaml
export KUBECONFIG="$PWD/kubeconfigs/vultr-gpu.yaml"
kubectl config current-context
kubectl get nodes -l gpu=on
# Confirm driver, NVIDIA default runtime, and no competing device plugin.
atmos helmfile apply hami -s vultr-gpu
kubectl get pods -n kube-system
kubectl get nodes -l gpu=on -o 'custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
atmos helmfile apply hami-demo -s vultr-gpu
kubectl wait --for=condition=Ready pod/hami-demo-gpu --timeout=180s
kubectl exec hami-demo-gpu -- nvidia-smi
```

Explain host preflight, competing device-plugin conflicts, HAMi readiness, Pod events on pending, 1024 MiB visible inside the Pod, and state confidentiality. For teardown in a later shell, re-export saved VKE `KUBECONFIG`, verify the context, re-enter the original plan/version and key, then destroy `hami-demo`, `hami`, and `vke` in that order after reviewing the destroy plan.
- [ ] **Step 3: Create website installation guide.** Use `docs/installation/vultr-installation.md` beside `aws-installation.md`, Docusaurus docs frontmatter, fenced code, a self-contained snapshot of each runnable Atmos/Terraform/Helmfile/chart file plus the rendered Pod YAML, and a truthful Vultr thank-you. Link `Project-HAMi/hami-demo` as the canonical source without assuming its public default branch already has `environment/`. Replace the old vLLM narrative; distinguish offline checks from unobserved live GPU behavior.
- [ ] **Step 4: Check documentation and site.** Run website `npm run lint`, `npm run format:check`, `npm run build:fast`, and `npm test`. Verify `docs/next/installation/vultr-installation` renders and its source snapshots match the executable files; offline build is not cloud verification.
- [ ] **Step 5: Review scoped changes.** Review only intended project and website paths. Preserve user-owned unrelated work. Every `hami-demo` and `hami-website` commit for this change must carry a DCO sign-off (`git commit -s`); do not push or publish without user authorization.

## Execution handoff

The components can be statically validated without a cloud account. Live provisioning, GPU runtime checks, and cloud destroy are operator actions after checking plan, cost, state ownership, and credentials. The installation guide is in the website's unreleased `/docs/next` content until that documentation is versioned.

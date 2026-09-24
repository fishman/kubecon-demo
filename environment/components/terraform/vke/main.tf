terraform {
  required_version = ">= 1.6.0"

  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.32"
    }
  }
}

resource "vultr_kubernetes" "this" {
  label   = var.cluster_name
  region  = var.region
  version = var.kubernetes_version

  node_pools {
    label         = "gpu"
    node_quantity = var.gpu_node_count
    plan          = var.gpu_plan

    labels {
      key   = "gpu"
      value = "on"
    }
  }
}

output "cluster_id" {
  value = vultr_kubernetes.this.id
}

output "kube_config" {
  value     = base64decode(vultr_kubernetes.this.kube_config)
  sensitive = true
}

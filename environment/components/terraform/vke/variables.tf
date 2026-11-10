variable "cluster_name" {
  type        = string
  description = "Vultr Kubernetes Engine cluster label."
}

variable "region" {
  type        = string
  description = "Vultr region with the selected NVIDIA GPU VKE plan."

  validation {
    condition     = length(trimspace(var.region)) > 0
    error_message = "VULTR_REGION must be a Vultr region id."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "Supported version returned by vultr-cli kubernetes versions."

  validation {
    condition     = length(trimspace(var.kubernetes_version)) > 0
    error_message = "VULTR_K8S_VERSION must be a supported VKE version."
  }
}

variable "gpu_plan" {
  type        = string
  description = "NVIDIA GPU VKE plan available in the selected region."

  validation {
    condition     = length(trimspace(var.gpu_plan)) > 0
    error_message = "VULTR_GPU_PLAN must be an NVIDIA GPU plan available in the selected region."
  }
}

variable "gpu_node_count" {
  type        = number
  description = "Number of GPU workers."
  default     = 1

  validation {
    condition     = var.gpu_node_count > 0
    error_message = "gpu_node_count must be positive."
  }
}

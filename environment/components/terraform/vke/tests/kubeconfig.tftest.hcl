mock_provider "vultr" {
  mock_resource "vultr_kubernetes" {
    defaults = {
      kube_config = base64encode("apiVersion: v1\nkind: Config\n")
    }
  }
}

run "exports_plain_yaml_kubeconfig" {
  command = apply

  variables {
    cluster_name       = "hami-demo"
    region             = "ewr"
    kubernetes_version = "example"
    gpu_plan           = "example"
  }

  assert {
    condition     = startswith(output.kube_config, "apiVersion: v1\nkind: Config\n")
    error_message = "kube_config must be decoded before writing it to a kubeconfig file."
  }
}

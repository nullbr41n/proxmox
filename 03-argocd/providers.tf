provider "kubernetes" {
  config_path = var.kubeconfig_path != "" ? pathexpand(var.kubeconfig_path) : null
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path != "" ? pathexpand(var.kubeconfig_path) : null
  }
}

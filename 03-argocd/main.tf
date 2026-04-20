resource "kubernetes_manifest" "metallb_ip_pool" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = "default-pool"
      namespace = "metallb-system"
    }
    spec = {
      addresses = [var.metallb_ip_addresses]
    }
  }

  depends_on = [data.terraform_remote_state.metallb]
}

resource "kubernetes_manifest" "metallb_l2_advertisement" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "L2Advertisement"
    metadata = {
      name      = "default"
      namespace = "metallb-system"
    }
    spec = {
      ipAddressPools = [kubernetes_manifest.metallb_ip_pool.manifest.metadata.name]
    }
  }

  depends_on = [kubernetes_manifest.metallb_ip_pool]
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"

  create_namespace = true
  wait             = true
  timeout          = 900

  set = [{
    name  = "server.service.type"
    value = var.argocd_server_service_type
  }]

  depends_on = [kubernetes_manifest.metallb_l2_advertisement]
}

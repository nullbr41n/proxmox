resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"

  create_namespace = true
  wait             = true
  timeout          = 900

  values = [yamlencode({
    configs = {
      params = {
        "server.insecure" = "true"
      }
    }
    server = {
      service = {
        type = var.argocd_server_service_type
      }
      ingress = {
        enabled          = true
        ingressClassName = "nginx"
        hostname         = var.argocd_hostname
        path             = "/"
        pathType         = "Prefix"
      }
    }
  })]

  depends_on = [data.terraform_remote_state.ingress_nginx]
}

resource "kubernetes_secret_v1" "argocd_apps_repo" {
  metadata {
    name      = "repo-apps"
    namespace = helm_release.argocd.namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = merge({
    url  = var.argocd_apps_repo_url
    type = var.argocd_apps_repo_type
  }, var.argocd_apps_repo_username != "" ? {
    username = var.argocd_apps_repo_username
  } : {}, var.argocd_apps_repo_password != "" ? {
    password = var.argocd_apps_repo_password
  } : {}, var.argocd_apps_repo_ssh_private_key != "" ? {
    sshPrivateKey = var.argocd_apps_repo_ssh_private_key
  } : {}, var.argocd_apps_repo_insecure_ignore_host_key ? {
    insecure = "true"
  } : {})

  type = "Opaque"

  depends_on = [helm_release.argocd]
}

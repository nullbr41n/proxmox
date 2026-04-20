resource "helm_release" "metallb" {
  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  namespace  = "metallb-system"

  create_namespace = true
  wait             = true
  timeout          = 900

  depends_on = [data.terraform_remote_state.cluster]
}

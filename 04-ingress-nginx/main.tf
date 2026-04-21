resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = var.ingress_nginx_namespace

  create_namespace = true
  wait             = true
  timeout          = 900

  values = [yamlencode({
    controller = {
      ingressClassResource = {
        name = var.ingress_nginx_ingress_class_name
      }
      ingressClass = var.ingress_nginx_ingress_class_name
      service = merge({
        type = var.ingress_nginx_service_type
        }, var.ingress_nginx_load_balancer_ip != "" ? {
        loadBalancerIP = var.ingress_nginx_load_balancer_ip
      } : {})
    }
  })]

  depends_on = [data.terraform_remote_state.networking]
}

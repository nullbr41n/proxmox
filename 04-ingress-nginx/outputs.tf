output "ingress_nginx_namespace" {
  description = "Namespace where ingress-nginx is installed."
  value       = helm_release.ingress_nginx.namespace
}

output "ingress_nginx_release_name" {
  description = "Helm release name for ingress-nginx."
  value       = helm_release.ingress_nginx.name
}

output "ingress_nginx_ingress_class_name" {
  description = "IngressClass name managed by the ingress-nginx controller."
  value       = var.ingress_nginx_ingress_class_name
}

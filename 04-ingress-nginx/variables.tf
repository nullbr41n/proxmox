variable "kubeconfig_path" {
  description = "Path to kubeconfig with admin access. If empty, uses KUBECONFIG env or the default kubeconfig search path."
  type        = string
  default     = ""
}

variable "ingress_nginx_namespace" {
  description = "Namespace where ingress-nginx will be installed."
  type        = string
  default     = "ingress-nginx"
}

variable "ingress_nginx_service_type" {
  description = "Service type for the ingress-nginx controller Service."
  type        = string
  default     = "LoadBalancer"
}

variable "ingress_nginx_ingress_class_name" {
  description = "Ingress class name managed by ingress-nginx."
  type        = string
  default     = "nginx"
}

variable "ingress_nginx_load_balancer_ip" {
  description = "Optional fixed MetalLB IP to assign to the ingress-nginx controller Service."
  type        = string
  default     = ""
}

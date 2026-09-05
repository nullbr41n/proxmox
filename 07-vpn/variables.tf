variable "kubeconfig_path" {
  description = "Path to kubeconfig with admin access. If empty, uses KUBECONFIG env or the default kubeconfig search path."
  type        = string
  default     = ""
}

variable "vpn_namespace" {
  description = "Kubernetes namespace for VPN resources."
  type        = string
  default     = "vpn"
}

variable "ingress_ip" {
  description = "MetalLB IP of the ingress-nginx controller. Returned as the A record for all *.intra_domain queries."
  type        = string
}

variable "intra_domain" {
  description = "Internal domain resolved by the VPN DNS service."
  type        = string
  default     = "intra.nixbin.com"
}

variable "coredns_vpn_ip" {
  description = "MetalLB IP for the VPN DNS service. VPN clients receive this as their DNS server."
  type        = string
}

variable "wg_easy_ip" {
  description = "MetalLB IP for the wg-easy Kubernetes Service (internal cluster IP)."
  type        = string
}

variable "wg_easy_host" {
  description = "Public IP or hostname embedded in client WireGuard configs as the Endpoint. Must be reachable on UDP 51820 from the internet."
  type        = string
}

variable "wg_easy_password_hash" {
  description = "bcrypt hash for the wg-easy admin UI. Generate with: docker run --rm -it ghcr.io/wg-easy/wg-easy:14 wgpw YOUR_PASSWORD"
  type        = string
  sensitive   = true
}

variable "wg_easy_vpn_cidr" {
  description = "VPN client address range. wg-easy assigns IPs sequentially; x is replaced with the host octet."
  type        = string
  default     = "10.8.0.x"
}

variable "wg_easy_allowed_ips" {
  description = "Routes pushed to VPN clients. Default is split-tunnel: only cluster network traffic goes through the VPN."
  type        = string
  default     = "10.10.11.0/24"
}

variable "wg_easy_image_tag" {
  description = "wg-easy image tag."
  type        = string
  default     = "14"
}

variable "coredns_image" {
  description = "CoreDNS image for the VPN DNS deployment. Should match the cluster CoreDNS version."
  type        = string
  default     = "registry.k8s.io/coredns/coredns:v1.13.1"
}

variable "storage_class_name" {
  description = "StorageClass for the wg-easy config PVC."
  type        = string
  default     = "lvm-4tb"
}

variable "npm_ip" {
  description = "IP of the reverse proxy (e.g. Nginx Proxy Manager) for domains not served by the cluster ingress."
  type        = string
  default     = ""
}

variable "npm_domains" {
  description = "Additional hostnames to resolve to npm_ip via VPN CoreDNS."
  type        = list(string)
  default     = []
}

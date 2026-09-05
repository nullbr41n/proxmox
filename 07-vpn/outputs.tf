output "wg_easy_ip" {
  description = "MetalLB IP for wg-easy. Admin UI: http://<ip>:51821  WireGuard endpoint: <ip>:51820/UDP."
  value       = var.wg_easy_ip
}

output "coredns_vpn_ip" {
  description = "MetalLB IP of the VPN DNS service. Pushed to WireGuard clients as their DNS server via WG_DEFAULT_DNS."
  value       = var.coredns_vpn_ip
}

output "vpn_namespace" {
  description = "Namespace where VPN resources are deployed."
  value       = kubernetes_namespace_v1.vpn.metadata[0].name
}

output "control_plane_vip" {
  description = "Stable Kubernetes API endpoint VIP."
  value       = var.kubeadm_control_plane_vip
}

output "control_plane_hostname" {
  description = "Stable Kubernetes API endpoint hostname."
  value       = var.kubeadm_control_plane_hostname
}

output "enabled_control_plane_slots" {
  value = sort(tolist(local.cp_slots))
}

output "enabled_worker_slots" {
  value = sort(tolist(local.worker_slots))
}

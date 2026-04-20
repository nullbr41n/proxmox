output "argocd_application_name" {
  description = "Name of the Argo CD app-of-apps Application."
  value       = kubernetes_manifest.argocd_apps.manifest.metadata.name
}

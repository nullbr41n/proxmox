variable "kubeconfig_path" {
  description = "Path to kubeconfig with admin access. If empty, uses KUBECONFIG env or the default kubeconfig search path."
  type        = string
  default     = ""
}

variable "argocd_apps_repo_url" {
  description = "Git repo URL for the Argo CD app-of-apps."
  type        = string
}

variable "argocd_apps_target_revision" {
  description = "Target revision or branch for the app-of-apps."
  type        = string
  default     = "main"
}

variable "argocd_apps_path" {
  description = "Path in the repo for the app-of-apps."
  type        = string
  default     = "apps"
}

variable "argocd_apps_helm_value_files" {
  description = "Helm value files for the app-of-apps."
  type        = list(string)
  default     = ["values.yaml"]
}

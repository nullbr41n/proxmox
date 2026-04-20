data "terraform_remote_state" "argocd" {
  backend = "local"

  config = {
    path = "${path.module}/../03-argocd/terraform.tfstate"
  }
}

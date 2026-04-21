data "terraform_remote_state" "argocd" {
  backend = "local"

  config = {
    path = "${path.module}/../05-argocd/terraform.tfstate"
  }
}

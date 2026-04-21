data "terraform_remote_state" "ingress_nginx" {
  backend = "local"

  config = {
    path = "${path.module}/../04-ingress-nginx/terraform.tfstate"
  }
}

data "terraform_remote_state" "cluster" {
  backend = "local"

  config = {
    path = "${path.module}/../01-cluster/terraform.tfstate"
  }
}

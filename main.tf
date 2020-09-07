resource "random_string" "random-dir" {
  length  = 8
  special = false
}

module "cluster-credentials" {
  source  = "git::https://github.com/IBM-CAMHub-Open/template_mcm_modules.git//terraform12/cluster_credentials?ref=5.0.0"

  cluster_type   = "gke"
  work_directory = "mcm${random_string.random-dir.result}"

  ## Details for accessing the target cluster
  cluster_name                = var.cluster_name
  cluster_config              = var.cluster_config
  service_account_credentials = var.service_account_credentials

  ## Access to optional bastion host
  bastion_host        = var.bastion_host
  bastion_user        = var.bastion_user
  bastion_private_key = var.bastion_private_key
  bastion_port        = var.bastion_port
  bastion_host_key    = var.bastion_host_key
  bastion_password    = var.bastion_password
}

resource "null_resource" "configure-dns" {
  depends_on = [module.cluster-credentials.credentials_generated]

  provisioner "local-exec" {
    command = "chmod 755 ${path.module}/scripts/configure_dns.sh && ${path.module}/scripts/configure_dns.sh"
    environment = {
      WORK_DIR            = "mcm${random_string.random-dir.result}"
      MCM_HUB_IP          = var.mcm_hub_ip
      CLUSTER_NAME        = var.cluster_name
      CLUSTER_ENDPOINT    = var.cluster_endpoint
      CLUSTER_USER        = var.cluster_user
      CLUSTER_TOKEN       = var.cluster_token
      CLUSTER_CREDENTIALS = module.cluster-credentials.credentials_jsonfile
    }
  }
}

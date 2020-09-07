variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  default     = ""
}

variable "cluster_endpoint" {
  description = "URL for the Kubernetes cluster endpoint"
  default     = ""
}

variable "cluster_user" {
  description = "Username for accessing the Kubernetes cluster"
  default     = ""
}

variable "cluster_token" {
  description = "Token for authenticating with the Kubernetes cluster"
  default     = ""
}

variable "cluster_config" {
  description = "kubectl configuration text, Base64 encoded"
}

variable "cluster_credentials" {
  description = "JSON-formatted file containing the cluster name, endpoint, user and token information"
  default     = ""
}

variable "service_account_credentials" {
  description = "Credentials for service account used to access the cluster (Base64-encoded)"
}

variable "work_directory" {
  description = "Path of the temporary directory where work files will be generated"
  default     = ""
}

variable "mcm_hub_ip" {
  description = "hub ip address"
  default     = ""
}

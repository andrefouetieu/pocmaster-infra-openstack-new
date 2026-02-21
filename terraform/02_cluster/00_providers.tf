terraform {
  required_version = ">= 0.14.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4.0"
    }
  }

  # State stocké dans AWS S3. Toute la config est passée via -backend-config (ex. backend.s3.hcl).
  # Credentials AWS : AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY ou ~/.aws/credentials.
  backend "s3" {}
}

# Authentification OpenStack :
# - Si openstack_cloud est défini dans tfvars → utilisation de clouds.yaml (nom du cloud).
# - Sinon → auth via les variables openstack_auth_url, openstack_username, etc.
# Pour un clouds.yaml hors emplacement standard : export OS_CLOUD_CONFIG=... avant terraform.
provider "openstack" {
  cloud               = var.openstack_cloud != "" ? var.openstack_cloud : null
  auth_url            = var.openstack_cloud == "" ? var.openstack_auth_url : null
  user_name           = var.openstack_cloud == "" ? var.openstack_username : null
  password            = var.openstack_cloud == "" ? var.openstack_password : null
  tenant_name         = var.openstack_cloud == "" ? var.openstack_project_name : null
  region              = var.openstack_cloud == "" ? var.openstack_region_name : null
  user_domain_name    = var.openstack_cloud == "" ? var.openstack_user_domain_name : null
  project_domain_name = var.openstack_cloud == "" ? var.openstack_project_domain_name : null
}

  
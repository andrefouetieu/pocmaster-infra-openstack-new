terraform {
  required_version = ">= 0.14.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

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

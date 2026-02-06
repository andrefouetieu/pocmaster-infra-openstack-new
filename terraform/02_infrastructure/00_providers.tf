terraform {
  required_version = ">= 0.14.0" #version de terraform
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.52.1" #version du provider
    }
  }

  backend "http" {
    address = "https://gitlab.com/api/v4/projects/55396315/terraform/state/state_infrastructure"
    lock_address = "https://gitlab.com/api/v4/projects/55396315/terraform/state/state_infrastructure/lock"            
    unlock_address = "https://gitlab.com/api/v4/projects/55396315/terraform/state/state_infrastructure/lock"          
    lock_method = "POST"
    unlock_method = "DELETE"
    retry_wait_min = 5
  }

}

  
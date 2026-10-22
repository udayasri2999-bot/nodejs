###############################################################
# variables.tf
###############################################################

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-southeast-2"
}

variable "project_name" {
  description = "Prefix for all resource names"
  type        = string
  default     = "nodejs-app"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"  # 2 vCPU, 2GB RAM – good for all 5 containers
}

variable "allowed_cidr" {
  description = "Your IP address in CIDR notation for SSH access (e.g. 203.0.113.5/32). Use 0.0.0.0/0 to allow all (not recommended)."
  type        = string
  default     = "0.0.0.0/0"
}

variable "public_key_content" {
  description = "Your SSH public key content (paste the contents of id_rsa.pub)"
  type        = string
}

variable "db_password" {
  description = "MySQL root password"
  type        = string
  sensitive   = true
  default     = "new_password"
}

variable "common_tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "nodejs-app"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

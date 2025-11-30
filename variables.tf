variable "primary_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "multireg"
}

variable "ami_us_east_1" {
  type    = string
  default = "ami-0123456789abcdef0" # replace with real AMI
}

variable "ami_us_west_2" {
  type    = string
  default = "ami-0123456789abcdef0" # replace with real AMI
}

variable "vpc_cidr_use1" {
  type    = string
  default = "10.10.0.0/16"
}

variable "vpc_cidr_usw2" {
  type    = string
  default = "10.20.0.0/16"
}

variable "hosted_zone_id" {
  type        = string
  description = "Route53 hosted zone ID for the domain used for failover records"
}

variable "domain_name" {
  type        = string
  description = "Domain to create records in Route53 (example.com)"
}

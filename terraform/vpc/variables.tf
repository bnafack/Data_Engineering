variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public Subnet CIDR values"
  default     = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]

}


variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private Subnet CIDR values"
  default     = ["10.2.4.0/24", "10.2.5.0/24", "10.2.6.0/24"]
}

variable "azs" {
  type        = list(string)
  description = "Availability Zones"

  default = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

}

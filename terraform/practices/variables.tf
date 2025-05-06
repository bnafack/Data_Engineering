variable "subnets" {
  description = "AWS List of subnets cidr block for a VPC"
  type        = list(string)
}

variable "class_subnet" {
  description = "Subnet categorie public, pivate"
  type        = list(string)
}



variable "vpc_cidr" {
  description = "VPC cidr block"
  type        = string
}

variable "vpc_name" {
  description = "vpc name"
  type        = string

}


variable "rtb_public" {
  description = "Public routable name"
  type        = string

}


variable "public_key" {
  description = "Path to public key"
  type        = string
  sensitive   = true

}



variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "vpc_name" {
  description = "Name of AWS VPC"
  type        = string
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR of AWS VPC"
}

variable "subnets" {
  type        = list(string)
  description = "Name of AWS subnet"
}


variable "subnet_cidr" {
  type        = string
  description = "CIDR of subnet"
}


## instance variable

variable "instances" {
  description = "List of AWS instances"
  type        = list(string)
}

variable "instance_type" {
  description = "Type of AWS instance to deploy"
  type        = string

}

variable "ami_id" {
  description = "ID of amazone machine image"
  type        = string

}

variable "public_key" {
  description = "Path to public key"
  type        = string
  sensitive   = true

}



variable "igw" {
  description = "Name of AWS internet getway"
  type        = string
}


variable "ngw" {
  description = "Name of Nat getway"
  type        = string

}

variable "public_rtb" {
  description = "Name of AWS route table"
  type        = string

}

variable "private_rtb" {
  description = "Name of AWS route table"
  type        = string

}

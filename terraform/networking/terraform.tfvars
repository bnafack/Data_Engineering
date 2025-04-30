vpc_name    = "vpc-dev"
vpc_cidr    = "10.10.0.0/16"
subnet_cidr = "10.10.2.0/24"
subnets     = ["sub-public", "subnet-private"]
igw         = "igw-dev"
ngw         = "ngw-dev"
public_rtb  = "rtb-public"
private_rtb = "rtb-private"


### instance value

instance_type = "t3.nano"
ami_id        = "ami-0ba9cfae65a212e98"
instances     = ["ec2-public", "ec2-private"]
public_key    = "keys/ec2.pub"


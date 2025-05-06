## ICMP for NACLs

When you run the `terraform apply` command, to enable pinging the target resource, update the **inbound NACL rules** by changing the ICMP type from **Echo Reply** to **Echo Request**. This will allow the resource to respond to ping requests properly.

---

### To Properly Use NACLs

You must configure **ephemeral ports for return traffic**. Without this, you will not be able to use this feature correctly, even if your rules appear valid.

This also help to connect to internet to install packages if https is allow. ["0.0.0.0/0"]

---

### EC2 Communication (Private ↔ Public)

To ping an EC2 instance in a **private subnet** from an EC2 in a **public subnet**, attach the **security group** of the public EC2 to its network interface using the following Terraform block:

```hcl
resource "aws_network_interface_sg_attachment" "public" {
  security_group_id    = aws_security_group.sgr_vpc.id
  network_interface_id = aws_instance.dev.primary_network_interface_id
}

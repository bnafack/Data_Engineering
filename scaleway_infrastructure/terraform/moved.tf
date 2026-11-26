# create_public_gateway / create_load_balancer turned these resources into `count` resources.
# These blocks keep the existing resources (and their public IPs) instead of destroying and recreating them.

moved {
  from = scaleway_vpc_public_gateway_ip.gw
  to   = scaleway_vpc_public_gateway_ip.gw[0]
}

moved {
  from = scaleway_vpc_public_gateway.gw
  to   = scaleway_vpc_public_gateway.gw[0]
}

moved {
  from = scaleway_vpc_gateway_network.gw
  to   = scaleway_vpc_gateway_network.gw[0]
}

moved {
  from = scaleway_lb_ip.lb
  to   = scaleway_lb_ip.lb[0]
}

moved {
  from = scaleway_lb.main
  to   = scaleway_lb.main[0]
}

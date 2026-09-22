output "instance_id" {
  value = linode_instance.this.id
}

output "public_ipv4" {
  value = local.public_ipv4
}

output "ipv6_address" {
  value = local.ipv6_address
}

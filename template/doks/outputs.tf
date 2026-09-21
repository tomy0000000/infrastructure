output "cluster_id" {
  value = digitalocean_kubernetes_cluster.this.id
}

output "endpoint" {
  value = digitalocean_kubernetes_cluster.this.endpoint
}

output "kubernetes_version" {
  value = digitalocean_kubernetes_cluster.this.version
}

# Carries a bearer token, and DigitalOcean expires it after 7 days.
output "kubeconfig" {
  value     = digitalocean_kubernetes_cluster.this.kube_config[0].raw_config
  sensitive = true
}

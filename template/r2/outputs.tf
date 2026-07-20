output "bucket_name" {
  value = cloudflare_r2_bucket.this.name
}

output "bucket_id" {
  value = cloudflare_r2_bucket.this.id
}

resource "cloudflare_workers_script" "this" {
  account_id         = var.account_id
  script_name        = var.name
  main_module        = "worker.js"
  compatibility_date = "2026-11-01"
  content = templatefile("${path.module}/worker.js.tftpl", {
    domain = var.domain
    issuer = var.issuer
  })
}

resource "cloudflare_workers_route" "this" {
  zone_id = var.zone_id
  pattern = "${var.domain}/.well-known/webfinger*"
  script  = cloudflare_workers_script.this.script_name
}

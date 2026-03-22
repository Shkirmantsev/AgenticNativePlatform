resource "cloudflare_dns_record" "gateway" {
  zone_id = var.zone_id
  name    = var.record_name
  content = var.record_value
  type    = "A"
  ttl     = 300
  proxied = false
}

# Cloudflare's API has no "purchase a domain" operation; this only manages
# renewal/lock/privacy settings for a domain already registered in the account.
# Buy constantlee.us via the Cloudflare dashboard first, then apply.
resource "cloudflare_registrar_domain" "this" {
  account_id  = var.account_id
  domain_name = var.domain
  auto_renew  = true
  locked      = true
  privacy     = true
}

data "cloudflare_zone" "this" {
  filter = {
    name = var.domain
  }
}

# Every service host resolves through this single record - no per-service
# DNS entries needed. Points at the "homelab" node specifically (not all
# three cluster nodes) since a single target is all that's needed here.
resource "cloudflare_dns_record" "wildcard" {
  zone_id = data.cloudflare_zone.this.id
  name    = "*.${var.domain}"
  type    = "A"
  content = "192.168.8.130"
  ttl     = 300
  proxied = false
}

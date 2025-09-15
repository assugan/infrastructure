data "aws_route53_zone" "root" {
  name         = "${var.domain}."
  private_zone = false
}

resource "aws_route53_record" "root_a" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = var.domain
  type    = "A"
  ttl     = 300
  records = [aws_eip.web.public_ip]
}

resource "aws_route53_record" "www_cname" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = "www.${var.domain}"
  type    = "CNAME"
  ttl     = 300
  records = [var.domain]
}

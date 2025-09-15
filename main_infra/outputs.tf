output "public_ip" {
  value = aws_eip.web.public_ip
}

output "public_dns" {
  value = aws_instance.web.public_dns
}

output "app_url" {
  value = "https://${var.domain}"
}

terraform {
  backend "s3" {
    bucket         = "assugan-tf-state"
    key            = "infra/assugan.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "assugan-tf-lock"
    encrypt        = true
  }
}
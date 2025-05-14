terraform {
  backend "s3" {
    bucket         = "imgrec-terraform-state"
    key            = "state.tfstate"
    region         = "us-east-1"
    dynamodb_table = "imgrec-tf-lock"
    encrypt        = true
  }
} 
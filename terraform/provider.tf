# main.tf
provider "aws" {
  region  = "us-east-1"
}
terraform {
  backend "s3" {
    bucket = "nour-tfstate"  # Match your bucket name
    key    = "terraform.tfstate"              # Path to state file in bucket
    region = "us-east-1"                      # Match your bucket’s region
  }
}


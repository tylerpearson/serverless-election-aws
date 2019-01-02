# This (unfortunately) does not allow variables
# To use these scripts, be sure to change to match your state bucket and profile
terraform {
  backend "s3" {
    bucket  = "election-terraform-state"
    key     = "terraform.tfstate"
    region  = "us-east-1"
    encrypt = "true"
    profile = "election-simulation"
  }
}

# This (unfortunately) does not allow variables
# To use these scripts, be sure to change to match your state bucket and profile
terraform {
  backend "s3" {
    bucket  = "terraform-election-state"
    key     = "terraform.tfstate"
    region  = "us-west-1"
    encrypt = "true"
    profile = "tyler-personal-election"
  }
}

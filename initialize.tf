provider "aws" {
  alias   = "us-east-1-personal"
  region  = "us-east-1"
  profile = "tyler-personal"
}

provider "aws" {
  alias   = "us-east-1"
  region  = "us-east-1"
  profile = "tyler-personal-election"
}

provider "aws" {
  alias   = "us-east-2"
  region  = "us-east-2"
  profile = "tyler-personal-election"
}

provider "aws" {
  alias   = "us-west-1"
  region  = "us-west-1"
  profile = "tyler-personal-election"
}

provider "aws" {
  alias   = "us-west-2"
  region  = "us-west-2"
  profile = "tyler-personal-election"
}

terraform {
  backend "s3" {
    bucket  = "terraform-election-state"
    key     = "terraform.tfstate"
    region  = "us-west-1"
    encrypt = "true"
    profile = "tyler-personal-election"
  }
}

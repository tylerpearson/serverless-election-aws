provider "aws" {
  alias   = "us-east-1"
  region  = "us-east-1"
  profile = "${var.aws_profile_name}"
}

provider "aws" {
  alias   = "us-east-2"
  region  = "us-east-2"
  profile = "${var.aws_profile_name}"
}

provider "aws" {
  alias   = "us-west-1"
  region  = "us-west-1"
  profile = "${var.aws_profile_name}"
}

provider "aws" {
  alias   = "us-west-2"
  region  = "us-west-2"
  profile = "${var.aws_profile_name}"
}

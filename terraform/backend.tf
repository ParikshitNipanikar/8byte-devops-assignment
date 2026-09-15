terraform {
  backend "s3" {
    bucket       = "8byte-terraform-state-385904685559"
    key          = "assignment/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
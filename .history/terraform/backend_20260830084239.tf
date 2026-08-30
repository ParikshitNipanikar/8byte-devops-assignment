cd ~/8byte-devops-assignment/terraform
cat > backend.tf << 'EOF'
terraform {
  backend "s3" {
    bucket         = "8byte-terraform-state-304106859365"
    key            = "assignment/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

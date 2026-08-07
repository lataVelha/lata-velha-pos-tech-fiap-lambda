terraform {
  backend "s3" {
    key = "lata-velha/lambda-auth-cpf/terraform.tfstate"
    # Lock de estado nativo do S3 (sem DynamoDB)
    use_lockfile = true
  }
}

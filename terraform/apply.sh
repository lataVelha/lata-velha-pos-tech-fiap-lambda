#!/usr/bin/env bash
#
# apply.sh — builda as duas lambdas (auth-cpf + jwt-authorizer) e sobe/derruba
# as lambdas (chave JWT + credenciais do RDS vao direto como variavel de
# ambiente da funcao, sem Secrets Manager). Nenhuma das duas tem API Gateway
# proprio — sao anexadas ao UNICO API Gateway do app, criado pelo repo
# infra (addons): auth-cpf como rota POST /auth/cpf, jwt-authorizer como
# aws_apigatewayv2_authorizer nas rotas protegidas.
#
#   (padrão)   npm ci && npm test && npm run build → terraform apply
#   --destroy  terraform destroy (não builda nada)
#
# Pré-requisitos:
#   - repo infra bootstrap (VPC) e infra-db (RDS) já aplicados — este script
#     lê vpc_id/subnets e o endpoint/credenciais do RDS do state deles.
#     infra addons NÃO precisa ter rodado ainda — ao contrário, e este repo
#     que precisa rodar ANTES do infra addons (que le o ARN das duas lambdas
#     daqui). Ordem completa: infra bootstrap → infra-db → lambda (este
#     repo) → infra addons → app.
#   - Node.js 20+ instalado.
#   - cp deploy/terraform.tfvars.example deploy/terraform.tfvars
#     (ou exporte TF_VAR_jwt_private_key_pem / TF_VAR_jwt_public_key_pem —
#     ver comentário no .example)
#
# Uso:
#   ./apply.sh                  — builda e sobe, com confirmação interativa
#   ./apply.sh --auto           — builda e sobe sem confirmação
#   ./apply.sh --skip-build     — pula npm ci/test/build (usa dist/ já existente)
#   ./apply.sh --destroy        — remove as duas lambdas
#                                  (rode DEPOIS de destruir infra addons —
#                                  o API Gateway de lá referencia as duas)
#   ./apply.sh --destroy --auto — remove sem confirmação

set -Eeuo pipefail

# --------------------------- saída no terminal ------------------------------
if [[ -t 1 ]]; then
  C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'; C_RED=$'\033[1;31m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_DIM=''; C_RESET=''
fi

AUTO=""
DESTROY=false
SKIP_BUILD=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto)       AUTO="-auto-approve" ;;
    --destroy)    DESTROY=true ;;
    --skip-build) SKIP_BUILD=true ;;
    *)
      echo "${C_RED}Flag desconhecida: $1${C_RESET}"
      echo "Uso: ./apply.sh [--auto] [--skip-build] [--destroy]"
      exit 1
      ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAMBDA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/deploy"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "${C_BLUE}════════════════════════════════════════════════════════════${C_RESET}"
if $DESTROY; then
  echo "${C_YELLOW}  LAMBDA — Destruindo auth-cpf + jwt-authorizer${C_RESET}"
else
  echo "  LAMBDA — auth-cpf + jwt-authorizer"
fi
echo "${C_BLUE}════════════════════════════════════════════════════════════${C_RESET}"
if $DESTROY; then
  echo "${C_YELLOW}  Confirme que o infra addons já foi destruído antes (ele referencia as duas).${C_RESET}"
fi

if [[ "$DESTROY" == "false" && "$SKIP_BUILD" == "false" ]]; then
  echo "${C_BLUE}==> Instalando dependências, testando e buildando as duas lambdas...${C_RESET}"
  ( cd "$LAMBDA_DIR" && npm ci && npm test && npm run build )
  echo "${C_GREEN}✓ Build concluído (dist/index.js + dist/authorizer.js).${C_RESET}"
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="lata-velha-tfstate-${ACCOUNT_ID}"

echo "${C_DIM}Bucket de estado: $BUCKET${C_RESET}"
if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "${C_DIM}  Bucket não existe — criando...${C_RESET}"
  aws s3 mb "s3://$BUCKET" --region "$REGION"
  aws s3api put-bucket-versioning \
    --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled
  echo "${C_GREEN}  ✓ Bucket criado com versionamento ativado.${C_RESET}"
fi

export TF_VAR_state_bucket="$BUCKET"

terraform -chdir="$DEPLOY_DIR" init -reconfigure \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="region=${REGION}"

if $DESTROY; then
  echo ""
  echo "${C_BLUE}==> Destruindo as lambdas (auth-cpf + jwt-authorizer)...${C_RESET}"
  terraform -chdir="$DEPLOY_DIR" destroy $AUTO
  echo ""
  echo "${C_GREEN}✓ Lambdas destruídas.${C_RESET}"
  exit 0
fi

echo ""
echo "${C_BLUE}==> Provisionando as lambdas (auth-cpf + jwt-authorizer)...${C_RESET}"
terraform -chdir="$DEPLOY_DIR" apply $AUTO

echo ""
echo "${C_GREEN}✓ LAMBDA concluído.${C_RESET} ${C_DIM}Próximo passo: infra addons vai ler estes ARNs e anexar as${C_RESET}"
echo "${C_DIM}  duas lambdas ao único API Gateway (rota /auth/cpf + authorizer).${C_RESET}"
terraform -chdir="$DEPLOY_DIR" output

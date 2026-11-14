# lata-velha-pos-tech-fiap-lambda

Duas Lambdas Python 3.12 (Clean Architecture: `domain → application → infrastructure → handler`)
do projeto **Lata Velha**. Nenhuma tem API Gateway próprio — as duas se anexam ao **único** API
Gateway do repo `infra` (que só cria o "casco": API + VPC Link + Stage, sem rotas). Este repo lê
`app_api_id`/`app_api_execution_arn` de lá via `terraform_remote_state` e anexa:

1. **`auth-cpf`** — `POST /auth/cpf`: login por **CPF + senha**, consultando o **RDS próprio do
   os-service** (`USERS: cpf, credential, roles`). Emite o mesmo JWT RS256 do os-service.
2. **`jwt-authorizer`** — anexada como `aws_apigatewayv2_authorizer` nas rotas protegidas do
   mesmo API Gateway, valida o JWT antes da requisição chegar no ALB.

> **Banco:** a auth-cpf **não usa mais o `infra-db`**. Ela lê o state
> `lata-velha/os-service/terraform.tfstate` para obter endpoint/credenciais do RDS do os-service.
> A rota específica `POST /auth/cpf` no API Gateway tem precedência sobre o
> `ANY /auth/{proxy+}` do stack `edge`.

## Sumário

- [Arquitetura](#arquitetura)
- [Contrato do endpoint (`auth-cpf`)](#contrato-do-endpoint-auth-cpf)
- [Dependências](#dependências)
- [CI/CD (GitHub Actions)](#cicd-github-actions)
- [Configuração (variáveis de ambiente)](#configuração-variáveis-de-ambiente)
- [Execução e deploy](#execução-e-deploy)

---

## Arquitetura

```
cliente ──▶ API Gateway (repo infra, único)
              ├── POST /auth/cpf ──────▶ auth-cpf ──▶ RDS do os-service (USERS: cpf, credential, roles)
              └── ANY /rota-protegida ─▶ jwt-authorizer ─▶ isAuthorized? ─▶ ALB interno ─▶ serviços (EKS)
```

`auth-cpf`: valida CPF → busca usuário no RDS do os-service → confere `ativo` → confere senha
(BCrypt) → assina JWT RS256 com a mesma chave do `app.key`/`app.pub` do os-service.

`jwt-authorizer`: extrai `Authorization: Bearer <token>`, verifica assinatura + issuer +
expiração com a chave pública. Não decide autorização por role (isso continua no
`SecurityConfig` do os-service) — é defesa em profundidade, rejeita cedo requisições sem token
válido.

Código num pacote só (`src/lata_velha_auth/`), camadas iguais ao `app` principal
(`domain → application → infrastructure → handlers`) — o que torna os casos de uso testáveis com
fakes, sem precisar de Postgres real (ver `test/`).

## Contrato do endpoint (`auth-cpf`)

```
POST {app_api_endpoint}auth/cpf
Content-Type: application/json

{ "cpf": "111.444.777-35", "password": "Admin@123" }
```

A base (`app_api_endpoint`) é output do repo `infra` (addons); este repo repassa como próprio
output (`auth_cpf_endpoint`).

| Status | Quando                                                                             |
| ------ | ---------------------------------------------------------------------------------- |
| `200`  | CPF válido, usuário ativo, senha confere — `{ "token", "tokenType", "expiresIn" }` |
| `400`  | CPF ausente/mal formatado                                                          |
| `401`  | Senha ausente ou incorreta                                                         |
| `404`  | Nenhum usuário com esse CPF                                                        |
| `403`  | Usuário inativo                                                                    |
| `500`  | Falha inesperada                                                                   |

Mesma ordem de checagem do `User.login()` do os-service. O token é aceito em qualquer endpoint
protegido dos serviços (o `jwt-authorizer` valida a assinatura antes do ALB).

## Dependências

Lê o remote state do bootstrap e do addons do repo
[`infra`](https://github.com/lataVelha/lata-velha-pos-tech-fiap-infra) (`vpc_id`/subnets;
`app_api_id`/`app_api_execution_arn`) e do **os-service** (`rds_endpoint`/`db_name`/credenciais
do RDS próprio). Não lê o `infra-db`. Publica `jwt_authorizer_id` (edge) e `auth_cpf_endpoint`.

## CI/CD (GitHub Actions)

- **PR** → instala dependências, roda `pytest`, builda (`./build.sh`) e `terraform plan`.
- **Push em `master`** → o mesmo, e aplica de verdade (`terraform apply`).
- **`workflow_dispatch`** (Actions → Run workflow) → dispara manualmente fora de um push, com
  a opção `destroy` pra desfazer.

Expõe `main.yml` como **workflow reusável** (aceita um input `destroy` pra desfazer) — o mono
repo chama este workflow na posição certa do pipeline.

**Secrets/vars do repositório**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`
(AWS Academy), `AWS_REGION` (var, opcional — default `us-east-1`). `TF_JWT_PUBLIC_KEY_PEM` não são obrigatórios — as variáveis já têm como default o conteúdo de
`app.key`/`app.pub`; só cadastre se rotacionar as chaves.

## Configuração (variáveis de ambiente)

Sem Secrets Manager — a chave JWT e as credenciais do RDS do os-service vão direto como
variável de ambiente de cada `aws_lambda_function`.

| Variável                                              | Quem recebe             | Valor                                   |
| ----------------------------------------------------- | ----------------------- | --------------------------------------- |
| `JWT_PRIVATE_KEY`                                     | só `auth-cpf`           | `var.jwt_private_key_pem`               |
| `JWT_PUBLIC_KEY`                                      | só `jwt-authorizer`     | `var.jwt_public_key_pem`                |
| `JWT_ISSUER` / `JWT_EXPIRES_IN`                       | as duas / só `auth-cpf` | `var.jwt_issuer` / `var.jwt_expires_in` |
| `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER`/`DB_PASSWORD` | só `auth-cpf`           | remote state do **os-service**          |

`JWT_PRIVATE_KEY`/`JWT_PUBLIC_KEY` precisam ser exatamente `app.key`/`app.pub` do os-service,
senão o `JwtDecoder` do os-service rejeita os tokens.

## Execução e deploy

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements/dev.txt
pytest -q
./build.sh   # gera build/auth-cpf/ e build/jwt-authorizer/ (wheels Linux x86_64)
```

Pré-requisitos pro deploy: `aws configure`, `infra` bootstrap + addons e o **os-service** já aplicados (o state dele fornece o RDS).

### Com o script (`apply.sh`)

```bash
cd terraform
./apply.sh                    # venv + pytest + build.sh, terraform apply (confirmação interativa)
./apply.sh --auto             # sem confirmação
./apply.sh --skip-build       # usa build/ já existente
./apply.sh --destroy          # remove auth-cpf + jwt-authorizer e as anexações —
                               # rode ANTES do os-service e do infra addons
```

### Manualmente (sem o script)

Útil para depurar um `plan`/`apply` específico ou quando o build já existe.

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements/dev.txt
pytest -q
./build.sh

REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="lata-velha-tfstate-${ACCOUNT_ID}"

cd terraform/deploy
export TF_VAR_state_bucket="$BUCKET"
# addons_state_key/os_service_state_key e as chaves JWT já têm default —
# só exporte se quiser sobrescrever algum

terraform init \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="region=${REGION}"
terraform plan
terraform apply
terraform destroy   # remove as duas lambdas — rode ANTES do os-service e do infra addons
```

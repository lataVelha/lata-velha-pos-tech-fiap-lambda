# lata-velha-pos-tech-fiap-lambda

Duas Lambdas Python 3.12 (Clean Architecture: `domain → application → infrastructure → handler`)
do projeto **Lata Velha**. Nenhuma tem API Gateway próprio — as duas se anexam ao **único** API
Gateway do repo `infra` (que só cria o "casco": API + VPC Link + Stage, sem rotas). Este repo lê
`app_api_id`/`app_api_execution_arn` de lá via `terraform_remote_state` e anexa:

1. **`auth-cpf`** — `POST /auth/cpf`: login por **CPF + senha**, alternativa ao `/auth/login`
   (email/senha) do app. Confere a senha contra o mesmo hash BCrypt (`USERS.CREDENTIAL`) e emite
   o mesmo tipo de JWT.
2. **`jwt-authorizer`** — anexada como `aws_apigatewayv2_authorizer` nas rotas protegidas do
   mesmo API Gateway (criadas pelo repo `app`), valida o JWT antes da requisição chegar no ALB.

## Sumário

- [Arquitetura](#arquitetura)
- [Contrato do endpoint (`auth-cpf`)](#contrato-do-endpoint-auth-cpf)
- [Dependências e ordem do pipeline](#dependências-e-ordem-do-pipeline)
- [CI/CD (GitHub Actions)](#cicd-github-actions)
- [Configuração (variáveis de ambiente)](#configuração-variáveis-de-ambiente)
- [Execução e deploy](#execução-e-deploy)

---

## Arquitetura

```
cliente ──▶ API Gateway (repo infra, único)
              ├── POST /auth/cpf ──────▶ auth-cpf ──▶ RDS Postgres (USERS: cpf, credential, roles)
              └── ANY /rota-protegida ─▶ jwt-authorizer ─▶ isAuthorized? ─▶ ALB interno ─▶ app (EKS)
```

`auth-cpf`: valida CPF → busca usuário → confere `ativo` → confere senha (BCrypt) → assina JWT
RS256 com a mesma chave privada do app (`sub`/`scope` no mesmo formato que `SecurityConfig.java`
espera). É só outro meio de login, não substitui o `/auth/login` por email/senha.

`jwt-authorizer`: extrai `Authorization: Bearer <token>`, verifica assinatura + issuer +
expiração com a chave pública. Não decide autorização por role (isso é só do `SecurityConfig.java`
do app) — é defesa em profundidade, rejeita cedo requisições sem token válido.

Código num pacote só (`src/lata_velha_auth/`), camadas iguais ao `app` principal
(`domain → application → infrastructure → handlers`) — o que torna os casos de uso testáveis com
fakes, sem precisar de Postgres real (ver `test/`).

## Contrato do endpoint (`auth-cpf`)

```
POST {app_api_endpoint}auth/cpf
Content-Type: application/json

{ "cpf": "111.444.777-35", "password": "Admin@123" }
```

A base (`app_api_endpoint`) é output do repo `infra` (addons) — este repo repassa como próprio
output (`auth_cpf_endpoint`).

| Status | Quando                                                                             |
| ------ | ---------------------------------------------------------------------------------- |
| `200`  | CPF válido, usuário ativo, senha confere — `{ "token", "tokenType", "expiresIn" }` |
| `400`  | CPF ausente/mal formatado                                                          |
| `401`  | Senha ausente ou incorreta                                                         |
| `404`  | Nenhum usuário com esse CPF                                                        |
| `403`  | Usuário inativo                                                                    |
| `500`  | Falha inesperada                                                                   |

Mesma ordem de checagem do `User.login()` do app. O token é aceito em qualquer endpoint
protegido do app.

## Dependências e ordem do pipeline

Lê o remote state do `infra` bootstrap (`vpc_id`/subnets, só `auth-cpf` usa pra alcançar o RDS),
do `infra-db` (credenciais do RDS, só `auth-cpf`) e do `infra` **addons** (`app_api_id`/
`app_api_execution_arn`, pra anexar a rota/authorizer). O `jwt_authorizer_id` criado aqui é lido
pelo repo `app`, que o usa nas próprias rotas protegidas.

Ordem: `infra` bootstrap → `infra` addons → `infra-db` → **`lambda`** → `app`.

## CI/CD (GitHub Actions)

- **PR** → instala dependências, roda `pytest`, builda (`./build.sh`) e `terraform plan`.
- **Push em `master`** → só a CI acima — não aplica nada de verdade.
- **`workflow_dispatch`** (Actions → Run workflow) → o deploy de verdade (`terraform apply`).

Expõe `main.yml` como **workflow reusável** (aceita um input `destroy` pra desfazer) — o mono
repo chama este workflow na posição certa do pipeline.

**Secrets/vars do repositório**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`
(AWS Academy), `AWS_REGION` (var, opcional — default `us-east-1`). `TF_JWT_PRIVATE_KEY_PEM`/
`TF_JWT_PUBLIC_KEY_PEM` não são obrigatórios — as variáveis já têm como default o conteúdo de
`app.key`/`app.pub`; só cadastre se rotacionar as chaves.

## Configuração (variáveis de ambiente)

Sem Secrets Manager — a chave JWT e as credenciais do RDS vão direto como variável de ambiente
de cada `aws_lambda_function`.

| Variável                                              | Quem recebe             | Valor                                   |
| ----------------------------------------------------- | ----------------------- | --------------------------------------- |
| `JWT_PRIVATE_KEY`                                     | só `auth-cpf`           | `var.jwt_private_key_pem`               |
| `JWT_PUBLIC_KEY`                                      | só `jwt-authorizer`     | `var.jwt_public_key_pem`                |
| `JWT_ISSUER` / `JWT_EXPIRES_IN`                       | as duas / só `auth-cpf` | `var.jwt_issuer` / `var.jwt_expires_in` |
| `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER`/`DB_PASSWORD` | só `auth-cpf`           | remote state do `infra-db`              |

`JWT_PRIVATE_KEY`/`JWT_PUBLIC_KEY` precisam ser exatamente `app.key`/`app.pub` do repo `app`,
senão o `JwtDecoder` do app rejeita os tokens.

## Execução e deploy

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements/dev.txt
pytest -q
./build.sh   # gera build/auth-cpf/ e build/jwt-authorizer/ (wheels Linux x86_64)
```

Pré-requisitos pro deploy: `aws configure`, `infra` bootstrap + addons + `infra-db` já aplicados.

```bash
cd terraform
./apply.sh                    # venv + pytest + build.sh, terraform apply (confirmação interativa)
./apply.sh --auto             # sem confirmação
./apply.sh --skip-build       # usa build/ já existente
./apply.sh --destroy          # remove as duas lambdas + a anexação no API Gateway —
                               # rode ANTES de destruir o infra addons
```

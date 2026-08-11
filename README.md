# lata-velha-pos-tech-fiap-lambda

Duas Lambdas (**Python 3.12**, Clean Architecture: `domain → application → infrastructure → handler`,
mesma disciplina do `app` principal) do projeto **Lata Velha**. Nenhuma tem API Gateway próprio —
as duas são anexadas ao **único** API Gateway do repo `infra`. Diferente de antes, é **este
repo** que faz a anexação (rota, integração, `aws_apigatewayv2_authorizer`) — o `infra` só cria
o "casco" do Gateway (API + VPC Link + Stage, sem rotas); este repo lê `app_api_id`/
`app_api_execution_arn` dele via `terraform_remote_state` e anexa:

1. **`auth-cpf`** — `POST /auth/cpf`: login por **CPF + senha**, alternativa ao `/auth/login`
   (email/senha) do app. Emite o mesmo tipo de JWT, conferindo a senha contra o mesmo hash BCrypt
   (`USERS.CREDENTIAL`).
2. **`jwt-authorizer`** — anexada como `aws_apigatewayv2_authorizer` nas rotas protegidas do
   mesmo API Gateway, valida o JWT antes da requisição chegar no ALB.

## Sumário

- [Arquitetura](#arquitetura)
- [Camadas (Clean Architecture)](#camadas-clean-architecture)
- [Contrato do endpoint (`auth-cpf`)](#contrato-do-endpoint-auth-cpf)
- [Dependências e ordem do pipeline](#dependências-e-ordem-do-pipeline)
- [CI/CD (GitHub Actions)](#cicd-github-actions)
- [Configuração (variáveis de ambiente)](#configuração-variáveis-de-ambiente)
- [Execução e deploy](#execução-e-deploy)
- [Notas de segurança](#notas-de-segurança)

---

## Arquitetura

```
cliente ──▶ API Gateway (repo infra, único)
              ├── POST /auth/cpf ──────▶ auth-cpf ──▶ RDS Postgres (USERS: cpf, credential, roles)
              └── ANY /rota-protegida ─▶ jwt-authorizer ─▶ isAuthorized? ─▶ ALB interno ─▶ app (EKS)
```

`auth-cpf`: valida CPF → busca usuário → confere `ativo` → confere senha (**BCrypt**, mesmo
algoritmo do `BCryptPasswordEncoder`/`PasswordHasherImpl` do app) → assina JWT **RS256** com a
mesma chave privada do app (`sub` = UUID do usuário, `scope` = roles separadas por espaço — mesmo
formato que `SecurityConfig.java` já espera). É só outro meio de fazer login, não uma
substituição — a equipe decidiu manter os dois: o login por email/senha no app e este por CPF.

`jwt-authorizer`: extrai `Authorization: Bearer <token>`, verifica assinatura RS256 + issuer +
expiração com a chave pública. Não decide autorização por role (isso é só do `SecurityConfig.java`
do app) — é defesa em profundidade, rejeita cedo requisições sem token válido.

## Camadas (Clean Architecture)

Um pacote só (`lata_velha_auth/`), compartilhado pelas duas lambdas, com as mesmas camadas do
`app` principal: `domain` (regras puras — CPF, `UserAuth`, exceções, zero import externo) →
`application` (casos de uso `AuthenticateByCpfUseCase`/`AuthorizeTokenUseCase` + `ports`,
interfaces que só dependem do `domain`) → `infrastructure` (implementa as `ports`:
`PostgresUserRepository`, `BcryptPasswordVerifier`, `JwtTokenSigner`/`JwtTokenVerifier`) →
`handlers` (entrypoint de cada lambda + composition root). A dependência é sempre pra dentro —
isso é o que torna `AuthenticateByCpfUseCase` testável com repositório/assinador **fake**, sem
precisar de Postgres nem mock de biblioteca (ver `test/test_authenticate_by_cpf_use_case.py`).

## Contrato do endpoint (`auth-cpf`)

```
POST {app_api_endpoint}auth/cpf
Content-Type: application/json

{ "cpf": "111.444.777-35", "password": "Admin@123" }
```

A base (`app_api_endpoint`) é output do repo `infra` (`terraform/addons`) — este repo lê esse
valor e expõe o endpoint completo como próprio output (`auth_cpf_endpoint`).

| Status | Quando                                                                                             |
| ------ | -------------------------------------------------------------------------------------------------- |
| `200`  | CPF válido, usuário existe, está ativo e a senha confere — `{ "token", "tokenType", "expiresIn" }` |
| `400`  | CPF ausente/mal formatado                                                                          |
| `401`  | Senha ausente ou incorreta                                                                         |
| `404`  | Nenhum usuário com esse CPF                                                                        |
| `403`  | Usuário inativo                                                                                    |
| `500`  | Falha inesperada                                                                                   |

A ordem de checagem (CPF → existe → ativo → senha) é a mesma do `User.login()` do app. O token é
aceito em qualquer endpoint protegido do app.

```
src/lata_velha_auth/
├── domain/                 # cpf.py, user.py, errors.py
├── application/            # ports.py + authenticate_by_cpf.py + authorize_token.py (use cases)
├── infrastructure/         # config.py, postgres_user_repository.py (pg8000),
│                           # bcrypt_password_verifier.py, jwt_token_service.py (PyJWT)
└── handlers/                # auth_cpf_handler.py + authorizer_handler.py (entrypoint + composition root)
test/                     # pytest — um arquivo por módulo testado
requirements/              # auth-cpf.txt (PyJWT+pg8000+bcrypt), jwt-authorizer.txt (só PyJWT), dev.txt
build.sh                   # empacota build/auth-cpf/ e build/jwt-authorizer/ (mesmo pacote copiado
                            # nas duas, wheels Linux x86_64 — funciona rodando em qualquer SO)
terraform/
├── apply.sh                # venv + pytest + build.sh, depois apply/destroy local
├── modules/                 # auth-cpf-lambda (com VPC) e jwt-authorizer-lambda (sem VPC)
└── deploy/                  # raiz do terraform deste repo (state próprio)
```

## Dependências e ordem do pipeline

- Lê o remote state do bootstrap do repo `infra` (`vpc_id`, `private_subnet_ids` — só `auth-cpf`
  usa, pra alcançar o RDS), do `infra-db` (`rds_endpoint`, credenciais — só `auth-cpf`) e do
  `infra` **addons** (`app_api_id`, `app_api_execution_arn` — pra anexar a rota/authorizer no
  API Gateway).
- Este repo cria a própria `aws_apigatewayv2_authorizer`, cujo `id` (`jwt_authorizer_id`) é
  lido pelo repo `app` — as rotas protegidas do app referenciam essa authorizer.

Ordem: `infra` bootstrap → `infra` addons → `infra-db` → **`lambda`** → `app`. Diferente de
antes, este repo não precisa mais rodar antes do `infra` addons — é o contrário: lê o `api_id`
que o addons já criou.

## CI/CD (GitHub Actions)

- **PR** → instala dependências, roda `pytest`, builda (`./build.sh`) e `terraform plan`.
- **Push em `master`** → só a CI acima (testes/build/plan) — não aplica nada de verdade.
- **`workflow_dispatch`** (Actions → Run workflow) → o deploy de verdade (`terraform apply`).

Expõe `main.yml` como **workflow reusável** (`workflow_call`, aceita um input `destroy` pra
desfazer) — o mono repo chama este workflow na posição certa do pipeline
(`uses: lataVelha/lata-velha-pos-tech-fiap-lambda/.github/workflows/main.yml@master`).

**Secrets/vars do repositório**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`
(AWS Academy), `AWS_REGION` (var, opcional — default `us-east-1`). `TF_JWT_PRIVATE_KEY_PEM`/
`TF_JWT_PUBLIC_KEY_PEM` não são obrigatórios — as variáveis Terraform já têm como default o
conteúdo de `app.key`/`app.pub`; só cadastre se rotacionar as chaves.

## Configuração (variáveis de ambiente)

Sem Secrets Manager — a chave JWT e as credenciais do RDS vão direto como variável de ambiente de
cada `aws_lambda_function`, lidas de `os.environ` no cold start.

| Variável                                              | Quem recebe                    | Valor                      |
| ----------------------------------------------------- | ------------------------------ | -------------------------- |
| `JWT_PRIVATE_KEY`                                     | só `auth-cpf` (assina)         | `var.jwt_private_key_pem`  |
| `JWT_PUBLIC_KEY`                                      | só `jwt-authorizer` (verifica) | `var.jwt_public_key_pem`   |
| `JWT_ISSUER`                                          | as duas                        | `var.jwt_issuer`           |
| `JWT_EXPIRES_IN`                                      | só `auth-cpf`                  | `var.jwt_expires_in`       |
| `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER`/`DB_PASSWORD` | só `auth-cpf`                  | remote state do `infra-db` |

`JWT_PRIVATE_KEY`/`JWT_PUBLIC_KEY` precisam ser exatamente `app.key`/`app.pub` do repo `app`,
senão o `JwtDecoder` do app rejeita os tokens — os defaults em `terraform/deploy/variables.tf` já
têm esse conteúdo, não precisa configurar nada pra testar local.

## Execução e deploy

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements/dev.txt
pytest -q             # domain, application (fakes), infrastructure (crypto real) e handlers
./build.sh              # gera build/auth-cpf/ e build/jwt-authorizer/ — wheels Linux x86_64,
                         # baixadas via pip mesmo rodando em macOS/Windows, sem compilar nada local
```

Pré-requisitos pro deploy: `aws configure`, Python 3.9+ (só pra testar local), `infra` bootstrap +
`infra-db` já aplicados.

```bash
cd terraform
./apply.sh                    # venv + pytest + build.sh, terraform apply (confirmação interativa)
./apply.sh --auto             # sem confirmação
./apply.sh --skip-build       # usa build/ já existente
./apply.sh --destroy          # remove as duas lambdas e a anexação delas no API Gateway —
                               # rode ANTES de destruir o infra addons (a rota/authorizer daqui
                               # referenciam o api_id dele); apply.sh --destroy da raiz já faz
                               # isso na ordem certa
```

Manualmente (sem o script): `pip install -r requirements/dev.txt && pytest -q && ./build.sh`,
depois `terraform init`/`plan`/`apply` em `terraform/deploy` (backend S3, `-backend-config="bucket=<state_bucket>"`).

## Notas de segurança

- **Senha verificada com BCrypt** (mesmo algoritmo do app) — testado contra um hash real do seed
  em `test/test_bcrypt_password_verifier.py`. Nunca logada nem persistida.
- **Sem throttling dedicado** em `POST /auth/cpf` (CPF tem baixa entropia, é potencialmente
  força-bruta-ável) — o `aws_apigatewayv2_stage` que suportaria isso agora é criado pelo repo
  `infra`, que não conhece essa rota no momento em que cria o stage. Rate-limit ficaria por
  conta de uma regra WAFv2 (fora do escopo atual).
- **Chave privada RSA em texto puro** em `terraform/deploy/variables.tf` (default da variável
  `jwt_private_key_pem`, mesma chave de `app.key` no repo `app`) — como este repo é público,
  essa chave está exposta. Rotacionar (gerar par novo, atualizar aqui e no `app`) se isso for
  uma preocupação real além do escopo acadêmico do projeto.

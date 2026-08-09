# lata-velha-pos-tech-fiap-lambda

Duas Lambdas (**Python 3.12**, Clean Architecture: `domain → application → infrastructure → handler`,
mesma disciplina do `app` principal) do projeto **Lata Velha**. Nenhuma tem API Gateway próprio —
as duas são anexadas ao **único** API Gateway do repo `infra` (módulo `app-gateway`), que lê o ARN
de cada uma via `terraform_remote_state`:

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

Dois **projetos Python independentes** (`auth_cpf/`, `jwt_authorizer/`), cada um com suas
próprias camadas `domain`/`application`/`infrastructure` + `handler.py` (entrypoint +
composition root), e um pacote **`shared/`** com o que as duas genuinamente precisam: `env.py`
e `jwt_token_service.py` (`JwtTokenSigner`/`JwtTokenVerifier`, PyJWT). `shared/` nunca importa
nada de `auth_cpf`/`jwt_authorizer` — as `ports` de cada projeto usam `typing.Protocol` (tipagem
estrutural) em vez de `ABC`, então `JwtTokenSigner`/`JwtTokenVerifier` satisfazem as interfaces
esperadas sem herdar nada de lá. Isso é o que torna `AuthenticateByCpfUseCase` testável com
repositório/assinador **fake**, sem precisar de Postgres nem mock de biblioteca (ver
`test/test_authenticate_by_cpf_use_case.py`).

## Contrato do endpoint (`auth-cpf`)

```
POST {app_api_endpoint}auth/cpf
Content-Type: application/json

{ "cpf": "111.444.777-35", "password": "Admin@123" }
```

`app_api_endpoint` é output do repo `infra` (`terraform/addons`).

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
src/
├── shared/                # env.py + jwt_token_service.py (JwtTokenSigner + JwtTokenVerifier)
├── auth_cpf/               # projeto 1 — POST /auth/cpf
│   ├── domain/              # cpf.py, user.py, errors.py
│   ├── application/         # ports.py + authenticate_by_cpf.py (use case)
│   ├── infrastructure/      # config.py, postgres_user_repository.py (pg8000), bcrypt_password_verifier.py
│   └── handler.py           # entrypoint + composition root
└── jwt_authorizer/         # projeto 2 — authorizer do API Gateway
    ├── application/          # ports.py + authorize_token.py
    ├── infrastructure/       # config.py
    └── handler.py            # entrypoint + composition root
test/                     # pytest — um arquivo por módulo testado
requirements/              # auth-cpf.txt (PyJWT+pg8000+bcrypt), jwt-authorizer.txt (só PyJWT), dev.txt
build.sh                   # empacota build/auth-cpf/ e build/jwt-authorizer/ (shared/ + o projeto
                            # de cada uma, wheels Linux x86_64 — funciona rodando em qualquer SO)
terraform/
├── apply.sh                # venv + pytest + build.sh, depois apply/destroy local
├── modules/                 # auth-cpf-lambda (com VPC) e jwt-authorizer-lambda (sem VPC)
└── deploy/                  # raiz do terraform deste repo (state próprio)
```

## Dependências e ordem do pipeline

- Lê o remote state do bootstrap do repo `infra` (`vpc_id`, `private_subnet_ids` — só `auth-cpf`
  usa, pra alcançar o RDS) e do `infra-db` (`rds_endpoint`, credenciais — só `auth-cpf`).
- Os outputs deste repo (ARNs das duas lambdas) são o que o módulo `app-gateway` do `infra` usa
  pra anexar a authorizer e criar a rota `/auth/cpf` — por isso precisa rodar **antes** do
  `infra` addons.

Ordem: `infra` bootstrap → `infra-db` → **`lambda`** → `infra` addons → `app`.

## CI/CD (GitHub Actions)

- **PR** → instala dependências, roda `pytest`, builda (`./build.sh`) e `terraform plan`.
- **Push em `master`** → o mesmo, e aplica (`terraform apply`).

Expõe `main.yml` como **workflow reusável** (`workflow_call`) — o `apply.sh` da raiz do mono repo
chama este workflow na posição certa do pipeline. Um push direto aqui não dispara o `infra`
addons sozinho; use o `apply.sh` da raiz para o pipeline completo.

**Secrets/vars do repositório**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`
(AWS Academy), `AWS_REGION` (var). `TF_JWT_PRIVATE_KEY_PEM`/`TF_JWT_PUBLIC_KEY_PEM` não são
obrigatórios — as variáveis Terraform já têm como default o conteúdo de `app.key`/`app.pub`; só
cadastre se rotacionar as chaves.

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
./apply.sh --destroy          # remove as duas lambdas — SÓ depois do infra addons já destruído
                               # (ele referencia as duas); apply.sh --destroy da raiz já faz isso certo
```

Manualmente (sem o script): `pip install -r requirements/dev.txt && pytest -q && ./build.sh`,
depois `terraform init`/`plan`/`apply` em `terraform/deploy` (backend S3, `-backend-config="bucket=<state_bucket>"`).

## Notas de segurança

- **Throttling** próprio em `POST /auth/cpf` no API Gateway (10 req/s sustentado, 20 de rajada).
- **Senha verificada com BCrypt** (mesmo algoritmo do app)
  um hash real do seed em `test/test_bcrypt_password_verifier.py`. Nunca logada nem persistida.

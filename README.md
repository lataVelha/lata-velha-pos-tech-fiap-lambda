# lata-velha-pos-tech-fiap-lambda

Duas functions serverless (AWS Lambda) do projeto **Lata Velha**. Nenhuma das duas tem API
Gateway próprio — as duas são anexadas ao **único** API Gateway do app (repo `infra`, módulo
`app-gateway`), que lê o ARN de cada uma via `terraform_remote_state`:

1. **`auth-cpf`** — autenticação por CPF, integrada como rota `POST /auth/cpf` (AWS_PROXY, pública). Fica ao lado do login por email/senha do app (`/auth/login`, ver `authentication/api/controllers/LoginController.java`) — não o substitui — como uma segunda porta de entrada que emite o mesmo tipo de JWT a partir de um CPF cadastrado na tabela `USERS`.
2. **`jwt-authorizer`** — anexada como `aws_apigatewayv2_authorizer` nas rotas protegidas do mesmo API Gateway, valida o JWT antes da requisição chegar no ALB.

## Sumário

- [Arquitetura](#arquitetura)
- [Contrato do endpoint (`auth-cpf`)](#contrato-do-endpoint-auth-cpf)
- [A lambda authorizer (`jwt-authorizer`)](#a-lambda-authorizer-jwt-authorizer)
- [Estrutura](#estrutura)
- [Dependências](#dependências)
- [O segredo (Secrets Manager)](#o-segredo-secrets-manager)
- [Execução local (código)](#execução-local-código)
- [Deploy (Terraform)](#deploy-terraform)
- [Notas de segurança](#notas-de-segurança)

---

## Arquitetura

```
                              ┌── POST /auth/cpf ───────▶ Lambda auth-cpf ──▶ RDS Postgres (tabela USERS)
                              │                                │
cliente ──▶ API Gateway (repo infra, único) ─┤                                ▼
                              │                                Secrets Manager
                              │                          (chave RSA priv+pub + credenciais RDS)
                              │                                ▲
                              └── ANY /rota-protegida ──▶ Lambda jwt-authorizer (só lê a chave pública)
                                          │ isAuthorized?
                                          ▼
                                  ALB interno ──▶ app (Spring Boot / EKS)
```

**`auth-cpf`**:
1. Valida o formato/dígito verificador do CPF recebido.
2. Consulta a tabela `USERS` (a mesma do app) por `cpf`, junto das `roles` associadas via `USER_ROLES`/`ROLE`.
3. Se não existe → `404`. Se existe mas `ativo = false` → `403`.
4. Se ativo, assina um JWT **RS256** com a mesma chave privada que o app usa (`JwtTokenProvider.java`) e devolve. O `sub` é o UUID do `USERS.ID` e o `scope` são as roles do usuário separadas por espaço — exatamente o formato que `SecurityConfig.java`/`JwtAuthenticationConverter` do app já esperam. Nenhuma role nova foi criada: o token carrega as roles reais do usuário (`ADMIN`, `USER`, `MECANICO`, `ATENDENTE`), então ele abre exatamente o que aquele usuário já teria acesso via login por senha.

O login por email/senha do app continua funcionando sem nenhuma alteração — esta function é só um caminho alternativo para obter o mesmo tipo de token.

## Contrato do endpoint (`auth-cpf`)

```
POST {app_api_endpoint}auth/cpf
Content-Type: application/json

{ "cpf": "111.444.777-35" }
```

`app_api_endpoint` é output do repo `infra` (`terraform/addons`, também disponível pronto em `auth_cpf_endpoint`) — não deste repo.

| Status | Quando | Corpo |
|---|---|---|
| `200` | CPF válido, usuário existe e está ativo | `{ "token": "<jwt>", "tokenType": "Bearer", "expiresIn": 3600 }` |
| `400` | CPF ausente, mal formatado ou com dígito verificador inválido | `{ "error": "CPF invalido" }` |
| `404` | Nenhum usuário cadastrado com esse CPF | `{ "error": "Usuario nao encontrado para o CPF informado" }` |
| `403` | Usuário existe mas está inativo (`ATIVO = false`) | `{ "error": "Usuario inativo" }` |
| `500` | Falha inesperada (ex.: banco indisponível) | `{ "error": "Erro interno" }` |

O `token` retornado é aceito em qualquer endpoint protegido do app, no header `Authorization: Bearer <token>`, igual ao token de `/auth/login`.

## A lambda authorizer (`jwt-authorizer`)

Anexada como `aws_apigatewayv2_authorizer` (tipo `REQUEST`, `enable_simple_responses`) nas
rotas protegidas do API Gateway do app (repo `infra`, módulo `app-gateway`) — ver o
`README.md` de lá para a lista de rotas públicas x protegidas. Recebe o evento de
autorização do API Gateway v2, extrai o header `Authorization: Bearer <token>` e:

1. Sem header ou sem prefixo `Bearer ` → `{ "isAuthorized": false }` (API Gateway responde `401`).
2. Verifica a assinatura **RS256** com a chave pública do mesmo secret da `auth-cpf`, e o `issuer`. Assinatura inválida, expirado ou issuer errado → `{ "isAuthorized": false }`.
3. Válido → `{ "isAuthorized": true, "context": { "sub": "...", "scope": "..." } }`.

Ela **não decide autorização por role** — só "esse token é válido ou não". Quem decide se
`ADMIN`/`USER`/`MECANICO` pode acessar cada rota continua sendo exclusivamente o
`SecurityConfig.java` do app. É uma duplicação intencional (defesa em profundidade): rejeita
cedo, no edge, requisições sem um token válido, sem gastar um hop até o ALB/pod.

Diferente da `auth-cpf`, essa função **não roda na VPC** (não acessa o RDS, só verifica uma
assinatura com a chave pública que já está no secret) — cold start bem mais rápido.

## Estrutura

```
src/                            # código das duas lambdas (Node.js + TypeScript)
├── handler.ts                   # entrypoint da auth-cpf (API Gateway proxy v2)
├── authorizerHandler.ts         # entrypoint da jwt-authorizer (API Gateway REQUEST authorizer v2)
├── cpf.ts                       # validação de CPF (mesmo algoritmo do Documento.java do app)
├── db.ts                        # consulta USERS por cpf (pg) — só a auth-cpf usa
├── jwtSigner.ts                  # assina o JWT RS256 com a chave do secret — só a auth-cpf usa
├── secretsManager.ts             # busca + cacheia o secret (Secrets Manager) — as duas usam
├── config.ts                     # variáveis de ambiente
└── httpError.ts                   # erros tipados (400/403/404) — só a auth-cpf usa
test/                            # jest
terraform/
├── apply.sh                      # build + apply/destroy local (builda as duas lambdas)
├── modules/
│   ├── auth-cpf-lambda/          # IAM role, SG, VPC, lambda — sem API Gateway proprio
│   └── jwt-authorizer-lambda/    # IAM role, lambda (sem VPC) — sem API Gateway proprio
└── deploy/                       # raiz do terraform deste repo (state próprio)
```

## Dependências

- **Lê** o remote state do bootstrap do repo [`infra`](https://github.com/lataVelha/lata-velha-pos-tech-fiap-infra) (`vpc_id`, `private_subnet_ids`) — a `auth-cpf` roda dentro da VPC porque o RDS só aceita conexões de dentro dela. A `jwt-authorizer` não usa isso (não roda na VPC).
- **Lê** o remote state do repo [`infra-db`](https://github.com/lataVelha/lata-velha-pos-tech-fiap-infra-db) (`rds_endpoint`, `db_name`, `db_username`, `db_password`) — só a `auth-cpf` usa.
- Precisa rodar **depois** de `infra` bootstrap e `infra-db`, e **antes** de `infra` addons — os outputs `jwt_authorizer_invoke_arn`/`jwt_authorizer_function_name` deste repo são o que o módulo `app-gateway` do `infra` usa para anexar a authorizer nas rotas protegidas (ver `infra/README.md`).
- Não depende do deploy do `app` nem o `app` depende deste repo — são independentes na infra, só compartilham a chave JWT (ver abaixo).

Ordem de pipeline: `infra` bootstrap → `infra-db` → **`lambda`** → `infra` addons → `app`.

## O segredo (Secrets Manager)

O Terraform cria um secret `<project_name>/auth-cpf-lambda` com este formato (a lambda lê em runtime, com cache entre invocações quentes):

```json
{
  "jwtPrivateKey": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
  "jwtPublicKey":  "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----\n",
  "jwtIssuer":     "lata-velha",
  "jwtExpiresIn":  3600,
  "dbHost":        "...",
  "dbPort":        5432,
  "dbName":        "lata_velha",
  "dbUser":        "...",
  "dbPassword":    "..."
}
```

`dbHost`/`dbPort`/`dbName`/`dbUser`/`dbPassword` vêm automaticamente do remote state do `infra-db`. `jwtPrivateKey`/`jwtPublicKey` precisam ser exatamente o conteúdo de `app/src/main/resources/app.key` e `app.pub` do repo `app`, senão o `JwtDecoder` do app (que só conhece a chave pública dele) rejeita os tokens emitidos por esta lambda — as variáveis `jwt_private_key_pem`/`jwt_public_key_pem` já vêm com esse conteúdo como **default**, então não precisa exportar nada pra testar local. Se algum dia rotacionar essas chaves no app, atualize os defaults em `terraform/deploy/variables.tf` junto. Em CI, os secrets `TF_JWT_PRIVATE_KEY_PEM`/`TF_JWT_PUBLIC_KEY_PEM` sempre sobrescrevem o default.

As duas lambdas (`auth-cpf` e `jwt-authorizer`) leem o **mesmo secret** — a `jwt-authorizer` só usa o campo `jwtPublicKey`.

## Execução local (código)

```bash
npm ci
npm test               # jest — cpf.ts, handler.ts e authorizerHandler.ts (com db/secretsManager mockados)
npm run build           # esbuild -> dist/index.js (auth-cpf) + dist/authorizer.js (jwt-authorizer)
npm run build:login      # so a auth-cpf
npm run build:authorizer # so a jwt-authorizer
```

## Deploy (Terraform)

Pré-requisitos: `aws configure` (ou variáveis `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN`), Node.js 20+, e os repos `infra` bootstrap + `infra-db` já aplicados (`infra` addons roda **depois** deste repo, não antes — ver [Dependências](#dependências)).

```bash
cp terraform/deploy/terraform.tfvars.example terraform/deploy/terraform.tfvars
# edite com o state_bucket, ou prefira exportar TF_VAR_jwt_private_key_pem /
# TF_VAR_jwt_public_key_pem em vez de colar a chave num arquivo local
```

### Com o script (`apply.sh`)

```bash
cd terraform
./apply.sh                    # npm ci + test + build, depois terraform apply (confirmação interativa)
./apply.sh --auto             # sem confirmação
./apply.sh --skip-build       # pula o build do Node (usa dist/ já existente)
./apply.sh --destroy          # remove as duas lambdas + secret
./apply.sh --destroy --auto   # remove sem confirmação
```

> **Ordem do destroy:** este repo precisa ser destruído **depois** do `infra` addons, não
> antes — o módulo `app-gateway` de lá referencia as duas lambdas (`aws_apigatewayv2_authorizer`
> e a integração de `POST /auth/cpf`), então destruir as lambdas primeiro quebraria essas
> referências. `apply.sh --destroy` da raiz do mono repo já faz isso na ordem certa.

### Manualmente

```bash
npm ci && npm test && npm run build   # gera dist/, que o terraform empacota

cd terraform/deploy
terraform init \
  -backend-config="bucket=<state_bucket>" \
  -backend-config="region=us-east-1"

terraform plan
terraform apply
```

## Notas de segurança

- **Throttling**: a rota `POST /auth/cpf` tem rate limit próprio no API Gateway (repo `infra`, módulo `app-gateway`, `auth_cpf_throttling_rate_limit`/`auth_cpf_throttling_burst_limit`, padrão 10 req/s sustentado e 20 de rajada) — só nessa rota, não na API inteira — para dificultar brute-force de CPF (baixa entropia: dígitos verificadores são calculados, não aleatórios).
- **`app.key`/`app.pub` estão versionados em texto plano no repo `app`** (`src/main/resources/`). Isso já era verdade antes desta function existir. Ao configurar o secret desta lambda, considere rotacionar esse par de chaves (gerar um novo, atualizar `app.key`/`app.pub` no app e o secret aqui juntos) em vez de reutilizar o par exposto — fora do escopo desta function, mas vale um follow-up.
- O secret nunca deve ir para `terraform.tfvars` versionado — use variáveis de ambiente `TF_VAR_*` (ver exemplo acima) ou um secret de CI, como já é feito para `db_password` nos outros repos.

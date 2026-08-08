import { Pool } from "pg";
import type { AuthCpfConfig } from "./config";

export interface UserAuth {
  id: string; // UUID — vira o "sub" do JWT, no mesmo formato que o app espera (UserId)
  username: string;
  ativo: boolean;
  roles: string[];
}

// Pool cacheado no escopo do modulo: reusa conexoes entre invocacoes
// "quentes" da mesma execution environment, em vez de abrir uma conexao
// nova a cada chamada.
let pool: Pool | undefined;

function getPool(cfg: AuthCpfConfig): Pool {
  if (!pool) {
    pool = new Pool({
      host: cfg.dbHost,
      port: cfg.dbPort,
      database: cfg.dbName,
      user: cfg.dbUser,
      password: cfg.dbPassword,
      // O parameter group padrao do RDS Postgres exige SSL (rds.force_ssl) —
      // sem isso a conexao cai com "no pg_hba.conf entry ... no encryption".
      // rejectUnauthorized:false pula a validacao da CA (mesma postura
      // pragmatica ja usada no resto do projeto pra um ambiente de lab).
      ssl: { rejectUnauthorized: false },
      max: 1, // uma Lambda processa uma requisicao por vez
      connectionTimeoutMillis: 5000,
      idleTimeoutMillis: 30000,
    });
  }
  return pool;
}

// Nomes de tabela/coluna nao sao entre aspas: as migrations do app criam
// USERS/ROLE/USER_ROLES sem aspas, entao o Postgres os guarda em minusculo
// (users, user_roles, role) — usar aqui exatamente como o Postgres guarda.
const FIND_USER_BY_CPF_SQL = `
  SELECT u.id AS id, u.user_name AS username, u.ativo AS ativo,
         coalesce(array_agg(r.nome) FILTER (WHERE r.nome IS NOT NULL), '{}') AS roles
  FROM users u
  LEFT JOIN user_roles ur ON ur.user_id = u.id
  LEFT JOIN role r ON r.id = ur.role_id
  WHERE u.cpf = $1
  GROUP BY u.id, u.user_name, u.ativo
`;

export async function findUserByCpf(cfg: AuthCpfConfig, cpf: string): Promise<UserAuth | undefined> {
  const result = await getPool(cfg).query<UserAuth>(FIND_USER_BY_CPF_SQL, [cpf]);
  return result.rows[0];
}

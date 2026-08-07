import { Pool } from "pg";
import type { AuthCpfSecret } from "./secretsManager";

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

function getPool(secret: AuthCpfSecret): Pool {
  if (!pool) {
    pool = new Pool({
      host: secret.dbHost,
      port: secret.dbPort,
      database: secret.dbName,
      user: secret.dbUser,
      password: secret.dbPassword,
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

export async function findUserByCpf(secret: AuthCpfSecret, cpf: string): Promise<UserAuth | undefined> {
  const result = await getPool(secret).query<UserAuth>(FIND_USER_BY_CPF_SQL, [cpf]);
  return result.rows[0];
}

import { requireEnv } from "./env";

export interface JwtPublicConfig {
  jwtPublicKey: string;
  jwtIssuer: string;
}

// Config minima da authorizer: so o necessario pra verificar assinatura +
// issuer, sem chave privada nem credenciais do banco (ela nunca acessa o
// RDS). Arquivo separado de config.ts de proposito — os dois viram bundles
// esbuild distintos (dist/index.js e dist/authorizer.js) e a authorizer nao
// deve exigir JWT_PRIVATE_KEY/DB_* no ambiente dela.
export const authorizerConfig: JwtPublicConfig = {
  jwtPublicKey: requireEnv("JWT_PUBLIC_KEY"),
  jwtIssuer: requireEnv("JWT_ISSUER"),
};

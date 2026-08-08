import { requireEnv } from "./env";

export interface AuthCpfConfig {
  jwtPrivateKey: string;
  jwtPublicKey: string;
  jwtIssuer: string;
  jwtExpiresIn: number;
  dbHost: string;
  dbPort: number;
  dbName: string;
  dbUser: string;
  dbPassword: string;
}

// Lidas direto das variaveis de ambiente da lambda (Terraform), sem Secrets
// Manager — ver lambda/README.md ("Configuracao (variaveis de ambiente)").
export const config: AuthCpfConfig = {
  jwtPrivateKey: requireEnv("JWT_PRIVATE_KEY"),
  jwtPublicKey: requireEnv("JWT_PUBLIC_KEY"),
  jwtIssuer: requireEnv("JWT_ISSUER"),
  jwtExpiresIn: Number(requireEnv("JWT_EXPIRES_IN")),
  dbHost: requireEnv("DB_HOST"),
  dbPort: Number(requireEnv("DB_PORT")),
  dbName: requireEnv("DB_NAME"),
  dbUser: requireEnv("DB_USER"),
  dbPassword: requireEnv("DB_PASSWORD"),
};

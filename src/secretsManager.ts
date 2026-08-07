import { GetSecretValueCommand, SecretsManagerClient } from "@aws-sdk/client-secrets-manager";
import { config } from "./config";

export interface AuthCpfSecret {
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

const client = new SecretsManagerClient({});

// Cacheado no escopo do modulo: reaproveitado entre invocacoes em uma
// mesma execution environment "quente", evitando uma chamada ao Secrets
// Manager a cada requisicao.
let cached: AuthCpfSecret | undefined;

export async function getAuthCpfSecret(): Promise<AuthCpfSecret> {
  if (cached) return cached;

  const response = await client.send(new GetSecretValueCommand({ SecretId: config.secretArn }));
  if (!response.SecretString) {
    throw new Error("Secret do Secrets Manager nao possui SecretString");
  }

  cached = JSON.parse(response.SecretString) as AuthCpfSecret;
  return cached;
}

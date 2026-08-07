function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Variavel de ambiente obrigatoria ausente: ${name}`);
  return value;
}

export const config = {
  secretArn: requireEnv("AUTH_CPF_SECRET_ARN"),
};

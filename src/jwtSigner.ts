import jwt from "jsonwebtoken";
import type { AuthCpfSecret } from "./secretsManager";
import type { UserAuth } from "./db";

export interface IssuedToken {
  token: string;
  expiresIn: number;
}

/**
 * Assina um JWT RS256 com a MESMA chave privada usada pelo app
 * (br.com.lata.velha.authentication.infrastructure.security.JwtTokenProvider),
 * para que o JwtDecoder do app (que so conhece a chave publica correspondente)
 * aceite tokens emitidos por aqui como se tivessem vindo do /auth/login.
 *
 * Claims espelham exatamente o que o JwtTokenProvider gera: "sub" = ID do
 * usuario (UUID, o mesmo formato que UserId.fromString espera) e "scope" =
 * roles do usuario separadas por espaco.
 */
export function issueToken(secret: AuthCpfSecret, user: UserAuth): IssuedToken {
  const expiresIn = secret.jwtExpiresIn;
  const scope = user.roles.join(" ");

  const token = jwt.sign(
    { scope },
    secret.jwtPrivateKey,
    {
      algorithm: "RS256",
      issuer: secret.jwtIssuer,
      subject: user.id,
      expiresIn,
    },
  );

  return { token, expiresIn };
}

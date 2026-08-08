import jwt from "jsonwebtoken";
import type { AuthCpfConfig } from "./config";
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
export function issueToken(cfg: AuthCpfConfig, user: UserAuth): IssuedToken {
  const expiresIn = cfg.jwtExpiresIn;
  const scope = user.roles.join(" ");

  const token = jwt.sign(
    { scope },
    cfg.jwtPrivateKey,
    {
      algorithm: "RS256",
      issuer: cfg.jwtIssuer,
      subject: user.id,
      expiresIn,
    },
  );

  return { token, expiresIn };
}

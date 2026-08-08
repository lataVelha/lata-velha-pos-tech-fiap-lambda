import type {
  APIGatewayRequestAuthorizerEventV2,
  APIGatewaySimpleAuthorizerWithContextResult,
} from "aws-lambda";
import jwt from "jsonwebtoken";
import { authorizerConfig } from "./authorizerConfig";

interface AuthorizerContext {
  sub: string;
  scope: string;
}

type Result = APIGatewaySimpleAuthorizerWithContextResult<AuthorizerContext> | { isAuthorized: false };

const BEARER_PREFIX = "Bearer ";

function extractBearerToken(event: APIGatewayRequestAuthorizerEventV2): string | undefined {
  const header = event.headers?.authorization ?? event.headers?.Authorization;
  if (!header || !header.startsWith(BEARER_PREFIX)) return undefined;
  return header.slice(BEARER_PREFIX.length).trim();
}

/**
 * Lambda authorizer (REQUEST, payload 2.0, simple response) do API Gateway
 * do app (ver infra/terraform/modules/app-gateway). Duplica, na borda, a
 * MESMA verificacao que o JwtDecoder do app faz: assinatura RS256 com a
 * chave publica compartilhada, issuer e expiracao. Nao decide autorizacao
 * por role — isso continua sendo responsabilidade exclusiva do
 * SecurityConfig do app, que tem o mapa completo de rota -> role.
 */
export async function handler(event: APIGatewayRequestAuthorizerEventV2): Promise<Result> {
  try {
    const token = extractBearerToken(event);
    if (!token) return { isAuthorized: false };

    const decoded = jwt.verify(token, authorizerConfig.jwtPublicKey, {
      algorithms: ["RS256"],
      issuer: authorizerConfig.jwtIssuer,
    }) as jwt.JwtPayload;

    return {
      isAuthorized: true,
      context: {
        sub: decoded.sub ?? "",
        scope: typeof decoded.scope === "string" ? decoded.scope : "",
      },
    };
  } catch (error) {
    console.warn("Token rejeitado pelo authorizer:", error instanceof Error ? error.message : error);
    return { isAuthorized: false };
  }
}

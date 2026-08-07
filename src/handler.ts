import { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from "aws-lambda";
import { cleanCpf, isValidCpf } from "./cpf";
import { findUserByCpf } from "./db";
import { HttpError, InvalidCpfError, UserInativoError, UserNotFoundError } from "./httpError";
import { issueToken } from "./jwtSigner";
import { getAuthCpfSecret } from "./secretsManager";

interface LoginCpfRequestBody {
  cpf?: unknown;
}

interface LoginCpfResponseBody {
  token: string;
  tokenType: "Bearer";
  expiresIn: number;
}

function jsonResponse(statusCode: number, body: unknown): APIGatewayProxyResultV2 {
  return {
    statusCode,
    headers: {
      "content-type": "application/json",
      "access-control-allow-origin": "*",
    },
    body: JSON.stringify(body),
  };
}

function parseCpf(event: APIGatewayProxyEventV2): string {
  let payload: LoginCpfRequestBody;
  try {
    payload = event.body ? (JSON.parse(event.body) as LoginCpfRequestBody) : {};
  } catch {
    throw new InvalidCpfError("Corpo da requisicao nao e um JSON valido");
  }

  if (typeof payload.cpf !== "string" || !isValidCpf(payload.cpf)) {
    throw new InvalidCpfError();
  }

  return cleanCpf(payload.cpf);
}

export async function handler(event: APIGatewayProxyEventV2): Promise<APIGatewayProxyResultV2> {
  try {
    const cpf = parseCpf(event);

    const secret = await getAuthCpfSecret();
    const user = await findUserByCpf(secret, cpf);

    if (!user) throw new UserNotFoundError();
    if (!user.ativo) throw new UserInativoError();

    const issued = issueToken(secret, user);
    const responseBody: LoginCpfResponseBody = {
      token: issued.token,
      tokenType: "Bearer",
      expiresIn: issued.expiresIn,
    };

    return jsonResponse(200, responseBody);
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse(error.statusCode, { error: error.message });
    }

    console.error("Erro inesperado ao autenticar por CPF", error);
    return jsonResponse(500, { error: "Erro interno" });
  }
}

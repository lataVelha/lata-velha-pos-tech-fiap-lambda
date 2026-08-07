import { generateKeyPairSync } from "crypto";
import jwt from "jsonwebtoken";
import type { APIGatewayProxyEventV2, APIGatewayProxyStructuredResultV2 } from "aws-lambda";

jest.mock("../src/db", () => ({ findUserByCpf: jest.fn() }));
jest.mock("../src/secretsManager", () => ({ getAuthCpfSecret: jest.fn() }));

import { findUserByCpf } from "../src/db";
import { getAuthCpfSecret, AuthCpfSecret } from "../src/secretsManager";
import { handler } from "../src/handler";

const mockedFindUserByCpf = findUserByCpf as jest.MockedFunction<typeof findUserByCpf>;
const mockedGetAuthCpfSecret = getAuthCpfSecret as jest.MockedFunction<typeof getAuthCpfSecret>;

const { publicKey, privateKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  publicKeyEncoding: { type: "spki", format: "pem" },
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
});

const secret: AuthCpfSecret = {
  jwtPrivateKey: privateKey,
  jwtPublicKey: publicKey,
  jwtIssuer: "lata-velha",
  jwtExpiresIn: 3600,
  dbHost: "localhost",
  dbPort: 5432,
  dbName: "lata_velha",
  dbUser: "admin",
  dbPassword: "admin123",
};

const VALID_CPF = "111.444.777-35";
const VALID_CPF_CLEAN = "11144477735";

function makeEvent(body: unknown): APIGatewayProxyEventV2 {
  return {
    body: JSON.stringify(body),
  } as APIGatewayProxyEventV2;
}

async function callHandler(body: unknown): Promise<APIGatewayProxyStructuredResultV2> {
  return (await handler(makeEvent(body))) as APIGatewayProxyStructuredResultV2;
}

beforeEach(() => {
  mockedGetAuthCpfSecret.mockResolvedValue(secret);
});

describe("handler", () => {
  it("retorna 400 quando o CPF e invalido", async () => {
    const result = await callHandler({ cpf: "123" });

    expect(result.statusCode).toBe(400);
    expect(mockedFindUserByCpf).not.toHaveBeenCalled();
  });

  it("retorna 400 quando o CPF nao e enviado", async () => {
    const result = await callHandler({});
    expect(result.statusCode).toBe(400);
  });

  it("retorna 404 quando nao existe usuario com o CPF informado", async () => {
    mockedFindUserByCpf.mockResolvedValue(undefined);

    const result = await callHandler({ cpf: VALID_CPF });

    expect(result.statusCode).toBe(404);
    expect(mockedFindUserByCpf).toHaveBeenCalledWith(secret, VALID_CPF_CLEAN);
  });

  it("retorna 403 quando o usuario esta inativo", async () => {
    mockedFindUserByCpf.mockResolvedValue({
      id: "8f14e45f-ceea-4ca2-8f7a-1234567890ab",
      username: "atendente@latavelha.com",
      ativo: false,
      roles: ["USER", "ATENDENTE"],
    });

    const result = await callHandler({ cpf: VALID_CPF });

    expect(result.statusCode).toBe(403);
  });

  it("retorna 200 com um JWT valido, assinado com a chave do segredo, quando o usuario esta ativo", async () => {
    mockedFindUserByCpf.mockResolvedValue({
      id: "8f14e45f-ceea-4ca2-8f7a-1234567890ab",
      username: "atendente@latavelha.com",
      ativo: true,
      roles: ["USER", "ATENDENTE"],
    });

    const result = await callHandler({ cpf: VALID_CPF });

    expect(result.statusCode).toBe(200);
    const body = JSON.parse(result.body as string);
    expect(body.tokenType).toBe("Bearer");
    expect(body.expiresIn).toBe(3600);

    const decoded = jwt.verify(body.token, publicKey, { algorithms: ["RS256"] }) as jwt.JwtPayload;
    expect(decoded.sub).toBe("8f14e45f-ceea-4ca2-8f7a-1234567890ab");
    expect(decoded.iss).toBe("lata-velha");
    expect(decoded.scope).toBe("USER ATENDENTE");
  });

  it("retorna 500 quando algo inesperado falha", async () => {
    mockedFindUserByCpf.mockRejectedValue(new Error("conexao recusada"));

    const result = await callHandler({ cpf: VALID_CPF });

    expect(result.statusCode).toBe(500);
  });
});

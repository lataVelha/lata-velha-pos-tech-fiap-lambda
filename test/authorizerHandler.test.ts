import { generateKeyPairSync } from "crypto";
import jwt from "jsonwebtoken";
import type { APIGatewayRequestAuthorizerEventV2 } from "aws-lambda";

jest.mock("../src/authorizerConfig", () => ({ authorizerConfig: {} }));

import { authorizerConfig as mockAuthorizerConfig, JwtPublicConfig } from "../src/authorizerConfig";
import { handler } from "../src/authorizerHandler";

const { publicKey, privateKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  publicKeyEncoding: { type: "spki", format: "pem" },
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
});

const secret: JwtPublicConfig = {
  jwtPublicKey: publicKey,
  jwtIssuer: "lata-velha",
};

function eventWithAuthHeader(authorization?: string): APIGatewayRequestAuthorizerEventV2 {
  return {
    headers: authorization ? { authorization } : {},
  } as APIGatewayRequestAuthorizerEventV2;
}

function signToken(overrides: Partial<jwt.SignOptions> = {}, key: string = privateKey): string {
  return jwt.sign({ scope: "USER ATENDENTE" }, key, {
    algorithm: "RS256",
    issuer: "lata-velha",
    subject: "8f14e45f-ceea-4ca2-8f7a-1234567890ab",
    expiresIn: 3600,
    ...overrides,
  });
}

beforeEach(() => {
  Object.assign(mockAuthorizerConfig, secret);
});

describe("authorizer handler", () => {
  it("nega quando nao ha header Authorization", async () => {
    const result = await handler(eventWithAuthHeader());
    expect(result).toEqual({ isAuthorized: false });
  });

  it("nega quando o header nao comeca com Bearer", async () => {
    const result = await handler(eventWithAuthHeader(signToken()));
    expect(result).toEqual({ isAuthorized: false });
  });

  it("nega um token assinado com outra chave", async () => {
    const token = jwt.sign({ scope: "USER" }, privateKey, {
      algorithm: "RS256",
      issuer: "lata-velha",
      subject: "8f14e45f-ceea-4ca2-8f7a-1234567890ab",
      expiresIn: 3600,
    });
    // corrompe a assinatura trocando os ultimos caracteres
    const tampered = token.slice(0, -5) + "AAAAA";
    const result = await handler(eventWithAuthHeader(`Bearer ${tampered}`));
    expect(result).toEqual({ isAuthorized: false });
  });

  it("nega um token expirado", async () => {
    const token = signToken({ expiresIn: -10 });
    const result = await handler(eventWithAuthHeader(`Bearer ${token}`));
    expect(result).toEqual({ isAuthorized: false });
  });

  it("nega um token com issuer diferente", async () => {
    const token = signToken({ issuer: "outro-issuer" });
    const result = await handler(eventWithAuthHeader(`Bearer ${token}`));
    expect(result).toEqual({ isAuthorized: false });
  });

  it("nega um token assinado com uma chave RSA diferente", async () => {
    const { privateKey: rogueKey } = generateKeyPairSync("rsa", {
      modulusLength: 2048,
      publicKeyEncoding: { type: "spki", format: "pem" },
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
    });
    const token = signToken({}, rogueKey);
    const result = await handler(eventWithAuthHeader(`Bearer ${token}`));
    expect(result).toEqual({ isAuthorized: false });
  });

  it("autoriza um token valido e propaga sub/scope no context", async () => {
    const token = signToken();
    const result = await handler(eventWithAuthHeader(`Bearer ${token}`));

    expect(result).toMatchObject({
      isAuthorized: true,
      context: {
        sub: "8f14e45f-ceea-4ca2-8f7a-1234567890ab",
        scope: "USER ATENDENTE",
      },
    });
  });
});

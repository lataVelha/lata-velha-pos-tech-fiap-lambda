"""
Config lida direto das variaveis de ambiente da lambda (Terraform) — sem
Secrets Manager, ver lambda/README.md ("Configuracao").
"""

import os
from dataclasses import dataclass


def _require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"Variavel de ambiente obrigatoria ausente: {name}")
    return value


@dataclass(frozen=True)
class AuthCpfConfig:
    # Sem jwt_public_key: a auth-cpf so ASSINA token (JwtTokenSigner usa so
    # a chave privada) — quem verifica assinatura com a chave publica e a
    # jwt-authorizer (JwtPublicConfig).
    jwt_private_key: str
    jwt_issuer: str
    jwt_expires_in: int
    db_host: str
    db_port: int
    db_name: str
    db_user: str
    db_password: str

    @classmethod
    def from_env(cls) -> "AuthCpfConfig":
        return cls(
            jwt_private_key=_require_env("JWT_PRIVATE_KEY"),
            jwt_issuer=_require_env("JWT_ISSUER"),
            jwt_expires_in=int(_require_env("JWT_EXPIRES_IN")),
            db_host=_require_env("DB_HOST"),
            db_port=int(_require_env("DB_PORT")),
            db_name=_require_env("DB_NAME"),
            db_user=_require_env("DB_USER"),
            db_password=_require_env("DB_PASSWORD"),
        )


@dataclass(frozen=True)
class JwtPublicConfig:
    jwt_public_key: str
    jwt_issuer: str

    @classmethod
    def from_env(cls) -> "JwtPublicConfig":
        return cls(
            jwt_public_key=_require_env("JWT_PUBLIC_KEY"),
            jwt_issuer=_require_env("JWT_ISSUER"),
        )

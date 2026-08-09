"""
Config lida direto das variaveis de ambiente da lambda (Terraform) — sem
Secrets Manager, ver lambda/README.md ("Configuracao").
"""

from dataclasses import dataclass

from shared.env import require_env


@dataclass(frozen=True)
class AuthCpfConfig:
    # Sem jwt_public_key: a auth-cpf so ASSINA token (JwtTokenSigner usa so
    # a chave privada) — quem verifica assinatura com a chave publica e a
    # jwt-authorizer (JwtPublicConfig, outro projeto).
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
            jwt_private_key=require_env("JWT_PRIVATE_KEY"),
            jwt_issuer=require_env("JWT_ISSUER"),
            jwt_expires_in=int(require_env("JWT_EXPIRES_IN")),
            db_host=require_env("DB_HOST"),
            db_port=int(require_env("DB_PORT")),
            db_name=require_env("DB_NAME"),
            db_user=require_env("DB_USER"),
            db_password=require_env("DB_PASSWORD"),
        )

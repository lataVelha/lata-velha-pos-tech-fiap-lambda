from dataclasses import dataclass

from shared.env import require_env


@dataclass(frozen=True)
class JwtPublicConfig:
    jwt_public_key: str
    jwt_issuer: str

    @classmethod
    def from_env(cls) -> "JwtPublicConfig":
        return cls(
            jwt_public_key=require_env("JWT_PUBLIC_KEY"),
            jwt_issuer=require_env("JWT_ISSUER"),
        )

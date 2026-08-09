"""
Assina e verifica o JWT RS256 compartilhado pelo app (mesma chave, mesmo
issuer, mesmas claims) — as duas metades (assinar/verificar) ficam juntas de
proposito, pra nunca divergir em algoritmo/claim entre a auth-cpf e a
jwt-authorizer. Zero import de auth_cpf/jwt_authorizer: quem usa isso
depende deste modulo, nunca o contrario.
"""

import time
from dataclasses import dataclass
from typing import List, Protocol

import jwt as pyjwt


@dataclass(frozen=True)
class IssuedToken:
    token: str
    expires_in: int


@dataclass(frozen=True)
class VerifiedClaims:
    sub: str
    scope: str


class SigningUser(Protocol):
    """O minimo que JwtTokenSigner precisa de um usuario pra assinar o
    token — tipagem estrutural: UserAuth (auth_cpf/domain/user.py) satisfaz
    isso so por ter os mesmos atributos, sem importar nada daqui."""

    id: str
    roles: List[str]


class JwtTokenSigner:
    """
    Assina um JWT RS256 com a MESMA chave privada usada pelo app
    (br.com.lata.velha.authentication.infrastructure.security.JwtTokenProvider),
    para que o JwtDecoder do app (que so conhece a chave publica
    correspondente) aceite tokens emitidos por aqui como se tivessem vindo
    do /auth/login. Claims espelham exatamente o que o JwtTokenProvider
    gera: "sub" = ID do usuario (UUID) e "scope" = roles separadas por
    espaco.
    """

    def __init__(self, private_key: str, issuer: str, expires_in: int):
        self._private_key = private_key
        self._issuer = issuer
        self._expires_in = expires_in

    def issue(self, user: SigningUser) -> IssuedToken:
        now = int(time.time())
        payload = {
            "scope": " ".join(user.roles),
            "iat": now,
            "exp": now + self._expires_in,
            "iss": self._issuer,
            "sub": user.id,
        }
        token = pyjwt.encode(payload, self._private_key, algorithm="RS256")
        return IssuedToken(token=token, expires_in=self._expires_in)


class JwtTokenVerifier:
    """
    Duplica, na borda, a MESMA verificacao que o JwtDecoder do app faz:
    assinatura RS256 com a chave publica compartilhada, issuer e expiracao.
    """

    def __init__(self, public_key: str, issuer: str):
        self._public_key = public_key
        self._issuer = issuer

    def verify(self, token: str) -> VerifiedClaims:
        decoded = pyjwt.decode(
            token,
            self._public_key,
            algorithms=["RS256"],
            issuer=self._issuer,
        )
        return VerifiedClaims(
            sub=decoded.get("sub", ""),
            scope=decoded.get("scope", "") if isinstance(decoded.get("scope"), str) else "",
        )

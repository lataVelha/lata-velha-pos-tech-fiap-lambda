import time

import jwt as pyjwt

from ..application.ports import IssuedToken, TokenSigner, TokenVerifier, VerifiedClaims
from ..domain.user import UserAuth
from .config import AuthCpfConfig, JwtPublicConfig


class JwtTokenSigner(TokenSigner):
    """
    Assina um JWT RS256 com a MESMA chave privada usada pelo app
    (br.com.lata.velha.authentication.infrastructure.security.JwtTokenProvider),
    para que o JwtDecoder do app (que so conhece a chave publica
    correspondente) aceite tokens emitidos por aqui como se tivessem vindo
    do /auth/login. Claims espelham exatamente o que o JwtTokenProvider
    gera: "sub" = ID do usuario (UUID) e "scope" = roles separadas por
    espaco.
    """

    def __init__(self, config: AuthCpfConfig):
        self._config = config

    def issue(self, user: UserAuth) -> IssuedToken:
        now = int(time.time())
        expires_in = self._config.jwt_expires_in

        payload = {
            "scope": " ".join(user.roles),
            "iat": now,
            "exp": now + expires_in,
            "iss": self._config.jwt_issuer,
            "sub": user.id,
        }
        token = pyjwt.encode(payload, self._config.jwt_private_key, algorithm="RS256")

        return IssuedToken(token=token, expires_in=expires_in)


class JwtTokenVerifier(TokenVerifier):
    """
    Duplica, na borda, a MESMA verificacao que o JwtDecoder do app faz:
    assinatura RS256 com a chave publica compartilhada, issuer e expiracao.
    """

    def __init__(self, config: JwtPublicConfig):
        self._config = config

    def verify(self, token: str) -> VerifiedClaims:
        decoded = pyjwt.decode(
            token,
            self._config.jwt_public_key,
            algorithms=["RS256"],
            issuer=self._config.jwt_issuer,
        )
        return VerifiedClaims(
            sub=decoded.get("sub", ""),
            scope=decoded.get("scope", "") if isinstance(decoded.get("scope"), str) else "",
        )

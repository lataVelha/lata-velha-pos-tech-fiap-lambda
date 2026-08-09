from .ports import TokenVerifier, VerifiedClaims


class AuthorizeTokenUseCase:
    """
    Verifica um JWT (assinatura RS256 + issuer + expiracao). Nao decide
    autorizacao por role — isso continua 100% no SecurityConfig do app; esta
    use case so responde "esse token e valido ou nao".
    """

    def __init__(self, token_verifier: TokenVerifier):
        self._token_verifier = token_verifier

    def execute(self, token: str) -> VerifiedClaims:
        return self._token_verifier.verify(token)

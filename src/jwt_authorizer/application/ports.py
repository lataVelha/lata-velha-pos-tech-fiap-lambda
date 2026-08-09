from typing import Protocol

from shared.jwt_token_service import VerifiedClaims

__all__ = ["TokenVerifier", "VerifiedClaims"]


class TokenVerifier(Protocol):
    def verify(self, token: str) -> VerifiedClaims: ...

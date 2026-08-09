"""
Interfaces (ports) que a camada application depende, mas nao implementa —
mesmo papel dos "gateways" no app principal (application/gateways/*). Quem
implementa de verdade fica em infrastructure/ (ou em shared/, no caso do
JwtTokenSigner), injetado pelo handler (composition root).

Protocol em vez de ABC: assim a implementacao real do assinador de token
(shared.jwt_token_service.JwtTokenSigner) satisfaz TokenSigner so por ter o
metodo certo (tipagem estrutural), sem shared/ precisar importar nada
daqui — a dependencia so aponta pra dentro (auth_cpf -> shared), nunca o
contrario.
"""

from typing import Optional, Protocol

from shared.jwt_token_service import IssuedToken

from ..domain.user import UserAuth

__all__ = ["IssuedToken", "PasswordVerifier", "TokenSigner", "UserRepository"]


class UserRepository(Protocol):
    def find_by_cpf(self, cpf: str) -> Optional[UserAuth]: ...


class PasswordVerifier(Protocol):
    def verify(self, raw_password: str, hashed_password: str) -> bool: ...


class TokenSigner(Protocol):
    def issue(self, user: UserAuth) -> IssuedToken: ...

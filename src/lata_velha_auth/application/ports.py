"""
Interfaces (ports) que a camada application depende, mas nao implementa —
mesmo papel dos "gateways" no app principal (application/gateways/*). Quem
implementa de verdade fica em infrastructure/, injetado pelos handlers
(composition root). Dependency Inversion: application nunca importa
infrastructure.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional

from ..domain.user import UserAuth


class UserRepository(ABC):
    @abstractmethod
    def find_by_cpf(self, cpf: str) -> Optional[UserAuth]:
        raise NotImplementedError


class PasswordVerifier(ABC):
    @abstractmethod
    def verify(self, raw_password: str, hashed_password: str) -> bool:
        raise NotImplementedError


@dataclass(frozen=True)
class IssuedToken:
    token: str
    expires_in: int


class TokenSigner(ABC):
    @abstractmethod
    def issue(self, user: UserAuth) -> IssuedToken:
        raise NotImplementedError


@dataclass(frozen=True)
class VerifiedClaims:
    sub: str
    scope: str


class TokenVerifier(ABC):
    @abstractmethod
    def verify(self, token: str) -> VerifiedClaims:
        raise NotImplementedError

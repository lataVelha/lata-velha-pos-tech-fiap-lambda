from dataclasses import dataclass
from typing import List


@dataclass(frozen=True)
class UserAuth:
    id: str  # UUID — vira o "sub" do JWT, no mesmo formato que o app espera (UserId)
    username: str
    ativo: bool
    roles: List[str]
    credential_hash: str  # hash BCrypt (coluna USERS.CREDENTIAL) — nunca a senha em texto puro

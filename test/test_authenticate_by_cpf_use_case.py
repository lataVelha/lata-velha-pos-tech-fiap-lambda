from typing import Optional

import pytest

from lata_velha_auth.application.authenticate_by_cpf import AuthenticateByCpfUseCase
from lata_velha_auth.application.ports import IssuedToken, PasswordVerifier, TokenSigner, UserRepository
from lata_velha_auth.domain.errors import (
    InvalidCpfError,
    InvalidCredentialsError,
    UserInativoError,
    UserNotFoundError,
)
from lata_velha_auth.domain.user import UserAuth

VALID_CPF = "111.444.777-35"
VALID_CPF_CLEAN = "11144477735"
CORRECT_PASSWORD = "Admin@123"
HASH_FOR_CORRECT_PASSWORD = "hash-fake-so-para-o-fake-verifier-comparar"


class FakeUserRepository(UserRepository):
    def __init__(self, user: Optional[UserAuth] = None):
        self.user = user
        self.received_cpf: Optional[str] = None

    def find_by_cpf(self, cpf: str) -> Optional[UserAuth]:
        self.received_cpf = cpf
        return self.user


class FakePasswordVerifier(PasswordVerifier):
    """Compara texto puro em vez de BCrypt de verdade — quem testa BCrypt de
    verdade e test_bcrypt_password_verifier.py, na camada de infrastructure."""

    def __init__(self):
        self.received: Optional[tuple] = None

    def verify(self, raw_password: str, hashed_password: str) -> bool:
        self.received = (raw_password, hashed_password)
        return raw_password == CORRECT_PASSWORD and hashed_password == HASH_FOR_CORRECT_PASSWORD


class FakeTokenSigner(TokenSigner):
    def __init__(self):
        self.issued_for: Optional[UserAuth] = None

    def issue(self, user: UserAuth) -> IssuedToken:
        self.issued_for = user
        return IssuedToken(token="fake.jwt.token", expires_in=3600)


def _active_user(credential_hash: str = HASH_FOR_CORRECT_PASSWORD) -> UserAuth:
    return UserAuth(
        id="8f14e45f-ceea-4ca2-8f7a-1234567890ab",
        username="atendente@latavelha.com",
        ativo=True,
        roles=["USER", "ATENDENTE"],
        credential_hash=credential_hash,
    )


def _use_case(repository, password_verifier=None, signer=None):
    return AuthenticateByCpfUseCase(
        repository, password_verifier or FakePasswordVerifier(), signer or FakeTokenSigner()
    )


def test_rejeita_cpf_invalido_sem_consultar_repositorio():
    repository = FakeUserRepository()
    use_case = _use_case(repository)

    with pytest.raises(InvalidCpfError):
        use_case.execute("123", CORRECT_PASSWORD)

    assert repository.received_cpf is None


def test_rejeita_senha_ausente_sem_consultar_repositorio():
    repository = FakeUserRepository()
    use_case = _use_case(repository)

    with pytest.raises(InvalidCredentialsError):
        use_case.execute(VALID_CPF, "")

    assert repository.received_cpf is None


def test_lanca_user_not_found_quando_nao_existe_usuario():
    repository = FakeUserRepository(user=None)
    use_case = _use_case(repository)

    with pytest.raises(UserNotFoundError):
        use_case.execute(VALID_CPF, CORRECT_PASSWORD)

    assert repository.received_cpf == VALID_CPF_CLEAN


def test_lanca_user_inativo_quando_usuario_esta_inativo():
    inactive_user = UserAuth(id="x", username="y", ativo=False, roles=[], credential_hash="qualquer")
    repository = FakeUserRepository(user=inactive_user)
    use_case = _use_case(repository)

    with pytest.raises(UserInativoError):
        use_case.execute(VALID_CPF, CORRECT_PASSWORD)


def test_lanca_invalid_credentials_quando_senha_esta_errada():
    repository = FakeUserRepository(user=_active_user())
    verifier = FakePasswordVerifier()
    use_case = _use_case(repository, password_verifier=verifier)

    with pytest.raises(InvalidCredentialsError):
        use_case.execute(VALID_CPF, "senha-errada")

    assert verifier.received == ("senha-errada", HASH_FOR_CORRECT_PASSWORD)


def test_emite_token_quando_cpf_e_senha_estao_corretos():
    user = _active_user()
    repository = FakeUserRepository(user=user)
    signer = FakeTokenSigner()
    use_case = _use_case(repository, signer=signer)

    issued = use_case.execute(VALID_CPF, CORRECT_PASSWORD)

    assert issued.token == "fake.jwt.token"
    assert issued.expires_in == 3600
    assert signer.issued_for == user

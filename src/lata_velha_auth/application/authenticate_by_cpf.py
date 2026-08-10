from ..domain.cpf import clean_cpf, is_valid_cpf
from ..domain.errors import (
    InvalidCpfError,
    InvalidCredentialsError,
    UserInativoError,
    UserNotFoundError,
)
from .ports import IssuedToken, PasswordVerifier, TokenSigner, UserRepository


class AuthenticateByCpfUseCase:
    """
    Login por CPF + senha: valida o CPF, consulta o usuario, confere a senha
    (mesmo hash BCrypt usado pelo login por email/senha do app —
    User.login()/Credential.match() em Java) e assina um token se tudo
    bater. Nao sabe nada de HTTP, Postgres, BCrypt ou JWT de verdade — so
    orquestra as tres ports injetadas.
    """

    def __init__(
        self,
        user_repository: UserRepository,
        password_verifier: PasswordVerifier,
        token_signer: TokenSigner,
    ):
        self._user_repository = user_repository
        self._password_verifier = password_verifier
        self._token_signer = token_signer

    def execute(self, raw_cpf: str, password: str) -> IssuedToken:
        if not isinstance(raw_cpf, str) or not is_valid_cpf(raw_cpf):
            raise InvalidCpfError()
        if not isinstance(password, str) or not password:
            raise InvalidCredentialsError()

        cpf = clean_cpf(raw_cpf)
        user = self._user_repository.find_by_cpf(cpf)

        if user is None:
            raise UserNotFoundError()
        if not user.ativo:
            raise UserInativoError()
        if not self._password_verifier.verify(password, user.credential_hash):
            raise InvalidCredentialsError()

        return self._token_signer.issue(user)

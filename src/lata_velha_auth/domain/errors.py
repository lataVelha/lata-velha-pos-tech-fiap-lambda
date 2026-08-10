"""
Excecoes de dominio. De proposito SEM conhecimento de HTTP (nada de status
code aqui) — quem traduz isso pra 400/404/403 e a camada de interface
(handlers), nao o dominio.
"""


class InvalidCpfError(Exception):
    def __init__(self, message: str = "CPF invalido"):
        super().__init__(message)


class UserNotFoundError(Exception):
    def __init__(self, message: str = "Usuario nao encontrado para o CPF informado"):
        super().__init__(message)


class UserInativoError(Exception):
    def __init__(self, message: str = "Usuario inativo"):
        super().__init__(message)


class InvalidCredentialsError(Exception):
    def __init__(self, message: str = "CPF ou senha invalidos"):
        super().__init__(message)

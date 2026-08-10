import bcrypt

from ..application.ports import PasswordVerifier


class BcryptPasswordVerifier(PasswordVerifier):
    """
    Confere a senha com o MESMO algoritmo usado pelo app
    (BCryptPasswordEncoder do Spring Security — PasswordEncoderConfig.java,
    hash $2a$, cost 10, coluna USERS.CREDENTIAL). A lib `bcrypt` do Python
    verifica hashes $2a$/$2b$/$2y$ da mesma forma, sem incompatibilidade.
    """

    def verify(self, raw_password: str, hashed_password: str) -> bool:
        if not raw_password or not hashed_password:
            return False
        try:
            return bcrypt.checkpw(raw_password.encode("utf-8"), hashed_password.encode("utf-8"))
        except ValueError:
            # hash mal formado (nao deveria acontecer com dado vindo do
            # Postgres) — nunca autentica em vez de propagar excecao.
            return False

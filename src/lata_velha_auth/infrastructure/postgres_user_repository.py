import ssl
from typing import Optional

import pg8000.native

from ..application.ports import UserRepository
from ..domain.user import UserAuth
from .config import AuthCpfConfig

# Nomes de tabela/coluna nao sao entre aspas: as migrations do app criam
# USERS/ROLE/USER_ROLES sem aspas, entao o Postgres os guarda em minusculo
# (users, user_roles, role) — usar aqui exatamente como o Postgres guarda.
_FIND_USER_BY_CPF_SQL = """
    SELECT u.id AS id, u.user_name AS username, u.ativo AS ativo,
           u.credential AS credential_hash,
           coalesce(array_agg(r.nome) FILTER (WHERE r.nome IS NOT NULL), '{}') AS roles
    FROM users u
    LEFT JOIN user_roles ur ON ur.user_id = u.id
    LEFT JOIN role r ON r.id = ur.role_id
    WHERE u.cpf = :cpf
    GROUP BY u.id, u.user_name, u.ativo, u.credential
"""


def _unverified_ssl_context() -> ssl.SSLContext:
    # O parameter group padrao do RDS Postgres exige SSL (rds.force_ssl) —
    # sem isso a conexao cai com "no pg_hba.conf entry ... no encryption".
    # Pula a validacao da CA (mesma postura pragmatica ja usada no resto do
    # projeto pra um ambiente de lab).
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    return context


class PostgresUserRepository(UserRepository):
    """
    Implementacao real de UserRepository, usando pg8000 (driver Postgres
    puro-Python — sem extensao compilada, empacota sem precisar de Docker).
    Conexao cacheada no escopo da instancia: reusada entre invocacoes
    "quentes" da mesma execution environment.
    """

    def __init__(self, config: AuthCpfConfig):
        self._config = config
        self._connection: Optional[pg8000.native.Connection] = None

    def _get_connection(self) -> pg8000.native.Connection:
        if self._connection is None:
            self._connection = pg8000.native.Connection(
                host=self._config.db_host,
                port=self._config.db_port,
                database=self._config.db_name,
                user=self._config.db_user,
                password=self._config.db_password,
                ssl_context=_unverified_ssl_context(),
                timeout=5,
            )
        return self._connection

    def find_by_cpf(self, cpf: str) -> Optional[UserAuth]:
        connection = self._get_connection()
        rows = connection.run(_FIND_USER_BY_CPF_SQL, cpf=cpf)
        if not rows:
            return None

        columns = [column["name"] for column in connection.columns]
        row = dict(zip(columns, rows[0]))

        return UserAuth(
            id=str(row["id"]),
            username=row["username"],
            ativo=bool(row["ativo"]),
            roles=list(row["roles"] or []),
            credential_hash=row["credential_hash"],
        )

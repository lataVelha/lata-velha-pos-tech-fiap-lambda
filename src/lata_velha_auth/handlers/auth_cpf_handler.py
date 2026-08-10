import json
from typing import Any, Dict, Optional, Tuple

from ..application.authenticate_by_cpf import AuthenticateByCpfUseCase
from ..domain.errors import (
    InvalidCpfError,
    InvalidCredentialsError,
    UserInativoError,
    UserNotFoundError,
)
from ..infrastructure.bcrypt_password_verifier import BcryptPasswordVerifier
from ..infrastructure.config import AuthCpfConfig
from ..infrastructure.jwt_token_service import JwtTokenSigner
from ..infrastructure.postgres_user_repository import PostgresUserRepository

# Composition root: monta as implementacoes reais das ports e injeta na use
# case, uma vez por execution environment (cold start). Falha rapido se
# faltar variavel de ambiente.
_config = AuthCpfConfig.from_env()
_use_case = AuthenticateByCpfUseCase(
    user_repository=PostgresUserRepository(_config),
    password_verifier=BcryptPasswordVerifier(),
    token_signer=JwtTokenSigner(_config),
)


def _json_response(status_code: int, body: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {
            "content-type": "application/json",
            "access-control-allow-origin": "*",
        },
        "body": json.dumps(body),
    }


def _parse_credentials(event: Dict[str, Any]) -> Tuple[str, Optional[str]]:
    raw_body = event.get("body") or "{}"
    try:
        payload = json.loads(raw_body)
    except (TypeError, ValueError):
        raise InvalidCpfError("Corpo da requisicao nao e um JSON valido")

    cpf = payload.get("cpf") if isinstance(payload, dict) else None
    password = payload.get("password") if isinstance(payload, dict) else None

    if not isinstance(cpf, str):
        raise InvalidCpfError()

    # Presenca/formato da senha e validada dentro da use case (regra de
    # negocio), nao aqui — o handler so extrai o que veio no corpo.
    return cpf, password


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    try:
        cpf, password = _parse_credentials(event)
        issued = _use_case.execute(cpf, password)

        return _json_response(200, {
            "token": issued.token,
            "tokenType": "Bearer",
            "expiresIn": issued.expires_in,
        })
    except InvalidCpfError as error:
        return _json_response(400, {"error": str(error)})
    except UserNotFoundError as error:
        return _json_response(404, {"error": str(error)})
    except UserInativoError as error:
        return _json_response(403, {"error": str(error)})
    except InvalidCredentialsError as error:
        return _json_response(401, {"error": str(error)})
    except Exception as error:  # noqa: BLE001 — fronteira do handler, vira 500
        print(f"Erro inesperado ao autenticar por CPF: {error}")
        return _json_response(500, {"error": "Erro interno"})

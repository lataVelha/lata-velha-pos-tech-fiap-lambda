import json
import os
from typing import Any, Dict, Optional

from datadog_lambda.wrapper import datadog_lambda_wrapper

from ..application.authorize_token import AuthorizeTokenUseCase
from ..infrastructure.config import JwtPublicConfig
from ..infrastructure.jwt_token_service import JwtTokenVerifier

# Composition root: so a chave publica + issuer, nunca a chave privada nem
# credenciais de banco (esta funcao nao assina token nem acessa o RDS).
_config = JwtPublicConfig.from_env()
_use_case = AuthorizeTokenUseCase(token_verifier=JwtTokenVerifier(_config))

_BEARER_PREFIX = "Bearer "


def _extract_bearer_token(event: Dict[str, Any]) -> Optional[str]:
    headers = event.get("headers") or {}
    header = headers.get("authorization") or headers.get("Authorization")
    if not header or not header.startswith(_BEARER_PREFIX):
        return None
    return header[len(_BEARER_PREFIX):].strip()


def _log_trace(message: str) -> None:
    """Log JSON com trace_id/span_id para correlação no Datadog (Story 20.1)."""
    payload: Dict[str, Any] = {
        "message": message,
        "service": "lata-velha-jwt-authorizer",
        "env": os.environ.get("DD_ENV", "prod"),
    }
    try:
        from ddtrace import tracer

        span = tracer.current_span()
        if span is not None:
            payload["trace_id"] = format(span.trace_id, "032x")
            payload["span_id"] = format(span.span_id, "016x")
    except Exception:  # noqa: BLE001 - telemetria não pode derrubar a autorização
        pass
    print(json.dumps(payload))


@datadog_lambda_wrapper
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda authorizer (REQUEST, payload 2.0, simple response) do API Gateway
    do app (ver infra/terraform/modules/app-gateway). Duplica, na borda, a
    MESMA verificacao que o JwtDecoder do app faz: assinatura RS256 com a
    chave publica compartilhada, issuer e expiracao. Nao decide autorizacao
    por role — isso continua sendo responsabilidade exclusiva do
    SecurityConfig do app, que tem o mapa completo de rota -> role.
    """
    _log_trace("authorizer invocation")
    token = _extract_bearer_token(event)
    if not token:
        # Decisão de negócio, não erro 5xx: o span fica OK e o log permite
        # distinguir "sem token" de "token inválido/expirado".
        print("auth.result=denied reason=missing_token")
        return {"isAuthorized": False}

    try:
        claims = _use_case.execute(token)
    except Exception as error:  # noqa: BLE001 — qualquer falha de verificacao nega o acesso
        # Nunca logar o token: só o tipo da falha.
        print(f"auth.result=denied reason={type(error).__name__}")
        return {"isAuthorized": False}

    return {
        "isAuthorized": True,
        "context": {
            "sub": claims.sub,
            "scope": claims.scope,
        },
    }

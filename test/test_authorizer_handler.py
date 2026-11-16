from unittest.mock import MagicMock
import re

from lata_velha_auth.application.ports import VerifiedClaims
from lata_velha_auth.handlers import authorizer_handler


def _event(authorization=None):
    return {"headers": {"authorization": authorization} if authorization else {}}


def test_nega_quando_nao_ha_header_authorization():
    result = authorizer_handler.lambda_handler(_event(), None)
    assert result == {"isAuthorized": False}


def test_nega_quando_header_nao_comeca_com_bearer(monkeypatch):
    fake_use_case = MagicMock()
    monkeypatch.setattr(authorizer_handler, "_use_case", fake_use_case)

    result = authorizer_handler.lambda_handler(_event("token-sem-prefixo"), None)

    assert result == {"isAuthorized": False}
    fake_use_case.execute.assert_not_called()


def test_nega_quando_verificacao_falha(monkeypatch):
    fake_use_case = MagicMock()
    fake_use_case.execute.side_effect = ValueError("assinatura invalida")
    monkeypatch.setattr(authorizer_handler, "_use_case", fake_use_case)

    result = authorizer_handler.lambda_handler(_event("Bearer algum.token.aqui"), None)

    assert result == {"isAuthorized": False}
    fake_use_case.execute.assert_called_once_with("algum.token.aqui")


def test_autoriza_token_valido_e_propaga_sub_scope(monkeypatch):
    fake_use_case = MagicMock()
    fake_use_case.execute.return_value = VerifiedClaims(
        sub="8f14e45f-ceea-4ca2-8f7a-1234567890ab", scope="USER ATENDENTE"
    )
    monkeypatch.setattr(authorizer_handler, "_use_case", fake_use_case)

    result = authorizer_handler.lambda_handler(_event("Bearer algum.token.aqui"), None)

    assert result["isAuthorized"] is True
    assert result["context"]["sub"] == "8f14e45f-ceea-4ca2-8f7a-1234567890ab"
    assert result["context"]["scope"] == "USER ATENDENTE"
    if "traceparent" in result["context"]:
        assert re.fullmatch(
            r"00-[0-9a-f]{32}-[0-9a-f]{16}-01",
            result["context"]["traceparent"],
        )


def test_contexto_inclui_traceparent_quando_disponivel(monkeypatch):
    fake_use_case = MagicMock()
    fake_use_case.execute.return_value = VerifiedClaims(
        sub="8f14e45f-ceea-4ca2-8f7a-1234567890ab", scope="USER"
    )
    monkeypatch.setattr(authorizer_handler, "_use_case", fake_use_case)
    monkeypatch.setattr(
        authorizer_handler,
        "_current_traceparent",
        lambda: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
    )

    result = authorizer_handler.lambda_handler(_event("Bearer algum.token.aqui"), None)

    assert result["context"]["traceparent"] == (
        "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    )


def test_current_traceparent_tem_formato_w3c():
    from ddtrace import tracer

    with tracer.trace("test"):
        traceparent = authorizer_handler._current_traceparent()

    assert traceparent is not None
    assert re.fullmatch(r"00-[0-9a-f]{32}-[0-9a-f]{16}-01", traceparent)


def test_current_traceparent_sem_span_retorna_none(monkeypatch):
    import ddtrace

    monkeypatch.setattr(ddtrace.tracer, "current_span", lambda: None)

    assert authorizer_handler._current_traceparent() is None


def test_handler_esta_embrulhado_pelo_datadog():
    """Story 20.1 / DT-DD-31: o lambda_handler precisa estar decorado."""
    handler = authorizer_handler.lambda_handler
    assert hasattr(handler, "func")
    assert handler.func.__name__ == "lambda_handler"


def test_negacao_sem_token_loga_decisao_de_negocio(capsys):
    """Story 20.1 / AC4: negação é decisão de negócio, não erro 5xx."""
    result = authorizer_handler.lambda_handler(_event(), None)
    captured = capsys.readouterr()
    assert result == {"isAuthorized": False}
    assert "auth.result=denied" in captured.out
    assert "missing_token" in captured.out

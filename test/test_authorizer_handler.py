from unittest.mock import MagicMock

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

    assert result == {
        "isAuthorized": True,
        "context": {
            "sub": "8f14e45f-ceea-4ca2-8f7a-1234567890ab",
            "scope": "USER ATENDENTE",
        },
    }


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

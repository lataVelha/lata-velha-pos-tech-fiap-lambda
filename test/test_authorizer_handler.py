from unittest.mock import MagicMock

from jwt_authorizer import handler as authorizer_handler
from jwt_authorizer.application.ports import VerifiedClaims


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

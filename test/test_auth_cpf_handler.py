import json
from unittest.mock import MagicMock

from auth_cpf import handler as auth_cpf_handler
from auth_cpf.application.ports import IssuedToken
from auth_cpf.domain.errors import InvalidCredentialsError, UserInativoError, UserNotFoundError

VALID_CPF = "111.444.777-35"
VALID_CPF_CLEAN = "11144477735"
PASSWORD = "Admin@123"


def _event(body):
    return {"body": json.dumps(body)}


def test_retorna_400_quando_cpf_e_invalido():
    result = auth_cpf_handler.lambda_handler(_event({"cpf": "123", "password": PASSWORD}), None)
    assert result["statusCode"] == 400


def test_retorna_400_quando_cpf_nao_e_enviado():
    result = auth_cpf_handler.lambda_handler(_event({"password": PASSWORD}), None)
    assert result["statusCode"] == 400


def test_retorna_401_quando_senha_nao_e_enviada(monkeypatch):
    fake_use_case = MagicMock()
    fake_use_case.execute.side_effect = InvalidCredentialsError()
    monkeypatch.setattr(auth_cpf_handler, "_use_case", fake_use_case)

    result = auth_cpf_handler.lambda_handler(_event({"cpf": VALID_CPF}), None)

    assert result["statusCode"] == 401
    fake_use_case.execute.assert_called_once_with(VALID_CPF, None)


def test_retorna_401_quando_senha_esta_errada(monkeypatch):
    fake_use_case = MagicMock()
    fake_use_case.execute.side_effect = InvalidCredentialsError()
    monkeypatch.setattr(auth_cpf_handler, "_use_case", fake_use_case)

    result = auth_cpf_handler.lambda_handler(_event({"cpf": VALID_CPF, "password": "errada"}), None)

    assert result["statusCode"] == 401


def test_retorna_404_quando_nao_existe_usuario(monkeypatch):
    fake_use_case = MagicMock()
    fake_use_case.execute.side_effect = UserNotFoundError()
    monkeypatch.setattr(auth_cpf_handler, "_use_case", fake_use_case)

    result = auth_cpf_handler.lambda_handler(_event({"cpf": VALID_CPF, "password": PASSWORD}), None)

    assert result["statusCode"] == 404
    fake_use_case.execute.assert_called_once_with(VALID_CPF, PASSWORD)


def test_retorna_403_quando_usuario_esta_inativo(monkeypatch):
    fake_use_case = MagicMock()
    fake_use_case.execute.side_effect = UserInativoError()
    monkeypatch.setattr(auth_cpf_handler, "_use_case", fake_use_case)

    result = auth_cpf_handler.lambda_handler(_event({"cpf": VALID_CPF, "password": PASSWORD}), None)

    assert result["statusCode"] == 403


def test_retorna_200_com_token_quando_cpf_e_senha_estao_corretos(monkeypatch):
    fake_use_case = MagicMock()
    fake_use_case.execute.return_value = IssuedToken(token="fake.jwt.token", expires_in=3600)
    monkeypatch.setattr(auth_cpf_handler, "_use_case", fake_use_case)

    result = auth_cpf_handler.lambda_handler(_event({"cpf": VALID_CPF, "password": PASSWORD}), None)

    assert result["statusCode"] == 200
    body = json.loads(result["body"])
    assert body["tokenType"] == "Bearer"
    assert body["expiresIn"] == 3600
    assert body["token"] == "fake.jwt.token"


def test_retorna_500_quando_algo_inesperado_falha(monkeypatch):
    fake_use_case = MagicMock()
    fake_use_case.execute.side_effect = RuntimeError("conexao recusada")
    monkeypatch.setattr(auth_cpf_handler, "_use_case", fake_use_case)

    result = auth_cpf_handler.lambda_handler(_event({"cpf": VALID_CPF, "password": PASSWORD}), None)

    assert result["statusCode"] == 500

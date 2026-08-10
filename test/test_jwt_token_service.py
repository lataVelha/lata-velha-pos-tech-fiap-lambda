import time

import jwt as pyjwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

from lata_velha_auth.application.ports import IssuedToken, VerifiedClaims
from lata_velha_auth.domain.user import UserAuth
from lata_velha_auth.infrastructure.config import AuthCpfConfig, JwtPublicConfig
from lata_velha_auth.infrastructure.jwt_token_service import JwtTokenSigner, JwtTokenVerifier


def _generate_rsa_pem_pair():
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    private_pem = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode()
    public_pem = key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode()
    return private_pem, public_pem


@pytest.fixture
def rsa_keys():
    return _generate_rsa_pem_pair()


@pytest.fixture
def auth_cpf_config(rsa_keys):
    private_pem, _ = rsa_keys
    return AuthCpfConfig(
        jwt_private_key=private_pem,
        jwt_issuer="lata-velha",
        jwt_expires_in=3600,
        db_host="localhost",
        db_port=5432,
        db_name="lata_velha",
        db_user="admin",
        db_password="admin123",
    )


def _user(credential_hash: str = "hash-irrelevante-para-este-teste") -> UserAuth:
    return UserAuth(
        id="8f14e45f-ceea-4ca2-8f7a-1234567890ab",
        username="atendente@latavelha.com",
        ativo=True,
        roles=["USER", "ATENDENTE"],
        credential_hash=credential_hash,
    )


def test_assina_token_valido_com_claims_esperadas(auth_cpf_config, rsa_keys):
    _, public_pem = rsa_keys
    signer = JwtTokenSigner(auth_cpf_config)

    issued: IssuedToken = signer.issue(_user())

    assert issued.expires_in == 3600
    decoded = pyjwt.decode(issued.token, public_pem, algorithms=["RS256"], issuer="lata-velha")
    assert decoded["sub"] == "8f14e45f-ceea-4ca2-8f7a-1234567890ab"
    assert decoded["iss"] == "lata-velha"
    assert decoded["scope"] == "USER ATENDENTE"


def test_verifica_token_valido_e_propaga_sub_scope(auth_cpf_config, rsa_keys):
    _, public_pem = rsa_keys
    signer = JwtTokenSigner(auth_cpf_config)
    verifier = JwtTokenVerifier(JwtPublicConfig(jwt_public_key=public_pem, jwt_issuer="lata-velha"))

    issued = signer.issue(_user())
    claims: VerifiedClaims = verifier.verify(issued.token)

    assert claims.sub == "8f14e45f-ceea-4ca2-8f7a-1234567890ab"
    assert claims.scope == "USER ATENDENTE"


def test_rejeita_token_expirado(auth_cpf_config, rsa_keys):
    _, public_pem = rsa_keys
    verifier = JwtTokenVerifier(JwtPublicConfig(jwt_public_key=public_pem, jwt_issuer="lata-velha"))

    now = int(time.time())
    expired_token = pyjwt.encode(
        {"scope": "USER", "iat": now - 20, "exp": now - 10, "iss": "lata-velha", "sub": "x"},
        auth_cpf_config.jwt_private_key,
        algorithm="RS256",
    )

    with pytest.raises(pyjwt.ExpiredSignatureError):
        verifier.verify(expired_token)


def test_rejeita_token_com_issuer_diferente(auth_cpf_config, rsa_keys):
    _, public_pem = rsa_keys
    verifier = JwtTokenVerifier(JwtPublicConfig(jwt_public_key=public_pem, jwt_issuer="lata-velha"))

    now = int(time.time())
    token = pyjwt.encode(
        {"scope": "USER", "iat": now, "exp": now + 3600, "iss": "outro-issuer", "sub": "x"},
        auth_cpf_config.jwt_private_key,
        algorithm="RS256",
    )

    with pytest.raises(pyjwt.InvalidIssuerError):
        verifier.verify(token)


def test_rejeita_token_assinado_com_outra_chave(auth_cpf_config, rsa_keys):
    _, public_pem = rsa_keys
    rogue_private_pem, _ = _generate_rsa_pem_pair()
    verifier = JwtTokenVerifier(JwtPublicConfig(jwt_public_key=public_pem, jwt_issuer="lata-velha"))

    now = int(time.time())
    token = pyjwt.encode(
        {"scope": "USER", "iat": now, "exp": now + 3600, "iss": "lata-velha", "sub": "x"},
        rogue_private_pem,
        algorithm="RS256",
    )

    with pytest.raises(pyjwt.InvalidSignatureError):
        verifier.verify(token)

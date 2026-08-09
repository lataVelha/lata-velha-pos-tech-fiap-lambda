import time
from dataclasses import dataclass
from typing import List

import jwt as pyjwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

from shared.jwt_token_service import IssuedToken, JwtTokenSigner, JwtTokenVerifier, VerifiedClaims

ISSUER = "lata-velha"
EXPIRES_IN = 3600


@dataclass(frozen=True)
class _FakeUser:
    """So precisa satisfazer o Protocol SigningUser (id + roles) — nem
    precisa ser UserAuth de verdade, mostrando que shared/ nao depende de
    auth_cpf/domain."""

    id: str
    roles: List[str]


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


def test_assina_token_valido_com_claims_esperadas(rsa_keys):
    private_pem, public_pem = rsa_keys
    signer = JwtTokenSigner(private_key=private_pem, issuer=ISSUER, expires_in=EXPIRES_IN)

    issued: IssuedToken = signer.issue(_FakeUser(id="8f14e45f-ceea-4ca2-8f7a-1234567890ab", roles=["USER", "ATENDENTE"]))

    assert issued.expires_in == EXPIRES_IN
    decoded = pyjwt.decode(issued.token, public_pem, algorithms=["RS256"], issuer=ISSUER)
    assert decoded["sub"] == "8f14e45f-ceea-4ca2-8f7a-1234567890ab"
    assert decoded["iss"] == ISSUER
    assert decoded["scope"] == "USER ATENDENTE"


def test_verifica_token_valido_e_propaga_sub_scope(rsa_keys):
    private_pem, public_pem = rsa_keys
    signer = JwtTokenSigner(private_key=private_pem, issuer=ISSUER, expires_in=EXPIRES_IN)
    verifier = JwtTokenVerifier(public_key=public_pem, issuer=ISSUER)

    issued = signer.issue(_FakeUser(id="8f14e45f-ceea-4ca2-8f7a-1234567890ab", roles=["USER", "ATENDENTE"]))
    claims: VerifiedClaims = verifier.verify(issued.token)

    assert claims.sub == "8f14e45f-ceea-4ca2-8f7a-1234567890ab"
    assert claims.scope == "USER ATENDENTE"


def test_rejeita_token_expirado(rsa_keys):
    private_pem, public_pem = rsa_keys
    verifier = JwtTokenVerifier(public_key=public_pem, issuer=ISSUER)

    now = int(time.time())
    expired_token = pyjwt.encode(
        {"scope": "USER", "iat": now - 20, "exp": now - 10, "iss": ISSUER, "sub": "x"},
        private_pem,
        algorithm="RS256",
    )

    with pytest.raises(pyjwt.ExpiredSignatureError):
        verifier.verify(expired_token)


def test_rejeita_token_com_issuer_diferente(rsa_keys):
    private_pem, public_pem = rsa_keys
    verifier = JwtTokenVerifier(public_key=public_pem, issuer=ISSUER)

    now = int(time.time())
    token = pyjwt.encode(
        {"scope": "USER", "iat": now, "exp": now + 3600, "iss": "outro-issuer", "sub": "x"},
        private_pem,
        algorithm="RS256",
    )

    with pytest.raises(pyjwt.InvalidIssuerError):
        verifier.verify(token)


def test_rejeita_token_assinado_com_outra_chave(rsa_keys):
    _, public_pem = rsa_keys
    rogue_private_pem, _ = _generate_rsa_pem_pair()
    verifier = JwtTokenVerifier(public_key=public_pem, issuer=ISSUER)

    now = int(time.time())
    token = pyjwt.encode(
        {"scope": "USER", "iat": now, "exp": now + 3600, "iss": ISSUER, "sub": "x"},
        rogue_private_pem,
        algorithm="RS256",
    )

    with pytest.raises(pyjwt.InvalidSignatureError):
        verifier.verify(token)

from auth_cpf.infrastructure.bcrypt_password_verifier import BcryptPasswordVerifier

# Hash real gerado pelo BCryptPasswordEncoder do Spring Security (seed
# V2__insert_data.sql, usuario admin@latavelha.com) — trava, como teste de
# regressao, que a lib bcrypt do Python continua compativel com o hash que o
# app Java gera (mesmo prefixo $2a$, mesmo cost 10).
SPRING_BCRYPT_HASH = "$2a$10$1dSgICxSKMCZaDflzpaD.Ovyb34nyvz/NfvPsg70gBfNcZ9o4u3UW"
CORRECT_PASSWORD = "Admin@123"


def test_aceita_senha_correta_contra_hash_gerado_pelo_spring():
    verifier = BcryptPasswordVerifier()
    assert verifier.verify(CORRECT_PASSWORD, SPRING_BCRYPT_HASH) is True


def test_rejeita_senha_incorreta():
    verifier = BcryptPasswordVerifier()
    assert verifier.verify("senha-errada", SPRING_BCRYPT_HASH) is False


def test_rejeita_senha_vazia():
    verifier = BcryptPasswordVerifier()
    assert verifier.verify("", SPRING_BCRYPT_HASH) is False


def test_rejeita_hash_vazio():
    verifier = BcryptPasswordVerifier()
    assert verifier.verify(CORRECT_PASSWORD, "") is False


def test_rejeita_hash_mal_formado_sem_lancar_excecao():
    verifier = BcryptPasswordVerifier()
    assert verifier.verify(CORRECT_PASSWORD, "isso-nao-e-um-hash-bcrypt") is False

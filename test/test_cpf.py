from lata_velha_auth.domain.cpf import clean_cpf, is_valid_cpf


def test_limpa_mascara_do_cpf():
    assert clean_cpf("111.444.777-35") == "11144477735"


def test_aceita_cpf_valido_com_mascara():
    assert is_valid_cpf("111.444.777-35") is True


def test_aceita_cpf_valido_sem_mascara():
    assert is_valid_cpf("11144477735") is True


def test_rejeita_cpf_com_tamanho_errado():
    assert is_valid_cpf("123") is False


def test_rejeita_cpf_com_todos_digitos_iguais():
    assert is_valid_cpf("11111111111") is False


def test_rejeita_cpf_com_digito_verificador_invalido():
    assert is_valid_cpf("111.444.777-36") is False

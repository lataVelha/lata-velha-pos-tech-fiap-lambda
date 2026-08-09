"""
Validacao de CPF. Espelha o algoritmo usado pelo app principal em
br.com.lata.velha.ordem_servico.domain.value_objects.Documento#isValidCpf,
para que os dois lados concordem sobre o que e um CPF valido. Camada de
dominio: zero dependencia de framework/biblioteca externa.
"""

import re


def clean_cpf(raw: str) -> str:
    return re.sub(r"\D", "", raw)


def is_valid_cpf(raw: str) -> bool:
    cpf = clean_cpf(raw)

    if len(cpf) != 11:
        return False
    if len(set(cpf)) == 1:
        return False

    digits = [int(c) for c in cpf]

    total = sum(digits[i] * (10 - i) for i in range(9))
    first_digit = 11 - (total % 11)
    if first_digit > 9:
        first_digit = 0
    if first_digit != digits[9]:
        return False

    total = sum(digits[i] * (11 - i) for i in range(10))
    second_digit = 11 - (total % 11)
    if second_digit > 9:
        second_digit = 0
    return second_digit == digits[10]

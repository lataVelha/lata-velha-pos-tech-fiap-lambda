/**
 * Validacao de CPF. Espelha o algoritmo usado pelo app principal em
 * br.com.lata.velha.ordem_servico.domain.value_objects.Documento#isValidCpf,
 * para que os dois lados concordem sobre o que e um CPF valido.
 */

export function cleanCpf(raw: string): string {
  return raw.replace(/[^\d]/g, "");
}

export function isValidCpf(raw: string): boolean {
  const cpf = cleanCpf(raw);

  if (cpf.length !== 11) return false;
  if (new Set(cpf.split("")).size === 1) return false;

  const digits = cpf.split("").map(Number);

  let sum = 0;
  for (let i = 0; i < 9; i++) {
    sum += digits[i] * (10 - i);
  }
  let firstDigit = 11 - (sum % 11);
  if (firstDigit > 9) firstDigit = 0;
  if (firstDigit !== digits[9]) return false;

  sum = 0;
  for (let i = 0; i < 10; i++) {
    sum += digits[i] * (11 - i);
  }
  let secondDigit = 11 - (sum % 11);
  if (secondDigit > 9) secondDigit = 0;
  return secondDigit === digits[10];
}

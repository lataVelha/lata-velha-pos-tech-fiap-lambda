import { cleanCpf, isValidCpf } from "../src/cpf";

describe("cleanCpf", () => {
  it("remove pontuacao e espacos", () => {
    expect(cleanCpf("111.444.777-35")).toBe("11144477735");
    expect(cleanCpf(" 111 444 777 35 ")).toBe("11144477735");
  });
});

describe("isValidCpf", () => {
  it("aceita CPFs validos, formatados ou nao", () => {
    expect(isValidCpf("11144477735")).toBe(true);
    expect(isValidCpf("111.444.777-35")).toBe(true);
    expect(isValidCpf("22255588846")).toBe(true);
    expect(isValidCpf("33366699957")).toBe(true);
  });

  it("rejeita CPF com digito verificador errado", () => {
    expect(isValidCpf("11144477736")).toBe(false);
  });

  it("rejeita CPF com todos os digitos iguais", () => {
    expect(isValidCpf("11111111111")).toBe(false);
    expect(isValidCpf("00000000000")).toBe(false);
  });

  it("rejeita CPF com tamanho invalido", () => {
    expect(isValidCpf("123")).toBe(false);
    expect(isValidCpf("123456789012")).toBe(false);
    expect(isValidCpf("")).toBe(false);
  });

  it("rejeita entrada nao numerica apos limpeza", () => {
    expect(isValidCpf("abc.def.ghi-jk")).toBe(false);
  });
});

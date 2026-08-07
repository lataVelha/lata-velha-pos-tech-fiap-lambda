export class HttpError extends Error {
  constructor(
    public readonly statusCode: number,
    message: string,
  ) {
    super(message);
    this.name = "HttpError";
  }
}

export class InvalidCpfError extends HttpError {
  constructor(message = "CPF invalido") {
    super(400, message);
  }
}

export class UserNotFoundError extends HttpError {
  constructor() {
    super(404, "Usuario nao encontrado para o CPF informado");
  }
}

export class UserInativoError extends HttpError {
  constructor() {
    super(403, "Usuario inativo");
  }
}

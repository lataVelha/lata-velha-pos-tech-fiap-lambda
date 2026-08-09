#!/usr/bin/env bash
#
# build.sh — empacota as duas lambdas (auth-cpf + jwt-authorizer) pra deploy.
#
# Cada uma vira um diretorio em build/<nome>/ com dois pacotes Python:
# shared/ (comum as duas — env.py + jwt_token_service.py) e o pacote
# especifico do projeto (auth_cpf/ ou jwt_authorizer/) — mais as dependencias
# baixadas como wheel PRE-COMPILADA pra Linux x86_64 (manylinux2014), mesmo
# rodando este script no macOS — sem isso, "pip install" compilaria (ou
# baixaria) a wheel da SUA maquina, que nao roda no runtime da Lambda
# (Amazon Linux).
#
# auth-cpf usa Postgres (pg8000) e BCrypt (bcrypt) alem de assinar o token
# (chave privada); jwt-authorizer so verifica assinatura (chave publica) —
# por isso cada uma tem seu proprio requirements/*.txt, ver README.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
PYTHON_VERSION="3.12"
PYTHON_ABI="cp312"
PLATFORM="manylinux2014_x86_64"

rm -rf "$BUILD_DIR"

build_function() {
  local name="$1" requirements_file="$2" project_package="$3"
  local target="$BUILD_DIR/$name"
  mkdir -p "$target"

  pip install \
    --quiet \
    --requirement "$SCRIPT_DIR/requirements/$requirements_file" \
    --platform "$PLATFORM" \
    --python-version "$PYTHON_VERSION" \
    --implementation cp \
    --abi "$PYTHON_ABI" \
    --only-binary=:all: \
    --target "$target" \
    --upgrade

  cp -r "$SCRIPT_DIR/src/shared" "$target/"
  cp -r "$SCRIPT_DIR/src/$project_package" "$target/"
}

build_function "auth-cpf" "auth-cpf.txt" "auth_cpf"
build_function "jwt-authorizer" "jwt-authorizer.txt" "jwt_authorizer"

echo "Build concluido: $BUILD_DIR/auth-cpf/ e $BUILD_DIR/jwt-authorizer/"

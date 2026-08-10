#!/usr/bin/env bash
#
# build.sh — empacota as duas lambdas (auth-cpf + jwt-authorizer) pra deploy.
#
# Cada uma vira um diretorio em build/<nome>/ com o pacote lata_velha_auth/
# (a mesma copia pras duas — codigo Python puro, nao tem custo empacotar o
# que nao e usado) + as dependencias baixadas como wheel PRE-COMPILADA pra
# Linux x86_64 (manylinux2014), mesmo rodando este script no macOS — sem
# isso, "pip install" compilaria (ou baixaria) a wheel da SUA maquina, que
# nao roda no runtime da Lambda (Amazon Linux).
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
  local name="$1" requirements_file="$2"
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

  cp -r "$SCRIPT_DIR/src/lata_velha_auth" "$target/"
}

build_function "auth-cpf" "auth-cpf.txt"
build_function "jwt-authorizer" "jwt-authorizer.txt"

echo "Build concluido: $BUILD_DIR/auth-cpf/ e $BUILD_DIR/jwt-authorizer/"

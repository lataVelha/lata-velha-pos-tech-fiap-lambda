import os

# Setados no import deste conftest (pytest carrega conftest.py ANTES de
# coletar os modulos de teste) — precisam existir antes mesmo dos handlers
# serem importados, ja que AuthCpfConfig.from_env()/JwtPublicConfig.from_env()
# rodam no module-level deles (composition root, no cold start). Uma
# autouse fixture com monkeypatch.setenv chegaria tarde demais: so roda por
# teste, depois da fase de coleta/import.
# Datadog: desabilita o tracer nos testes (sem rede) e fornece valores
# dummy para o wrapper não tentar inicializar a extension.
os.environ.setdefault("DD_TRACE_ENABLED", "false")
os.environ.setdefault("DD_API_KEY", "dummy")
os.environ.setdefault("DD_SITE", "us5.datadoghq.com")
os.environ.setdefault("DD_ENV", "test")
os.environ.setdefault("DD_SERVICE", "lata-velha-lambda-test")

os.environ.setdefault("JWT_PRIVATE_KEY", "dummy")
os.environ.setdefault("JWT_PUBLIC_KEY", "dummy")
os.environ.setdefault("JWT_ISSUER", "lata-velha")
os.environ.setdefault("JWT_EXPIRES_IN", "3600")
os.environ.setdefault("DB_HOST", "localhost")
os.environ.setdefault("DB_PORT", "5432")
os.environ.setdefault("DB_NAME", "lata_velha")
os.environ.setdefault("DB_USER", "admin")
os.environ.setdefault("DB_PASSWORD", "admin123")

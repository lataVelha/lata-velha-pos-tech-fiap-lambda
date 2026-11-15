"""Forwarder de access logs do API Gateway para o Datadog Logs API.

Story 20.2: o log group `/aws/apigateway/lata-velha-app-api` recebe os access
logs em JSON. Uma subscription filter invoca esta Lambda, que:

1. descompacta o payload do CloudWatch Logs (base64 + gzip);
2. faz allowlist dos campos (sem IP/PII);
3. envia cada registro para `https://http-intake.logs.us5.datadoghq.com/api/v2/logs`
   com `service:lata-velha-edge`, `env:prod`, `source:apigateway`.

Sem dependências externas (somente stdlib), para caber no zip da Lambda.
"""

from __future__ import annotations

import base64
import gzip
import json
import os
import urllib.error
import urllib.request
from typing import Any

DD_SITE = os.environ.get("DD_SITE", "us5.datadoghq.com")
DD_API_KEY = os.environ.get("DD_API_KEY", "")
DD_ENV = os.environ.get("DD_ENV", "prod")
SERVICE = "lata-velha-edge"

# Allowlist: nada de IP, query string, headers ou body.
ALLOWED_FIELDS = (
    "requestId",
    "requestTime",
    "httpMethod",
    "routeKey",
    "status",
    "responseLatency",
    "integrationLatency",
    "responseLength",
    "integrationError",
)


def _decode_cloudwatch_event(event: dict[str, Any]) -> list[dict[str, Any]]:
    encoded = (event.get("awslogs") or {}).get("data")
    if not encoded:
        return []
    raw = gzip.decompress(base64.b64decode(encoded))
    payload = json.loads(raw)
    records: list[dict[str, Any]] = []
    for log_event in payload.get("logEvents", []) or []:
        message = log_event.get("message", "")
        try:
            record = json.loads(message)
        except (TypeError, ValueError):
            continue
        if isinstance(record, dict):
            records.append(record)
    return records


def sanitize_record(record: dict[str, Any]) -> dict[str, Any]:
    """Mantém só campos allowlistados e normaliza os tipos."""
    clean = {key: record.get(key) for key in ALLOWED_FIELDS if record.get(key) is not None}
    status = clean.get("status")
    try:
        status_code = int(status)
    except (TypeError, ValueError):
        status_code = 0

    def _number(key: str) -> float | None:
        try:
            return float(clean[key])
        except (KeyError, TypeError, ValueError):
            return None

    return {
        "ddsource": "apigateway",
        "service": SERVICE,
        "host": "apigateway",
        "ddtags": f"env:{DD_ENV},service:{SERVICE},source:apigateway",
        "message": json.dumps(clean, ensure_ascii=False, separators=(",", ":")),
        "http": {
            "status_code": status_code,
            "method": clean.get("httpMethod"),
        },
        "route_key": clean.get("routeKey"),
        "request_id": clean.get("requestId"),
        "response_latency": _number("responseLatency"),
        "integration_latency": _number("integrationLatency"),
        "integration_error": clean.get("integrationError"),
    }


def _post_to_datadog(logs: list[dict[str, Any]]) -> None:
    if not DD_API_KEY or not logs:
        return
    url = f"https://http-intake.logs.{DD_SITE}/api/v2/logs"
    body = json.dumps(logs, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "DD-API-KEY": DD_API_KEY,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            response.read()
    except urllib.error.HTTPError as error:
        # 4xx é permanente (chave/rota); 5xx/429 podem ser retentados pelo
        # CloudWatch Logs se a Lambda falhar.
        if error.code >= 500 or error.code == 429:
            raise
        print(f"datadog.logs.http_error status={error.code}")


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    records = _decode_cloudwatch_event(event)
    logs = [sanitize_record(record) for record in records]
    _post_to_datadog(logs)
    return {"statusCode": 200, "body": f"forwarded={len(logs)}"}

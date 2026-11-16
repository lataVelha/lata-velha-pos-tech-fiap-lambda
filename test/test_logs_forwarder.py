import base64
import gzip
import json
from unittest.mock import patch

from lata_velha_logs_forwarder import handler as forwarder


def _event(records):
    payload = {"logEvents": [{"id": str(i), "timestamp": 1, "message": json.dumps(r)} for i, r in enumerate(records)]}
    compressed = gzip.compress(json.dumps(payload).encode())
    return {"awslogs": {"data": base64.b64encode(compressed).decode()}}


def test_forwarder_sanitiza_e_envia_sem_ip():
    sent = {}

    def fake_post(logs):
        sent["logs"] = logs

    record = {
        "requestId": "abc",
        "ip": "203.0.113.10",
        "httpMethod": "GET",
        "routeKey": "GET /ordens-servico",
        "status": "500",
        "responseLatency": "123",
        "integrationError": None,
        "body": "cpf=11144477735",
    }
    with patch.object(forwarder, "_post_to_datadog", side_effect=fake_post):
        result = forwarder.handler(_event([record]), None)

    assert result == {"statusCode": 200, "body": "forwarded=1"}
    log = sent["logs"][0]
    assert log["service"] == "lata-velha-edge"
    assert log["ddsource"] == "apigateway"
    assert log["http"]["status_code"] == 500
    assert log["route_key"] == "GET /ordens-servico"
    # allowlist: IP e body não podem vazar
    assert "203.0.113.10" not in json.dumps(log)
    assert "11144477735" not in json.dumps(log)


def test_forwarder_ignora_payload_invalido():
    compressed = gzip.compress(json.dumps({"logEvents": [{"message": "not-json"}]}).encode())
    event = {"awslogs": {"data": base64.b64encode(compressed).decode()}}
    with patch.object(forwarder, "_post_to_datadog") as post:
        result = forwarder.handler(event, None)
    assert result["body"] == "forwarded=0"
    post.assert_called_once_with([])


def test_forwarder_encaminha_evento_cloudwatch():
    sent = {}

    def fake_post(payload):
        sent["payload"] = payload

    event = {
        "source": "aws.cloudwatch",
        "detail-type": "CloudWatch Alarm State Change",
        "detail": {
            "alarmName": "lata-velha-os-service-events-dlq-messages",
            "state": {"value": "ALARM", "reason": "Threshold crossed"},
        },
    }
    with patch.object(forwarder, "_post_event", side_effect=fake_post):
        result = forwarder.handler(event, None)

    assert result["statusCode"] == 200
    assert "alarm=lata-velha-os-service-events-dlq-messages" in result["body"]
    payload = sent["payload"]
    assert payload["alert_type"] == "error"
    assert payload["title"] == "CloudWatch alarm lata-velha-os-service-events-dlq-messages"
    assert "source:cloudwatch" in payload["tags"]

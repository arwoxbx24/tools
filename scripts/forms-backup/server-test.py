import http.client
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).parent


def request(port, method, path, body=None, headers=None):
    client = http.client.HTTPConnection("127.0.0.1", port, timeout=1)
    client.request(method, path, body, headers or {})
    response = client.getresponse()
    result = response.status, dict(response.getheaders()), response.read()
    client.close()
    return result


with tempfile.TemporaryDirectory() as temp:
    Path(temp, "index.py").write_text(
        "import json\n"
        "def handler(event, _):\n"
        " if event['path'] == '/boom': raise RuntimeError()\n"
        " return {'statusCode': 302, 'headers': {'Location': '/ok'}, 'body': json.dumps(event)}\n"
    )
    probe = socket.socket()
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()
    env = os.environ | {"FORMS_HANDLER_DIR": temp, "FORMS_BACKUP_BIND": "127.0.0.1", "FORMS_BACKUP_PORT": str(port)}
    process = subprocess.Popen([sys.executable, ROOT / "server.py"], env=env, stderr=subprocess.DEVNULL)
    try:
        for _ in range(20):
            try:
                status, headers, body = request(port, "GET", "/?a=1")
                break
            except ConnectionRefusedError:
                time.sleep(.05)
        else:
            raise AssertionError("server did not start")
        event = json.loads(body)
        assert status == 302 and headers["Location"] == "/ok"
        assert event["httpMethod"] == "GET" and event["queryStringParameters"]["a"] == "1"
        status, _, body = request(port, "POST", "/", "NAME=x&PHONE=1", {"X-Real-IP": "9.9.9.9", "X-Real-Remote-Address": "6.6.6.6"})
        event = json.loads(body)
        assert status == 302 and "NAME=x" in event["body"]
        assert event["headers"]["X-Real-Remote-Address"] == "9.9.9.9"
        assert request(port, "GET", "/boom")[0] == 502
        print("PASS 3/3")
    finally:
        process.terminate()
        process.wait()

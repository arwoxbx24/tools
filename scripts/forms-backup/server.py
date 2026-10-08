import base64
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qsl, urlsplit

sys.path.insert(0, os.environ.get(
    "FORMS_HANDLER_DIR",
    "/root/workspaces/projects/arwox-v3-src/site78-releases/2026-07-29/backend-arwox-lead-form",
))
import index


class FormsBackupHandler(BaseHTTPRequestHandler):
    def _handle(self):
        try:
            raw = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        except ValueError:
            raw = b""
        try:
            body, encoded = raw.decode(), False
        except UnicodeDecodeError:
            body, encoded = base64.b64encode(raw).decode(), True
        request = urlsplit(self.path)
        headers = dict(self.headers)
        headers["X-Real-Remote-Address"] = self.headers.get("X-Real-IP", "")
        event = {
            "httpMethod": self.command,
            "headers": headers,
            "body": body,
            "isBase64Encoded": encoded,
            "queryStringParameters": dict(parse_qsl(request.query, keep_blank_values=True)),
            "path": request.path,
        }
        try:
            response = index.handler(event, None)
        except Exception:
            print("forms-backup handler failed", file=sys.stderr)
            self.send_response(502)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        body = response.get("body") or ""
        data = base64.b64decode(body) if response.get("isBase64Encoded") else body.encode()
        self.send_response(response.get("statusCode", 200))
        for name, value in (response.get("headers") or {}).items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_GET = _handle
    do_POST = _handle


def main():
    server = ThreadingHTTPServer((
        os.environ.get("FORMS_BACKUP_BIND", "172.17.0.1"),
        int(os.environ.get("FORMS_BACKUP_PORT", "20140")),
    ), FormsBackupHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()

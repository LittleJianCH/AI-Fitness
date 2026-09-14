"""Isolated UI-test transport: inject one stale curve revision per workout.

All authentication and workout operations still reach the disposable backend.
The single altered response makes the refresh/unmount cancellation regression
deterministic without adding test switches to the application or backend.
"""

import http.client
import http.server
import json
import os
import pathlib
import sys
import threading

seen = set()
lock = threading.Lock()


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # Never log requests, credentials or bodies.

    def proxy(self):
        connection = http.client.HTTPConnection("127.0.0.1", int(os.environ["PORT"]), timeout=30)
        try:
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            headers = {k: v for k, v in self.headers.items() if k.lower() not in ("host", "connection")}
            connection.request(self.command, self.path, body, headers)
            response = connection.getresponse()
            payload = response.read()
            if self.command == "GET" and self.path.endswith("/power-curve") and response.status == 200:
                with lock:
                    stale = self.path not in seen
                    seen.add(self.path)
                if stale:
                    curve = json.loads(payload)
                    curve["inputRevision"] = str(int(curve["inputRevision"]) + 1)
                    payload = json.dumps(curve).encode()
            self.send_response(response.status)
            for key, value in response.getheaders():
                if key.lower() not in ("content-length", "transfer-encoding", "connection"):
                    self.send_header(key, value)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        finally:
            connection.close()

    do_GET = do_POST = do_PUT = do_DELETE = proxy


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
pathlib.Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()

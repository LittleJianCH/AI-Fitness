"""Loopback-only transport for the disposable iOS integration harness.

Inject one stale curve revision per workout. Explicitly enabling
FITNESS_TEST_ANALYSIS_FAILURE_CONTROLS=1 also permits the UI tests to toggle
synthetic analysis failures through POST /__test/analysis-failure/on or /off.
All API requests still reach the disposable backend; only successful analysis
responses are replaced. No fault switches are added to the app or backend.
"""

import http.client
import http.server
import json
import os
import pathlib
import sys
import threading

seen = set()
fault_controls_enabled = os.environ.get("FITNESS_TEST_ANALYSIS_FAILURE_CONTROLS") == "1"
failure_enabled = False
lock = threading.Lock()


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # Never log requests, credentials or bodies.

    def proxy(self):
        global failure_enabled
        if (fault_controls_enabled and self.command == "POST"
                and self.path in ("/__test/analysis-failure/on", "/__test/analysis-failure/off")):
            with lock:
                failure_enabled = self.path.endswith("/on")
            self.send_response(204)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        connection = http.client.HTTPConnection("127.0.0.1", int(os.environ["PORT"]), timeout=30)
        try:
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            headers = {k: v for k, v in self.headers.items() if k.lower() not in ("host", "connection")}
            connection.request(self.command, self.path, body, headers)
            response = connection.getresponse()
            payload = response.read()
            response_status = response.status
            with lock:
                fail_analysis = failure_enabled
            if self.command == "GET" and self.path.endswith("/analysis") and response.status == 200 and fail_analysis:
                response_status = 503
                payload = b'{"error":"Synthetic derived analysis failure"}'
            if self.command == "GET" and self.path.endswith("/power-curve") and response.status == 200:
                with lock:
                    stale = self.path not in seen and not fail_analysis
                    seen.add(self.path)
                if stale:
                    curve = json.loads(payload)
                    curve["inputRevision"] = str(int(curve["inputRevision"]) + 1)
                    payload = json.dumps(curve).encode()
            self.send_response(response_status)
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

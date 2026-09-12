"""Local-only redirect fixture. Never logs requests or credentials."""
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path == '/api/v1/me':
            self.send_response(307)
            self.send_header('Location', '/redirected')
            self.end_headers()
        else:
            self.send_response(200)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.end_headers()
            self.wfile.write(b'{"createdAt":"2026-09-12T00:00:00Z","id":"00000000-0000-0000-0000-000000000001","username":"alice"}')


server = HTTPServer(('127.0.0.1', 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()

#!/usr/bin/env python3
# buildin-bridge-listener.py — one-shot localhost HTTP receiver.
#
# Usage: buildin-bridge-listener.py PORT OUTFILE
#
# Binds 127.0.0.1:<PORT>, accepts one POST request, writes request body to
# OUTFILE, responds 200, then exits. Implements CORS so a browser tab on
# https://buildin.ai can fetch() into us. Chrome treats http://127.0.0.1 as a
# secure context, so mixed-content blocking does not apply.
#
# Used by buildin-login.sh bridge-start/bridge-wait to move the `next_auth`
# cookie from the browser to the local .env without going through the system
# clipboard (which has proven unreliable on macOS via DevTools MCP).
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

if len(sys.argv) < 3:
    sys.stderr.write("usage: buildin-bridge-listener.py PORT OUTFILE\n")
    sys.exit(2)

PORT = int(sys.argv[1])
OUT  = sys.argv[2]


class Handler(BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(n).decode("utf-8", "replace").strip()
        with open(OUT, "w") as f:
            f.write(body)
        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *args, **kwargs):
        pass  # silent


srv = HTTPServer(("127.0.0.1", PORT), Handler)
srv.handle_request()  # serve exactly one request, then exit

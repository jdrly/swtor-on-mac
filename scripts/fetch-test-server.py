"""A local HTTP server for scripts/test-sandbox.sh's download tests (som.sh fetch-engine with
SWTOR_ON_MAC_ENGINE_URL): it serves one file under /<mode>/<its name> and misbehaves the way
networks do.

    python3 -I scripts/fetch-test-server.py <file> <port>

Modes (the first request of a path is the "first try"):
  ok         the file, with its length; Range requests answered (206)
  html       a captive portal's page with HTTP 200
  dropnolen  first try: no length, the connection closed after 32 MB (curl calls that a
             success); then as ok
  droplen    the first two tries: with its length, closed after 32 MB more each (curl: exit 18,
             the download resumes); then as ok
  norange    first try: closed after 32 MB with a length; Range requests get the whole file with
             200 (a server that can't resume)
  changed    the file with one byte changed in the middle (the same size, an xz start)
  alwaysdrop every try closed after 32 MB more (with its length)
Requests are logged to stdout as "<mode> <range or ->".
"""
import http.server
import os
import sys

DATA = open(sys.argv[1], "rb").read()
NAME = os.path.basename(sys.argv[1])
CUT = 32 * 1024 * 1024
tries = {}


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def send_body(self, body, start=0, length=True, close_after=None):
        if start:
            self.send_response(206)
            self.send_header("Content-Range", f"bytes {start}-{len(DATA) - 1}/{len(DATA)}")
        else:
            self.send_response(200)
        if length:
            self.send_header("Content-Length", str(len(body)))
        else:
            self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body[:close_after] if close_after is not None else body)
        self.wfile.flush()
        if close_after is not None or not length:
            self.close_connection = True

    def do_GET(self):
        parts = self.path.strip("/").split("/")
        if len(parts) != 2 or parts[1] != NAME:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        mode = parts[0]
        n = tries[mode] = tries.get(mode, 0) + 1
        rng = self.headers.get("Range", "")
        start = int(rng[len("bytes="):].split("-")[0]) if rng.startswith("bytes=") else 0
        print(mode, rng or "-", flush=True)
        if mode == "html":
            page = b"<!DOCTYPE html><html><head><title>Wi-Fi login</title></head><body>Please log in</body></html>"
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(page)))
            self.end_headers()
            self.wfile.write(page)
        elif mode == "changed":
            body = bytearray(DATA)
            body[len(body) // 2] ^= 0xFF
            self.send_body(bytes(body))
        elif mode == "dropnolen" and n == 1:
            self.send_body(DATA, length=False, close_after=CUT)
        elif mode == "alwaysdrop" or (mode == "droplen" and n <= 2):
            self.send_body(DATA[start:], start=start, close_after=CUT)
        elif mode == "norange":
            if n == 1:
                self.send_body(DATA, close_after=CUT)
            else:
                self.send_body(DATA)   # ignores Range
        else:
            self.send_body(DATA[start:], start=start)


class Server(http.server.ThreadingHTTPServer):
    def handle_error(self, request, client_address):
        pass   # (the client hanging up on a cut-off transfer is expected)


Server(("127.0.0.1", int(sys.argv[2])), Handler).serve_forever()

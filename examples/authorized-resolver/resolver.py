"""Optional reference server: only serves an explicit, operator-owned URL map.
Deploy behind your own HTTPS reverse proxy; never expose an untrusted open proxy.
No source scraping, DRM bypass, third-party credentials, or arbitrary JS execution.
"""
import argparse
import json
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

parser = argparse.ArgumentParser()
parser.add_argument("--catalog", required=True)
parser.add_argument("--port", type=int, default=8765)
args = parser.parse_args()
catalog = json.loads(Path(args.catalog).read_text(encoding="utf-8"))

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def respond(self, status, body):
        raw = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):
        try:
            if self.path != "/resolve":
                return self.respond(404, {"error": "Not found"})
            n = int(self.headers.get("Content-Length", "0"))
            if not 0 < n <= 65536:
                return self.respond(400, {"error": "Invalid request size"})
            req = json.loads(self.rfile.read(n))
            p, i, q = req["platform"], req["id"], req["quality"]
            if p not in {"tx", "wy", "kg", "kw", "mg"} or q not in {"128k", "320k", "flac", "flac24bit"}:
                return self.respond(400, {"error": "Invalid source or quality"})
            row = catalog.get(f"{p}:{i}", {})
            media = row.get(q)
            if not isinstance(media, str):
                return self.respond(404, {"error": "No authorized URL for requested quality"})
            parsed = urlsplit(media)
            if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
                return self.respond(500, {"error": "Invalid server media configuration"})
            response = {"url": media}
            if isinstance(row.get("lyrics"), str):
                response["lyrics"] = row["lyrics"]
            self.respond(200, response)
        except (ValueError, KeyError, TypeError):
            self.respond(400, {"error": "Invalid JSON request"})

if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()

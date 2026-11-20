"""Tiny demo HTTP service.

GET /         -> {"app": "<APP_NAME>", "version": "<VERSION>", "pod": "<hostname>"}
GET /healthz  -> 200 "ok"

APP_NAME and VERSION come from environment variables (in Kubernetes: a
ConfigMap). They are read on every request rather than cached at import time,
so the response always reflects the process's current environment.
"""
import json
import os
import signal
import socket
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "8080"))


class Handler(BaseHTTPRequestHandler):
    def _send(self, status, body, content_type):
        payload = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        # Ignore any query string, e.g. "/?x=1"
        path = self.path.split("?", 1)[0]

        if path == "/":
            body = json.dumps(
                {
                    "app": os.environ.get("APP_NAME", "unknown"),
                    "version": os.environ.get("VERSION", "unknown"),
                    "pod": socket.gethostname(),
                    #this hostname helps identify which pod is catering the request when it is replicasets
                }
            )
            self._send(200, body, "application/json")
        elif path == "/healthz":
            self._send(200, "ok", "text/plain")
        else:
            self._send(404, json.dumps({"error": "not found"}), "application/json")

    def log_message(self, fmt, *args):
        # Default logger writes to stderr; send access logs to stdout instead
        # so `kubectl logs` shows them like any other container output.
        print("%s - %s" % (self.address_string(), fmt % args), flush=True)


def main():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)

    # As PID 1 in a container, Python has no default SIGTERM handling, so
    # `kubectl delete pod` / rolling updates would wait the full grace period
    # and then SIGKILL us. Handle SIGTERM and shut down cleanly instead.
    def stop(signum, frame):
        # shutdown() blocks until serve_forever() exits, so it must not run
        # in the same thread that is inside serve_forever() (the signal
        # handler runs in the main thread).
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    print("listening on :%d" % PORT, flush=True)
    server.serve_forever()
    server.server_close()
    print("shut down cleanly", flush=True)


if __name__ == "__main__":
    main()

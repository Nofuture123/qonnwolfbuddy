"""Offline native socket fixture; no host Herdr or internal helper replacement."""
import json
import socket
import sys
import threading
from pathlib import Path

path, log = map(Path, sys.argv[1:3])
server = socket.socket(socket.AF_UNIX)
server.bind(str(path))
server.listen()

def handle(connection):
    with connection:
        raw = connection.makefile("rb")
        request = json.loads(raw.readline())
        with log.open("a") as out:
            out.write(json.dumps(request) + "\n")
        method = request["method"]
        if method == "events.subscribe":
            result = {"type": "subscription_started"}
        elif method == "workspace.move":
            # Close fixtures register their owned Space last already; move must be a no-op.
            result = {"type": "workspace_list", "workspaces": []}
        else:
            connection.sendall((json.dumps({"id": request["id"], "error": {"code": "unsupported"}}) + "\n").encode())
            return
        connection.sendall((json.dumps({"id": request["id"], "result": result}) + "\n").encode())
        if method == "events.subscribe":
            # Keep the stream live; no synthetic event or repeated fallback wake.
            raw.read()

while True:
    connection, _ = server.accept()
    threading.Thread(target=handle, args=(connection,), daemon=True).start()

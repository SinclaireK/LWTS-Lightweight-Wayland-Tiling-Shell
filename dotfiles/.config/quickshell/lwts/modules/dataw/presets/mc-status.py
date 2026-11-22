#!/usr/bin/env python3
# Minecraft server status (Server List Ping, no external service): mc-status.py host [port] -> JSON for a data widget.
import json, socket, struct, sys, time

def varint(n):
    out = b""
    while True:
        b = n & 0x7F; n >>= 7
        out += bytes([b | (0x80 if n else 0)])
        if not n: return out

def read_varint(s):
    n = shift = 0
    while True:
        b = s.recv(1)
        if not b: raise IOError("closed")
        n |= (b[0] & 0x7F) << shift; shift += 7
        if not b[0] & 0x80: return n

def main():
    host = sys.argv[1]; port = int(sys.argv[2]) if len(sys.argv) > 2 else 25565
    t0 = time.time()
    s = socket.create_connection((host, port), timeout=4)
    ping = round((time.time() - t0) * 1000)
    h = host.encode()
    data = varint(0) + varint(767) + varint(len(h)) + h + struct.pack(">H", port) + varint(1)
    s.sendall(varint(len(data)) + data + b"\x01\x00")
    read_varint(s); read_varint(s); n = read_varint(s)
    raw = b""
    while len(raw) < n:
        c = s.recv(n - len(raw))
        if not c: break
        raw += c
    st = json.loads(raw.decode("utf-8", "replace"))
    p = st.get("players", {})
    names = [x.get("name", "") for x in p.get("sample", []) or []][:3]
    print(json.dumps({"value": f"{p.get('online', 0)}/{p.get('max', 0)} online", "sub": ", ".join(names) or f"{ping} ms", "on": p.get("online", 0) > 0}))

try: main()
except Exception: print(json.dumps({"value": "Offline", "sub": "", "on": False, "alert": True}))

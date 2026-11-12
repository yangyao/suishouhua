#!/usr/bin/env python3
"""RFC6455 raw-socket WS probe for the TV debug chain.

Modes:
  ping  : connect to ws://HOST/ws, send WS ping every 5s for 60s, report drops.
  stress: send 50 strokes (30 points each, split into 4 stroke_points frames,
          16ms between frames), count stroke_end acks via SyncTrace in logcat
          is done externally; here we just send and record send result.
"""
import socket, base64, os, struct, sys, time, json

HOST = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
PORT = 9723


def connect():
    s = socket.create_connection((HOST, PORT), timeout=5)
    key = base64.b64encode(os.urandom(16)).decode()
    req = (f"GET /ws HTTP/1.1\r\nHost: {HOST}:{PORT}\r\n"
           "Upgrade: websocket\r\nConnection: Upgrade\r\n"
           f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n")
    s.sendall(req.encode())
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = s.recv(4096)
        if not chunk:
            raise RuntimeError("handshake EOF")
        buf += chunk
    head, rest = buf.split(b"\r\n\r\n", 1)
    if b"101" not in head.split(b"\r\n")[0]:
        raise RuntimeError(f"handshake failed: {head[:80]}")
    return s, rest


def send_frame(s, opcode, payload=b"", mask=True):
    header = bytes([0x80 | opcode])
    n = len(payload)
    mbit = 0x80 if mask else 0
    if n < 126:
        header += bytes([mbit | n])
    elif n < 65536:
        header += bytes([mbit | 126]) + struct.pack(">H", n)
    else:
        header += bytes([mbit | 127]) + struct.pack(">Q", n)
    if mask:
        mkey = os.urandom(4)
        payload = mkey + bytes(b ^ mkey[i % 4] for i, b in enumerate(payload))
    s.sendall(header + payload)


class Reader:
    def __init__(self, s, initial=b""):
        self.s = s
        self.buf = initial

    def read_frame(self, timeout=2.0):
        self.s.settimeout(timeout)
        def need(n):
            while len(self.buf) < n:
                chunk = self.s.recv(65536)
                if not chunk:
                    raise EOFError("server EOF")
                self.buf += chunk
        need(2)
        b0, b1 = self.buf[0], self.buf[1]
        opcode = b0 & 0x0F
        ln = b1 & 0x7F
        off = 2
        if ln == 126:
            need(4); ln = struct.unpack(">H", self.buf[2:4])[0]; off = 4
        elif ln == 127:
            need(10); ln = struct.unpack(">Q", self.buf[2:10])[0]; off = 10
        need(off + ln)
        payload = self.buf[off:off + ln]
        self.buf = self.buf[off + ln:]
        return opcode, payload


def mode_ping():
    s, rest = connect()
    r = Reader(s, rest)
    print(f"connected, leftover={len(rest)}B")
    pings, pongs, drops = 0, 0, 0
    start = time.time()
    try:
        while time.time() - start < 60:
            send_frame(s, 0x9, b"hb"); pings += 1
            t0 = time.time()
            try:
                op, _ = r.read_frame(timeout=5.0)
                if op == 0xA:
                    pongs += 1
            except (EOFError, socket.timeout, OSError) as e:
                drops += 1
                print(f"DROP at t={time.time()-start:.1f}s: {type(e).__name__} {e}")
                s, rest = connect()
                r = Reader(s, rest)
                print("reconnected")
            time.sleep(5.0)
    finally:
        s.close()
    print(f"RESULT ping: pings={pings} pongs={pongs} drops={drops} over 60s")
    return drops


def mode_stress():
    s, rest = connect()
    r = Reader(s, rest)
    send_frame(s, 0x1, json.dumps({"type": "hello"}).encode())
    op, payload = r.read_frame(timeout=5)
    print("hello ->", payload.decode()[:80])
    if b"paired" not in payload:
        print("not paired, abort")
        return
    sent = 0
    t0 = time.time()
    try:
        for i in range(50):
            sid = f"probe-{i}"
            send_frame(s, 0x1, json.dumps(
                {"type": "stroke_start", "id": sid, "tool": "pen",
                 "color": "#2B2B2E", "width": 2}).encode())
            pts = [[0.05 + 0.01 * j + 0.001 * i, 0.2 + 0.005 * j] for j in range(30)]
            for k in range(4):
                chunk = pts[k * 7:(k + 1) * 7] if k < 3 else pts[21:]
                send_frame(s, 0x1, json.dumps(
                    {"type": "stroke_points", "id": sid, "points": chunk}).encode())
                time.sleep(0.016)
            send_frame(s, 0x1, json.dumps({"type": "stroke_end", "id": sid}).encode())
            sent += 1
    except (BrokenPipeError, OSError) as e:
        print(f"SEND FAIL at stroke {sent}: {type(e).__name__} {e}")
    dt = time.time() - t0
    s.close()
    print(f"RESULT stress: sent={sent}/50 strokes in {dt:.2f}s")


if __name__ == "__main__":
    mode = sys.argv[2] if len(sys.argv) > 2 else "ping"
    (mode_ping if mode == "ping" else mode_stress)()

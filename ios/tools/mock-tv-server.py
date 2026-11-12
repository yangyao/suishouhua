#!/usr/bin/env python3
"""本地 mock 电视端 WS 服务器（RFC6455 极简实现，无三方依赖）。

用法: python3 tools/mock-tv-server.py [port]   # 默认 9723
监听 ws://127.0.0.1:<port>/ws
- hello → 空闲时回 paired(canvasAspect 1.7777)；已有连接时回 rejected(in_use)（协议：无配对码）
- ping → pong
- stroke_start/stroke_points/stroke_end/undo/redo/clear/erase → 打印日志

macOS 上 Network.framework (NWListener) 在部分环境会报 POSIX 22，故用纯 socket 实现。
"""
import base64
import hashlib
import json
import os
import socket
import struct
import sys
import threading

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
active_conn = [None]  # 当前占用的连接（单设备独占）


def recv_exact(conn, n):
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("closed")
        buf += chunk
    return buf


def read_frame(conn):
    b1, b2 = recv_exact(conn, 2)
    opcode = b1 & 0x0F
    masked = b2 & 0x80
    length = b2 & 0x7F
    if length == 126:
        length = struct.unpack(">H", recv_exact(conn, 2))[0]
    elif length == 127:
        length = struct.unpack(">Q", recv_exact(conn, 8))[0]
    mask = recv_exact(conn, 4) if masked else None
    payload = recv_exact(conn, length) if length else b""
    if mask:
        payload = bytes(c ^ mask[i % 4] for i, c in enumerate(payload))
    return opcode, payload


def send_text(conn, text):
    data = text.encode("utf-8")
    header = bytes([0x81])
    n = len(data)
    if n < 126:
        header += bytes([n])
    elif n < 65536:
        header += bytes([126]) + struct.pack(">H", n)
    else:
        header += bytes([127]) + struct.pack(">Q", n)
    conn.sendall(header + data)


def handle_message(conn, text):
    print("◀ " + text, flush=True)
    try:
        obj = json.loads(text)
    except json.JSONDecodeError:
        return
    t = obj.get("type")
    if t == "hello":
        if active_conn[0] is not None and active_conn[0] is not conn:
            reply = json.dumps({"type": "rejected", "reason": "in_use"})
            send_text(conn, reply)
            print("▶ " + reply, flush=True)
            # 协议：拒绝后关闭连接。延迟关闭确保拒绝对先送达客户端。
            threading.Timer(0.5, conn.shutdown, args=(socket.SHUT_RDWR,)).start()
            return
        active_conn[0] = conn
        reply = json.dumps({"type": "paired", "canvasAspect": 1.7777})
        send_text(conn, reply)
        print("▶ " + reply, flush=True)
        # 重连恢复场景可手动打开 history：
        # history = json.dumps({"type": "history", "strokes": [
        #     {"id": "demo1", "tool": "pen", "color": "#3577F2", "width": 2,
        #      "points": [[0.1, 0.3], [0.5, 0.5], [0.9, 0.7]]}]})
        # send_text(conn, history)
    elif t == "ping":
        send_text(conn, json.dumps({"type": "pong"}))


def serve_conn(conn):
    try:
        # 握手
        request = b""
        while b"\r\n\r\n" not in request:
            request += conn.recv(4096)
        headers = {}
        for line in request.split(b"\r\n")[1:]:
            if b":" in line:
                k, v = line.split(b":", 1)
                headers[k.strip().lower().decode()] = v.strip().decode()
        key = headers.get("sec-websocket-key", "")
        accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
        conn.sendall(
            (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
            ).encode()
        )
        print("connection established", flush=True)
        buffer = ""
        while True:
            opcode, payload = read_frame(conn)
            if opcode == 0x8:  # close
                break
            elif opcode == 0x9:  # ping
                conn.sendall(bytes([0x8A, len(payload)]) + payload)
            elif opcode in (0x1, 0x0):
                buffer += payload.decode("utf-8", errors="replace")
                if opcode == 0x1:
                    handle_message(conn, buffer)
                    buffer = ""
    except (ConnectionError, OSError):
        print("connection closed", flush=True)
    finally:
        if active_conn[0] is conn:
            active_conn[0] = None
        conn.close()


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9723
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", port))
    server.listen(5)
    print(f"mock TV listening on ws://0.0.0.0:{port}/ws", flush=True)
    while True:
        conn, addr = server.accept()
        print(f"connection from {addr}", flush=True)
        threading.Thread(target=serve_conn, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    main()

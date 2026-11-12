#!/usr/bin/env python3
"""TCP relay: LAN IP:9723 -> 127.0.0.1:9723 (adb forward to emulator).

Binds only the LAN address so it does not clash with adb forward on localhost.
Transparently passes HTTP and WebSocket frames.
"""
import socket, threading, sys

LAN_IP = "192.168.2.200"
LAN_PORT = 9723
UPSTREAM = ("127.0.0.1", 9723)

def pump(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        try: dst.shutdown(socket.SHUT_WR)
        except OSError: pass
        try: dst.close()
        except OSError: pass

def handle(client):
    try:
        upstream = socket.create_connection(UPSTREAM, timeout=5)
    except OSError:
        client.close()
        return
    # 连接建立后必须清除超时：否则空闲 5s 就会被 recv timeout 掐断，
    # 表现为电视每 5 秒闪回配对页、传输中的笔画丢失。
    upstream.settimeout(None)
    client.settimeout(None)
    t = threading.Thread(target=pump, args=(client, upstream), daemon=True)
    t.start()
    pump(upstream, client)

def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((LAN_IP, LAN_PORT))
    srv.listen(16)
    print(f"relay listening on {LAN_IP}:{LAN_PORT} -> {UPSTREAM}", flush=True)
    while True:
        client, addr = srv.accept()
        threading.Thread(target=handle, args=(client,), daemon=True).start()

if __name__ == "__main__":
    main()

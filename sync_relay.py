#!/usr/bin/env python3
"""Experiment17 E17SYNC1 reference WebSocket relay.

Install:  pip install websockets
Run:      python sync_relay.py --host 0.0.0.0 --port 8765

This relay only forwards JSON packets to clients with the same room+key.
For internet use, put it behind TLS/reverse proxy and use wss:// in Sync.lua.
"""

import argparse
import asyncio
import json
import websockets

clients = set()
meta = {}

async def handler(ws):
    clients.add(ws)
    try:
        async for raw in ws:
            try:
                packet = json.loads(raw)
            except Exception:
                continue
            if packet.get("protocol") != "E17SYNC1":
                continue
            room = str(packet.get("room", ""))
            key = str(packet.get("key", ""))
            client = str(packet.get("client", ""))
            if not room or not client:
                continue
            meta[ws] = (room, key, client)
            dead = []
            for other in tuple(clients):
                if other is ws:
                    continue
                if meta.get(other, (None, None, None))[:2] != (room, key):
                    continue
                try:
                    await other.send(raw)
                except Exception:
                    dead.append(other)
            for other in dead:
                clients.discard(other)
                meta.pop(other, None)
    finally:
        clients.discard(ws)
        info = meta.pop(ws, None)
        if info:
            room, key, client = info
            bye = json.dumps({"protocol":"E17SYNC1","type":"bye","room":room,"key":key,"client":client})
            for other in tuple(clients):
                if meta.get(other, (None, None, None))[:2] == (room, key):
                    try:
                        await other.send(bye)
                    except Exception:
                        pass

async def main(host, port):
    async with websockets.serve(handler, host, port, max_size=2_000_000, ping_interval=20, ping_timeout=20):
        print(f"Experiment17 sync relay: ws://{host}:{port}")
        await asyncio.Future()

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    asyncio.run(main(args.host, args.port))

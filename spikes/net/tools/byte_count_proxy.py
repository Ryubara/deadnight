"""Counts the bytes a Godot WebSocket server and its clients exchange (what the network really carries).

    python tools/byte_count_proxy.py --listen 8912 --target 8910 --seconds 20

Point clients at the listen port (`--url=ws://127.0.0.1:8912`). Prints bytes per second, both directions.
"""

import argparse
import asyncio
import time

counts = {"client_to_server": 0, "server_to_client": 0}
REPORT_SECONDS = 5


async def pipe(reader, writer, key):
    try:
        while data := await reader.read(65536):
            counts[key] += len(data)
            writer.write(data)
            await writer.drain()
    except ConnectionError:
        pass
    finally:
        writer.close()


async def handle(client_reader, client_writer, target):
    server_reader, server_writer = await asyncio.open_connection("127.0.0.1", target)
    await asyncio.gather(
        pipe(client_reader, server_writer, "client_to_server"),
        pipe(server_reader, client_writer, "server_to_client"),
    )


async def main(listen, target, seconds):
    server = await asyncio.start_server(lambda r, w: handle(r, w, target), "127.0.0.1", listen)
    start = time.monotonic()
    last = dict(counts)
    async with server:
        while time.monotonic() - start < seconds:
            await asyncio.sleep(REPORT_SECONDS)
            now = dict(counts)
            up = (now["client_to_server"] - last["client_to_server"]) / REPORT_SECONDS
            down = (now["server_to_client"] - last["server_to_client"]) / REPORT_SECONDS
            print(
                f"t={time.monotonic() - start:5.1f}s  clients->server {up:8.0f} B/s  server->clients {down:8.0f} B/s",
                flush=True,
            )
            last = now


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen", type=int, default=8912)
    parser.add_argument("--target", type=int, default=8910)
    parser.add_argument("--seconds", type=float, default=20)
    args = parser.parse_args()
    asyncio.run(main(args.listen, args.target, args.seconds))

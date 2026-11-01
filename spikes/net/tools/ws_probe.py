"""Measures a net-spike server from outside Godot, with microsecond timestamps.

Joins as a player that never moves, pings 20 times a second and records when every snapshot arrives.
The Godot clients read the socket only on their 30 Hz tick, so their numbers are quantised to 33 ms;
this probe reads the socket as soon as bytes arrive, so its numbers are the network plus the server's
own tick (a ping waits on average half a tick for the server's next poll).

    uv run --with websockets python ws_probe.py wss://host --seconds 60
"""

import argparse
import asyncio
import statistics
import struct
import time

import websockets

PROTOCOL_VERSION = 1
HELLO, WELCOME, SNAPSHOT, PING, PONG = 1, 2, 4, 6, 7
STALL_MS = 100.0


def percentile(sorted_values: list[float], fraction: float) -> float:
    return sorted_values[min(int(fraction * len(sorted_values)), len(sorted_values) - 1)] if sorted_values else 0.0


def summarise(name: str, values: list[float]) -> str:
    ordered = sorted(values)
    return (
        f"{name}: n={len(ordered)} mean={statistics.fmean(ordered):.1f} sd={statistics.pstdev(ordered):.1f} "
        f"min={ordered[0]:.1f} p50={percentile(ordered, 0.5):.1f} p95={percentile(ordered, 0.95):.1f} "
        f"p99={percentile(ordered, 0.99):.1f} max={ordered[-1]:.1f} ms"
    )


async def run(url: str, seconds: float) -> None:
    connect_started = time.perf_counter()
    async with websockets.connect(url, max_size=None, compression=None) as ws:
        connected_ms = (time.perf_counter() - connect_started) * 1000
        await ws.send(bytes([HELLO, PROTOCOL_VERSION]))
        pings: dict[int, float] = {}
        rtts: list[float] = []
        gaps: list[float] = []
        sizes = 0
        last_snapshot = 0.0
        stop = time.perf_counter() + seconds

        async def pinger() -> None:
            ping_id = 0
            while time.perf_counter() < stop:
                ping_id += 1
                pings[ping_id] = time.perf_counter()
                await ws.send(struct.pack("<BI", PING, ping_id))
                await asyncio.sleep(0.05)

        task = asyncio.create_task(pinger())
        while time.perf_counter() < stop:
            try:
                data = await asyncio.wait_for(ws.recv(), timeout=2)
            except TimeoutError:
                gaps.append(2000.0)
                continue
            now = time.perf_counter()
            sizes += len(data)
            if data[0] == PONG:
                sent = pings.pop(struct.unpack_from("<I", data, 1)[0], None)
                if sent is not None:
                    rtts.append((now - sent) * 1000)
            elif data[0] == SNAPSHOT:
                if last_snapshot:
                    gaps.append((now - last_snapshot) * 1000)
                last_snapshot = now
        task.cancel()

    stalls = [gap for gap in gaps if gap >= STALL_MS]
    print(f"probe {url} for {seconds:.0f} s; websocket connect (TCP+TLS+upgrade) {connected_ms:.0f} ms")
    print(summarise("ping round trip", rtts))
    print(summarise("snapshot arrival gap", gaps))
    print(
        f"stalls (gap >= {STALL_MS:.0f} ms): {len(stalls)}, "
        f">=200 ms: {sum(g >= 200 for g in gaps)}, >=500 ms: {sum(g >= 500 for g in gaps)}, "
        f"longest {max(gaps):.0f} ms, frozen time {sum(g - 33.3 for g in stalls):.0f} ms; "
        f"down {sizes / seconds:.0f} B/s payload"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    parser.add_argument("--seconds", type=float, default=30)
    arguments = parser.parse_args()
    asyncio.run(run(arguments.url, arguments.seconds))

"""Runs one comparison scenario: a headless server, a link-conditioning TCP proxy, and N bot clients.

    uv run --with psutil python tools/run_scenario.py --mode own|mp --players 4 --zombies 24 \
        --latency-ms 50 --loss 0.02 --seconds 20 --godot <path-to-godot> --out <folder>

The proxy sits between every client and the server, so both stacks are measured identically at the TCP
level and neither needs a hook: it counts the bytes (WebSocket framing included, TCP/IP headers not),
delays every chunk by --latency-ms each way, and models TCP loss: with probability --loss per chunk
the chunk is "lost" and re-delivered after --rto-ms, and (this is head-of-line blocking) every later
chunk in that direction waits behind it.
"""

# ruff: noqa: ASYNC220, ASYNC230, SIM115, ISC004
# A throwaway harness: blocking spawn and open calls at start-up are fine.
import argparse
import asyncio
import random
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

import psutil

PROJECT = Path(__file__).resolve().parent.parent


class Proxy:
    def __init__(self, listen_port, target_port, latency, loss, rto, seed):
        self.listen_port, self.target_port = listen_port, target_port
        self.latency, self.loss, self.rto = latency, loss, rto
        self.rng = random.Random(seed)
        self.up = 0  # client -> server bytes
        self.down = 0  # server -> client bytes
        self.up_chunks = 0
        self.down_chunks = 0
        self.stalls = 0

    async def start(self):
        self.server = await asyncio.start_server(self._handle, "127.0.0.1", self.listen_port)

    async def _handle(self, c_reader, c_writer):
        try:
            s_reader, s_writer = await asyncio.open_connection("127.0.0.1", self.target_port)
        except OSError:
            c_writer.close()
            return
        await asyncio.gather(
            self._pump(c_reader, s_writer, True),
            self._pump(s_reader, c_writer, False),
            return_exceptions=True,
        )

    async def _pump(self, reader, writer, upward):
        loop = asyncio.get_running_loop()
        queue: asyncio.Queue = asyncio.Queue()
        last_due = 0.0

        async def deliver():
            while True:
                due, data = await queue.get()
                if data is None:
                    break
                delay = due - loop.time()
                if delay > 0:
                    await asyncio.sleep(delay)
                writer.write(data)
                try:
                    await writer.drain()
                except ConnectionError:
                    break
            writer.close()

        task = asyncio.create_task(deliver())
        try:
            while data := await reader.read(65536):
                if upward:
                    self.up += len(data)
                    self.up_chunks += 1
                else:
                    self.down += len(data)
                    self.down_chunks += 1
                due = loop.time() + self.latency
                if self.loss > 0 and self.rng.random() < self.loss:
                    due += self.rto
                    self.stalls += 1
                last_due = max(last_due, due)  # in-order delivery: later chunks wait behind
                queue.put_nowait((last_due, data))
        except ConnectionError:
            pass
        queue.put_nowait((0, None))
        await task


def cpu_seconds(proc: psutil.Process) -> float:
    total = 0.0
    for p in [proc, *proc.children(recursive=True)]:
        try:
            t = p.cpu_times()
            total += t.user + t.system
        except psutil.Error:
            pass
    return total


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["own", "mp", "nf"], required=True)
    ap.add_argument("--players", type=int, default=4)
    ap.add_argument("--zombies", type=int, default=24)
    ap.add_argument("--latency-ms", type=float, default=0)
    ap.add_argument("--loss", type=float, default=0)
    ap.add_argument("--rto-ms", type=float, default=300)
    ap.add_argument("--seconds", type=int, default=20)
    ap.add_argument("--port", type=int, default=8930)
    ap.add_argument("--godot", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--label", default="")
    ap.add_argument("--project", default=str(PROJECT), help="Godot project folder (netfox: ../net-compare-netfox)")
    ap.add_argument("--extra", default="", help="extra game arguments for server and clients, e.g. --pack")
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    label = a.label or f"{a.mode}"
    server_port, proxy_port = a.port, a.port + 1

    base = [a.godot, "--headless", "--path", a.project, "--"]
    mode = [f"--mode={a.mode}", *a.extra.split()]
    server_log = open(out / f"{label}-server.log", "w")
    server = subprocess.Popen(
        [*base, *mode, "--server", f"--port={server_port}", f"--zombies={a.zombies}", f"--run-seconds={a.seconds + 8}"],
        stdout=server_log,
        stderr=subprocess.STDOUT,
    )
    proxy = Proxy(proxy_port, server_port, a.latency_ms / 1000.0, a.loss, a.rto_ms / 1000.0, 7)
    await proxy.start()
    await asyncio.sleep(3)  # let the server come up
    clients = []
    for i in range(a.players):
        log = open(out / f"{label}-client{i + 1}.log", "w")
        clients.append(
            (
                subprocess.Popen(
                    [
                        *base,
                        *mode,
                        "--client",
                        f"--url=ws://127.0.0.1:{proxy_port}",
                        f"--bot-seed={(i + 1) * 7}",
                        f"--run-seconds={a.seconds}",
                        "--input-redundancy=1",
                    ],
                    stdout=log,
                    stderr=subprocess.STDOUT,
                ),
                log,
            )
        )
    sproc = psutil.Process(server.pid)
    await asyncio.sleep(4)  # connections and spawns settle
    cpu0, wall0 = cpu_seconds(sproc), time.time()
    up0, down0, uc0, dc0 = proxy.up, proxy.down, proxy.up_chunks, proxy.down_chunks
    deadline = time.time() + a.seconds + 6
    while time.time() < deadline and any(c.poll() is None for c, _ in clients):
        await asyncio.sleep(0.25)
        if time.time() - wall0 >= a.seconds - 6:  # stop the window before the clients leave
            break
    cpu1, wall1 = cpu_seconds(sproc), time.time()
    up1, down1, uc1, dc1 = proxy.up, proxy.down, proxy.up_chunks, proxy.down_chunks
    for c, log in clients:
        try:
            c.wait(timeout=15)
        except subprocess.TimeoutExpired:
            c.kill()
        log.close()
    server.terminate()
    try:
        server.wait(timeout=5)
    except subprocess.TimeoutExpired:
        server.kill()
    server_log.close()

    win = wall1 - wall0
    results = []
    for i in range(a.players):
        text = (out / f"{label}-client{i + 1}.log").read_text(errors="replace")
        m = re.search(r"RESULT .*", text)
        results.append(m.group(0) if m else "NO RESULT")
    errors = sum(
        (out / f).read_text(errors="replace").count("ERROR")
        for f in [f"{label}-server.log", *[f"{label}-client{i + 1}.log" for i in range(a.players)]]
    )

    num = r"([\d.]+)"

    def nums(pattern):
        return [float(m.group(1)) for r in results if (m := re.search(pattern, r))]

    n = a.players
    summary = [
        f"scenario={label} mode={a.mode} players={n} zombies={a.zombies} latency_one_way={a.latency_ms}ms "
        f"loss={a.loss} rto={a.rto_ms}ms window={win:.1f}s",
        f"down_per_client={(down1 - down0) / win / n:.0f} B/s  up_per_client={(up1 - up0) / win / n:.0f} B/s  "
        f"(payload+WebSocket framing; add ~40 B per TCP packet: down_pkts/s/client="
        f"{(dc1 - dc0) / win / n:.1f} up_pkts/s/client={(uc1 - uc0) / win / n:.1f})",
        f"server_cpu={(cpu1 - cpu0) / win * 100:.1f}% of one core (whole process tree, measured window)",
        f"rtt_ms mean={statistics.mean(nums('rtt=' + num + ' ms') or [0]):.0f}  "
        f"gap_p50={statistics.mean(nums('gap_p50=' + num) or [0]):.0f} "
        f"p95={statistics.mean(nums('p95=' + num) or [0]):.0f} "
        f"p99={statistics.mean(nums('p99=' + num) or [0]):.0f} "
        f"max={max(nums('max=' + num + ' ms n=') or [0]):.0f} ms  (arrival gap between updates of own state; 33 ms ideal)",
        "corrections>1cm: "
        + " ".join(
            re.search(r"corrections>1cm=(\d+/\d+) mean=([\d.]+) cm max=([\d.]+)", r).group(0).split("=", 1)[1]
            if re.search(r"corrections>1cm=", r)
            else "?"
            for r in results
        ),
        f"proxy_stalls={proxy.stalls} ERROR_lines_in_logs={errors}",
    ]
    text = "\n".join(summary)
    print(text)
    (out / f"{label}-summary.txt").write_text(text + "\n\n" + "\n".join(results) + "\n")


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))

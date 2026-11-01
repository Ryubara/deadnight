# Net spike

A throwaway Godot project that proves the multiplayer shape Deadnight will build on: **our own network-first
foundation**, not Godot's high-level multiplayer (no `MultiplayerAPI` RPCs, `MultiplayerSpawner` or
`MultiplayerSynchronizer`). A headless server on a fixed tick, clients that predict and interpolate, our own binary
protocol, over a transport interface with two implementations: raw WebSocket (what a Discord Activity can reach) and an
in-process loopback (single-player runs the same server inside the client). The architecture, numbers and the
reasoning are in [`docs/research/multiplayer.md`](../../docs/research/multiplayer.md); this page is how to run it.

Two or more clients join; each moves a capsule with WASD or the arrow keys; everyone sees everyone. A white ring marks
where the server last said your own capsule was: the gap between it and the capsule is what prediction hides.

## Layers

| Layer | Files (`scripts/`) |
| --- | --- |
| Transport | `net/client_transport.gd`, `net/server_transport.gd` (interfaces), `net/ws_client_transport.gd`, `net/ws_server_transport.gd` (WebSocketPeer, TCPServer), `net/loopback_*_transport.gd` (in-process), `net/conditioned_transport.gd` (artificial delay, jitter, loss) |
| Protocol | `net/protocol.gd` (all message layouts, versioned) |
| Simulation | `sim/game_sim.gd` (no nodes, integer centimetres, shared by server and client prediction), `sim/input_sampler.gd` (keyboard or seeded bot) |
| Server | `game_server.gd`, `net/server_peer.gd`: fixed 30 Hz tick, per-client input queue, delta snapshots against the last acknowledged one |
| Client | `game_client.gd` (prediction, reconciliation, interpolation), `client_stats.gd` (measurements), `world_view.gd` (drawing) |
| Entry | `main.gd`: `--server`, a client, or `--local` single-player |

## Run it locally

Use the pinned Godot (`gds tool path godot`). From this folder:

```text
godot --headless --path . --import                         # once
godot --headless --path . -- --server                      # the server, port 8910 (or $PORT)
godot --path . --resolution 960x540                        # a client over WebSocket: WASD / arrows
godot --path . --resolution 960x540 -- --bot-seed=7        # a client that walks by itself (seeded)
godot --path . -- --local                                  # single-player: server in-process, loopback
godot --headless --path . -- --client --bot-seed=7 --run-seconds=20    # a headless bot, prints a RESULT line
```

Options after `--`:

| Option | Meaning |
| --- | --- |
| `--server` / `--client` | force the role (headless defaults to server) |
| `--local` | single-player: run the server in this process over a loopback transport |
| `--port=N`, `--url=ws://host:port` | where to listen / connect (default 8910; on the server `$PORT` is read too) |
| `--bot-seed=N` | the client walks by itself, seeded |
| `--latency=ms`, `--jitter=ms`, `--loss=0..1` | make the client's link worse, both directions (any transport) |
| `--input-redundancy=N` | inputs per packet (default 1, or 3 when `--loss` is set) |
| `--interp-ms=N` | remote-player interpolation delay (default 100) |
| `--snapshot-every=N`, `--full-snapshots` | server: snapshot every N ticks; never send deltas |
| `--run-seconds=N` | quit after N seconds (scripted runs) |

On the web the page address supplies the same options: `index.html?url=wss://host&bot-seed=3`.

Port 9080 is not used: the Godot editor's MCP bridge listens there on the maintainer machine, and Windows lets a second
listener bind it silently.

## Web client

Needs the pinned export templates (`gds workspace init --no-clone --fetch godot-templates`). The preset `Web` is
**single-threaded** (`variant/thread_support=false`), so the page needs no cross-origin isolation headers and works in
an iframe such as a Discord Activity.

```text
godot --headless --path . --export-release Web       # writes ../../build/net-web/ (git-ignored)
python -m http.server 8920 --directory ../../build/net-web
# open http://127.0.0.1:8920/index.html?bot-seed=3   (add &url=wss://... for a remote server)
```

Without `url`, the page connects to `ws://<page host>:8910`.

## Server image (Railway)

```text
docker build -t deadnight-net .
docker run --rm -e PORT=8910 -p 8910:8910 deadnight-net
```

The image downloads the Linux Godot binary (version and SHA-512 from the kit's `tools.toml`), imports the project at
build time, and runs `godot --headless --path /app -- --server` as a non-root user. It listens on `$PORT` over plain
`ws://`; Railway's edge terminates TLS, so clients use `wss://<service>.up.railway.app`. Not deployed: that is the
maintainer's decision.

## Measuring

Clients print a line every 2 s and a `RESULT` line at the end (payload bytes each way, round trip in ticks, how far
snapshots corrected the prediction); the server prints its own totals every 5 s. For bytes on the wire including
WebSocket framing, put `tools/byte_count_proxy.py` between them:

```text
python tools/byte_count_proxy.py --listen 8912 --target 8910 --seconds 16
godot --headless --path . -- --client --url=ws://127.0.0.1:8912 --bot-seed=7 --run-seconds=14
```

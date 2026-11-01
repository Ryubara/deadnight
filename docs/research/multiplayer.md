# Multiplayer: the network-first architecture

**Status:** decided ([Networking](../design/networking.md)) and proven by a spike (`spikes/net/`, issue #6). The spike
is throwaway; the first real step is in the game: the night runs on a headless server over WebSocket and two or more
players can join it ([Testing multiplayer](testing-multiplayer.md), issue #302). [The real game over
WebSocket](#the-real-game-over-websocket) says what that is and how it differs from the spike; the rest of this page is
the spike's design and measurements, which the game follows where it does not say otherwise.

See also [Platform backend](platform-backend.md) (where the server runs and how a client joins a match) and
[Rules engine](rules-engine.md) (the game rules as a server-first `RefCounted`: its actions, events and snapshots are
what this page's `GameSim` and protocol would carry).

Deadnight is a web game (a Discord Activity) with its server on Railway, and single-player must be the same game. So
the network is not a layer added to a finished game: the game is a **server simulation** and a **client** that talks
to it, and single-player is that same server running inside the client's process. The spike builds that shape end to
end and measures it.

## The real game over WebSocket

What the game has now (`game/net/`, `game/gameplay/night/`), against what the spike had.

| | The game (issue #302) | Still the spike's design |
| --- | --- | --- |
| Transport | `WebSocketLink` (client) and `WsListener` (server) from the spike's `WebSocketPeer`/`TCPServer` code; `GameLink` is the interface `LoopbackLink` (single-player) and `WebSocketLink` share. Port 8910 | `ConditionedTransport` (delay, jitter, loss) is not ported |
| Server | `NightHost`: `godot --headless --path game -- --server [--port N]`, one `NightServer`, up to 4 players, the lowest free id is the seat, a new night is built when the last player leaves | `GameServer`'s per-client baselines and acks |
| Tick | the night's own **60 Hz** step; a `TICK` to each client every 2nd step (30 a second) | the spike's 30 Hz tick |
| Protocol | `NetWire`, version 1 (the layout is in its header); a command is a fixed 47 bytes; a `TICK` is a packed array of the events since the last one with the frame last; `LookWire` types 8 and 9 for looks | the version only in the handshake; refusal of another version |
| Snapshots | the `NightServer` frame, sent as a **difference against the frame that client had before** (`FrameDelta`): TCP never reorders or loses, so the previous frame is the baseline and no ack is needed. Compressed with Zstandard above 256 bytes | the spike's centimetre deltas against an acked baseline (they were for a protocol over an unreliable link) |
| Events | every client hears every event (shots, hits, rules); a late joiner gets the rules' snapshot in `WELCOME` (`HudState.load_snapshot`) and the doors, boards and circuits from the frames (`WorldMirror`) | |
| The local player | **predicted**: the client moves its own body at once and records where each numbered command left it; the frame's `ack` says which command the server used, and `Reconciler` moves the body a share (25 %) of the way to the server's answer per frame, snapping over 2.5 m | the spike replays the unacknowledged inputs on the server's position; the game does not replay yet |
| Everyone else | `RemoteAvatars`: a character in the player's look and seat armband, drawn **100 ms behind** the newest frame between two frames, walking or running by its speed | the same delay, kept |
| Commands | a pressed edge is kept when two commands arrive together, a command not renewed for `NightTuning.command_ticks` (30) steps stops the player, the player is the connection's (#163) | |

Not in the game yet: reconnect (#53), lag compensation for shots (#54), rate limits and a version policy (#55), interest
management and a tighter packing of zombies (#57), server bodies without models (#153), the Discord proxy and Railway
(#52).

The first numbers from the real thing, loopback on one loaded machine: 222 bytes a `TICK` with two players and four
zombies (6.6 KB/s down), a command 47 bytes (2.8 KB/s up), a round trip of 2 to 18 ms. They are in
[Testing multiplayer](testing-multiplayer.md#numbers-from-a-local-run) with how to repeat them.

## The decision

- Own protocol over **WebSocket** (Godot's raw `WebSocketPeer`, and `TCPServer` + `accept_stream` on the server).
  Discord's proxy reaches our server through HTTP and WebSocket only; no WebRTC, no UDP.
- **Not** Godot's high-level multiplayer (no RPCs, `MultiplayerSpawner`, `MultiplayerSynchronizer`); reasons below.
- Server-authoritative simulation on a **fixed 30 Hz tick**, no nodes, no engine time.
- Clients send **input commands with sequence numbers**; the server answers with **snapshots**, as a delta against the
  last snapshot that client acknowledged.
- Client-side **prediction and reconciliation** for the local player, **interpolation** (100 ms behind) for the rest.
- Transport behind an interface: `WebSocket` for multiplayer, `Loopback` for single-player, plus a **conditioner**
  (delay, jitter, loss) for tests.

## Layers

```text
  client                                                        server (headless, Railway)
  +--------------------+                                        +--------------------+
  | WorldView (draw)   |                                        |  GameServer (tick) |
  | GameClient         |  predict / reconcile / interpolate     |  ServerPeer x N    |
  |   InputSampler     |                                        |  GameSim (rules)   |
  | GameSim.integrate  |  <- shared movement rule               |  GameSim           |
  +---------+----------+                                        +---------+----------+
            | Protocol (bytes)                                            | Protocol (bytes)
  +---------+----------+        WebSocket (wss:// via the edge)  +---------+----------+
  | ClientTransport    | <-------------------------------------> | ServerTransport    |
  |  WebSocket | Loopback| (single-player: Loopback, same process)  |  WebSocket | Loopback
  |  + Conditioned     |                                          +--------------------+
  +--------------------+
```

| Layer | Owns | Does not know about |
| --- | --- | --- |
| Transport | moving whole packets (`send`, `poll`, `packet_received`) | what is in a packet |
| Protocol | the byte layout of every message, its version | sockets, game rules |
| Simulation (`GameSim`) | the rules: movement, bounds, collisions | time, nodes, networking |
| Replication (`GameServer`, `ServerPeer`) | the tick, input queues, snapshots, baselines | sockets, drawing |
| Prediction (`GameClient`) | pending inputs, reconciliation, the interpolation buffer | sockets, drawing |

Everything above the transport is plain `RefCounted`/`Node` code with typed GDScript. The server never touches a scene:
it runs headless, and the same class runs inside a client for single-player.

## Transport

```text
ClientTransport:  connect_to(url)  poll()  send(bytes)  close()  is_open()     signals: connected, disconnected, packet_received(bytes)
ServerTransport:  listen(port)  poll()  send(peer_id, bytes)  disconnect_peer(peer_id)  close()     signals: peer_connected, peer_disconnected, packet_received(peer_id, bytes)
```

- `WebSocketClientTransport` / `WebSocketServerTransport`: Godot's `WebSocketPeer`; the server accepts with
  `TCPServer`, polls every peer every tick, and gives a peer an id when its handshake completes. Binary frames only.
- `LoopbackServerTransport` / `LoopbackClientTransport`: arrays in one process. A packet sent during tick _t_ is read in
  tick _t_+1, which is what a zero-latency network would do, so single-player has the same ordering and the same code
  path as online (measured round trip: 2 ticks, 67 ms, with no added latency).
- `ConditionedTransport` wraps either client transport: fixed one-way delay, random jitter, random loss, both
  directions, seeded RNG and the owner's own tick clock (no real time, so runs repeat). Jitter may reorder packets.
- TCP never loses or reorders: over a real WebSocket, "loss" arrives as a stall and a burst. The conditioner's loss and
  reorder model what a future unreliable transport (or a very bad link's stalls) would do, so the protocol is built to
  survive them: inputs are resent redundantly, snapshots carry their tick and stale ones are ignored.

## Protocol

Version 1. One message is one WebSocket frame: a type byte then fixed little-endian fields. The version travels only in
the handshake (`HELLO`/`WELCOME`); a server refuses a client of another version. Defined in `scripts/net/protocol.gd`.

| Type | Dir | Layout | Bytes |
| --- | --- | --- | --- |
| `HELLO` 1 | C→S | `u8 version` | 2 |
| `WELCOME` 2 | S→C | `u8 version, u8 player_id, u8 tick_rate, u32 server_tick` | 8 |
| `INPUT` 3 | C→S | `u32 ack_tick, u32 first_seq, u8 count, count × (i8 x, i8 y)` | 10 + 2 × count |
| `SNAPSHOT` 4 full | S→C | `u32 tick, u32 ack_seq, u32 0, u8 count, count × (u8 id, i16 x_cm, i16 y_cm)` | 14 + 5 × players |
| `SNAPSHOT` 4 delta | S→C | `u32 tick, u32 ack_seq, u32 baseline_tick, u8 count, count × (u8 id, i8 dx_cm, i8 dy_cm)` | 14 + 3 × moved |
| `EVENT` 5 | S→C | `u8 kind (1 joined, 2 left), u8 player_id` | 3 |
| `PING` 6 / `PONG` 7 | C→S / S→C | `u32 client_tick` / `u32 client_tick, u32 server_tick` | 5 / 9 |

- Positions are whole **centimetres** (`i16` covers ±327 m; the arena is ±11 m), movement input is a direction
  quantised to `i8` per axis (`-127..127`). Nothing floating-point crosses the wire.
- WebSocket adds 2 bytes per server frame and 6 per client frame (masked); these are **not** in the table or in the
  payload numbers below.
- Every minimum length is checked before reading; a malformed packet is dropped (see the lesson on the one-byte-short
  `WELCOME` guard).
- `EVENT` carries what a snapshot cannot say: a player left. Presence otherwise comes from snapshots.

## Simulation and tick

`GameSim` holds `players: id → Vector2i (cm)` and one rule, `integrate(pos, dir)`: a quantised direction becomes a fixed
20 cm step (6 m/s at 30 Hz), clamped to the arena. A direction longer than the unit circle is clamped server-side, so a
client cannot move faster by lying. Time is **per input, not per frame**: a client moves one step for each input the
server applies, and the server applies each input exactly once, in order. That is why replaying inputs on the client
reproduces the server's result exactly, and why a stalled client stands still instead of teleporting.

The server alone resolves player-against-player collisions (a mover is pushed back out to 80 cm). The client does not
know where others are _now_, so its prediction is sometimes wrong, which is what reconciliation is for.

The tick is `physics_ticks_per_second = 30` (`_physics_process`), 33 ms. Per tick the server: polls the transport,
applies every queued input (at most 6 per client), then sends each client a snapshot (`--snapshot-every=N` sends every
Nth tick).

## Replication: snapshots and deltas

- Each tick, per client, the server sends the positions of all players. The **baseline** is the newest snapshot tick that
  client reported in its `INPUT.ack_tick`, if the server still has that state (it keeps what it sent each client, up to
  64 ticks, dropping what is older than the ack).
- A **delta** lists only players that moved since the baseline, as `i8` centimetre deltas. If a delta cannot express the
  change (a new player, or a move over 127 cm since the baseline), or there is no baseline, the server sends a **full**
  snapshot (`baseline_tick = 0`). A player leaving clears every baseline, so the next snapshot is full.
- The client keeps the last 64 snapshots by tick to rebuild a delta's state; a delta whose baseline it lacks is
  ignored (the next full one repairs it). Players absent from a _full_ snapshot are removed.
- `SNAPSHOT.ack_seq` tells a client the last of its inputs the server applied: the key to reconciliation.

## Prediction and reconciliation (the local player)

Each client tick the client samples input, gives it the next sequence number, **applies it locally at once**
(`integrate`), and sends the last `input_redundancy` inputs (default 1; 3 when loss is simulated). It keeps the inputs
the server has not acknowledged. When a snapshot arrives it takes the server's position for itself, drops inputs up to
`ack_seq`, **replays** the remaining ones on top, and that becomes the predicted position. The distance between the old
and the new predicted position is the **correction**. The capsule is drawn at the predicted position, smoothed
(25/s) to hide the 30 Hz steps; a white ring marks the last authoritative position.

## Interpolation (everyone else)

Remote players are drawn **100 ms (3 ticks) in the past** (kept after the Railway measurements: see
[Measured on Railway](#measured-on-railway)), interpolated between the two snapshots around that moment.
The client's render clock runs at the tick rate and is eased toward `latest_snapshot_tick − 3` on every snapshot
(snapping if it is over 6 ticks off). A buffer of 100 ms covers one lost snapshot at 30 Hz; the price is that others
are always 100 ms plus half the round trip old. Unchanged players have no delta entry; the client carries their value
forward so their buffers keep ticking.

## Single-player

`--local` builds a `LoopbackServerTransport`, starts a `GameServer` on it **in the client's process**, and hands the
client a `LoopbackClientTransport`. Nothing else differs: the client sends hello, input and pings, and receives
welcome and snapshots, like online. The server node is added before the client, so it ticks first each frame. No code
path says "offline". (Measured: the same prediction and snapshot code runs; with no latency every correction is 0.)

## What we deliberately do not use from Godot's multiplayer, and why

`SceneMultiplayer` with `MultiplayerSpawner`, `MultiplayerSynchronizer` and RPCs works over WebSocket and was the first
version of this spike. We measured it, then dropped it:

| Reason | Detail |
| --- | --- |
| **Traffic grows with the square of players** | A client-owned synchronizer is relayed by the server to every other client. Same game, per client, payload+framing as seen on the wire: upstream 1.8 KB/s with 2 players, 3.7 with 4, 6.1 with 8; downstream 1.9, 4.5, 7.8. The own protocol: up 0.37 KB/s at every size, down 0.6 (2 players), 1.0 (8, delta). |
| **No tick, no acknowledgement** | A synchronizer sends on its own interval (default per frame); there is no tick number, no ack, no baseline, so no deltas, no input sequence numbers, no reconciliation. |
| **Prediction and interpolation are ours to write anyway** | The engine provides neither; the high-level API gives a way to get values over, not a networking model. |
| **The simulation lives in nodes** | `MultiplayerSynchronizer` replicates node properties, so the game state is the scene tree. We want a node-free simulation that a headless server, a test and a single-player loopback can all run. |
| **Paths and spawns must match between peers** | RPCs and sync are routed by node path; a mismatch fails at runtime. A message protocol has one place that defines it. |
| **Client and server are one program shape** | A loopback/offline mode needs a fake `MultiplayerPeer`; ours is a transport swap. |

We keep Godot for what it is good at here: `WebSocketPeer`, `TCPServer`, `StreamPeerBuffer`, the fixed physics tick, the
headless server and the single-threaded web export.

## Measured

Headless bot clients (seeded random walks) on one Windows machine (loaded by other jobs, so round trips are noisy),
real WebSocket on localhost, 18 s each. Bytes are **payload** (what the game sends), per client; add the WebSocket
frame header (2 bytes per server message, 6 per client message, about 60 B/s down and 180 B/s up at 30 Hz).

| Scenario | Up | Down | Round trip | Notes |
| --- | --- | --- | --- | --- |
| 2 players | 366 B/s | 600 B/s | 37 ms | 30 inputs/s of 12 B; 30 snapshots/s of ~19 B |
| 8 players, delta snapshots | 366 B/s | 1020 B/s | 33–44 ms | server out 8.0 KB/s total, snapshot 33 B; players bump into each other: corrections > 1 cm in 0–42 of ~534 per player, max 20–38 cm |
| 8 players, full snapshots only | 365 B/s | 1615 B/s | 33–39 ms | server out 13.1 KB/s total, snapshot 54 B: deltas save 37 % with everyone moving |
| 4 players, +100 ms each way, 20 ms jitter, 5 % loss, inputs sent 3× | 478 B/s | 950 B/s | 300 ms | corrections > 1 cm: 0–1 of ~495 |
| same, inputs sent 1× | 361 B/s | 950 B/s | 300 ms | corrections > 1 cm: 23–25 of ~495, mean 0.8–1.0 cm, max 32–61 cm |

- A snapshot every tick costs one client about 1 KB/s at 8 players: bandwidth is not the constraint; 4 players is the
  design target and costs about 0.8 KB/s down.
- **Round trip** is measured in whole ticks (33 ms) from `PING`/`PONG`, so it carries ±33 ms of rounding, and on this
  loaded machine a localhost round trip costs 1 to 2 ticks. The artificial 100 ms each way shows up as 300 ms: 200 ms
  of link, jitter, plus the tick quantisation on both ends. Real Railway latency is in the next section.
- **Corrections** are zero when nothing disagrees (alone, or no collisions). They appear when the server pushes a
  capsule out of another (up to ~40 cm for one snapshot) or, with simulated loss and no redundancy, when a lost input is
  never applied (up to 61 cm). Three-fold input redundancy removes nearly all loss corrections for 117 B/s more.
- The first version (Godot's high-level multiplayer) measured: 2 players 3.5 KB/s up and 3.8 down in total; 4 players
  15.0 / 18.0; 8 players 49 / 62 (4-second windows through the byte-counting proxy). Same bots, same game.

## Measured on Railway

Issue #52, Railway half. The spike's server image (`spikes/net/Dockerfile`, unchanged apart from extra logging) ran on
Railway in a throwaway project, **region `us-west2`** (the service's `multiRegionConfig`; the default, one replica).
The measuring machine is in Houston, Texas and enters Railway's network at the `iah1` edge (the `x-railway-edge`
response header); a plain TCP connect to the edge takes about 20 ms, so the path is Houston, edge, California and
back. All numbers are one machine on a home connection, 40 to 60 s per run, on the same loaded Windows box as the
local baseline (a native Windows server on `127.0.0.1`); repeat them before trusting a decimal. The Discord Activity
proxy half is **not measured** (it needs a Discord application, a maintainer decision) and stays open in #52.

Three kinds of client, because they answer different questions:

- **`tools/ws_probe.py`** joins as a silent player and reads the socket the moment bytes arrive: round trip and
  snapshot gaps at microsecond resolution. This is the network plus the server's own tick.
- **Headless and desktop Godot bots** are what the game does: they read the socket on their 30 Hz tick, so their
  numbers carry up to one tick of rounding each way.
- **The web build in Chrome** (served from `127.0.0.1`, pointed at the `wss://` URL; headless Chrome with software
  WebGL, driven by Playwright because the browser extension was not connected).

| Client (60 s, 1 player) | Server | Round trip mean / p50 / p95 / p99 / max (ms) | Snapshot gap p99 / max (ms) | Gaps over 100 ms |
| --- | --- | --- | --- | --- |
| probe | local | 19 / 17 / 35 / 44 / 67 | 49 / 87 | 0 |
| probe | **Railway** | **77 / 78 / 90 / 96 / 106** (min 54) | **37 / 69** | **0** |
| Godot headless bot | local | 36 / 34 / 60 / 98 / 189 | 63 / 189 | 1 |
| Godot headless bot | **Railway** | **85 / 96 / 103 / 131 / 135** | 68 / 148 | 2 |
| Godot desktop (windowed) | local | 37 / 33 / 67 / 78 / 215 | 67 / 216 | 1 |
| Godot desktop (windowed) | **Railway** | **98 / 100 / 100 / 112 / 235** | 67 / 235 | 4 (2 over 200) |
| Web, Chrome | local | 41 / 33 / 75 / 98 / 100 | 99 / 174 | 19 |
| Web, Chrome | **Railway** | **96 / 99 / 112 / 130 / 136** | 73 / 212 | 1 |

How to read it:

- **Round trip.** The probe's Railway mean is 77 ms against 19 ms locally. The local 17 ms is the server's tick wait (a
  ping waits on average half a 33 ms tick for the next poll), so the **network round trip is about 60 ms** (minimum
  54 ms), Houston to `us-west2`. A game client sees **85 to 100 ms**: the 60 ms, plus the server's tick wait, plus the
  client's own tick rounding. Plan on **about 100 ms** round trip for a player on the same continent but a different
  region, and measure again from a player near the region (the region is a deployment setting).
- **Jitter** is small: the probe's round-trip standard deviation is 9 ms and the snapshot arrival gap's is 3 ms
  (33.3 ms mean, 37 ms at p99). Over the two probe runs (100 s, 3000 snapshots) the longest gap was 73 ms.
- **Stalls (TCP head-of-line blocking): none seen on the network.** The probe, which reads the socket without waiting
  for a frame, saw **no snapshot gap of 100 ms or more** in 100 s on Railway (nor locally). The gaps the Godot clients
  report come from the client's own frames, not the link: the _local_ web run shows 19 of them and the local desktop
  run one of 215 ms, on a loopback with nothing to stall. On Railway the Godot runs show 0 to 4 per minute, up to
  235 ms, no worse than locally, and when a client frame is late the packets wait in the socket and are read together,
  so nothing is lost. A real stall needs packet loss, which this home link did not show; the earlier simulated test
  (100 ms each way, 5 % loss) remains the stress case, and a Discord proxy hop adds a second TCP connection to it.
  One outlier: a ping in the probe run beside four bots took 422 ms while snapshots on the same socket kept arriving
  (max gap 73 ms), so it is most likely the probe's own scheduling; it is mentioned only because it was seen.
- **Bandwidth** is as predicted (payload): one client 380 B/s up and 540 B/s down; four clients 390 B/s up and 795 B/s
  down each. The server, with five players, sends 4.4 KB/s and receives 1.6 KB/s. A 4-player hour is about 15 MB out
  of the server.
- **Server tick on Railway** (202 five-second windows, about 17 minutes, 0 to 5 players): the time between ticks
  averaged 33.3 to 33.4 ms in every window; the longest was 57.6 ms, once (one tick of about 30 000 started over 50 ms
  late; no tick ran in a catch-up burst). Work per tick averaged 0.07 to 0.3 ms with one player and 0.5 to 0.6 ms with
  five (the worst single tick was 14.5 ms, a one-off); process CPU 1 to 1.8 % of one core with one player and 2 to
  2.6 % with five; memory 25 to 26 MiB. The tick is nowhere near its 33 ms budget, so Railway's CPU is not what limits
  4 players.
- Connecting costs more than a round trip: the WebSocket upgrade over TLS took 370 to 490 ms from Houston. Show a
  connecting state; do not block on it.

### The interpolation delay and the snapshot rate

Both stay at the spike's values: **100 ms (3 ticks) and a snapshot every tick (30 Hz)**. The client now counts how
often the render clock runs ahead of a remote player's newest snapshot (the buffer is dry and the player freezes).
Two headless bots, one measuring, 45 s each:

| Interpolation delay | Starved draws, Railway | Starved draws, local |
| --- | --- | --- |
| 33 ms (1 tick) | 841 / 6402 (13 %) | 751 / 6450 (12 %) |
| 67 ms (2 ticks) | 1 / 6352 | 6 / 6274 |
| **100 ms (3 ticks)** | **0 / 6408** | **0 / 6437** |

One tick is clearly too little, two nearly enough (the worst snapshot gap the probe saw was 73 ms, just over two
ticks), three has margin for the Godot client's own frame hiccups. **67 ms is a reasonable setting if the feel of
other players turns out to matter more than a rare freeze**; it is `--interp-ms=67`, and the next thing to test with
real players. A lower snapshot rate would force a longer delay (15 Hz needs at least two snapshot periods, 133 ms) to
save 270 B/s per client that nobody is short of, so 30 Hz stays.

### Hosting facts (Railway)

- **Inbound UDP is not offered.** Railway's documentation describes HTTP/HTTPS, WebSockets over HTTP/1.1
  ([connections "can stay open indefinitely, even while idle"](https://docs.railway.com/networking/public-networking/specs-and-limits))
  and a [TCP Proxy](https://docs.railway.com/networking/tcp-proxy) for raw TCP services such as databases; the pages
  read do not mention UDP at all. A Railway moderator says it outright in the community forum (28 Mar 2026): "To my
  knowledge, Railway has never supported UDP", "Railway only has TCP proxies", and that UDP is planned with no date
  ([thread](https://station.railway.com/questions/udp-not-working-anymore-24a1898e)). The forum is not documentation:
  if UDP or WebRTC data channels would decide something, ask Railway before relying on this. For #38, assume **TCP
  only** (HTTP, WebSocket, raw TCP) for a game server on Railway; that is also all a Discord Activity can reach.
  Private networking between Railway services is a separate matter and was not tested.
- WebSockets work through the edge with no configuration beyond the `$PORT` the image already reads; the public URL
  is `https://<service>-production-xxxx.up.railway.app`, so clients use `wss://`.
- Build and deploy from the spike folder took about a minute (`railway up` builds the Dockerfile remotely).

## What the web build needs

- Single-threaded export (`variant/thread_support=false`): no cross-origin isolation headers, works in an iframe. The
  preset is `spikes/net/export_presets.cfg`; export templates must be installed (`gds workspace init --fetch
  godot-templates`, about 1 GB).
- The WebSocket client is the same class on desktop and web. A web build **cannot** listen: the server is always a
  desktop/headless process.
- The server address comes from the page: `index.html?url=wss://<service>.up.railway.app`, read with
  `JavaScriptBridge.eval("window.location.search")`. Without it the page uses `ws://<page host>:8910`. An `https` page must
  use `wss://`.
- The release `.wasm` is about 39 MB uncompressed: serve it compressed (Railway static hosting, or the Discord
  Activity's own asset hosting).
- Verified in Chrome (Playwright, software WebGL) against the local server and against Railway over `wss://`: the web
  client renders, connects, and moves. It also publishes its last `RESULT` line as `window.netResult`.

## Local setup

`spikes/net/README.md` has every command. Port 9080 is **not** used: on the maintainer's machine the Godot editor MCP
bridge listens there, and Windows let the game server bind the same port silently; clients then reached the wrong
listener. Check a port with `netstat -ano | grep :<port>`.

## Server image

`spikes/net/Dockerfile`: Linux Godot 4.7.2 (SHA-512 from `tools.toml`), project imported at build time, runs
`godot --headless --path /app -- --server` as a non-root user, port from `$PORT` (Railway), plain `ws://` inside (the
edge terminates TLS). `/app` must be owned by the game user or the build-time import cannot write `.godot/`. Built and
run locally with Docker, and deployed once to Railway for the measurements above. Idle, the container used about
37 MiB and under 1 % of a core.

## Left open (follow-up issues)

- Latency through Discord's proxy (needs a Discord application, the maintainer's); reconnect and resume after a
  dropped socket. Railway is measured above from one place only: a player near `us-west2`, or a European one, would
  see other numbers.
- Combat-grade rewind (lag compensation) for hit detection; the spike only has movement and collisions.
- Binary packing of many entity kinds (zombies, projectiles): the entry layout will need a type byte and bit flags.
- Rate limits and input validation (inputs per second, packet size), authentication, and a protocol-version policy.
- Snapshot interest management (only what a client can see) once the world is bigger than one screen.
- The scenario test with a conditioner (delay, jitter, loss) in the link, in CI: today `tests/net/test_night_online.gd`
  runs the server and its clients over a real socket on loopback without one.
- Float determinism between client builds (wasm vs native): the shared `integrate` uses float math before rounding to
  integers; if it ever diverges, switch it to integer-only arithmetic.

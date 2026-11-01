# Multiplayer: the network-first architecture

**Status:** proposal, proven by a spike (`spikes/net/`, issue #6). The spike is throwaway; this page is its product.

Deadnight is a web game (a Discord Activity) with its server on Railway, and single-player must be the same game. So
the network is not a layer added to a finished game: the game is a **server simulation** and a **client** that talks
to it, and single-player is that same server running inside the client's process. The spike builds that shape end to
end and measures it.

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

Remote players are drawn **100 ms (3 ticks) in the past**, interpolated between the two snapshots around that moment.
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
  of link, jitter, plus the tick quantisation on both ends. Real Railway latency is **not measured**: that needs a
  deployment, which is the maintainer's decision.
- **Corrections** are zero when nothing disagrees (alone, or no collisions). They appear when the server pushes a
  capsule out of another (up to ~40 cm for one snapshot) or, with simulated loss and no redundancy, when a lost input is
  never applied (up to 61 cm). Three-fold input redundancy removes nearly all loss corrections for 117 B/s more.
- The first version (Godot's high-level multiplayer) measured: 2 players 3.5 KB/s up and 3.8 down in total; 4 players
  15.0 / 18.0; 8 players 49 / 62 (4-second windows through the byte-counting proxy). Same bots, same game.

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
- Verified in Chrome (Playwright, software WebGL) against the local server: the web client renders, connects, and moves.

## Local setup

`spikes/net/README.md` has every command. Port 9080 is **not** used: on the maintainer's machine the Godot editor MCP
bridge listens there, and Windows let the game server bind the same port silently; clients then reached the wrong
listener. Check a port with `netstat -ano | grep :<port>`.

## Server image

`spikes/net/Dockerfile`: Linux Godot 4.7.2 (SHA-512 from `tools.toml`), project imported at build time, runs
`godot --headless --path /app -- --server` as a non-root user, port from `$PORT` (Railway), plain `ws://` inside (the
edge terminates TLS). `/app` must be owned by the game user or the build-time import cannot write `.godot/`. Built and
run locally with Docker; **not deployed** (the maintainer decides). Idle, the container used about 37 MiB and under 1 %
of a core.

## Left open (follow-up issues)

- Real latency over Railway and through Discord's proxy; reconnect and resume after a dropped socket.
- Combat-grade rewind (lag compensation) for hit detection; the spike only has movement and collisions.
- Binary packing of many entity kinds (zombies, projectiles): the entry layout will need a type byte and bit flags.
- Rate limits and input validation (inputs per second, packet size), authentication, and a protocol-version policy.
- Snapshot interest management (only what a client can see) once the world is bigger than one screen.
- A scenario test that runs server + bots + conditioner headless in CI and asserts convergence.
- Float determinism between client builds (wasm vs native): the shared `integrate` uses float math before rounding to
  integers; if it ever diverges, switch it to integer-only arithmetic.

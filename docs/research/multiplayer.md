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
| Protocol | `NetWire`, version 5 (the layout is in its header; 5 put the client's measured round trip in the ping, [Scoreboard](scoreboard.md)); a command is a fixed 23 bytes, snapped by `CommandCodec` (#77, [below](#command-quantization-and-rewinding-the-body)); a `TICK` is a packed array of the events since the last one with the frame last; `LookWire` types 8 and 9 for looks; `MARK` (type 11, ten bytes) a client's ping, rate limited at 2 a second and answered with a `ping_placed` event for everyone | the version only in the handshake; refusal of another version |
| Snapshots | the `NightServer` frame, sent as a **difference against the frame that client had before** (`FrameDelta`): TCP never reorders or loses, so the previous frame is the baseline and no ack is needed. Compressed with Zstandard above 256 bytes | the spike's centimetre deltas against an acked baseline (they were for a protocol over an unreliable link) |
| Events | every client hears every event (shots, hits, rules); a late joiner gets the rules' snapshot in `WELCOME` (`HudState.load_snapshot`) and the doors, boards and circuits from the frames (`WorldMirror`) | |
| The local player | **predicted**: the client moves its own body at once and records where each numbered command left it; the frame's `ack` says which command the server used, and `Reconciler` moves the body a share (25 %) of the way to the server's answer per frame, snapping over 2.5 m | the spike replays the unacknowledged inputs on the server's position; the game does not replay yet |
| Everyone else | `RemoteAvatars`: a character in the player's look and seat armband, drawn **100 ms behind** the newest frame between two frames, walking or running by its speed. The model is stood the way `player.tscn` stands its own (turned half way round, scaled by `PlayerTuning.model_scale`, 0.8): the first version drew it at scale 1, a quarter taller than on the player's own screen and facing the camera; `test_a_player_is_as_tall_on_every_screen` holds it to a millimetre | the same delay, kept |
| Looks | a client sends its look once after joining (`--look N` replaces the saved one for a run); `NightServer` owns the `LookServer` and answers with `look_packet` events, which the host sends only to the player they are for; every screen dresses every body, a client's own included, from the one `LookRegistry` table | |
| Commands | a pressed edge is kept when two commands arrive together, a command not renewed for `NightTuning.command_ticks` (30) steps stops the player, the player is the connection's (#163) | |

Not in the game yet: lag compensation for shots (#54), interest
management and a tighter packing of zombies (#57), the Discord proxy (#52).

The first numbers from the real thing, loopback on one loaded machine: 222 bytes a `TICK` with two players and four
zombies (6.6 KB/s down), a command 47 bytes (2.8 KB/s up; 23 and 1.4 KB/s since protocol 2), a round trip of
2 to 18 ms. They are in
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
| `PING` 6 / `PONG` 7 | C→S / S→C | `u32 client_tick` / `u32 client_tick, u32 server_tick` | 7 / 9 |

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

### Command quantization and rewinding the body

Protocol 2 (#77) sends a command in 23 bytes instead of 47: a stick axis is a signed byte (1/127), the view turn a
`u16` (65536 steps, 0.0055 degrees), the look a `s16` over a quarter turn either way, the shot origin centimetres in
three `s16` (good to 327 m from the origin) and the shot direction as a turn and a look. `CommandCodec` holds the steps;
every `snap_*` is the decode of the encode, so a number is only ever one of the wire's values. A client that predicts
moves its body with `NetWire.quantize(command)`, the command as the server will read it: without that, a 600-tick run
with turns and jumps over a ramp ended 1.9 to 2 cm from the server's (`test_prediction_numbers.gd`), with it the two end
within 0.2 mm (what is left is the physics engine's own contact memory). Version 1 clients are refused (`Refusal.VERSION`).

A body moved by hand does not have the floor contact `CharacterBody3D.move_and_slide` keeps between calls (whether there
was a floor, its normal). Rewinding the body to an older state and replaying commands from it without setting that
contact left a replay up to 0.28 m off the run it replaces on a ramp on Windows (the body remembered "in the air"
while the state stood on the ramp; the same replay on the Linux CI runner followed the run exactly, so the effect depends
on the platform's float results and is not pinned by a test); `PlayerSimulation.restore(body, state, delta)` presses
the body into the floor with the snap turned off (or lets it hang, for a state in the air), then puts it back, and the
same replays end within 3 mm (the rest is the
seam where the ramp meets the floor). The game's `Reconciler` still does not replay, but takes the server's answer by
moving the body and calls `restore` for the move, so a snap over 2.5 m (a respawn) lands with the right contact. A
replaying client, when one is built, rewinds with the same call. The tests are `test_rewind_replay.gd` (from the ramp,
from mid-air above it, from every 13th tick of a run).

### Limits, hostile clients and the version policy

The server decodes nothing but fixed layouts from a client (`NetWire`), and since #55 it also holds each connection to a
budget (`PeerLimits`, `TokenBucket`; `test_peer_limits.gd`, and a hostile client over a real socket in
`test_night_hostile.gd`):

| Limit | Value | Why |
| --- | --- | --- |
| Packet size | 64 bytes at most, and each message type has its exact size (command 23, hello 2, ping 7, look 13); the socket's own buffer is 4 KB, so a frame of 200 KB is refused by the engine and the peer is gone | no client message is longer |
| Commands | 90 a second sustained, 240 at once | a client sends 60 a second; a 3 s stall of the connection delivers 180 together and is forgiven |
| Pings, looks, hellos | 4/s (burst 6), 1/s (burst 3), 1/s (burst 2) | a client pings twice a second and sends one look and one hello |
| Strikes | a packet over its rate costs 0.5, one the server cannot read (empty, too long, unknown type, wrong size, before hello, hello twice) costs 5; they wear off at 5 a second; at 100 the server hangs up | a flood of commands is cut off after about 450 packets, an honest client never gets one |
| Connections | 16 at once (the 17th is hung up on), and one that has not said hello in 10 s is dropped | idle sockets cost memory |
| Closing | a client that does not answer the closing handshake is let go after 1 s | a flooder's own backlog kept the old close pending forever |

A packet over a rate is dropped without telling the client. Commands out of order are not refused: over TCP they cannot
arrive out of order, and a client that lies about its `seq` only confuses its own reconciliation. The shot origin is
already held within `NightTuning.origin_slack` of the player's head by the server.

**Version policy.** `NetWire.VERSION` is the protocol of this build and `MIN_VERSION` the oldest client it takes; today
they are equal, because the web client and the server are built from one commit and deployed together. A layout change
(a field added, resized or reordered, a type renumbered) raises `VERSION`; new keys in events and frames do not, because
clients ignore keys they do not know. A client of another version is sent `REFUSED(VERSION, server_version)` and hung up
on, and the game says which side is behind: the server speaks a newer version, so reload the page; or an older one, so
the server is not deployed yet. To support the old client for one release, lower `MIN_VERSION` and keep both layouts
readable for that release. Nothing is negotiated.

**Authentication hook.** `NightHost.admit` is called with `(transport_id, version)` after the version is accepted and
returns 0 to let the client in or a `Refusal` (`DENIED`) to turn it away. It is unset today (everyone is let in); the
platform backend's ticket check plugs in there (see [the backend](platform-backend.md)) once hello carries a ticket.

### Server bodies and drawn avatars (#153)

A single-process night draws the server's own bodies (the Soldier's model, skeleton and animation), so the world is
one scene. A game server draws nothing: `NightServer.drawn_bodies` is false under `NightHost`, and `NightWorld.add_body`
then calls `Player.strip_model`, which frees the `Model` and the `AnimationTree` and leaves an empty `Model` node, the
collision and the simulation. A body is **5 nodes** on a server and 71 drawn (`test_server_bodies.gd`), and walks the same
(the model has no part in `PlayerSimulation`; the test replays 120 ticks on both). Each client draws the others from the
frames as `RemoteAvatars`, and a door's look follows `door_opened`: the split of the issue is the transport since #302,
this removes the cost of the bodies on the server.

One thing the server decides that no command says: while a player repairs, the server turns the body toward the breach
(#338). The frame marks such a player (`turn`), and the player's own predicted body takes the server's facing for those
frames (a position correction is not enough: the facing is not in `Reconciler`).

### Reconnect and resume

A client whose socket drops (a phone changing network, a proxy cutting an idle socket, a Wi-Fi blip) gets its player
back (#53, protocol version 3):

- **The token.** Every WELCOME carries 8 random bytes, one set for each connection and replaced on every resume. A client
  that comes back says HELLO with them after the version. The token proves nothing but being the same client; a made-up
  or used token is just a new player, never someone else's seat (`test_a_token_that_is_nobodys_is_a_new_player_not_a_hijack`,
  `test_a_used_token_does_not_work_twice`).
- **What the server does meanwhile.** A socket that closes without a goodbye (anything but close code 1000 or 1001) keeps
  its seat and body for `NightHost.RESUME_WITHIN` (30 s): no commands come, so after `NightTuning.command_ticks` steps the
  body stands still and the dead can hurt it like any other (a downed player is revived by the others as usual); the other
  players keep seeing it. A clean goodbye (the page closed, the Leave button) frees the seat at once. The seat is not given
  to a newcomer while it is held, and the night is not rebuilt while one is.
- **Coming back.** A HELLO with a held (or still-open, not yet noticed dead) token takes the seat: the same player id,
  body, points and weapons, a new token, the rules' snapshot as they are now and the looks of everyone again, and a first
  frame that is whole (the diff against nothing). The old socket, if it was still open, is hung up on.
- **The client.** `WebSocketLink` tries a new socket every second for 25 s (`resume_within`, a little under the server's
  hold), says `lost` when it begins and `resumed` when the seat is back, and `closed` when the time is up or the server
  turned it away. `Night` has `connection_lost`, `connection_resumed` and `connection_ended` signals; while the socket is
  down the client's body waits where it is, and when the seat is back the HUD loads the new snapshot and the reconciler
  takes the body to the server's position.
- **Not here yet:** a message on screen while the link is down (the signals are there), and the link conditioner (delay,
  jitter and loss) of the spike: the tests cut the socket with `WebSocketLink.drop()`, which closes it with a private
  close code the server reads as "the network went", and `test_reconnect.gd` runs over a real socket.

### A client that freezes (#483)

The maintainer's report: after a hitch (the first flare shot loading its effect) the player "flies all over the map until
only the skybox shows". The server logs had nothing to show for it (joins, stats and leaves; the server saw a client that
went quiet and came back), so the cause came from a reproduction, `test_client_freeze.gd`: the server as a process of
its own, the client over the real socket with 100 ms each way, a person walking with the keys, and the client's thread
stopped with `OS.delay_msec` for 0.5, 2 and 5 s.

- **The cause was `Reconciler`, and a freeze only set it off.** A correction moved the body but left the remembered
  positions of the commands still unanswered where they were. The server's answers are a round trip behind, so the next
  frames measured the same error again and corrected it again: each correction (a quarter of the error, or all of it over
  2.5 m) was repeated for every frame in flight. With a round trip of about 200 ms the repeats outweigh the error, and
  the body is thrown further each time, exponentially (to 10^23 m in 15 s on `main`, with no freeze at all, once
  anything pushed the body off by more than the 3 cm deadzone). A freeze is the surest push: the engine runs up to eight
  ticks at once to catch up, the server takes only the newest of the commands that come together, and the client is
  some 0.7 m ahead of it. The fix shifts the remembered positions by every correction (`Reconciler.correction`).
  `test_reconciler_loop.gd` runs the loop in one dimension at 50 to 400 ms: 14 of 20 cases ended thousands of metres
  off on `main`, none now. A body far from the server with no answer to judge it by is put where the server says (`LOST`).
- **The tests had missed it** because the network was the thing that stalled (`LinkConditioner` holds packets back while
  the client's own loop keeps running, and at 25 ms the loop above is stable): nothing froze the _client_, and nothing
  ran a round trip long enough for the loop to matter while anything pushed the body.
- **After a freeze the client starts again from the server's state** (`StallGuard`). A gap of over 250 ms between two
  ticks resyncs: the body goes where the newest frame of the backlog has the player, the commands in flight are forgotten,
  and the ticks the engine runs to catch up (under 8 ms apart) neither move the body nor send a command. The server
  goes on with the last command for `command_ticks` (half a second, 3 m of sprint), so the client is then snapped back
  to it: 5.4 to 5.6 m at worst in the test, 0.00 to 0.03 m after the player stops.
- **A long freeze must not drop what the server sends.** The engine's default socket buffers are 64 KB: at 15 to 35 KB a
  second a client that read nothing for about three to twelve seconds lost the newest ticks (an `ERROR: Buffer payload
  full` in the browser's console, as seen at game over), and the frame deltas that followed were against frames it never
  had, so a position that changed in a lost tick stayed wrong for good (3.7 m in `test_stall_buffers.gd`). The client's
  inbound and the server's outbound buffers are now 1 MB each with room for 8192 packets (a minute or more), and a tick
  the socket still would not take makes the next frame whole. `peer_stalled` and `peer_recovered` in the server log say
  when it happened. No wire change: the protocol version stays.
- **What is not done:** the browser build was not frozen on purpose here (the Chrome probe needs a night with the flare
  in hand). The flare's own first-shot hitch is in [First-use hitches](first-use-hitches.md#the-flares-first-shot-483).

## Match settings

The rules of a match (zombie intensity, alive cap, break: `MatchSettings`, #414) are the
server's and travel inside the rules' snapshot, version 10, as `match_settings`.
That is the whole protocol change: the WELCOME already carries `GameRules.to_dict()`, so the first player, a late
joiner and a player coming back read the same settings from it (`MatchSettings.from_snapshot`), and the protocol
version is not raised. The host sets them with `NightHost.configure_match` before the night starts; once it began
the call changes nothing for this night. Tested over a real socket in `test_match_settings_net.gd`. Details and the
numbers are in [rounds](../design/rounds.md#match-settings).

## Revives

A teammate's revive (#486, [Revive](../design/revive.md)) is made of what is already on the wire. The hold is the
`use_held` flag every command carries (`F_USE_HELD`); the server finds who is in reach, counts the hold in its revive
channel (`revive` to the rules when it is complete) and answers with events (`revive_started`, `revive_stopped`, `player_revived`
with a `reviver_id`, `player_died`) and, in every frame, four fields for every player: `bleed`, `dead`, `revive` and
`reviver`. A frame after the first carries only what changed, so a field that is sometimes absent can never be cleared
by a delta: these four are always there. The rules' snapshot (so every WELCOME) holds each player's `revives`, `dead`,
`bleed_left`, `revive_progress` and `reviver_id`: **snapshot version 12**, and the protocol version is not raised (no
byte layout changed). A hold the client stops sending is released by the channel at the next tick, so a lost or late
command breaks a hold and never leaves one stuck. Tested over a real socket in `test_night_revive_online.gd`.

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

### Measured on the game's own server (#52, 2026-11-01)

The game server (`deploy/server/`, the head of `main` at the time, protocol version 2) on the same Railway service, a
headless desktop client and the web build in headless Chrome (graphics card) joined one night from the same machine
(Houston; TCP connect to the edge 29 ms mean, 76 ms worst of 10; TLS done at 81 ms). One night of three players, round 3,
15 zombies at most:

| What | Desktop client (315 s) | Web client in Chrome (120 s) |
| --- | --- | --- |
| Round trip, ping to pong, read on the client's tick | mean 78 ms, worst p95 132 ms, max 132 ms (621 samples) | mean 77 ms, p95 86 ms, max 90 ms (118 samples) |
| Gap between TICKs (30 a second is 33.3 ms) | mean 33.3 ms, worst p95 59 ms, max 107 ms, 1 stall over 100 ms in 9540 | not read |
| Down / up | 8.7 KB/s down, 1.4 KB/s up (one bot, three players) | not read |

The server's `stats` lines with three players: 25 KB/s out in all, 2.6 ms of work a 60 Hz step on average, 8 to 20 ms
worst. So the 100 ms interpolation delay and the 30 Hz snapshots stay (one stall in 9540 ticks is covered by the
delay), and the cost of a night is bandwidth that fits a phone. The two clients saw each other (`players` [1, 2, 3] in
the frame and three portraits on the HUD) and the zombies killed raised the points of the bot and the second player.
Not measured: the Discord proxy, a lossy network, a server far from the player (the service runs in one region).

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

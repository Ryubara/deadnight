# Networking comparison: own protocol, Godot MultiplayerAPI, netfox

**Status:** measured on one machine, for the maintainer to decide (issue #38). Nothing here chooses; it reports.
Every number is labelled **measured** (we ran it; the raw lines are in
`spikes/net-compare/results/measurements.txt`), **cited** (a vendor page, linked) or **estimated** (reasoned, not run).

Fixed whichever way we go: authoritative headless Godot server on a 30 Hz tick, client prediction and reconciliation,
interpolation of others, single-player through the same path, web export, Docker hosting, a separate platform
backend. See [Multiplayer](multiplayer.md) for the own-protocol design this compares against.

## The three candidates

| | Own protocol | MultiplayerAPI (built in) | netfox on MultiplayerAPI |
| --- | --- | --- | --- |
| Transport | `WebSocketPeer` + `TCPServer` | `WebSocketMultiplayerPeer` | `WebSocketMultiplayerPeer` |
| State to clients | our snapshot, i8 deltas against an acked baseline | `MultiplayerSynchronizer` per entity, `ON_CHANGE` | `RollbackSynchronizer` (players), `StateSynchronizer` (zombies) |
| Input to server | `INPUT` message, sequence numbers | one RPC per tick, we add the sequence number | netfox input history (`Input` node) |
| Prediction, reconciliation | ours | ours (the engine gives values, not a model) | netfox: rewind and re-simulate |
| Interpolation of others | ours (snapshot ticks) | ours (arrival time: the engine sends no tick) | `TickInterpolator` (not used in the headless runs) |
| Simulation | node-free `GameSim` | same `GameSim`, copied into entity nodes | same `GameSim` rules inside `_rollback_tick` |

The scenario is the same everywhere: 4 players (seeded bots) and 24 zombies, 30 Hz, one shared `GameSim` (integer
centimetres, players pushed apart, zombies walk to the nearest player). It lives in `spikes/net-compare/` (own and
MultiplayerAPI, `--mode=own|mp`) and `spikes/net-compare-netfox/` (netfox, fetched by a script, never committed).

## How it was measured (identical for all three)

`spikes/net-compare/tools/run_scenario.py` starts the headless server and N headless bot clients, and puts a **TCP
proxy** between them. Because it works on bytes, no stack needs a hook:

- **Bandwidth** is what the proxy forwards: payload plus WebSocket framing, **without** TCP/IP headers (about 40 B per
  packet more, so add roughly 1.6 KB/s at 40 packets/s; the netfox runs send 800 to 1200 packets/s, 30 to 50 KB/s more).
- **Latency** is a fixed delay per chunk in each direction (50 ms each way gives 100 ms RTT).
- **Loss** models TCP, not UDP: with probability 2 % per chunk the chunk is "lost" and re-delivered 300 ms later
  (a retransmission timeout), and **every later chunk in that direction waits behind it** (head-of-line blocking).
  It is a model of TCP's behaviour, not real packet loss: real loss was not available on this machine.
- **Server CPU** is the server process tree's CPU time over a 10 to 18 s window, as a percentage of one core.
- **Feel** is the client's own log: the *gap* between arrivals of its own authoritative state (33 ms is ideal; a
  stall shows as one long gap) and the *correction* (how far an authoritative update moved the predicted position;
  the same definition for own and MultiplayerAPI; for netfox it is the visible jump of the player's position per
  tick against what its input explains, so it is **not strictly comparable**).

Caveats that apply to all numbers: Windows, localhost, one run per cell unless stated (the machine is shared, so CPU
and tail latencies are noisy), Godot 4.7.2 headless, `Engine.max_fps = 60` on every server. Linux in Docker was not
measured. Railway latency was not measured (the maintainer allowed test deployments late in the task; the time box
did not leave room, and the own-protocol deployment is another engineer's task, #52).

## Results

### Bandwidth per client and server CPU: 4 players + 24 zombies, 30 Hz, clean link (measured)

| Stack | Down per client | Up per client | Server CPU (one core) |
| --- | --- | --- | --- |
| Own protocol (deltas) | 2.4 to 2.9 KB/s | 0.56 KB/s | 2.0 to 4.3 % |
| MultiplayerAPI, server-owned, default | 20 to 23 KB/s | 0.78 KB/s | 2.5 to 5.2 % |
| MultiplayerAPI, position packed in one int32 | 15 to 17 KB/s | 0.78 KB/s | about 5 % (one run) |
| netfox 1.35.3, default settings | 37 KB/s | 19.6 KB/s | 28 to 30 % |
| netfox, tuned (input redundancy 1, input broadcast off) | 30 KB/s | 12.0 KB/s | 25.6 to 27.6 % |

- The own protocol sends 3 bytes per moved entity (id, dx, dy) and one header per snapshot. The MultiplayerAPI sends a
  separate sync record per entity with the engine's own addressing and a Variant per property: about 25 B per entity
  per tick with a `Vector2i`, about 20 B packed into an int32. Zombies move every tick, so `ON_CHANGE` saves nothing
  for them.
- Absolute cost is small either way: 4 clients at 23 KB/s is 0.33 GB/h of server egress; at Railway's published
  $0.05/GB that is about $0.017 per match-hour (own protocol: about $0.002). For a player on mobile data, 23 KB/s is
  83 MB/h against 9 MB/h.
- netfox sends hundreds of small messages per second (800 to 1000 packets/s down per client against 40 for the others).
  We did not isolate the cause. netfox's issue tracker has an open report of state being re-broadcast for every
  resimulated tick ([#630](https://github.com/foxssake/netfox/issues/630)); we cannot say it is this one.
  A careful netfox user may well get lower numbers with more tuning than we did in the time box.

### Does bandwidth grow with the square of the players? (measured, clean link, 24 zombies)

The first, dropped spike on the high-level API reported upstream of 1.8, 3.7 and 6.1 KB/s per client for 2, 4 and 8
players. Reproduced, and explained:

| Players | Own (down / up) | MP server-owned (down / up) | MP packed (down / up) | MP **client-owned** players (down / up) |
| --- | --- | --- | --- | --- |
| 2 | 2.7 / 0.56 KB/s | 20.2 / 0.78 | 15.3 / 0.78 | 2.0 / 2.2 |
| 4 | 2.4 / 0.56 | 23.3 / 0.78 | 16.6 / 0.78 | 3.8 / 4.6 |
| 8 | 2.9 / 0.56 | 24.4 / 0.77 | 18.9 / 0.77 | 6.9 / 8.6 |

- **It is an artefact of client authority, not of the MultiplayerAPI.** With players' synchronizers owned by their
  clients, each client sends its state once *per other peer* (the server only relays), so a client's upstream grows
  with the player count and the server's total grows with its square (our last column: 2.2, 4.6, 8.6 KB/s up).
  With server-owned synchronizers and input-only RPCs a client's upstream is **constant** (0.78 KB/s at 2, 4 and 8)
  and downstream grows only with the number of entities (20 to 24 KB/s, the zombies dominate).
- The client-owned column leaves the zombies idle (the server there does not know where players are), so its
  downstream is players only; compare its *shape*, not its level. Do not use it as a "cheaper" option: it also gives up
  server authority.
- What stays true in every design: each client must be told about every entity it can see, so total server egress is
  players x entities. That is why snapshot size per entity (3 B against 20 to 25 B) matters, and why interest
  management ([Multiplayer](multiplayer.md), left open) matters once the world is large.

### Feel under 100 ms RTT, and with 2 % TCP loss (measured, 4 players, 24 zombies)

Gap between arrivals of the client's own state, in ms (33 is ideal). Mean of the 4 clients; one run per cell.

| Scenario | Own p95 / p99 / max | MultiplayerAPI p95 / p99 / max | netfox |
| --- | --- | --- | --- |
| clean | 35 / 38 / 50 | 35 / 46 / 70 | n/a (see below) |
| 100 ms RTT | 46 / 67 / 170 | 59 / 75 / 87 | n/a |
| 100 ms RTT + 2 % TCP loss | 59 / 333 / 337 | 264 / 347 / 633 | n/a |

- Under the TCP model a lost chunk freezes everything behind it for 300 ms: the stall shows as one gap of about
  330 ms followed by a burst. Both stacks show it; neither can avoid it over WebSocket. The own protocol's *tail*
  looked a little better in this one run, but with 4 clients and one run per cell we do not claim a difference
  between the two.
- Corrections over 1 cm per ~650 ticks at 100 ms RTT: own 36 to 165, MultiplayerAPI 34 to 124, mean 0.7 to 4.6 cm,
  max 40 to 126 cm (own) and 24 to 75 cm (MultiplayerAPI): both come from the server pushing
  players apart, not from the transport. With loss, own and MultiplayerAPI stay in the same range
  (TCP delays inputs, it does not drop them, so no input redundancy is needed: `--input-redundancy=1`).
- netfox: gaps are not logged (its sync is inside the addon). Its visible position jumps are larger under delay and
  stall: mean 0.3 to 3.5 cm, max 79 to 182 cm at 100 ms RTT, and mean 2.6 to 6.9 cm, max up to 577 cm with loss; its
  measured RTT (its own time sync) read 575 to 616 ms under loss against 220 ms for the other two. Different
  definitions of "correction" (see above): treat it as a warning to test, not a verdict.
- UDP is not available to web clients (see hosting), so "loss" on the real product is always a TCP stall like this one.

### Server CPU, repeated (measured)

Server process CPU as a percentage of one core, 4 players + 24 zombies, clean link, three runs each on an otherwise quiet
machine (earlier single runs on a busier machine read 5 to 9 % for own and MultiplayerAPI, so treat anything under
about 5 points as noise):

| Stack | Run 1 | Run 2 | Run 3 |
| --- | --- | --- | --- |
| Own protocol | 2.2 % | 2.0 % | 4.3 % |
| MultiplayerAPI, server-owned | 2.5 % | 4.7 % | 5.2 % |
| netfox (tuned) | 25.6 % | 26.2 % | 27.6 % |

Own and MultiplayerAPI are indistinguishable at this size (the spike's idle server was under 1 %); netfox costs about
ten times more, in every run, with the default and the tuned settings. A 1 vCPU Railway service is not at risk for 4
players with any of them, but netfox leaves the least headroom for the real game's simulation.

## Single-player, web export, testability

- **Single-player through the same path.**
  *Own:* measured in the merged spike: a loopback transport; one code path, no "offline" branch.
  *MultiplayerAPI (measured, `--mode=mp --local`):* the default `OfflineMultiplayerPeer` runs the same spawner, nodes
  and server class in one process: 150 inputs sent, 149 applied, 24 zombies spawned, no errors. Two catches: an
  RPC to ourselves with `call_remote` is an engine **error** ("RPC 'ping' on yourself is not allowed by selected
  mode"), so the input RPC needs `call_local` and the ping must be skipped; and the synchronizers never fire (nothing
  travels), so the client reads the entity directly, which is a second code path in the client.
  *netfox:* its examples include a [single-player example](https://github.com/foxssake/netfox/tree/v1.35.3/examples/single-player)
  that we did not run (**estimated**: works, but the full rollback machinery runs for one player).
- **Web export.** Own: measured in the merged spike (Chrome, single-threaded export). MultiplayerAPI: Godot documents
  `WebSocketMultiplayerPeer` for web clients ([docs](https://docs.godotengine.org/en/stable/tutorials/networking/websocket.html));
  **not run** here. netfox: its README and docs say nothing about web; a maintainer answered an issue that it is
  "protocol-agnostic" ([#146](https://github.com/foxssake/netfox/issues/146)); our runs show it works over
  `WebSocketMultiplayerPeer` on desktop headless, the web build was **not run**.
- **Testability without a scene tree.** Own: `Protocol`, `GameServer` over a loopback transport and `GameSim` are
  `RefCounted`/`Node` with no tree needed for the sim and the protocol (`GameSim` and `Protocol` need none at all).
  MultiplayerAPI: replication happens in nodes inside a running `SceneTree` with a peer, so a test needs a tree and
  two peers (the `GameSim` underneath is still testable alone). netfox: the same, plus its autoloads and tick loop.

## Code size and effort (counted lines; the "door" is estimated)

| | Lines | What is in it |
| --- | --- | --- |
| Own protocol | 913 | server 188, client 251, protocol 169, transports (WebSocket, loopback, interface) 270, peer state 35 |
| MultiplayerAPI | 350 | server 84, client 121, entity 58, world and RPCs 47, entry 40 |
| netfox | 193 | app 110, player 40, zombie 27, input 16 (plus the addon, 4 000+ lines, third-party) |

- The own protocol is bigger *and does more*: deltas against acked baselines, a loopback for single-player, a link
  conditioner for tests. The MultiplayerAPI count has no deltas, no single-player and no conditioner. Read the
  lines as "what we write to get to the same prototype", not as quality.
- **A new networked thing (a door), estimated:** own protocol, an entity kind needs a type byte and its fields in the
  protocol (encode and decode), server state and delta rules, client decode and interpolation: about 5 places and
  40 to 60 lines. MultiplayerAPI: one spawn case and a property list: about 15 lines, as MpEntity shows (the zombie
  needed only an id check). netfox: similar to MultiplayerAPI plus choosing rollback or state-only per kind.
  The own protocol's cost is paid once if entry layouts are generated from a table (an open item in
  [Multiplayer](multiplayer.md)).

## Hosting facts (cited)

- **Railway has no documented inbound UDP.** Its networking docs describe HTTP/HTTPS domains and a TCP proxy only:
  "TCP Proxy enables you to expose non-HTTP services to the internet"
  ([TCP Proxy](https://docs.railway.com/networking/tcp-proxy),
  [Networking](https://docs.railway.com/networking),
  [Public networking](https://docs.railway.com/reference/public-networking)). A feature request for native inbound UDP
  is `under_review` ([Help Station](https://station.railway.com/feedback/adding-inbound-udp-fad19847)). No Railway
  statement says "we do not support UDP" and none says it does: absence of documentation. The backend engineer's
  deployment (#52) tests it.
- **WebSocket over Railway's HTTPS domain works**: "Support for websockets over HTTP/1.1", and "Websocket connections
  are exempt from these duration and inactivity limits"
  ([Specs and limits](https://docs.railway.com/networking/public-networking/specs-and-limits)). TLS terminates at
  the edge ([Edge networking](https://docs.railway.com/networking/edge-networking)). Two Help Station threads report
  upgrades failing at the edge (one app-side), so test it end to end.
- Do not send WebSockets through the TCP proxy: it is "for raw TCP, not HTTP upgrades"
  ([thread](https://station.railway.com/questions/web-socket-upgrade-not-reaching-app-meta-5efe7579)).
- Prices ([Railway plans](https://docs.railway.com/reference/pricing/plans)): $20 per vCPU-month, $10 per GB-month
  RAM, $0.05 per GB egress.
- **It does not matter for the choice between the three**: a web client (the Discord Activity) can only use WebSocket
  or WebRTC, and Discord's proxy reaches us over HTTP and WebSocket. All three candidates run on TCP/WebSocket here.
  UDP would only matter for a native-only build or WebRTC.
- If UDP is ever needed: **Edgegap** takes Docker images, supports UDP and TCP, and WebSocket with a TLS upgrade, has a
  Godot + netfox sample ("Forest Brawl") and bills per vCPU-minute and egress
  ([docs](https://docs.edgegap.com/docs/sample-projects/godot.md),
  [WebSocket guide](https://docs.edgegap.com/docs/sample-projects/unity-netcodes/mirror-on-edgegap-websocket),
  [2025 pricing post](https://edgegap.com/blog/announcement-offering-changes-for-2025); rates not re-verified for
  today). **Fly.io** needs a dedicated IPv4 for UDP and the service bound to `fly-global-services`
  ([docs](https://docs.fly.io/networking/udp-and-tcp)).

## netfox: version support, licence, maintenance (cited)

- **Licence:** MIT ([repository](https://github.com/foxssake/netfox), GitHub reports `MIT`; each addon folder ships a
  `LICENSE`). Using it still means committing third-party code with a licence entry: that is the maintainer's call
  under the repository rules, so the prototype does **not** commit the addon (a script fetches it).
- **Godot versions:** the README says "Godot 4.x is supported by netfox"; its `project.godot` declares 4.1. **No
  statement of Godot 4.7 support was found**, and no release notes name a Godot version. We ran v1.35.3 on Godot 4.7.2
  headless without errors in our scenario: that is evidence for our use, not a support promise.
- **Releases:** the newest tag and release is v1.35.3 (23 November 2025). The default branch is active (last commit
  26 September 2026) and its `plugin.cfg` reads 1.49.4, so users on tags are about eleven minor versions behind main.
  1 124 stars, 54 open issues, one dominant maintainer (271 of the top contributors' commits against 13 for the next).
- **Fit:** "Client-side Prediction and Server-side Reconciliation", client-server, a network simulator and an
  Edgegap partnership are advertised. Documented web support: none. Lock-in: its rollback model dictates how
  simulation code is written (`_rollback_tick`, properties named in state/input lists) and ties simulation to
  nodes.

## What each choice means (for the maintainer)

| | Own protocol | MultiplayerAPI, server-owned | netfox |
| --- | --- | --- | --- |
| Bandwidth per client (4 + 24) | **lowest, measured**: 2.4 to 2.9 KB/s | 7 to 10 times more, measured; 6 to 7 times with packing | 12 to 15 times more, measured (not tuned further) |
| Server CPU (4 + 24) | 2 to 4 % | 2.5 to 5 % | 26 to 28 % |
| Feel under delay and TCP stalls | good; stalls unavoidable on TCP | same range, measured | not comparable; larger visible jumps; test before relying |
| Single-player | loopback, measured | needs a local shortcut | upstream example, not run |
| Code to get a prototype | most (913) | middle (350, fewer features) | least of ours (193), plus addon |
| New networked thing | ~5 places | ~1 place | ~1 place |
| Testability without a tree | best | needs a tree and peers | needs a tree, autoloads |
| Lock-in and upkeep | ours entirely | the engine's API, stable across 4.x so far | one maintainer, no Godot 4.7 statement, rollback model |
| Licence | ours | engine (MIT) | MIT, third-party commit decision |

**Reading of the evidence (the maintainer decides).** The quadratic-traffic claim does not hold against a careful
use of the MultiplayerAPI: it is a property of client-owned synchronizers. A careful MultiplayerAPI setup is
therefore a real option, with about half the code and cheaper new entity kinds, at 7 to 10 times the bandwidth of our
deltas and no ready single-player path. Our protocol is the cheapest on the wire and in testability and the most
code to own. netfox solves prediction for us but cost the most bandwidth and server CPU in our setup, has no
stated Godot 4.7 support or web claim, and is a third-party commit. If bandwidth, mobile data and a node-free
testable simulation matter most, the own protocol is supported by the numbers; if time to the first playable
matters most and 20 KB/s per client is acceptable, the MultiplayerAPI server-owned setup is supported by them.

## Not measured, for follow-ups

- Real network and Railway latency, Linux/Docker CPU, memory.
- Web export of the MultiplayerAPI and netfox builds; browser WebSocket throughput.
- netfox with more tuning (state interval, visibility filters, fewer synchronized properties), and its `TickInterpolator`.
- Real packet loss (we model TCP stalls), jitter, and many more than 8 players.
- Rollback for hit detection (lag compensation) with any of the three.
- The "intermittent engine error" below.

**Observed once:** a MultiplayerAPI server run with 4 clients joining at once logged
`Invalid packet received. Size too small` from `scene_cache_interface.cpp` (4 lines, in one of about 20 runs); the
run still completed. Not reproduced; a reason to stagger joins or test it before relying on spawn timing.

## Reproduce

```text
spikes/net-compare/tools/run_all.sh <godot> <out>        clean, 100 ms RTT, 100 ms RTT + 2 % loss; own and MultiplayerAPI
spikes/net-compare/tools/run_scaling.sh <godot> <out>    2, 4, 8 players, four server setups
spikes/net-compare/tools/run_cpu.sh <godot> <out>        server CPU, three repeats, needs spikes/net-compare-netfox set up
spikes/net-compare-netfox/tools/setup_netfox.sh          fetches netfox v1.35.3 and the shared scripts (not committed)
```

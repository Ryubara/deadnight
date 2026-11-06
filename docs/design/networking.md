# Networking

Decided by the maintainer on 2026-11-01, from the measured comparison in
[Networking comparison](../research/networking-comparison.md).

## The decision

Deadnight uses **our own protocol over a plain WebSocket**, not Godot's MultiplayerAPI (RPCs, MultiplayerSpawner,
MultiplayerSynchronizer) and not netfox.

- **Why:** about 8 times less download per player than the MultiplayerAPI set up server-authoritative (2.4-2.9 KB/s
  against 20-23 KB/s for 4 players and 24 zombies at 30 Hz), at the same server CPU and the same feel. Bandwidth is
  what browser and Discord players and hosting costs feel; netfox cost about ten times the server CPU.
- **Eight seats (#690):** a room held eight people and bots together; a person is sent about 14 KB/s and sends 1.5 KB/s
  at eight players with a crowd ([measured](../research/multiplayer.md#eight-players-690)). Since #1179 the eight are
  **people**: the bots take no seat and have ids of their own (101 and up), so a night holds up to 15 bodies. Protocol
  version 16 (no layout changed; a client of 15 would keep eight rows and eight seats and draw it wrongly)
  ([measured](../research/multiplayer.md#eight-people-and-bots-1179)).
- **The shape:** one authoritative headless Godot server on a fixed 30 Hz tick; clients send inputs, the server sends
  delta snapshots against the last one each client acknowledged; clients predict and reconcile their own player and
  interpolate everything else. Single-player runs the same server in the game process over a loopback transport.
- **Where it lives:** the spike's code in `spikes/net/` (transport interface, protocol v1, server, client) is the
  starting point; game systems stay plain data in and plain data out (the rules engine, the player simulation, the
  zombie state) so the server owns them and the protocol carries them.
- **Zombie snapshots:** `ZombieCodec` spends 13 bytes a zombie and has hard limits (u16 ids alias past 65535, positions
  wrap past 327.67 m from the origin); they are listed with their tests in
  [the zombie research](../research/zombies.md#snapshot-limits), and the wire protocol must either keep to them or widen
  the fields.
- **Hosting:** the game server runs as a Docker image on Railway (TCP and WebSockets on its HTTPS domain); the platform
  backend is separate ([research](../research/platform-backend.md)).

## Names in a night

The game server puts the ticket's name on the player's seat, so every client shows the same names (#485). Two seats never
show the same name in any case of letters: the later one becomes `Ann (2)`, `Ann (3)`, cut to the HUD's 20 characters
first so the number is never lost. A WELCOME carries every seat's name (`names`: player id to name) so a player who joins
late or comes back shows everyone at once; the others hear a new name as a `player_named` event. A seat with no name stays
`PLAYER n`, and the seat keeps its name while the player is away. These are new keys, and the protocol version is 9
(8 added the aim pose and look to each player of the frame, 7 sent the zombies as deltas).

## Before the night

Players meet in a lobby on the platform backend, which polls rather than pushes and lets a night in progress take
newcomers: [the lobby](lobby.md).

## Open work

Server and bots in CI (#56), latency over Railway and Discord (#52).

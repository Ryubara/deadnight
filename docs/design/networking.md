# Networking

Decided by the maintainer on 2026-11-01, from the measured comparison in
[Networking comparison](../research/networking-comparison.md).

## The decision

Deadnight uses **our own protocol over a plain WebSocket**, not Godot's MultiplayerAPI (RPCs, MultiplayerSpawner,
MultiplayerSynchronizer) and not netfox.

- **Why:** about 8 times less download per player than the MultiplayerAPI set up server-authoritative (2.4-2.9 KB/s
  against 20-23 KB/s for 4 players and 24 zombies at 30 Hz), at the same server CPU and the same feel. Bandwidth is
  what browser and Discord players and hosting costs feel; netfox cost about ten times the server CPU.
- **The shape:** one authoritative headless Godot server on a fixed 30 Hz tick; clients send inputs, the server sends
  delta snapshots against the last one each client acknowledged; clients predict and reconcile their own player and
  interpolate everything else. Single-player runs the same server in the game process over a loopback transport.
- **Where it lives:** the spike's code in `spikes/net/` (transport interface, protocol v1, server, client) is the
  starting point; game systems stay plain data in and plain data out (the rules engine, the player simulation, the
  zombie state) so the server owns them and the protocol carries them.
- **Zombie snapshots:** `ZombieCodec` spends 12 bytes a zombie and has hard limits (u16 ids alias past 65535, positions
  wrap past 327.67 m from the origin); they are listed with their tests in
  [the zombie research](../research/zombies.md#snapshot-limits), and the wire protocol must either keep to them or widen
  the fields.
- **Hosting:** the game server runs as a Docker image on Railway (TCP and WebSockets on its HTTPS domain); the platform
  backend is separate ([research](../research/platform-backend.md)).

## Open work

Reconnect and resume (#53), lag compensation for hits (#54), input validation, rate limits and a version policy (#55),
server and bots in CI (#56), more entity kinds and interest management (#57), latency over Railway and Discord (#52).

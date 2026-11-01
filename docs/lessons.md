# Lessons

Problems we hit and how we solved them, newest first. Five lines each: date, symptom, cause, fix, where it is
documented.

## 2026-11-01: a client could not connect to a server that was listening

- **Symptom:** `ERROR: Invalid ID received from server` on the client; the server printed nothing and showed no peers.
- **Cause:** port 9080 was already taken by another WebSocket server (the Godot editor's MCP bridge). Windows let the
  game server bind the same port, so connections went to the other listener, which is not our server.
- **Fix:** the spike listens on 8910. Before picking a port, check it: `netstat -ano | grep :<port>`.
- **Documented:** [Multiplayer research](research/multiplayer.md#local-setup).

## 2026-11-01: the server image failed to import the project

- **Symptom:** `docker build` printed `Could not create project data directory (res://.godot)`, and the container then
  failed with parse errors on every script that uses a `class_name`.
- **Cause:** `WORKDIR /app` makes a root-owned folder; the non-root user could not create `.godot/` (the import cache
  and the global class list) inside it.
- **Fix:** create `/app` and `chown` it to the game user before the `COPY` and the build-time `--import`.
- **Documented:** `spikes/net/Dockerfile`, [Multiplayer research](research/multiplayer.md#server-image).

## 2026-11-01: a handshake packet was rejected for being one byte short

- **Symptom:** the client connected and received snapshots, yet never became a player (id stayed 0).
- **Cause:** the decoder's minimum-length check for WELCOME counted 9 bytes; the packet is 8 (type, version, id, rate,
  4-byte tick). A malformed-packet guard silently dropped every valid welcome.
- **Fix:** derive each minimum length from the layout comment in `protocol.gd`, and print a counter for dropped packets
  while developing. A guard that fails closed hides its own bug.
- **Documented:** [Multiplayer research](research/multiplayer.md#protocol).

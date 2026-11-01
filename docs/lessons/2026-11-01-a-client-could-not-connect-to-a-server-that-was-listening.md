# A client could not connect to a server that was listening

2026-11-01

- **Symptom:** `ERROR: Invalid ID received from server` on the client; the server printed nothing and showed no peers.
- **Cause:** port 9080 was already taken by another WebSocket server (the Godot editor's MCP bridge). Windows let the
  game server bind the same port, so connections went to the other listener, which is not our server.
- **Fix:** the spike listens on 8910. Before picking a port, check it: `netstat -ano | grep :<port>`.
- **Documented:** [Multiplayer research](../research/multiplayer.md#local-setup).

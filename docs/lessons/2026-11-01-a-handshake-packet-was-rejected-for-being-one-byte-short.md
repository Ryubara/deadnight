# A handshake packet was rejected for being one byte short

2026-11-01

- **Symptom:** the client connected and received snapshots, yet never became a player (id stayed 0).
- **Cause:** the decoder's minimum-length check for WELCOME counted 9 bytes; the packet is 8 (type, version, id, rate,
  4-byte tick). A malformed-packet guard silently dropped every valid welcome.
- **Fix:** derive each minimum length from the layout comment in `protocol.gd`, and print a counter for dropped packets
  while developing. A guard that fails closed hides its own bug.
- **Documented:** [Multiplayer research](../research/multiplayer.md#protocol).

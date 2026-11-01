# The server image failed to import the project

2026-11-01

- **Symptom:** `docker build` printed `Could not create project data directory (res://.godot)`, and the container then
  failed with parse errors on every script that uses a `class_name`.
- **Cause:** `WORKDIR /app` makes a root-owned folder; the non-root user could not create `.godot/` (the import cache
  and the global class list) inside it.
- **Fix:** create `/app` and `chown` it to the game user before the `COPY` and the build-time `--import`.
- **Documented:** `spikes/net/Dockerfile`, [Multiplayer research](../research/multiplayer.md#server-image).

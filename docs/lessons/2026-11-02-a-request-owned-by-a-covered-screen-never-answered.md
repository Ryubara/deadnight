# A request made under a screen the router had covered never got its answer

2026-11-02

- **Saw:** in the browser the lobby screen's Join stayed on "Joining..." for ever and the host's seats never updated,
  while every unit test passed (#515).
- **Cause:** the lobby screen used the `TogetherApi` of Play together, whose `HTTPRequest` nodes are children of that
  screen. The router sets `process_mode` to disabled on a screen another one covers, and a disabled parent does not
  process its `HTTPRequest`, so the request never completed. The tests used fake APIs that answer at once.
- **Fix:** a screen that keeps asking while it is on top takes an API of its own, under itself
  (`TogetherApi.detached(self)`), and says its goodbye through one under the root (`detached(get_tree().root)`). One
  test checks whose child the API is; the browser probe (`tools/web_smoke/lobby.py`) is what proved the flow.
- **Check:** a screen that calls the network is run once in the web build with the real backend before it counts as done.

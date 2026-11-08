# A bot's callout never reached the test, because the seated night dropped what `apply` returned

2026-11-02

- **Symptom:** a bot sent a `say` action, the server accepted it, and no `bot_say` event was ever heard in a
  `SeatedNight` (#229).
- **Cause:** `NightServer.apply` answers an action with its events (the game server broadcasts them);
  `SeatedNight._send` called it and discarded the answer, so a ping's mark or a line only ever existed on a real server.
- **Fix:** the seated night keeps the answers that are everyone's business (`bot_say`, `ping_placed`) and hears them
  with the next step's events, as a broadcast would. A new action that the server answers with an event needs the
  same. The general rule (a stand-in builds and forwards what the game does) is on the kit's
  [Testing a game](https://ryubara.github.io/gdstudio/gamedev/testing/#scenarios) page.
- **Documented:** `game/tests/night/seated_night.gd`.

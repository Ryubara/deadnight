# A host who goes to paste the invite stops polling, and a closed tab never says it left

2026-11-02

- **Symptom:** none yet: caught on paper while designing the lobby (#515), before presence was built. The lobby lists
  who is there from each member's poll; a closed tab sends nothing, so without presence the seat stays until the lobby
  expires (10 minutes), and a host whose tab went to the background to paste the link into a chat would look equally
  gone.
- **Cause:** the web build draws and polls from its frame loop, and a browser stops a hidden tab's frames. "Quiet" is
  therefore the normal state of a player who is elsewhere for a minute, and it looks the same as a closed tab.
- **Fix:** presence from the poll with a minute's grace (`memberAwayMs`), a member dropped only while someone else was
  seen inside that minute (a lobby whose members are all quiet is left to expire, never emptied by the rule), `away`
  shown after 15 s, and a clear message to a player who comes back after being dropped. Tests move an injected clock.
- **Documented:** [the lobby](../design/lobby.md#poll-or-push) and
  [the platform backend](../research/platform-backend.md#the-lobby-before-the-night).

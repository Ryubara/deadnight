# Scoreboard

The scoreboard (issue #472) shows every player in the night with kills, downs, points and, over a link, ping, plus the
round and the night's clock. What it shows is described in [HUD](../design/hud.md#the-scoreboard); this page is where
the numbers come from and what we decided.

## Where each number comes from

| Number | Source | Reaches the HUD by |
| --- | --- | --- |
| Kills | `PlayerState.kills`, counted by `GameRules` on every kill (gun, melee, blast); already there | the `frame`'s `players[id].kills`, and the welcome snapshot |
| Downs | `PlayerState.downs`, counted in `PlayerHealth.down` (a blow or a forced down) | the same |
| Points | `PlayerState.points`; the HUD already follows `points_changed` | events (unchanged) |
| Clock | `GameRules.night_time`, seconds counted while a break or a round runs | the frame's `clock` (whole seconds, so a delta frame carries it once a second) and the snapshot |
| Ping | the client's own last measured round trip, sent in its `PING`, held in `NightServer.pings` | the frame's `players[id].ping`, only for a player with one |
| Round | the HUD's round, as before | events |

Counts travel as whole numbers, not as changes: a frame said twice changes nothing, and a HUD that joins late has the
right numbers from the snapshot. `NightTally` (the challenges) also counts kills per player, from the events a client
hears; the played-night tests use those events as the independent count the server's number is checked against.
It is not the source: it counts on the client, and counts no downs.

## Versions

- `GameRules.SNAPSHOT_VERSION` 9 to 10: a player's `downs` and the rules' `night_time`. Every older snapshot is
  refused as
  `bad_version` (`test_scoreboard_counts.gd` keeps one from version 9).
- `NetWire.VERSION` 4 to 5 (`MIN_VERSION` 5): a `PING` is 7 bytes, the client's last round trip in milliseconds
  (`NetWire.NO_RTT` before the first answer) after its clock. The server cannot measure a round trip itself over TCP
  without an extra message, so the client reports its own; a client that lies can only misprint its own ping.
- Both numbers move often on `main`. Read them at merge time and bump past whatever is there
  (the kit's lesson "Two branches bumped the same snapshot version").

## What we did not do

- **Revives.** `player_revived` names nobody who helped; the round's end revives everyone (see
  [Challenges](challenges.md#learned-while-building)). When a teammate revive exists it is one more count beside downs.
- **Names.** The HUD still says `PLAYER N` for everyone; the backend's display name is on the server (`HostPeer.user_name`)
  and is not replicated. A scoreboard of `PLAYER 1` to `PLAYER 4` works, a scoreboard of names would be better.

## Tests and captures

`test_scoreboard_counts.gd` (rules), `test_night_scoreboard.gd` (a bot's night alone, and a late HUD),
`test_night_scoreboard_online.gd` (two bots and a late joiner over a real socket; the ping round trip),
`test_hud_scoreboard.gd` (input, rows, the fullest board at five canvases), `test_touch_controls.gd` (the button).
Captures: `tests/captures/scoreboard_tour.tscn`, alone and with four, at 1920 x 1080 and 2340 x 1080 with touch.

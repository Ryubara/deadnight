# Revive

Deadnight's rules for being downed and for pulling a teammate back up (#486). The research is in
[Teammate revives](../research/revive.md); the HUD parts are in [HUD](hud.md#revives), the wire in
[Rounds, points and fuel](rounds.md#actions-and-events-the-seam). Every number below is a field of one inspector
resource, `ReviveTuning` (`game/gameplay/rules/revive_tuning.gd`, set in `default_tuning.tres` as `revive`), so a
designer changes it in the editor and the balance simulator, the server and every client read the same table.

## In one screen

- A player is **up**, **downed** or **dead**. Down is zero health. A downed player cannot move, shoot, buy or throw,
  and a clock runs: **bleed-out**. A teammate who **holds Use** beside the body for `revive_seconds` gets them up. If the
  clock reaches zero first, the player is **dead** until the round ends.
- The server decides all of it. A client sends the commands it always sends (move, fire, `use` and `use_held`); the
  server finds who is in reach, counts the hold, runs the clock and says what happened in events and in each frame.
- Both players read the same ring: the reviver on their prompt and over the body, the downed player on their own
  card. The downed player also reads the bleed-out clock, and a teammate reads it over the body.
- **The night ends when every player is down or dead**, as before.
- A downed or dead player at the end of a round gets up for a tenth of their points, as before.
- Revives are counted by the server for the scoreboard's `REVIVES` column.

## The tuning resource

| Field | Value | Meaning |
| --- | --- | --- |
| `bleed_out_seconds` | 45 | Time a downed player has before they are dead, if nobody holds the revive |
| `revive_seconds` | 3.5 | Hold time to pull a player up |
| `reach` | 2.0 m | How near the reviver stands to the body; beyond it the hold breaks |
| `health_fraction` | 0.5 | Share of maximum health a revived player gets up with (a round's end restores all) |
| `reviver_points` | 0 | Points paid to the reviver; 0 ([decided](#decided-2026-11-02-505)) |
| `bleed_stops_while_held` | true | The clock stands still while someone holds the revive |

Why these: the bleed-out sits between the two reference games' clocks, 30 seconds and minutes
([research](../research/revive.md#what-the-games-agree-on-and-where-they-differ)); a round here lasts one to three
minutes, so 45 seconds is "in this round" and not "forever". The hold is about a reload and a half
(`Reload_Rifle` is 2.6 s), long enough to be a choice with zombies near and short enough to try. The balance simulator
used to say 6 seconds and half health with no bleed-out; it reads this table now.

## The states

| State | `downed` | `dead` | `bleed_left` | Can be revived | Counts as down for the night's end |
| --- | --- | --- | --- | --- | --- |
| Up | false | false | 0 | no | no |
| Downed | true | false | seconds left, counting down | yes | yes |
| Dead | true | true | 0 | no | yes |

`downed` stays true for both, so everything that already refuses a downed player (shopping, the chase, the shot) keeps
refusing a dead one. `dead` and `bleed_left` are in the snapshot, so a late joiner and a player coming back read the
same clocks.

```text
   up --blow to zero--> downed --bleed_left <= 0--> dead
    ^                     |                            |
    +---- held revive ----+       round ends: both get up (a tenth of the points)
```

## The hold

- **Start.** `use_held` with a downed, living teammate within `reach` and no other reviver on them. The prompt
  (`use_target`) offers `revive` before a door, a shop or a breach: you cannot buy a door with a friend on the floor.
- **Progress.** Every tick the hold lasts adds the tick to the downed player's progress, kept by the server's
  `ReviveChannel`. At `revive_seconds` it asks the rules for the `revive` action: the player gets up, `player_revived`
  with the `reviver_id`, health back to `health_fraction`.
- **Interrupted** (progress goes back to zero at once) when the reviver:
    - lets go of Use (`released`);
    - moves out of `reach` (`moved`);
    - is downed (by a blow or any other road: `down`);
    - or when the target is revived by other means (a round's end), bleeds out, or leaves.
- **A hit on the reviver does not reset the hold** (Left 4 Dead's rule does); the reviver is exposed instead, and a
  second blow downs them and breaks it. This is [decision 4](#decided-2026-11-02-505).
- **One at a time.** A body with a reviver on it offers nothing to a second player. The server picks the first.

## Bleed-out

`bleed_left` counts down in a round only. While the revive is held and `bleed_stops_while_held`, it does not. When it
reaches zero: `player_died` (cause `bleed_out`), `dead` is true and the body stays. A dead player is not offered a
revive and is not a chase target. The night does not end by a death unless it was the last one up, and then it had
already ended when that player went down.

## Getting up

- **By a teammate:** `player_revived` {`player_id`, `reviver_id`}, `player_healed` with reason `revive`, health
  `max_health * health_fraction`, the regeneration wait restarted. The reviver's `revives` is one more.
- **By the round's end:** `player_revived` {`player_id`, `reviver_id`: -1}, all health, no revive counted for anyone.
  (A dead player comes back the same way: their death lasts for the rest of that round.)

## Events

| Event | Fields | For |
| --- | --- | --- |
| `player_downed` | `player_id`, `cause`, `bearing`, **`bleed_seconds`** | the DOWN card, the clock |
| `revive_started` | `player_id` (the reviver), `target_id` (the downed) | the rings |
| `revive_stopped` | `player_id` (the reviver), `target_id`, `reason` (`released`, `moved`, `down`, `done`) | clears the rings |
| `player_revived` | `player_id`, **`reviver_id`** (-1 for a round's end) | the feed, the voice, the scoreboard |
| `player_died` | `player_id`, `cause` (`bleed_out`) | the feed, the DOWN card turns to DEAD |

The rules' action: `revive` {`player_id` (the reviver), `target_id`}, sent by the server's channel when the hold is
complete; a client never sends it. It is refused as `wrong_phase`, `unknown_player`, `self_revive`, `player_downed` (the
reviver), `target_dead` or `not_downed`. The bleed-out clock takes the ids the channel is holding with each `tick`.

The frame carries, for every player: `bleed` (seconds left, 0 when up or dead), `dead`, `revive` (progress as a
fraction, 0 to 1) and `reviver` (player id, 0 for none), and `reviving` (the id a player is raising now). They are
present for every player always, because a frame after the first only carries fields that changed ([`FrameDelta`](../research/multiplayer.md)).

## What the player sees

- **The downed player** sees the red frame and `DOWN` as before, with the **bleed-out clock** in the health card in
  place of "hold on for a revive" (seconds and a draining bar), and a **ring** over it when a teammate holds the
  revive. When they are dead it says `DEAD  BACK NEXT ROUND`.
- **The reviver** sees `REVIVE <NAME>` on the prompt card with the hold's ring filling while they hold, and the same
  ring over the body.
- **A player on the ground** is offered nothing on the prompt card (the frame's `prompt` is empty for them): they can
  use nothing, and a shop card over a body would lie.
- **Everyone else** sees the body marker (an ally marker with the bleed-out seconds over it) so a teammate across the
  lot knows who is bleeding and for how long, and the ring while someone is reviving.
- **The team box** shows `DOWN` and, once dead, `DEAD`; the portrait dims.
- **The scoreboard** has a `REVIVES` column between downs and points.
- **The feed**: `RUBY REVIVED PAUL` and `PAUL BLED OUT`.
- **The body** lies down in `Downed_Idle` and the reviver kneels in `Revive_Kneel` (#536), driven by the server's
  events (`player_downed`, `player_revived`, `revive_started`, `revive_stopped`) on every screen
  ([decision 8](#decided-2026-11-02-505)). The shoulder camera does not frame a body on the ground yet (#532).

## Bots

The `Autopilot` reads only what a client reads: a downed teammate in the frame, its `bleed` and `reviver`. It revives
when no zombie is within 7 m of the body or of itself (it shoots them first, as it does at any time), walks to the body
and holds Use; it gives up if the clock is shorter than its walk and goes on. It does not revive a body with a reviver
on it. This makes the online and the autopilot tests able to play a revive end to end.

## Decided (2026-11-02, #505)

The maintainer approved all eight as built ("Go for it"). Each is a field of the tuning resource or a small change, so it
can be retuned in the inspector.

1. **Solo self-revive**: none. A lone player who goes down ends the night.
2. **A revive perk or tonic**: none for now; a later tonic (#281) can add one.
3. **Crawl and a sidearm while downed**: neither. The optional `Downed_Crawl` clip (#536) stays unused.
4. **A hit on the reviver** does not reset or slow the hold. A second blow downs them, which breaks it.
5. **Points for the reviver** (`reviver_points`): 0.
6. **Dead players** get up at the round's end.
7. **The clock stops while held** (`bleed_stops_while_held`): on.
8. **A reviver clip**: `Revive_Kneel` (#536).

Values: `bleed_out_seconds` 45, `revive_seconds` 3.5, `reach` 2.0 m, `health_fraction` 0.5.

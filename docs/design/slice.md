# The first playable night

The vertical slice: one night on the drive-in lot, from the main menu's Play to the last player going down, with
the pieces built so far joined by the same wires the multiplayer game will use. It is not the finished game; this
page says what is in, and what is next.

## How it runs

```text
 client (draws, sends)                             server (decides)
 ┌────────────────────────────┐   LoopbackLink   ┌──────────────────────────────────┐
 │ Human controls  ─┐         │  (var_to_bytes)  │ NightServer                      │
 │ or Autopilot ────┴ command ─┼─────────────────►│  GameRules   rounds, points, shop│
 │                            │                  │  CombatServer   weapons          │
 │ ClientState ◄── events ────┼◄─────────────────┤  ZombieSim + Director            │
 │ NightView (zombies, shots, │   events + frame │  player bodies, health           │
 │ numbers, sounds), HUD      │                  │                                  │
 └────────────────────────────┘                  └──────────────────────────────────┘
```

- One physics tick (`Night.tick`): the link delivers what was sent last tick; the server steps (moves the players
  from their latest `NightCommand`, the zombies, the rules clock, the weapons, health, then fires, reloads, uses);
  its events and one `frame` go back; the client reads its controls (or the autopilot decides) and sends the next
  command.
- A `NightCommand` is a `PlayerCommand` plus the trigger, reload, use and the camera ray. A person and the bot
  produce exactly this; the server cannot tell them apart. The player is the connection's, never what the message
  says. A pressed edge (use, reload, swap, jump) is kept until a step uses it, even when a newer command arrives in
  the same tick, and a command that is not renewed for `NightTuning.command_ticks` steps (30, half a second at the
  60 Hz step) is replaced by one that stands still, keeps the view angles and releases the trigger.
- A `frame` is the whole picture a client or a HUD draws from: phase, round, zombies left, fuel, open doors, the
  zombies as `ZombieCodec` bytes, and for each player their position, health, weapon, ammunition, points and the
  prompt for what `use` would do. The HUD binds to `ClientState.event_received` and these frames
  (`NightHudBinding`, below).
- All state is in the server: the rules own points, rounds and the zombies' health; the combat server owns ammunition
  and who was hit; the night server owns where the players stand and their health. The client keeps only what it has
  heard.

## What is in

| Part | Where | Notes |
| --- | --- | --- |
| Main menu Play starts the night; Esc pauses; Back to the menu | `ui/screens/night_screen.gd`, `main_menu.gd` | the pause freezes the clock and frees the mouse |
| Move, look, sprint, jump, shoot, reload | `gameplay/night/` | `fire`, `reload`, `interact`, `pause` are input actions (mouse, R, E, Esc; gamepad right trigger, X, Y, Start), each defined once and none sharing a pad button with another gameplay action (`tests/ui/test_input_actions.gd`); B crouches and neither pauses nor leaves the night |
| Zombies spawn from the rules, chase through the navigation mesh, strike | `gameplay/zombies/` | spawns only in the field and in areas whose door is bought |
| Player health: 100, regenerates after 5 s unhurt, a down at zero | `GameRules` (`HealthTuning`); `NightServer` sends a zombie's swing as a `blow` | all down ends the night |
| Rounds, break, points for hits and kills, the round bonus | `gameplay/rules/` | unchanged |
| Doors: `interact` next to a slab buys the door; `LotDoors` frees its slabs, `DoorNavigation` rebakes the mesh, its area joins the spawns | `NightWorld` (binds the lot to the rules), `NightServer` | one path, the lot's own ([Doors](../research/zombies.md#doors)); the prompt shows the price |
| Boards at the fence breaches: the dead tear them off, `interact` from the field side puts one back for the rules' repair points | `Barricade`, `NightWorld`, `NightServer`, `ZombieSim` | [the fence's boards](rounds.md#the-fences-boards); the prompt shows only at a breach with a board down |
| The shop spots: the shotgun and the rifle on walls, the prize crane, ammunition lockers; the crowbar is always carried, `swap` changes the weapon in hand | `NightServer` (`use_target`, `buy`), `NightWorld.shop_spots` | the supply drop is gone: rounds are bought ([the lot](map.md#shop-spots), [ammunition](rounds.md#ammunition)) |
| The lamps follow the generator: a circuit off or a dry tank darkens its lamps and posts, a failing tank flickers them, and the dead are 25% faster on ground no lit circuit lights | `LotLamps`, `NightView`, `NightWorld.is_lit` | [the lot's lamps](map.md#which-lamps-hang-on-which-circuit) |
| Sound: shots, reloads, dry fire, round stings | `NightView` | through the `Audio` autoload |
| The HUD: round, points, health, ammunition, the prompt at a door or breach, the party, the generator | `NightHudBinding`, `ui/hud/` | below |
| The autopilot | `gameplay/night/autopilot.gd` | below |
| Server and client in one process over the loopback link | `Night` | the same code runs 2-4 players next |

## The HUD

`Night.hud` (set before `start`) is fed by `NightHudBinding`, a client-side class that reads only
`ClientState.event_received`: the rules' events go to `HudState.apply_event` as they are (round, points, party,
fuel, purchases, game over, and the player's health), and each `frame` sets what the rules do not announce, which way
the local player faces, the held weapon's ammunition and the prompt (`use_target`: a door's name and price, or a
breach). Health is the rules' (`player_added`, `player_hurt` with the blow's `bearing`, `player_healed`,
`player_downed`); the frame's `facing` turns a bearing into the damage arc. The server's own `player_damaged` (with
`from` and the knockback) stays for the player's motion. Weapons' events are not forwarded. The night screen and the
autopilot capture each put a `Hud` in their own tree and hand it to the night; the HUD never reads a game object.
Ammunition moves into the weapons' events under #133; only the binding changes then.

## The autopilot

A bot that plays the night through `NightCommand`s. It sees only what a client sees: its own position, the zombies
of the latest frame, its points and the prompt, plus the level's navigation mesh and a ray test against the walls.
It backs away from the nearest zombie inside 7 m (sprinting), shoots the nearest zombie in range and in the clear
(from the camera and from the barrel, the third-person corner problem), reloads on an empty magazine, walks to the
next door when its points cover the price and buys it, goes to the nearest broken breach in a break and puts
the boards back, and puts one back at a breach it stands at when nothing is in sight. It also throws the breaker of an
area it has bought (the dead spawn there; they are faster off lit ground) and puts the extra circuits out when the
tank runs low ([map](map.md#the-breaker-posts)); `tests/night/test_autopilot_switches.gd` checks the rule on frames
and the bot doing it in a night. When the tank is at the low line and it can pay for a can it walks to the nearest
open can stand and buys until the tank is back above 40% ([map](map.md#the-fuel-cans),
`tests/night/test_autopilot_fuel.gd`).

Three traps cost time while it was written. Its sight check is a `Callable` of a `WorldProbe`, and a `Callable` does not
keep a `RefCounted` alive: `Night` holds the probe in `_sight`, because one made from a temporary object was freed at
once and silently answered "clear". A shot leaves the barrel, so `Autopilot._clear` tests the line from the eye and from
the barrel. And a faster run is more fixed ticks per physics frame (`Night.ticks_per_frame`), never `Engine.time_scale`,
which scales the step each tick gets and plays a different night. Each is in [lessons](../lessons.md).

`tests/night/test_autopilot_night.gd` runs it headless in GdUnit4 (so in CI) for three rounds with a cheaper first
door, and asserts the night is not over, three rounds started, zombies killed, points earned **and** spent, and a
door open, with a HUD on the night that must show the same round and points, have offered the door by name and
price before the purchase, and listed the purchase when it happened. `tests/captures/autopilot_night.tscn` plays it
for captures and prints a report (`-- --rounds=5 --speed=30`, `--trace`, `--log`).

## What is next

Each of these is an issue.

- **Characters** (#90): the player model carries no weapon in hand yet; hit and death reactions.
- **Grenades** (#99) and **boss nights** (#97) join through `NightServer` and the rules.
- **Real transport.** Done for one machine (#302, [Testing multiplayer](../research/testing-multiplayer.md)): the night
  runs on a headless `NightHost` over WebSocket, clients draw the others as avatars and follow the doors from the
  frames. What is left: the player bodies on the server still have models (#153), Railway and Discord.
- **Tonics**, the re-cut. (A breaker post for each circuit is in:
  the lamps follow `circuit_changed` and the tank, and a player or the bot throws the switch.)
- **Revive** by a teammate. (The boards at the breaches are in; their sounds are the audio's next.)
- **Performance** of the server tick in late rounds (profile with `autopilot_night.tscn --speed`).

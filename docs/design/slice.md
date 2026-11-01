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
 │ numbers, sounds), readout  │                  │                                  │
 └────────────────────────────┘                  └──────────────────────────────────┘
```

- One physics tick (`Night.tick`): the link delivers what was sent last tick; the server steps (moves the players
  from their latest `NightCommand`, the zombies, the rules clock, the weapons, health, then fires, reloads, uses);
  its events and one `frame` go back; the client reads its controls (or the autopilot decides) and sends the next
  command.
- A `NightCommand` is a `PlayerCommand` plus the trigger, reload, use and the camera ray. A person and the bot
  produce exactly this; the server cannot tell them apart.
- A `frame` is the whole picture a client or a HUD draws from: phase, round, zombies left, fuel, open doors, the
  zombies as `ZombieCodec` bytes, and for each player their position, health, weapon, ammunition, points and the
  prompt for what `use` would do. The HUD (#89) binds to `ClientState.event_received` and these frames.
- All state is in the server: the rules own points, rounds and the zombies' health; the combat server owns ammunition
  and who was hit; the night server owns where the players stand and their health. The client keeps only what it has
  heard.

## What is in

| Part | Where | Notes |
| --- | --- | --- |
| Main menu Play starts the night; Esc pauses; Back to the menu | `ui/screens/night_screen.gd`, `main_menu.gd` | the pause freezes the clock and frees the mouse |
| Move, look, sprint, jump, shoot, reload | `gameplay/night/` | `fire`, `reload`, `interact` are input actions (mouse, R, E; gamepad right trigger, X, Y) |
| Zombies spawn from the rules, chase through the navigation mesh, strike | `gameplay/zombies/` | spawns only in the field and in areas whose door is bought |
| Player health: 100, regenerates after 5 s unhurt, a down at zero | `NightServer`, `NightTuning` | all down ends the night |
| Rounds, break, points for hits and kills, the round bonus | `gameplay/rules/` | unchanged |
| Doors: `interact` next to a slab buys the door, its slabs go, the navigation mesh is rebuilt, its area joins the spawns | `NightWorld`, `NightServer` | the prompt shows the price |
| Repair: `interact` at a fence breach pays the rules' repair points | `NightServer` | no boards are drawn yet |
| A supply drop at the end of each round refills ammunition | `NightServer._resupply` | stands in for an ammunition shop |
| Sound: shots, reloads, dry fire, round stings | `NightView` | through the `Audio` autoload |
| Debug readout of round, points, health, ammunition, prompt | `NightReadout` | replaced by the HUD |
| The autopilot | `gameplay/night/autopilot.gd` | below |
| Server and client in one process over the loopback link | `Night` | the same code runs 2-4 players next |

## The autopilot

A bot that plays the night through `NightCommand`s. It sees only what a client sees: its own position, the zombies
of the latest frame, its points and the prompt, plus the level's navigation mesh and a ray test against the walls.
It backs away from the nearest zombie inside 7 m (sprinting), shoots the nearest zombie in range and in the clear
(from the camera and from the barrel, the third-person corner problem), reloads on an empty magazine, walks to the
next door when its points cover the price and buys it, and puts a board back at a breach when nothing is in sight.

`tests/night/test_autopilot_night.gd` runs it headless in GdUnit4 (so in CI) for three rounds with a cheaper first
door, and asserts the night is not over, three rounds started, zombies killed, points earned **and** spent, and a
door open. `tests/captures/autopilot_night.tscn` plays it for captures and prints a report
(`-- --rounds=5 --speed=30`, `--trace`, `--log`).

## What is next

Each of these is an issue.

- **HUD** (#89) in place of the readout, binding to `ClientState`.
- **Characters** (#90): the player model carries no weapon in hand yet; hit and death reactions.
- **Grenades** (#99) and **boss nights** (#97) join through `NightServer` and the rules.
- **Real transport.** `LoopbackLink` becomes the network protocol; the player bodies split into server bodies and
  drawn avatars, and the doors' look follows the `door_opened` event instead of the shared scene.
- **Player health in the rules.** It lives in `NightServer` for now; it belongs beside the downed state in
  `GameRules`, with its snapshot.
- **Ammunition, weapons and the crane in the shop**, tonics, the generator and its circuits (the lamps do not yet
  follow `circuit_changed`), the re-cut.
- **Barricades** to repair, and revive by a teammate.
- **Performance** of the server tick in late rounds (profile with `autopilot_night.tscn --speed`).

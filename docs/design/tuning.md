# Tuning in the editor

For someone who opens the project in Godot and wants to change how the game plays: which scene is which, how to play
it from the editor, which file holds which number, and which tests tell you what a change broke. Every command here
was run against `main` on 2026-11-02 (Godot 4.7.2); what could not be run is marked.

!!! note "Your edits reach the game through a pull request"
    The editor changes files in your checkout, and only the checkout. The game that other players and the web build
    run is made from `main`: a changed `.tres` or script goes live when a pull request with it merges (CI runs the
    tests and the balance gate first). Nothing you save in the editor changes the live game by itself.

## Play a night now: `dev/play_night.tscn`

Open `game/dev/play_night.tscn` and press **F6**: a solo night starts at once, with no menu, on the lot, with the
HUD. Before you press it, select the `PlayNight` node and set what you want in the inspector:

![The PlayNight node in the inspector](play-night-inspector.png)

| Option | Does |
| --- | --- |
| Start Round | The round to start in (1 to 60). Round 7 starts at once with round 7's zombies. |
| Seed Value | The night's dice (default `Night.SEED`, 1958). |
| Autopilot | The bot plays, seen over its shoulder: watch what a change does. |
| Skip Intro | Skip the break before round 1 (on). Off waits it out. |
| Warm Up | Load and draw everything once behind the loading screen, as the game does (on). Off starts faster but the first shots hitch. |
| Rules Tuning | Which `RulesTuning` `.tres` the night plays with (default `default_tuning.tres`). Point it at a copy to try a variant. |
| Starting Points | Points to start with; -1 keeps the tuning's. |
| God Mode | Health is topped up every tick. |
| Infinite Ammo | Every carried gun is refilled every tick. |

The scene copies the tuning before it applies an option, so no option ever edits a `.tres`. The player's own numbers
(`PlayerTuning`, weapons, grenades) are the `.tres` files in the table below: edit one, press F6 again. It is not part
of the shipped game (the menu's Play is `ui/screens/night_screen.tscn`), and `tests/dev/test_play_night.gd` starts it
headless and checks each option. It plays from the editor with the real mouse and keys; the autopilot option needs
neither.

## Which scene is which

The entry scene is `res://main.tscn`; it puts `ui/screens/main_menu.tscn` on the router, whose Play starts
`ui/screens/night_screen.tscn`, which builds the night on `world/drive_in_greybox.tscn`. Every scene, what it is for
and what loads it are in [Scenes: which is which](scenes.md).

## Play from the editor

- **A night, straight away: F6 on `dev/play_night.tscn`** (above).
- **The whole game: F5** (Run Project) opens `main.tscn`. Click Play (it takes about half a second for the items to
  appear). You are in the night, alone, on the seed `Night.SEED` (1958). Esc pauses; "Back to the menu" leaves.
- **F6 on `night_screen.tscn` does not start a night.** The screen starts it when the router *enters* it (its
  `screen_enter`), and F6 only instances the scene. You get the loading card and nothing else (checked). Go through
  the menu, or use `dev/play_night.tscn`.
- **Movement and camera only: F6 on `world/test_room.tscn`.** Real keys and mouse (WASD,
  mouse, Shift sprints, C crouches, Space jumps).
  The `Player` node's `Tuning` slot holds `player_tuning_default.tres`: change a value, press F6 again.
- **Weapons and grenades:** F6 on `weapon_range.tscn` or `grenade_range.tscn`; the demo runs on its own.
- **A night played by the bot, to see what a change does to the numbers:** F6 on
  `tests/captures/autopilot_night.tscn`. It takes command-line options after `--`
  (`--rounds=N`, `--speed=N` ticks a frame, `--seed=N`, `--seconds=S`, `--log`, `--fast`, `--cheap`, `--shoulder`, in the
  script's header), and prints a `REPORT` line. From a shell, headless (about a minute for three rounds):

  ```text
  godot --headless --path game res://tests/captures/autopilot_night.tscn -- --rounds=3 --speed=40
  ```

  On `main` that prints `REPORT ticks=11665 round=3 kills=16 shots=55 earned=1416 spent=1200 doors=2 damage_taken=0
  over=false`. A change that is meant to be neutral leaves the line as it is.
- **Start flags** (`core/main.gd`, `net/net_args.gd`), given after `--` on the command line (in the editor: Debug >
  Customize Run Instances, the main instance's arguments; not tried there, check that the game sees them):

  | Flag | Does |
  | --- | --- |
  | `--server [--port N] [--seed N]` | Runs a game server instead of the game (headless, no menu): checked, it prints `listening`. It loads the same `default_tuning.tres` as your checkout. |
  | `--connect [ws://host:port]` | Menu skipped, straight into the night of that server. |
  | `--bot` | With `--connect`: the autopilot plays your seat. |
  | `--look N` or `--look seed:N` | Wear preset N, or a random look, instead of the saved one. |
  | `--report [seconds]` | Print what the joined night looks like from here. |

  Your own options (volume, mouse sensitivity, shake) are saved by the `Settings` autoload in `user://settings.cfg`
  (Project > Open User Data Folder); they are the player's, not tuning.

Press F5 or F6 with a mouse in your hand: the night captures the mouse while you play (Esc frees it).

## The tuning resources

A game developer's numbers live in resources, `.tres` files with an exported script, so the inspector edits them. Open
one by double-clicking it in the FileSystem dock; each `@export_group` is a section, and the `##` comment above each
number is its tooltip. Save with Ctrl+S. A number the `.tres` does not mention falls back to the script's default,
which is what the inspector shows with no "revert" arrow; the file wins when it has the number.

| Resource | File | What it controls | Where it is loaded |
| --- | --- | --- | --- |
| `RulesTuning` (parts below) | `gameplay/rules/default_tuning.tres` | The whole rules table: one resource, nine parts | `GameRules.DEFAULT_TUNING_PATH`, by the night's server (`GameRules`), by the client for HUD numbers (`Night`), the balance simulator and the tests |
| `RoundTuning` | in `default_tuning.tres` (`rounds`) | How a round grows: zombie count, health, speed, spawn pace, break length, how the night darkens | the rules, the zombie simulation |
| `EconomyTuning`, `ShopItem` | `economy` | Points per hit and kill; every shop item's price, requirement and pool | the rules, the shop |
| `FuelTuning` | `fuel` | Generator tank, drain per circuit, start state | the rules, the lights |
| `ZombieRoster`, `ZombieType` | `roster` | Each type of the dead: health and speed multipliers, attack, pay, from which round | the rules, the zombie spawner |
| `SpecialTuning`, `SpecialRound` | `specials` | Which rounds are special (boss, one type only) and their rewards | the rules |
| `ExplosiveTuning` | `explosives` | Grenades carried, blast pay, when a blast cripples | the rules |
| `BarricadeTuning` | `barricades` | Boards per breach, seconds a zombie takes to tear one | the rules, the zombies |
| `HealthTuning` | `health` | The health bar and how fast it mends | the rules |
| `CraneTuning` | `crane` | The prize crane's timing and its chance to break down | the rules (`crane_play.gd`), `crane_view.gd` |
| `PlayerTuning` | `gameplay/player/player_tuning_default.tres` | How the player feels: speeds, acceleration, jump, crouch, step up, hip fire, camera framing and springs, shake, sprint sway (15 groups) | `Player.tuning` (the export on the `Player` node of `player.tscn`, `test_room.tscn`), remote avatars, the touch look and the camera probe |
| `NightTuning` | `gameplay/night/night_tuning_default.tres` | What a player starts with (gun, melee), how far a hand reaches (doors, boards, fuel), the repair and switch intervals, grenade release times, the muzzle, how long a command lasts, the bot's spectator camera | `NightTuning.shipped()`: the night (`Night.night_tuning`, the server and the client), the tests |
| `ZombieTuning` | `gameplay/zombies/zombie_tuning_default.tres` | How a zombie behaves: the crowd cap, how often it re-plans, lure rules, separation and turn rate, the fence stop, the swing (reach, windup, damage), emerging, staggers, the boss's entrance and stagger, the blast push | `ZombieTuning.shipped()`: the simulation (`ZombieSim`), the client's horde, the balance simulator, the tests |
| `SoundDef` in a `SoundBank` | `core/audio/banks/<family>.tres` (ui, weapons, steps, zombies, world, grenades, stings, beds: 97 sounds) | One sound: its files, bus, level, pitch spread, voice-budget group and priority, cooldown, 3D reach, near cap, rear cue, duck | `SoundCatalog.BANKS`, loaded by `SoundCatalog.get_def` (the `Audio` autoload, the night's sounds, the tests) |
| `SoundMix` | `core/audio/sound_mix_default.tres` | How many voices each group may hold; the soldier's voice level, own-voice drop, reach | `SoundCatalog.mix()`, `Audio` (the voice budget), `SoldierVoice` |
| `AimAssistTuning` | `gameplay/player/aim_assist_tuning_default.tres` | The touch aim assist: reach, capture, friction, magnetism, auto-fire, the simulator's gain | `TouchAimAssist.tuning` (the night), the balance simulator, the tests |
| `ShotFxTuning` | `gameplay/weapons/fx/shot_fx_tuning_default.tres` | How a shot looks: the wall spark, dust and mark, the blood puff, the flare in flight (core, halo, flicker, trail), the lure on the ground (glow, embers) | `ImpactFx`, `ProjectileView`, `LureView` |
| `WeaponDef` | `gameplay/weapons/defs/<id>.tres` (pistol, smg, shotgun, rifle, flare_gun, crowbar) | One weapon: damage, rate, magazine, reload, spread, recoil and shake, projectile, melee sweep | `WeaponCatalog` (the server and the client), the simulator |
| `GrenadeDef` | `gameplay/grenades/defs/frag.tres` | The grenade: fuse, throw, bounces, blast radius and damage | `NightServer.GRENADE_DEF` |
| `WeaponHold` | `gameplay/player/holds/<id>.tres` | How a weapon sits on the Soldier: size, rest pose, support hand | `PlayerAnimation` |
| Range scenes' own exports | the root node of `world/weapon_range/weapon_range.tscn` and `world/grenade_range/grenade_range.tscn` | The range cameras (position, target, field of view), the barrel, the demo throw | the scene itself: select the root node |
| `ReticleStyle` | `ui/hud/reticle_style.tres` | The centre reticle's ticks, gap and dot | the `Hud` node's `reticle_style` |
| `UITokens` | `ui/skin/deadnight_tokens.tres` | The skin: colours, type sizes, spacing | `project.godot` (`[gds_ui] tokens`) |
| Audio buses | `default_bus_layout.tres` | Bus volumes (Music, Effects, UI, Voice, Ambience) | the project (`Audio` autoload) |

### What moved in #415 and what stays in code

Every number a designer would tune that was a `const` in a script is now an export of a resource above, with a
group, a range and a unit, and a `##` tooltip. Issue [#415](https://github.com/Ryubara/deadnight/issues/415)'s
audit, area by area:

| Area | Moved | Left in code, and why |
| --- | --- | --- |
| Zombies | `ZombieTuning` (all 28 numbers, now a `.tres` the simulation loads) | per-type numbers are already `ZombieType` in `default_tuning.tres`; `ZombieRig`, `AnimationThrottle`: animation and rendering cost, not design |
| Sound | every `SoundDef` (97), the group limits, the soldier voice's level and reach | the soldier's per-moment table (`SoldierVoiceCatalog.EVENTS`: takes, priority, cooldown, chance) is tied to the generated files; `UI_CUES` (ids); the pitch rule `ArmsCatalog.FIREARM_PITCH_SEMITONES` (checked by a test, no longer builds anything); mix helpers in `audio_service.gd`, `footstep_sounds.gd`, `world_sounds.gd`, `weapon_sounds.gd` (follow-up) |
| Weapons | the look of a shot, a flare and a lure (`ShotFxTuning`) | `WeaponDef` and `GrenadeDef` were already resources; `ImpactFx.MAX_ACTIVE` (the pool's size) and `MAX_SIZE` (the bound the tests check) |
| Camera | the range scenes' cameras (exports on their root nodes) | the player's camera is `PlayerTuning`; the bot's camera is `NightTuning` (#465); the loading warm-up's hidden stage camera (`NightWarmup.SHOT_FOV`, near and far shot) only guarantees shaders compile, it is not a feel number |
| Touch | `AimAssistTuning` (a `.tres` now) | the finger's look gain and sprint thresholds (`TouchLook`, `TouchControls`, touch pull requests in flight: tests use their names); button and stick layout (`TouchLayout`: layout arithmetic) |
| HUD, menu | nothing | sizes and colours are the skin (`UITokens`) and `HudStyle` layout arithmetic |

What stays in code on purpose: the network protocol and its limits (`net/`), layout arithmetic, ids and node names,
and constants that only a test uses.

## Tests that pin the defaults

Most tests read the resource (`RulesFixture.tuning()` loads `default_tuning.tres`), so a retune does not break them.
A few pin numbers from the design on purpose; those are what fails after a change, and the failure names the number.
Changing `RoundTuning.count_base` from 4 to 5 and running the round suite (checked) fails exactly:

```text
test_round_tuning.gd > test_zombie_count_starts_at_four_for_one_player
test_round_tuning.gd > test_zombie_count_matches_the_documented_table      (10, 21, 54 become 11, ..., 22)
```

Every tuning resource has one more pin, `tests/tuning/test_tuning_defaults.gd`: each file must hold the numbers the
game had as constants before it was a resource, and each exported property must be in the table
(`tests/tuning/default_values.gd`, and `sound_defaults.json` for the 97 sounds). It fails with the property's name.
When you retune on purpose, change the number in that table too: it is the one place that says what shipped.

| You change | Run | What it holds |
| --- | --- | --- |
| Rounds, economy, fuel, zombie types, specials, health | `tests/rules` | The documented tables (`test_round_tuning.gd`), shop and fuel rules, the snapshot's fingerprint of the table (`test_wire.gd`; computed from the table, so a retune moves both sides together), and the **balance gate** (`test_balance_targets.gd`): 60 seeded nights in five cells must land inside `BalanceTargets`' ranges (`docs/design/rounds.md`, "Balance targets"). A change that is fine for you but moves a range fails here by design: say so in the pull request. |
| Zombie behaviour | `tests/zombies`, `tests/tuning` | Movement, attacks, types, the boss, the director; the shipped numbers |
| Player feel, camera | `tests/player`, `tests/world/test_camera_probe_tuning.gd` | Speeds against the zombies', the camera's pull-back, the shake's peak ("subtle" is a number), hip fire, the 8-direction movement matrix |
| Weapons, grenades | `tests/weapons`, `tests/grenades` | Damage per zone, ammo and reload, the shot's look, the blast |
| Sounds | `tests/core`, `tests/tuning` | The catalogue, the budget and the mix levels; the shipped value of every sound |
| The night's hands and the lot | `tests/night`, `tests/world` | Reach, repair, fuel and switch spots |

Run one suite or folder headless, with the pinned Godot (the flag is needed because GdUnit4 refuses headless
otherwise); the whole suite is what CI runs, `-a res://tests`:

```text
godot --headless --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/rules -c --ignoreHeadlessMode
```

`game/addons/gdUnit4` is not committed: a workspace fetches it (`gds workspace init --fetch gdunit4`). The editor
needs it too if you want the GdUnit panel.

## Checking a change

1. Save the resource, run the scene you changed (F5, or F6 on the test room).
2. Run the tests of its area (the table above), then the whole suite before a pull request.
3. A change that is meant to be neutral: the autopilot line above is unchanged.
4. Commit on a branch and open a pull request; the checks and a maintainer decide, `main` takes no direct pushes.

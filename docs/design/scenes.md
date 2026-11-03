# Scenes: which is which

For someone who opens the project in Godot and asks "which scene is the game, and what loads the night?". Every
route here was read from the code on 2026-11-02; the numbers you tune are in [Tuning in the editor](tuning.md).

## The short answer

- **The entry scene** is `res://main.tscn` (`run/main_scene` in `project.godot`, so F5 and the exported game start
  it). It holds only the film overlay and the script `core/main.gd`.
- **`main.gd` puts the main menu on the router** (`ui/screens/main_menu.tscn`). Nothing else loads at start.
- **The menu's Play starts the night: `ui/screens/night_screen.tscn`.** Its script builds a `Night`
  (`gameplay/night/night.gd`), which builds the lot from **`world/drive_in_greybox.tscn`** and puts the player
  (`gameplay/player/player.tscn`) in it. So the scene that *loads the main game* is `night_screen.tscn`, and the
  scene that *is the map* is `drive_in_greybox.tscn`.
- **To play a night from the editor without the menu:** F6 on `dev/play_night.tscn`.

## The route

```text
main.tscn                          entry; core/main.gd
  UIRouter (an autoload) holds the stack of screens
  ui/screens/main_menu.tscn        the first screen: the soldier on a live lot, a tab shell over it
    Play tab    "Solo"          -> ui/screens/night_screen.tscn       the night, HUD over it
                "Play together" -> ui/screens/together_screen.tscn    quick join, create, join by code
                                      -> ui/screens/lobby_screen.tscn the lobby: code, seats, Start
                                      -> night_screen.tscn            (or join_screen.tscn with --dev)
    Loadout tab                 -> ui/screens/customize_screen.tscn   the wardrobe
    More tab    Settings        -> ui/screens/settings_screen.tscn
                Credits         -> ui/screens/credits_screen.tscn
```

Start flags change the route (`core/main.gd`): `--server` runs a game server and no menu, `--connect` goes
straight to the night of a server, `--room CODE` opens Play together on that code, `--stage` opens only the menu's
3D stage (`ui/screens/menu_stage_screen.tscn`, for frame-time runs). The Autoloads are `UIRouter`, `Settings`
(`core/settings.gd`) and `Audio` (`core/audio/audio_service.gd`).

## The main scenes and what each is for

| Scene | What it is | Loaded by |
| --- | --- | --- |
| `main.tscn` | The root: film overlay, `core/main.gd` | the project (`run/main_scene`) |
| `ui/screens/main_menu.tscn` | The menu: `MenuShell` (tabs Play, Loadout, Shop, Challenges, More) over `MenuStage`, a cheap live lot built in code | `main.gd` |
| `ui/screens/night_screen.tscn` | **The game.** A bare `Control`; when the router enters it, `NightScreen` builds `Night`, the HUD and the touch controls and starts the night. Esc, Start or the touch pause button open its menu (Resume, Settings, Leave night); the result is its overlay | the Play screen (the menu's Solo), `together_screen`, `join_screen`, `--connect` |
| `world/drive_in_greybox.tscn` | **The map**: the drive-in lot with lamps, doors, boards, breaker switches, fuel spots, spawn markers and navigation meshes. The rules and `NightWorld` find its nodes by name and by `meta` (`shop_id`, `barricade_id`): renaming one breaks the game and `tests/world/test_drive_in_greybox.gd` | `NightWorld` (`gameplay/night/night_world.gd`) |
| `world/smallmap/smallmap_greybox.tscn` | The second map's greybox (#631), written by `tools/world/build_smallmap_greybox.py`: rooms, links (`Doors`), window sockets, spawns, camera probes ([the second map](smallmap.md)). Its zombie meshes are `world/smallmap/smallmap_navmeshes.res` | nothing yet: the map picker (#624) |
| `gameplay/player/player.tscn` | The player's body: camera rig, collision, the soldier model. One per player, local and remote | `NightWorld`, `world/test_room.tscn` |
| `ui/hud/hud.tscn` | The HUD: health, ammo, round, points, markers, feed, prompts | `NightScreen` |
| `ui/screens/together_screen.tscn`, `lobby_screen.tscn`, `join_screen.tscn` | Play with others: quick join, create a night or join by code; the lobby (code, seats, the host's Start) before the night; type a server address (`--dev`) | the menu, `main.gd` flags |
| `ui/screens/customize_screen.tscn` | The wardrobe: pick a look, saved to the profile | the Loadout tab |
| `ui/screens/settings_screen.tscn`, `credits_screen.tscn` | Settings (the player's options) and the credits | the More tab |
| `ui/screens/menu_stage_screen.tscn` | The menu's stage alone, for frame-time runs | `main.gd --stage` |
| `ui/screens/play_screen.tscn` | Solo's step before the night: the match settings (`MatchSettingsPanel`, the room host's panel) and Start the night | the menu's Solo |

The parts of the lot are scenes under `world/drive_in/` (`props/`, `fixtures/`, one scene per kind of thing: cars,
lamp posts, the marquee, boards, the circuit switch, the neon sign, the wreck), and the two machines under
`world/machines/` (the re-cut bench, the soda fountain). `world/drive_in/capture_rig.tscn` is a camera the captures
place for stills of the lot.

## Scenes you press F6 on (tools, not the game)

| Scene | What it is |
| --- | --- |
| `dev/play_night.tscn` | A solo night at once, no menu. Its inspector sets the round, the seed, the bot, god mode and more ([Tuning in the editor](tuning.md#play-a-night-now-devplay_nighttscn)) |
| `world/test_room.tscn` | A grey room with a `Player` you move with the real keys and mouse. The place to tune movement and the camera. No zombies, no rules, no HUD |
| `world/weapon_range/weapon_range.tscn` | A scripted demo fires every weapon at zombie dummies. Plays itself. Its root node's inspector has the camera and the barrel |
| `world/grenade_range/grenade_range.tscn` | The same for the grenade: cook, throw, bounce, blast. Its inspector has the camera and the demo throw |
| `ui/specimens/typography_specimen.tscn` | The skin's type specimen (needs font files kept outside the repository) |
| `tools/bench/audio_gun_bench.tscn`, `tools/web_audio_load/web_audio_load.tscn` | Audio measurement rigs (the gun levels; the browser's voice load, which `tools/web_smoke/audio_load.py` drives) |
| `tests/captures/*.tscn`, `tests/tours/*.tscn`, `tests/player/capture_*.tscn`, `tests/art/capture_*.tscn` | Scripted captures and tours (Movie Maker): they play the game with the real input actions and write frames. Not shipped. `tests/captures/autopilot_night.tscn` plays a night with the bot |

## Where the night is built (for a developer)

`NightScreen._ready` makes a `Night`; `Night.start` makes `NightServer` (the rules, the zombie simulation, the
weapons: authority) and a client (`NightView`: the lot, the avatars, the zombies, the effects) joined by a loopback
link, so a solo night is the same code as a night on a server. `NightWorld` instances the lot and the players;
`NightHudBinding` feeds the HUD from the night's events. Numbers each part reads are listed in
[Tuning in the editor](tuning.md#the-tuning-resources).

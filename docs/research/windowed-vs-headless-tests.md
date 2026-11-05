# Where a windowed GdUnit run and a headless one see different games

CI runs every GdUnit suite headless (`--headless ... --ignoreHeadlessMode`); an agent that runs a suite in a window
(`gds godot -- ... GdUnitCmdTool.gd -a <suite>`) can see it fail when CI is green. Three UI suites did on `main`
(#1187), each for a reason that is the game's own switch, not the engine:

| What differs | Headless | Windowed | Where |
| --- | --- | --- | --- |
| The menu shell's phone layout | never: a headless window is 64 pixels, so `MenuShell._is_compact` is `false` | on when the window's short side is under 500 pixels (`MenuScale.is_phone`) | `ui/menu/menu_shell.gd` |
| The helicopter drop that opens a person's night (#1057) | off (`NightScreen.arrival_enabled`) | on: the look is held, the touch layer and the HUD are the show's, the reticle is away until it ends | `ui/screens/night_screen.gd` |
| The loading screen (`NightScreen.warm_up_enabled`) | off | on | `ui/screens/night_screen.gd` |

What each did:

- **`test_hover_room`, the Plate button.** The suite's "phone" canvas set the window to 844 x 390 and the factor to 2,
  but a headless shell still built the desktop layout, so CI never measured the phone's Loadout tab. In a window it is
  the phone's: the strip that holds the Plate button is 99 units high, the button was 79 (the theme's size 34 text),
  and its ring and hover growth made 100.4. The button is now at the body size on a phone (68 high), and the suite builds
  `MenuShell` with `phone_mode` from `MenuScale.is_phone(window size)`, as `UiFitRun` does, and asserts the phone
  canvas saw buttons at all. The same suite headless failed on the old game with the same line before the fix.
- **`test_bot_wheel_input` and `test_night_crosshair`.** A window plays the drop on the first night, so the suites'
  first running frame is the show's: no reticle, no look, no touch. They now start a night with no drop due, as
  `--noarrival` and every headless run do, and the crosshair suite also runs the drop and asserts the reticle is away
  under it and back when it ends (solo and joined, a Resume under it, a drop that ends under the pause card). The game
  was right: a player has a reticle from the moment the drop ends.

## Not fixed here

`test_night_mouse_look` (3 of 4 fail windowed, 1 with the drop off), `test_night_screen` (3 of 8, 1 with the drop off)
and `test_night_menu` (12 of 13 and 7 errors) also fail windowed on `main` and pass headless; the drop explains most
but not all of them. They are their own issue.

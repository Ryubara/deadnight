# The menu's tab shell

The tab bar and the five panels over the [live stage](menu-stage.md) (issue #397; the design and the picked direction,
"the program", are in [Main menu](main-menu.md#the-rework-the-player-in-a-live-drive-in-397)). Code: `game/ui/menu/`
and `game/ui/screens/main_menu.gd`.

## Parts

| Part | What it is |
| --- | --- |
| `MenuShell` | The stage, a scrim on the panel's side, `MenuTabBar`, `MenuPlate`, `MenuHints` and one `MenuPanel` per tab. Q and E, Ctrl+Tab and the bumpers change tab (`MenuNav.tab_step`, one pure function); a drag on the stage turns the soldier in Loadout |
| `MainMenu` | The router's screen that hosts the shell. It reads the profile and the challenge board, and turns each ask a panel makes (`MenuContext.action`) into a router push through one table, `MainMenu.ROUTES` |
| `MenuProfile` | The account facts from the cached profile (`profile/cache` in the settings file, JSON, read-only): name, XP, stubs, mastery. Billing levels are derived (`150 + 30 x level`), an empty or damaged cache is a new player |
| Panels | `PlayPanel` (the sign, Play together, Quick join, Solo, today's challenges), `LoadoutPanel` (the customize screen embedded, a showcase weapon row), `ShopPanel`, `ChallengesPanel` (a sheet of paper: dailies, orders, milestones, a family chip), `MorePanel` |
| Look | `MenuLook` (colours, type sizes, `Paper`, `Punches`, `Ring`, the ticket polygon), `MenuItemButton` (a ticket), `ChallengeRow` (a stub, or a ruled line on the sheet) |
| `MenuScale` | The phone rules: below 500 px on the short side the UI factor doubles, so the design is 540 units high. The factor is the menu's: a night pushed over it runs on the player's own scale (1080 units high, what its HUD and touch layer are made for, #606) and the shell puts the factor back when it shows again |

## Placeholders and seams (listed because they are not the real thing yet)

- **The Shop** has three real entries (the look catalogue's gated colours, priced as `LookCatalog` says) and five
  placeholder rows marked "Coming"; a press buys nothing. Prices are the catalogue's first guesses.
- **Play together** opens the Play together screen from one table (`MainMenu.ROUTES`). **Quick join** is not in it: the
  menu opens `QuickJoinOverlay`, a card over the menu that finds the first open public night and goes in (#526; see
  [the lobby](../design/lobby.md#quick-join-from-the-menu)).
- **The profile** has no writer: nothing in the client sets XP, stubs or mastery; the backend (or a test) fills the cache.
- **Mastery** shows the level and the way to the next one; trims do not exist yet.
- **Account** says that signing in comes with the platform.
- **The challenge board** is the tracker's (#399); until it is in the project the menu finds the class by name at run
  time and shows no challenges when it is missing.

## What we learned

- **A count beside its text, never at an offset.** The first mock put each count at a hand-measured x and "1,850/3,000"
  ran off the paper. The rows are containers now: the text takes what is left and is cut with an ellipsis, the count
  takes what it needs. The longest count, `1,000,000/1,000,000`, is 331 units wide in the display face;
  `test_the_longest_count_fits_its_row_on_every_panel_and_canvas` fills rows with it on the desktop and the phone layouts.
- **A `Label` set to trim with an ellipsis has no minimum width**, so inside a container it collapses to nothing. Only
  the text that is allowed to give way is trimmed (`ChallengeRow` titles); every other label keeps its size.
- **The headless test window is 64 pixels**, which the phone rule reads as a phone. The shell treats a headless run as
  a desktop; a test that wants the phone layout sets `phone_mode`.
- **The wardrobe's own labels are 16 units**, 11.6 px on a phone: under the written 14 px. On a phone the Loadout tab
  raises every label to the caption size and every picker to a tap target (62 units, 44 px); a test walks every label
  and every pressable control of every tab at 844 x 390.
- **Focus order is written, not guessed.** Down from the last start, with the rows in another container, went nowhere;
  the Play tab chains its starts and rows explicitly and ends the chain on the last row.
- **Hover moves the focus** (the same rule as the buttons of the addon), so the keyboard and the mouse never disagree.
- **The browser runs find the menu's items by key.** The seven scripts of `tools/web_smoke/` pressed Down and Up
  counts against the old column. They share `smoke.menu_item(page, tab, steps)` now: E walks to the tab (the game reports
  it as `window.deadnight.tab`), the tab's first control takes the focus whatever it was, and `steps` presses of Down
  reach the item. `start_solo` is Play, then two Downs, then Enter (Solo), then Enter again on the Play screen's
  Start the night (#620).

- **A panel holds its choices and writes them once, when the player leaves** (#489). The Loadout tab first wrote the
  showcase weapon on every click, which made the stage dress the soldier from the *saved* look (the weapon's
  `Settings.changed` ran `MenuStageView.reload_look`) and so threw the picked outfit off the screen, and leaving the tab
  dropped any look not saved with the footer's Save. Now the wardrobe keeps the working look, `LoadoutPanel` the weapon,
  and the stage previews both; `MenuPanel.commit` writes them with one `Settings.save()`. The shell calls it on a tab
  change, on `MenuContext.leaving` (just before any action: Play, Settings, Credits, Quit), on a close request and when
  the window loses focus (a browser has no close request), and as it leaves the tree. A visit with no change writes
  nothing. A new panel with choices does the same: hold in memory, override `commit`, never write per click.
- **Solo went to the night with no rules (#620).** `MainMenu.ROUTES[&"solo"]` pointed at the night screen since the
  first menu (#33). The Play screen (`PlayScreen`, #449) holds the settings a room host sets (the same
  `MatchSettingsPanel`) and was left unrouted ("a one-line change left to the menu work", #449); the menu rework
  (#466) wrote "Solo opens the night" and the scenes table called the screen an old placeholder, so nothing owned the
  line. Solo now opens it and Start opens the night. A headless run measures text as nothing, so a layout test there
  cannot see a phone overflow: the Play screen's fit at 844 x 390 (540 units high) is checked by
  `tests/captures/solo_settings_tour.tscn` (real fonts; it prints each control outside the window) and by
  `tools/web_smoke/solo_settings.py` (a finger and a keyboard through the real build). On a phone the screen drops the
  overline, the hints and the margins and makes every row and button a tap target (62 units).

- **A hovered button is paint, and a scroll area cuts paint** (#628). `UIButton` grows 3.5 percent on hover; the lobby's
  rows are full-width buttons in a `ScrollContainer`, which clips at its own rectangle, so "Copy the link" lost its
  left edge. Two shared rules: the button grows only by the room it has inside its nearest clipping ancestor, and the
  theme keeps `UITokens.hover_room` free at the left and right of every `ScrollContainer` (not above and below: screens
  compute a scroll area's height from its content). A button flush with the first or last row of an area grows
  sideways only. The focus ring above the first and below the last row of an area is still cut (#644). `test_hover_room.gd`
  hovers every button of every menu screen at 720p, 1080p and the phone canvas, scrolled to the top, end and middle.

## Tests

`test_menu_shell.gd` (35 cases: tabs by keys, bumpers, D-pad and A, a click and a tap, hints per device, each panel
showing the profile, board and save, the stage following, the wardrobe previewing and restoring, a phone's minimums,
every panel inside every canvas, reduced motion, the longest count), `test_menu_profile_and_nav.gd`,
`test_main_menu.gd`, `test_main_menu_input.gd`, `test_gamepad_navigation.gd`, `test_loadout_keeps_choices.gd` (real
clicks: an outfit survives a weapon change, another tab and a reload from the file, and a visit writes the file once,
counted by `Settings.write_count`). Captures: `tests/captures/menu_shell_tour.tscn`,
`tests/captures/menu_loadout_keep_tour.tscn` (pick, change weapon, other tab, back; prints what the soldier wears).
`tests/captures/lobby_hover_tour.tscn` hovers the lobby's buttons with a real mouse event (windowed, through `gds godot`),
and exported as the main scene of a web build it publishes where each button is (`window.hoverRects`) for a browser to
hover (#628, before and after).

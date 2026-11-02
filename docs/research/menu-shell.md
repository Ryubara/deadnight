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
| `MenuScale` | The phone rules: below 500 px on the short side the UI factor doubles, so the design is 540 units high |

## Placeholders and seams (listed because they are not the real thing yet)

- **The Shop** has three real entries (the look catalogue's gated colours, priced as `LookCatalog` says) and five
  placeholder rows marked "Coming"; a press buys nothing. Prices are the catalogue's first guesses.
- **Play together and Quick join** open the same screen the old Join did, from one table (`MainMenu.ROUTES`) that the
  rooms flow replaces.
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
  reach the item. `start_solo` is Play, then two Downs, then Enter.

## Tests

`test_menu_shell.gd` (35 cases: tabs by keys, bumpers, D-pad and A, a click and a tap, hints per device, each panel
showing the profile, board and save, the stage following, the wardrobe previewing and restoring, a phone's minimums,
every panel inside every canvas, reduced motion, the longest count), `test_menu_profile_and_nav.gd`,
`test_main_menu.gd`, `test_main_menu_input.gd`, `test_gamepad_navigation.gd`. Captures: `tests/captures/menu_shell_tour.tscn`.

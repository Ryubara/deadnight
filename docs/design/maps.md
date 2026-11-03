# Maps and the map choice

A night is played on one map, and whoever starts it chooses which: a solo player on the Play screen, a room's host in
the lobby. The drive-in lot ([the lot](map.md)) is the only shipped map; the second, a small indoor one
([the formula](../research/maps/small-map-formula.md), greybox #631), is listed as a locked "coming soon" card until its
scene lands. Issue #624.

## The registry

`MapRegistry` (`game/world/maps/map_registry.gd`) lists the maps, each a `MapInfo` resource under `game/world/maps/`:

| Field | What it is |
| --- | --- |
| `id` | The id the settings, the backend and the wire carry (`drive_in`, `small_indoor`) |
| `title`, `blurb` | The card's name and a line about the map |
| `scene_path` | The scene `NightWorld` builds: the same node layout as `world/drive_in_greybox.tscn` (doors, spawns, lamps, switches, fuel) |
| `preview_path` | The card's picture, 16:9 (`assets/ui/maps/`); none draws the locked card's hatched stub |
| `area_m2`, `min_players`, `max_players` | What the card says: `13,200 m² · 1 to 8 players` |
| `shipped` | False while the map is not built: listed, locked, never loaded |

`MapRegistry.of(id)` is the map to load: an id nobody knows, or a map that is not playable yet, is the drive-in lot,
so a night never fails to start over a map. `NightWorld.build(info)` instances the map's scene; `Night.start` builds
the map its `match_settings.map` names, `NightHost` the map of its `match_settings` (the room opens with the ticket's
rules), and a client that joined a room builds the map of its lobby first (`NightScreen.join_map`, from
`MapRegistry.of_lobby`) and builds the world again when the WELCOME says another one (`Night._use_map_of_server`: an
address typed on the Join screen knows nothing of the map).

### Adding a map

1. Build its scene with the lot's node layout and put it where `scene_path` says.
2. Add a `MapInfo` resource (copy `drive_in.tres`), the picture, and list it in `MapRegistry.PATHS`.
3. Set `shipped = true` and `scene_path`; add its id to `PLAYABLE_MAPS` in `spikes/backend/src/settings.ts` (a test
   compares the two lists, `test_the_backend_lists_the_maps_the_game_can_play`).

A map with its own prices, windows or caps names a rules overlay in its scene's `metadata/tuning` (`MapTuning`, laid
over a copy of the shared table by `NightWorld.rules_for`: the night and the balance simulator do it already; a client
that builds the map from a WELCOME must too, before the snapshot's tuning id is compared). A scene with floors, its own
spawn groups and saved meshes is read through `MapLayout` ([the second map](smallmap.md#what-a-night-reads-from-a-map-scene)).

The small indoor map's entry (`small_indoor.tres`) already exists with `shipped = false`; its name, "The back rooms",
is a working title. Its scene plays (the links, windows, buys and box are set up, #632) and the tests and captures build
it with `Night.scene` / `NightWorld.scene`; the picker unlocks it when its entry gets a `scene_path` and `shipped`.

## The choice is a match setting

`MatchSettings.map` (key `map`, a String) goes wherever the other settings go: the rules' snapshot, so every WELCOME
carries it (the packed variable holds any dictionary, so the protocol layout and `NetWire.VERSION` are unchanged); the
backend's lobby (`PUT /lobbies/:id/settings`, the start's `settings`) and the ticket's `settings` claim. The key is
optional when read (`MatchSettings.OPTIONAL_KEYS`): a ticket, lobby or snapshot from a build before the choice has none
and means the lot, and a build that knows nothing of the key ignores it, so a client and a server of two builds still
read each other. It is always written. A map that cannot be played is refused as `bad_settings` by the backend and as
`map` by `MatchSettings.problem`; `clamped()` puts the lot in its place.

The backend's lobby view and the preview of a code say `map` (the lot when the host set none), so a screen that does
not read the settings can show it.

## The picker

`MapPicker` is a row of `MatchSettingsPanel`, the one panel Solo's Play screen and the room's lobby both hold, so a
host and a solo player get the same choice from one definition (`test_solo_match_settings.gd` fails on a setting
without a row). It is the first row, in the control column of a `UIRow`: one `MapCard` under another, 440 units wide.

A card is a ticket drawn as the menu's are (`MenuLook.draw_ticket`, the cream paper with a notch in each side, the
perforated stub, `MenuItemButton`'s amber outline for the focus or the pointer): the preview on the stub, the name in
the display face, the size and the players under it, and `SELECTED` in red on the chosen card (with a red outline). A
map that is not built is on shaded paper with a hatched stub, a padlock and a COMING SOON stamp; it takes the focus (a
keyboard can read it) but a press chooses nothing (`MapPicker.blocked`). A phone held sideways gets the compact card:
no picture, 74 units high, the name over one line of facts.

| Input | What it does |
| --- | --- |
| Up, Down, the d-pad | Walk the cards; Left and Right stay on the card; the first card's Up and the panel's Down continue the screen's chain |
| Enter, Space, A | Choose the card in focus |
| A tap, a click | Choose that card; hovering moves the focus, as on every ticket |

A guest's lobby shows the host's choice and cannot move it (`set_editable(false)`: no focus, no clicks).

## Where else the map shows

- **A code looked at** (`LobbyScreen` in preview mode) shows the room's map as a ticket nobody can press, under the
  seats.
- **Quick join** (`QuickJoinOverlay`) shows the map of the night it found as a card under "Finding a night...", from the
  moment the backend answers until the night opens. There is no room list in the game: Quick join takes the first open
  night, and a code is looked at with its preview.
- **The lobby of a member** has the picker in its rules: the host's moves, a guest's is read only.

Proof: `tests/world/test_map_registry.gd`, `test_map_night.gd` (a stub second map built by the world, the solo night,
and the lot for a map that cannot be played), `tests/net/test_map_choice_net.gd` (a room on the stub map over a real
socket; a client built on the wrong map builds again), `tests/ui/test_map_picker.gd` (keyboard, gamepad and touch),
`spikes/backend/test/rooms.test.ts`, and the captures in the pull request.

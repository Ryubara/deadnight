# Maps and the map choice

A night is played on one map, and whoever starts it chooses which: a solo player on the Play screen, a room's host in
the lobby. There are two maps: the drive-in lot ([the lot](map.md)) and the small indoor one, "The back rooms"
([the second map](smallmap.md), [the formula](../research/maps/small-map-formula.md)), shipped in #792. A map that is
listed and not built is shown as a locked "coming soon" card (a `MapInfo` with `shipped = false`). Issue #624.

## The registry

`MapRegistry` (`game/world/maps/map_registry.gd`) lists the maps, each a `MapInfo` resource under `game/world/maps/`:

| Field | What it is |
| --- | --- |
| `id` | The id the settings, the backend and the wire carry (`drive_in`, `small_indoor`) |
| `title`, `blurb` | The card's name and a line about the map |
| `scene_path` | The scene `NightWorld` builds: the lot's node layout (doors, spawns, lamps, switches, fuel), or a scene `MapLayout` reads (the second map's) |
| `preview_path` | The card's picture, 16:9 (`assets/ui/maps/`); none draws the locked card's hatched stub |
| `area_m2`, `min_players`, `max_players` | What the card says: `13,200 m² · 1 to 8 players` |
| `unlock_level` | The account level that opens the map: the drive-in 1, the back rooms **10** (see [Levels open maps](#levels-open-maps)) |
| `shipped` | False while the map is not built: listed, locked, never loaded (both maps are shipped; the suites use a stub, `StubMaps`) |

`MapRegistry.of(id)` is the map to load: an id nobody knows, or a map that is not playable yet, is the drive-in lot,
so a night never fails to start over a map. `NightWorld.build(info)` instances the map's scene; `Night.start` builds
the map its `match_settings.map` names, `NightHost` the map of its `match_settings` (the room opens with the ticket's
rules), and a client that joined a room builds the map of its lobby first (`NightScreen.join_map`, from
`MapRegistry.of_lobby`) and builds the world again when the WELCOME says another one (`Night._use_map_of_server`: an
address typed on the Join screen knows nothing of the map).

### Adding a map

1. Build its scene with the lot's node layout and put it where `scene_path` says. It carries the soda fountain, the
   five perk coolers, the re-cut bench and a prize crane place, as every map does (the formula's row 25);
   `test_map_machines.gd` reads the picker's list and fails a map without one.
2. Add a `MapInfo` resource (copy `drive_in.tres`), the picture, and list it in `MapRegistry.PATHS`.
3. Set `shipped = true` and `scene_path`; add its id to `PLAYABLE_MAPS` in `spikes/backend/src/settings.ts` (a test
   compares the two lists, `test_the_backend_lists_the_maps_the_game_can_play`).

A map with its own prices, windows or caps names a rules overlay in its scene's `metadata/tuning` (`MapTuning`, laid
over a copy of the shared table by `NightWorld.rules_for`: the night and the balance simulator do it already; a client
that builds the map from a WELCOME must too, before the snapshot's tuning id is compared). A scene with floors, its own
spawn groups and saved meshes is read through `MapLayout` ([the second map](smallmap.md#what-a-night-reads-from-a-map-scene)).

The small indoor map's entry (`small_indoor.tres`) has `scene_path`, a picture (`assets/ui/maps/small_indoor_preview.png`),
`max_players = 8` (the room's seats, as the lot) and `shipped = true`; its id is in `PLAYABLE_MAPS` of the backend.

## Levels open maps

Decision 17 of [the progression plan](progression.md#maps) (the maintainer, 2026-11-04: "Maps locked by levels: yes",
"Host's level decides the map", and for the back rooms "it's not too early. Level 10 is fine."). `MapInfo.unlock_level`
is data, so moving a map is one line in its `.tres`; `MapRegistry.RESERVED_UNLOCKS` keeps the rungs 25 and 40 for maps
three and four. With the 8-hour curve level 10 comes after about half an hour of play.

- **The host's level decides.** The picker of the person who hosts (Solo's Play screen, a room host's lobby) offers a map
  only when that person's level opens it (`MapPicker.level`, from `PlayerLevel.local()`, the cached profile: a Guest
  account is a real account with a level). A card the level does not open is [hidden](#the-picker); a press, Enter or
  A on it chooses nothing and plays the refusal (`map_card_locked`). Solo's Start also fits the choice to the level
  (`MatchSettings.fit_host`), and a picker that takes the host role holding a map the level does not open falls back to
  the lot.
- **A guest below the level still plays there.** A guest's picker is read only and shows the map the lobby is on by name,
  whatever the guest's level; the night loads it from the WELCOME as any map.
- **The server checks the host's level from the ticket, never from a client's message.** The backend signs the lobby
  host's level into every ticket of the match (`hostLevel`; every ticket carries the host's, so the order the players
  arrive in decides nothing). `TicketVerifier.admit` reads it and applies `MatchSettings.fit_host`: a ticket whose rules
  name a map the host's level does not open opens the room on the drive-in lot (the other rules stand) and the game
  server logs `map_locked`. A claim that is there but damaged counts as level 1, so it never opens a map, and a ticket
  with no `hostLevel` (a backend from before levels) is level 1 as well (`TicketVerifier.NO_LEVEL`). The backend signs the
  claim from the host's stored profile (#1098), and `test_map_unlock_net.gd` runs the rule over the real backend. A client
  cannot change a room's rules over the net (`NightHost.configure_match` is the server's).
- **In a browser test** a page that asks for the probes sets `window.deadnight_player_level` before the game starts
  (`tools/web_smoke/smoke.py give_level`), because a fresh build has no profile and so every player is level 1.

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
map that is not built (none is today; the suites use a stub) is on shaded paper with a hatched stub, a padlock and a
COMING SOON stamp; it takes the focus (a keyboard can read it) but a press chooses nothing (`MapPicker.blocked`).

A map the level does not open yet is a **hidden card**, in the look the wardrobe uses for what is locked (#1065): the
name is `???`, the stub is the map's picture as a dark silhouette under a padlock and a `LEVEL 10` stamp, and under the
name it says `Level 10`. With the focus or the pointer on it, it says what to do ("Reach level 10 to host a night on this
map."), and the pointer's tip says the same; a screen reader gets "Locked map, Reach level 10 to host a night on this
map." and never the name. It takes the focus, and a press chooses nothing and plays the refusal. The card of the map
the lobby is on is never hidden. A phone held sideways gets the compact card: no picture, 74 units high, the name over
one line of facts (the hidden card's two lines are `Level 10` and, on focus, `Reach level 10` / `to host here.`).

| Input | What it does |
| --- | --- |
| Up, Down, the d-pad | Walk the cards; Left and Right stay on the card; the first card's Up and the panel's Down continue the screen's chain |
| Enter, Space, A | Choose the card in focus |
| A tap, a click | Choose that card; hovering moves the focus, as on every ticket |

A guest's lobby shows the host's choice and cannot move it (`set_editable(false)`: no focus, no clicks).

## Where else the map shows

- **A code looked at** (`LobbyScreen` in preview mode) shows the room's map as a ticket nobody can press, under the
  seats.
- **The Server Browser** (`ServerBrowserScreen`) shows each night's map as the faded picture behind its row and its name
  on it (`NightRow`, from the row's `map` id; an id the game does not know is the lot). A code is looked at with its
  preview.
- **The lobby of a member** has the picker in its rules: the host's moves, a guest's is read only.

Proof: `tests/world/test_map_registry.gd`, `test_map_night.gd` (a stub map and the second map built by the world, the
solo night, and the lot for a map that cannot be played), `tests/net/test_map_choice_net.gd` (a room on the stub map and
on the second map over a real socket, and a client built on the wrong map builds again), `tests/ui/test_map_picker.gd`
(keyboard, gamepad and touch, on stub maps, the second map's card chosen, and the hidden card below level 10: focus, Enter,
A, a click and a tap refused, the level rising, a guest below it seeing the lobby's map), `tests/net/test_ticket_verifier.gd`
and `tests/net/test_map_unlock_net.gd` (a level-3 host, a level-12 host and a guest of either, over a real socket),
`tests/progression/test_player_level.gd`, `spikes/backend/test/rooms.test.ts`, and
the captures in the pull request.

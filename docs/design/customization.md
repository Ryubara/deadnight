# Customization

How a player dresses their character and how the others see it. The look itself (slots, parts, colour channels,
presets) is defined in [Characters](characters.md); this page is the screen, the saved form,
the wire form and the rules that keep teammates readable. Cosmetics only: nothing here changes a night
([progression](progression.md#wardrobe-costumes-and-the-locks): the grid, `???` locks, costumes and mouths).
Costumes are [below](#costumes).

## The screen

**Loadout** on the main menu opens the wardrobe: the soldier on the menu's stage, and beside it a strip of tabs
(Costumes, Body, Hair, Hats, Tops, Legs, Shoes, Eyes, Neck, Colours) with the choices of the tab in a grid under it
(#1065, #1066).

![The Tops tab at level 12, a locked item under the pointer](../research/wardrobe-grid-tops.png)

| Part | What it does |
| --- | --- |
| Tab strip | A press shows the tab; the pad and the keys walk the strip (a tab is shown when it is pressed, not when the focus passes it) |
| Costumes tab | The twelve presets as costumes: lit when the player owns every piece, a `???` silhouette until then ([Costumes](#costumes)) |
| Body tab | The character (Male, Female), the face, the mouth and the skin colour (the old Preset row is the Costumes tab now) |
| Hair tab | Hair style and hair colour |
| Hats, Tops, Legs, Shoes, Eyes, Neck | One grid each (Neck also holds the armband). The wearables of the ladder, **the starting pieces first and then up the ladder by level**; the slots that may be empty start with a slashed "None" |
| Colours tab | The costume's **Default** option, then main, second and trim colour: one cloth palette of 16, three grids |
| Detail line | What the pointer or the focus is on: the name and what a press does, or `???` and how to get it |
| Randomize | A look made only of what the player has unlocked |
| Save / Back | On its own screen, Save writes the look; Back (or Esc, gamepad B) leaves and drops unsaved changes, and the footer says which. In the main menu's Loadout tab there is no Save: the look and the showcase weapon are kept while the tab is open and written once when the player leaves it |
| Turntable | On its own screen it turns by itself (still with reduced motion); drag it, or push the right stick |

**A cell** (`WardrobeCell`) is a plate with the item's icon over its name. A lit one is the item's drawing; a locked
one is **the silhouette of the same drawing in one flat colour, its name `???`, and a small padlock**. A press on a lit
cell wears the item (the soldier shows it at once; the worn one has a check and an amber border); a press on a locked one
shakes the cell and changes nothing: **there is no fitting room**. Face, hair, skin, body, mouth and armband are free and
carry no lock mark; **weapons and tonics are never locked and are not in the wardrobe**.

**Hover and focus say the same words.** The pointer over a cell, or the focus on it (a pad, a keyboard, a tap on a phone),
puts on the detail line `??? - Reach level 22 (you are level 12)` for a locked item, `Jacket - press to wear` for a lit
one, and the rest line when nothing is pointed at. The pointer does not take the focus (that would scroll the grid under
the hand). A piece the ladder promises and the art does not have yet (#1078) shows lit once its level is reached and says
"not drawn yet"; it cannot be worn, and below its level it is a silhouette like any other.

**The icons** (`ItemIcons`) are drawn in code on a 100 by 100 plate, in the level icons' language (#1060): flat colours,
an ink outline, a few shapes. A locked silhouette is every outline first and then every fill in `UITokens.outline`, so
the inner detail disappears and the ink rim stays. No texture is loaded, so nothing has to be held (the white-square
lesson of `LevelIcons`) and the same code is sharp at any size. The free choices (a face, a hair style, a mouth) are
their names on a plate: eight mouths are told apart by name.

**Phone.** The cells are 104 by 114 units (colours 84 by 100), 64 units being the least a finger gets, the ten tabs
fit one row of the narrowest card (5 units of padding, 21-unit type: 14.6 CSS px on the 667 x 375 page), and the card
opens on a full row of items (#1271). Its chrome is cut to make room, since a phone leaves the tab 372 units: the
card's own margins are 8 and 6 units (the theme's are 32 and 24), and the Randomize button and the detail line share
the card's last row (the "saved" line is kept up to date and not shown). The weapon row of the Loadout tab sits at the
end of the Body tab's page there, so the grid is what shows first, and the focus starts on the wardrobe's tab, not on
the weapon row below the fold.

Input: a cell is one focus stop. Left, right, up and down walk the grid (the engine's nearest-control walk); up from the
first row goes to the tab on show; down from a tab goes to the page's first cell; accept wears.

## Costumes

The twelve presets of `parts.json` are the costumes (`Costumes`, #1066). A costume is a whole look: its pieces, its face
and hair, its colours. Nothing new is saved: wearing one sets an ordinary look, so the save and the wire are unchanged.

- **Lit or `???`.** A costume is the player's when they own **every piece** of it (`LookUnlocks.owns_costume`); until then
  its cell is the silhouette of its figure, its name `???`, and the pointer or the focus reads `??? - Reach level 20
  (you are level 12)`, the level of the last piece they lack. A press on it is refused like any locked cell: no fitting
  room. The grid runs the starting costumes first, then up the ladder.
- **Equipping.** A press on a lit costume sets the whole look (the soldier shows it at once, the worn one has a check).
  The player may then change any part they own. The costume on the character is found by its pieces (body, headwear, top,
  legs, shoes, eyewear, neckwear, armwear: `Costumes.of_look`), so the face, the hair, the mouth and the colours can be
  changed and it is still that costume.
- **Default colours.** A costume's colours are data on the preset. The Colours tab starts with a **Default** option
  that gives the costume on the character its own main, second and trim colour back (skin and hair colour stay the
  player's). It is dim, and says "wear a costume to give it its own colours back", while no costume is on. The player's
  own colours come from the palette they have unlocked, as always.
- **Default needs none of the colour unlocks.** A costume may default to a colour the ladder opens later (the Usher's gold
  trim is level 42; the costume is level 20). `CharacterLook.without_locked` keeps the three cloth colours of a costume
  the player owns **while the look wears all three** (`CharacterLook.default_costume`), on load, on Save and on the server.
  Change one of the three and the others fall back to the palette the player owns, at once on the screen. A locked
  colour that is worn as a Default shows lit, not as a padlock, so the grid never says `???` over a colour on the
  soldier. The grid of the palette itself is not widened: gold is still level 42 in every channel for anyone choosing it.
- **Which costumes a new player has.** Only two presets are made of starting pieces (Soda jerk and Carhop). The plan said
  four ([progression](progression.md#wardrobe-costumes-and-the-locks)); no four can be made of the ladder as it is, and
  the maintainer kept the two (2026-11-04, #1066).

## Saved and sent

| Form | Where | Shape |
| --- | --- | --- |
| Saved | `character/look` in the settings file, soon the platform profile | JSON of readable ids (`{"version":1,"parts":{"headwear":"helmet",...},"colours":{"skin":"peach",...}}`): a catalogue that grows never breaks a save |
| On the wire | one packet per look | version byte, then one byte per part slot (its index) and per colour channel (its palette index): 17 bytes |

Whatever comes from outside is untrusted: a damaged save, a look of another version, an index out of range all become
the first option of that slot (or the default look for a wrong version), and the server puts back anything the sender
has not unlocked (`LookServer`, with the unlocks `NightServer` answers from `player_levels`: the level the ticket's
XP gives a seat that has an account (`NightHost.register_account`), the local player's level from their profile in a
night at their own machine; a player with no known level, a server with no backend, is trusted with the whole
wardrobe). The wire is at version 3 (the
`mouth` slot, #1061); a look of version 2 still reads (16 bytes, `CharacterLook.OLDEST_VERSION`, the first mouth), and a
save from before the mouth has no `mouth` id and takes the first too.

## On the network

Two messages continue the numbering of the [own protocol](networking.md) (types 1 to 7 are the spike's):

| Message | Direction | Fields |
| --- | --- | --- |
| `LOOK` (8) | client to server, once on join | the look (18 bytes with the type; 17 before the mouth, #1061) |
| `PLAYER_LOOK` (9) | server to everyone | player id, seat, the look (20 bytes with the type) |

On join the server gives the player the lowest free **seat** (0 to 7), tells everyone, and tells the newcomer who is
already there; until the newcomer's own look arrives they wear the preset of their seat. Every client keeps a
`LookRegistry` and builds each player's model from it with the same assembler the wardrobe uses.

In the night (`Night`, `NightServer`) the same path runs over the loopback link: after `join`, the client sends a
`look` message carrying `LookWire.look` of the look saved in the wardrobe (`LookStore`); the server's `LookServer`
accepts it and answers every client with `look_packet` events (the `PLAYER_LOOK` bytes); the client's `LookRegistry`
takes them and `Night` dresses each body from the resolved table (`Player.dress`, which is
`CharacterAssembler.dress` on the body's own Soldier). The HUD portraits hear the same table as `player_look` events.
The player scene's Model is the modular Soldier (`soldier_parts.glb`, the kit Soldier's rig and clips), so the
animation tree and the weapon mount work as before; until a look arrives a body wears the default look.

## Rules that keep a lot readable

- **The armband is the seat's, not the look's.** Four fixed colours (red, cyan, yellow, green), emissive so they read in
  the dark, added by the assembler whatever the player wears. A look cannot change, hide or reuse it.
- **Identical looks are told apart, the same way everywhere.** `LookResolver` walks the players by id; a look already
  taken has its main colour moved on three palette places (more, if that is taken too). It needs no message: every client
  reaches the same answer from the same looks, whatever order they arrived in.
- **Locked options show as silhouettes.** A gate is `{"level": n}` (the account level that opens it) or
  `{"order": name}` (a challenge's reward, none yet). The table is the ladder's `unlocks.json`
  (`game/gameplay/progression/`, the one table the level popups and the maps read too), read by `LookCatalog`
  (`part_gates()`, `palette_gates()`): a part or colour it does not name is free. A preset may wear gated pieces
  (they are the [costumes](#costumes)); one put on a player is repaired by what they own.
- **A look is repaired to what its wearer owns.** `CharacterLook.without_locked` puts a piece the player does not own back
  to **the first piece of the slot that they may wear** (a vest, sneakers, trousers, no hat) and a colour to the first
  they may use (black), on load (`LookStore.load_look`, the level read from the profile file), on Save, and on the server
  (below). The saved look and the wire format are unchanged: an index per part.
- **Free first.** Every slot has a piece a new player owns, and Randomize never picks a locked one.

## Where it lives

| File | Role |
| --- | --- |
| `game/gameplay/character/look_catalog.gd` | the choices, read from `parts.json` |
| `character_look.gd`, `look_resolver.gd`, `look_unlocks.gd`, `look_store.gd` | the look as data, duplicate handling, gates, saving |
| `character_assembler.gd` | builds a model from a look and a seat |
| `game/net/look_wire.gd`, `look_server.gd`, `look_registry.gd` | the messages, the server side, the client table |
| `game/gameplay/character/costumes.gd` | the presets as costumes: the pieces, the level, the costume a look wears, the Default colours |
| `game/ui/screens/customize_screen.gd`, `look_preview.gd` | the wardrobe: the tabs, the pages, the detail line |
| `game/ui/wardrobe/wardrobe_cell.gd`, `wardrobe_tab.gd`, `item_icons.gd` | a cell of the grid, a tab of the strip, the drawings |
| `game/gameplay/progression/unlocks.json` | the ladder: what each level gives (the wardrobe's rows are the wearables and `colour`) |

## The parts

The choices are read from `parts.json`, the catalogue the Soldier parts build writes beside the model
([Characters](characters.md)): eleven part slots, five colour channels over three palettes, twelve presets. The assembler
is `SoldierLook` (the parts' own loader) plus the seat armband, and the character stands in its `Idle` clip. The seat
armband is a ring placed on the right upper arm from the skeleton's own bone directions, so it follows whatever the
rig's axes are; the `arm: armband` part of the look is a separate, cosmetic armband on the left arm, tinted by the trim
colour, and the two are never confused because only the seat's is emissive and fixed.

Saved and sent looks refer to parts by index (wire) or by id (save). Parts and palette entries are only ever added at
the end, as the catalogue page says. The web preset includes `*.json` in its export filter, and CI opens the wardrobe
in a browser ([web export](../research/web-export.md)). What a locked entry asks for is a row of `unlocks.json`
(`{level, slot, item, available}`): a wearable's row also has `part`, its key in the catalogue (`torso/rolled`), and a
`label` while the art is not drawn; a `colour` row's `item` is a name of the cloth palette. A piece or colour with no row
is free (the starting ones). `available` is true exactly when `parts.json` has a model for the piece, and a test fails
otherwise, and for a row with no icon. A new piece is a row in `unlocks.json`, an entry in `parts.json` and a drawing in
`ItemIcons`. The ids are the catalogue's, not the row's `item` (`top/ushers_jacket` is `torso/usher`, `trousers/swing_skirt`
is `legs/swing`, `neck/film_strip_scarf` is `neck/film`): the `part` key is the map.

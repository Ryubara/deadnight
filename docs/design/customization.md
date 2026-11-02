# Customization

How a player dresses their character and how the others see it. The look itself (slots, parts, colour channels,
presets) is defined in [Characters](characters.md); this page is the screen, the saved form,
the wire form and the rules that keep teammates readable. Cosmetics only: nothing here changes a night
([progression](progression.md#the-cast-and-the-marquee-cosmetic-identity)).

## The screen

**Customize** on the main menu opens the wardrobe: a lit turntable with the character on the left, the pickers on the
right.

| Control | What it does |
| --- | --- |
| Preset | One of the eight starting looks; reads **Custom** as soon as anything is changed by hand |
| A selector per part slot | Face, hair style, headwear, top, trousers, footwear, eyewear, neckwear, armwear; left and right step through the parts |
| A strip per colour channel | Swatches: skin, hair, main, second and trim colour |
| Randomize | A look made only of what the player has unlocked |
| Save / Back | On its own screen, Save writes the look; Back (or Esc, gamepad B) leaves and drops unsaved changes, and the footer says which. In the main menu's Loadout tab there is no Save: the look and the showcase weapon are kept while the tab is open and written once when the player leaves it |
| Turntable | Turns by itself (still with reduced motion); drag it, or push the right stick |

Input: a strip is one focus stop. Left and right (arrows, d-pad, stick) move along it and choose as they go, up and down
change row, a click picks a chip. A locked chip is drawn grey with a padlock; the cursor can stop on it (the caption
says how to get it: "Reach Billing level 10") but the choice stays on the last free one.

## Saved and sent

| Form | Where | Shape |
| --- | --- | --- |
| Saved | `character/look` in the settings file, soon the platform profile | JSON of readable ids (`{"version":1,"parts":{"headwear":"helmet",...},"colours":{"skin":"peach",...}}`): a catalogue that grows never breaks a save |
| On the wire | one packet per look | version byte, then one byte per part slot (its index) and per colour channel (its palette index): 15 bytes |

Whatever comes from outside is untrusted: a damaged save, a look of another version, an index out of range all become
the first option of that slot (or the default look for a wrong version), and the server puts back anything the sender
has not unlocked (`LookServer`, with the unlocks the platform backend will supply).

## On the network

Two messages continue the numbering of the [own protocol](networking.md) (types 1 to 7 are the spike's):

| Message | Direction | Fields |
| --- | --- | --- |
| `LOOK` (8) | client to server, once on join | the look (16 bytes with the type) |
| `PLAYER_LOOK` (9) | server to everyone | player id, seat, the look (18 bytes with the type) |

On join the server gives the player the lowest free **seat** (0 to 3), tells everyone, and tells the newcomer who is
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
- **Locked options show, greyed.** Gates are `billing` (a level), `stubs` (a price) or `order` (a goal); the gate table
  is in `LookCatalog` until progression exists, and no preset uses a gated option. A gated part reads "(locked)" in its
  selector and stays put when stepped onto.
- **Free first.** Every palette and slot starts with a free entry, and Randomize never picks a locked one.

## Where it lives

| File | Role |
| --- | --- |
| `game/gameplay/character/look_catalog.gd` | the choices, read from `parts.json` |
| `character_look.gd`, `look_resolver.gd`, `look_unlocks.gd`, `look_store.gd` | the look as data, duplicate handling, gates, saving |
| `character_assembler.gd` | builds a model from a look and a seat |
| `game/net/look_wire.gd`, `look_server.gd`, `look_registry.gd` | the messages, the server side, the client table |
| `game/ui/screens/customize_screen.gd`, `game/ui/components/choice_strip.gd`, `look_preview.gd` | the wardrobe |

## The parts

The choices are read from `parts.json`, the catalogue the Soldier parts build writes beside the model
([Characters](characters.md)): nine part slots, five colour channels over three palettes, eight presets. The assembler
is `SoldierLook` (the parts' own loader) plus the seat armband, and the character stands in its `Idle` clip. The seat
armband is a ring placed on the right upper arm from the skeleton's own bone directions, so it follows whatever the
rig's axes are; the `arm: armband` part of the look is a separate, cosmetic armband on the left arm, tinted by the trim
colour, and the two are never confused because only the seat's is emissive and fixed.

Saved and sent looks refer to parts by index (wire) or by id (save). Parts and palette entries are only ever added at
the end, as the catalogue page says. The web preset includes `*.json` in its export filter, and CI opens the wardrobe
in a browser ([web export](../research/web-export.md)). What a locked entry asks for is `LookCatalog.PALETTE_GATES`
and `PART_GATES` until progression exists.

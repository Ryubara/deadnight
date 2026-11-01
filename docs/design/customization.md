# Customization

How a player dresses their character and how the others see it. The look itself (slots, parts, colour channels,
presets) is defined in `docs/design/characters.md` (the modular parts, #100); this page is the screen, the saved form,
the wire form and the rules that keep teammates readable. Cosmetics only: nothing here changes a night
([progression](progression.md#the-cast-and-the-marquee-cosmetic-identity)).

## The screen

**Customize** on the main menu opens the wardrobe: a lit turntable with the character on the left, the pickers on the
right.

| Control | What it does |
| --- | --- |
| Preset | One of the eight starting looks; reads **Custom** as soon as anything is changed by hand |
| A strip per part slot | Text chips (headwear today; every slot with two parts or more appears) |
| A strip per colour channel | Swatches: skin, hair, main, second and trim colour |
| Randomize | A look made only of what the player has unlocked |
| Save / Back | Save writes the look; Back (or Esc, gamepad B) leaves and drops unsaved changes, and the footer says which |
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

## Rules that keep a lot readable

- **The armband is the seat's, not the look's.** Four fixed colours (red, cyan, yellow, green), emissive so they read in
  the dark, added by the assembler whatever the player wears. A look cannot change, hide or reuse it.
- **Identical looks are told apart, the same way everywhere.** `LookResolver` walks the players by id; a look already
  taken has its main colour moved on three palette places (more, if that is taken too). It needs no message: every client
  reaches the same answer from the same looks, whatever order they arrived in.
- **Locked options show, greyed.** Gates are `billing` (a level), `stubs` (a price) or `order` (a goal); the gate table
  is `LookCatalog.PALETTE_GATES` until progression exists, and no preset uses a gated option.
- **Free first.** Every palette and slot starts with a free entry, and Randomize never picks a locked one.

## Where it lives

| File | Role |
| --- | --- |
| `game/gameplay/character/look_catalog.gd`, `look_catalog.json` | the choices, read from a catalogue in the schema of `parts.json` |
| `character_look.gd`, `look_resolver.gd`, `look_unlocks.gd`, `look_store.gd` | the look as data, duplicate handling, gates, saving |
| `character_assembler.gd` | builds a model from a look and a seat |
| `game/net/look_wire.gd`, `look_server.gd`, `look_registry.gd` | the messages, the server side, the client table |
| `game/ui/screens/customize_screen.gd`, `game/ui/components/choice_strip.gd`, `look_preview.gd` | the wardrobe |

## Until the modular parts land

The artist's catalogue (`parts.json`, described in `docs/design/characters.md`) has nine part slots; the kit Soldier
is one model, so `look_catalog.json` is a stand-in with the **same slots, colour channels, palettes and presets**
but only the parts the Soldier can show (headwear: a bare head or the field helmet; the rest have one part and so
are not offered). The assembler tints the Soldier's materials by channel. To switch over: point
`LookCatalog.CATALOG_PATH` at `parts.json` (add its gates to `PART_GATES`), replace `CharacterAssembler` with the
parts' own `SoldierLook.apply`, and move the seat armband to the right arm so it does not clash with the `arm:
armband` part. Saved and sent looks stay valid because the stand-in's part order is a prefix of the real one. A web
export must include `*.json` (the export filter) or the catalogue is missing in the browser.

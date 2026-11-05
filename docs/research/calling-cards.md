# Calling cards and emblems (#1070)

What a player wears on their plate: a **calling card** (a 440 by 120 sheet, shown behind their name) and an **emblem**
(a small badge after the name). The design is
[the plate](../design/progression.md#plate-calling-cards-emblems-and-frames); this page is how it is built and what
was measured.

## What is owned, and where it comes from

One gate per piece (progression rule 3): the ladder gives it at a level, or a challenge gives it, never both.
`PlateCatalog` joins the three files that say so and **derives** ownership from the level (from XP) and the finished
challenges (`Profile.done`), so nothing is stored twice and a retune needs no migration.

| File | Says |
| --- | --- |
| `gameplay/progression/plate_pieces.json` | every card and emblem: title, motif, palette, and a card's `side` or an emblem's `shape` |
| `gameplay/progression/unlocks.json` | the ladder's rows (`tier_card`, `tier_emblem`, `emblem`) with the level of each |
| `gameplay/challenges/data/feats.json` | the 21 lasting goals the night counts today, each with `grants` (`card:<id>`, `emblem:<id>`) |

A **feat** is a new challenge family (`ChallengeDef.Family.FEAT`): done once, says nothing on the way (only the finish
reaches the prompt), counted in total or in one night, and over several stats when it asks for "every weapon" (the lowest
of the listed stats is its progress). `test_plate_catalog` fails on a piece nothing gives, a piece given twice, a grant
with no art, a motif or a palette nobody has; `test_challenge_feats` pins the 21 and the stats they name. To add a piece
(#1071, #1073, #1074): a line in `plate_pieces.json` and a row in `unlocks.json` or a `grants` entry.

## The art

Pieces are composed from shared parts, not painted: `PlateMotifs` has 22 motifs of a few flat shapes each (ticket, reel,
car, saucer, marquee, skull, crosshair, ...), `PlatePalettes` 11 colour families of four roles, and `PlateCompose` puts
a motif on a card (ground, band with the title, bulbs, stripes) or in a badge (disc, ticket or hexagon). `CardArt` and
`EmblemArt` build the shapes when the piece or the size changes and draw them as **one command** (`HudShapes`), so a
card costs nothing after its first frame. The sheet of every piece is `tests/captures/plate_sheet.tscn`.

## How a card reaches every client

No client message carries one and the protocol stays 15:

1. The equip screen writes `equipped` (`card`, `emblem`) on the profile (`ProfileStore.equip`, queued like XP and sent by
   `ProfileUplink`, `PlateEquip`).
2. The backend signs `card`, `emblem` (plain names only) and `done` (the last 256 finished challenges, only when
   something is chosen) into the **ticket**, from the stored profile (`ProgressService.claimsFor`).
3. `TicketVerifier.account_of` reads them; `PlateTable` holds what the seat asked for to what it owns (the tier pieces
   by the level its XP gives, the challenge pieces by `done`) and drops the rest.
4. `account_seated` carries `card` and `emblem` to everyone, the WELCOME's `plates` to a late joiner; `HudState.plate_of`
   is what every part reads (a bot has none, nor has a seat with no account).

The lobby lists what a member **chose** (`card`, `emblem` on each member, from the profile the backend already reads
for the level); the night holds it to what they own, so a hand-edited profile shows a card in the lobby and none in
the night.

**Where a finish comes from.** A feat is a challenge like the others, so both trackers finish it: the client's
(`ProgressSession` marks `done` on the profile, solo) and the game server's (`ChallengeAward`, #1129: a `challenge_done`
event to every client and the id in the round report, which the backend writes to the profile's `done`). Nothing here
copies either. The equip screen reads the account's profile again when it opens (`ProfileUplink.read`), so a night with
friends shows its finishes there. A live "you earned a card" popup from `challenge_done` is not built (the event
carries the reward's XP, not the grants).

## The box (the maintainer's question)

`HudPlayerBox` puts the card behind the **whole points box** (the issue's reading: "calling cards ... next to their
names"). The points stay on the seat's armband colour on a tab that runs in from the right edge (`HudPointsTab`), so they
are exactly as readable as without a card; the name and the level are drawn over the card with an outline in the seat's
colour (`HudPlayerBox.HALO`), so every glyph sits on the colour its ink was chosen for. The order icon, level, gap, name
is untouched (a test compares the rectangles with and without a card). Turning it into "the card replaces the portrait"
is `HudPlayerBox._card`'s rectangle: `_box()` is the card's today, the portrait square would be `Vector2.ONE * height`.

A first version laid a veil of the seat's colour over the card and pulled any darker part toward it until the words had
4.5:1; the cards came out flat brown and the armband's colour was gone, so the tab and the outline replaced it.
Contrast with the seat's colour is held at 4.5 or more for every card, seat colour and downed state
(`test_plate_boxes`, the same ink the box always chose).

**Cost.** Per frame nothing: the card and emblem are retained draw commands, and `show_player` (every kill) compares
two ids and writes nothing when they are equal. Per join: a card builds about 60 shapes once (the clip against the
box's shape is `Geometry2D.intersect_polygons`). On the wire: two keys on one `account_seated` a join, and at most
256 short strings in a ticket. The HUD is one pass of the box's own `_draw` plus two small children.

## The unlock card

The popup card of an unlock (`PopupCard`, #1131) asks `LadderItem.of(slot, item)` for its picture and name, like the
wardrobe: a tier card is `Kind.CARD` ("Cartoon calling card", the card drawn by `PlateDraw` on a wider chip), a tier
emblem or the level 2 starting emblem `Kind.EMBLEM`, and the `calling_cards` row shows the first card. A piece the
plate does not have keeps the letter chip and the spelled id. `test_popup_thumbnails` runs over every available row.

## What is not here

- A live popup for a card or emblem earned (see above) and the client marking an online finish at once on its file.
- A local night (solo) never tells the HUD its player's level (no event seats the local account), so the player's own box
  shows no level and no card there; that needs `night.gd`, which is at the line limit.
- The hidden challenges, poster sets (#1073) and frames (#1071, #1072) are their own issues. The odd, easy and
  together challenges' stats were built in #1074 ([the stats](../design/progression.md#the-odd-and-together-stats)).

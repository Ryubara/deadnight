# Calling cards, emblems and frames (#1070, #1071)

What a player wears on their plate: a **calling card** (a 440 by 120 sheet, shown behind their name), an **emblem**
(a small badge after the name) and a **frame** (a border round the plate, [below](#frames)). The design is
[the plate](../design/progression.md#plate-calling-cards-emblems-and-frames); this page is how it is built and what
was measured.

## What is owned, and where it comes from

One gate per piece (progression rule 3): the ladder gives it at a level, or a challenge gives it, never both.
`PlateCatalog` joins the three files that say so and **derives** ownership from the level (from XP) and the finished
challenges (`Profile.done`), so nothing is stored twice and a retune needs no migration.

| File | Says |
| --- | --- |
| `gameplay/progression/plate_pieces.json` | every card, emblem and frame: title, palette, and a card's motif and `side`, an emblem's motif and `shape`, a frame's `style` |
| `gameplay/progression/unlocks.json` | the ladder's rows (`tier_card`, `tier_emblem`, `emblem`, `plate_frame`) with the level of each |
| `gameplay/challenges/data/feats.json` | the 24 lasting goals the night counts today, each with `grants` (`card:<id>`, `emblem:<id>`, `frame:<id>`) |

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
names"). The points stay on the seat's armband colour on a tab that runs in from the right edge (`HudPointsTab`), so
they are exactly as readable as without a card; the level and the name sit on a strip of the same colour
(`HudNameTab`) as long as they are, so every glyph is on the colour its ink was chosen for. The order icon, level, gap,
name is untouched (a test compares the rectangles with and without a card). Turning it into "the card replaces the
portrait" is `HudPlayerBox._card`'s rectangle: `_box()` is the card's today, the portrait square would be
`Vector2.ONE * height`.

A first version laid a veil of the seat's colour over the card and pulled any darker part toward it until the words had
4.5:1; the cards came out flat brown and the armband's colour was gone, so the tab and an outline in the seat's colour
replaced it (#1070). The outline was a ring about a pixel wide in a night on a phone and the words blurred into the
card, so #1189 replaced it with the strip and a heavier type where a unit is under 0.6 of a pixel. The pixels, the
numbers and what was not reachable are [Words over a card](plate-words-contrast.md). The design check (ink against the
seat's colour, `test_plate_boxes`) holds for every card, seat colour and downed state; the pixel check is
`test_plate_words`.

**Cost.** Per frame nothing: the card and emblem are retained draw commands, and `show_player` (every kill) compares
two ids and writes nothing when they are equal. Per join: a card builds about 60 shapes once (the clip against the
box's shape is `Geometry2D.intersect_polygons`). On the wire: two keys on one `account_seated` a join, and at most
256 short strings in a ticket. The HUD is one pass of the box's own `_draw` plus two small children.

## The unlock card

The popup card of an unlock (`PopupCard`, #1131) asks `LadderItem.of(slot, item)` for its picture and name, like the
wardrobe: a tier card is `Kind.CARD` ("Cartoon calling card", the card drawn by `PlateDraw` on a wider chip), a tier
emblem or the level 2 starting emblem `Kind.EMBLEM`, and the `calling_cards` row shows the first card. A piece the
plate does not have keeps the letter chip and the spelled id. `test_popup_thumbnails` runs over every available row.

## Frames

A frame is a border run just **inside** the outline of a plate: the points box of the HUD (its ticket shape), a roster
row (the scoreboard, the night report), a lobby seat, a swatch. It is composed like a card from shared parts:
`PlateFrames` has six styles (`double`, `rivets`, `glow`, `bulbs`, `holes`, `rope`), each a few bands and a row of dots
or dashes in the four colours of a palette, so another frame is a line of `plate_pieces.json` (`id`, `title`,
`palette`, `style`). `FrameArt` draws the ops as one command like the other plate art (`HudShapes`), and
`PlateDraw.frame` does it onto any canvas item (the unlock card's chip).

| Frame | From | Look |
| --- | --- | --- |
| Chrome, Brass, Neon, Gold | the ladder, levels 29, 37, 50, 55 (`plate_frame` rows, now `available`) | double bar, riveted bar, neon glow, marquee bulbs |
| Filmstrip | "Reach round 20" (`f_filmstrip`) | a dark strip with sprocket holes |
| Velvet Rope | "Get 25 teammates back on their feet" (`f_velvet_rope`) | a twisted cord |
| Searchlight | "Play 100 nights" (`f_searchlight`) | a cold glow |

**Only challenges the night counts.** The three challenge frames name stats the night produces today (`round`,
`revives`, `nights`); `test_plate_frames` fails on a frame whose challenge asks for a stat that is not in
`ChallengeStats.FIXED`. The "beat this map" frames (the maintainer's example) are #1072: they need extraction (#1056)
and, for "reach a round on a named map", a per-map stat the tally does not have (`NightTally` never learns the map).

**How it reaches everyone.** The same way as the card and the emblem, with a third key: `equipped.frame` on the profile,
`frame` in the ticket (the backend's `claimsFor`, and `knownLevel` for the lobby's list), `PlateTable` holds it to what
the seat owns (the ladder's by level, the challenge's by `done`), `account_seated` and the WELCOME's `plates` carry it,
and `HudState.plate_of` is what every part reads. The protocol stays 15.

**Where it is drawn.**

- `HudPlayerBox`: a `FrameArt` over the card and the tab, under the words, on the box's ticket outline (a downed seat
  dims it with the card). The border is at most 2.2 strokes deep and the box keeps 12 units of padding before its
  words, so nothing moves (a test compares the badge's rectangles and the number's end with and without).
- The scoreboard and the night report: `PlateRow.frame_over` puts a `FrameArt` last in the row's panel. A panel inset by
  padding would inset the frame with it, so the room at the right end is taken from the last cell and kept by a spacer
  (`PlateRow.clear_the_frame`); the lobby's seat takes the frame **outside** its inset rectangle (`FrameArt.grow`).
- The equip screen (`CardsScreen`): one tab for each kind (Calling cards, Emblems, Frames; a tab shows its page when it
  is pressed, so the pad's focus never switches a page by itself), each a grid of tiles; a frame tile is a swatch of a
  plate with the frame round it. The preview shows the frame outside the card, so it never covers the printed title.
- The unlock card of a frame's level (`PopupCard`, `LadderItem.Kind.FRAME`, caption "NEW FRAME").

**Width.** The stroke is `floor(height * 0.085)` clamped to 2 to 5 (`PlateFrames.width_for`): 2 on the compact box of a
party of five or more, 3 on a roster row, 4 on a teammate's box, 5 on your own. The first version used 3 to 4 on every
box and the compact one read as all border.

**A row made `available`.** The four `plate_frame` rows were flipped by this work, so the readers of `unlocks.json` were
listed first: `LadderUnlocks` (`earned_at`, `next_after`, `label_of`: "chrome frame"), `XpAward.crossing` and
`ProgressNews` (generic: they announce what `earned_at` says), `PopupLadder` (the caption and the cue were there),
`PopupCard` and `LadderItem` (the new `FRAME` kind: art, and the name "Chrome plate frame"), `NightReport` (the label),
the voice catalog (`plate_frame` already cheers like an emblem) and `LookCatalog` (reads only rows with a `part`).
`test_popup_thumbnails` runs over every available row and found nothing missing.

## What is not here

- A live popup for a card or emblem earned (see above) and the client marking an online finish at once on its file.
- A local night (solo) never tells the HUD its player's level (no event seats the local account), so the player's own box
  shows no level and no card there; that needs `night.gd`, which is at the line limit.
- The hidden challenges (#1172), poster sets (#1073) and the frames for beating a map (#1072) are their own
  issues. The odd, easy and together challenges' stats were built in #1074
  ([the stats](../design/progression.md#the-odd-and-together-stats)).

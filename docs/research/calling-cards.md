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
- The hidden challenges (#1172) and the frames for beating a map (#1072) are their own issues. The odd, easy and
  together challenges' stats were built in #1074 ([the stats](../design/progression.md#the-odd-and-together-stats)).
  Poster sets are [below](#poster-sets-1073).

## Poster sets (#1073)

[The design](../design/progression.md#poster-sets): six feats themed as a fake film, each one done uncovers a panel of
its poster, all six win a calling card and an emblem. The data is one file, `gameplay/challenges/data/poster_sets.json`
(id, title, the lines the poster prints, a palette and a motif, the six feat ids and `grants` in the same
`card:<id>` / `emblem:<id>` as a challenge's); `PosterSets` reads it and `PosterSet` is one set.

- **Nothing is stored.** A panel is uncovered when the board's `feats[id]` reached the target
  (`ChallengeProfile.feats_done`, so the Challenges tab reads the board and nothing else), a set is finished when its six
  are, and `PlateCatalog` gives the set's two pieces to anyone whose `Profile.done` holds all six
  (`owns` for a piece whose source is `{set}`). So the prize is granted once however often a board is read, the save
  round-trips with the board, the server's ticket check (`PlateTable`, which reads `done`) needs no change, and the
  protocol stays 15. `test_poster_sets` pins it.
- **What a set may list.** `PosterSets.problems` fails a set that names a challenge that is not a feat, one in two
  sets, a stat the night does not count (`ChallengeStats.is_known`) or one that needs a crowd (`revives`), a palette or
  a motif nobody has, or not six. The count was taken from the data before it was written down: 21 feats, so two sets
  of six use 12 and nine are left over; the design's "two sets of the 21" is that. Adding a set is a record in the
  file, two pieces in `plate_pieces.json` and a test count.
- **The art.** `PosterCompose` builds a 300 by 450 poster from the cards' own parts (`PlateShapes`, `PlateMotifs`,
  `PlatePalettes`): a ground, a sunburst of dark rays, stars, a hill, a disc of light, the set's large motif (a new `bolt`
  and the existing `crosshair`) and a band for the title, in the palette's four roles; `PosterArt` draws it as one
  command (`HudShapes`) and puts the title (display face) and a cover with its number over each panel not uncovered.
  The two sets are two palettes and two motifs. `tests/captures/poster_sets.tscn` draws the sheet.
- **The tab.** `ChallengesPanel` has a `Poster sets` chip (`Family.SETS`). `PosterSetView` is the whole set (the poster
  at 250 units, the title, how far it is as punches, the six numbered rows, "Finish the set" with the card and the
  emblem; on a phone the poster is 150 units beside the title and the rows go under it) and the teaser (a 56 unit
  poster, the title, the punches) that All shows after Today and that opens the chip when pressed. A view is a button
  so a pad walks it. Its height is computed from the fonts (`_height`): a container that holds a set is asked for its
  size before the set is in the tree, where a `MarginContainer` reports zero, and a `Button` never asks its children.
- **Telling a finish, once.** The set's finish is an event, `poster_set_done` (`PosterSets.event_of`):
    - *Online*, the game server's `ChallengeAward` adds it after the `challenge_done` of the sixth feat (the id is in
      `board.finished`, so it is said once), every client hears it, the popup lane shows it for its own player, and
      `SoldierVoice` cheers it as `poster_set` for everyone. `ChallengeSession` notes it in the ledger
      (`ProgressSeen.set_key`, `set:<id>`) as it hears it.
    - *Solo* (the rules run here, no server follows the board), `ChallengeSession` finds the set the finished feat
      completes in its own board and tells it as the same event to the client state (`event_received`), so the HUD,
      the voice and the night report hear it as they hear a game server's; the ledger is noted. Two feats of a set
      can finish on one event (both are on the board at the first): the session and the server's `ChallengeAward`
      each say a set once (`sets_told`); `test_poster_set_report_online` found the server telling it twice.
    - *In the menu*, `ProgressNews.finished_keys` lists a finished set among the finished challenges (`set:<id>`), so
      the read at sign-in tells a set the cache lacked (a night the server played, another machine) and not one the
      night showed live (the ledger) or one a solo night finished (the cache has it): `test_poster_sets` runs the three.
- **The cheer.** `poster_set` has weight 4 in `SoldierVoiceCatalog.CHEER_WEIGHT`, over `tier_up` (3) and over
  `challenge_done`, whose weight stays the maintainer's 2: the set arrives with the challenge that finished it and
  with the tier its XP may cross, and is the rarest thing a player does, so the one cheer a window says is the set's.
  The three takes already existed (#1063).
- **The card.** `PopupQueue.Kind.SET`: the poster (56 units), `POSTER SET DONE`, the title and the prize's card and
  emblem, with the tier card's chasing bulbs; it holds as long as a tier card, is as important as one when the queue
  overflows and sounds the card cue.
- **The night report.** `ReportTracker` keeps the sets the local player finished tonight (the event, once each) and
  `NightReport.compose` puts them in the model (`sets`, kept or unkept night alike). `HudNightReport` shows the first
  as a row under the level notes: its poster (30 units wide), the title, `WON: <card> + <emblem>`, and a line `+N MORE
  POSTER SETS` for the rest. The card is two lines of small type, so on a short phone-with-notch canvas
  (1872 by 864, safe height 840) the rows are at their floor and the `NEXT:` note is left out when a set is shown
  (`_drop_next`); `EndBoardFixtures.fullest_report` holds both sets and `test_end_board_fit` and
  `test_night_report_card` run it on every canvas. Online it is told by the server's event
  (`test_poster_set_report_online`, over a real `GameServer`: every client hears it once and only the finishing
  seat's report names it); solo by the session (`test_poster_sets`). The capture:
  `night_report_capture.tscn --set=N`.
- **The poster's pixels.** Covers are solid tiles (nothing of the picture or the title shows through), kept inside the
  frame with a hairline gap of the poster's dark between them; the panel lines are the covers' own edges, so none is
  drawn over the frame or a word, and the tagline is two pieces, one in each column (`THE DRIVE-IN`, `PRESENTS`).
  `test_poster_art_pixels` reads the picture back (the frame is the frame colour all round at 0 to 6 panels, a covered
  panel is one colour but for its number, covering panel 2 changes nothing in panel 1); it needs a renderer, so a
  headless run skips it: run it through `gds godot`.
- **Cost.** Per frame nothing: the poster and the prize are retained commands. A finish of a feat asks
  `PosterSets.completed_by` (a search of two sets); the 12 feats of the sets are checked only when they finish.

What is not here: a poster for the nine feats outside the sets, the poster's panels animating as they uncover (the
covers change on the next read of the board), and feats in the menu's news (a finished feat on its own is
not told by the menu; the set it completes is).

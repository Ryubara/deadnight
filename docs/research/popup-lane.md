# The popup lane

How the progression's cards (#1064) are built and what proves them. The design is
[Popups, motion and sound](../design/progression.md#popups-motion-and-sound); the events are `XpAward`'s
(`xp_gained`, `level_up`, `tier_up`, `unlock_earned`) and a finished challenge's `challenge_advanced`.

## The parts

| Part | Does |
| --- | --- |
| `PopupQueue` | The plain data and the clock: which card starts when, the three-at-most and eight-waiting limits, the merge into "N new items", the tier made of its level card, the drop, the stamp, the slide. Moved by `advance(delta)`, no `Tween`, so a test steps it by hand |
| `PopupCard` | One paper ticket. It draws itself once; the lane moves, fades and scales its icon from outside, so a card standing still costs no redraw |
| `PopupLane` | A `HudPart`: hears the events of the local player, makes the cards, plays their cues (`PopupLink` sends them to `Audio.play_ui`), follows the part above it |
| `PopupLadder` | The words of an item (slot caption, name), the next unlock of a level and the holes |
| `LadderItem` | What a row of `unlocks.json` is: its name and what to draw, read from the part registry, the cloth palette or `MapRegistry` (the wardrobe's own sources) |
| `MenuPopups` | The same lane in the router's layer for every menu screen; a night's screen sends it away (`set_night`) |

## What the lane does that a column cannot

- **It stands under whichever of the banner, the marquee and the boss bar is up, and eases to its place** (about a
  quarter second) when one comes or goes. Put in their column it jumped by the banner's height when the banner
  left.
- **It shows only what fits.** `PopupQueue.room` is the space from the lane's top to the box round the crosshair
  (`Hud.CENTRE_CLEAR`); a card that does not fit waits, one card always may stand, and a waiting card sends the oldest
  one away after `popup_min_show`. With the round banner up on the smallest canvas (1536 by 864) that is two cards;
  with a boss bar too, one.
- **It waits while the HUD is hidden** (the helicopter drop, #1057): the queue is blocked, nothing starts and nothing
  ages, and the cards are shown when the HUD comes back.

## The first-run touch hints (#1132)

`TouchHints` draws over the lane, so on a first run a level up read "DRAG TO LOOK" through its words. Two ways out were
weighed. Holding a card until the hint is gone ties the lane to the touch layer, delays progress by as long as a player
goes without a look drag (the hint is there until used, and a player who aims with auto-fire may never drag), and
leaves the cue waiting too. Moving the hint costs one rectangle: the lane's column is known from the safe area
(centre, `PopupCard.WIDTH` wide), so the look hint sits on the look area's side of it, and the stick's hint steps off
it where a small canvas puts it under the cards. The look hint also steps down, 8 units at a time, past a touch button
that climbs to its place on a short screen (2340 x 864). The look hint still may meet the top right feed and notices of
a night (rows that fade after seconds); the test measures it against the parts that always stand, as before.

## One source with the wardrobe

An unlock card shows the item's thumbnail and name as the wardrobe's grid does (#1131): `LadderItem.of(slot, item)`
finds the row, reads the part's label from `LookCatalog` (the cell's own title), a colour's from the cloth palette,
a map's from `MapRegistry` (the map whose `unlock_level` is the row's level), and the card draws `ItemIcons` (a
wearable), `ItemIcons.draw_chip` (a colour) or the map's preview on the cell's plate. A row with no art (a plate item)
keeps the letter chip and its id spelled out. `test_popup_thumbnails.gd` compares every announced row's name with the
wardrobe cell's title at level 55. A name too long for the card is cut by the label's ellipsis, never wider than the
card.

## Layout before the first frame

A column lays itself out a frame late: until it has, a part's rectangle is not where it will be (a banner 772 units
high, a column of width 0). The lane reads the rectangle of a part above it only once its column has a width, and the
tests wait a frame (`await_idle_frame`) before they measure or step a lane; the lane's own `_process` is switched off
in them so the frames they wait for do not also move it.

## What tells the menu's lane (#1130)

`MenuPopups.announce(events)` is called by the places that learn of progress while no night is up. Each one turns
what it learned into the events the night tells (`XpAward.crossing` makes the level, tier and unlock events for
both), so the cards are the night's cards.

| Source | Wired | How |
| --- | --- | --- |
| A profile read at sign-in at a higher level than the cache | yes | `ProfileUplink.adopt_and_tell`: the levels between the cache's (or the ledger's, if higher) and the account's |
| A finished challenge on the account's board that the cache lacks (#1124) | yes | `ChallengeUplink.sync_after_sign_in`: today's dailies, open and settled orders, ladders at their last step |
| The XP of a signed-in solo night (#1122, #1123) | nothing to wire | credited live and shown live in the night; the cache holds it, so the next read finds nothing new (a test pins it) |
| A brand-new player's first Solo account (#1122) | no | waits on the maintainer's decision |

**Never twice.** `ProgressSeen` (`user://progress_seen.json`, the account's highest level told and the finished
challenges a night's HUD showed) is written by the night's own HUD as it shows a card (`NightHudBinding` for a
level, `ChallengeHudLink` for a finish) and read when the account's data is read. A read tells only what is above the
cache and the ledger, and then empties the challenge part: the cache is the account's from then on. A cache that is
not this account's (a new machine, another account) is no baseline, so a first read tells nothing. What the menu
learns while a night is up waits (`MenuPopups` keeps it) and shows when the night's screen is gone.

**Proof from a real source.** `tests/net/test_menu_news_online.gd` runs the real backend: a returning Guest signs in
(`StartupSignIn`), the game server's report credits the account a level and the board gets a finished order, and the
cards show once. A client's own profile write is held to about 2 XP a second by the backend, so a test that needs a
high level credits it as a game server does (`/internal/matches/<id>/report`). `tests/captures/popup_news.gd` records
the same over the menu.

## Proof

`tests/ui/test_popup_queue.gd` (order, caps, merge, timings, drop, stamp, slide, blocked), `test_popup_lane.gd` (the
server's real events through `XpAward`, the words and order of a card, the setting, mouse filter, the HUD's wait, the
lane against every other part of the HUD and the crosshair at five canvases, with and without a boss bar, on the phone
layout and mirrored, and the touch hints against the cards at those canvases and both hands),
`tests/ui/test_menu_news.gd` and `tests/progression/test_progress_news.gd` (the menu's sources and the ledger), and the
captures `tests/captures/popup_menu.gd`, `popup_news.gd` and `popup_night.gd` (a game server night whose seat's account
earns XP the way a kill or a challenge reward does, the dead on screen) and `touch_hints_tour.gd --levelup` (a first run
on a phone with a level up).

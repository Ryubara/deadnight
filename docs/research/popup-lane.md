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
| `PopupLadder` | The words of an item (slot caption, name, swatch), the next unlock of a level and the holes |
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

## Layout before the first frame

A column lays itself out a frame late: until it has, a part's rectangle is not where it will be (a banner 772 units
high, a column of width 0). The lane reads the rectangle of a part above it only once its column has a width, and the
tests wait a frame (`await_idle_frame`) before they measure or step a lane; the lane's own `_process` is switched off
in them so the frames they wait for do not also move it.

## Proof

`tests/ui/test_popup_queue.gd` (order, caps, merge, timings, drop, stamp, slide, blocked), `test_popup_lane.gd` (the
server's real events through `XpAward`, the words and order of a card, the setting, mouse filter, the HUD's wait, the
lane against every other part of the HUD and the crosshair at five canvases, with and without a boss bar, on the phone
layout and mirrored, and the touch hints against the cards at those canvases and both hands), and the captures
`tests/captures/popup_menu.gd` and `popup_night.gd` (a game server night whose seat's account earns XP the way a kill or
a challenge reward does, the dead on screen) and `touch_hints_tour.gd --levelup` (a first run on a phone with a level
up).

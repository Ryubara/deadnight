# Progression: levels 1 to 55, icons, cards and popups

What we read and measured before planning the level system the maintainer asked for (issue #977, 2026-11-04):
levels 1 to 55 with an icon each, XP, unlocks of wearables, colours and maps, calling cards and emblems behind
challenges, a cosmetics grid with dark locked items, level-up popups and the level over each name. The plan is the
proposal given to the maintainer (it becomes a section of [Permanent progression](../design/progression.md) once
approved); this page is the evidence. Studied for understanding only: no name, icon, card or emblem of another game is
used here or in the plan.

The design page already holds an earlier plan (Billing 1 to 50, mastery, stubs, orders) of which only the challenge
board is built ([Challenges](challenges.md)). What stands from it: its ten rules (a night resets, unlocks widen and
never raise, the server awards, nothing waits on the backend). What the 2026-11-04 request changes is listed in the
proposal.

## How we searched, and what we could not read

Web search and page fetches, 2026-11-03. Many pages refused the fetch tool or came back as search summaries; those
rows say *summary*. Vendor blogs and forum threads are named as such. The psychology papers were read in abstract and
secondary summaries, not in full; where a number from a blog could not be traced to the paper it is left out. Where
there was no source, the row says *our reading*.

## What a level ladder does in this genre

| Part | What it does for the player | What we found | Take |
| --- | --- | --- | --- |
| A number with an icon per level | A glanceable sign of time put in, shown next to the name | The request names the shooter genre's icon-per-level ladder as its model. No sourced study of why the icon matters; guides treat calling cards as "badges of honor that show a player's dedication" ([Prima Games](https://primagames.com/tips/how-to-get-calling-cards-call-of-duty-modern-warfare), [Upcomer](https://upcomer.com/how-to-unlock-all-calling-cards-in-call-of-duty-modern-warfare-2), *summary*) | The icon is the flex: it has to read at a glance at 24 px, so it is a silhouette first and a detail second |
| Calling cards and emblems from challenges | A wide banner and a small badge, mostly earned by weapon and mode challenges, with the rarest behind mastery | Hundreds exist in one release; Black Ops 6 was said to carry over 450 cards, some of them with *hidden* unlock criteria and animated "100 percent" cards ([Windows Central](https://www.windowscentral.com/gaming/here-are-all-of-the-call-of-duty-black-ops-7-dark-ops-challenges-and-the-rewards-you-can-get), [GGRecon](https://www.ggrecon.com/guides/mw2-calling-cards-how-to-get/), *summary*). One report of a glitch that granted every emblem in the database shows how much weight the client gives them ([Prima Games](https://primagames.com/?p=78288), *summary*) | A card per challenge family, a few hidden; fewer, better drawn pieces rather than hundreds; the grant is the server's, not the client's |
| Reset for a reward (prestige) | Starts the climb again, for a badge or a perk | Already weighed in the [design page's table](../design/progression.md#what-the-research-says): Payday 2's infamy read as artificial length, Deep Rock's promotion opening new content was accepted | No reset; the ladder keeps going past the cap without taking anything |
| Mastery by weapon | A second ladder for what you already like | Same table: long grinds, bugs | Left to its own later issue |
| Daily and weekly tasks | Small goals that decide what to do tonight | [Challenges](challenges.md) | Built; the new cards and emblems are what they reward |

## Incremental games: prestige and frequent small rewards

- **Prestige is a pacing tool as much as a reward.** Anthony Pecorella, in *The Math of Idle Games, Part III*, gives it
  two jobs: it creates the "ladder climbing" effect that makes idle games compelling, and it "reins growth back into a
  more manageable number" so progress and upgrades can be tied to a steadier figure. The bonus can come from max
  earnings, lifetime earnings, earnings since the last reset or upgrades bought, each with its own incentive to wait or
  to repeat ([Game Developer](https://www.gamedeveloper.com/design/the-math-of-idle-games-part-iii)). Our ladder has a
  cap and no resetting number to tame, so the main reason for the reset is absent.
- **Many small rewards, no failure state.** The genre gives frequent small achievements, clear goals and steady
  progress without a way to lose it ([Wikipedia](https://en.wikipedia.org/wiki/Incremental_game)). Our take: a level is
  one such step, so the first levels come within a night and a night that fails still pays.
- **The "sweet spot" claim** (prestige is most efficient at some interval, too early or too late wastes) is from one
  forum post (*anecdotal*) and is not relied on.

## The psychology, and where it is thin

| Effect | Source | What it says | How we use it | Limit |
| --- | --- | --- | --- | --- |
| **Goal gradient** | Kivetz, Urminsky and Zheng, *The goal-gradient hypothesis resurrected*, Journal of Marketing Research 2006 ([abstract](https://business.columbia.edu/faculty/research/goal-gradient-hypothesis-resurrected-purchase-acceleration-illusionary-goal)) | Effort speeds up as a goal gets nearer: coffee-card holders bought faster toward the free drink; online raters returned sooner toward a reward | Always show the *next* thing and how near it is (the bar and "next: a lanyard at 19"); a level's bar is visible on the plate and in the night report | Vendor blogs add numbers the paper does not give; only the finding is used |
| **Endowed progress** | Nunes and Drèze, Journal of Consumer Research 2006 ([Wharton summary](https://knowledge.wharton.upenn.edu/?p=5630)) | A task presented as already begun is finished more often: a car-wash card with 2 of 10 stamps pre-filled was redeemed more than a blank 8-stamp card (reported 34 percent against 19; *summary*) | The first night pays an opening bonus, so a new player's first bar is not empty and level 2 comes within the first night. The bonus has a reason, as the paper found it must: "your ticket is punched on the way in" | The effect needs a believable reason; a free bar with no reason is the dark pattern |
| **Variable reward** | Loot boxes use a variable-ratio schedule, the one gambling uses ([Zendle and Cairns 2018](https://www.massey.ac.nz/about/news/videogame-loot-boxes-similar-to-gambling/), summary; Drummond and Sauer 2018 for the structure) | The surprise of *when* a reward comes holds attention; the same schedule has a documented association with problem gambling (direction not established) | None of ours is chance. The surprise is in *what a challenge asks* (odd ones) and in cards with hidden criteria: a surprise of discovery, not of luck. No random unlock, no packs | The association was found in loot-box *spending*; ours has no spending, but a hidden reward that is gated by luck would still be a slot machine |
| **Autonomy, competence, relatedness** | Ryan, Rigby and Przybylski 2006, and Przybylski, Rigby and Ryan, *A motivational model of video game engagement*, Review of General Psychology 2010 ([abstract](https://journals.sagepub.com/doi/10.1037/a0019440)) | The three needs each independently predict enjoyment and continued play | Autonomy: choices (what to wear, which card to show). Competence: the ladder and the cards. Relatedness: the level over a teammate's head and the plate in the lobby. A number going up alone covers only one | The papers are about need satisfaction, not about levels in particular |
| **Social display** | Lehdonvirta, *Virtual Consumption*, 2009 ([thesis](https://utupub.fi/bitstream/handle/10024/98536/Ae11_2009lehdonvirta.pdf), summary) | People value virtual goods as markers of status and identity and for social activities with friends, for the reasons they value material goods | The things a player can show (the icon, the card, the emblem, the wardrobe) are the reward; they need an audience: the name tag, the lobby plate, the night report | A display that ranks players invites comparison; a friend lobby is the common case here, so we show, we do not sort |
| **Collection** | *Our reading*; no source found | A grid with dark slots invites filling | The wardrobe's grid, a costume as a set of pieces | Completion for its own sake is a grind: sets are small (five pieces) |

## Where the ethical lines are

Zagal, Björk and Lewis, *Dark Patterns in the Design of Games* (Foundations of Digital Games 2013), define dark game
design patterns as "those elements of a game's design whose purpose can be argued as questionable and perhaps even
unethical" and group them as temporal (grinding, appointment play), monetary (pay to skip, pay to win) and social (a
pyramid scheme, where progress needs invited friends); a critique says its ethics are not drawn from an explicit
framework ([abstract](https://www.deceptive.design/articles/dark-patterns-in-the-design-of-games), [Chalmers
record](https://research.chalmers.se/en/publication/177148), *summary*; the paper itself refused our fetch). Streaks are
the temptation that is closest to a ladder: a counter that rewards presence turns pride into obligation, and critics
say it should have recovery built in ([Yu-kai Chou](https://yukaichou.com/gamification-analysis/streak-design-gamification-motivation-burnout/),
*summary*; the 40 percent figures around Duolingo are unsourced blog claims and are not used).

What that gives, on top of the design page's [ten rules](../design/progression.md#rules-we-hold-ourselves-to):

| # | Rule for this system | Because |
| --- | --- | --- |
| 11 | **Nothing is for sale, now or as a plan.** No currency bought with money, no pass, no pack | Monetary dark patterns; the first question the maintainer has not been asked, so the system works with the answer "no" |
| 12 | **Every grant is a named thing earned by a stated act.** No random unlock, no "mystery" reward | Variable-ratio schedules |
| 13 | **No streak, no login reward, no timer on anything lasting.** A returning player loses nothing; rested XP is a gift, never a bar that drains | Temporal patterns; Chou's critique |
| 14 | **A level never locks a person out of a friend's night.** The host's unlocks set the lot; a guest's level is shown, never asked | Social pyramid; "level never sorts people" (rule 8) |
| 15 | **A challenge the night cannot count is not offered.** Each has a stat the night already counts or an event added with it | The Helldivers lesson in [Challenges](challenges.md): a bar is trusted only if exact |
| 16 | **Every popup can be turned down** (all, big ones only, off) and every cue has a picture; nothing is sound-only | [Challenges](challenges.md#toasts-and-prompts-in-a-fast-game), accessibility sources there |
| 17 | **The level can be hidden by whoever looks.** A setting hides everyone's levels on the viewer's own screen | A new player facing a "55" over every head is the opposite of the welcome we want (*our reading*) |

## Popups and their sound

- **Placement and queueing are covered in [Challenges](challenges.md#toasts-and-prompts-in-a-fast-game)** (batch like
  events, queue, cap, a setting). Toast systems in engines stack by pushing older ones aside and collapsing the stack
  when one expires, with a queue that rejects duplicates and overflow ([Godot toast add-on docs](https://ss-docs-gameforge.pages.dev/en/addons/toast),
  [a notification queue](https://docs.rs/ftui-widgets/latest/src/ftui_widgets/notification_queue.rs.html), both
  *summary* and implementation notes, not studies).
- **Sound: short, rising, scaled to the event.** The practical sources (sound-library vendors and an indie guide, so
  weak evidence) agree on four habits: most interface cues under 500 ms; a rising pitch with consonant intervals and a
  clean ending reads as progress; a big milestone earns a longer, fuller cue than a small one; cap repetition and give
  a volume control ([Morphic](https://morphic.com/resources/sounds/level-up-sound-effects), [Game Juice](https://gamejuice.pages.dev/articles/ui-audio-silent-interfaces),
  [a reward-loop guide](https://mtgarena.pro/info/sound-design-secrets-that-supercharge-reward-loops-in-games), all
  *summary*). **No source covered cues tiered by rarity or the overlap of a stack of sounds**; those numbers are ours,
  to be tuned by analysis (peaks, loudness, spectra) and listening.
- **We already have a sound language.** [Menu sounds](menu-sfx.md) has five weights (hint, move, press, commit,
  moment), one bus under the game's loud sounds and recipes made by synthesis with a ticket punch, a rip and soft
  chimes ([`challenge_recipes.py`](https://github.com/Ryubara/deadnight/blob/main/tools/audio/challenge_recipes.py)).
  A level-up is a *moment*, an unlock a *commit*; the new cues are recipes in the same family, not a new style.

## Feeling hand-made

There is little rigorous evidence here: the sources are practitioner talks and vendor blogs, and one forum comment
says a generic card layout "looks like a generic app". What we can ground:

- **Layered feedback is what makes a small action feel good** (Jonasson and Purho, *Juice It or Lose It*, 2012: the
  same block-breaker with colour, easing, particles, shake and sound added one at a time; [GDC Vault](https://gdcvault.com/play/1016487/Juice-It-or-Lose),
  *summary*), and a counter-talk argues it can cost immersion. So each popup has a few layers (a drop with a small
  overshoot, a stamp, a chime) and no more.
- **A UI that belongs to its world** beats a generic overlay (design guides; a minimalist-UI article warns that a
  cryptic over-designed diegetic UI is worse than a clean plain one; vendor blogs, *anecdotal*).
- **Our own list**, from the [UI look rules](../design/style.md#ui-look) and the maintainer's corrections (the voice
  lines that "sound a bit robotic": write it as a person who works there would say it):
  1. **Every thing has a noun from the drive-in and a voice.** Levels are *billings*, the grid is *the wardrobe*, a
     card is a *one-sheet*, the popup is a *ticket punched*; no "Congratulations", no "Achievement unlocked".
  2. **Hand-picked, never generated, glyphs.** Fifty-five named drawings, each a real object (stub, popcorn box, key,
     reel, torch, clapper, saucer, projector, searchlight); a tier is a frame and a colour, not a procedural recolour.
  3. **Uneven on purpose.** Big numerals and small captions, a left margin, paper that is cream with a perforation, a hard
     offset shadow; no glass, no glow on everything, no pill buttons.
  4. **Restraint in motion.** One motion language (drop, stamp, slide up), the same easing everywhere, reduced motion
     fades.
  5. **Specific copy.** "Rolled sleeves: reach level 4", "Last car out", "Won the night with the lights off": a title
     is a small joke or a fact, never a category name.
  6. **A name a player would say.** Card titles are checked by reading aloud (the voice-line check).

## What the simulator measured

The curve is a function of XP, and the XP per night comes from the [balance simulator](balance-simulator.md): 150
seeded nights per cell, seed 4000, the real rules and weapons, bots of three skills in teams of one, two and four, and
the back rooms. A night's XP is 20 per round reached (10 past round 20) plus 1 per 100 points earned, plus a one-off
300 for the first night ever; time per night is the simulator's round clock plus 5 s breaks, a 12 s intro and 120 s of
menus between nights (the design page's own assumption).

| Cell (nights only) | Rounds | XP a night | Minutes a night with menus | XP an hour |
| --- | ---: | ---: | ---: | ---: |
| Weak, solo | 5.5 | 149 | 5.4 | 1,642 |
| Average, solo | 11.4 | 389 | 10.7 | 2,189 |
| Average, two | 13.3 | 430 | 13.1 | 1,967 |
| Average, four | 15.3 | 494 | 17.0 | 1,745 |
| Strong, solo | 16.1 | 641 | 16.1 | 2,397 |
| Strong, four | 20.2 | 743 | 24.0 | 1,855 |
| Average, solo, the back rooms | 14.1 | 518 | 13.3 | 2,345 |

![Hours to each level for four cells](progression-curve.png)

- **XP per hour is nearly flat across skill and team size** (1,640 to 2,400): a weak player's nights are short, and a
  four-player night is long, so the level a player has says how long they have played, not how well. That is the
  intended reading of a number shown over every head. Level 55 comes after about 22 hours for a strong solo player,
  24 for an average one, 30 for an average four and 32 for a weak solo one. Level 10, the second map, comes after
  1.1 to 1.6 hours: three to seventeen nights (seven for the average solo player).
- **The model leaves out** boards, doors, fuel cans, bosses and the challenges (about 15 percent more on a three-night
  day if the three dailies are finished), so every time above is an upper bound for a player who does those things.
  Bots are not people: the curve is meant to be retuned from the first real nights' telemetry.

## The icon pipeline

![Sample level icons](progression-icons.png)

*Twelve of the 55 icons: a frame by tier, a glyph by level, five bulbs for the level inside the tier. Drawn as SVG, in
[`progression-icons/`](https://github.com/Ryubara/deadnight/tree/main/docs/research/progression-icons).*

- **Godot rasterises SVG without a window.** `Image.load_svg_from_string(svg, scale)` in a `--headless -s` script
  gave a PNG per file (the 12 here, in 3 s). It draws shapes, strokes, gradients and clip paths, and **draws no `<text>`**
  (a test svg's text produced no pixels), so a number is never baked into an icon: the game draws it. The tag shows the
  icon and the number as two things.
- **At 24 px only the frame and a silhouette survive**: the bulbs and the stub's lines vanish (see the sheet's last
  row). Each glyph is therefore chosen for a clear outline and a colour that differs from its neighbours'.
- **One atlas for the tags.** Names over heads can be eight at once; one atlas texture keeps them in one batch on the
  web build. The source stays one SVG per icon.

## Sources, and what we could not read

Everything linked above. Not read in full: the two 2006 papers (abstracts and secondary summaries), Zagal et al. 2013
(fetch refused), Lehdonvirta's thesis (table of contents and abstracts), the CoD guides (search summaries). No source
was found for: how long a level-up popup should stay, how tiers of reward sounds should differ, a measured effect of an
icon per level, or whether players read AI-looking UI as worse. Those numbers are ours and move by capture and play.

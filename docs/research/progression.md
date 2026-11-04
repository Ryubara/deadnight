# Progression: levels 1 to 55, icons, cards and popups

What we read and measured before planning the level system the maintainer asked for (issue #977, 2026-11-04): levels 1
to 55 with an icon each, XP, unlocks of wearables, colours and maps, calling cards and emblems behind challenges, a
cosmetics grid with dark locked items, level-up popups and the level over each name. The plan is the approved
[Permanent progression](../design/progression.md) page (the maintainer's answers of the same day changed it: see its
[decisions](../design/progression.md#decisions)); this page is the evidence. Studied for understanding only: no name,
icon, card or emblem of another game is used here or in the plan.

The design page held an earlier plan (Billing 1 to 50, mastery, stubs, orders) of which only the challenge board is
built ([Challenges](challenges.md)); the approved plan replaces Billing with the ladder of 55 and lists what changed
([what changed](../design/progression.md#what-changed-from-the-earlier-plan)). What stands from the earlier plan: its
ten rules, some of them changed by the maintainer (a night resets, the server awards, nothing waits on the backend).

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
| Reset for a reward (prestige) | Starts the climb again, for a badge or a perk | Already weighed in the [design page's table](../design/progression.md#what-the-research-says): Payday 2's infamy read as artificial length, Deep Rock's promotion opening new content was accepted | **Superseded:** the maintainer wants a prestige that costs something ("a loss just for flex value") with exclusive rewards; what resets is open (#1055). The ladder keeps going past the cap without taking anything until then |
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
record](https://research.chalmers.se/en/publication/177148), *summary*; the paper itself refused our fetch). Streaks
are the temptation that is closest to a ladder: a counter that rewards presence turns pride into obligation, and
critics say it should have recovery built in ([Yu-kai
Chou](https://yukaichou.com/gamification-analysis/streak-design-gamification-motivation-burnout/), *summary*; the 40
percent figures around Duolingo are unsourced blog claims and are not used).

What that gives, on top of the design page's [ten rules](../design/progression.md#rules-we-hold-ourselves-to):

| # | Rule for this system | Because |
| --- | --- | --- |
| 11 | **Nothing is for sale, now or as a plan.** No currency bought with money, no pass, no pack | Monetary dark patterns; the first question the maintainer has not been asked, so the system works with the answer "no" |
| 12 | **Every grant is a named thing earned by a stated act.** No random unlock, no "mystery" reward | Variable-ratio schedules |
| 13 | **No streak, no login reward, no timer on anything lasting.** A returning player loses nothing (the maintainer dropped rested XP; the first game of the day pays a small bonus for finishing a round, never for logging in) | Temporal patterns; Chou's critique |
| 14 | **A level never locks a person out of a friend's night.** The host's unlocks set the lot; a guest's level is shown, never asked | Social pyramid; "level never sorts people" (rule 8) |
| 15 | **A challenge the night cannot count is not offered.** Each has a stat the night already counts or an event added with it | The Helldivers lesson in [Challenges](challenges.md): a bar is trusted only if exact |
| 16 | **Every popup can be turned down** (all, big ones only, off) and every cue has a picture; nothing is sound-only | [Challenges](challenges.md#toasts-and-prompts-in-a-fast-game), accessibility sources there |
| 17 | **The level can be hidden by whoever looks.** A setting hides everyone's levels on the viewer's own screen | A new player facing a "55" over every head is the opposite of the welcome we want (*our reading*) |

## Popups and their sound

- **Placement and queueing are covered in [Challenges](challenges.md#toasts-and-prompts-in-a-fast-game)** (batch like
  events, queue, cap, a setting). Toast systems in engines stack by pushing older ones aside and collapsing the stack
  when one expires, with a queue that rejects duplicates and overflow ([Godot toast add-on
  docs](https://ss-docs-gameforge.pages.dev/en/addons/toast), [a notification
  queue](https://docs.rs/ftui-widgets/latest/src/ftui_widgets/notification_queue.rs.html), both *summary* and
  implementation notes, not studies).
- **Sound: short, rising, scaled to the event.** The practical sources (sound-library vendors and an indie guide, so
  weak evidence) agree on four habits: most interface cues under 500 ms; a rising pitch with consonant intervals and a
  clean ending reads as progress; a big milestone earns a longer, fuller cue than a small one; cap repetition and give
  a volume control ([Morphic](https://morphic.com/resources/sounds/level-up-sound-effects), [Game
  Juice](https://gamejuice.pages.dev/articles/ui-audio-silent-interfaces), [a reward-loop
  guide](https://mtgarena.pro/info/sound-design-secrets-that-supercharge-reward-loops-in-games), all *summary*). **No
  source covered cues tiered by rarity or the overlap of a stack of sounds**; those numbers are ours, to be tuned by
  analysis (peaks, loudness, spectra) and listening.
- **We already have a sound language.** [Menu sounds](menu-sfx.md) has five weights (hint, move, press, commit,
  moment), one bus under the game's loud sounds and recipes made by synthesis with a ticket punch, a rip and soft
  chimes ([`challenge_recipes.py`](https://github.com/Ryubara/deadnight/blob/main/tools/audio/challenge_recipes.py)).
  A level-up is a *moment*, an unlock a *commit*; the new cues are recipes in the same family, not a new style.

## Feeling hand-made

There is little rigorous evidence here: the sources are practitioner talks and vendor blogs, and one forum comment
says a generic card layout "looks like a generic app". What we can ground:

- **Layered feedback is what makes a small action feel good** (Jonasson and Purho, *Juice It or Lose It*, 2012: the
  same block-breaker with colour, easing, particles, shake and sound added one at a time; [GDC
  Vault](https://gdcvault.com/play/1016487/Juice-It-or-Lose), *summary*), and a counter-talk argues it can cost
  immersion. So each popup has a few layers (a drop with a small overshoot, a stamp, a chime) and no more.
- **A UI that belongs to its world** beats a generic overlay (design guides; a minimalist-UI article warns that a
  cryptic over-designed diegetic UI is worse than a clean plain one; vendor blogs, *anecdotal*).
- **Our own list**, from the [UI look rules](../design/style.md#ui-look) and the maintainer's corrections (the voice
  lines that "sound a bit robotic": write it as a person who works there would say it):
  1. **Every thing has a noun from the drive-in and a voice.** Levels are *billings*, the grid is *the wardrobe*, a
     card is a *one-sheet*, the popup is a *ticket punched*; no "Congratulations", no "Achievement unlocked".
  2. **Hand-picked, never generated, glyphs.** Fifty-five named drawings, each a real object (stub, popcorn box, key,
     reel, torch, clapper, saucer, projector, searchlight); a tier is a frame and a colour, not a procedural recolour.
  3. **Uneven on purpose.** Big numerals and small captions, a left margin, paper that is cream with a perforation, a
     hard offset shadow; no glass, no glow on everything, no pill buttons.
  4. **Restraint in motion.** One motion language (drop, stamp, slide up), the same easing everywhere, reduced motion
     fades.
  5. **Specific copy.** "Rolled sleeves: reach level 4", "Last car out", "Won the night with the lights off": a title
     is a small joke or a fact, never a category name.
  6. **A name a player would say.** Card titles are checked by reading aloud (the voice-line check).

## What the simulator measured

The curve is a function of XP, and the XP per night comes from the [balance simulator](balance-simulator.md): 150
seeded nights per cell, seed 4000, the real rules and weapons, bots of three skills in teams of one, two and four. A
night's XP is 20 per round reached (10 past round 20) plus 1 per 100 points earned; time per night is the simulator's
round clock plus 5 s breaks, a 12 s intro and 120 s of menus between nights (the design page's own assumption).

The first measurement (nights at count 1 only, for a plan of 22 to 32 hours) was replaced the same day by the next one,
for the maintainer's pace of about eight hours.

### The 8-hour curve, measured

The maintainer asked for about eight hours ("Maybe 8 hours of playtime. Gotta make it short"), assumed **300 or more
kills a game** (modifiers raise the count), and wanted the climb to **scale upward** ("it takes longer to level up the
higher you go ... so users can feel the first level up satisfaction early on"). So the cells were run again at **count
multipliers 1, 2 and 5** (the match setting `count_multiplier`; the command-line tool took `--count` for the run, an
unchanged copy of `balance_cli.gd` with one added line, not committed), 18 cells in all. A night's XP is as above, so
a kill is its points over 100:

| Cell | Count | Rounds | Kills a night (all) | Kills a player | XP a night | Minutes a night with menus | XP an hour |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Weak, solo | 1 | 5.2 | 38 | 38 | 146 | 5.5 | 1,603 |
| Weak, solo | 2 | 2.1 | 16 | 16 | 57 | 3.6 | 957 |
| Weak, solo | 5 | 1.0 | 7 | 7 | 27 | 2.8 | 569 |
| Average, solo | 1 | 10.0 | 122 | 122 | 337 | 9.5 | 2,123 |
| Average, solo | 2 | 5.3 | 65 | 65 | 161 | 5.7 | 1,703 |
| Average, solo | 5 | 1.3 | 20 | 20 | 44 | 3.2 | 844 |
| Strong, solo | 1 | 15.5 | 290 | 290 | 614 | 15.9 | 2,316 |
| Strong, solo | 2 | 7.6 | 122 | 122 | 250 | 7.5 | 2,010 |
| Strong, solo | 5 | 2.8 | 77 | 77 | 123 | 4.4 | 1,683 |
| Average, two | 1 | 12.4 | 278 | 139 | 391 | 12.1 | 1,942 |
| Average, two | 2 | 7.4 | 207 | 103 | 242 | 7.5 | 1,929 |
| Average, two | 5 | 1.9 | 52 | 26 | 61 | 3.5 | 1,036 |
| Average, four | 1 | 14.8 | 682 | 171 | 472 | 16.3 | 1,739 |
| Average, four | 2 | 8.7 | 466 | 117 | 280 | 9.0 | 1,868 |
| Average, four | 5 | 2.3 | 140 | 35 | 76 | 3.9 | 1,171 |
| Strong, four | 1 | 20.7 | 1410 | 353 | 766 | 24.9 | 1,842 |
| Strong, four | 2 | 11.8 | 898 | 225 | 442 | 12.3 | 2,165 |
| Strong, four | 5 | 5.3 | 508 | 127 | 211 | 6.5 | 1,948 |

- **A count multiplier does not raise XP an hour here.** The simulator's bots die earlier under a horde (an average
  solo night ends in round 1 or 2 at x5), so nights are short and the 120 s of menus dominate: 570 to 1,950 XP an hour
  at x5 against 1,600 to 2,320 at x1. A horde modifier is not a way to level faster, in the model; with people the
  answer may differ.
- **The cells with 300 or more kills a night** (strong solo at x1; average two and four players and strong four at x1
  and x2; strong four at x5) pay **1,740 to 2,320 XP an hour, 1,970 on average**. The lines the model leaves out
  (boards, doors, cans, bosses, the dailies and the first game of the day) add about 15 percent, which is about 2,300
  an hour. Eight hours at that is about 18,000 XP.
- **The table that was chosen** (85 XP to leave a level for levels 1 to 5, rising each tier to 590 for 51 to
  54; **18,010 XP to level 55**; the shape is the first plan's 250 to 1,750 scaled by a third, so it still rises 7
  times):

| Level | XP to reach | Weak, solo x1 | Average, solo x1 | Strong, solo x1 | Average, four x1 | Strong, four x5 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | 85 | 1 min | 1 min | 1 min | 1 min | 1 min |
| 5 | 340 | 11 min | 8 min | 8 min | 10 min | 9 min |
| 10 | 965 | 34 min | 26 min | 24 min | 32 min | 28 min |
| 15 | 1,840 | 67 min | 51 min | 46 min | 62 min | 55 min |
| 20 | 2,965 | 1.8 h | 82 min | 76 min | 1.7 h | 90 min |
| 25 | 4,360 | 2.7 h | 2.0 h | 1.9 h | 2.5 h | 2.2 h |
| 30 | 6,010 | 3.7 h | 2.8 h | 2.6 h | 3.4 h | 3.1 h |
| 40 | 10,060 | 6.2 h | 4.7 h | 4.3 h | 5.8 h | 5.1 h |
| 50 | 15,110 | 9.4 h | 7.1 h | 6.5 h | 8.7 h | 7.7 h |
| 55 | 18,010 | 11.2 h | 8.5 h | 7.8 h | 10.3 h | 9.2 h |

![Hours to each level](progression-curve.png)

- **The climb rises: the first level takes about a minute, the last 15 to 22 minutes** (590 XP at 2,000 XP an hour),
  seven times longer. Reading only the average (8 hours over 54 levels is 9 minutes a level) would hide that.
- **Level 10, the second map, arrives after 24 to 34 minutes**: 1.5 to 6.3 nights, 2.7 for the average solo player. It
  is under half an hour for the average and strong cells, so the maintainer is told; moving the map to level 12 or 15
  (35 or 50 minutes) is one number.
- Level 55 comes after 7.8 hours for the strong solo cell, 8.5 for the average, 10.3 for the average four and 11.2 for
  the weak solo one, nights only; with the lines the model leaves out about 13 percent less.
- XP per hour is nearly flat across skill and team size at count 1 (1,600 to 2,300), so the level says how long a
  player has played more than how well. Bots are not people: the curve is meant to be retuned from the first real
  nights.
- **The live XP stress** is not measured here (nothing is built): the cells give the scale, about 0.2 to 1.9 kills a
  second across a team on average (a strong four at x5), and the server-XP issue (#1059) measures the real server at x5.

### The first measurement (superseded)

For a plan of 53,250 XP: level 55 after 22 to 32 hours and level 10 after 1.1 to 1.6 hours, from the same simulator at
count 1 with the earlier build of the rules. Kept for the method only.

## The icon pipeline

![Sample level icons](progression-icons.png)

*Twelve of the 55 icons: a frame by tier, a glyph by level, five bulbs for the level inside the tier. Drawn as SVG, in
[`progression-icons/`](https://github.com/Ryubara/deadnight/tree/main/docs/research/progression-icons).*

- **Godot rasterises SVG without a window.** `Image.load_svg_from_string(svg, scale)` in a `--headless -s` script gave
  a PNG per file (the 12 here, in 3 s). It draws shapes, strokes, gradients and clip paths, and **draws no `<text>`**
  (a test svg's text produced no pixels), so a number is never baked into an icon: the game draws it. The tag shows
  the icon and the number as two things.
- **At 24 px only the frame and a silhouette survive**: the bulbs and the stub's lines vanish (see the sheet's last
  row). Each glyph is therefore chosen for a clear outline and a colour that differs from its neighbours'.
- **One atlas for the tags.** Names over heads can be eight at once; one atlas texture keeps them in one batch on the
  web build. The source stays one SVG per icon.

### The ladder as built (#1060)

![The whole ladder at 128 px](progression-icon-ladder.png)

*The 55 icons from the 128 px atlas, a column a tier, drawn in the game by `LevelIcons`
(`game/tools/captures/level_tags.tscn`). Original drawings; none is traced from any game.*

| Step | Where | What it does |
| --- | --- | --- |
| Draw | `tools/level_icons/draw_icons.py` | One function a drawing, the frames, the tier colours; writes the SVGs (standard library) |
| Source | `game/assets/ui/levels/level_NN.svg` | 128 x 128, shapes and strokes, no `<text>`; a `<title>` (the working name) and a `<desc>` (the tier). The folder has a `.gdignore`: nothing the game ships reads them, and 55 more textures would only grow the pack |
| Export | `game/tools/art/export_level_icons.gd` | `Image.load_svg_from_string` at each cell size, no window: `level_icons_64.png`, `level_icons_128.png` and `level_icons.json` in `game/assets/ui/level_atlas/`, a column per level in the tier, a row per tier |
| Read | `LevelIcons` | `atlas(cell)`, `region(level, cell)`, `texture(level, cell)` (a shared `AtlasTexture`), `tier(level)` |
| Check | `tools/check_level_icons.py` (CI, pre-commit) | The manifest holds a hash of every SVG and atlas, so an SVG changed without an export fails with no Godot and no raster compared across machines; so does an atlas changed by hand, and an SVG edited by hand that the script would overwrite |

To change a drawing: edit its function, run the script, run the export, import once, and commit all of it.

- **Frames:** ticket, token, sign in turn, a colour each, so that no two tiers of one shape share a colour: tickets
  cream, tan, green, pink; tokens sky, silver, violet, gold on red; signs copper, periwinkle, teal.
- **A drawing keeps to its plate.** It sits in a 100 x 100 box at 0.8, outlined 4.5 in the ink `#1c1730`, with two to
  four colours; light (a beam, a fog bank) is the one thing with no outline. Bulbs are at y 120, r 5.2, lit butter,
  unlit `#3b3350`. Everything stays 3 px inside the cell, so a mipmap does not bleed into the next one.
- **24 px, read by eye and by number.** The closest pairs of whole icons at 24 px are all two of one tier (the frame
  is the same): ray gun and saucer 11.2 of 255 a channel, cup and milkshake 11.6, radio mast and flare 11.9. Cup and
  milkshake were the only pair that read alike by eye (a red band, a tapered shape, a straw): the cup's band went sky
  blue. At 24 px the bulbs are a dotted line, not five countable dots: the number beside the icon carries the level.
- **Mipmaps cost sharpness and buy stillness.** Both atlases carry mipmaps, and a canvas item that shows an icon under
  its cell size sets `texture_filter = LevelIcons.FILTER`. Against plain linear filtering a 24 px icon is softer at
  rest, and changes 22 to 43 percent less when it moves a quarter of a pixel (mean change a step on the asphalt, of
  255: 4.3, 1.7, 4.5 with mipmaps, 5.5, 3.0, 5.7 without). A tag moves all the time, so tags want them.
**Draw cost**, counted in the web build and on the desktop (the same numbers: Compatibility renderer, 1760 x 960,
`tools/web_smoke/level_tags_cost.py`), draw calls of eight tags with the frame's one taken off:

| Eight of them | Calls |
| --- | ---: |
| Icons from the atlas, one canvas item | 1 |
| Icons from the atlas, eight `TextureRect`s (`LevelIcons.texture`) | 1 |
| Icons from eight separate textures | 8 |
| Whole tags: all the icons, then all the outlines, then all the letters | 3 |
| Whole tags: icon, outline, letters, tag by tag | 24 |

So `HudMarkers` (it already collects its words and draws them last) gets the icons first: three calls for eight tags,
not twenty-four. The atlases add 0.98 MB to the pack (lossless, with mipmaps: 0.31 and 0.68 MB) and load on first use.

**Locked silhouettes (the wardrobe, #1065).** A locked item's base icon is the same drawing language with its inner
detail gone: one flat shape in `#3b3350` with the ink outline, on the plate of the grid, no bulbs.

## The game server awards XP (#1059)

The maintainer chose the game server to award XP, a kill at a time, live ("Game server is good. We'll see how much
it stresses when we do it because XP is earned after every zombie kill and there can be hordes"). It is built, and the
horde was measured. The plan is [Who awards XP](../design/progression.md#who-awards-xp-and-live-xp).

### How it works

| Part | Where | What it does |
| --- | --- | --- |
| `XpAward` | `gameplay/progression/xp_award.gd` | A meter (`XpMeter`) for each seat that holds an account. It hears the rules' events through `NightServer._on_rules_event` (one dictionary read for the events that cannot pay: a shot, a hit, a frame) and adds what each change is worth (`XpRules.live`). `end_tick` answers the events every client hears. Nothing a client sends reaches it |
| `NightTally.keep_only` | `gameplay/challenges/night_tally.gd` | Counts only the paying stats, so a kill is a few dictionary reads and not the dozen stats the challenges keep. `forget` and `set_present` let a person take a bot's seat with a clean count |
| `LadderUnlocks` | `gameplay/progression/ladder_unlocks.gd`, `unlocks.json` | What each level gives (the design page's table as data). A row whose art is not drawn has `available` false: the level's card is told, the item is not. The wardrobe, the maps and the plate read the same file |
| `NightHost` | `net/night_host.gd` | Registers a seat from the ticket the server verified (never a client's word), releases it when the seat is freed, puts every seat's level in the WELCOME and tells the others a seat's level when it sits (`account_seated`, `account_left`), and makes a report when the award says one is due |
| `XpReportQueue` | `net/xp_report_queue.gd` | The reports wait here in order, one in flight, and are sent again unchanged after 2, 5, 15, 30, 60 s until the backend takes them. A night never waits on the backend |
| `ClientState` | `gameplay/night/client_state.gd` | `levels` (every seat's), `account_xp` (this player's raw XP from the WELCOME, then every `xp_gained`), `night_xp` |

A **Guest account** earns like any other (its ticket carries an account id like any other); a seat with no account
(a server with no backend, so no ticket) is never registered and earns nothing, and a **bot** is never registered, so
it has no level. A **late joiner** is paid for the rounds it plays, not the ones it missed (`round_base`), and a
person who takes a bot's seat starts with a clean count. **Signed-in solo** runs the same code in the local rules: the
profile is still written by `ProgressSession` at round ends, which also tells the award the XP no stat shows (the
opening night, the day's first game, a challenge) so the events agree with the file.

### The events

Every client hears them (they ride the tick like any rules event); the popups (#1064), the level over a head (#1077),
the night report (#1068) and the voice lines (#1063) read them.

| Event | Keys | When |
| --- | --- | --- |
| `xp_gained` | `player_id`, `hundredths` (added since the seat was last told), `xp` (the night's whole XP), `total` (the account's raw XP), `sources` (`{stat: hundredths}`: `points_earned`, `round`, `boards_repaired`, `doors_bought`, `fuel_cans`, `kills:boss`, `revives`, `opening_night`, `first_game_of_the_day`, `challenge`) | At most once a seat a tick: a tick's kills are added first |
| `level_up` | `player_id`, `level`, `total` | Once for each level crossed, in order |
| `tier_up` | `player_id`, `tier`, `tier_name`, `level` | A crossed level that opens a tier (6, 11, ...) |
| `unlock_earned` | `player_id`, `level`, `slot`, `item` | One for each available item the crossed level gives |
| `account_seated`, `account_left` | `player_id`, `level` | A seat with an account sat down or left (the others' `levels`) |

The WELCOME's snapshot carries `levels` (`{player_id: level}`) and the joiner's own `account_xp`.

### The interface with the backend (#1075)

The backend side is built ([Progression](platform-backend.md#progression-the-profile-slot-round-reports-and-the-xp-clamp));
the game server follows it. Nothing is written per kill.

- **The ticket** carries `xp` (the raw total), `level` and `icon`, read from the stored profile when it is minted. The
  server registers a seat with the ticket's `xp` and nothing else; a ticket without one is an account at 0 XP.
- **A report**: `POST /internal/matches/:matchId/report` with the game server's bearer secret and
  `{kind: "round" | "night", round, seats: [{userId, xp, openingNight?, bonusDay?, lines}]}`. `xp` is the whole XP the seat
  earned since its last report, without the two one-offs; `lines` are the night's paying counts so far (`round`,
  `points_earned`, `boards_repaired`, ...). A seat that has finished a round also claims `openingNight: true` and
  `bonusDay` (the UTC day number): the backend knows the profile and pays the opening night and the day's first game
  itself, once. A `round` report is made when a round ends (`round` is that round); a `night` report when the night ends
  (`round` is the round reached) or when the room closes with a round half played, and lists every seat.
- **The key** is the match, the kind, the round and the account, so a repeat pays nothing and answers `duplicate`. One
  request carries every seat, so a night is the rounds played plus one.
- **Answers**: 200, 201 and 204 take a report; any other 4xx but 408 and 429 refuses it for good (dropped, logged); the
  rest and no answer are retried in order after 2, 5, 15, 30 and 60 s (200 reports kept at most), so the backend being
  down never stops a night. The backend holds one account to 1,500 XP a match, the same as `XpRules.NIGHT_CAP`.
- **A signed-in solo night** is capped by the backend at 120 XP a minute of wall clock (`PUT /saves/profile`). Sending
  `ProfileStore`'s queue to that slot (`ProgressSession.uploader`) is not part of this issue; it is filed on its own.

### The horde, measured

**Method.** `game/tools/bench/xp_horde_bench.tscn`: a four-player night on a real `GameServer` (tickets, a room, a
WebSocket): an autopilot player over a socket and three hosted bots, all holding accounts (in the bench only; a game
server never gives a bot one), **count multiplier 5** from round 8 with 20,000 points each so the bots have bought their
guns, players who cannot die so the horde keeps coming, 120 seconds from the round's start at a fixed 60 Hz step,
headless. Three seeds, the arms played in turn on each. A tick is the room's own work (`NightHost`'s step including the
packing and sending of the tick), taken every step; bytes are what the client's link takes in, and the XP events' own
size is counted by `var_to_bytes`. This machine ran other agents' Godot processes throughout, so a time here has noise:
read the calibration row (a fixed loop timed in the same process) and the spread across seeds, and trust the counts.
`xp_award_micro.tscn` times the award alone on hand-made events and repeats to a few percent.

Natural play, the web's 40 dead (seeds 1 to 3):

| | No award | Every tick | Every 2nd tick | 0.25 s window |
| --- | ---: | ---: | ---: | ---: |
| Server tick, mean (ms) | 4.45 (4.38 to 4.53) | 4.56 (4.47 to 4.63) | 4.48 (4.45 to 4.51) | 4.35 (4.32 to 4.38) |
| Server tick, p99 (ms) | 11.4 (10.7 to 12.1) | 12.3 (11.7 to 12.9) | 11.5 (11.1 to 11.8) | 11.7 (11.5 to 11.9) |
| Server tick, worst (ms) | 23.2 (20.9 to 24.7) | 32.8 (24.3 to 46.9) | 23.8 (22.6 to 25.5) | 23.8 (23.2 to 24.4) |
| Kills a second, mean / peak second | 1.76 / 13 | 1.72 / 9 | 1.7 / 11 | 1.71 / 13 |
| `xp_gained` a second a client hears, mean / peak | 0.0 / 0 | 5.4 / 14 | 5.4 / 16 | 5.3 / 14 |
| XP events, bytes a second, mean / peak | 0.0 / 0 | 1076.0 / 2744 | 1065.0 / 3136 | 1056.0 / 2744 |
| All bytes a second a client takes, mean / peak | 23013.0 / 32358 | 24215.0 / 34050 | 23995.0 / 33501 | 23670.0 / 34258 |
| The award's own time (microseconds a tick) | - | 5.2 | 5.0 | 4.8 |
| The client's cost of applying one `xp_gained` (microseconds) | - | 20.3 | 20.0 | 21.0 |
| Backend writes | 1 | 1 | 1 | 1 |
| Calibration loop (ms) | 3.74 | 2.65 | 3.17 | 3.13 |

Natural play plus 20 kills a second made at the rules:

| | No award | Every tick | 0.25 s window |
| --- | ---: | ---: | ---: |
| Server tick, mean (ms) | 1.57 (1.55 to 1.58) | 1.57 (1.56 to 1.58) | 1.63 (1.56 to 1.74) |
| Server tick, p99 (ms) | 3.9 (3.7 to 4.2) | 4.1 (3.9 to 4.3) | 5.0 (4.0 to 6.7) |
| Server tick, worst (ms) | 20.9 (20.1 to 21.3) | 20.3 (19.9 to 20.7) | 24.1 (20.7 to 30.9) |
| Kills a second, mean / peak second | 4.57 / 5 | 4.57 / 5 | 4.57 / 5 |
| `xp_gained` a second a client hears, mean / peak | 0.0 / 0 | 4.7 / 6 | 3.8 / 6 |
| XP events, bytes a second, mean / peak | 0.0 / 0 | 945.0 / 1792 | 768.0 / 1792 |
| All bytes a second a client takes, mean / peak | 10439.0 / 14272 | 10935.0 / 14983 | 10862.0 / 14596 |
| The award's own time (microseconds a tick) | - | 4.1 | 4.3 |
| The client's cost of applying one `xp_gained` (microseconds) | - | 26.6 | 27.6 |
| Backend writes | 1 | 2 | 2 |
| Calibration loop (ms) | 2.74 | 2.62 | 4.18 |

Natural play, the desktop's 120 dead:

| | No award | Every tick |
| --- | ---: | ---: |
| Server tick, mean (ms) | 4.51 (4.06 to 4.95) | 4.66 (4.47 to 5.01) |
| Server tick, p99 (ms) | 12.0 (11.8 to 12.4) | 15.1 (11.8 to 21.8) |
| Server tick, worst (ms) | 43.3 (24.9 to 72.4) | 36.6 (23.7 to 60.7) |
| Kills a second, mean / peak second | 1.82 / 11 | 1.65 / 11 |
| `xp_gained` a second a client hears, mean / peak | 0.0 / 0 | 5.2 / 14 |
| XP events, bytes a second, mean / peak | 0.0 / 0 | 1035.0 / 2744 |
| All bytes a second a client takes, mean / peak | 23033.0 / 32840 | 24377.0 / 33501 |
| The award's own time (microseconds a tick) | - | 5.3 |
| The client's cost of applying one `xp_gained` (microseconds) | - | 20.7 |
| Backend writes | 1 | 1 |
| Calibration loop (ms) | 3.57 | 3.27 |

**The award alone** (`tools/bench/xp_award_micro.tscn`, three runs, the calibration loop 2.6 ms):

| Piece | Cost |
| --- | ---: |
| One kill: three hits, the removal and its points (five events), counted and added | 16.3 microseconds |
| An event the award ignores (a shot, a frame) | 0.19 microseconds |
| The end of a tick with nothing to tell | 1.1 microseconds |
| A tick that tells all four seats (four `xp_gained`) | 43 microseconds |
| A burst: 120 kills in one tick (a grenade into a horde), counted, then the tick's end | 0.77 ms median, 0.9 to 1.3 ms worst of 200 |
| The client applying one `xp_gained` in `ClientState` | 0.72 microseconds |
| One `xp_gained` on the wire, before compression | 196 bytes |

**Reading.**

- **The tick does not move.** The room's mean tick with the tracker (4.53 ms) is inside the spread of the runs without
  it (4.65 to 5.07; the machine's noise is larger than the tracker). The tracker's own time is 16 microseconds a tick,
  0.1 % of the 16.7 ms tick, and the CI budget case (round 12 at 3x, every seat an account, the desktop's crowd) holds
  it as `server.challenges` at 0.0047 times the calibration loop against a limit of 0.012.
- **The burst is the number to watch.** A kill is 58 microseconds, about 4 times the XP award's 16, because every stat
  change (a kill makes five to eight: the kill, the head, the weapon, the type, the points of the hits and the kill)
  walks the seat's three open dailies and three open orders. 120 kills in a tick cost 4.4 ms, over five times the XP
  award's 0.8 and about a quarter of a tick, once, and only when the dead fall together (a grenade); the room's worst
  tick in natural play is already 30 to 55 ms. The knob if a real horde ever asks: index the open challenges of a
  profile by stat so a change with no challenge on it is one lookup (a kill's `kills:type` and `kills:weapon` changes
  mostly have none).
- **The events are about half a percent of what a client takes.** 0.35 a second on average, 9 in the peak second (a round
  ending finishes several at once), 119 bytes a second against 23 KB/s (peak second 3 KB/s), and only quarter marks are
  told, never a kill. The XP events, by comparison, are 5 %.
- **The backend** is read once for each account when its seat sits down (four reads, a test counts them) and written
  with the round's report, never per kill: 1 write in the 120 s of one round, 3 where two rounds ended. A report with
  four boards weighs 3.3 KB, 0.9 KB a board; a long-played board is bigger (every weapon and kind of dead is a stat), and
  the backend holds one to 64 KiB.
- **What was not measured.** A board that has been played for weeks (hundreds of lifetime stats) was not: the profile's
  work is the same three dailies and three orders, so its cost is the same per change, but its JSON grows with the stats
  it counts and is sent whole each round. 8 seats in one room (the limit) was not run either; the cost is linear in
  seats that hold an account.

## Sources, and what we could not read

Everything linked above. Not read in full: the two 2006 papers (abstracts and secondary summaries), Zagal et al. 2013
(fetch refused), Lehdonvirta's thesis (table of contents and abstracts), the CoD guides (search summaries). No source
was found for: how long a level-up popup should stay, how tiers of reward sounds should differ, a measured effect of an
icon per level, or whether players read AI-looking UI as worse. Those numbers are ours and move by capture and play.

# Permanent progression

What grows between nights, how it is earned, what it unlocks and when, and what the platform backend stores. This page
is the **approved plan**: the maintainer answered the proposal on 2026-11-04 ([the decisions](#decisions)) and the
build is filed as issues ([build order](#build-order)). Nothing here is built except the challenge board; every number
is a first guess in one table each, and what the maintainer has not decided is marked **Open**. The evidence is on the
[research page](../research/progression.md).

## In one paragraph

A night is a fresh start and stays one: the same points, the same fuel, the same lot for everybody. What carries over is
**a level from 1 to 55** (XP from play, a climb that takes about eight hours and takes longer the higher it goes), what
the levels unlock (wearables, colours, costumes, maps, calling cards, emblems and plate frames), challenges and poster
sets, and a **slightly better kit for a higher level** (approved; how slight is for the research in #1055). Every weapon
and tonic is free to every player from the first night. There is **no account currency**: XP and challenges give things
directly. Nothing is sold. A player who wants to can **prestige** at the top, and prestige will cost something
(**Open**: what; see [Prestige](#prestige)). Missing a day costs nothing but that day's three challenges.

## Decisions

What the maintainer decided on 2026-11-04 (answers to the proposal, and later the same day), with their words where
they matter, and where each lands. Where this table differs from the earlier plan, the table wins
([what changed](#what-changed-from-the-earlier-plan)).

| # | Decision | Lands in |
| --- | --- | --- |
| 1 | **Levels 1 to 55**, each with its own icon; the second map at level 10; art in waves ("Art in waves: yes") | [The ladder](#the-ladder), [Level icons](#level-icons), #1060, #1078 |
| 2 | **Pace about 8 hours** to level 55: "Maybe 8 hours of playtime. Gotta make it short" | [The curve](#the-curve), #1058 |
| 3 | **The climb scales upward**: "It shouldn't really be 9 minutes a level unless you're just averaging it out. It should scale upward like call of duty e.g. it takes longer to level up the higher you go. That way users can feel the first level up satisfaction early on" | [The curve](#the-curve), #1058 |
| 4 | **300 or more kills a game** is the assumption (modifiers raise the count); the curve is measured at count multipliers 1, 2 and 5 | [The curve](#the-curve), research page |
| 5 | **The game server awards XP, per kill, live**: "Game server is good. We'll see how much it stresses when we do it because XP is earned after every zombie kill and there can be hordes." A signed-in solo night stays on the player's machine, capped by the backend | [Who awards XP](#who-awards-xp-and-live-xp), #1059, #1075 |
| 6 | **No offline XP**, **no rested XP**, **a first-game-of-the-day XP bonus**: yes; dailies pay XP. **Only accounts earn XP, because the server tracks it; a Guest account is one**: "only signed in accounts earn XP since we only track XP on the server. But even \"Guest\" accounts will be tracked on server." A night with no account at all earns nothing. Guest accounts expire after 7 days unless used again (kept in the game's own storage, fine for the Discord Activity); built in #1080, a returning guest within 7 days is the same account | [Where XP comes from](#where-xp-comes-from), [Storage and trust](#storage-and-trust), #1058 |
| 7 | **No account currency** for now ("Disabled; XP based"). In-night points for buying stay | [In one paragraph](#in-one-paragraph) |
| 8 | **All weapons and tonics free** from the first night. **A higher level has a slightly better kit**: "yeah the higher level player would ideally have a slightly better kit but that's a reward for them playing more." | [Rules](#rules-we-hold-ourselves-to), [Combat bonuses](#combat-bonuses), #1055 |
| 9 | **Popups in real time**, as soon as they trigger, during play; XP and milestones credit live, not at a round's end. "Animations for this stuff need to be good" | [Popups, motion and sound](#popups-motion-and-sound), #1064 |
| 10 | **Sounds**: a record scratch of our own making when a challenge is done; an honourable, battlefield-like sound for a level up (snare and brass; bigger on a tier) | [Popups, motion and sound](#popups-motion-and-sound), #1062 |
| 11 | **Progression voice lines**: several celebration lines for every progression event, male and female, ElevenLabs, heard by every client; made on the free tier, regenerated under the commercial plan before release | [Voice lines](#voice-lines), #1063, #252 |
| 12 | **Wardrobe**: a grid; locked names are `???` with a silhouette of the base icon and the unlock instructions on hover; **no fitting room**; mouths are free | [Wardrobe](#wardrobe-costumes-and-the-locks), #1065, #1061 |
| 13 | **Costumes** in their own tab, each with a **"Default"** colour option, and the player's own colours from the palette they have unlocked ("costumes in their default colors will have a Default option, and the users will have the ability to choose their own colors") | [Wardrobe](#wardrobe-costumes-and-the-locks), #1066 |
| 14 | **Plate frames**: part of levels 1 to 55, plus exclusive ones from challenges ("beat this map"); calling cards and emblems yes; **no title phrases, no ticket book, no applause** | [The plate](#plate-calling-cards-emblems-and-frames), #1070, #1071, #1072 |
| 15 | **Poster sets**: "a great addition" | [Poster sets](#poster-sets), #1073 |
| 16 | **Night report credits** yes | [The night report and credits](#the-night-report-and-credits), #1068, #1069 |
| 17 | **Maps locked by levels**; the host's level decides | [Maps](#maps), #1067 |
| 18 | **Level shown over heads by default**; bots keep their usual difficulties and have **no level** | [The level over a head](#the-level-over-a-head), #1077 |
| 19 | **Prestige** is optional, with exclusive rewards, and costs a loss: "Prestiging comes with a loss just for flex value and we lack that currently" | [Prestige](#prestige) (**Open**, #1055) |
| 20 | **Extraction**: a way to win a night; an elite unit dropped by helicopter | [Extraction](#extraction), #1056, #1057 |
| 21 | **Rarity**: wanted, with wild shader looks (wings with blue fire and glow); and weapon modifiers, skills, attachments and cool skins to research | [Research still to come](#research-still-to-come-rarity-modifiers-attachments-skills), #1053, #1055 |
| 22 | **Left out**: Bad Weather nights, the fitting room, rested XP, the ticket book, applause, title phrases | [What changed](#what-changed-from-the-earlier-plan) |

**Open:** what prestige resets and which rewards are exclusive (after #1055); how slight the combat edge is (#1055);
the extraction details (#1056, each point a choice); rarity (#1053); the voice lines are free-tier takes to regenerate
under the commercial plan (#252); the sizes of the first-game bonus and the opening night (first guesses; what they
are is still with the maintainer).

## What changed from the earlier plan

The first version of this page (Billing 1 to 50, mastery trims, stubs, Concession Orders as the economy, the Cast and
the Marquee) was written before the request for a 55-level ladder. The maintainer's answers changed it:

| Earlier plan | Now | Why |
| --- | --- | --- |
| **Billing**, an account level 1 to 50 that widens a pool of weapons, tonics and flashlights | **The ladder of 55**: cosmetics, colours, costumes, maps, cards, emblems and frames | All weapons and tonics are free (decision 8) |
| "A level-1 and a level-50 player stand in the same lot and are equally dangerous"; rule 1: permanent data never raises a number in the rounds | **A higher level has a slightly better kit** | The maintainer approved a slight combat edge as the reward for playing more; weapons and tonics stay free |
| No prestige ("Encore", no reset) | **Prestige is wanted and costs something** (open) | "Prestiging comes with a loss just for flex value" |
| *Stubs*, a cosmetic currency | **No currency**: items by level and challenge directly | "Disabled; XP based" |
| No daily first-win bonus | **A first-game-of-the-day XP bonus** | Approved. It is paid for finishing a round, never for logging in |
| Rested XP replaces login rewards | **No rested XP** | Not wanted |
| Offline and solo earn like a team, merged on sign-in | **No offline XP**; no merge | XP exists only for an account the server tracks, a Guest account included |
| The client awards XP now, the server later | **The game server awards XP, per kill, live**; a signed-in solo night stays on the player's machine, capped by the backend | Approved |
| Popups wait for the break between rounds | **Real time**, during play, in the lane under the round banner | Approved |
| A level never locks you out ("no lock on level") | **Maps are locked by level; the host's level decides** | Approved; a guest below a map's level still plays it in a friend's night |
| Bots wear a level near the lobby's average | **Bots have no level** and keep their usual difficulties | Approved |
| Title phrases, ticket book, applause, fitting room, Bad Weather | **Dropped** | Not wanted (title phrases: the maintainer was unsure, dropping was recommended) |
| Night Report lines *Lamps*, *Holdings*, *Mentor* and *Solo +10%*; the Night Report paying stubs | The simpler [XP lines](#where-xp-comes-from) (Rounds, Points, Upkeep, Headliner, Rescue, the bonuses) | The proposal replaced them and the maintainer approved the proposal's XP table; each line is a stat the night already counts |
| 22 to 32 hours to level 55 (53,250 XP) | **About 8 hours** (18,010 XP), a rising curve | "Gotta make it short" |

!!! note "Rules 1 and 2 are replaced for combat kit (2026-11-04)"
    The maintainer approved a slightly better kit for players who have played more: "the higher level player would
    ideally have a slightly better kit but that's a reward for them playing more". Weapons and tonics stay free for
    everyone, and the night's economy, rounds and fuel stay the same for all. How slight, what resets on a prestige and
    what stays: [Attachments, modifiers, skills, skins and prestige](../research/weapon-progression.md). The
    level-1 and level-50 sentence above and rules 1 and 2 below are read with that page.

## What the research says

Study was for understanding only; no name, number or presentation below is ours to reuse. Forum threads are named as
anecdotal where they carry the claim. Several press pages could not be read in full by the tooling; those rows lean
on the search summary and are marked.

| Approach (example) | What it does | Works | Backfires | Take for Deadnight |
| --- | --- | --- | --- | --- |
| Deck or loadout built from unlocks (Back 4 Blood) | A small starter deck, bigger decks and new cards unlocked with a currency spent on themed "lines" | The studio dropped fully random distribution because players would "have different experiences"; rule-changing cards beat stat cards ("a 5 percent move speed increase only registers for a very savvy player"); a half-empty starter deck makes each new card get tried ([Game Developer](https://www.gamedeveloper.com/design/behind-back-4-bloods-ingenious-card-system)) | Solo play earned no progression currency and players called it a major flaw ([Pure Xbox](https://www.purexbox.com/news/2021/10/back-4-blood-players-have-a-major-concern-with-its-solo-campaign), [GGRecon](https://www.ggrecon.com/guides/back-4-blood-solo-progression/)) | Choice over randomness; unlocks change decisions, not numbers; solo earns exactly like a team |
| Class levels with a free track, cosmetic-only money (Deep Rock Galactic) | Per-class levels, a free seasonal track, paid items are cosmetic | A free progression track "grafts well" onto existing progression ([Game Rant](https://gamerant.com/deep-rock-galactic-interview-season-1-co-op-design-battle-pass-progression/), [season FAQ](https://www.deeprockgalactic.com/season01-faq)); when fans objected that a paid cosmetic's original design was free for everyone, the studio moved the original into the free track ([PC Gamer](https://www.pcgamer.com/deep-rock-galactic-studio-remakes-cosmetic-dlc-after-fans-complain-everyone-gets-the-original-designs-for-free)) | Anecdotal: little to do beyond 10-20 hours except cosmetic farming ([Steam thread](https://steamcommunity.com/app/548430/discussions/1/3492005739867760090)) | Money, if ever, only buys cosmetics; the plain version of every cosmetic stays earnable |
| Reset for a reward (Deep Rock promotion, Call of Duty prestige, Payday 2 infamy, Killing Floor 2 prestige) | At the cap a level resets to 1 for a badge, a perk or access | A promotion that opens new content is accepted: at level 25 a class resets and the forge and deep dives open ([TheGamer](https://www.thegamer.com/deep-rock-galactic-how-to-promote-character/)); classic prestige returned in Black Ops 6 and keeps weapon progress and Zombies gums (sources disagree on exactly what is kept) ([Esports.gg](https://esports.gg/news/call-of-duty/prestige-in-black-ops-6-how-does-it-work-rewards-and-more/)) | Infamy was read as extending progression artificially; players lost skill points, weapons and money "for pretty much no reward" ([Quarter to Three](https://quartertothree.com/fp/?p=29322), [Steam thread](https://steamcommunity.com/app/218620/discussions/8/617329920710858574)); Overkill later reworked it to add skill points instead of discounts ([Overkill](https://overkill-archive.starbreeze.com/?p=7229)); Killing Floor 2 prestige called repetitive with "no gameplay-changing features" (anecdotal) | **Superseded by the maintainer's answer:** prestige is wanted and must cost something (a loss for flex value), with exclusive rewards; what resets is open ([Prestige](#prestige)) |
| Weapon camo and mastery tracks (Call of Duty Zombies) | Each weapon has tiered challenges for camos | Goals tied to the weapon you already like | Players call the grind too long and say certain weapon archetypes are always better ([Gamereactor](https://www.gamereactor.eu/what-really-grinds-my-gears-call-of-duty-black-ops-6s-camo-challenges-1453823/)); challenge bugs ([NME](https://www.nme.com/news/call-of-duty-vanguard-players-report-weapon-challenges-are-bugged-3088522)) | Few mastery tiers, reachable in a handful of nights, rewarded with side-grades that make the weapon *different*, not better |
| Challenge-only battle pass (Halo Infinite) | Pass progress only from challenges at launch | Clear goals | Backlash that matches did not count; the studio added "play 1 game" challenges and sped weekly ones up ([GameSpot](https://www.gamespot.com/articles/halo-infinite-major-battle-pass-progression-changes-coming-this-week/1100-6498137/), [Windows Central](https://www.windowscentral.com/halo-infinite-fans-angry-about-battle-pass)) | Playing the game always earns; challenges add to it, never replace it |
| Permanent, un-expiring tracks (Helldivers 2 warbonds) | Premium tracks never retire; premium tracks can be progressed with medals earned in play | Studio statements that they never retire and are not pay-to-win ([Prima Games](https://primagames.com/tips/do-helldivers-2s-warbonds-go-away-answered), [Yahoo](https://www.yahoo.com/tech/helldivers-2-warbonds-not-pay-220436504.html)); a limited-run crossover was made permanent ([Final Boss](https://finalboss.io/helldivers-2-x-killzone-is-back-this-time)) | Premium tracks still cost paid credits | Nothing expires; a returning player picks up where they left off |
| Expiring seasons and daily tasks (battle passes in general) | Rewards vanish when the season ends | Predictable revenue (not our concern) | FOMO and burnout; even a never-expiring pass can create FOMO through a purchase window ([VideoGamer](https://www.videogamer.com/features/marvel-rivals-battle-pass-still-gives-players-massive-fomo-and-it-should-be-fixed), [Exputer](https://exputer.com/features/battle-passes-replaced-loot-boxes-consumers/)); commentary, not data | No timers on lasting progress and no streaks. The maintainer chose dailies that simply expire ([Challenges](#challenges-dailies-orders-and-milestones)) |
| Random loot and crafting (Vermintide 2, Darktide, Killing Floor 3) | Gear power from chests and crafting | Vermintide 2's designers wanted gear to matter less than skill ([PC Gamer](https://www.pcgamer.com/how-warhammer-vermintide-2-plans-to-fix-the-first-games-loot-system), via search summary) | Darktide's launch progression was called RNG-heavy and incomplete, and Fatshark apologised and rebuilt it ([Shacknews](https://shacknews.com/article/133824/warhammer-40000-darktide-launch-apology), [PC Gamer](https://pcgamer.com/fatshark-details-upcoming-changes-to-darktides-gear-acquisition-and-crafting)); Vermintide 2 players report a slow power grind and an account-wide item level that leaves alts behind (anecdotal); Killing Floor 3 launched "Mixed" with a progression grind, worse solo ([MeinMMO](https://mein-mmo.de/en/killing-floor-3-launch-durchwachsen,1516766)) | No random power. Every unlock is a named thing the player picked or earned |
| Meta currency that pays on failure (Vampire Survivors, Hades) | Every run, won or lost, pays toward permanent options | "Players always have something to work towards, even when they don't manage to complete a run" ([Substack](https://jboger.substack.com/p/the-secret-sauce-of-vampire-survivors), community analysis); opt-in difficulty for opt-in reward ([fan analysis](https://saschb2b.github.io/game-mechanics/games/hades/meta-progression)) | - | A lost night pays almost the same; harder nights are a choice that pays more |
| Unlocks that add options (Risk of Rain 2) | Challenges unlock characters, skills, skins; items reset every run | Unlocks "have entirely different experiences" rather than raise power ([PC Gamer](https://www.pcgamer.com/au/risk-of-rain-2-character-unlocks), [GamesRadar](https://www.gamesradar.com/risk-of-rain-2-challenges)) | Some challenges needed rework (anecdotal) | The model for the whole page |
| No persistent power (Left 4 Dead) | The Director varies each run; player strength does not carry | The Director decides where items and threats appear, so levels replay differently ([Valve design theory](https://developer.valvesoftware.com/wiki/Left_4_Dead_Design_Theory)); we found no source on why it skips unlocks | Nothing to collect between sessions (our reading) | Deadnight's rounds supply the variation; progression supplies the collecting |
| Always-online progression (Payday 3) | Progression needs the servers | Cross-progression | Launch outages kept players out; Starbreeze found update-pipeline errors that could have wiped progression ([GameSpot](https://www.gamespot.com/articles/payday-3-devs-ceo-apologizes-for-online-shooters-unstable-launch/1100-6517936/), [mp1st](https://mp1st.com/news/payday-3-first-patch-issues-identified-before-it-can-be-released-starbreeze-revamping-patching-process-for-steady-cadence)) | A night never waits on the backend; rewards queue and are replayed safely |
| Level as a matchmaking signal | Match or filter by account level | Easy to build | Level is a weak proxy for skill: farmed XP, smurfs, several characters ([EA forum threads](https://forums.ea.com/discussions/star-wars-battlefront-2-en/the-matchmaking-balance-thread/10839464/replies/10839533), anecdotal); newcomers say veteran lobbies push them out | Never match on level; a level opens maps (the host's level decides) and cosmetics, and never sorts people |

The motivation underneath, from self-determination theory applied to games: the pull of a game comes from **autonomy,
competence and relatedness**, and in multiplayer games all three independently predict enjoyment and continued play
([Ryan, Rigby and Przybylski 2006](https://link.springer.com/content/pdf/10.1007%2Fs11031-006-9051-8.pdf)). That is
the test for every feature below: it should give a choice (autonomy), a visible sign of getting better (competence) or
a reason to play with other people (relatedness) - and a number going up is only the weakest of the three.

## Rules we hold ourselves to

Rules 1 to 10 were the first plan's; 11 to 17 are on the [research
page](../research/progression.md#where-the-ethical-lines-are). Changed rules say what they were.

| # | Rule | Because |
| --- | --- | --- |
| 1 | **The night resets.** Starting points, fuel, circuits and the lot are the same for every player, and a level never changes the economy or the rounds' tuning. *Changed:* a higher level may carry a **slightly better kit** (the maintainer's approval, [combat bonuses](#combat-bonuses)); the size of the edge is set by research (#1055) and audited, so a level-1 player still wins nights | Power creep and split lobbies, held to "slight" |
| 2 | **Unlocks widen first.** Every weapon and tonic is available to everyone from the first night. What a level unlocks is cosmetic, a map, or the slight kit edge | Rule-changing beats stat-changing; old and new players stay in one balance |
| 3 | **One gate per item.** An item is earned by exactly one of: a level or a named challenge or poster set. Never two in series. *Was:* a Billing level, a mastery level, an order or stubs | Stacked gates are what players call grind |
| 4 | **Nothing is for sale and there is no currency.** *Was:* stubs bought only cosmetics | Keeps pay-to-win off the table; "Disabled; XP based" |
| 5 | **Playing always pays.** Win or lose, solo or four, a night earns; challenges add to it | Halo's lesson, Back 4 Blood's lesson |
| 6 | **A missed day owes nothing.** Daily challenges expire at each daily reset (the maintainer, 2026-11-02, [decision](#decision-daily-challenges)): no banking, no carry-over, no streak, no login reward. *Changed:* the **first game of the day** pays a small XP bonus, for finishing a round, never for logging in | FOMO and burnout; a daily is an offer for one day, never a debt |
| 7 | **No random power.** Randomness in a night (the crane) is fine; randomness in what a player *has* is not | Darktide, Vermintide |
| 8 | **Level never sorts people.** No matchmaking, no difficulty, no level for a bot. *Changed:* a level opens maps, and **the host's level decides** which maps a lobby offers; a guest below a map's level still plays it | Weak signal; most lobbies here are friends |
| 9 | **The server awards, the client asks.** XP is added by the game server, per kill, in real time; a signed-in solo night is awarded on the player's machine and capped by the backend | Cheating and trust; the game is network-first |
| 10 | **A night never waits on the backend.** Rewards are saved at round ends and can be late, never a condition to play | Payday 3 |

## What grows

| Layer | What it is | Gives | Gate | Resets |
| --- | --- | --- | --- | --- |
| **Level** | The account level, 1 to 55, with its icon | Wearables, colours, maps, tier cards and emblems, plate frames, the slight kit edge | Night XP | never (prestige: open) |
| **Challenges** | Dailies, three orders and lifetime milestones | XP, and calling cards, emblems and frames | Doing the thing | a daily expires; the rest never |
| **Poster sets** | Six themed challenges a set | A calling card and an emblem for the finished set | The six challenges | never |
| **The plate** | What others see: card, emblem, frame, level and icon | Identity | Levels and challenges | never |
| **Costumes** | The twelve presets, in their own colours | A quick whole look | Owning every piece | never |
| **Prestige** | A choice at the top | Exclusive rewards for a loss | Level 55 | by design: open |

## XP and the ladder of 55

### Where XP comes from

A night's *report*, in the night's own words: Rounds, Points, Upkeep, Headliners. Every line is a stat the night counts
today (`NightTally`), except where marked. A kill pays through its points, so XP moves with **every kill**, live.

| Line | Pays | Counted today | Note |
| --- | --- | --- | --- |
| Rounds | 20 a round reached, 10 a round past round 20 | yes (`round`, the best round started) | down or not: playing always counts; the round pays when it starts, so the night's last round counts |
| Points | 1 XP per 100 points you earned yourself | yes (`points_earned`) | kills, headshots and bonuses are already in points, so no kill is stolen. The server adds each kill's points to a running tally as it happens |
| Upkeep | 2 a board mended (up to 100 XP, so 50 boards), 15 a door opened, 15 a fuel can | yes | the lot's chores pay a little |
| Headliner | 50 a boss brought down | yes (`kills:boss`) | |
| Rescue | 40 a revive, up to 5 a night | one tally line (`player_revived` names the reviver) | solo has none; no solo penalty |
| Opening night | 50, once, "your ticket is punched on the way in" | a flag | the first bar is not empty; the first level comes in about a minute |
| **First game of the day** | 100, once a local day (the day number the dailies use) | `bonus_day` in the profile | **New.** Credited when that day's first round ends, so it pays for playing; a missed day owes nothing. First guess |
| Dailies, orders | 25, 50, 100 and 75, 200, 600 | yes (built) | paid as XP; the stub amounts are dropped |

Capped at **1,500 XP a night** (about twice the strong four-player night's 766), and the backend's clamp below. There
is **no streak, no login reward, no rested XP** and no currency.

### Who awards XP, and live XP

The maintainer asked how other games do it and chose: the **game server awards XP per kill, live**, and "we'll see how
much it stresses when we do it". The design keeps the cost per kill small and puts the measurement in the build:

- **A running tally per seat on the server.** A kill adds its points (a hundredth of an XP each) to the killer's
  tally; rounds, boards, doors, cans and bosses add when they happen. **The backend is never written per kill.** The
  server saves at **round ends** and at the end of the night, one report a seat, keyed by match and round so a retry
  cannot pay twice.
- **The event stream carries it**: an `xp_gained` event at most once per seat per server tick (a tick's kills are
  added first), then `level_up`, `tier_up` and `unlock_earned` when a total crosses a level. These are the events the
  popups, the level over a head and the voice lines read, so **every client hears them**, and a late joiner sees every
  level.
- **A signed-in solo night stays on the player's machine**: the same tally runs in the local rules and the client writes
  at round ends; the backend caps how fast XP can rise (about 120 XP a minute, three times a strong four-player night).
- **The stress is measured** (#1059, built): a four-player night at **count multiplier 5** on the dedicated server, with
  and without the tally, three seeds: tick time (mean, p99, worst) and the tally's cost per kill; `xp_gained` events and
  bytes a second per client at the peak; the client's cost of applying them; the backend writes a night (the rounds
  plus the night's own, never the kills). The numbers, the events' keys and the interface with the backend are in
  [the research page](../research/progression.md#the-game-server-awards-xp-1059).

### The curve

The XP to leave a level is set per tier of five (a table, not a formula, so it reads and retunes by hand), and **it
rises**: the maintainer wants the first level up early and the top ones far slower ("It should scale upward like call of
duty"). Only raw XP is stored; the level is computed from this table, so a retune needs no migration.

| Tier | Levels | XP to leave each | | Tier | Levels | XP to leave each |
| --- | --- | ---: | --- | --- | --- | ---: |
| Doors Open | 1-5 | 85 | | Main Feature | 31-35 | 390 |
| Cartoon | 6-10 | 135 | | Late Show | 36-40 | 440 |
| Newsreel | 11-15 | 185 | | Midnight Show | 41-45 | 490 |
| Intermission | 16-20 | 235 | | Headliner | 46-50 | 540 |
| Trailers | 21-25 | 290 | | Last Reel | 51-54 | 590 |
| Second Feature | 26-30 | 340 | | After 55 | - | nothing until prestige is decided |

Total **18,010 XP** to level 55 (it was 53,250 for the earlier 22 to 32 hours). **Measured** with the balance
simulator (150 seeded nights a cell, seed 4000, the real rules and weapons, bots of three skills in teams of one, two
and four) at **count multipliers 1, 2 and 5**; an XP an hour table is on the [research
page](../research/progression.md#the-8-hour-curve-measured). The cells with **300 or more kills a night** (the
maintainer's assumption) pay 1,740 to 2,320 XP an hour in nights alone; the lines the model leaves out (boards, doors,
cans, bosses, dailies and the first game of the day) add about 15 percent. So:

| | Weak, solo (38 kills) | Average, solo (122) | Strong, solo (290) | Average, four (682) | Strong, four, count x5 (508) |
| --- | ---: | ---: | ---: | ---: | ---: |
| XP an hour, nights only | 1,603 | 2,123 | 2,316 | 1,739 | 1,948 |
| **The first level** (level 2, 85 XP, with the opening night's 50) | 1.3 min | 1.0 min | 0.9 min | 1.2 min | 1.1 min |
| Level 5 | 11 min | 8 min | 8 min | 10 min | 9 min |
| **Level 10, the second map** | 34 min | 26 min | 24 min | 32 min | 28 min |
| Level 25 | 2.7 h | 2.0 h | 1.9 h | 2.5 h | 2.2 h |
| **The last level** (54 to 55, 590 XP) | 22 min | 17 min | 15 min | 20 min | 18 min |
| **Level 55** | 11.2 h | 8.5 h | 7.8 h | 10.3 h | 9.2 h |

![Hours to each level](../research/progression-curve.png)

Reading it: the first level takes about a minute and the last one 15 to 22 minutes, **seven times longer**; the
average solo player reaches 55 in 8.5 hours of nights alone (about 7.5 with the lines the model leaves out), the
strong in 7.8 and the slowest cell in 11. **Level 10, the second map, arrives after 24 to 34 minutes: about half an
hour, the third night for an average solo player.** The maintainer asked to be told this (it "may arrive in under half
an hour"): it does for the average and strong cells and for the cells with 300 or more kills. The maintainer
answered that level 10 "is fine" and approved the curve ("The XP simulator is good"). At count x5
the simulator's bots die in the first rounds, so XP an hour is lower, not higher: a horde modifier is not a way to
level faster here. Bots are not people: the curve is meant to be retuned from the first real nights' telemetry.

**Held by a test.** `test_xp_pace` reads the gate's cells (average solo, strong solo and average four at count
multipliers 1, 2 and 5; 60 seeded nights each, seed 4000, [measured](../research/xp-curve.md)) and holds level 55
between 7 and 11.5 hours for the nights that count 240 or more kills, level 10 between 20 and 40 minutes, the first
level inside 3 minutes in every cell and the last level between 10 and 30 minutes and slower than every level before
it, so a retune of the rounds or the economy that moves the pace, or a curve that goes flat, fails.

### The ladder

Eleven tiers of five, named for a night at the pictures. A tier has a frame (a ticket, a token or a sign, and a
colour), a level has its glyph, and five bulbs under the badge show the level inside the tier. Every fifth level gives a
**tier card and emblem**. Icon titles are working names for the icon issue (#1060). The time column is the average solo
cell, nights only.

| Level | Tier | Icon | XP to leave | Total XP | Average solo, total time | Unlocks |
| ---: | --- | --- | ---: | ---: | ---: | --- |
| 1 | Doors Open | Admission stub | 85 | 0 | 0 | the icon |
| 2 | Doors Open | Ticket roll | 85 | 85 | 1 min | Plate: calling cards and emblems open; the emblem Admit One |
| 3 | Doors Open | Tin token | 85 | 170 | 3 min | Colour: Cherry |
| 4 | Doors Open | Turnstile arm | 85 | 255 | 6 min | Top: Rolled sleeves |
| 5 | Doors Open | Popcorn box | 85 | 340 | 8 min | Colour: Tan; Tier card and emblem |
| 6 | Cartoon | Whitewall tyre | 135 | 425 | 11 min | Headwear: Usher's cap |
| 7 | Cartoon | Hubcap | 135 | 560 | 14 min | Colour: Mustard |
| 8 | Cartoon | Fuzzy dice | 135 | 695 | 18 min | Top: Jacket |
| 9 | Cartoon | Speaker on its post | 135 | 830 | 22 min | Colour: Brown |
| 10 | Cartoon | Back-room key | 135 | 965 | 26 min | **Map: the back rooms**; Tier card and emblem |
| 11 | Newsreel | Paper cup and straw | 185 | 1,100 | 30 min | Trousers: Shorts |
| 12 | Newsreel | Hot dog | 185 | 1,285 | 35 min | Shoes: Boots |
| 13 | Newsreel | Milkshake | 185 | 1,470 | 40 min | Eyewear: Goggles |
| 14 | Newsreel | Candy box | 185 | 1,655 | 45 min | Headwear: Helmet |
| 15 | Newsreel | Film reel | 185 | 1,840 | 51 min | Colour: Teal; Tier card and emblem |
| 16 | Intermission | Pennant | 235 | 2,025 | 56 min | Top: Tank top |
| 17 | Intermission | Flash bulb | 235 | 2,260 | 62 min | Colour: Pink |
| 18 | Intermission | Megaphone | 235 | 2,495 | 69 min | Top: Usher's jacket (new art) |
| 19 | Intermission | Director's chair | 235 | 2,730 | 76 min | Neck: Press lanyard (new art) |
| 20 | Intermission | Usher's torch | 235 | 2,965 | 82 min | Trousers: Striped; Tier card and emblem |
| 21 | Trailers | Marquee letter | 290 | 3,200 | 89 min | Colour: Denim |
| 22 | Trailers | Lobby card | 290 | 3,490 | 1.6 h | Headwear: Ranger hat |
| 23 | Trailers | Poster tube | 290 | 3,780 | 1.8 h | the icon |
| 24 | Trailers | Ticket punch | 290 | 4,070 | 1.9 h | Eyewear: Cinema glasses (new art) |
| 25 | Trailers | Clapper | 290 | 4,360 | 2.0 h | **Map slot: the third map, when it exists (choice)**; Tier card and emblem |
| 26 | Second Feature | Radio mast | 340 | 4,650 | 2.2 h | Top: Letter jacket |
| 27 | Second Feature | Dish aerial | 340 | 4,990 | 2.3 h | Colour: Charcoal |
| 28 | Second Feature | Walkie-talkie | 340 | 5,330 | 2.5 h | Shoes: Saddle shoes (new art) |
| 29 | Second Feature | Flare | 340 | 5,670 | 2.6 h | Plate frame: Chrome |
| 30 | Second Feature | Marquee arrow | 340 | 6,010 | 2.8 h | Tier card and emblem |
| 31 | Main Feature | Rocket | 390 | 6,350 | 3.0 h | Trousers: Overalls (new art) |
| 32 | Main Feature | Ray gun | 390 | 6,740 | 3.2 h | Colour: Green |
| 33 | Main Feature | Robot head | 390 | 7,130 | 3.3 h | Headwear: Projectionist's visor (new art) |
| 34 | Main Feature | Space helmet | 390 | 7,520 | 3.5 h | Neck: Bolo tie (new art) |
| 35 | Main Feature | Flying saucer | 390 | 7,910 | 3.7 h | Tier card and emblem |
| 36 | Late Show | Skull | 440 | 8,300 | 3.9 h | Top: Coveralls (new art) |
| 37 | Late Show | Bat | 440 | 8,740 | 4.1 h | Plate frame: Brass |
| 38 | Late Show | Spider web | 440 | 9,180 | 4.3 h | Shoes: Roller skates (new art) |
| 39 | Late Show | Tombstone | 440 | 9,620 | 4.5 h | the icon |
| 40 | Late Show | Rubber monster | 440 | 10,060 | 4.7 h | Trousers: Swing skirt (new art); **Map slot: the fourth map, when it exists (choice)**; Tier card and emblem |
| 41 | Midnight Show | Crescent moon | 490 | 10,500 | 4.9 h | the icon |
| 42 | Midnight Show | Hurricane lamp | 490 | 10,990 | 5.2 h | Colour: Gold |
| 43 | Midnight Show | Fog light | 490 | 11,480 | 5.4 h | the icon |
| 44 | Midnight Show | Lightning bolt | 490 | 11,970 | 5.6 h | Top: Creature tee (new art) |
| 45 | Midnight Show | Projector | 490 | 12,460 | 5.8 h | Tier card and emblem |
| 46 | Headliner | Spotlight | 540 | 12,950 | 6.1 h | Shoes: Rubber boots (new art) |
| 47 | Headliner | Star | 540 | 13,490 | 6.3 h | the icon |
| 48 | Headliner | Trophy | 540 | 14,030 | 6.6 h | Headwear: Creature mask (new art) |
| 49 | Headliner | Curtain | 540 | 14,570 | 6.8 h | the icon |
| 50 | Headliner | Searchlight | 540 | 15,110 | 7.1 h | Neck: Film-strip scarf (new art); Plate frame: Neon; Tier card and emblem |
| 51 | Last Reel | Gold bulb | 590 | 15,650 | 7.3 h | the icon |
| 52 | Last Reel | Film strip | 590 | 16,240 | 7.6 h | Top: Varsity gold (new art) |
| 53 | Last Reel | Laurel | 590 | 16,830 | 7.9 h | the icon |
| 54 | Last Reel | Golden ticket | 590 | 17,420 | 8.2 h | the icon |
| 55 | Last Reel | The last reel | - | 18,010 | 8.5 h | Plate frame: Gold; the last emblem; Tier card and emblem; XP past 55 is kept (prestige is open) |

Counts: **26 wearables** (11 that exist in the catalogue, **15 new pieces**), **10 colours**, **2 map slots** past the
second map, **4 plate frames** from levels (more are a line each), **11 tier cards and 11 tier emblems**. Ten levels
give only their icon (1, 23, 39, 41, 43, 47, 49, 51, 53, 54): the maintainer may prefer a feature there. A level whose
item is not drawn yet gives only its icon until the piece lands; the table is data (`unlocks.json`), so adding a piece
is one line. **Rarity is not assumed** (#1053): the table gives names and levels, and a rarity tier, if any, is laid
over it later.

### Combat bonuses

The maintainer approved a **slightly better kit for a higher level** ("a reward for them playing more"), replacing the
first plan's rule that a level 1 and a level 55 player have the same tools. Weapons and tonics stay free to
everyone. **How slight, and what it is** (a little more starting ammunition, a small reload edge, an attachment or a
skill) is for the research in #1055 (weapon modifiers, attachments, skills and skins). Until it reports, nothing here
changes a number in a night, and no build issue is filed. Constraints that stay: a level-1 player must still be able
to win the night; the edge is audited with a seeded bot night so it stays inside a small band; it is never sold.

## Wardrobe, costumes and the locks

- **Free forever:** the character (male, female), face, hair style and colour, skin, **and a new mouth row** (#1061; the
  face research already built `line` and `grin` beside the shipped `smile`).
- **Locked:** headwear, top, trousers, shoes, eyewear, neckwear, and the 16-colour cloth palette (primary, second and
  trim colours share it). **Weapons and tonics are never locked.**
- **Start with two of each**. A slot that may be empty keeps its free "None".

| Slot | Start with | Locked (existing) | Locked (new art) |
| --- | --- | --- | --- |
| Headwear | Ball cap, Paper cap | Usher's cap 6, Helmet 14, Ranger hat 22 | Projectionist's visor 33, Creature mask 48 |
| Top | Short sleeves, Field vest | Rolled sleeves 4, Jacket 8, Tank top 16, Letter jacket 26 | Usher's jacket 18, Coveralls 36, Creature tee 44, Varsity gold 52 |
| Trousers | Trousers, Cuffed jeans | Shorts 11, Striped 20 | Overalls 31, Swing skirt 40 |
| Shoes | Sneakers, Shoes | Boots 12 | Saddle shoes 28, Roller skates 38, Rubber boots 46 |
| Eyewear | Glasses, Sunglasses | Goggles 13 | Cinema glasses 24 |
| Neckwear | Scarf, Bow tie | - | Press lanyard 19, Bolo tie 34, Film-strip scarf 50 |
| Colours | Black, Cream, Grey, Olive, Red, Blue | Cherry 3, Tan 5, Mustard 7, Brown 9, Teal 15, Pink 17, Denim 21, Charcoal 27, Green 32, Gold 42 | - |

- **The grid screen** (mock-up below): the live soldier on the left, a tab per category along the top, items in a grid
  on the right. An unlocked item is lit. **A locked item is a dark silhouette of the base icon, its name is `???`, and
  the instructions to unlock it show on hover** ("Reach level 4; you are level 12", or the challenge's act). On a
  gamepad or a phone, focus does what hover does. A locked item can be looked at but not worn: **no fitting room.**
  Face and body tabs carry no lock marks, so what is free is plain (#1065).
- **Costumes have their own tab** (#1066): the twelve presets (greaser, usher, mechanic...) become costumes that wear
  their pieces **in the costume's default colours**, and the colour picker offers a **"Default"** option (the costume's
  own colours, free) beside the player's own colours from the palette they have unlocked ("costumes in their default
  colors will have a Default option, and the users will have the ability to choose their own colors"). A costume is
  dark with `???` and hover instructions until the player owns every piece, lit after. Four costumes use starting
  pieces only, so a new player has a quick start. Equipping a costume sets the look; the player may then change any
  part they own.
- **Built (#1065):** `LookUnlocks` asks a gate `{"level": n}`, and the part and palette gates are read from
  `unlocks.json` (the same table, extended with a `part` key on each wearable's row; `LookCatalog.part_gates()`,
  `palette_gates()`). The saved look and the wire format are unchanged (an index per part); a look wearing something
  the player does not own is repaired on load, and the game server drops it for a player whose level it knows. The
  grid, the silhouettes and the hover words are on [Customization](customization.md#the-screen).

![The wardrobe grid](../research/progression-grid.png)

*The mock-up predates the decisions: it shows names for the next unlocks; the plan is `???` with a silhouette and hover
text.* The 15 new wearable pieces are art in waves (#1078): eight, then seven; the ladder works without them.

## Maps

`MapRegistry` lists the maps with a `shipped` flag; `unlock_level` is on each map resource (built in #1067, see
[Maps](maps.md#levels-open-maps)). The drive-in
(first map) is level 1; **the back rooms (the second map) is level 10**. Reserved rows at 25 and 40 for maps three and
four when they exist. The picker shows a locked card dark with "Level 10" in the same `???`-and-hover look as the
wardrobe. **The host's level decides the lot** (decision 17): a lobby whose host is below a map's level does not offer
it; a guest below it plays a hosted night there as a visitor; the server checks the host's level from the ticket. The
balance simulator already runs the back rooms (`--map=small_indoor`); a night there pays about 7 percent more XP an
hour: not a loophole. Level 10 arrives after about half an hour ([the curve](#the-curve)) and is confirmed; it is one number.

## Plate: calling cards, emblems and frames

![Cards, emblems, the plate and name tags](../research/progression-plate.png)

- **Calling card** (a *one-sheet*): a wide banner (440 by 120) with a title printed on it ("Last car out"), shown on the
  player's plate in the lobby, the scoreboard and the night report. **Emblem:** a small badge worn beside the name.
  **Plate frame:** a border for the plate. One of each is equipped (#1070, #1071).
- **No title phrases** (a free line under the name from word cards): the maintainer was unsure and dropping was
  recommended, so a card carries its printed title only. **No ticket book. No applause.**
- **Frames come from two places:** the ladder (**part of levels 1 to 55**: Chrome 29, Brass 37, Neon 50, Gold 55 to
  start; more are a line each) and **exclusive ones from challenges**, such as "beat this map". The "beat this map"
  frames wait for **extraction** (#1056) and are their own issue (#1072).
- Cards are **composed from shared parts** (a scene of reel, ticket, car, bulbs, saucer, a palette, a title), so about
  40 are a week of art, not 40 paintings; emblems are drawn once each.
- Launch set: **11 tier cards and 11 tier emblems** from the ladder, and **31 challenge cards and 31 emblems**: 42 of
  each. A challenge gives a card, an emblem, a frame or a mix, as the tables say (never two gates in series). The rarity
  of a frame or card is not assumed (#1053).

## Challenges: dailies, orders and milestones

Small, visible reasons to play a night a certain way. The foundation is built (issue #399: the model, the counting, the
save and the read API). Their rewards are now **XP, and calling cards, emblems and plate frames** (no currency, no
stubs): dailies and orders pay XP at the amounts in the table below and a finished family of orders or a poster set
gives a card. What the research behind it found is in [Challenges](../research/challenges.md).

### Decision: daily challenges

The maintainer asked for daily challenges (2026-11-02, #399: "daily challenges and stuff to meet ... checkpoint
progress prompts in the UI during gameplay ... a really well thought out design ... modern and sleek, not
AI-ified") and then decided their shape: **dailies expire at each daily reset. No banking, no carry-over and no
streaks.** That changes rule 6, which used to say "nothing expires". The research
([Challenges](../research/challenges.md)) leaned the other way (Fortnite and Overwatch both moved toward progress
that carries over, and the CHI Play study found fear of missing out is one of three ways players take dailies); the
decision stands, and what keeps it from becoming a chore is in the table.

| Part of the decision | Rule |
| --- | --- |
| Dailies exist | Three a day, dealt from the date, the same for everybody |
| They expire | At the reset, finished or not: the board shows three new ones at zero. Nothing is banked, nothing carries over |
| No streak | Nothing counts consecutive days, or days played. Nothing is paid for opening the game. *Changed 2026-11-04:* the **first game of the day** pays a small XP bonus (100, a first guess), credited when that day's first round ends: it pays for playing, never for logging in, and a missed day owes nothing |
| Small on purpose | One short, one medium, one long a day; the short one is under a night's work, so one night finishes something |
| Playing always counts | Every night advances everything it touches; a challenge adds a goal, it is never the only way to progress |
| Orders and milestones stay | Three orders at a time and the lifetime ladders have no timer and never expire; orders are the long goals |
| Nothing exists only on one date | A daily's reward (XP) is the same kind of thing every day |

### Families

| Family | Size | Refresh | Counts | Shown |
| --- | --- | --- | --- | --- |
| **Daily** | One short, one medium, one long a day (under a night to a few nights) | Expires at the player's midnight: the date picks the next three, at zero | From the moment it is on the board | Home panel and Challenges tab |
| **Order** (Concession Order) | Three open; short, medium or long (days to weeks) | Never. A finished order is replaced when the night ends; the player may swap any one at any time | Total or best night, per order | Challenges tab; the home panel shows the nearest to done |
| **Milestone** | A ladder of lifetime steps per stat (kills, nights, rounds, best round, headshots, boards, doors, grenade kills, melee kills, headliners, fuel cans, points) | Never; the rung is derived from the lifetime total | Lifetime | Challenges tab; a step reached shows in the night |

A challenge is a record in `game/gameplay/challenges/data/` (`dailies.json`, `orders.json`, `milestones.json`):
`id`, `text` (`{n}` is the target, so retuning a target retunes the words), `stat`, `target` (a milestone has `steps`),
`mode` (`total`, adding up across nights, or `night`, the best single night), `tier`, a `group` for dailies, a
`pillar` for orders and a placeholder `reward`. A test checks every file: unique ids, a stat the night counts, rising
steps, enough of every tier and group for a day to be varied.

### Refresh and the order draw

| Rule | Value | Why |
| --- | --- | --- |
| A day | Local midnight to local midnight (UTC where the platform gives no offset). The day is a whole number; the rotation is a function of it | A test can set any day; the same date gives the same dailies for friends in one call |
| The deal | One short, one medium, one long. Two of one group never share a day. A challenge dealt the day before is passed over | A day is varied; a returning player sees different things |
| Rotation memory | Worked out from the first day of a 30-day block, so a day needs no stored history; only a block's first day can repeat the day before | A pure function: no state, no drift between devices |
| Expiry | Every daily leaves at the reset, done or not; the new three start at zero, even one dealt again. A player away for a month sees three dailies and nothing else | No debt, no backlog, no catching up |
| Finished | A finished daily stays on the board, done, until the reset | The card shows done, once |
| Orders | Three, drawn from a seeded draw per account (`order_seed`, `order_draws`), not one finished lately. A swap redraws that slot and costs only its own progress. A finished order is replaced when the night is settled | No pay-to-skip; the pool is solo-safe by construction |
| Milestones | Lifetime totals; a best stat (the round reached) is a high-water mark | Facts stored, rungs derived |

### What a night counts

Counted from the events a client hears (`NightTally`), for every player in the night, solo and co-op by the same code.
A stat is a name; a challenge names one.

| Stat | From |
| --- | --- |
| `kills`, `kills:head` (head or weak zone), `kills:melee`, `kills:blast` (a grenade), `kills:boss` | `zombie_removed` (`cause` killed, the `killer_id`, `zone`, `melee`, `boss`) |
| `kills:weapon:<id>` | the same, with the killer's weapon: the last `weapon_equipped`, `shot_fired` or frame reading of that player. A blast has no weapon |
| `kills:type:<id>` | the same, by zombie type |
| `boards_repaired` | `board_repaired` |
| `doors_bought`, `buys`, `fuel_cans` | `purchase_made` (a refusal is `purchase_denied` and counts nothing) |
| `points_earned` | `points_changed` with a gain, without the starting purse |
| `rounds` | `round_ended`, for every player in the lot (down or not: playing always counts) |
| `round` (best) | `round_started`, `game_over` |
| `nights` | `game_over`, for every player still in the lot |

**Not counted yet, and no challenge asks for them** (a challenge the night cannot finish is a broken promise): rescues
(no teammate revive exists in the rules; a downed player gets up when the round ends, and `player_revived` names nobody
who helped), weapon mastery steps (mastery is not built), lighting goals that need the circuits' state (they are the
generator's, not a player's), and every "Together" order. Each is one stat and a data record the day its event exists.

### The read API

One small class, `ChallengeBoard` (`game/gameplay/challenges/challenge_board.gd`), is everything the main menu's home
panel and the Challenges tab (#397) read. It loads the save, deals today's dailies and saves what changed; it holds no
node.

| Call | Answers |
| --- | --- |
| `ChallengeBoard.open()` | The player's board (the save at `user://challenges.json`; a clock and catalogue can be passed for tests and captures) |
| `dailies()` | Today's three: `id`, `text`, `progress`, `target`, `fraction`, `done`, `tier`, `reward` |
| `orders()` | The open orders: the same keys plus `slot` and `pillar` |
| `milestones()` | Each ladder: `text` (the next step), `value`, `rung`, `rungs`, `target` (0 when done), `fraction` toward the next step, `done` |
| `seconds_to_refresh()`, `refresh_text()` | Time to the next dailies, "6 h 12 min" |
| `swap_order(slot)`, `refresh()`, signal `changed` | The one write the menu makes; `refresh()` when the screen is shown again |

### The save

Facts only, in the platform backend's envelope (`{revision, schemaVersion, data}`, [save
format](../research/platform-backend.md#save-format)): the day the dailies were dealt for, each daily's day and
progress, each order's progress, the order seed and its draw count, the lifetime totals by stat, how many dailies and
orders were ever finished. Today it is the file `user://challenges.json`; the backend's `challenges` slot takes the
same text for a signed-in account (#1075). The rules: `schemaVersion` is 1; a newer version is never read or
overwritten (an old client cannot wipe progress); a damaged file is set aside as `.broken` and play starts fresh;
every number is small (a count or a seed under 2^31), so none needs the backend's string rule for 64-bit values; a
night saves at the end of every round and at the end of the night, so a quit loses at most the round in progress. Only
a night a person plays writes the save (bots, captures and tests have no board). **Online, the server awards (rule
9)**: the same `NightTally` and `ChallengeTracker` run on the game server, following every signed-in seat and announcing
what is done (built, #1076: [how it works](../research/progression.md#the-game-server-follows-the-challenges-1076)).
The server reads the account's board from the backend once, when the seat sits down, and writes it back in each round's
report; the client's local board is a cache that keeps counting as it did, and the in-night prompt shows the server's
word. A signed-in solo night runs it locally.

### The progress prompt in the night

A small checkpoint that says a challenge moved one step: a quarter mark (25, 50, 75, 100 percent) of a daily or an
order, or a milestone step reached. The rules, drawn from the [HUD](hud.md) and its [research](../research/hud.md):

- **Rare and quiet.** A target under 4 is only said when done (a quarter of 3 is no step). A jump over two marks says
  the highest. One prompt per challenge per moment; a daily, an order and a milestone crossing in the same instant are
  three prompts in a queue, not one crowded card.
- **A half-second read.** The name of the thing in at most six words, the count as the large part (`12 / 40`), and
  four punch-card dots, one more punched at each quarter. Nothing else: no reward text, no explanation (the Challenges
  tab explains).
- **One home.** It does not repeat a number the HUD already owns (points, round). Progress toward a challenge lives
  here and on the tab, nowhere else in the night.
- **Never over the crosshair or the round counter,** nor the prompt card, the gains, the feed, health or ammo. It
  sits in the free band on the screen's left edge, a third of the way down (it stays on the left for a left hand),
  and a test checks it against the HUD's measured parts at every canvas the HUD test uses.
- **Panels appear on change and leave.** In 0.25 s, held about 2.4 s, out 0.4 s (completions hold 3.2 s). With two or
  more waiting, holds shorten to 1.6 s so a burst of advances never queues up a minute of prompts. A completion is
  never dropped; the lowest quarter marks go first when more than three wait. Stale prompts (older than 20 s) are
  dropped, so one never describes something long gone.
- **Calm while it matters.** Nothing new starts while the player is down; the queue waits (and still goes stale).
- **A sound.** One soft cue: a short tick for a quarter mark, a rising pair for a finished challenge or a milestone,
  on the UI bus, quieter than a shot, made from `tools/audio/challenge_recipes.py` (a ticket punch, then two soft
  notes a fifth apart; no generated voice).
- **Reduced motion and touch.** Reduced motion fades without sliding. The touch layout keeps clear of the fire
  and move buttons.
- **A setting.** `Challenge prompts`: all, completions and milestones only, or off. Nothing is hidden by default.

**The look** is the maintainer's choice for the main menu, "The program" (2026-11-02): a paper ticket, cream with dark
ink, notched like the HUD's cards, a perforated tear line down its left edge, progress as punch-card dots (a punched
hole is a quarter done), the finish a fifth mark: the last hole punched and the caption `FINISHED`. Two directions
were drawn for it first (a dark lit-sign card with a row of bulbs, and this ticket); the ticket was chosen so the
night and the menu read as one set of paper.

### The menu (issue #397)

The home panel shows the day's three dailies as three plain lines with their counts, the order nearest to done, and
"New dailies in 6 h 12 min" in small print. The Challenges tab has three groups (Today, Orders, Milestones) and a swap
on each order. Both read `ChallengeBoard` and nothing else. The menu's look is the maintainer's choice for the main
menu, "The program": paper tickets, with progress as punch-card dots; the night's prompt below matches it.

### The challenge list for cards and emblems

Every challenge names a stat the night counts, or says what must be added. Marks: **yes** counted today by
`NightTally`; **line** one tally line, the event already exists; **event** something must be emitted first. A
challenge with a **line** or **event** is not offered until its stat exists (rule 15), so the first release has
the **yes** ones (21 of them) and the rest arrive with the stat (#1074). Challenges that need a **win** arrive with
extraction (#1056).

**Easy** (one night; each gives an emblem)

| Title | The act | Counted |
| --- | --- | --- |
| Walk-in | Play your first night | yes (`nights`) |
| Hammer and nails | Mend 10 boards | yes |
| Open for business | Open a way through | yes |
| Fill 'er up | Deliver a fuel can | yes |
| Say cheese | Your first headshot kill | yes |
| Fire in the hole | A grenade kill | yes |
| Round five | Reach round 5 | yes |
| Regular customer | Spend at the stand five times in one night | yes (`buys`) |
| Pocket money | Earn 2,000 points in one night | yes |
| Try the lot | Kill with five different weapons (any nights) | line (distinct `kills:weapon:*`) |
| Out the back | Play a night in the back rooms | line (the map id) |
| Two's company | Play a night with another person | line (seat count) |

**Grind** (lifetime counters, the top rung of the existing ladders; each gives a card and its emblem)

| Title | The act | Counted |
| --- | --- | --- |
| Ten thousand extras | 10,000 kills | yes (`m_kills` goes to 25,000) |
| Dead eye | 1,500 headshot kills | yes |
| Ironwork | Mend 1,000 boards | yes |
| Gas man | Deliver 150 fuel cans | yes |
| Demolition crew | 1,000 grenade kills | yes |
| Hands only | 1,000 melee kills | yes |
| Headliner hunter | Bring down 100 headliners | yes |
| Long run | Reach round 30 | yes (`m_best_round`) |
| House regular | Play 250 nights | yes |
| The big take | Earn 1,000,000 points in all | yes |
| Full rack | 250 kills with every weapon | yes (`kills:weapon:*`) |
| Pest control | 500 kills of every kind of dead | yes (`kills:type:*`) |

**Odd but fun** (one night or a moment; each gives a card with a joke for a title)

| Title | The act | Counted |
| --- | --- | --- |
| Hands in pockets | Clear a round without firing a shot | line (`shot_fired` per round) |
| Stingy | Reach round 6 without spending a point | line (points spent, per night) |
| Three for one | Three dead with one grenade | line (kills grouped by blast) |
| Carpenter's rush | Mend three boards on one window within ten seconds | line (`board_repaired` times) |
| Door to door | Open every way through before round 5 | line (doors by round) |
| Early bird | Open a door in the first thirty seconds of a night | line (door time) |
| Lights out | Clear round 3 with every circuit off | event (the generator's state) |
| Last bullet | End a round with an empty magazine and nothing in reserve | event (ammo state) |
| Whack-a-mole | Five crawlers with the crowbar within thirty seconds | line |
| Booth holder | Stay in the booth for a whole round | event (area presence) |
| Fell asleep in the car | Be downed in the first five seconds of a round | line |

**Together** (solo-safe: never required for a level; the old rule that a solo player is dealt none stands)

| Title | The act | Counted |
| --- | --- | --- |
| Hand up | Revive a teammate | line (`player_revived` with a reviver) |
| Whole crew | Finish a round with everyone upright | line |
| Pit crew | Mend a board a teammate is also mending | event |
| Hold the line | Five revives in one night | line |
| Nobody home | Let a round end with you having killed nothing in it | line (kills per round) |

**Hidden** (shown as `???` with a riddle until done): *Intermission* (stand at the stand for a whole break: event),
*The long way round* (reach round 8 without using the second door: event), *Dead on arrival* (die in round 1: line),
*Standing room only* (a night with four on the lot and the same four at the end: line), *Final cut* (finish all eleven
tier cards: derived).

**Numbers:** 12 easy, 12 grind, 11 odd, 5 together, 5 hidden = 45 challenges. The existing 26 dailies, 12 orders and
12 milestones stay, and **pay XP** (and a card for finishing a family of orders, or a poster set, below). The
challenge tracker runs on the game server for online nights (#1076) so a finished challenge shows in the popup lane in
real time and every client can hear its celebration.

## Poster sets

![Poster sets](../research/progression-poster-set.png)

*A mock-up, not the game.* The maintainer: "a great addition". A **poster set** is six challenges themed as a fake
B-movie ("Attack of the Fifty-Foot Generator"): each one done uncovers a panel of the poster, and finishing all six
wins the set's calling card and emblem. A set shows on the Challenges tab as its poster with its panels and six rows,
and in the night report when finished. Every challenge in a set is one the night counts (rule 15: the mock's "restart
the generator" and "kill with shock" need their stats first), so the first release has two sets from the 21 counted
challenges and sets arrive as their stats do. Posters are composed from shared parts like the cards, and sets are
solo-safe (no Together challenge in one). Build: #1073.

## The night report and credits

The card at the end of a night: the lines of the report as they paid (Rounds, Points, Upkeep, Headliners, challenges,
the first game of the day), the level bar toward the next level and what it gives ("next: a lanyard at 19"). XP is
credited **live** during the night, so the report is the receipt: it repeats the level the popups announced, and never
first-announces one (#1068). A Guest account earns and shows XP like any other; a night with no account at all earns
nothing, and the report shows no XP. **Credits** (decision
16, #1069): the night ends with a film's credits where each player gets a crew title for what they did most ("Key
Grip: most boards mended", "Best Boy: most fuel cans", "Stunt Double: most times down") and a line of XP, chosen by
rule from `NightTally`; solo gets a credit too.

**Built (#1068).** The end board (`HudEndBoard`, the night report) has a ticket under the round line,
`HudNightReport`: a line for each thing that paid (Rounds, Points, Upkeep, Headliners, Rescues, Challenges, Opening
night, First game of the day; only those that paid), the night's total, the level (`LEVEL 2 TO 4` when the night
crossed some) with its bar (what the account had in the level, then what the night added), what the crossed levels
gave, and the next level that gives something to wear or play (levels whose art is not drawn yet are not promised, as
in the popups). The report adds no number of its own: `ReportTracker` sums the `sources` of the `xp_gained` events
the client hears (the game server's tally, or the local rules' in a signed-in solo night, a Guest account included),
and `NightReport` cuts them into whole XP so that **the lines add up to the total exactly** (the XP a rounded-down
line loses goes to the lines that lost most; a night over the cap ends in a negative "Night limit" line). A night
nobody keeps (no account at all) is counted by the client with the same `XpRules.worth` and shown under the heading
"your night, unsaved" with the XP it would have paid, no bar and "no account: this night was not saved". The
players' rows are untouched by it (the icon and level beside a name are #1077's).

**Built (#1069).** The credits are a second ticket under the players' ticket on the end board
(`HudCredits`): a line for every player with their crew title, what it was for, their name and the XP the night paid
them (nothing where the server told none: a bot, or a night nobody keeps). `NightCredits.award` is a pure function of
what `NightTally` counted: the titles of `crew_titles.json` are handed out in the order of the file (the rarer deeds
first, so the top scorer does not take them all), each to the player with the most of its stat among those without a
title, a tie to the lower seat, a stat of zero to no one; a player has at most one, and the rest are Extras, so a solo
night has its credit too. The titles name only stats the night counts: Special Effects (headliners felled), Stunt
Coordinator (revives), Best Boy (fuel cans), Location Manager (doors opened), Key Grip (boards mended), Stunt Double
(times down; `NightTally` now counts `downs` from `player_downed`) and Executive Producer (points earned). A client
counts them for every player in `CrewTracker` (only those stats, and only a boss kill of the horde) and reads each
seat's XP from the `xp_gained` every client hears; `ReportTracker` owns it, so the Night itself gains no line. The rows
of the two tickets share the screen's height, to a floor, so eight players fit the smallest canvas.

## Popups, motion and sound

![Popup storyboard](../research/progression-popups.png)

- **In real time.** A level, an unlock, a tier or a finished challenge shows **as soon as it triggers, during play**
  (the maintainer, decision 9), not at the break. In a menu the cards are top centre; in a night they sit in
  the **popup lane just under the round banner**, which owns top centre while the dead are out. A challenge's quarter
  mark keeps its own left-edge prompt ([built](#the-progress-prompt-in-the-night)). A card never shows during the
  arrival drop (#1057), it waits for the fade back in. A new HUD test measures the lane against the banner, the
  marquee and the boss bar at every canvas, and the phone layout.
- **Look:** the paper ticket of the menu and the night's prompt ("the program"): cream, dark ink, a notch, a
  perforation. A **level card** is wide: the icon on the left, `LEVEL UP`, the big number, a row of punch holes toward
  the next. An **unlock card** is half the height: a swatch or thumbnail, `NEW TOP`, the name. A small XP gain is a
  line on the level bar, not a card.
- **Motion** (one language; "Animations for this stuff need to be good"): the level card drops in 0.25 s with a small
  overshoot, the icon scales 0.8 to 1.1 to 1 (a stamp); unlock cards follow 0.15 s apart; each holds 2.6 s (unlock 2.0
  s, tier 3.6 s) and slides up when the one above leaves; **three visible at most**, the oldest leaves first; a queue
  of eight, then the lowest are merged ("3 new items"). Reduced motion fades without sliding. A setting: all, big ones
  only, off. **Good animation is an acceptance check of the popup issue (#1064), proved by clips, including a stack of
  cards arriving during a fight**, read frame by frame and attached for the maintainer to judge.
- **Sound** (recipes of our own, synthesised: a *moment* is the top weight of the sound ladder, [menu
  sounds](../research/menu-sfx.md)). The maintainer asked for a **record scratch** ("like how Tony Hawk's Pro Skater
  has done it") when a challenge is done and something **"more honorable sounding or battlefield-like"** for a level
  up. The scratch is a style reference: **no audio is taken from any game**; both are made here (#1062):

| Cue | Sound | Length | Peak |
| --- | --- | ---: | --- |
| Challenge done | a record scratch of our own making, then room for the character voice line that follows | 0.6 s | the commit's -13 dBFS |
| Level up | honourable and battlefield-like: a snare roll into a short brass call | 1.1 s | 2 dB above the commit |
| Tier up | the same, bigger: a longer roll, a fuller brass chord that rises and holds, a low drum hit | 2.0 s | the loudest menu sound, still 6 dB under a pistol shot |
| Unlock | a ticket punch and one soft bell, a little brighter each time it plays inside two seconds (a stack climbs a pentatonic scale, four steps at most, then holds) | 0.35 s | the commit's -13 dBFS |
| Card, emblem or frame earned | an unlock with a paper rustle | 0.5 s | the commit |

  Checked by analysis: peak and K-weighted loudness against the bed and against a night's mix, the spectrum, the
  first-50-ms share, no clipping, a stack of eight in two seconds under the peak, and a level up during a gun burst
  still audible. Nothing is sound-only: the cards are the picture. This replaces the first proposal's ticket punch and
  bells for level and tier cues.

## Voice lines

The maintainer: **new voice lines for progression events, heard by all clients**, **multiple celebration lines for
every event so they do not repeat**, and "We will always be using ElevenLabs. I'll get us more credits and a
commercial license." So (#1063): several celebration takes each for a level up, a tier up, an unlock, a challenge done
(the line after the record scratch), a poster set, a card, emblem or frame, and the first game of the day, male and
female, made with ElevenLabs. Every client hears them through the server events the XP issues emit: `SoldierVoice`
already makes a voice from a server event, and a teammate's level up is heard by everyone. **Priority:** they outrank
combat chatter but not urgent lines (hurt, downed, a boss, a warning). **Made (#1063, 2026-11-04)**: 24 takes in each
voice on the free tier, at the maintainer's word ("go ahead and get them going, I'll get the package with commercial
rights in a moment"); they are **not licensed for commercial use** and are regenerated under the commercial plan before
release ([#252](https://github.com/Ryubara/deadnight/issues/252)). The server's `level_up`, `tier_up` and
`unlock_earned` are wired to them for every client; `challenge_done` waits for the challenge tracker (#1076)
([research](../research/audio.md#the-progression-voice-lines-1063),
[sound design](audio.md#the-soldiers-voices)).

## Level icons

![Sample level icons](../research/progression-icons.png)

- **Style:** flat shapes, one dark ink outline, three or four colours a glyph, drawn objects of the drive-in and the
  B-movie. A tier is a frame (ticket, token or sign) and a colour; a level is a hand-picked object. Hand-picked, not
  generated: fifty-five named drawings, each checked against its neighbours so that no two read alike at 24 px.
- **Source:** one SVG per level in the repository (128 by 128; **no `<text>`**: the rasteriser draws none, so the
  number is drawn by the game beside the icon), in `game/assets/ui/levels/`. Twelve samples are in
  `docs/research/progression-icons/`.
- **Export for Godot:** a tool script (`Image.load_svg_from_string` in a headless run) rasterises every SVG into **one
  atlas PNG** (64 px cells for tags and popups, 128 px for the plate), committed with a manifest; a CI check fails
  when an SVG changed and the atlas did not.
- Original drawings; none traced from any game. Build: #1060.

## The level over a head

The HUD's ally marker (`HudMarkers`, drawn in screen space) shows a name above a triangle. It becomes **icon, level,
name**: the icon from the 64 px atlas at 24 px, the level right beside it, a little padding, then the name, in the
same marker so it keeps its place rules. This is the maintainer's order ("icon, then level to the right of it, with a
bit of padding to the right and it shows the players name"), and it is the same **everywhere** a level shows: over a
head, in the bottom-left player boxes, on the scoreboard, in the night report and in the lobby's seat list. Two gaps
decide it and live in one place, `LevelTag`: `ICON_GAP` (4) between the icon and the level, tight, and `NAME_GAP` (12)
between the level and the name, visibly larger. A row with no level (a bot, a seat without one, the setting off) is
the name alone, with no badge and no gap. In a list (the scoreboard, the report, the lobby, the boxes) a level has the
room of two digits, so the names of the people start on one line and 55 is never cut; over a head the level takes its
own width and the whole tag is centred as a bare name is. In the compact box the name ends in an ellipsis before the
badge or the points are cut. **Shown by default**
(decision 18); a setting hides every level on the viewer's own screen. The level comes from the server's XP tally, which
every client hears (the WELCOME's `levels`, then `account_seated`, `level_up` and `account_left`); the icon is the
level's own. **Bots have no level** and keep
their usual difficulties (the earlier idea of a level near the lobby's average is dropped). A Guest account is an
account and has a level like any other; only a bot has none.
Also on the scoreboard, the lobby list, the night report and the player boxes at the bottom left (calling cards
beside the box come with #1070). A name tag never shows a card or an emblem in the night.
Built in #1077: [how it travels and what it costs](../research/multiplayer.md#the-level-and-icon-beside-a-name-1077).
The setting is **Player levels** (Settings, Accessibility). A level gained in a night reaches the tags by the
`level_up` event the tally already sends (#1114), so a tag changes the moment the level does.

## Prestige

**Open.** The maintainer: "Prestige is optional. There can be exclusive rewards earned for prestiging. But normally
prestiging comes with resetting everything a player has, so what will reset? Prestiging comes with a loss just for
flex value and we lack that currently." So the first plan's "keep everything, add a gold star" is **rejected**:
prestige must cost something. What resets, and which rewards are exclusive, depends on the research in #1055. Until
then **no prestige is built and nothing is filed**; XP past level 55 is stored and shows a full bar. The research
([prestige](../research/progression.md#incremental-games-prestige-and-frequent-small-rewards)) is the evidence: resets
read as artificial length when they give nothing back, and are accepted when they open new content.

## Extraction

A night can be won. Filed as **#1056** (the design, a proposal for the maintainer: each point is a choice)
and **#1057** (the helicopter drop that opens a night). The maintainer's words: "Every map needs to meet a quota, and
also steps that have been completed to be able to extract. Steps that are unique to the map itself." and "there needs
to be maybe a kill quota, and steps to complete to escape like map-level steps. But we need to make sure the map-level
steps aren't too easy and if they are easy then it may need to get expanded upon a bit."

**The story** is that the players are **an elite military unit dropped by helicopter** at locations "to take out the
zombies and fix up the area before extract". On arrival, "when a player spawns in they hear a helicopter sound in the
distance. And a cutscene plays that aims at an angled sky view downward that shows them 'landing' from a rope and a
light shines below the helicopter and then after that their screen fades black and they 'spawn in' -- this will still
work for clients that join late too, other clients won't see it and keeps everything moving smoothly." (That replaces
the earlier idea of "caught in the middle of the start of a zombie apocalypse".)

What it means for progression: what a win pays in XP and the "beat this map" plate frames (#1072) are extraction's to
settle (#1056 lists them). Nothing in the ladder assumes a win; win-based challenges wait. A popup never shows during
the arrival drop.

## Research still to come: rarity, modifiers, attachments, skills

- **Cosmetic rarity** (#1053): the maintainer wants it, with wild shader looks (wings with blue fire and glow). It
  needs research on how other games do rarity and a name for the tiers. **The ladder does not assume its outcome**:
  the unlock table has names and levels only.
- **Weapon modifiers, attachments, skills and skins** (#1055, with prestige): "I think we may need to start looking
  into weapon modifiers, skills, attachments, and cool skins ... how attachments can play a part (BO3 did attachments
  and skins pretty good in zombies ...) but gun modifiers and maybe character skills (like skill tree) would be worth
  looking into." They bear on the combat bonuses ("how slight") and on what prestige resets.
- **Parked: mastery and trims.** The earlier plan's per-weapon mastery (levels 1 to 10 from points earned with a
  weapon) and side-grade *trims*, with an audit that a trim stays within five percent of the base, is kept below as
  input to #1055, not as a plan: weapons are free to all, and a mastery ladder is a second ladder the maintainer has
  not asked for.

| Mastery level | Reward |
| --- | --- |
| 2 | First finish (paint) |
| 3 | **Trim B**, a side-grade |
| 6 | **Trim C**, a second side-grade |
| 10 | Mastery finish (a showpiece look) |

A **trim** is chosen before a night, one per weapon, and must meet the *side-grade rule*: it changes a decision and
nets out against its cost (a shotgun's tight *Choke* against a loose *Wide*, a rifle's *Tracer* that paints targets
for the team). The audit: a seeded headless bot night with each weapon-trim pair must land within five percent of the
base on rounds reached and points per round.

## Storage and trust

- **What is stored: facts.** `{schemaVersion, xp (raw), equipped {card, emblem, frame}, done [challenge ids],
  opening_night, bonus_day}`; level, unlocks and the next reward are computed from the tables, so retuning never
  migrates. The challenge save keeps its own lifetime counters.
- **Where:** the backend's saved progress (`PUT/GET /saves/:slot`, an envelope with a revision and a schema version,
  64 KiB; a profile is a few kilobytes): slot `profile`, and slot `challenges` for the board. **No offline XP:** XP
  exists only for an account the server tracks, and **a Guest account is one** (the maintainer, 2026-11-04: "only
  signed in accounts earn XP since we only track XP on the server. But even \"Guest\" accounts will be tracked on
  server"). A local file is a cache and a retry queue for that account's own writes, never a second store, and **there
  is no merge of an offline save**. A night with no account at all (the backend cannot be reached) earns nothing. A
  night never waits on the backend: a failed write is sent again.
- **A Guest account lasts 7 days without a sign-in** (built, #1080). The backend signs a guest in with a long-lived
  signed credential (`guestToken`) that the game keeps in its own storage (`user://guest_account.json`, the browser's
  IndexedDB on the web); the same account, with its saves, comes back each time it is signed in to within 7 days of
  the last sign-in, and each sign-in restarts the 7 days. An account idle for 7 days is deleted with its saves; a
  Discord account never is. A forged or expired credential makes a new guest, never another's account. Clearing the
  browser's data is a new guest. Moving a guest to Discord or another source is not built (the maintainer: "we'll talk
  about this more down the line"). How: [Guest accounts](../research/platform-backend.md#guest-accounts).
- **Writes are round-end reports, never per kill.** The game server posts each seat's XP at each round's end and at
  the night's end, keyed by match and round so a retry cannot double-pay; only a server the platform started may post
  one. A signed-in solo client writes its profile at round ends and the backend **caps** it: at most about 120 XP a
  minute of wall clock between writes (a strong four-player night is about 35 XP a minute at this curve), a schema it
  knows, a level that follows from raw XP (#1075).
- **The first game of the day:** the day number (the dailies' own) comes with the write and is accepted once, within one
  day of the backend's date.
- **Built (#1075):** the `profile` slot, the round report (`POST /internal/matches/:id/report`, keyed by match, kind,
  round and account), the ledger and the clamp are in the platform backend; the details, the error names and what the
  game server must send are in [Progression on the backend](../research/platform-backend.md#progression-the-profile-slot-round-reports-and-the-xp-clamp).
  One decision there: the server posts XP **without** the two one-offs and claims them (`openingNight`, `bonusDay`); the
  backend knows the profile and pays each once.
- **Built (#1106): a signed-in solo night sends its XP.** The queue holds **changes** (`{id, xp, opening_night,
  bonus_day, done}`), not profiles: the backend takes the whole profile on a revision, so each send reads the account's
  own latest, puts the change on it and writes that. The account's profile is read at sign-in and replaces the file's
  (no merge of an offline file). How: [the solo night's write](../research/progression.md#a-signed-in-solo-nights-write-1106).
- **What a level is seen by:** the ticket the backend mints carries `level`, `icon` and `xp`; never the client's word
  in the night.
- **What would force more:** a leaderboard, any ranking, anything paid, or a reward a cheater would gain from (none
  here). Say so before any is added.

| Record | Fields | Written by | Notes |
| --- | --- | --- | --- |
| `account` | id, Discord user id, display name copy, created, last seen, schema version | sign-in | Nothing else personal. Delete and export on request |
| `profile` | `xp` (raw), equipped card, emblem and frame, `opening_night`, `bonus_day` | the game server's round reports; a solo client (capped); the client for equips | Level and unlocks are derived |
| `challenges` | the board's facts: lifetime counters, done list, orders, dailies | the game server's tracker online; the client solo | The save in [the board](#the-save) |
| `ledger` | account, xp delta, reason, match id, round index, time | round reports | Append only; the balance is its sum; support can see why. No second currency |
| `night_log` | last 50 nights: match id, rounds, lines, time | round reports | For the history screen and tuning telemetry |
| `match_report` | match id, round index, server version, ruleset hash, per-player facts, signature | game server | Idempotency key is (match id, round index) |

| Question | Answer |
| --- | --- |
| Who can write progression online? | Only a game server instance started by the platform; a client cannot post XP for an online night |
| What if the backend is down? | The night runs; reports queue on the game server and flush later |
| What if the game server crashes? | Rounds reported so far stand; the unfinished one is lost |
| Cheating? | Plausibility caps per line, an XP-per-minute ceiling for solo, a ruleset hash that must match the canonical tuning |
| Retuning | Stored raw numbers, derived levels; an item added to a level is granted on next sign-in |
| Telemetry | Nights per day, level at day 7, hours to each level (the curve is retuned from it), quit round, challenge completion time |

## How a fresh night stays fair

| Situation | Rule |
| --- | --- |
| Veteran and newcomer on the same night | Both start with the same points, fuel, lot and circuits, and **every weapon and tonic**. The veteran has more cosmetics and, by the maintainer's decision, a slightly better kit; a level-1 player can still win the night (audited, [combat bonuses](#combat-bonuses)) |
| Whose pool does the crane use | The player's own. Points, shop and crane are already per-player in the economy |
| A lobby of friends in one Discord call | The common case. No queue sorts them; level is shown, never used to match |
| A public or fill-in lobby | The host can tag the lobby *Newcomers welcome* (shown on the lobby card, nothing else changes) |
| A guest below the host's map level | Plays the map as a visitor; the host's level decides the lot |
| A custom or modded lobby | Only a server instance the platform started with the canonical tuning (a ruleset hash) can award anything |
| Comparing results (leaderboards, if ever) | Only **Standard Nights** count: no combat bonus, the base kit |
| Solo | Same pace as a team; orders drawn from the solo-safe pool |

## First hours

From the measured cells (average solo, nights only, with the opening night's 50 XP): the table says where a player is
after a time, so "the first level up satisfaction early on" can be read off.

| Time played | Level, average solo | Level, average four | Just arrived (average solo) |
| ---: | ---: | ---: | --- |
| 1 min | 2 | 2 | The first level; the plate's cards and emblems open |
| 15 min | 7 | 6 | Colour Cherry, rolled sleeves, a tier card at 5, Usher's cap, Mustard |
| 30 min | 11 | 9 | **The back rooms (level 10)**; Shorts |
| 1 h | 16 | 14 | Newsreel pieces and the Tank top (16); Pink is next |
| 2 h | 24 | 22 | Cinema glasses; Ranger hat |
| 3 h | 31 | 27 | Chrome frame (29); Overalls |
| 5 h | 41 | 37 | Brass frame (37); the Creature mask (48) is the next tier's |
| 8 h | 53 | 47 | The last tiers; level 55 is next |

| Knob | First value | What it moves | Retune when |
| --- | --- | --- | --- |
| XP to leave a level | 85 rising to 590 by tier | Pace to 55 | Telemetry says hours to 55 are not about 8, or the first level takes more than about 2 minutes |
| Rounds | 20 a round | The base of a night | The rounds work changes the round length |
| Points | 1 XP per 100 points | How much a kill is worth | Hordes at count x5 are not fast enough or too fast |
| Rescue | 40, cap 5 | Revive appetite | Revive-farming appears |
| Opening night | 50 | The first night's headline | The first level takes too long or comes too fast |
| First game of the day | 100 | The pull to play one night a day | It reads as a streak or as a chore |
| Night cap | 1,500 | Farming | A real night reaches it |
| Order sizes | 75 / 200 / 600 XP | Goal appeal | Orders do not finish at their stated length |

## Later: the weekly bill

A **Double Feature** is a weekly opt-in lobby type with two rule twists (for example, "the lights flicker" and "double
sprinters") and one cosmetic *reel poster*. The bill changes weekly, nothing is lost by skipping it, and every poster
returns within a few weeks (the Helldivers lesson). It needs a weekly operator task, so it ships only if the maintainer
wants live operations; it is not filed.

## Build order

The build issues, filed from this plan (each with its own tests and captures; `Depends on` where they touch the same
files):

| Step | Issue | Depends on |
| --- | --- | --- |
| 1 | #1058 XP, the 8-hour curve and the profile (first; the others read its tables) | - |
| 2 | #1075 The backend's profile slot, round reports and clamp | 1 |
| 3 | #1059 The game server awards XP per kill, live, and the horde measurement | 1 |
| 4 | #1060 The 55 level icons and the atlas (art; parallel) | - |
| 5 | #1061 More mouths, free (art; parallel) | - |
| 6 | #1062 The record scratch, level-up fanfare and unlock sounds (audio; parallel) | - |
| 7 | #1063 Progression voice lines (made on the free tier; regenerate under the commercial plan, #252) | 3, 6 |
| 8 | #1064 The popup lane, live, with motion proved by clips | 3, 4, 6 |
| 9 | #1065 The wardrobe grid, `???`, locks | 1, 4 |
| 10 | #1066 The Costumes tab | 9 |
| 11 | #1067 Maps by level | 1 |
| 12 | #1068 The night report | 3 |
| 13 | #1069 Film credits | 12 |
| 14 | #1070 Calling cards and emblems | 1, 9 |
| 15 | #1071 Plate frames | 14 |
| 16 | #1072 Frames for beating a map | 15, #1056 |
| 17 | #1073 Poster sets | 14 |
| 18 | #1074 The stats the odd and together challenges need | 14 |
| 19 | #1076 The challenge tracker on the game server | 3, 2 |
| 20 | #1077 The level and icon over names online | 1, 4, 2 |
| 21 | #1078 The 15 new wearables, in two waves (art) | - |

Not filed on purpose: **prestige** (waits on #1055), the **combat bonuses** (#1055), **rarity**
(#1053), **extraction** (#1056, #1057 already exist), the weekly bill. Risks: the **15 new wearables and the mouths
are the long pole** (art); the ladder ships without them. XP is a model of bots (the first real nights retune the
curve).

## Open questions for the maintainer

| # | Question | Leaning |
| --- | --- | --- |
| 1 | What does prestige reset, and which rewards are exclusive? | After #1055 |
| 2 | How slight is the combat edge, and what is it (ammunition, reload, an attachment, a skill)? | After #1055 |
| 3 | Are 50 XP for the opening night and 100 for the first game of the day the right size? | First guesses; tune from telemetry |
| 4 | Do the voice lines wait for the new credits and the commercial licence? | Made now on the free tier (maintainer, 2026-11-04); regenerated under the commercial plan before release (#252) |
| 5 | Which rarity tiers, if any, and what do the top ones cost? | #1053 |
| 6 | Extraction's quota, steps, last stand and what a win pays | #1056 |
| 7 | Is a weekly bill (live operations) in scope, and who runs it? | Defer |
| 8 | How do we treat the account of a young player (Discord's age rules, name plates, data retention)? | Word cards only; export and delete from day one |

## Sources, and what we could not read

Search and the cited pages were the only research. Pages that refused the fetch tool (Game Developer's GDC 2023 Deep
Rock talk summary, several press articles) are cited only for what the search summary said. Steam forum threads are
anecdotes. Where a number is ours it sits in a table above; no figure from another game is used as a target. The curve
is measured with the [balance simulator](../research/balance-simulator.md) (the numbers are on the [research
page](../research/progression.md#the-8-hour-curve-measured)).

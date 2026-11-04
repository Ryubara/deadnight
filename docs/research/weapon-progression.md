# Attachments, modifiers, skills, skins and prestige

Research and a proposal for issue #1055, 2026-11-04. No game change: this page is what we read, what the balance
simulator measured, and what I would build, with every point a **choice** for the maintainer. It sits beside
[Progression: levels 1 to 55](progression.md) (the ladder, the icons, the popups) and the design page
[Permanent progression](../design/progression.md) (its rules 1 and 2 are replaced below). Other games are studied for
understanding only: no name, number, icon, layout or asset of any of them is used here or in the plan.

The maintainer's question, in his words: *"prestiging comes with resetting everything a player has, so what will
reset? Prestiging comes with a loss just for flex value and we lack that currently"*, and, later the same day, *"the
higher level player would ideally have a slightly better kit but that's a reward for them playing more"*. Weapons and
tonics stay free for everyone; the climb is about 8 hours.

## The answer in six lines

1. **What resets (my recommendation).** Prestige is optional, opens at level 55, and puts the **kit and the outfit**
   back to the start: the level (to 1), every wardrobe piece and cloth colour the ladder gave, the level plate frames,
   the skill picks, and the attachments and re-cut finishes earned by using weapons. A prestige costs one more climb,
   about **8 hours** for an average solo player (the number is measured below).
2. **What stays.** Everything that records a feat rather than time: calling cards and emblems, challenge and
   "beat this map" frames, weapon skins earned by a feat, lifetime stats, and everything prestige itself gives. **Maps
   stay unlocked** (access to the game is not a flex), and each prestige lets the player **keep one item** for good
   (the genre's permanent unlock).
3. **What it gives.** A visible mark (a star on the level icon, a card, an emblem, a frame), a few exclusives, and an
   XP bonus on the next climb (+5 percent a prestige, at most +25) which is convenience, not combat power. Exclusives
   lean on extraction ([#1056](https://github.com/Ryubara/deadnight/issues/1056)): the best of each prestige is
   earned by winning a night on that climb.
4. **How slight is "slightly".** Measured with the balance simulator: a full level-55 kit worth **about +5 percent
   rounds reached and +9 percent kills** to an average solo player, and about **+12 percent points** to the one wearing
   it beside three level-1 teammates, whose own points hardly move (+1 percent) ([the
   tables](#what-a-slightly-better-kit-does)).
   That is the budget; a test holds it.
5. **The honest part.** Because the power is small by design, the *power* a prestige takes back is small too. The
   loss that carries the flex is the visible one: the level back to 1, the wardrobe back to two of each, the kit
   rebuilt. If the maintainer wants a bigger loss than that, the only honest lever is a bigger kit, and the simulator
   says where that stops being "slightly" (about double: [below](#where-slightly-stops)).
6. **The systems.** Attachments (earned by weapon-class kills, 3 slots, two options each) and skill picks (one of two
   at every fifth level) carry the power; gun modifiers (a choice of how the re-cut goes) and weapon skins carry
   identity. Attachment art is the expensive part ([cost](#what-it-costs-to-build)).

## What the genre does

"read" means the page was fetched and answered through the fetch tool (a small model reads the page for a question, so
wording is a paraphrase); "summary" means a search snippet, or a refused fetch. Forum threads are anecdotal. The Call of
Duty wiki refused every fetch, so several Black Ops 3 Zombies specifics (below) are **not found** rather than guessed.

### Black Ops 3 Zombies, the maintainer's example

| What | What we found | Source | |
| --- | --- | --- | --- |
| Rank and kits | Zombies has a rank of its own; "higher ranks unlock upgrades for customizing guns with attachments" (weapon kits); players start with five standard gums | [Gfinity](https://www.gfinityesports.com/article/black-ops-3-zombies-first-impressions) | read |
| Gunsmith and paintshop | A multiplayer section: up to five attachments and optics on a gun; the paintshop allows up to 64 layers on three sides | [CharlieIntel](https://www.charlieintel.com/call-of-duty/black-ops-3-features-new-weapon-customization-gunsmith-with-new-paintshop-feature-29769/) | read |
| Gobblegums | One-use or timed boosts. Classic gums come on level-up and are unlimited; Mega gums come from a slot machine paid in a drop currency and are limited by an inventory; a pack of five is chosen before the match; four visual rarities | [Accelerated Ideas](https://www.accelerated-ideas.com/news/black-ops-3-zombies--gobble-gum-explained.aspx), [GIGA](https://www.giga.de/spiele/call-of-duty-black-ops-3/tipps/call-of-duty-black-ops-3-gobblegums-und-power-ups-im-zombie-modus/) | read |
| Prestige (multiplayer page) | Opens at level 55; sets the level to 1 and relocks the things bought with Unlock Tokens (weapons, equipment, perks, wildcards, scorestreaks, specialists); **keeps weapon attachments, challenges, camos, calling cards and Black Market items**; a **Permanent Unlock Token** keeps one item available from level 1; ten prestiges, then Master Prestige and levels to 1000; each of the first five gives a class slot; every prestige a calling card; prestige icons replace the rank icon | [Activision support](https://support.activision.com/uk/en/call-of-duty--black-ops-iii/articles/prestige-mode-in-call-of-duty-black-ops-iii) | read by me |
| Zombies prestige | One source (a forum summary, anecdotal) lists losing "all your gun attachments and unlocks and classic Gobblegum" and reports attachment and camo bugs after prestige; Activision's page does not cover Zombies, and its multiplayer rule says attachments are kept. The two **conflict** | [GameFAQs](https://gamefaqs.gamespot.com/boards/145061-call-of-duty-black-ops-iii/73260063) | summary |
| Permanent unlock choice | One pick per prestige; replies say it matters less after five to seven prestiges, and report regret and accidental picks | [Steam thread](https://steamcommunity.com/app/311210/discussions/0/490125737479746742) | read, anecdotal |
| Not found | Whether box or wall weapons roll attachments, whether attachments change stats in Zombies, how many a weapon carries, whether they show on the model, Pack-a-Punch levels and camos, the gold/diamond camo challenges, character cosmetics | | not found |

So the part of the maintainer's example that is checkable is the **shape**: attachments and camos are *earned by play
and kept*; the one thing the player chooses to keep through a prestige is a single item; the reward is a number, an
icon and a card. How Zombies itself shows an attachment on the weapon was not recoverable, and I do not claim it.

### The same genre's later games (the better-documented ones)

| Game | Attachments, skins | Prestige: resets / keeps / exclusive | Source |
| --- | --- | --- | --- |
| Black Ops 7 | A **weapon prestige** per weapon: resets that weapon's level and relocks its earned attachments (optics stay); keeps camos, reticles, charms. Prestige 1 gives a unique **Prestige Attachment** for the weapon, one Permanent Unlock, a universal camo and an icon; Prestige Master raises the cap to 250 and permanently unlocks all attachments | **Player prestige** resets the level to 1, relocks level unlocks (except base items, emotes, Zombies gums and permanent unlocks) and clears loadouts; **keeps weapon progression, camos, reticles, builds, challenge progress**. Prestige 1: an icon, an operator skin, a calling-card challenge set and one Permanent Unlock; one more per prestige up to ten. Lifetime stats stay viewable | [Activision support](https://support.activision.com/black-ops-7/articles/progression-in-black-ops-7) (read by me) |
| Black Ops 6 | Keeps weapon progression, camos and sights; resets level, most level unlocks, challenge progress and combat stats; each prestige gives a permanent unlock token; after ten, 1,000 more levels | | [PCGamesN](https://www.pcgamesn.com/call-of-duty-black-ops-6/prestige) read |
| Modern Warfare 4 (2026) | **Classic prestige** loses level unlocks and class progress for **+20 percent XP**, a Permanent Unlock Token and cosmetics; a **regular prestige** drops the level but keeps everything | | [Gamerfuzion](https://www.gamerfuzion.com/modern-warfare-4-prestige-explained-classic-vs-regular-all-10-prestige-rewards-prestige-master/) read |
| Killing Floor 2 | Perk classes; **every fifth level the player picks one of two skills**, and can swap them before, during and after a match | Prestige needs a perk at 25, resets that perk's XP; gives a unique weapon skin, an icon and **+30 percent XP** for that perk; permanent | [Wikipedia](https://en.wikipedia.org/wiki/Killing_Floor_2) read; [GameWatcher](https://www.gamewatcher.com/killing-floor-2-prestige-rewards-5-tips-to-help-you-prestige-fast) read |
| Deep Rock Galactic | Weapon mods in tiers, and **overclocks**: Clean (no drawback, small gain), Balanced (moderate, small drawback), Unstable (big gain, big drawback); the designers say a bad overclock should not exist, each is "an interesting gameplay twist"; one per weapon | **Promotion** at class level 25: the level resets, **unlocks stay**, a star is added; rewards a perk slot, content access and cosmetics; one guide calls it "a status symbol" | [Devtrackers](https://devtrackers.gg/deep-rock-galactic/p/b59d19f0-roadmap-june-endgame-faq), [wiki](https://deeprockgalactic.wiki.gg/wiki/Overclocks), [TheGamer](https://www.thegamer.com/deep-rock-galactic-how-to-promote-character/) read |
| Payday 2 | Skill trees (structure **not found**) | **Infamy** at level 100: resets level, skill points and cash; **keeps** weapons, mods, masks (but weapons are locked behind their levels again); gives an infamy level, a tree point and exclusive items | [MP1st](https://mp1st.com/news/upcoming-payday-2-update-allows-infamous-prestige-progress-wipe), [Gaming Nexus](https://www.gamingnexus.com/News/31925/Payday-2-will-now-allow-you-to-become-infamous-) read |
| World War Z | Weapons level by use; class perks | Prestige keeps existing perks, adds four new perks per class per rank and a prestige weapon variant (one unofficial FAQ says the opposite; it is not relied on) | [MP1st](https://mp1st.com/news/world-war-z-upcoming-content-called-kill-it-with-fire-includes-prestige-ranks-new-maps-and-more) read |
| RuneScape | | The developers' own reason: top levels were so common they "no longer signal much"; a reset lets players compete again; lifetime XP is kept and titles and emotes show it | [Dev blog](https://runescape.wiki/w/Update:Dev_Blog_-_Prestige) read |

### What we take from it

| Pattern | Evidence | Take |
| --- | --- | --- |
| **The line is kit and outfit versus record.** What the level unlocked is relocked; what a feat earned (camos, cards, challenges, lifetime stats) is kept | BO3, BO6 and BO7 all keep camos and challenge progress; BO7 keeps weapon progression on a player prestige and takes it on a *weapon* prestige | Same line, drawn the same way: kit and outfit reset, trophies stay |
| **One chosen item is kept** | Permanent Unlock Token (BO3, BO6, BO7, MW4) | A Keepsake per prestige; the Steam thread says the pick matters less late, so cap it |
| **A prestige is paid in numbers, not power** | +30 percent XP (KF2), +20 percent XP (MW4), an icon, a card, a class slot | XP bonus and marks; no combat power |
| **Revoking something earned is the thing players resent** | Cold War: icons bought with keys were usable only at the top prestige, and a season reset revoked access, so players regrind ([CharlieIntel](https://www.charlieintel.com/black-ops-cold-war/black-ops-cold-war-players-call-for-changes-to-prestige-master-icons-86149/), read). BO6: removing legacy XP tokens was reversed within a day after backlash ([Push Square](https://pushsquare.com/news/2024/11/strong-fan-backlash-forces-treyarch-to-reverse-black-ops-6-xp-token-erasure), read). Payday 2's reset was read as "extending progression artificially" ([design page](../design/progression.md#what-the-research-says)) | Nothing a feat earned, and nothing prestige gave, is ever revoked; a reset is announced with a list of what goes |
| **A wipe with no payoff drains motivation** | Modern Warfare 2019's seasonal rank wipe: "far less motivation to grind"; in a poll of nearly 140,000, only 12 percent wanted to keep seasonal ranks, the rest wanted prestige back ([Upcomer](https://upcomer.com/the-call-of-duty-community-voices-their-demand-for-a-prestige-system-in-black-ops-cold-war), read) | Prestige is a **choice**, never forced; the payoff is visible |
| **Why a reset can be a flex** | RuneScape's developers: a reset restores competition and the display (titles, emotes, lifetime XP kept) shows it. One Roblox glossary says prestige hurts retention when the second run feels like the first or players feel they lost too much (summary). No source calls the loss itself a costly signal for games, and the 2026 DeepMind paper argues high cost is neither necessary nor sufficient for a signal ([arXiv](https://arxiv.org/html/2603.13220), summary) | The **display** is the flex: the star and the history must be seen where the level is seen. The second climb must differ from the first (below) |
| **Veterans stronger in one lobby is a known friction** | Vermintide 2: power restrictions stopped new players joining experienced friends, and the studio removed them on public Veteran and in private games ([PCGamesN](https://www.pcgamesn.com/warhammer-vermintide-2/progression-rework-less-grind), read). Helldivers 2's top upgrades take hundreds of missions (summary). A Deep Rock forum thread: prestige should "never give other players a benefit" (anecdotal). Deep Rock's studio wanted veterans and new players both to add value to a team ([Game Rant](https://gamerant.com/deep-rock-galactic-interview-season-1-co-op-design-battle-pass-progression/), read) | A small edge, never a gate, and the host can turn the kit off for a night ([choice 3](#choices-for-the-maintainer)) |
| **Side-grades or numbers** | Fischer, *Dissecting Progress* (Game Developer, 2014): horizontal progress adds abilities and keeps mechanics interesting; vertical progress is rising numbers and forces enemies to scale against a stronger player, with grinding behind it ([article](https://gamedeveloper.com/design/dissecting-progress), read). Deep Rock's overclocks are the cleanest example of trade-offs | Most of the kit is trade-offs; the power is a small, capped slice ([measured below](#what-a-slightly-better-kit-does)) |

## What Deadnight already has, and why that matters

The night already carries the genre's *in-night* power, bought with points and gone when the night ends:

| In the night (resets every night) | |
| --- | --- |
| The **re-cut** (our upgrade station): x1.75 damage, x1.5 magazine, once a weapon, 5,000 points, one element on the four weakest guns | [Upgrades](../design/upgrades.md) |
| **Six tonics** (health, fire rate, reload, third weapon, revive, reload shock), limit of four | [Perks](../design/perks.md) |
| **17 weapons** in nine classes (starter pistol, pistol, SMG, shotgun, rifle, LMG, sniper, special, melee), all free to every player | [Weapons](../design/weapons.md) |

So a permanent layer must not be a second copy of these. The re-cut and the tonics are the big, bought, in-night power
(+75 percent damage is a hundred times larger than anything below); what is missing is the **small, owned, between-night
layer**: a few percent from what you have played, which can be taken away. That is also why the gun modifier below
*transforms the re-cut* rather than adding a third source of damage.

The earlier rule (design page rules 1 and 2) said permanent data never raises a number and a level-1 and a level-55
player stand with the same tools. The maintainer has replaced it for **combat kit only**: the night's economy, rounds
and
fuel stay the same for everyone, and weapons and tonics stay free. The new rule I propose: *a kit may raise what a
player does with their own weapon by a few percent; it never changes what the dead do, what anything costs, or what a
round is.*

## The four systems

Each is a choice (marked **Choice**): include, change or drop.

### 1. Attachments (power, small, earned by using weapons)

- **Shape.** Three slots on every firearm: **magazine**, **grip** and **barrel**. Each slot has two options; one is the
  plain gain, the other a trade-off (the Deep Rock overclock pattern: plain, balanced, unstable, but only the first
  two).
  Nothing is random. A cosmetic fourth slot, the **sight** (reticle shape and colour), changes no number.
- **How earned: by kills with the weapon's class, not with the account level** (the genre's weapon-level pattern, and
  the one kept through a player prestige in Black Ops 7). The class (`WeaponClass`) is the unit, not the weapon, because
  the simulator shows the box starves rare guns ([below](#what-a-slot-costs-in-hours)): a class opens its three slots at
  150, 600 and 1,500 kills, and a kill with any other class gives a quarter as much (so a class nobody draws still
  moves).
- **How shown.** In the lobby and the night's pause card as words and numbers ("Long mag: 15 percent more rounds"), and
  on the weapon in the hands and on other players' bodies as a part ([cost](#what-it-costs-to-build)).
- **What it does to play.** It is the one place where the weapon gets *different*, not only stronger: the drum is a
  commitment (more rounds, slower reload), the light grip the opposite.

### 2. Gun modifiers (identity and a choice, no new power)

- **Shape.** The re-cut finish. Today a weapon's re-cut is one fixed profile with at most one element. A modifier lets
  the player pick *which way the re-cut goes* before the night, from the finishes they have opened for that weapon:
  explosive, shock, fire (the existing elements) and, for the guns that have none, a numbers-only finish. It changes
  what the 5,000 points buy and nothing else, so it adds **no damage of its own**.
- **How earned.** A finish opens at a class's second slot (600 kills).
- **Not measured.** The simulator does not play elements (its page says so); a finish is held by the element tests, as
  today. **Choice**: ship attachments and skills first and add finishes second.

### 3. Skills (power, small, one pick of two every fifth level)

- **Shape.** Eleven picks across the climb, one at each tier end (levels 5, 10, ... 55), each a pair; the pick can be
  swapped any time in the lobby, free (Killing Floor 2's pattern, which the 2026 genre has kept). Four themes across
  the pairs so the choice reads: the **gunner** (reload, rounds), the **mender** (revive time, health), the
  **runner** (a step of speed, a longer sprint), the **handyman** (boards mended faster, a repair that pays a little
  more). A prestige empties the picks and the next climb re-picks them.
- **Why a pick, not a tree.** A tree needs points, a respec rule, a screen and a story about wasted points; a pair per
  tier is eleven small decisions, readable in a card, with nothing to get wrong. **Choice**: a real tree (more art, more
  UI, more tuning) if the maintainer wants the shape.

### 4. Skins (cosmetic, never reset)

- **Weapon skins** (camos) come from per-class **feats** (kills, headshots, a night without a re-cut, an extraction),
  in the three-tier shape the genre uses (a common set, a special set, a mastery set), with **rarity** from the
  research in [#1053](https://github.com/Ryubara/deadnight/issues/1053). They are the long game and they stay through a
  prestige, because a feat earned them. Prestige adds exclusive skins (below).
- **Character costumes** stay as in [the progression plan](progression.md): level-gated pieces are part of what resets.

## What a "slightly better" kit does

The model: `NightSim` (the balance simulator, [how it works](balance-simulator.md)) with a **loadout laid over chosen
players**: damage, reload, magazine and fire interval as multipliers on the weapon, accuracy, head rate and mobility
added to the skill level, health added to the most, and a multiplier on the chance a blow lands (a "blows that land"
number: 0.97 is 3 percent fewer). The patch is a research tool, kept at the end of this page and not applied ([the
patch](#the-simulator-patch)).
Every cell: seeds 4000 and up, 400 nights, rounds capped at 40, the gate's skill levels (the Rookie, the Regular, the
Veteran of the bots page) and teams of one, two and four. Confidence is the simulator's own: a nights-mean has a 95
percent interval of about plus or minus 0.4 rounds in solo, so a difference under half a round is within noise.

### Which levers matter

One lever at a time, at the **largest size I would ever consider** (so the ranking is clear above the noise), average
and
strong solo players, 400 nights each:

| One lever alone (the ceiling size) | Average solo: rounds | kills | Strong solo: rounds | kills |
| --- | ---: | ---: | ---: | ---: |
| Magazine +50% rounds | +8% | +17% | +14% | +25% |
| Reload 20% faster | +4% | +8% | +8% | +15% |
| Accuracy +5 points | +3% | +6% | +4% | +9% |
| Fire interval -10% | +2% | +5% | +3% | +7% |
| Damage +10% | +2% | +3% | +3% | +6% |
| Health +25 | +4% | +6% | +3% | +6% |
| 10% fewer blows land | +1% | +2% | +3% | +6% |
| 3 points more shooting time | +1% | +2% | +2% | +3% |
| Melee +25% | +0% | +0% | +0% | +0% |

![What each lever and kit is worth](weapon-progression-levers.png)

- **Melee shows no effect because the model almost never swings** (the Regular never goes dry, `dry_rounds` 0 on the
  balance page): the melee and "blows that land" numbers of the kit are therefore **under-measured**, and a melee
  skill is held by the melee tests, not by this table.
- **Rounds in a magazine and reload time are the two big levers** for the Regular and the Veteran: the dead come faster
  than a reload, so every second at the trigger counts. Damage per shot is the weakest lever (a shot kills or does not;
  headshots are already about 80 percent of hits), and accuracy and fire interval are in between. This is why the kit
  puts its weight on the magazine and the grip and gives the barrel only a few percent of damage.
- **Rounding matters at the bottom.** A "+15 percent magazine" is nothing on the flare gun (1) and the double barrel
  (2) and a single round on the magazines of 4 to 10 (the fifty cal's 8 becomes 9): the simulator rounds to the nearest
  round. The rule I would write is "at least one more round on any magazine of 4 or more", so a small gun is not
  silently left out, and the audit counts it.

### The kit I propose, and what it is worth

**The level-55 kit** (everything opened and equipped by a player who has climbed once; `K55` below):
magazine +15 percent (grip: reload 8 percent faster), barrel +3 percent damage and +1 point of accuracy,
skills: +10 health, 3 percent fewer blows land, melee +10 percent, one point more time at the trigger. Every number on a
card is a whole percent or a whole point.

| Solo, 400 nights | Mean round, no kit | Level-55 kit | Prestige kit (1.5x) | Kills a night, no kit | Level-55 kit | Prestige kit (1.5x) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Rookie | 5.3 | 6.4 (+19%) | 6.7 (+25%) | 39 | 55 (+42%) | 60 (+55%) |
| Regular | 10.3 | 10.8 (+5%) | 11.1 (+8%) | 128 | 140 (+9%) | 148 (+15%) |
| Veteran | 15.5 | 16.9 (+8%) | 17.6 (+13%) | 292 | 340 (+16%) | 372 (+27%) |

| One kitted player in a team of | Kit | The kitted player's points | A level-1 teammate's points | Team mean round |
| --- | --- | ---: | ---: | ---: |
| two Regulars | level 55 | +7% | +3% | 12.6 to 12.9 (+2%) |
| two Regulars | 1.5x kit | +17% | +3% | 12.6 to 13.2 (+5%) |
| four Rookies | level 55 | +12% | -1% | 6.2 to 6.3 (+1%) |
| four Rookies | 1.5x kit | +27% | +5% | 6.2 to 6.5 (+5%) |
| four Regulars | level 55 | +12% | +1% | 14.8 to 15.0 (+2%) |
| four Regulars | 1.5x kit | +17% | +2% | 14.8 to 15.2 (+3%) |
| four Veterans | level 55 | +7% | -1% | 20.8 to 20.9 (+0%) |
| four Veterans | 1.5x kit | +12% | -1% | 20.8 to 21.0 (+1%) |

| Four Regulars | Team mean round | Team kills a night |
| --- | ---: | ---: |
| nobody kitted | 14.8 | 680 |
| one at level 55 | 15.0 (+2%) | 706 (+4%) |
| two at level 55 | 15.5 (+5%) | 749 (+10%) |
| all four at level 55 | 15.9 (+8%) | 792 (+17%) |
| all four with the 1.5x kit | 16.6 (+12%) | 863 (+27%) |

What the tables say:

- **"Slightly" in numbers.** For a Regular the level-55 kit is **+5 percent rounds reached, +9 percent kills and +9
  percent points a night** (solo). A Veteran gets more (+8, +16, +15) because he is on the longer end of the curve where
  a magazine and a reload buy more. That is the budget I propose: *the full kit lifts a Regular's or a Veteran's mean
  round by at
  most 10 percent (the Rookie's boss cliff is the stated exception), and in a team the kitted player earns at most 15
  percent more points than the same seat unkitted.* It is cheap to hold with a test: the gate's cells with and without
  a kit.
- **A level 1 beside a level-55 in one lobby.** The kitted player takes **about 12 percent more of the points** (7 for
  Veterans and for two players) and makes 5 to 27 more kills a night; the level-1 teammate's own points **hardly
  move** (-1 to +3 percent). The team reaches 0 to 2 percent further, because one player's extra kills mostly come out
  of the others' share of the
  same dead. Nobody is shut out; the gap is small enough that a friend's night does not turn on it.
- **A Rookie gains the most in relative terms** (+19 percent rounds, +42 percent kills): the first boss at round 5 is a
  cliff for a weak player ([the simulator page](balance-simulator.md) says the same), and a few percent tips more
  nights over it. The kit therefore helps the weakest player most in rounds, not least: it is not a veteran-only edge.
  The cliff is an honest limit of the model and is not read further than that.
- **If the whole lobby has the kit** (the normal case among friends who have played the same amount) the team reaches
  **8 percent further and kills 17 percent more**. The gate and its ranges are set without a kit; the kit makes a
  full level-55 lobby roughly one round better than the gate says. That is the reward, but it must be a number someone
  watches: the guard test below reads both.

### Where "slightly" stops

The same measures with the kit at larger sizes (all levers scaled together):

| Average solo, 400 nights | Mean round | Kills a night |
| --- | ---: | ---: |
| no kit | 10.3 | 128 |
| level-55 kit (the budget) | 10.8 (+5%) | 140 (+9%) |
| 1.5 times that (the 1.5x kit) | 11.1 (+8%) | 148 (+15%) |
| half of the ceiling kit (about 2.6 times the budget) | 12.6 (+22%) | 189 (+47%) |
| the ceiling kit: every lever at its largest (about 5 times) | 14.9 (+44%) | 253 (+97%) |

| Four Regulars, one kitted | Kitted player's points | Teammate's points | Team mean round |
| --- | ---: | ---: | ---: |
| level-55 kit | +12% | +1% | 14.8 to 15.0 (+2%) |
| half of the ceiling kit | +32% | +5% | 14.8 to 15.7 (+6%) |
| the ceiling kit | +52% | +7% | 14.8 to 16.2 (+10%) |

At about 2.6 times the budget a Regular's solo night is a fifth longer (+22 percent rounds, +47 percent kills) and the
kitted player in a team of four takes a third more points (+32 percent) while a teammate gains 5; at the ceiling it is
+44 and +97 percent and +52 percent points. That is a different game. So **the cap I propose is the level-55 kit, and
half a kit more
for the prestige ceiling at most** (the 1.5x kit above: +8 percent rounds and +14 percent points for a Regular solo,
+17 percent points in a lobby). Past that the numbers are not a reward any more but a reason to avoid the player or to
stop playing without one.

### Side-grades are not neutral by themselves

The design page's old audit says a trade-off must net to about zero (within five percent). Three packs of the kind the
genre uses, at sizes I would call generous, measured the same way:

| A trade-off pack | Average solo: rounds | kills | Strong solo: rounds | kills |
| --- | ---: | ---: | ---: | ---: |
| Heavy: damage +20%, 15% slower fire, 10% slower reload | +2% | +2% | -1% | -0% |
| Drum: magazine +60%, 30% slower reload | +4% | +7% | +8% | +15% |
| Quick: 15% faster fire, damage -10%, magazine -20% | -4% | -6% | -4% | -9% |

A **drum** (more rounds, slower reload) is a clear gain for both players (+4 and +8 percent rounds), because a longer
magazine at a slower reload still beats stopping to reload at the wrong moment; a **heavy** barrel is neutral (+2 and
-1 percent: stronger shots against slower fire); a **quick** pack is a loss (-4 percent). So a trade-off is a gain, a
wash or a loss until it has been measured: every attachment gets this audit in the simulator before it ships, and the
plain option's number is what counts against the budget. A drum that is a free gain is not a side-grade; it is the
plain option with a name.

### For the bots

Bots keep their difficulties (decision 2026-11-04) and carry no kit and no level, so they stay the yardstick. A human
with the level-55 kit beside three bots is the "one kitted player in a team of four" row of the tables: +12 percent
points to the human, 0 to +1 percent to a bot, the team a quarter of a round further. The bot bands and the bots' own
tuning
stand untouched, and the simulator's Rookie, Regular and Veteran remain the bots' yardstick.

### For the rule that a night resets

The kit never touches the night's own tuning: starting points, prices, fuel, rounds, the dead. It scales only what the
player does with their own weapon and body, and it is read by the server from the profile at the start of the night
(never from the client), so a late joiner and a restored night see the same numbers. One thing changes in practice:
a night is no longer the same for a level-1 and a level-55 player in *numbers*, by the budget above. I propose a match
setting beside the existing perk limit, **Loadouts: On or Standard**, so a host can turn every kit off for a lobby (a
race, a challenge night, a stream). **Choice** 3 below.

### What a slot costs in hours

The simulator counts kills by weapon (the patch adds the count). The kills a Regular makes in a night, grouped by
class (from 150 solo nights; the box's draw decides the mix, which is a model of the bots' shopping, not a person's):

| Class | Kills a night | Kills an hour | Hours to 150, 600, 1,500 kills |
| --- | ---: | ---: | --- |
| SMG (Tommy gun, MP5, PPSh) | 35 | 220 | 0.7, 2.7, 6.8 |
| Rifle (lever rifle, M4A1) | 32 | 200 | 0.7, 3.0, 7.5 |
| Shotgun (double barrel, 870 pump) | 20 | 125 | 1.2, 4.8, 12 |
| Starter pistol | 19 | 120 | 1.2, 5.0, 12.5 |
| LMG (M249) | 16 | 100 | 1.5, 5.8, 14.6 |
| Sniper, pistol, special | under 1 | under 5 | tens to hundreds of hours |

- **A class by use alone starves the rare guns.** The fifty cal, the dual pistols and the wonder weapons come from the
  box and are drawn in a night or two a hundred; their classes would never open a slot. Hence the quarter share for
  kills with another class: over 8 hours of play a Regular makes about 6,200 kills, so every class collects 1,200 to
  1,500
  quarter-share kills by the time the climb ends, and the favourite classes finish their three slots in 3
  to 8 hours. In a team of four the split is even more uneven (the shotgun and rifle take three quarters of the kills),
  which is another reason for the share.
- **The maintainer's "300+ kills a game"** (modifiers raise the count) is about 2.4 times the Regular's 128. The hours
  above fall by the same factor under a high-count setting; the thresholds are data and are retuned from telemetry,
  as the progression page already says of the XP.

## Prestige: what resets, what stays

### The table

| | Resets (goes back to the start) | Stays | Is given |
| --- | --- | --- | --- |
| Level and XP | Level to 1, XP to 0 | Lifetime stats (kills, nights, best round, extractions) in the ledger | A star on the level icon for each prestige; a prestige card and emblem |
| Kit | The eleven skill picks; the attachments and re-cut finishes earned by weapon use (class kills go back to 0) | Nothing of the kit except a Keepsake | One Keepsake per prestige (one item kept, below) |
| Wardrobe | Every piece and cloth colour the ladder gave (26 pieces, 10 colours), the four level plate frames; back to two of each and the free colours | The free character, face, hair; any item kept by a Keepsake; anything earned by a challenge or a night won | The prestige colour set and a prestige-only costume piece |
| Maps | Nothing (see below) | Every map already unlocked | |
| Cards and emblems | Nothing | Every calling card and emblem, including the tier ones (they record that the level was reached once) | One of each per prestige |
| Weapon skins | Nothing | Every skin a feat earned | An exclusive skin per prestige, earned on the climb by extracting |
| Challenges | Dailies and orders in progress; level-based ones | Lifetime counters and finished ones, "beat this map" frames | |
| Weapons and tonics | Nothing: free to all | | |

The reset line is the one the genre draws: **what the ladder gave goes, what a feat earned stays**. Everything on the
left was bought with time; everything in the middle was earned by doing something, so taking it back would be the
thing players resent most (Cold War's revoked icons, the BO6 token backlash). What prestige itself gave is never taken
back either.

### Maps and level-locked cosmetics, specifically

- **Maps stay unlocked.** At the 8-hour pace the second map (level 10) comes after about 21 minutes for a Regular
  (a level 10 in the curve below), so re-locking it costs 21 minutes and a friend's night, not a flex: the **host's**
  level decides the lot (answer 5 of the maintainer's progression decisions), so a prestiged host at level 3 could not
  host the back rooms for his
  friends. The Deep Rock promotion is the precedent (unlocks stay, the level resets, content opens), and map access is
  the
  one thing here whose absence only annoys. **Option B** (re-lock to level 10): possible, cheap to build, and I would
  not. **Option C** (re-lock and let the Keepsake save a map): the same cost with a worse choice. **Choice** 5.
- **With the 8-hour pace the back rooms at level 10 is now 21 minutes in.** The previous plan put it at 1.2 hours;
  I would move the unlock to level 20 (about 70 minutes) to keep the same feel. **Choice** 6.
- **Level-locked cosmetics reset**, except: the Keepsake, anything a challenge or an extraction gave, the free set. The
  plate frames from levels (29, 37, 50, 55) reset; the "beat this map" frames (answer 10: exclusive ones from
  challenges) stay, because a night won earned them.
- **A look is never lost silently.** On prestige the profile remembers the worn look; the wardrobe shows the locked
  pieces dark, as it does for a new player, with the level that reopens each; a saved outfit shows "complete again at
  level N". A player who wants a piece back sooner picks it as the Keepsake.

### The Keepsake

One item kept per prestige, picked on the prestige screen from what the player has now: a wardrobe piece, a colour, a
plate frame, or one class's attachment slot (a pick or a slot is the only way any kit survives a prestige, so five
Keepsakes cannot hold more than a fifth of it). It is the genre's single item kept (BO3, BO6, BO7, MW4) and it
answers the regret the Steam thread reports, since the player picks at the moment of loss and sees the whole list.
Two guards: a Keepsake is an *item*, never a level, and **at most five are held** (the same thread says the choice stops
mattering after five to seven), so the tenth prestige is as costly as the first.

### What prestige gives

- **The marks**: a star on the level icon per prestige (up to ten, then a gold one), a prestige card and emblem, and a
  plate frame at prestiges 1, 5 and 10. They show where the level shows (the name tag, the lobby plate, the report):
  the display is the flex ([the research](#what-we-take-from-it)).
- **The XP bonus**: +5 percent XP a prestige, at most +25 percent, for the next climb. It is the genre's reward (+20
  and +30 percent in the games above), it is not combat power, and it makes the loop shorter without making it free
  ([the figure](#hours-8-to-80)).
- **Exclusive items, leaning on extraction.** Each prestige has two kinds: items **given at the reset** (the mark, the
  card, the emblem, the frame) and an **exclusive earned on that climb by winning a night** (an extraction, from
  [#1056](https://github.com/Ryubara/deadnight/issues/1056)): a weapon skin, a costume piece, in the rarity tiers
  [#1053](https://github.com/Ryubara/deadnight/issues/1053) is researching. The second kind makes a prestige more
  than a longer grind: the player must win, once, on the climb, to finish the set. **Choice** 8: and whether prestige
  itself should *need* one extraction at level 55 (a final exam; I would not, because a team that has not got extraction
  working yet should not be locked out).
- **No combat power.** The prestige kit is the level-55 kit; nothing from the prestige adds to it. If the maintainer
  later wants a prestige to add power, the cap above is half a kit (the 1.5x kit) and it should be a visible slot, not a
  hidden multiplier.

### The loss, honestly

A prestiged player has lost **the kit for a while and the outfit for a while**:

- The kit comes back along the climb: a pick at every fifth level (half the picks at level 25, about 1.8 hours for a
  Regular; seven of eleven at level 40, about 4.4 hours) and the attachments as class kills pass 150, 600 and 1,500.
  The *power* gap against a player who did not prestige is therefore **at most the whole budget at the first night
  (about 5 percent of a Regular's rounds), half of it after two hours, and gone by hour 8**. If the loss must
  *hurt in play*, it will not; it is a few percent for a few hours.
- What does hurt is the **identity**: back to two of each, level 1 over the head, a star beside it, the outfit that took
  8 hours dark again. That is what the maintainer's word "flex" asks for: the loss is *seen*, and the star says it was
  chosen.
- Two honest consequences. (1) **The Keepsake and the exclusives soften it on purpose**, and the research says the
  softening is what keeps players from resenting it; (2) **the more powerful the kit, the more the loss counts in
  play.**
  The one lever for a bigger loss is a bigger kit, and the table above says that costs the lobby.

## Hours 8 to 80

### The 8-hour curve

The XP curve of [the progression page](progression.md) is 53,250 XP for 22 to 32 hours. At 8 hours it is a third of
that, **and it climbs**: the maintainer's *"it takes longer to level up the higher you go ... first level up
satisfaction early on"*. The cost to leave a level, per tier of five (the last tier has four levels; **17,465 XP** in
all), with the opening-night bonus lowered to 100 so the first night is not seven level-ups at once:

| Tier | Levels | XP to leave each | | Tier | Levels | XP to leave each |
| --- | --- | ---: | --- | --- | --- | ---: |
| Doors Open | 1-5 | 80 | | Main Feature | 31-35 | 435 |
| Cartoon | 6-10 | 115 | | Late Show | 36-40 | 495 |
| Newsreel | 11-15 | 160 | | Midnight Show | 41-45 | 550 |
| Intermission | 16-20 | 205 | | Headliner | 46-50 | 610 |
| Trailers | 21-25 | 265 | | Last Reel | 51-54 | 610 |
| Second Feature | 26-30 | 320 | | | | |

The first level costs a Regular **2.3 minutes** and the last **17**. Time to each level from the same simulator cells
as the progression page (XP per night and minutes per night from `model.py`; nights only: boards, doors, fuel and
the dailies add about 15 percent, so each time is an upper bound):

| Level | XP to reach it | Regular, solo | Regulars, four | Veteran, solo | Rookie, solo |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | 80 | 0 min | 0 min | 0 min | 0 min |
| 5 | 320 | 6 min | 8 min | 6 min | 8 min |
| 10 | 860 | 21 min | 26 min | 20 min | 28 min |
| 15 | 1,615 | 43 min | 52 min | 39 min | 57 min |
| 20 | 2,595 | 70 min | 86 min | 65 min | 93 min |
| 25 | 3,860 | 106 min | 2.2 h | 97 min | 2.3 h |
| 30 | 5,405 | 2.5 h | 3.1 h | 2.3 h | 3.3 h |
| 40 | 9,365 | 4.4 h | 5.3 h | 4.0 h | 5.8 h |
| 50 | 14,475 | 6.8 h | 8.3 h | 6.2 h | 9.0 h |
| 55 | 17,465 | 8.2 h | 10.0 h | 7.5 h | 10.8 h |

### What a player does with the hours

| Hours | What the player does | What the systems give |
| --- | --- | --- |
| 0 to 0.5 | First nights; levels 1 to 10; the first skill picks (5 and 10); starter class slot 1 | The popups come within minutes; the second map (or its new level) |
| 0.5 to 8 | The climb: a pick every 5 levels, the favourite classes' three slots, the wardrobe, level 55 | The kit grows to its budget; every cosmetic of the ladder; first extractions as [#1056](https://github.com/Ryubara/deadnight/issues/1056) lands |
| 8 to 20 | Prestige 1 (optional) or stay: the classes the box rarely draws (tens of hours), 45 challenges and the poster sets, extraction on the other maps, skin feats | Skins and cards; the choice of prestige or not |
| 20 to 80 | Prestiges 2 to 10: each one a climb with a **different kit** (the picks are re-chosen, the Keepsake changes the start), one win to finish each exclusive set | A star per prestige; ten exclusive sets; the +25 percent XP bonus after five |
| After 80 | Master mark; the stars go on without a reset; skins and the ledger | Nothing more is gated |

![Hours to each prestige](weapon-progression-hours.png)

The loop is **ten climbs** (the figure: no bonus, prestige 10 at 82 hours for an average solo player; with +5 percent a
prestige at most +25 percent, **70 hours**). That is the 8-to-80 the maintainer asked for, and it is arithmetic on the
curve, not a promise: whether players *want* a second climb depends on the second climb being different. The levers
that make it so are the re-chosen picks, the Keepsake, the exclusives that need a win, and the extraction itself
(a new way to end a night). The Roblox glossary's warning (summary) is the risk: prestige hurts retention when the
second run feels like the first.

## Choices for the maintainer

Each is mine to recommend and his to decide.

| # | Choice | Recommendation |
| --- | --- | --- |
| 1 | What resets | **Kit and outfit** (level, skill picks, attachments and finishes, level wardrobe and plate frames). Cards, emblems, skins, lifetime stats stay. Options: *ladder only* (keep attachments: a smaller loss, a bigger kit left), *everything* (including cards: the genre's most resented) |
| 2 | Keepsake | One item per prestige, at most five held. Or none (a harsher, cleaner reset) |
| 3 | The host's switch | A match setting **Loadouts: On or Standard** (kit off for the whole lobby), default On |
| 4 | How slight | The level-55 kit and a prestige cap of the 1.5x kit; the guard test holds them. A bigger kit is possible and the tables say what it costs |
| 5 | Maps on a reset | **Stay unlocked.** Or re-lock until level 10 (21 minutes), or until level 10 with a Keepsake |
| 6 | Back rooms at level 10 or 20 | **20** at the 8-hour pace (about 70 minutes) |
| 7 | Skills: pairs or a tree | **A pair at every fifth level**, swappable. Or a tree |
| 8 | Prestige exclusives | One earned by an extraction on the climb; prestige itself does not need one |
| 9 | XP bonus | +5 percent a prestige, at most +25 percent |
| 10 | Attachments by class kills | **By class**, a quarter share to the other classes. Or by weapon (starves the rare guns), or by account level (the maintainer's "play more" but not "use the weapon") |
| 11 | Gun modifiers | The re-cut finish, **second wave**, after attachments and skills |
| 12 | Attachment art | Parts on the three sockets the models already have, shared across weapons ([cost](#what-it-costs-to-build)) |
| 13 | Opening-night bonus | 100 XP at the 8-hour pace (it was 300 at 22 to 32 hours) |

## What it costs to build

Sizes are relative (S under a day of an agent's work, M two to four days, L a week or more); the order is the order I
would file them in.

| Piece | What it touches | Size |
| --- | --- | --- |
| **Kit rules**: a `PlayerKit` read by the combat server the way `PerkEffects` is read (damage, reload, magazine, fire interval, health, blows that land), from the profile at the start of a night, never from the client | `gameplay/weapons`, `gameplay/rules`, snapshot version, a test that the kit never touches a tuning number | M |
| **Profile and save**: class kills, picks, finishes, keepsakes, prestige count, skins; the prestige reset as one function with a test per row of the table above | the profile of the progression plan; the backend's `profile` slot grows by a few hundred bytes; a schema version | M |
| **The kit on the wire**: attachment bits in each weapon's frame entry (`arms [ammo, reserve, tier]` gets three small fields), the kit's numbers in the backend-minted ticket so the server trusts the account, not the client; a late joiner sees it | `net`, the ticket, WELCOME | M |
| **The workbench and the cards**: a lobby screen (a weapon class, its three slots, two options each, the numbers), a pause card, the HUD ammo card naming the attachment, the picks screen | `ui`, menus | M to L |
| **Attachment art, three sockets**: **all 15 firearm models already carry a `Muzzle` marker** (so the barrel slot needs no model change), **10 carry a `Support` marker** where the second hand rests (the grip slot, with a check that the hand's IK still reaches), and **10 carry a magazine part** (`Magazine`, `Drum`, `Box`, `Cell`, `Tank`) while five (the double barrel, flare gun, lever rifle, pump and revolver) have a tube or a cylinder and nothing to swap: for those the magazine slot is shown as a coloured band and the HUD card. Each model also has a `_far` model: parts go on the near model only. Shared parts (three muzzles, three grips, a magazine swap by scale) rather than 15 bespoke sets | `assets/weapons`, `WeaponHold`, the re-cut skin shader must cover the new parts | L |
| **Skins**: a camo layer on the existing palette material (like the re-cut skin: one surface, one texture read) and the feat tracking | `gameplay/weapons/fx`, tally lines | M |
| **Gun modifiers (finishes)** | `RecutProfile` gets a list of finishes; the HUD names the chosen one | M |
| **The guard test**: the gate's cells with the level-55 kit and without; fails if the Regular's mean round rises more than 10 percent or the kitted player's points share more than 15 percent | `tests/balance` | S |
| **Prestige screen**: the list of what goes and what stays, the Keepsake pick, the confirmation, the marks | `ui` | M |

The art and the workbench are the long pole. The kit rules and the guard test are small and could ship alone behind
**Loadouts: Standard**; the kit then grows as the picks and the slots arrive.

## The simulator patch

Not applied in this pull request (it is a research tool and the issue says no game change); it is kept beside this
page so every number can be reproduced. It adds `SimLoadout` (a static
table of numbers per player id, parsed from `--loadout=damage=1.03:reload=0.92:...` and `--equipped=1,2`), and reads
it in
`NightSim` at: the shot interval, the reload time, the magazine size (a `mag_scale` on `SimArm`, rounded to
the nearest round), the damage and the melee damage on a hit, the accuracy and the head rate on a roll, the chance a
blow lands, the most health, and the shooting time. `BalanceBatch` sums points, kills and downs by player id and kills
by weapon; `balance_cli.gd` passes the two flags to `SimLoadout.parse`. The default loadout changes nothing (every
read has the neutral default), so the gate's numbers are the shipped ones. Commands:

```text
godot --headless --path game -s res://tools/balance/balance_cli.gd -- --skill=average --players=4 --nights=400 \
  --seed=4000 --rounds=40 --loadout=mag=1.15:reload=0.92:damage=1.03:accuracy=0.01:health=10:land=0.97:melee=1.1:uptime=0.01 \
  --equipped=1 --out=cell.json
```

If the maintainer approves the kit, the patch becomes a proper build issue (the kit rules) rather than a research
branch; I kept it out so this stays a docs change. The diff against `main` is in
[`weapon-progression-loadout.patch`](weapon-progression-loadout.patch) (apply it
with `git apply --ignore-whitespace`; the new file is `game/tools/balance/sim_loadout.gd`).

## What I could not read, and what is open

- **Black Ops 3 Zombies specifics**: whether box weapons roll attachments, how many a Zombies weapon holds, whether they
  show on the model, Pack-a-Punch levels and camo challenges. The Call of Duty wiki refused every fetch and no other
  source was reachable; the **shape** of the maintainer's example (attachments and camos earned and kept, one item kept
  through prestige) rests on the Activision pages of the same game and its successors.
- **The Zombies prestige conflict**: Activision's multiplayer page keeps attachments; a forum summary says Zombies
  prestige relocks them. Not settled; I draw the line where the later games draw it (progress kept on a player
  prestige, earned attachments relocked on a *weapon* prestige) and put the reset on the *kit*.
- **Payday 2 skill-tree structure** and **Helldivers 2** developer statements were not found; Helldivers 2 appears only
  through a press summary.
- **No source calls the loss of a reset a costly signal for games** (RuneScape's developers come closest). The "flex"
  argument here is design reasoning plus the genre's practice, not a study.
- **The simulator's limits** ([the page](balance-simulator.md)): bots, a weapon mix that is the bots' shopping, no
  elements, no melee geometry; the weak player's boss cliff makes a Rookie's percent look large. Numbers compare kits,
  they do not predict a person's night. Open for the build: the kit's value in a high-kill (modifier) setting, and
  whether the box should weight starved classes.

# The roster of nine new weapons and the re-cut plan

Issue #785, the design the build issues read ([#793](https://github.com/Ryubara/deadnight/issues/793) the six
firearms, [#794](https://github.com/Ryubara/deadnight/issues/794) the re-cuts and elements,
[#788](https://github.com/Ryubara/deadnight/issues/788) the ray gun, the freeze gun and status effects,
[#789](https://github.com/Ryubara/deadnight/issues/789) the dual pistols). It studies the genre's round-based zombie
modes for numbers and design only. Names ("Ray Gun", "Wunderwaffe", "Pack-a-Punch"), camos, models and sounds are not
copied (`AGENTS.md`). The numbers we chose, and what ships where, are on the design page
[Weapons](../design/weapons.md#the-nine-new-weapons-785) and [The re-cut](../design/upgrades.md#the-re-cut-plan-for-seventeen-weapons-785);
this page is the evidence and the method.

## Sources and how sure we are

The fan wikis refuse an automated page read, but their MediaWiki API answers a plain request
(`curl -A "<a browser user agent>" "https://<wiki>.fandom.com/api.php?action=parse&page=<Title>&prop=wikitext&format=json&formatversion=2&redirects=1"`,
[the lesson](https://github.com/Ryubara/gdstudio) of the kit's wiki entry). Every infobox below was read that way on
2026-11-03. **Quoted** is an infobox figure; **reported** is community knowledge no page we opened states; **ours** is our
choice. The infobox numbers differ between games (a weapon is retuned in each), so each row names its game.

- Call of Duty Wiki: [Ray Gun](https://nazizombies.fandom.com/wiki/Ray_Gun), [PPSh-41](https://nazizombies.fandom.com/wiki/PPSh-41),
  [MP5K](https://nazizombies.fandom.com/wiki/MP5K), [M14](https://nazizombies.fandom.com/wiki/M14),
  [M1911](https://nazizombies.fandom.com/wiki/M1911), [Python](https://nazizombies.fandom.com/wiki/Python),
  [CZ75](https://nazizombies.fandom.com/wiki/CZ75), [Wunderwaffe DG-2](https://nazizombies.fandom.com/wiki/Wunderwaffe_DG-2),
  [Pack-a-Punch](https://nazizombies.fandom.com/wiki/Pack-a-Punch), [Mystery Box](https://nazizombies.fandom.com/wiki/Mystery_Box)
  (the Nazi Zombies wiki, for the Black Ops and World at War modes).
- [Winter's Howl](https://callofduty.fandom.com/wiki/Winter%27s_Howl), [Ice Staff](https://nazizombies.fandom.com/wiki/Staff_of_Ice),
  [Remington 870 MCS](https://callofduty.fandom.com/wiki/Remington_870_MCS), [M249 SAW](https://callofduty.fandom.com/wiki/M249_SAW),
  [M4A1](https://callofduty.fandom.com/wiki/M4A1), [Barrett .50cal](https://callofduty.fandom.com/wiki/Barrett_.50cal),
  [Dual Wield](https://callofduty.fandom.com/wiki/Dual_Wield), [Zombies (Treyarch)](https://callofduty.fandom.com/wiki/Zombies_(Treyarch))
  (the Call of Duty Wiki).
- Earlier pages of ours: [the Mystery Box](mystery-box.md), [weapon upgrades](weapon-upgrade.md),
  [round scaling](round-scaling.md), [the balance simulator](balance-simulator.md).

## The genre's numbers

| Weapon (game) | Per hit | Rate | Magazine / reserve | Reload | Where, price | Upgraded |
| --- | --- | --- | --- | --- | --- | --- |
| PPSh-41 (WaW, BO) | 60 to 100 | 1,250 RPM | 71 / 355 | 2.5 s (4.1 empty) | Mystery Box 950; one mode's wall 5,000 | 80 to 150, 1,578 RPM, 115 / 700 |
| MP5K (BO) | 50 to 100 | 750 RPM | 30 / 120 | 2.9 s (3.2 empty) | wall 1,000, ammo 500 | 80 to 140, 40 / 200 |
| M14, a semi rifle (BO) | 105 to 80 | 625 RPM | 8 / 96 | 2.4 s (3.45) | wall 500, ammo 250 | 200 to 150, 16 / 192 |
| Remington 870 MCS (BO2) | 310 to 15 x 4 pellets | 80 RPM (pump) | 6 / 48 | shell by shell | wall 900 to 1,500 by map, ammo half | 10 shells, faster pump, near one-hit |
| M249 SAW (CoD4, the genre's LMG class) | 130 to 90 | 937 RPM | 100 / 300 | 6.45 s | the genre's LMGs are Mystery Box only (the Box page names MG42, M1919, HK21, RPK); no Zombies price quoted for the SAW | reported: double damage, bigger magazine |
| M4A1 (CoD4 and the AR class) | 68 to 50 | 800 RPM | 30 / 420 | 2.0 s | the genre's assault rifles are walls at about 1,200 (reported) | reported: about double |
| Barrett .50cal (CoD4, a one-shot sniper) | 1,000 (campaign) | semi | 10 / 30 | 4.1 s | sniper class: Mystery Box only in the classic modes (reported); a 2,000 essence wall in a later mode (quoted) | reported |
| Dual pistols: CZ75 with Dual Wield (BO) | pistol damage x 2 guns | full auto after upgrade | 20 each (upgraded) | per gun | Box 950, then 5,000 to add the second gun | "more damage, more max ammo, run faster" |
| Ray Gun (WaW to BO3) | 1,000 direct, splash 300 to 1,500 | 181 RPM | 20 / 160 | 3 s | Mystery Box 950 only | damage doubled, magazine 40, red bolts |
| Winter's Howl (BO, BO4) | 1,000 (1,500 upgraded), shatter splash 500 to 250 | 181 RPM | 6 / 24 | 3.8 s | Mystery Box 950 only | 9 / 36, more freezes, 1,500 |
| M1911, the start pistol (WaW, BO) | 20 | 1,200 RPM | 8 / 32 (80 max) | 1.9 s | free | **explosive rounds**: damage 1,000, 75 RPM, 6 / 40 |

Findings that shape ours:

1. **The genre's zombie health** starts at 150, adds 100 a round to 950 on round 9, then climbs 10% a round (round 15
   1,683, round 30 7,030) ([Zombies (Treyarch)](https://callofduty.fandom.com/wiki/Zombies_(Treyarch))). A weapon is
   judged by how many rounds it kills in one or two hits: the start pistol (20) takes 8 hits on round 1, the SMGs
   (50 to 100) 2 to 3, the Remington's pellets (310 each) one shell until about round 5, and the Ray Gun's 1,000 plus a
   splash of up to 1,500 "one-hit kills up to round 20 to 25" (quoted from its page).
2. **Ours is gentler early and steeper late**: round 1 is 50, +8 a round to round 8 (106), then **x1.15 a round**
   (`health_growth` in `default_tuning.tres`, set by the headshot retune, [#745](../research/balance-simulator.md#the-headshot-retune-745)):
   round 10 is 140, round 15 282, round 20 567, round 30 2,294. The table on [Rounds](../design/rounds.md#the-tuning-table)
   still showed the old 7% curve; it is corrected with this page. So a genre weapon's rounds-of-use is mapped by
   its **ratio to round-1 health**, never by its number: a one-hit window of "round 10 health" is 140 here, of "round
   20" 567.
3. **Every box weapon is a one-hit or two-hit tool early and obsolete late**: the genre answers with the upgrade, not
   with weaker zombies. A weapon is "worth its place" while it kills within a few hits.
4. **Wonder weapons are Mystery Box only** at the box's price, one-hit kills for most of the night, with a small reserve
   (20 / 160, 6 / 24, 3 / 15) and a splash that hurts the shooter (the Ray Gun: players buy a perk against it, quoted).
5. **The weakest weapon gets the element** (the start pistol's upgrade is an explosive round, and its dual-wield form
   too): this is the maintainer's rule, and the genre does it. The strong guns (the SMGs, the rifle, the LMGs) get
   numbers only (damage, magazine, reserve, rate).
6. **Dual pistols** are two guns with their own ammunition counters, fired independently (one trigger each) and
   reloaded independently, in the modern shooters' version ([Dual Wield](https://callofduty.fandom.com/wiki/Dual_Wield):
   "each weapon fires independently ... each gun has its own ammo counter and can be reloaded independently",
   no aiming down the sights, the hip spread worse, the ammunition supply doubled); in the zombies mode the CZ75 pair
   can be fired one at a time "so that the other reloads", and cannot aim down the sights.

## Ours: how the genre's numbers were turned into ours

1. **Anchor the role, not the number.** A weapon's role comes from the genre (SMG: volume at short range; AR: the
   accurate all-rounder; LMG: a huge magazine and a long reload; the anti-materiel rifle: few, huge, piercing hits; a
   pump: a cheap close wall; the wonder weapons: one-hit kills, small ammunition, the Box only).
2. **Fit it to the health curve above** with the data the game already has: shots to kill from `DamageModel`, kills a
   second from `WeaponWorth.sustained_dps` against the round's health (the weapon pick of the simulator's players), and
   the kills one magazine plus the reserve make.
3. **Run it through the simulator** (`NightSim` through `balance_cli.gd`): the "what is a weapon worth" cell
   ([the simulator page](balance-simulator.md), the average solo player, the weapon bought from the start with the
   price taken out) and the shipped gate with the new crane pool. The cells and results are below.
4. **Price it by what the simulator says it is worth**, not by the genre's price (our points are earned at another
   rate): wall weapons by worth, the rest by the crane's weights.

Where the numbers are on the design page: [the nine weapons](../design/weapons.md#the-nine-new-weapons-785).

## The balance simulator run

Method (all on `main` at `1a4e3016`, then the same code with the nine draft definitions registered; nothing of this
is committed, the build issues add the definitions): `balance_cli.gd` cells of the **average solo player, 150 nights,
seed 1**, a weapon bought from the start with 20,000 points (`--shopping=weapon_<id> --set=economy.start_points=20000`,
the price taken out), and with the re-cut as well (`weapon_<id>,upgrade_weapon`, 40,000 points). A solo median is not
a stable number on 150 nights ([perks](../research/perks.md#numbers)), so the **mean round** and the share of nights
reaching round 10 and 12 are read with it. `UpgradeTuning.weapons` must list the new ids or the re-cut never goes on
them (the simulator's re-cut skipped them until the list was extended: a finding for #794).

### What a weapon is worth (average solo, 150 nights, seed 1)

Mean round, and the share of nights that reach round 10 and 12, with the weapon bought from the start with the price
taken out ("alone"), and with the re-cut as well (the player has the revolver and the weapon; the simulator re-cuts the
carried firearm that kills most once re-cut). The first row is the revolver alone.

| Weapon | Alone: mean round, reach 10 / 12 | Re-cut: mean round, reach 10 / 12 / 15 | Note |
| --- | --- | --- | --- |
| Revolver alone | 9.2, 49% / 1% | 12.4, 97% / 79% / 0% | the shipped start; its re-cut is already worth three rounds |
| Double-barrel | 9.0, 49% / 0% | 10.0, 97% / 0% / 0% | the model gives a close shotgun no value (pellets hit one zombie, the reserve runs dry) |
| Hunting rifle | 10.1, 81% / 15% | 11.4, 95% / 39% / 9% | the best of the old walls |
| Tommy gun (a crane prize; a wall item added for the run) | 11.5, 100% / 47% | 14.6, 100% / 100% / 67% | |
| **Pump 870** | 8.5, 31% / 0% | 12.4, 97% / 79% / 1% | a neutral buy like the double-barrel; the re-cut went to the revolver |
| **PPSh** | 10.3, 71% / 1% | 13.1, 100% / 99% / 1% | |
| **Dual pistols** | 10.9, 91% / 35% | 13.8, 100% / 99% / 23% | |
| **MP5** | 11.4, 99% / 48% | 14.5, 100% / 100% / 58% | |
| **M4A1** | 11.5, 100% / 49% | 14.5, 100% / 100% / 59% | |
| **M249** | 12.0, 100% / 73% | 14.5, 100% / 100% / 65% | |
| **Fifty cal** | 9.0, 49% / 0% | 11.6, 97% / 67% / 0% | piercing is not modelled, and five rounds are all it holds |
| **Ray gun** | 14.0, 100% / 91% (46% reach 15) | 16.3, 100% / 97% / 87% | one hit, and a blast of 160 for the neighbours on its side |
| **Freeze gun**, as one kill a bolt | 9.0, 49% / 0% | 11.0, 97% / 7% / 0% | |
| Freeze gun, every zombie in the 2.2 m bloom killed (an upper bound) | 9.5, 49% / 15% | 11.7, 97% / 50% / 3% | |

What it says:

- **The new automatics sit in a ladder above the old walls**: the rifle is worth a round, the PPSh a round and a
  tenth, the dual pistols a round and three quarters, the MP5 and the M4A1 two and a quarter, the M249 two and
  three quarters; the ray gun is worth almost five. That is the order the prices and weights follow
  ([weapons](../design/weapons.md#where-they-are-and-what-they-cost)).
- **Ammunition capacity, more than damage, makes a weapon worth taking in the model.** The old shotgun and rifle (32 and
  80 rounds at most) run dry inside a round; a magazine of 30 and a reserve of 180 does not. The numbers were fitted so
  that no new automatic is worth more than its genre rank says (the first draft's 240-round MP5 and 300-round M249
  were worth three and four rounds and were cut to the reserves of the table).
- **A re-cut revolver is the best single shop item in the model today** (three rounds, for a weapon the player already
  has and a cheap round). The re-cut new weapons are worth about two rounds more than the re-cut revolver, which is the
  "worth keeping" the plan asks for ([the re-cut plan](../design/upgrades.md#the-re-cut-plan-for-seventeen-weapons-785)).
- **What the model cannot see**: piercing (the fifty cal, the M249, the rifle), a shotgun's pellets across a crowd, the
  freeze (a frozen zombie is a free kill for the whole team: the "upper bound" row kills the whole bloom and still gains
  only a third of a round, because 30 bolts are all a load holds), spread, and any player moving. These are why the
  fifty cal and the freeze gun read as small gains and are not tuned up on this evidence: they are for a person's
  playtest.
- **The pump's simulated value is zero or less**, like the double-barrel's; it is priced as the cheapest wall (700) for
  its early value, a close one-shell kill to round 9.
  Superseded by the maintainer on [#858](https://github.com/Ryubara/deadnight/issues/858): no wall sells the pump,
  the MP5 or the M4A1 ([the wall tier](../design/weapons.md#the-wall-tier)); they are box only, so the run above,
  which put them on walls, is to be read again with them in the box.

### The shipped gate with the new crane pool

The six cells of the gate (60 nights, seed 4000; weak solo, average 1, 2, 4 and 8, strong solo; ranges 4 to 9, 8 to
14, 11 to 16, 12 to 17, 14 to 20, 12 to 18), the shipped shopping lists (the average player buys through the crane and
the two walls and re-cuts, so the new weapons reach it only as crane prizes). Baseline is `main` (`1a4e3016`).

| Step | Medians | Gate |
| --- | --- | --- |
| `main` | 5 / 10 / 15 / 16 / 18 / 18 | passes |
| the nine in the crane at the table's weights (28.5 in all); the re-cut does not go on them | 5 / 12 / 15 / 17 / 18 / 18 | passes (every median in its range) |
| the same, and the re-cut allowed on the nine (`UpgradeTuning.weapons`) | 5 / 14 / 15 / 17 / 19 / **19** | the strong solo is **19 against 18**; average solo (14) and four players (17) are at their ceilings |
| the same with `health_growth` 1.16 (1.15 shipped) | 5 / 14 / 15 / 17 / 18 / 18 | passes |

The medians are in the gate's order: weak solo, average 1, 2, 4 and 8 players, strong solo.

The first draft numbers (an MP5 of 16 a hit with 150 / 240 rounds, an M4A1 of 22 with 120 / 210, a ray gun of 340 with
48 / 72) gave 5 / 12 / 15 / **18** / 18 / 18 (average four players one over) and were cut to the table's. The other gate
conditions on the cells that were read are held: the stampede (round 10) kills 30% of the average solo nights that
reach it (limit 40%) as before, the first boss night kills 13% of them as before and 74% of the weak (limit 85%).
The cells' time to kill and spend share were not read: the gate itself runs them.

**What this asks of the build issues** (#793, #794): re-run the gate with the nine registered and the re-cut allowed,
the time to kill of every type included (the headliner's limit is 30 s and sits at 30.3 s on 1.16 in the #745 notes,
so the lever is not free); if strong solo reads 19, either `health_growth` 1.15 to 1.16 (the lever #745 used) or a
gate range of 12 to 19 is the maintainer's to choose, not an agent's. The ranges move with the weapons ("the report is
read again and the ranges with it", `balance_targets.gd`).

## The upgrade station: what the genre does, and what ours does

**The genre**: Pack-a-Punch costs 5,000 (3.3 times a 1,500 wall shotgun), once per weapon. The quoted wiki: "higher
damage for bullet weapons, more devastating effects on wonder weapons (some exceptions), more (usually double) ammo,
camo, attachments (a second upgrade changes them); the muzzle flash and the shot's sound change"; "most weapons, when
upgraded, roughly double in magazine size and damage" (a guide). The per-weapon rows above: PPSh 60-100 to 80-150 and
71 / 355 to 115 / 700; MP5K 50-100 to 80-140 and 30 / 120 to 40 / 200; the M14 105 to 200 and 8 to 16 rounds; the
Remington gets ten shells and a faster pump; the Ray Gun doubles and takes red bolts; the Winter's Howl goes 1,000 to
1,500 and 6 / 24 to 9 / 36. **An element only on the weakest**: the start pistol, 20 a hit, becomes **explosive
rounds** (damage 1,000, 75 RPM, 6 / 40 rounds), and its dual-wield form too; none of the SMGs, the rifles or the LMGs
gets one.

**Ours stays the re-cut** ([upgrades](../design/upgrades.md)): x1.75 damage, x1.5 magazine and reserve limit, filled,
1,500 points and 1,500 more for each weapon already re-cut. The research shows no reason to change it: the genre's
numbers are "about double damage and magazine", and ours are 1.75 and 1.5 because our curve compounds 15% a round and
the gate holds them (the 2.0 and 1.6 of [weapon-upgrade.md](weapon-upgrade.md) failed or crowded it). What the research
adds is the **element rule** and the list of weapons it goes to
([the plan](../design/upgrades.md#the-re-cut-plan-for-seventeen-weapons-785)), the weapons `UpgradeTuning.weapons` must
hold, and one more finding: a magazine of 1 or 2 gains little from the x1.5 (the double-barrel's 2 becomes 3).

## The wonder weapons

- **The Ray Gun**: 1,000 direct and 300 to 1,500 splash (quoted), 20 / 160, 181 RPM, a 3 s reload, the Box only at 950;
  "a one-hit kill up to round 20 to 25 depending on the game", "less effective at long ranges (the ray moves slowly)",
  its splash hurts the shooter and players buy a perk against it. In ours: 300 direct (body kill to round 15, head to
  18), blast 160 sliding to 30% at 3 m, the shooter takes 25% of it, 10 / 40, only in the crane, 5.3% of a spin. The
  splash radius was chosen so that the three to five zombies at the front of a lane (0.4 m across, queuing 0.6 to 1 m
  apart) are inside 3 m and take between 160 and 48: enough to kill the round-1 to 8 ones among them and hurt the rest.
- **The Winter's Howl** and the Ice Staff (an Origins weapon that freezes, then shatters): "fires a blizzard of ice that
  damages, slows, and, with enough shots, freezes"; "if the zombie is hit again while slowed it is stopped and encased
  in ice; when frozen the zombie is immediately killed; if left a few seconds, shot or walked into, the ice cube
  shatters"; "as rounds climb it takes more shots to freeze, by round 50 up to two magazines"; the Pentagon Thief
  "will only be slowed". 6 / 24, 3.8 s reload, the Box only. Ours takes the three: the freeze threshold climbs with
  the round (one, two, three bolts by tens of rounds), a boss is slowed and not frozen, and the ammunition is small.
  The maintainer's rule (a frozen zombie holds for 3 s, and any hit kills and shatters it) is kept exactly; the genre
  kills the zombie on freezing and shatters it a few seconds later, ours holds it for the team to shatter, which makes
  it a support weapon and a reason for a second player.
- **Pass-through**: the genre's Wunderwaffe chains up to ten zombies "with no diminished power"; its Winter's Howl is a
  cone. Neither was copied as a pass-through: a bolt that goes through every zombie of a lane is a lane of free kills at
  any round; ours bursts on the first body and a **bloom** of 2.2 m (the freeze) or 3 m (the ray's blast) is the
  several zombies.
- **Rarity**: the Box gives wonder weapons at the weight of others in a pool of about thirty ("the only place" for
  them); ours is a pool of 17 with the two at 1.5 of 28.5, 5.3% each, and a player has one to two plays a night, so
  about one night in seven shows one of them.

## Dual pistols

- **How the genre fires two guns**: in the shooters since 2009 ([Dual Wield](https://callofduty.fandom.com/wiki/Dual_Wield))
  "the two weapons can be fired independently with the aim button acting as the trigger for the left weapon (consoles),
  the mouse buttons (PC)"; "both guns count as a single weapon" for switching; "each gun has its own ammo counter and can
  be reloaded independently, which allows staggering the reload"; "players are unable to aim down the sight"; the
  ammunition supply is doubled; the hip spread is worse (more than halved accuracy on SMGs, a little on handguns); a
  slower draw. In the zombies mode the CZ75 upgraded with the Dual Wield attachment becomes a pair with 20 rounds each,
  "full auto, more damage, more max ammo", it "can sustain fire indefinitely when one is fired while the other
  reloads", "cannot aim down the sights, so many shots miss", and "the player runs faster". The M1911's upgraded
  pair is the explosive "Mustang and Sally".
- **Ours**: one trigger, alternating hands, one counter of 24, one reload, no tightening on aim; the reasons are one
  control on pad and touch, no second button, and the server's single `fire` command per shot
  ([the design](../design/weapons.md#the-dual-pistols)). The genre's independent triggers and reloads are the next
  step if the maintainer asks for them.

## Display names

Several real names are trademarks. The maintainer chose original names with the same guns (#857); the names, the
reason and the test that keeps a maker's name out are on [the design page](../design/weapons.md#display-names-original-names-the-same-guns).
A `display_name` is one line of a definition.

## Not done, and open

- The build: no definition, scene, sound or hold was made; the draft definitions the simulator ran on were kept in the
  scratch folder of the task, never in the repository.
- The sound, models and holds of the nine weapons are
  [#787](https://github.com/Ryubara/deadnight/issues/787), [#790](https://github.com/Ryubara/deadnight/issues/790) and
  [#791](https://github.com/Ryubara/deadnight/issues/791).
- The numbers of the **fifty cal, the freeze gun and the pump** are the least certain: the simulator cannot see what
  they are for. A playtest and the first bot soak with them in the box decide.
- Left to the maintainer: a melee re-cut (the crowbar, bat and axe have no magazine and are not re-cut), the flare gun's
  re-cut with damage (a fire patch) against the earlier ruling of no damage for the time being
  ([#439](https://github.com/Ryubara/deadnight/issues/439)), the gate's strong-solo ceiling, and the display names.

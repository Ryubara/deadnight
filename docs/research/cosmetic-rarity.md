# Cosmetic rarity: tiers, names, signals, and what the top tier costs

Issue #1053 (the maintainer, 2026-11-04, on the progression plan #977) suggested giving cosmetics a rarity instead,
which means the top ones must look striking, with strong shader effects: wings trailing glowing blue fire was the
example. Research only: nothing here ships. The test effect lives in
`game/tests/captures/cosmetic_fx_bench.*` (not in any shipped scene; the web export leaves `tests/` out) and is
measured by `tools/web_smoke/cosmetic_fx_cost.py`. The plan it serves is `docs/research/progression.md` (rules 11 and
12:
nothing for sale, no random grants). Other games' tier names, colours and art are studied here and never used.

## How we searched, and what we could not read

Web search and page fetches, 2026-11-04. Fandom wikis answered HTTP 402 and a few other pages refused the fetch tool,
so many rows rest on a search summary: they say *summary*; *read* means the page itself was fetched. Where nothing could
be sourced the row says *our reading*. No source we found studies players' reaction to "looks AI-made"; that part is our
reading, built on the complaints below.

## How games tier cosmetics

| Game | Tiers, low to high | Beyond colour | How the top is earned | Source |
| --- | --- | --- | --- | --- |
| Apex Legends | Common, Rare, Epic, Legendary, Heirloom (grey, blue, purple, gold, red) | Heirlooms are melee skins with their own animation; "reactive" weapon skins change through three stages with kills (*summary*) | Heirloom shards from packs (under 1 percent for 150 shards) or the store: chance and money | [GGRecon](https://www.ggrecon.com/articles/i-want-games-to-decide-on-a-rarity-system/) (*read*), [wiki.gg](https://apexlegends.wiki.gg/wiki/Heirloom) (*summary*) |
| Overwatch 2 | Common, Rare, Epic, Legendary (grey, blue, purple, gold), then Mythic | Legendary is "a major visual redesign"; Mythic adds customisation and effects (*summary*) | Credits, coins and a battle pass; Mythic behind the pass's upper rows (*summary*) | [GGRecon](https://www.ggrecon.com/articles/i-want-games-to-decide-on-a-rarity-system/) (*read*), [ludo.guide](https://www.ludo.guide/guide/overwatch-2/cosmetics/rarity), [Windows Central](https://www.windowscentral.com/gaming/overwatch-2-battle-pass) (*summary*) |
| Valorant | Select, Deluxe, Premium, Ultra, Exclusive | Select: none; Deluxe: a colour theme and light effects; Premium: full VFX, several finishers, kill counters; Ultra: evolving forms, voice (sources conflict on Exclusive against Ultra) (*summary*) | The store, by price (875 to 1,775 VP; Ultra and Exclusive vary) | [Riot support](https://support.riotgames.com/valorant/store/price-tiers-for-skins-in-valorant) (*read*, names and prices only), [PCGamesN](https://www.pcgamesn.com/valorant/skins) (*summary*) |
| Team Fortress 2 | Qualities, not a ladder: Normal, Unique, Vintage, Genuine, Strange, Unusual, Haunted, Collector's, Decorated, Community, Self-Made, Valve | **Unusual** puts a particle effect on a hat: 359 effects over 674 cosmetics; "quality is a purely cosmetic property" | Crates, under 1 percent for an Unusual: a lottery | [TF2 wiki, Item quality](https://wiki.teamfortress.com/wiki/Item_quality), [Unusual](https://wiki.teamfortress.com/wiki/Unusual) (*read*) |
| Dota 2 | Common, Uncommon, Rare, Mythical, Legendary, Immortal, Arcana (sources disagree on Ancient) | An Arcana can change a hero's model, animations, ability effects, sounds and portrait; Mythical sometimes changes an icon (*summary*) | Treasure chests and the store | [Liquipedia](https://liquipedia.net/dota2/Mythical), [Hawk Live](https://hawk.live/posts/dota-2-arcana) (*summary*) |
| Counter-Strike 2 | Consumer (white) up to Covert (red), seven in all, and a special Contraband | A finish and a wear; knives and gloves are a class of their own (*summary*) | Cases and trading | [counterstrikewiki](https://counterstrikewiki.com/Skin_Rarity), [exitlag](https://www.exitlag.com/blog/cs2-rarity-guide-skins-value/) (*summary*) |
| Fortnite | Common, Uncommon, Rare, Epic, Legendary, plus named *series* (Icon, Gaming Legends and others); Epic removed the visible tiers in April 2024 and kept the series labels | The series carry the look; the tier had none beyond colour (*summary*) | The shop and the battle pass | [PC Gamer](https://www.pcgamer.com/games/battle-royale/epic-removes-the-item-rarity-system-from-fortnite-but-some-fans-aint-happy-and-think-its-trying-to-gouge-players) (headline only), [esports.gg](https://esports.gg/news/fortnite/fortnite-skin-rarity-list/) (*summary*) |
| Call of Duty: Warzone (loot) | Common (white), Uncommon (green), Rare (blue), Epic (purple), Legendary (gold) | Colour only: this is gear, not cosmetics | Found | [GGRecon](https://www.ggrecon.com/articles/i-want-games-to-decide-on-a-rarity-system/) (*read*) |
| Destiny 2 (shaders) | Rarity of a shader is measured against how many players own it (*summary*) | A colour scheme, and ornaments that change a piece's look | The Eververse store, engrams, activities | [Dexerto](https://www.dexerto.com/destiny/destiny-2-rarest-shaders-3135675/) (*summary*) |
| Helldivers 2 | Not tiers: *warbonds* (a free Standard one, premium ones for Super Credits) | Armour sets and capes are bought page by page | **Medals earned in missions**, no randomness stated; Super Credits are also found in play | [Helldivers wiki](https://helldivers.wiki.gg/wiki/War_bonds) (*read*), [Prima Games](https://primagames.com/tips/how-to-unlock-premium-warbonds-in-helldivers-2-without-spending-a-cent) (*summary*) |
| Warframe | Not tiers on cosmetics | Syandanas and Ephemera (a trailing effect) | A Nightwave season's acts give a Syandana and an Ephemera: "no Platinum is necessary" (the developer's post, *summary*) | [Warframe news](https://www.warframe.com/en/news/vol9-5-21) (*summary*) |
| Deep Rock Galactic | No tiers; cosmetic-only paid DLC | The base game has no microtransactions; most cosmetics unlock in play (*summary*, forum opinion) | A cosmetic pack was remade after fans said paid items should "stand out" | [PC Gamer](https://pcgamer.com/deep-rock-galactic-studio-remakes-cosmetic-dlc-after-fans-complain-everyone-gets-the-original-designs-for-free) (headline only) |

What that says:

- **Four to seven steps, and the middle four are the same four**: grey, blue, purple, gold (Apex, Overwatch, Warzone;
  Fortnite and World of Warcraft add green). Colour is the weakest signal and the one games disagree on most: one
  article notes that a player took a turquoise Exotic weapon for the lower blue one
  ([GGRecon](https://www.ggrecon.com/articles/i-want-games-to-decide-on-a-rarity-system/), *read*).
- **The signal that works is what the item does to the picture, in order**: a new concept instead of a recolour at
  Legendary (the same article says Legendary skins usually have a concept of their own rather than added gold, and
  common ones are typically recolours); trim and light effects in the middle (Valorant's Deluxe); animation, finishers
  and
  particles at the top (Valorant Premium, Overwatch Mythic, Dota's Arcana, TF2's Unusual hats); a thing that changes
  while you play (Apex reactive skins, Valorant Ultra).
- **Every top tier above is bought or rolled** (packs, crates, a pass, a store). The ones that give things for acts are
  Helldivers 2 (Medals), Warframe (Nightwave acts), and Deep Rock Galactic (unlocks). None of them ties the *wildest*
  look to a stated act as far as we could read: that is the space our plan can take.
- **Rarity as a share of owners** (Destiny's shaders, CS2's drop odds) needs a population and chance. We have neither
  and must not use chance (plan rule 12): our rarity is **how hard the stated act is**, not how few have it.

## What players call cheap, and what the studios hold themselves to

| Complaint | Evidence | Take for Deadnight |
| --- | --- | --- |
| A recolour sold as a higher tier | Apex: "I'd rather have a selection of 3 or 4 major skin changes than 20 or 30 slightly different colour pallet"; Epic and Legendary skins "mostly new colors" ([Kotaku](https://kotaku.com/apex-legends-players-want-better-cheaper-skins-1834813028), *read*). Overwatch 2: a Legendary "is just a reskin with literally nothing changed about it" ([Dexerto](https://dexerto.com/overwatch/overwatch-2-players-blast-season-11-legendary-skin-thats-just-an-old-recolor-2798498), *read*) | A tier above the second is a different shape or material, never only a colour. Colours stay free of rarity (they are the 16-colour palette) |
| A look that does not fit the game's art | Call of Duty players call celebrity and space-marine skins "ridiculous", saying it "isn't a game like Overwatch or Fortnite where the skins fit the art style" ([GGRecon](https://www.ggrecon.com/articles/cod-players-slam-ridiculous-skins-on-offer-and-ask-for-future-games-to-calm-down), *read*) | Every top piece belongs to the 1958 drive-in and B-movie night: a saucer-pilot wing, a film-strip scarf, a creature mask; never a generic angel |
| A skin you will not see in play | Apex: a weapon shows your skin only when you pick it up first; "Why would I pay $18 for a skin I won't see even if I use the gun?" ([Kotaku](https://kotaku.com/apex-legends-players-want-better-cheaper-skins-1834813028), *read*) | Rarity is worn on the body the camera sees from behind (the back, the head, the feet), not on a held weapon, and others see it (an opt-out for the viewer) |
| An effect that costs readability | Riot's own rule: a skin's "primary feature should never be removed or significantly altered", an ability "at least as clear as the base skin", and a near-permanent glow that hides whether an effect is active is to be avoided; "the complete experience should make it quick and easy to identify the champion at all times" ([Riot, Clarity in League](https://www.leagueoflegends.com/en-us/news/dev/clarity-in-league/), *read*). An opinion piece says bright, bulky cosmetics become a "shiny target" ([Gadget Review](https://www.gadgetreview.com/?p=343116), *summary*); Marvel Rivals lets a player hide an effect, but only for themselves, so the team still sees it ([guide](https://topuplist.com/blogs/detail/marvel-rivals-team-up-vfx-toggle-settings-guide), *summary*) | An effect never covers the head, hands or a gun; it never looks like a zombie's glow or the generator's light (blue fire is a colour the night uses for nothing else, check it); a setting "Other players' effects: full, simple, off" |
| Recycled content | MW2 players "call out cosmetics recycled from Warzone 1" ([Charlie INTEL](https://www.charlieintel.com/call-of-duty-modern-warfare-2/modern-warfare-2-players-call-out-cosmetics-recycled-from-warzone-1-245367/), *summary*) | One effect, built once, is not offered as three tiers; each tier's piece has its own silhouette |

**Looking AI-made** (our reading, no source): the signs are the same as the cheap-skin complaints with a house style on
top: one blue-cyan-violet gradient on everything, a uniform soft glow with no shape under it, perfectly symmetric noise,
and effects that are not attached to a concept. The guards that follow from it: a hand-drawn silhouette first (the wing
is a drawn fan of feathers with a wear, a chip and one broken feather, not a generated shape), the effect follows the
shape (fire licks the feather edges, it does not float on top), one palette (the drive-in's neon: the lot's `tint`
colours, not a new rainbow), and **less glow than the first try**: glow is the accent of the top tier only.

## The test effect and the cost of each part

Four Soldiers (the shipped `SoldierLook`, real presets, two standing and two running) each wear wings with blue fire. A
tier above the middle needs a **slot** the ladder does not have yet (the wardrobe has headwear, top, trousers, shoes,
eyewear, neckwear): a *Back* slot is what carries wings, and it is the same mount (`Torso` bone) a pack or cape would
use.
The bench builds it in arms, each adding to the one before, so a part's cost reads from the frame:

| Arm | What is added | Draw calls it adds, per player |
| --- | --- | --- |
| `base` | four Soldiers, nothing else | 0 |
| `wings` | a dark feathered wing pair (7 feathers a side, 5 segments each, one opaque surface, unshaded with an ember edge) | 1 |
| `flame` | the flame sheet over the wings: the same fan, wider and longer, additive, a two-octave value noise scrolling off the tips; no texture | 1 |
| `gpu` | 40 flame sparks, `GPUParticles3D`, additive billboards, a colour ramp | 1 |
| `cpu` | the same sparks as `CPUParticles3D`, instead of `gpu` | 1 |
| `halo` | `gpu` + a billboard glow quad behind each (the lot's own `glow.gdshader`): the fake glow | 1 |
| `glow` | `gpu` + the engine's glow (`Environment.glow_enabled`, threshold 0.7): the real glow, a post pass | 0 objects, extra passes |
| `full` | `gpu` + `halo` + `glow` | |

![The effect on four Soldiers: wings, flame, sparks, halo and glow](cosmetic-rarity-effect.png)

### Measured: four Soldiers in view, 1280 x 720 (844 x 390 on the phone row)

Medians over interleaved rounds (arms shuffled by round, the page reloaded for every cell, the first 150 frames
dropped).
"Engine draws" is `RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME`; "WebGL draws" is what the browser was asked, counted in
the page with the kit's trace (`drawArrays`, `drawElements` and the instanced ones, wrapped for three seconds only). The
counts do not move with the machine: they are the comparison. Times are the engine's frame time.

| Arm | Engine draws | WebGL draws | Frame ms, desktop game | Frame ms, web on this GPU | Frame ms, web phone stand-in | Frame ms, web on SwiftShader |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `base` | 25 | 75 | 0.71 | 1.8 | 3.7 | 42.8 |
| `wings` | 29 | 83 | 0.74 | 1.8 | 3.7 | 44.1 |
| `flame` | 33 | 87 | 0.76 | 1.8 | 3.7 | 44.5 |
| `gpu` (sparks, GPU particles) | 37 | 95 | 0.81 | 2.1 | 3.8 | 46.0 |
| `cpu` (sparks, CPU particles) | 37 | 91 | 0.83 | 2.0 | 4.0 | 45.6 |
| `halo` (fake glow, 3.4 m) | 41 | 99 | 0.86 | 2.1 | 3.7 | 53.0 |
| `glow` (engine glow) | 37 | 103 | 0.86 | 2.1 | 4.1 | 65.9 |
| `full` | 41 | 107 | 0.93 | 2.2 | 4.0 | 69.7 |

- **Desktop game**: the pinned Godot, Compatibility, the RTX 5080 of this machine, windowed, no frame cap, three rounds.
  `gpu_ms` rises 0.17 to 0.26 ms and render CPU 0.20 to 0.32 ms for `full`.
- **Web on this GPU**: the installed Chrome, WebGL2, no frame cap, three rounds. **Phone stand-in**: the same Chrome at
  844 x 390 with a pixel ratio of 2, touch, and the processor slowed four times (what the kit page names for a phone's
  CPU side, `docs/godot/web-phone-frames.md`); it does not stand in for a phone's fill rate. **SwiftShader**: Chromium
  on the software renderer, 1280 x 720, two rounds of 60 frames; every pixel is paid for, the kit's stand-in for a weak
  GPU.
  The wings in the table are the first wing shape (fan higher up, soft violet edge); the final look (below, flat two
  colours, the fan lower so it clears the head) was measured again on this GPU (three rounds, the same eight arms: 1.8
  to 2.2 ms,
  the same draw counts) and on SwiftShader for four arms (43.1, 47.0, 68.2, 71.0 ms for `base`, `gpu`, `glow`, `full`).
- **The ceiling is not the draws.** Four wearers add 16 draw calls (4 a layer, one a wearer): 2 percent of the lot's 770
  at the start of a night ([phone frames](phone-frames.md)), and on a phone the frame is script and physics, not draws.
  What a weak GPU pays for is **pixels**: on SwiftShader the flame sheet costs 0.5 ms, the wings 1.3, the sparks 1.5
  (0.9 for CPU particles), the 3.4 m halo **7** over the sparks (53.0 against 46.0 ms; a big additive quad covers many
  pixels, and a
  second run of the arm against `base` gave 54.6 against 43.7 ms; at 1.8 m it gave 50.1, so the area is most of it),
  and the engine glow **about 20**, half as much again as the base frame.

### Does glow exist on each renderer? Yes, and it costs a screen pass

- **Desktop game (Compatibility, OpenGL)**: yes. `Environment.glow_enabled` works; the frame changes by 0.05 to 0.1 ms.
- **Web (WebGL2), on a GPU and on SwiftShader**: yes. The page's pixels differ from the glow-off view in about 490 000
  to
  510 000 of 921 600 pixels, against 22 000 to 38 000 between two glow-off views (the sparks move), and the mean
  brightness rises 18 to 29 (of 255). The WebGL trace shows why it costs: the glow adds one `blitFramebuffer` and **13
  more framebuffer binds a frame** (9 to 22) and 8 more draws, whatever the effect underneath, so it is a fixed cost
  per frame, paid even with no wearer in view if the setting is on.
- **It is not cheaper in pieces**: one blur level (the fourth) instead of the default three (0.8, 0.4, 0.1 at levels 1
  to 3) cost the same on SwiftShader (70.1 against 70.9 ms, with the same 13 extra binds): the price is the passes
  that read and write the whole frame, not the blur.
- **The night turned glow off on purpose**: [Night environment](night-environment.md) tried it for the lamps and dropped
  it ("a faint halo ... not enough to justify the extra post-processing passes on a weak web GPU"). This measurement
  agrees on the cost and shows the other side: a bright additive wing is the case where glow earns it.
- **Not measured: a real phone.** No phone is in reach of the machine; the stand-ins bound it (fill: SwiftShader; CPU:
  the slowed Chrome). The measurement that settles it is the maintainer's phone with `?arm=full` and `?arm=halo` on the
  bench page the probe exports, listed under the choices.

### The honest fallback

1. **Glow stays an accent of the effect, not a screen setting.** The flame's own pale core, drawn hard against a
   dark wing, reads as bright with no post pass; the sparks and a small halo add the rest.
2. **Tier 5 with the engine glow only on the desktop game and on the web when the frame has room**, off on a phone and
   under a software renderer (the kit lesson `docs/lessons/2026-11-02-a-browser-masks-the-gpu-from-godot.md` has the
   check for SwiftShader). The effect without the glow is `wings` + `flame` + `gpu` sparks: 12 draw calls for
   four wearers, 3 ms on the weakest stand-in.
3. **A halo quad only where it is small and near** (the nearest one or two wearers), or not at all on a phone: 3 to 7
   ms on the software stand-in for four of them.
4. **A level of detail by distance**, as the zombies have: the full effect within about 12 m of the camera, the
   `wings` + `flame` pair to 25 m, the dark wing beyond. Four wearers is the most a room holds; a 5-player lobby is
   the same four (the local one is seen from behind and close).
5. **Warm the effect up** with the first-use pass (the kit page `docs/godot/first-use-hitches.md`): the effect adds
   four shader programs (the wing, the flame, the
   sparks' material and the halo; the page's `useProgram` calls a frame go from 30 to 54), and a program is built
   the first time it is drawn.

## Proposal for the maintainer: five tiers, three name sets, how each is earned

Every row marked **Choice** is the maintainer's. Nothing here is built.

### The tiers (Choice: five, the industry's usual count)

| Tier | What it adds to the picture | Cost class (measured above) | Earned by (never bought, never random) |
| --- | --- | --- | --- |
| 1 | Plain: the piece as drawn | none | The starting pieces and the first ten levels |
| 2 | A trim in the shared palette, a second material | none | Levels 11 to 20 |
| 3 | Painted detail and a static emissive trim (a bulb row, a stripe that glows): drawn, not animated | none (a material parameter) | Levels 21 to 33 |
| 4 | **An animated surface**: a shimmer, a scrolling film-strip, a chrome sweep, on the piece's own mesh | none in draw calls (the piece already draws); a few fragment instructions | Levels 34 to 46, plus a poster set (a finished themed set of six challenges) |
| 5 | **An attached effect** (wings with blue fire, a creature mask that breathes embers, a film-strip scarf that streams): a back, head or neck piece with flame, sparks and a glow | one to three draw calls a wearer, the real glow only where the platform allows it | Levels 48 to 52, **or** a stated hard act: "beat the back rooms at round 15", "Encore star 3", a hidden poster. Never a pack, never a timer |

- **Rarity is the stated act's difficulty, not a share of owners** (see the first section): the plan's rule 12 and rule
  11
  hold, and a player can read in the grid what the tier asks for.
- **Colours stay free of rarity** (the 16-colour palette is not a tier); a tier-3 piece in any colour still glows its
  own
  trim colour.
- **A top piece may not cover** the head, the hands or the held gun (Riot's rule above; in the bench the first wing
  shape
  hid the wearer's head from behind and the fan was moved down), and it keeps the Soldier's silhouette readable at 25 m.
- **Blue is not unique to it**: the Bolt weapon's burst and the shock perk are electric blue, so a wearer can be taken
  for a source of damage. **Choice:** the maintainer's blue fire stays as the example, and the effect colour follows the
  wearer's trim colour, so not every wearer is the same blue. The style page lists "purple-to-blue gradients" and "even
  neon glow on everything" as the look of generated work: the test effect is two flat colours with hard edges (the
  shock arc's look), and the glow is the top tier's alone.

### Three name sets (original; Choice: one of them, or a mix)

The level plan already uses *Doors Open, Cartoon, Newsreel, Intermission, Trailers, Second Feature, Main Feature, Late
Show, Midnight Show, Headliner, Last Reel* for its eleven level tiers, so these avoid all of them.

| Tier | A. **The Billing** (who is named on the poster) | B. **The Showing** (when it plays) | C. **The Print** (the film's life) |
| --- | --- | --- | --- |
| 1 | Extra | Matinee | Dailies |
| 2 | Bit Part | Dusk Showing | Release Print |
| 3 | Supporting | Feature Presentation | Special Edition |
| 4 | Lead | Graveyard Slot | Director's Cut |
| 5 | Marquee Name | Cult Classic | Lost Reel |

- **A** reads at a glance in the grid ("Marquee Name"), and a poster set makes sense with it ("top-billed"). It is the
  safest and the most plainly a ladder.
- **B** is the most drive-in and carries the zombie night ("Graveyard Slot"); *Cult Classic* is a top tier a player
  would be proud of. Its risk: "Feature Presentation" is long on a 24 px chip.
- **C** is the most B-movie and the best story for the top ("Lost Reel"), and the hardest to read as a ladder to a new
  player.
- **My pick: B for the names, A's plain words in the tooltip** ("Cult Classic: the top billing"). **Choice.**
- **Signals beyond colour** (so colour is never the only sign): a frame shape on the grid cell and the plate, one per
  tier (a plain stub, a notched ticket, a ticket with a bulb row, a marquee panel, a framed one-sheet with a lit edge),
  the name in the tier's tooltip, and from tier 3 up the piece's own trim shows on the grid's preview. The tier colours
  come from the lot's neon palette, not the grey-blue-purple-gold of other games.

### How the 26 wearables of the level ladder map

Existing pieces are marked (e); the rest are new art in the plan.

| Tier | Pieces (level) |
| --- | --- |
| 1 | Rolled sleeves 4 (e), Usher's cap 6 (e), Jacket 8 (e), Shorts 11 (e), Boots 12 (e) |
| 2 | Goggles 13 (e), Helmet 14 (e), Tank top 16 (e), Usher's jacket 18, Press lanyard 19, Striped trousers 20 (e) |
| 3 | Ranger hat 22 (e), Cinema glasses 24, Letter jacket 26 (e), Saddle shoes 28, Overalls 31, Projectionist's visor 33 |
| 4 | Bolo tie 34, Coveralls 36, Roller skates 38, Swing skirt 40, Creature tee 44, Rubber boots 46 |
| 5 | Creature mask 48, Film-strip scarf 50, Varsity gold 52, **and the new Back slot** (wings and the like) |

- Five, six, six, six and three plus the Back slot make the 26. The ladder keeps its order; a piece's tier is where its
  level falls, so nothing is re-gated.
- **Choice: a Back slot.** Without it the top tier can only be a head or neck piece with an effect, which is the wrong
  place for wings. With it, tier 5 gets three to five new pieces (a pair of wings, a film-reel pack, a flame cape, a
  saucer-pilot jet pack) that are more art than the plan holds for the first waves (the plan's art-in-waves answer
  covers it). The effect pieces are drawn from the same shared parts (feather, reel, flame).
- **Choice: effects on tier 4 and 5 are visible to others by default**, with the setting "Other players' effects: full,
  simple, off" (rule 16's relatives). *Simple* swaps the particles and the glow for the flame sheet alone; *off* shows
  the dark wing.

### What I would do

1. **Take the five tiers and name set B**, with A's plain words in the tooltip, and the mapping above (nothing
   re-gated; the ladder's 26 pieces fall 5, 6, 6, 6, 3).
2. **Build tier 5 as wings and other back pieces on a new Back slot**, drawn from shared parts, and cap it at four
   effect layers a wearer: dark wing, flame sheet, sparks, and (only near) a halo. That is one draw call a layer a
   wearer: 16 for four wearers, 2 percent of the lot's draws.
3. **Do not put the engine glow in the shipped effect.** It is the one part that is not cheap: a fixed screen pass
   (13 more framebuffer binds, one more blit) that cost about half a frame again on the software stand-in, and
   the night already dropped it once. On the desktop game it is 0.05 to 0.1 ms and may be a setting ("Glow: on by
   default on the desktop game, off on a phone and on a software renderer").
4. **Keep rarity out of colour**, tie it to a stated act, and give it a setting for what others wear.
5. **Draw the first top piece by hand before the second tier-5 piece is planned**, and show it to the maintainer
   beside the flat test effect: this bench proves the cost, not the look. A wing with a drawn silhouette, a chip and a
   broken feather will read as made by hand; a fan of identical feathers (as the test's) does not.

### The choices left for the maintainer

| # | Choice | My answer |
| --- | --- | --- |
| 1 | Five tiers, or four or six | Five |
| 2 | Name set A, B, C or a mix | B, with A's words in the tooltip |
| 3 | A Back slot, and wings as the first piece | Yes; wings first, a film-reel pack second |
| 4 | How tier 5 is earned: by level, by a stated hard act, or both | Both: three by level (48, 50, 52) and the Back pieces by acts and poster sets |
| 5 | Others' effects: shown by default with a three-way setting, or hidden by default | Shown, with "full, simple, off" |
| 6 | The engine glow: a setting on the desktop game and the web when the frame has room, or never | A setting, off on a phone and a software renderer |
| 7 | One blue for all, or the wearer's trim colour | The wearer's trim colour; blue the default |
| 8 | Try it on a phone before the build issue is filed | Yes: `?arm=full`, `?arm=halo` and `?arm=glow` on the bench page the probe exports |

### What changed on the way

- The first wing shape (a soft gradient with a violet edge, a sine hash) was replaced by the flat two-colour look and
  the
  sine-free hash the shock shader uses; the cost did not change (same draws, same programs).
- The first halo sat on the back, between the camera and the body, and veiled the head; it now sits in the chest so
  the body hides it.
- The bench loads the lot's own `glow.gdshader` for the halo; nothing of it is copied.

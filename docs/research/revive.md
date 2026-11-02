# Teammate revives

Research for #486, 2026-11-02: how co-op zombie shooters handle being downed and being picked up, so Deadnight can pick
its own rules. Call of Duty's Zombies mode is the reference the maintainer named; Left 4 Dead and Back 4 Blood are the
two others. The rules we chose are in [Revive](../design/revive.md). This page studies design only: no names, layouts
or assets are copied, and no number below is carried over unchanged.

How each fact was learned, because the sources are thin: **read** means I read the text of the page myself;
**reported** means a search summary or a community page that I could not open or that is not the game's own data.
The fan wikis for all three games (Fandom) refused every fetch, so the exact base numbers come from a Steam guide, a
magazine guide and mod changelogs, and **the sources disagree**; where they do, both figures are given. Nothing here
is from the games' own files.

## Summary

- Every game has the same three states: **up**, **down** (alive, helpless, a clock running) and **out** (the clock ran
  out, or a rule killed you). A teammate's hold on the use button moves you from down to up; nothing else does,
  except a perk or an item that moves you from down to up on your own.
- The **clock** is long in L4D (minutes), short in CoD Zombies (half a minute), and the hold takes about as long as
  a reload (three to five seconds). A short clock makes the revive an emergency; a long one makes it a chore.
- Every game gives **a way to shorten the hold** (a perk, a card) and a **way to save a lone player** (an item, a
  perk that is a limited self-revive). A lone player with no such thing loses the run on the first down.
- **A run ends when everyone is down** (CoD, L4D) or when the team has no lives left (Back 4 Blood). A player who is
  out for good watches, or comes back at the next checkpoint or round, depending on the game.
- Deadnight has none of this yet: a downed player stands where they fell and gets up at the end of the round
  ([rounds](../design/rounds.md#how-rounds-work)). The decisions that the maintainer has to make are listed
  at the end.

## Call of Duty Zombies (the named reference)

| Question | What I found | Source |
| --- | --- | --- |
| Downed state | The downed player is in "last stand". Community pages describe a crawl and a pistol, and the Steam guide below reads as if the player can be helped back up while crawling. Not confirmed in a source I could open: whether crawling changes the clock (a forum thread titled "crawling in last stand has no effect on how long it lasts" exists; I could not read it). | [GameFAQs thread title](https://gamefaqs.gamespot.com/boards/960189-call-of-duty-black-ops/59983817), reported |
| Time until bleed-out | **30 seconds** in the Zombies of the Black Ops era, "after which the player is removed from the round". A later game (Black Ops 4) was patched so that the last zombie of a round gets a longer bleed-out (5 to 10 minutes), which shows the designers treat the clock as a tuned value, not a constant. | [Nazi Zombies wiki, Last Stand](https://nazizombies.fandom.com/wiki/Last_Stand) (search summary, reported); BO4 patch note (search summary, reported) |
| Hold to revive | **3 seconds** with no perk in one Steam guide ("Stock Revive time: 3 seconds"), **about 4 seconds** in the Nazi Zombies wiki's summary. The two disagree. | [Steam guide: Just a Perks guide](https://steamcommunity.com/sharedfiles/filedetails/?id=135266390) (read, fetched); wiki (reported) |
| Interrupted? | Not found in any source I could open. | |
| Perk that changes it | **Quick Revive**: "you revive people twice as fast": 1.5 s from 3 s in the guide; 0.75 s with a second permanent version. In Black Ops 6 the perk "reduces the time it takes to revive an ally by 50%" and halves the health regeneration delay. | [Steam guide](https://steamcommunity.com/sharedfiles/filedetails/?id=135266390) (read); [Game8, BO6 Quick Revive](https://game8.co/games/Call-of-Duty-Black-Ops-6/archives/480521) (read) |
| Perks and items around it | BO6 "augments" change the revive: reviving an ally keeps their perks on their bleed-out bar, speeds both of you up for a moment, or heals you; one lets you revive yourself by killing a zombie while down, at most three times; one makes you immune for two seconds at lethal damage; one lengthens the time in last stand. Another game's perk (Electric Cherry in the Steam guide) fires when you revive a teammate. | [Game8](https://game8.co/games/Call-of-Duty-Black-Ops-6/archives/480521) (read); [Steam guide](https://steamcommunity.com/sharedfiles/filedetails/?id=135266390) (read) |
| Solo | One earlier game gave a solo player a "Revive" for **500 points**, "usually available from the start", usable **three times** in a game, and "you wait out 30 seconds, then you help yourself back up". BO6 hands a solo player one self-revive automatically and sells more at a crafting table. | [Steam guide](https://steamcommunity.com/sharedfiles/filedetails/?id=135266390) (read); [Game8](https://game8.co/games/Call-of-Duty-Black-Ops-6/archives/480521) (read) |
| How being downed ends the run | Out of the round when the clock ends (a player respawns at the next round in the games I know; not confirmed from a source here). The match ends when every player is down. | not confirmed by a source I could open |
| HUD | Not found in a source I could open. From play (unsourced): the downed player sees a bleed-out bar and teammates see an icon over them. We make our own and capture it. | |

## Left 4 Dead (series)

| Question | What I found | Source |
| --- | --- | --- |
| Downed state | "Incapacitated": the survivor "falls to the ground with 300 temporary health" that drains, and is "limited to your sidearms, which fire far more slowly and with much lower accuracy". A survivor hanging from a ledge is a second kind of down. | [Fandom summary](https://left4dead.fandom.com/wiki/Incapacitated) (reported, via a search summary); [bit-tech guide](https://bit-tech.net/reviews/gaming/pc/complete-guide-to-left-4-dead/5/) (read) |
| Time until bleed-out | "It takes **around 240 seconds** for an incapacitated team-mate to bleed out", and much faster if they are pinned or surrounded. A community changelog gives the stock decay rate as 3 and the incapacitated health as 300, which fits 100 seconds if the unit is per second, so the figure depends on the version; do not take any of them as exact. | [bit-tech](https://bit-tech.net/reviews/gaming/pc/complete-guide-to-left-4-dead/5/) (read); [Steam changelog of a mod](https://steamcommunity.com/sharedfiles/filedetails/changelog/2280431319?p=2) (reported) |
| Hold to revive | "It takes **five seconds** to resurrect an incapacitated team-mate." | [bit-tech](https://bit-tech.net/reviews/gaming/pc/complete-guide-to-left-4-dead/5/) (read) |
| Interrupted? | **Yes: "the timer is reset every time an infected strikes the rescuer."** The advice that follows is the team plays it: "two of you should melee away the waves of infected while the third rescues." | [bit-tech](https://bit-tech.net/reviews/gaming/pc/complete-guide-to-left-4-dead/5/) (read) |
| After the revive | The survivor gets up with low health, most of it temporary ("30 health points, 29 of them temporary"). After the second incapacitation the screen goes black and white: "the next time you are knocked down you'll be killed". A medkit resets the count. | [bit-tech](https://bit-tech.net/reviews/gaming/pc/complete-guide-to-left-4-dead/5/) (read); [Fandom](https://left4dead.fandom.com/wiki/Incapacitated) (reported) |
| Solo / self-help | A pinned survivor can free themselves with an item (a hold; the revive cvar `survivor_revive_duration` is the time a mod uses for it). | [AlliedModders thread](https://forums.alliedmods.net/showthread.php?p=2413840) (reported) |
| How a run ends | Not stated in the page I read; the player has to choose who to save first when more than one is down. | [bit-tech](https://bit-tech.net/reviews/gaming/pc/complete-guide-to-left-4-dead/5/) (read) |
| HUD | The black-and-white vision is the HUD's way to say "one more and you are out". | [bit-tech](https://bit-tech.net/reviews/gaming/pc/complete-guide-to-left-4-dead/5/) (read) |

## Back 4 Blood (the third)

| Question | What I found | Source |
| --- | --- | --- |
| Downed state | When health reaches zero the player falls but does not die; "a second health bar then appears", and the player "can still use equipped secondary weapons". A downed player can **hold the button to die** at once when no one can come. | [Gamepressure](https://www.gamepressure.com/back-4-blood/death-consequences/z8eb89) (read); [Sportskeeda](https://www.sportskeeda.com/esports/how-revive-teammates-back-4-blood) (search summary, reported) |
| Time until bleed-out | One report puts the standard window near 90 seconds, and says a bug with one character in the party cut it to 20 to 30 seconds (acknowledged by the developers). | [PiunikaWeb](https://piunikaweb.com/blog/back-4-blood-mom-in-party-speeds-up-bleed-out-time-bug-acknowledged) (search summary, reported) |
| Hold to revive | A teammate holds the interact button; no time found. | [Sportskeeda](https://www.sportskeeda.com/esports/how-revive-teammates-back-4-blood) (reported) |
| After death | A dead player cannot be revived without a defibrillator; without one they "take control of a bot, but only if your squad uses bot NPCs", or are carried to another part of the map and respawn there to be freed later. | [Gamepressure](https://www.gamepressure.com/back-4-blood/death-consequences/z8eb89) (read) |
| How a run ends | A team that fails a location loses a **life** (the number depends on difficulty and the cards chosen) and restarts the location. | [Gamepressure](https://www.gamepressure.com/back-4-blood/death-consequences/z8eb89) (read) |

Related, from the [bot research](bots.md): in every game, **bots that fail at revives are the thing players name**:
they run in with zombies on the victim, give up at the first hit, or ignore the call. Our bots clear the zombies around
the victim first ([bots, revives](bots.md#the-recommendation-in-one-screen)).

## What the games agree on, and where they differ

| Axis | Agree | Differ |
| --- | --- | --- |
| A downed player acts | Little: a weak sidearm, slow or no movement, no shopping or teammate help. | CoD crawls; L4D stays; B4B can use a sidearm and can choose to die. |
| The clock | One, visible to the downed player at least. | 30 s (CoD), 90 s to 240 s (B4B, L4D). Pinned or surrounded in L4D shortens it. |
| The hold | A held button, a progress meter, 3 to 5 s. | Whether a hit resets it (L4D yes). Whether a perk halves it (CoD, BO6, yes). |
| Solo | A paid or found one-off self-revive that costs time or points. | A free single self-revive (BO6) against none (L4D). |
| After | The revived player is weak for a moment. | CoD gives the perks back with an augment; L4D gives temporary health and a black-and-white state. |
| End | Everyone down ends the run (CoD, L4D) or costs a life (B4B). | A downed player out for good returns at the next round (CoD), is carried or free in the next area (B4B). |

## What Deadnight has today

From the code on the `scoreboard` branch this was written on:

- **Down:** `PlayerHealth.down` sets `downed` at zero health; the body stays where it fell; the frame carries
  `downed`; shopping is refused (`PLAYER_DOWNED`); the zombies stop chasing a downed player. `set_downed` is a server
  action with no client road.
- **Up:** only the end of a round: `PlayerHealth.revive` runs for each downed player then, after a down penalty of a
  fraction of their points. `player_revived` has no reviver.
- **The night ends** when every player is down, as soon as the last one falls.
- **Hold actions already exist**: repair is a held `use` the server paces (`_repairing`), and the HUD's prompt kinds
  and the touch button's labels already name `revive` (`ui/hud/hud_prompt.gd`, `ui/touch/touch_controls.gd`) with no
  server behind them.
- **The balance simulator** models a revive at 6 seconds and half health with no bleed-out
  (`tools/balance/night_sim.gd`), written before anything was built.
- **A `Downed` clip** exists (`assets/characters/soldier/clips.json`); there is no clip for the reviver.

## What we take

1. **Three states: up, downed (bleeding), dead (until the round ends).** Same as CoD and L4D, with the death a
   round long and not for the night.
2. **A hold, not a press**, with a progress ring both players read, a reach, and an interrupt when the reviver goes
   out of reach or is downed. Not "any hit resets it" (L4D's rule makes clearing the zombies first the whole game; ours
   gives the reviver a risk instead, [design](../design/revive.md#the-hold)); that is a decision for the maintainer.
3. **A bleed-out clock between the two games' lengths** that stops while someone holds the revive, so a revive that
   began never ends in a death by a hair.
4. **No self-revive by default** and no perk: both are shop decisions ([tonics, #281](https://github.com/Ryubara/deadnight/issues/281)).
5. **Everyone down ends the night**, unchanged.
6. **The counts are the server's**: a `REVIVES` column beside kills and downs, never counted by a client.
7. **A downed player does nothing**, as today. The maintainer decided against a crawl and a sidearm.

## The questions, and what was decided

The maintainer approved the built answer to each on 2026-11-02 (#505; [the list](../design/revive.md#decided-2026-11-02-505)).

1. **Solo self-revive**: none, one free, or paid? (CoD: paid, three times; BO6: one free.) Decided: none.
2. **A revive perk or tonic**: halve the hold, or keep the downed's perks? (#281's tonics.) Decided: none for now.
3. **Crawl and sidearm while downed**: both CoD and L4D let a downed player act a little. Decided: neither.
4. **A hit on the reviver resets or slows the hold**: L4D resets, CoD unknown. Decided: no.
5. **Points for the reviver**: the build pays none (a field in the resource, default 0). Decided: 0.
6. **Dead players**: watch a teammate, get up at the next round (built), or only with an item.
   Decided: get up at the round's end.
7. **Bleed-out pause**: the clock stops while someone holds the revive (built); CoD and L4D unknown. Decided: on.
8. **A reviver clip** for the soldier: `Revive_Kneel` from #536 (a Blender job, not wired here).

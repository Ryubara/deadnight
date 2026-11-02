# Challenges

What we looked at before designing the daily challenges, orders, milestones and the in-night progress prompt (issue
399), what players dislike about them, and what we built because of it. The design is in
[Permanent progression](../design/progression.md#challenges-dailies-orders-and-milestones). Study was for
understanding only: no text, layout or icon of another game is reused.

## How we searched, and what we could not read

Web search and page fetches. Several press pages refused the fetch tool (GameSpot, PC Gamer) and are cited only for
what the search summary said, marked *summary*. Forum and blog posts are anecdotes, marked *anecdotal*. We found **no
authoritative source for how long an in-play toast should last or where it should sit**: the numbers in the design are
ours, to be tuned by capture and play, not copied. We also found no design writeup worth citing on what makes a
challenges screen look modern; that comes from our own [UI look](../design/style.md#ui-look) rules.

## What other games do, and where it went wrong

| Example | What it does | What players or the studio said | Take |
| --- | --- | --- | --- |
| Daily quests in general | A small task per day, a streak or a login bonus on top | A CHI Play study of engagement rewards found players split three ways: motivation, fear of missing out, and an obligation or chore ([Daily Quests or Daily Pests?](https://doi.org/10.1145/3549489), *summary*). PC Gamer's headline calls them "tedious" ([article](https://www.pcgamer.com/daily-quests-arent-fun-theyre-tedious), *summary*). Path of Exile's co-creator called login streaks manipulative ([GamesRadar](https://www.gamesradar.com/games/when-i-was-growing-up-games-were-designed-to-be-fun-not-manipulative-path-of-exile-co-creator-shines-a-blacklight-on-the-bulls-t-design-tricks-infesting-all-my-live-service-games), *summary*) | An offer, never a debt: no streak, no login reward, nothing that punishes a missed day |
| Fall Guys | Randomised, personalised dailies replaced fixed ones | One player's blog: a "jump 45 times" task can finish in a round, another day eats two hours; asks for fixed challenges back ([Punished Backlog](https://punishedbacklog.com/a-case-against-fall-guys-new-randomized-daily-challenges/?amp=1), *anecdotal*) | Deal by date (the same for everyone), and size each tier so a short one is short |
| Fortnite weekly quests | Chapter 4 season 1 made weekly quests expire after a week; Epic later reversed it ("Weekly Quests will no longer expire after a week", patch 23.30) | Players who could not play every week fell behind the pass ([Kotaku](https://kotaku.com/fortnite-weekly-quests-old-epic-patch-update-chapter-4-1850002299), [Gamepur](https://vip-develop.gamepur.com/?p=474687), *summary*) | Unfinished work stays: the bank |
| Overwatch 2 weekly challenges | Season 5: unfinished weekly challenges stopped resetting to zero (all progress carries over); win-based ones became "complete games", with double progress for wins | Patch notes and press ([Dexerto](https://dexerto.com/overwatch/overwatch-2-reveals-big-changes-to-weekly-challenges-in-season-5-2174623), [Prima Games](https://primagames.com/tips/overwatch-2-june-13-update-full-patch-notes-listed), *summary*). A later system showed 0/3 after a finish before the reset and confused people ([Blizzard forum](https://us.forums.blizzard.com/en/overwatch/t/the-new-weekly-challenge-system/908468), *anecdotal*) | Carry progress, make playing count, and never show a number that goes backwards |
| Halo Infinite | At launch only challenges paid; the studio added a "play one game" challenge and eased the weeklies | Players said the matches themselves counted for nothing and that challenges pulled them off the team's goal ([Pure Xbox](https://www.purexbox.com/news/2021/11/halo-infinites-battle-pass-progression-is-being-updated-in-response-to-player-feedback), [Stevivor](https://stevivor.com/news/halo-infinite-battle-pass-progression-complaints/)) | Playing always counts; no challenge pays for hurting the team |
| Destiny 2 | Bounties and quests lived together in one Pursuits list | A long-running complaint: too many presses, everything lumped together, and a count in the dozens made the list feel big and unfocused; Bungie later separated bounties from quests ([Bungie.org thread](https://destiny.bungie.org/forum/index.php?id=162457), [Gamerant](https://gamerant.com/destiny-2-separating-bounties-quests-update/), the counts from a 2019 critique, *anecdotal*) | Three dailies, three orders: a short list, grouped by kind |
| Helldivers 2 Major Orders | One shared goal, progress as a bar and a percentage on the map | The recurring complaint was progress that was not tracked or lagged ([GamesRadar](https://gamesradar.com/helldivers-2-major-order-progress-might-not-be-tracked-properly-as-the-war-systems-suffer-a-minor-outage), [VideoGamer](https://www.videogamer.com/news/helldivers-2-glitch-is-causing-the-current-major-order-to-not-be-tracked-correctly)) | A progress bar is only trusted if it is exact: count from events, test every stat against the client's own count |

## Toasts and prompts in a fast game

| Source | Finding | Take |
| --- | --- | --- |
| UEFN notification guide ([summary](https://uefncentral.com/de/blog/optimized-in-game-notifications-uefn)) | Persistent HUD for ongoing status, popups for brief celebrations; batch similar events (multi-kills) instead of one popup each; placement by urgency, minor items in corners | A quarter mark is minor: edge, short, batched; a completion is the celebration |
| Popup plugins and mods ([RuneLite Watchdog](https://github.com/adamk33n3r/runelite-watchdog/wiki/Popup-Notification), [Star Conflict thread](https://forum.star-conflict.com/t/improvements-for-pop-ups-information-on-the-hud-screen/11654), *anecdotal*) | One at a time, queued, auto-dismissed; players ask for adjustable duration and a way to switch popups off | A queue with a cap, and a setting |
| Game Accessibility Guidelines ([allow players to progress through text prompts at their own pace](https://gameaccessibilityguidelines.com/allow-players-to-progress-through-text-prompts-at-their-own-pace)) | Reading speeds differ even in narrow age groups; key information gets missed through distraction | A prompt never carries the only copy of something: everything it says is on the Challenges tab |
| WCAG 2.2.1 Timing Adjustable ([BOIA](https://www.boia.org/wcag2/cp/2.2.1)) | A time limit needs an off or adjust control; real-time activities are exempt | A toast is not a time limit on the player, but a setting for prompts (all, completions only, off) costs nothing |
| Xbox Accessibility Guidelines ([version history](https://learn.microsoft.com/ar-sa/xbox/accessibility/xag-version-history), *summary*) | Critical UI text at a lower secondary reading level; larger subtitles because they are on screen briefly | Plain words, six at most, large numbers |

## What we built because of it

- Three dailies a day, banking up to three, no streak (the Fortnite and Overwatch reversals; the CHI Play split).
- Dealt by date, so a day is the same for everyone and a tier's size is its promise (Fall Guys).
- Every stat counted from the night's events and checked against an independent count in a real played night
  (`test_night_challenges.gd`), so a bar can be trusted (Helldivers).
- A prompt that is rare (quarter marks, and only when a target is large enough to have them), queued, short and
  switchable.

## Learned while building

- **A rotation that avoids yesterday needs yesterday.** Passing over the day before's challenges makes today depend on
  a chain with no start. Anchoring the chain at the first day of each 30-day block keeps the deal a pure function of
  the date, at the price of one possible repeat per block (tested: no repeat on any other day).
- **An event the rules do not send cannot be counted.** Revives were on the issue's list, but a downed player here gets
  up when the round ends and `player_revived` names nobody who helped; weapon mastery is not built. They are left out
  of the data rather than shipped as challenges that cannot finish.
- **Kills arrive before the shot that made them.** The server's outbox puts the rules' `zombie_removed` ahead of the
  combat server's `shot_fired`, so a kill's weapon is the weapon the player held (the last `weapon_equipped`, shot or
  frame reading), not the last shot. The played-night test checks that every kill is a weapon's or a grenade's.
- **`parse_string` prints an engine error on bad JSON.** A test of a damaged save would print `ERROR` in the log; a
  `JSON` instance's `parse` returns the code quietly.
- **A night test that buys a door should wait for the bake** (`NightFixture.settle_bake`) before freeing the night,
  and still leaves "resources still in use at exit" now and then: the existing night suites do too (one run in four
  of `test_night_hud_ammo.gd`).

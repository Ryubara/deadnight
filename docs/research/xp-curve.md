# The XP curve as built

What the level curve of issue #1058 measures, and how the test that holds it works. The design is
[The curve](../design/progression.md#the-curve); the earlier 150-night measurement is on the
[progression research page](progression.md#what-the-simulator-measured). This page is the CI-sized read the test
makes on every run.

## What is built

- `LevelCurve` (`game/gameplay/progression/`): XP to leave a level by tier of five, 85 up to 590, **18,010 XP to level
  55**; only raw XP is stored, the level is computed.
- `XpRules`: the lines as pure functions. A running total is kept in **hundredths of an XP** (a point is a hundredth),
  so a server adds a kill's points as they are earned; `XpRules.live(change)` is what one `NightTally` change adds and
  `XpRules.settle(stats, awards)` what a finished night is worth, and a test feeds a night change by change and gets
  the same number. The night's cap (1,500 XP) holds the whole total.
- `ProgressSession` counts the local player's night and writes the profile at each round's end; `ProfileStore` keeps
  `user://profile.json` as a cache and a retry queue. A Guest account earns like any other (the maintainer, 2026-11-04);
  a night with no account at all earns nothing.

Two readings of the issue's words, both one constant in `XpRules`: "2 XP a board mended (to 100)" is **100 XP at most**
(50 boards), and "a round reached" pays when the round **starts** (the `round` stat), so the round a night ends in is
paid, as the simulator model assumed.

## Measured (60 seeded nights a cell, seed 4000)

Nights only, with 120 s of menus between nights, the 12 s intro and 5 s breaks, and the opening night's 50 XP credited
once. Boards, doors, cans, bosses, revives, dailies and the day's first game pay more, so every time is an upper bound.

| Cell | Kills a night | Rounds | XP a night | Level 2 | Level 10 | Last level (54 to 55) | Level 55 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Strong, solo | 249.8 | 14.3 | 553 | 0.9 min | 23.8 min | 15.3 min | 7.8 h |
| Average, four | 657 | 14.4 | 458 | 1.2 min | 31.6 min | 20.3 min | 10.3 h |
| Average, four, count x2 | 428 | 8.4 | 265 | 1.1 min | 30.0 min | 19.3 min | 9.8 h |
| Strong, solo, count x2 | 111 | 7.2 | 236 | 1.1 min | 27.8 min | 17.9 min | 9.1 h |
| Average, solo | 112 | 9.5 | 316 | 1.0 min | 26.5 min | 17.1 min | 8.7 h |
| Average, solo, count x2 | 62 | 5.2 | 155 | 1.3 min | 32.9 min | 21.2 min | 10.8 h |
| Strong, solo, count x5 | 86 | 2.9 | 134 | 1.2 min | 30.8 min | 19.9 min | 10.1 h |
| Average, four, count x5 | 123 | 2.1 | 70 | 1.9 min | 49.3 min | 31.8 min | 16.1 h |
| Average, solo, count x5 | 18 | 1.2 | 41 | 2.6 min | 68.9 min | 44.4 min | 22.5 h |

**The shape:** the first level takes about a minute and the last 15 to 20 minutes (a level of the last tier costs 590
XP against 85 for the first, **6.9 times**), and no level is quicker than the one before it. **Level 10, the second
map, lands after 24 to 32 minutes** in the nights that count 240 or more kills. The cells that count fewer kills (the
bot dies in the first rounds at count x5) are slower, so a horde modifier is not a way to level faster.

## How the test holds it

`game/tests/rules/test_xp_pace.gd` reads the cells through `ShippedCells` (`game/tests/rules/shipped_cells.gd`), the
cache the balance gate also reads, and `BalancePace` (`game/tools/balance/balance_pace.gd`) turns a cell into XP and
minutes. The bands (level 55 in 7 to 11.5 hours, level 10 in 20 to 40 minutes, the first level inside 3 minutes, the
last between 10 and 30 minutes) apply to the nights that count at least 240 kills, the maintainer's target of over 300
kills a game read loosely because the model's strong solo night counts 290 at 150 nights and 249.8 at 60; the
first-level band holds in every cell.

**CI cost:** the gate's own six cells took 54 to 61 s on worker threads on this machine; the pace suite, run after it
in the same process, added **6 cells in 13 s** (average and strong solo and average four at count x2 and x5; the three
at x1 are the gate's cells and cost nothing again). Alone it runs nine cells in 29 s. Suites in separate shards do not
share the cache, so the x1 cells run twice there, a few seconds.

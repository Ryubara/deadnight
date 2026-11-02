# Crowd budget: what the web build pays for 40 and 46 zombies

The measurement behind [the crowd-budget decision](../design/zombies.md#decision-the-rules-cap-stops-at-40-315)
(issue #315): four players could have 46 zombies alive, the web ceiling is 40. Method, numbers and what they do not
say. The kit's crowds spike (`docs/godot/crowds.md` there) measured a bare crowd; this page measures the real night.

![Frame time against the crowd, as played and at worst](crowd-budget.png)

## What the client does above 40

Nothing: it never stands more. `ZombieTuning.hard_cap` (40) lets the director admit a spawn request only while fewer
than 40 stand; the rest wait in its queue, still counted alive by the rules (which decide spawns and the end of the
round) and by the balance model, which has no director. So a cap of 46 meant 40 on the lot and 6 queued. In the web
build with the cap at 46 the highest `alive` the probe ever read was 40 in all four runs.

## How it was measured

A throwaway build of the game (not committed; the numbers are the product) with these changes, otherwise the shipped
code and the real menu, night, camera and view:

- `RoundTuning.alive_cap` read from the page's `?alive=N`; 600 zombies a round, one every 0.25 s, 30% runners, 10%
  crawlers and 6% brutes from round 1 (the round-30 mix), player health 1,000,000 so the night does not end.
- `?worst=1`: every zombie at gameplay detail whatever its distance (`FAR_FROM` 100 km), the animation throttle off
  (every zombie advances every frame), and no frustum culling. This is the most the crowd can cost; real play is
  between the two.
- `tools/web_smoke/first_use.py`'s page recorder (a `requestAnimationFrame` delta per frame, the probe's `alive`), the
  player walking a square and firing, 25 s of night after the menu. Frames counted are those with at least 90% of the
  cap alive (the empty lot: after 10 s). Two runs a cell.
- Chrome 156 (installed, GPU: RTX 5080 through ANGLE D3D11), headless, `--disable-gpu-vsync --disable-frame-rate-limit`
  so the page is not held to the display, 1280 x 720, a fresh profile each run.

## Numbers (ms per frame, mean and p95, two runs each)

| Alive | As played mean / p95 | Worst case mean / p95 |
| ---: | --- | --- |
| 0 | 2.5 / 4.2 | 3.2 / 5.5 |
| 28 | 2.4 to 4.0 / 5.0 to 11.3 | 8.1 to 11.0 / 12.7 to 16.7 |
| 40 | 3.4 to 5.1 / 7.9 to 14.3 | 8.1 to 10.3 / 12.5 to 14.8 |
| 46 asked | peaked at 40 (never settled at 46) | peaked at 40 |

- At worst a zombie costs about 0.15 ms here (3.2 ms empty, 8 to 10 ms at 40), so the six more would add about 1 ms
  on this machine. As played, the cost is a third of that: most of the crowd is off screen or beyond 18 m, on the cheap
  mesh and the slow animation tier.
- The spread between runs (8.1 and 11.0 at 28) is the machine, not the crowd: another agent's browser run shared the
  GPU for part of it. Read differences under 30% as noise, as the spike did.
- With Chrome's CPU throttled 4 times (`Emulation.setCPUThrottlingRate`, a rough stand-in for a weak laptop's
  processor, not its GPU) the empty lot already took 11 to 16 ms (to 39 in a noisy run) and 28 zombies 70 to 180 ms,
  40 zombies 150 to 200 ms. That is an upper bound of a poor model, but it says the web build has no headroom on a slow
  CPU at 28, let alone at 46: raising the ceiling is not supported.

## What it does not say

- It is one fast machine and one browser. A real weak laptop (integrated GPU, a thermally limited CPU) and Firefox are
  still not measured ([#105](https://github.com/Ryubara/deadnight/issues/105)); big rounds from the browser need the
  autopilot from the page ([#171](https://github.com/Ryubara/deadnight/issues/171)).
- Four players also draw three more soldiers; the build here has one.
- The crowd stood still around a walking player in the greybox's field: zombies at the breaches, queued at the boards.

## What changed

`RoundTuning.alive_cap_ceiling` (40, the same number as `ZombieTuning.hard_cap`, a test pins it) cuts the cap, so
four players ask for 40 from round 21 on instead of up to 46.

The balance report, rerun with the same seed and 300 nights a cell, once with the ceiling lifted
(`--set rounds.alive_cap_ceiling=1000`) and once with it in place, is **byte for byte the same**: every cell's median
and every round's pressure and death rate. The reason is in the cap's own arithmetic: four players pass 40 only from
round 22, and no simulated four-player night gets there (the strong cell, the best: 2 of 300 nights reach round 21, none
round 22; its median is 17). So the cells could not tell whether the cap or the count binds past 40 because nothing in
the model lives there; the ceiling is a rule about the web build, not a retune, and the gate's targets are untouched.

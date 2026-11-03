# Hit blood: splashes and marks on a zombie hit

Why a zombie that was hit showed no blood (#618), how the genre makes a hit read, what Deadnight did and what it costs.
The look and the numbers are in [Shot feedback](../design/shot-feedback.md#blood); the code is `BloodFx`.

## What was wrong

A hit on a zombie drew one dark-red puff 6 to 14 cm across for 0.22 s (`ImpactFx`, kind `FLESH`), nothing for a melee
blow but a spark, nothing for a grenade, and no mark anywhere. At the shoulder camera's distance the puff was a few
pixels, so the maintainer saw no blood at all.

## What the genre does (for design only, nothing copied)

- **Blood is information about the hit.** A spray at the wound the way the shot went, bigger for a bigger weapon and a
  much bigger one for a headshot, so the player reads "that was a head" without the number. The study of impact feel in
  action games ([What Features Influence Impact Feel?](https://arxiv.org/pdf/2208.06155)) lists on-hit effects as
  spot-pattern effects that mark where the hit landed, and says the severity of a hit is what they should carry.
- **Marks stay, to a limit.** A pool of decals with a count of those alive and one function that spawns them, the oldest
  recycled past the cap ([a shooter tutorial](https://kolosdev.com/shooter-tutorial-blood-splatters/), a Unity
article on
  [Ultrakill-style
decals](https://medium.com/@aldebaran38/how-to-make-blood-decals-like-ultrakill-in-unity-f9c89e7a61eb)
  with a cap of 100). Shorter lives are the other lever: a Dragon's Dogma 2 mod cut its blood decals to 45 s for
  performance. A per-hit rule that scales with the hit (a ground splat for a big hit, a spray behind the victim for a
  bigger one) is in [a Brute Force reimplementation's
notes](https://github.com/kduong-dev/brute-force-2003-reloaded/issues/150).
- **Readability has a ceiling.** Players complain when "the whole screen gets covered in red particles", so the splash
  is short (0.35 to 0.65 s), sits on the zombie, and the marks are on the world, never on the screen.

## What we did

| Choice | Why |
| --- | --- |
| A billboard quad and a shader for the splash, no `GPUParticles3D` | a particle system costs two programs of its own on the web ([first-use hitches](first-use-hitches.md#particle-systems-two-programs-of-their-own-and-a-sample-that-expires)); one unshaded quad shader is one program, drawn in the warm-up |
| The drops are drawn in the fragment shader from `progress` and a seed | the same splash in a test, a capture and every client; no per-frame allocation, nothing to pool but the quad |
| The shot's direction is turned into the camera's plane in `vertex()` and the cone opens to all round when the shot is straight away from the camera | from the shoulder camera most shots go straight away from it; a splash that only fans sideways would be a flat disc |
| `damage_dealt` carries `weapon_id` and `dir` | the view needs the weapon class and the way; no `NetWire` version change, events are dictionaries and clients ignore keys they do not know (the policy is in `net_wire.gd`). `NetWire.VERSION` stays 12 |
| Marks are found by the client's own rays (`WorldCast`) | a hit has no surface normal (a zombie is hit shapes); the ground and the wall are the client's own physics world, so nothing more travels |
| Marks are quads lifted 1 cm plus 2 mm a metre off the surface | a flat unshaded quad on a floor flickers in the depth buffer without the lift; no `Decal` node (it adds a light-like limit and a program per surface in Compatibility) |
| Two caps per platform: 64 marks on a desktop, 32 in the browser; 24 splashes | the numbers are tuning (`BloodTuning`); the measurement is below |

## Cost on the web

Desktop Chrome with an RTX 5080, the crowd bench of 20 zombies (`tools/web_smoke/blood_cost.py`,
`game/tests/captures/blood_cost_bench.tscn`): 80 hits a second (each of the 20 zombies nearest the camera is hit four
times a
second, a mix of SMG, shotgun, rifle and pistol hits, one in five a headshot), the pools full all the time (24
splashes and
32 marks alive, the worst case), frame limit lifted, a fresh browser each run, three runs interleaved, medians. Blood
off
means the same hits with no effect drawn.

| | Frame ms | p95 ms | Draw calls |
| --- | --- | --- | --- |
| blood off | 2.40 | 2.90 | 83.4 |
| blood on | 2.49 | 3.10 | 100.5 |

The same on a stand-in for a weak GPU (Chromium on SwiftShader, every pixel paid for, the processor slowed four
times, 150
frames, three runs interleaved):

| | Frame ms (median of 3) | Runs | Draw calls |
| --- | --- | --- | --- |
| blood off | 190 | 190, 190, 296 | 90.6 |
| blood on | 214 | 189, 214, 247 | 122.2 |

That is too noisy to fix a number (a 190 ms frame swings by 100 ms between runs), but the cost is not more than about 13
percent of a frame that is already 190 ms, with the pools full: the quad shader pays for its pixels. A normal fight
keeps far fewer than 24 splashes and 32 marks alive.

**No first-use hitch.** The real game's web build (`tools/web_smoke/first_use.py`, fresh profile, 30 s of play with
shooting, two runs): 239 programs linked in all and **0 in play**, the worst loading frame 2.6 s (the two blood
shaders are drawn in the warm-up, behind the loading screen).

So the cost is about 0.1 ms and 17 draw calls on that machine, and the browser console printed no error in any run.

## Things that did not work or are easy to get wrong

- A mark lying on a surface flickers without a lift that grows with the distance to the camera.
- A splash held in the warm-up has to stand still (`set_process(false)`): a frame that builds a program takes seconds
and
  would end a half-second splash before it is drawn.
- The first idea, a mark on the zombie itself, was dropped: a body is a skinned mesh with no decal support in
  Compatibility.

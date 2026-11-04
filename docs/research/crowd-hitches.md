# Hitches in the crowd's views

One page for the frames in which the drawn crowd changes in bulk, what each cost and what fixed it. Measured with
`game/tests/captures/cripple_hitch.tscn` (windowed, real time, vsync off, a loaded machine: read milliseconds as 1.5
to 2 times a quiet machine's).

## A blast that cripples a crowd (#932)

A walker whose legs a blast takes becomes a crawler: `ZombieHorde.apply_snapshot` sees the look change. It used to call
`ZombieView.dress` (free the model, instance the .glb, strip it, build a new `AnimationTree`); now `_redress` moves the
zombie to a parked view of the crawler look, as a spawn does, and parks the walker's body. The bench cripples 20 of 30
on a fresh horde twelve times (the warm-up's parked bodies in place) and records the call and the worst of the eight
frames after it.

| | call | worst frame (median of 12) | worst of all | steady frame |
| --- | ---: | ---: | ---: | ---: |
| before, run 1 | 40.3 ms | 44.1 ms | 50.1 ms | 1.25 ms |
| before, run 2 | 42.1 ms | 45.6 ms | 50.7 ms | 1.24 ms |
| after, run 1 | 0.61 ms | 3.4 ms | 5.5 ms | 1.22 ms |
| after, run 2 | 0.63 ms | 3.5 ms | 3.8 ms | 1.24 ms |

What the 0.6 ms call and the 3.4 ms frame still hold: 20 views set going (`setup`, `_restart`), 20 first poses, and the
first drawing of 20 crawler bodies that were hidden until then. Three things made up the rest of the cost on the way:

- **`load(path)` of the scene before looking in the pool**: about 1 ms a reuse (21 of the first 24 ms). The scene is
  only looked up when a view must be made. Every spawn from the pool paid it too (`horde.add_view`).
- **`tree.active = false` when parking and `true` when reusing** throws away the tree's resolved tracks, and the next
  advance rebuilds them: 2 ms for twenty in one frame. A parked tree stays active (it is advanced by hand, by the
  throttle only, and a parked view is not in it), and the warm-up advances each new body once.
- **Crawlers parked**: 20 kept (`ZombieHorde.PARKED_FOR_LOOK`) and 20 made by the warm-up (`NightWarmup.PARKED_BODIES`,
  it was 3). A blast that cripples more than the pool holds makes the rest in the frame, 0.4 ms each.

The cost of the 20 parked crawlers: 17 more bodies made behind the loading screen (about 7 ms at the 0.42 ms median the
review measured for a body) and 17 more hidden bodies in the tree, which cost no per-frame work (hidden, never advanced).

Kit page: `docs/godot/crowds.md` (a pooled body costs 1 ms to take if the pool still looks the scene up).

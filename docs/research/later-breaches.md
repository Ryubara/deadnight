# Boarded breaches for the later areas

Deadnight #849 (from the map review, #833). The dead of the midway, the yard, the back lot and the plaza used to rise
on bare ground at a fence; they now come in by boarded gaps like the field's six. What the design is lives in
[the map page](../design/map.md#the-later-areas-breaches-849); this page is what was measured while building it.

## What the review found, and why

By the lot's own report the share of the spawn pool at the field's breaches fell from 100 % to 35 % as the doors
opened, and the other 17 points were "bare ground at a fence", 20 to 91 m from any breach, nothing opening, nothing torn
and nothing lit (captures in the pull request). The map page had written that on purpose ("a spawn inside an area has
nothing to tear"): the closing-in rule was designed for the pool, and nobody asked what a player sees there. The
maintainer's decision (2026-11-03): more walls with boards around the map, each later area's dead come through boarded
breaches in walls, and where an area has only a fence it gets a wall section with a breach.

## What was built

| Area | Breaches | How |
| --- | --- | --- |
| Midway | `mid_w`, `mid_e` | no outer wall to cut, so a bay in each south corner: a 7 m wall across the corner at z 33, a 4 m gap, the court's fence and the plaza's closing the other sides; the spawn is 3.5 m behind the boards |
| Yard | `yard_e1`, `yard_e2`, `yard_s` | gaps in the east wall (z 6, 30) and the south wall (x 36), the field's apron behind each |
| Back lot | `back_w1`, `back_w2`, `back_s` | the same on the west wall (z 10, 34) and the south wall (x -36) |
| Plaza | `plaza_w`, `plaza_e` | gaps in the side walls at z 49.5; two of its three spawn points share the west apron |

- The generator's `breach()` takes an inward direction, an id and a wall material, so the field's and the later ones
  are one function; `pocket()` is the midway's. The positions are tables (`YARD_BREACHES`, `BACK_BREACHES`,
  `PLAZA_BREACHES`, `MIDWAY_POCKETS`) at the top of `tools/world/build_greybox.py`.
- Ten more ids in `BarricadeTuning` and the shared table: 16 breaches in all, the same five boards, tearing and mending.
  Every spawn point carries the `barricade_id` it lies behind (`NightWorld.spawn_gates`), so the dead rise there and
  stop short of the boards; `NightWorld._walkable` walks from the spawn to the inside of the boards before an area's
  points join the pool.
- Where a gap was placed it was checked against the props: six dressing props moved (`lot_props.py`): the midway's tires,
  pipes and pallets stood on the bays' walls or across their gaps, and the pipes' new place is away from the container
  beside the booth so the move made no new step up.
- Not touched: the plaza's end wall (the walking-mesh test pins nothing past it), the midway's west fence, the plaza's
  south-west corner ([#845](https://github.com/Ryubara/deadnight/issues/845), [#846](https://github.com/Ryubara/deadnight/issues/846))
  and every lamp ([#850](https://github.com/Ryubara/deadnight/issues/850), [#851](https://github.com/Ryubara/deadnight/issues/851)).
  The new breaches are dark like the field's were before the apron lamps; lighting them is those issues' call.

## Numbers

- **Spawn audit** (`tools/world/map_audit.gd`, from the map-review branch): 17 points, none inside a solid, none in view
  of the start, 3.5 to 4.3 m behind their boards; nearest lamp (`lot_report.gd`) 1.6 and 6.1 m (midway), 18 to
  22 (yard), 14 to 19 (back lot), 10 to 16 (plaza). The counts per area (6, 2, 3, 3, 3) and so the pool shares are unchanged
  (`test_later_breaches.gd`).
- **Escape sweep** (`tools/world/map_escape_probe.gd`, the real body, 1.5 m launch cells, depth 3, all doors sold): 84,280
  hops and 4,306 standing places on this branch against 83,295 and 4,283 on the map-review branch it started from. The
  one `beyond_the_map` standing place is the same on both, the plaza's south-west corner at (-19.5, 61.5), the
  known way out of #845; no new one. With only the concession sold (the midway's bays reachable): 66,735 hops against
  65,965, no `beyond_the_map` or `high`. The probe's `inside_a_closed_area` kind flags the top of any prop the body can
  stand on (about 2,700 on both sides) and is not a clean signal on its own: compare per region, and the new regions were
  props that had moved.
- **Draw calls** (a camera at each of 49 spots of the map-review tour, 12 frames of waiting, the median of five reads;
  [lesson](https://github.com/Ryubara/gdstudio/pull/419)):

  | | Mean | Median | Worst spot |
  | --- | ---: | ---: | ---: |
  | Before | 326.1 | 227 | 1101 |
  | The breaches, everything drawn | 357.4 | 259 | 1157 |
  | With the aprons hidden past 35 m and the boards past 45 m | 339.9 | 239 | 1109 |

  The new geometry is 44 CSG boxes and 50 boards, and there is no occlusion culling, so a wall across the lot costs a
  call from every spot that faces it. The aprons are behind the perimeter wall and show only through a torn gap, so
  `visibility_range_end` hides them past 35 m (the generator's `range_end`), and the boards past 45 m
  (`metadata/board_view_end`, read by `Barricade`). The field's aprons and boards are as they were: +13.8 draws on
  average (+4 %), +8 at the worst spot.
- **Pooled torn boards.** A `Barricade` made its drawn copies of torn boards the first time a board came off, a node
  entering the tree in the middle of a fight; with dead tearing in the midway `test_kill_allocations.gd` saw six such
  nodes in 14 kills. The pool of five copies is now made when the breach is built (80 hidden empty meshes for 16
  breaches).

## Where the dead tear boards now

The dead of a later area stand behind five boards for about six seconds (1.2 s a board, faster for the quick types)
before they come in, as the field's do. A solo player who has bought the concession now has the midway's dead held for
that long too: the opening arrival is later, not more numerous. The rules' pace, counts and spawn rolls are not
changed.

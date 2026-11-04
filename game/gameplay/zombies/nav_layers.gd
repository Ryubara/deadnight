class_name NavLayers
extends RefCounted
## The navigation layers of the lot's one map. The mesh is the dead's: it runs through every gap the
## boards of a barricade shut to a person. The polygons across a barricade and the pieces too small
## to walk (`NavmeshSplit`) are a region of their own on a layer only the dead ask for, so a path
## for a body that boards stop (`WALK`: a person, a bot, a stand-in) never runs through one or
## starts on one, and a path for the dead (`DEAD`) does. `WALK` is the engine's default layer, so a
## path asked without one is a person's, and a region made without one (a test's arena) is walkable.

## The layer of the whole mesh but for the gaps (the engine's default layer, 1).
const WALK := 1
## The layer of the polygons across a barricade and the pieces too small to walk.
const GAP := 2
## The dead walk both.
const DEAD := WALK | GAP

class_name SeparationGrid
extends RefCounted
## The spatial grid of the zombies' separation pass, built every sim step without making anything
## (the old one made an `Array` for each occupied cell and a hash node for it, 30 times a second,
## #933). Its arrays are packed, sized once for the biggest crowd seen and reused; the cells are a
## sort, not a table: every standing zombie is one `int` (its cell and its place in `bodies`) in a
## list sorted by the engine, so the zombies of three neighbouring cells of a row are one run of
## the list that a binary search finds.
##
## The standing zombies (not the dying) are `bodies[0 .. count - 1]`, in the order of the crowd's
## dictionary. A cell is a square of `radius` metres, keyed `cx * CELL_STRIDE + cz`, so the keys of
## the cells beside it are the key plus `dx * CELL_STRIDE + dz`. `places` holds, ascending, the
## `key * INDEX_SPAN + body index` of every body (and the sentinel after them): bodies of one cell
## are together, in the order of `bodies`, and the cell of `key` follows the cell of `key - 1`.
## So the nine cells a zombie reads, in the order x then z, are three runs, one for each `dx`.

## Odd, and wider than twice the cells on a side of any map. A neighbour's key is the key plus
## `dx * CELL_STRIDE + dz`.
const CELL_STRIDE := 1048573
## Room in a place for the index of a body; a crowd past it is not separated past its first
## `INDEX_SPAN - 1` (the cap of the game is far below).
const INDEX_SPAN := 65536
const INDEX_MASK := INDEX_SPAN - 1
## After the last body in `places`, bigger than any real one, so a run ends without a bounds test.
const END := 0x7FFFFFFFFFFFFFFF
const MIN_CAPACITY := 64

## How many standing zombies the last `rebuild` found.
var count: int = 0
var bodies: Array[ZombieBody] = []
## Each body's cell key.
var cell_of := PackedInt64Array()
## Each body's place in `places`.
var place_of := PackedInt32Array()
var places := PackedInt64Array()
## Where each place's body stood when the pass began, kept up to date by `moved`: a neighbour's
## distance is read from here, in the order the list is read, not through an object.
var at := PackedVector3Array()

var _capacity: int = 0


## Sorts the standing zombies of `zombies` (id to `ZombieBody`) into cells of `radius` metres.
func rebuild(zombies: Dictionary, radius: float) -> void:
	if zombies.size() > _capacity:
		_grow(zombies.size())
	var found := 0
	for id: int in zombies:
		var zombie: ZombieBody = zombies[id]
		if not zombie.is_alive():
			continue
		var position := zombie.position
		var key := floori(position.x / radius) * CELL_STRIDE + floori(position.z / radius)
		bodies[found] = zombie
		cell_of[found] = key
		places[found] = key * INDEX_SPAN + found
		found += 1
		if found == INDEX_MASK:
			break
	# The places the last pass filled that this one does not: nobody stands there now, and the
	# dead and the removed must not be held by the stale tail.
	for i in range(found, count):
		bodies[i] = null
		places[i] = END
	count = found
	places.sort()
	for place in found:
		var body_index := places[place] & INDEX_MASK
		place_of[body_index] = place
		at[place] = bodies[body_index].position


## The first place whose entry is `key * INDEX_SPAN` or more: where the run of cell `key` begins.
func first_of(key: int) -> int:
	return places.bsearch(key * INDEX_SPAN)


## Body `body_index` now stands at `position` (the pass pushed it).
func moved(body_index: int, position: Vector3) -> void:
	at[place_of[body_index]] = position


## Room for `needed` zombies: the next power of two. Only a crowd bigger than any before comes
## here, so a crowd that stays within its size makes nothing.
func _grow(needed: int) -> void:
	_capacity = maxi(MIN_CAPACITY, nearest_po2(needed))
	bodies.resize(_capacity)
	cell_of.resize(_capacity)
	place_of.resize(_capacity)
	at.resize(_capacity)
	var old := places.size()
	places.resize(_capacity + 1)
	for i in range(old - 1 if old > 0 else 0, _capacity + 1):
		places[i] = END

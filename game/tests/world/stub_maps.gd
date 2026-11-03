class_name StubMaps
extends RefCounted
## A second map for the suites of the map choice: the drive-in lot's own layout under another id,
## carrying one marker node (`MARKER`) a test looks for to tell which scene a night was built from.
## `install` puts the real list plus the stub into `MapRegistry`; `remove` puts the real one back.

const ID := "stub_lot"
const SCENE := "res://tests/world/stub_map.tscn"
const MARKER := "StubMarker"
## A map that is listed and not built, for the suites of the locked card (the second map ships, so
## it is no longer the one that stays locked).
const LOCKED_ID := "stub_locked"


static func stub(shipped := true) -> MapInfo:
	var info := MapInfo.new()
	info.id = ID
	info.title = "Stub lot"
	info.blurb = "A map for the tests."
	info.scene_path = SCENE
	info.area_m2 = 900
	info.min_players = 2
	info.max_players = 3
	info.shipped = shipped
	return info


## A listed map that is not built: no scene, not shipped.
static func locked_stub() -> MapInfo:
	var info := MapInfo.new()
	info.id = LOCKED_ID
	info.title = "Locked stub"
	info.blurb = "A map that is not built."
	info.area_m2 = 600
	info.min_players = 1
	info.max_players = 4
	info.shipped = false
	return info


## The lot, a locked map and the stub, in that order, in `MapRegistry` (the picker's own suite: the
## real second map is playable now, so it has a suite of its own).
static func install_picker_set() -> MapInfo:
	MapRegistry.reset()
	var list: Array[MapInfo] = [MapRegistry.find(MapRegistry.DEFAULT), locked_stub()]
	var extra := stub(true)
	list.append(extra)
	MapRegistry.use(list)
	return extra


## The real maps and the stub, in `MapRegistry`.
static func install(shipped := true) -> MapInfo:
	MapRegistry.reset()
	var list: Array[MapInfo] = []
	list.append_array(MapRegistry.all())
	var extra := stub(shipped)
	list.append(extra)
	MapRegistry.use(list)
	return extra


static func remove() -> void:
	MapRegistry.reset()


## Whether the world was built from the stub's scene.
static func built_from_stub(world: NightWorld) -> bool:
	return world.greybox != null and world.greybox.get_node_or_null(MARKER) != null

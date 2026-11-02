class_name LotBotData
extends RefCounted
## What a bot is given of the lot beside its walking mesh and the two questions its eyes answer
## (`BotLevel`): where it falls back to, where the dead break in, the lot's loops for kiting
## (`docs/design/map.md#loops-for-kiting`) and the places a jump is a way. Read from the built lot.

## Metres from the walls of the generator cage or the booth that a loop for kiting runs.
const LOOP_MARGIN := 3.0


## Fills `level` from `world`.
static func fill(level: BotLevel, world: NightWorld) -> void:
	level.home = Autopilot.HOME
	level.breaches = world.repair_points()
	level.loops = loops(world.greybox)
	level.links = links(world.greybox)


## The loops as closed rings on the ground: round the generator cage (about 50 m) and round the
## projection booth (about 85 m). A ring is the rectangle `LOOP_MARGIN` metres outside the walls of
## the cage or the booth's floor, so a bot that follows it keeps clear of both.
static func loops(greybox: Node3D) -> Array[PackedVector3Array]:
	var rings: Array[PackedVector3Array] = []
	for part: Array in [["GeneratorYard", "Cage"], ["ProjectionBooth", "Floor"]]:
		var ring := _ring_round(greybox, part[0], part[1])
		if not ring.is_empty():
			rings.append(ring)
	return rings


## The places a bot may jump on purpose: pairs of `Marker3D` under `BotLinks` named `<name>From` and
## `<name>To`. The lot has none yet (a jump is a way out of a trap, which is the plan's phase 5).
static func links(greybox: Node3D) -> Array[BotLink]:
	var found: Array[BotLink] = []
	var group := greybox.get_node_or_null("BotLinks")
	if group == null:
		return found
	for marker in group.get_children():
		if String(marker.name).ends_with("From"):
			var other := group.get_node_or_null(String(marker.name).trim_suffix("From") + "To")
			if other != null:
				found.append(
					BotLink.new(
						(marker as Node3D).global_position, (other as Node3D).global_position
					)
				)
	return found


## A rectangle ring round the walls of `area` whose names start with `prefix`, or empty.
static func _ring_round(greybox: Node3D, area: String, prefix: String) -> PackedVector3Array:
	var node := greybox.get_node_or_null(area)
	if node == null:
		return PackedVector3Array()
	var box := Rect2()
	var found := false
	for child in node.get_children():
		if child is CSGBox3D and String(child.name).begins_with(prefix):
			var part := child as CSGBox3D
			var at := part.global_position
			var rect := Rect2(
				at.x - part.size.x * 0.5, at.z - part.size.z * 0.5, part.size.x, part.size.z
			)
			box = rect if not found else box.merge(rect)
			found = true
	if not found:
		return PackedVector3Array()
	box = box.grow(LOOP_MARGIN)
	return PackedVector3Array(
		[
			Vector3(box.position.x, 0.0, box.position.y),
			Vector3(box.end.x, 0.0, box.position.y),
			Vector3(box.end.x, 0.0, box.end.y),
			Vector3(box.position.x, 0.0, box.end.y),
		]
	)

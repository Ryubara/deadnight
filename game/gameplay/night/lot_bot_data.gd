class_name LotBotData
extends RefCounted
## What a bot is given of the lot beside its walking mesh and the two questions its eyes answer
## (`BotLevel`): where it falls back to, where the dead break in, the lot's loops for kiting
## (`docs/design/map.md#loops-for-kiting`) and the places a jump is a way. Read from the built lot.

## Metres from the walls of the generator cage or the booth that a loop for kiting runs.
const LOOP_MARGIN := 3.0
## Metres apart that two places a bot may roam to are at the least.
const ROAM_SPACING := 5.0


## Fills `level` from `world`. With the rules' `tuning` the bots also get the shop (`shop`): a level
## made without it is one whose bots do no errands (the suites that measure the fight alone).
static func fill(level: BotLevel, world: NightWorld, tuning: RulesTuning = null) -> void:
	# What a body is stopped by: the walls, and the boards across a breach (a shot goes through them).
	level.walk_probe = WorldProbe.new(
		world.get_world_3d().direct_space_state, WorldProbe.WORLD_MASK | Barricade.BOARD_LAYER
	)
	level.walk = (level.walk_probe as WorldProbe).static_callable()
	level.home = Autopilot.HOME
	level.breaches = world.repair_points()
	level.loops = loops(world.greybox)
	level.links = links(world.greybox)
	level.roam_spots = roam_spots(world)
	level.mark_last = ZombieTuning.shipped().mark_last
	if tuning != null:
		level.shop = shop(world, tuning)


## What a bot is given of the shop, the breaches, the breaker posts and the fuel crates: the rules'
## tables and where to stand at each of them.
static func shop(world: NightWorld, tuning: RulesTuning) -> BotShop:
	var found := BotShop.new()
	found.economy = tuning.economy
	found.fuel = tuning.fuel
	found.boards = tuning.barricades.boards
	found.max_grenades = tuning.explosives.max_grenades
	var overlay := world.layout.map_tuning() if world.layout != null else null
	if overlay != null:
		found.clear_from = overlay.bot_clear_from
		found.calm_share = overlay.bot_calm_share
		found.hurt_share = overlay.bot_hurt_share
		found.team_links = overlay.bot_team_links
		found.shopping.assign(overlay.bot_shopping)
	var night_tuning := NightTuning.shipped()
	found.use_reach = night_tuning.use_reach
	found.fuel_reach = night_tuning.fuel_reach
	found.lamp_reach = LightTuning.current().lamp_reach
	for item in tuning.economy.items:
		match item.kind:
			ShopItem.Kind.DOOR:
				if world.door_ids().has(item.id) and not world.door_stands(item.id).is_empty():
					found.doors.append(item.id)
					found.door_stands[item.id] = world.door_stands(item.id)
			ShopItem.Kind.FUEL:
				found.fuel_item = item
	found.spots = world.shop_spots()
	for id in world.barricade_ids():
		found.repair_stands[id] = world.repair_spot(id)
		found.repair_centres[id] = world.barricade(id).centre()
	for circuit_id in world.switches.circuit_ids():
		found.circuit_stands[circuit_id] = world.switches.standing_point(circuit_id)
		found.circuit_doors[circuit_id] = world.switches.door_of(circuit_id)
	var lamps := world.lamp_points()
	for circuit_id: StringName in lamps:
		found.circuit_lamps[circuit_id] = lamps[circuit_id]
	for id in world.fuel.ids():
		found.fuel_stands[id] = world.fuel.standing_point(id)
		found.fuel_doors[id] = world.fuel.door_of(id)
	return found


## The places a roaming bot goes: the shop's spots, the breach stands, the doors' stands, the
## breaker posts and the fuel crates, ground the walking mesh has (a spot is put on it), no two
## less than `ROAM_SPACING` apart.
static func roam_spots(world: NightWorld) -> Array[Vector3]:
	var wanted: Array[Vector3] = []
	for spot in world.shop_spots():
		wanted.append(spot["position"])
	for id in world.barricade_ids():
		wanted.append(world.repair_spot(id))
	for door_id in world.door_ids():
		wanted.append_array(world.door_stands(door_id))
	for circuit_id in world.switches.circuit_ids():
		wanted.append(world.switches.standing_point(circuit_id))
	for id in world.fuel.ids():
		wanted.append(world.fuel.standing_point(id))
	var found: Array[Vector3] = []
	# A question put to a map before its first mesh is in prints an error: with none yet, the points
	# are taken as the lot gives them (the walk to one that is off the mesh is snapped later).
	var meshed := (
		world.map().is_valid() and NavigationServer3D.map_get_iteration_id(world.map()) > 0
	)
	for point in wanted:
		var on_mesh := (
			NavigationServer3D.map_get_closest_point(world.map(), point) if meshed else point
		)
		var taken := false
		for other in found:
			if Vector2(other.x - on_mesh.x, other.z - on_mesh.z).length() < ROAM_SPACING:
				taken = true
				break
		if not taken:
			found.append(on_mesh)
	return found


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

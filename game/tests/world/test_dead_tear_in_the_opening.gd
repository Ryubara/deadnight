extends GdUnitTestSuite
## A dead that tears a window's boards stands in front of the opening, where a person inside can
## shoot it (#997). On the second map's `upper_b2` the dead stood in front of a jamb (the gate
## spanned the whole gap and then some), tore from there, and a person inside had the jamb between
## them and it: the boards stood at 5 for 190 s while the round waited.
##
## On both maps, at every window and every breach, a crowd of dead comes from all across the
## field to boards that stand, and on every tick that one is tearing (`ZombieBody.tearing`) it is
## asked where it stands along the wall and whether a shot from inside reaches it: from the repair
## spot, from close to the window, from beside it and from the room's depth, at its chest and at
## its head, through the world's own solids (jambs, sill, lintel) and the fitted hit zones of its
## tearing pose (`Hitbox.ray_at`, what the server's trace uses).

const LOT := "res://world/drive_in_greybox.tscn"
const SMALL := "res://world/smallmap/smallmap_greybox.tscn"
## Metres out from the barricade the dead start, and how far apart along the wall.
const START_OUT := 5.0
const START_SIDES: Array[float] = [-2.4, -1.2, -0.4, 0.4, 1.2, 2.4]
## Where a person inside stands, as (metres in from the barricade, metres along the wall): the
## repair spot (`NightWorld.REPAIR_SPOT`) is the first.
const VIEWS: Array[Vector2] = [
	Vector2(1.4, 0.0), Vector2(0.9, 0.0), Vector2(1.4, 0.4), Vector2(1.4, -0.4), Vector2(2.6, 0.0)
]
const EYE_HEIGHT := 1.55
## What is aimed at, on the dead (m above its feet): its chest and its head.
const AIMS: Array[float] = [1.1, 1.62]
## Seconds the crowd works the boards; the check starts at the first second.
const SECONDS := 14.0
const STAND_IN := 3.6
## The crowd's ids: the night's own dead have lower ones.
const FIRST_ID := 900
const WORLD_SLACK := 0.05

var _seated: SeatedNight
var _probe: WorldProbe


func after_test() -> void:
	if _seated != null:
		_seated.dispose()
		_seated = null


func _start(path: String) -> void:
	var tuning := RulesFixture.tuning()
	tuning.health.max_health = 1000000.0
	_seated = await SeatedNight.start(self, 1, tuning, 5, false, load(path) as PackedScene)
	for item in _seated.server.rules.tuning.economy.items:
		if item.kind == ShopItem.Kind.DOOR:
			_seated.open_door(item.id)
	await _seated.settle(30)
	_probe = WorldProbe.new(_seated.world.get_world_3d().direct_space_state)


## One barricade, boards up all through: "" when every tearing dead stood in the opening and every
## shot reached it, else what went wrong.
func _crowd_at(id: StringName) -> String:
	var world := _seated.world
	var barricade := world.barricade(id)
	var sim := _seated.server.sim
	var rules := _seated.server.rules
	barricade.set_boards(barricade.capacity(), false)
	sim.zombies.clear()
	var across := barricade.inward().cross(Vector3.UP)
	var floor_y := barricade.global_position.y
	var stand := barricade.centre() + barricade.inward() * STAND_IN
	_seated.server.body_of(1).teleport(Vector3(stand.x, floor_y + 0.1, stand.z))
	var next_id := FIRST_ID
	for side in START_SIDES:
		var start := barricade.centre() - barricade.inward() * START_OUT + across * side
		start.y = floor_y
		var zombie := sim.spawn(next_id, 2.0 + 0.5 * (next_id % 3), start, 0.0, null, id)
		zombie.enter(ZombieBody.Mode.CHASE)
		next_id += 1
	var tearing_ticks := 0
	var widest := 0.0
	for tick in int(SECONDS / ZombieSim.STEP):
		rules.barricades.boards[id] = barricade.capacity()
		_seated.tick()
		if tick % 30 == 0:
			await get_tree().physics_frame
		for zombie: ZombieBody in sim.zombies.values():
			# The night's own dead come to other breaches: only this crowd is judged.
			if zombie.id < FIRST_ID or not zombie.tearing:
				continue
			tearing_ticks += 1
			var along := (zombie.position - barricade.centre()).dot(across)
			widest = maxf(widest, absf(along))
			var report := _can_be_shot(barricade, zombie)
			if not report.is_empty():
				return (
					"%s: a dead tearing at %+.2f m along (opening %.2f) %s"
					% [id, along, barricade.clear_half, report]
				)
	if tearing_ticks == 0:
		return "%s: nobody tore the boards in %.0f s" % [id, SECONDS]
	return ""


## "" when every view reaches `zombie` at every aim point, else the view that did not.
func _can_be_shot(barricade: Barricade, zombie: ZombieBody) -> String:
	var across := barricade.inward().cross(Vector3.UP)
	var target := zombie.hit_target()
	for view in VIEWS:
		var eye := (
			barricade.centre()
			+ barricade.inward() * view.x
			+ across * view.y
			+ Vector3(0.0, EYE_HEIGHT, 0.0)
		)
		for aim_height in AIMS:
			var aim := zombie.position + Vector3(0.0, aim_height, 0.0)
			var distance := eye.distance_to(aim)
			var toward := (aim - eye) / distance
			var blocked := _probe.distance(eye, aim)
			if blocked >= 0.0 and blocked < distance - WORLD_SLACK:
				return (
					"is behind a solid from %.1f m in, %+.1f m along, at %.2f m up (%.2f of %.2f m)"
					% [view.x, view.y, aim_height, blocked, distance]
				)
			if Hitbox.ray_at(eye, toward, distance + 1.0, target).is_empty():
				return (
					"is missed from %.1f m in, %+.1f m along, at %.2f m up"
					% [view.x, view.y, aim_height]
				)
	return ""


func _every_barricade(path: String) -> void:
	await _start(path)
	var checked := 0
	for id in _seated.world.barricade_ids():
		var report := await _crowd_at(id)
		assert_str(report).override_failure_message(report).is_empty()
		checked += 1
	assert_int(checked).is_equal(_seated.world.barricade_ids().size())
	assert_int(checked).is_greater(5)


func test_a_dead_tearing_at_a_drive_in_breach_stands_in_its_opening_and_can_be_shot() -> void:
	await _every_barricade(LOT)


func test_a_dead_tearing_at_a_second_map_window_stands_in_its_opening_and_can_be_shot() -> void:
	await _every_barricade(SMALL)

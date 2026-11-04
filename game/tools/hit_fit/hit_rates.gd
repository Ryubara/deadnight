extends SceneTree
## Prints how often a shot that touches a zombie's visible mesh registers, per body and pose: a
## ray grid over the skinned mesh (`ZombieMeshProbe`, `ZombieRayGrid`) shot through the weapons'
## trace (`AimResolver.trace_one`, what the combat server calls), and the forehead shots of a
## crawler through a whole `CombatServer`. Run before and after a change to the zones:
##   godot --headless --path game -s res://tools/hit_fit/hit_rates.gd
## It builds each target the way the night does (`ZombieBody.hit_target`) when the zombie has
## that, and by its profile's hit scale on the older code that has not.

const SPACING := 0.08
const CRAWL_TIMES: Array[float] = [0.0, 0.42, 0.83, 1.25]
const SHOOTER := Vector3(0.0, 1.55, 6.0)

## Body, mode, clip, times and (when it runs) speed of each row of the first table.
const ROWS := [
	[&"crawler", ZombieBody.Mode.CHASE, &"Crawl", CRAWL_TIMES],
	[&"crawler", ZombieBody.Mode.ATTACK, &"extra/Crawl_Attack", [0.1, 0.3, 0.54, 0.8]],
	[&"walker", ZombieBody.Mode.CHASE, &"Idle", [0.5]],
	[&"walker", ZombieBody.Mode.CHASE, &"Walk", [0.0, 0.67]],
	[&"walker", ZombieBody.Mode.CHASE, &"Run", [0.17, 0.5], 3.5],
	[&"walker", ZombieBody.Mode.ATTACK, &"Punch", [0.35]],
	[&"walker", ZombieBody.Mode.STAGGER, &"HitReact", [0.3]],
	[&"brute", ZombieBody.Mode.CHASE, &"Walk", [0.33]],
	[&"headliner", ZombieBody.Mode.CHASE, &"Boss_Walk", [0.4, 1.0]],
]

var _def: WeaponDef = WeaponCatalog.get_def(&"pistol")


func _initialize() -> void:
	await process_frame
	print("shots that touch the mesh, by what the weapons' trace registers")
	for row: Array in ROWS:
		_row(row)
	_forehead()
	quit()


func _body(look: StringName, mode: int, speed: float = 0.0) -> ZombieBody:
	var body := ZombieBody.new()
	body.id = 1
	var profile := ZombieProfile.new()
	profile.look = look
	profile.type = look
	profile.hit_chance = 0.6 if look == &"crawler" else 1.0
	profile.boss = ZombieModels.is_boss(look)
	profile.weak = profile.boss
	body.profile = profile
	body.mode = mode as ZombieBody.Mode
	body.move_speed = speed
	return body


func _target(body: ZombieBody) -> Dictionary:
	if body.has_method(&"hit_target"):
		return body.call(&"hit_target")
	return {"id": 1, "pos": Vector3.ZERO, "yaw": 0.0, "scale": body.profile.hit_scale()}


func _shooter(target: Dictionary) -> Callable:
	var targets := {1: target}
	var def := _def
	return func(origin: Vector3, dir: Vector3) -> StringName:
		var shot := AimResolver.trace_one(def, origin, dir, origin, targets, Callable())
		var hits: Array = shot["hits"]
		return hits[0]["zone"] if not hits.is_empty() else &""


func _row(row: Array) -> void:
	var look: StringName = row[0]
	var probe := ZombieMeshProbe.make(root, look)
	probe.use_extra_clips()
	var body := _body(look, row[1], row[4] if row.size() > 4 else 0.0)
	var target := _target(body)
	var touched := 0
	var registered := 0
	var head_touched := 0
	var head_registered := 0
	var head_own := 0
	var stray := 0
	var landed := 0
	for time: float in row[3]:
		probe.pose(row[2], time)
		var grid := ZombieRayGrid.new()
		grid.elevations = [0.0, 25.0]
		grid.run(probe, _shooter(target), SPACING)
		var head := ZombieMeshProbe.Part.HEAD
		touched += grid.touched_count()
		registered += _count(grid.registered)
		head_touched += grid.touched_count(head)
		head_registered += grid.registered[head]
		head_own += grid.matched[head]
		stray += grid.spurious
		landed += grid.spurious + _count(grid.registered)
	print(
		(
			"  %-10s %-9s all %5.1f%% | head %5.1f%% (as head %5.1f%%) | registered off the mesh %4.1f%%"
			% [
				look,
				row[2],
				100.0 * float(registered) / float(touched),
				100.0 * float(head_registered) / float(head_touched),
				100.0 * float(head_own) / float(head_touched),
				100.0 * float(stray) / float(maxi(landed, 1)),
			]
		)
	)
	probe.free_model()


func _count(counts: Array) -> int:
	return counts[0] + counts[1] + counts[2] + counts[3]


## Forehead shots at a crawler, each through a whole combat server of its own.
func _forehead() -> void:
	var probe := ZombieMeshProbe.make(root, &"crawler")
	var body := _body(&"crawler", ZombieBody.Mode.CHASE)
	var target := _target(body)
	var shots := 0
	var landed := 0
	var headshots := 0
	for time in CRAWL_TIMES:
		probe.pose(&"Crawl", time)
		var forehead := probe.forehead(12)
		for index in range(0, forehead.size(), maxi(forehead.size() / 3, 1)):
			var point := forehead[index]
			var seen := probe.ray(SHOOTER, (point - SHOOTER).normalized())
			if seen.is_empty() or seen["part"] != ZombieMeshProbe.Part.HEAD:
				continue
			var server := WeaponsFixture.make_server()
			server.apply(CombatAction.give_weapon(1, &"pistol"))
			server.apply(CombatAction.targets([target]))
			server.apply(CombatAction.tick(WeaponsFixture.STEP))
			var events := server.apply(WeaponsFixture.fire_at(1, 1, SHOOTER, point, server.now))
			shots += 1
			for event in WeaponsFixture.of(events, &"damage_dealt"):
				landed += 1
				if event["headshot"]:
					headshots += 1
	print("forehead shots through a whole combat server, at a crawler in four frames of its crawl")
	print(
		(
			"  %d shots: %d did damage (%.0f%%), %d were headshots (%.0f%%)"
			% [
				shots,
				landed,
				100.0 * float(landed) / float(maxi(shots, 1)),
				headshots,
				100.0 * float(headshots) / float(maxi(shots, 1)),
			]
		)
	)
	probe.free_model()

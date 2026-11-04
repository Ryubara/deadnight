extends SceneTree
## What a melee blow really does in the night (#924, after #897): for the quick melee, the crowbar,
## the bat and the axe, a blow from the player's eye (the real sweep, the fitted hit zones, the
## combat server and the rules' health for the round) at a walker standing 0.7, 1.1 and 1.5 m
## ahead (walking up, or striking), aimed at its head, chest and legs: the aim is the crosshair on
## that point, which in the third-person view is a ray from the camera pivot (1.6 m up) through it,
## and the blow sweeps along that direction from the eye. It prints a line for each blow
## (`BLOW <weapon> r<round> <pose> <reach> <aim> zone=<zone> damage=<n> left=<health>`) and a line
## for each weapon and round with the blows it takes (`HITS <weapon> r<round> <n>`). Not part of
## the game. Run with `godot --headless --path game -s res://tests/captures/melee_zone_probe.gd`.

const WEAPONS: Array[StringName] = [&"quick_melee", &"crowbar", &"baseball_bat", &"fire_axe"]
const ROUNDS: Array[int] = [1, 2, 3, 4, 6, 8, 10]
const REACH: Array[float] = [0.7, 1.1, 1.5]
const AIMED: Dictionary = {"head": 1.62, "chest": 1.1, "legs": 0.5}
## The camera pivot's height: the crosshair ray runs from it through the point aimed at.
const PIVOT := 1.6
const POSES: Array[StringName] = [ZombiePose.MOVE, ZombiePose.STRIKE]
const WAIT_STEPS := 70

var _eye := Vector3.ZERO


func _initialize() -> void:
	_eye = Vector3(0.0, NightTuning.new().eye_height, 0.0)
	print("EYE %.2f" % _eye.y)
	for weapon in WEAPONS:
		for round_number in ROUNDS:
			for reach in REACH:
				for pose in POSES:
					for aim: String in AIMED:
						_one_blow(weapon, round_number, reach, aim, pose)
			_hits_to_kill(weapon, round_number)
	quit()


func _walker_in(round_number: int) -> Array:
	var tuning := RulesFixture.tuning()
	tuning.specials.every = 0
	var rules := RulesFixture.make_rules(1, 1234, tuning)
	var server := WeaponsFixture.make_server(rules)
	rules.round_number = round_number - 1
	RulesFixture.into_round_one(rules)
	RulesFixture.run(rules, 40.0)
	var walker := -1
	for id in rules.zombie_ids():
		if walker < 0 and rules.zombie_type(id) == &"walker":
			walker = id
		else:
			RulesFixture.kill(rules, 1, id)
	return [server, walker]


## One swing of `weapon` in hand, as the night's `_shoot` sends it: from the eye.
func _swing(server: CombatServer, weapon: StringName, seq: int, dir: Vector3) -> Array[Dictionary]:
	if weapon == &"quick_melee":
		return server.apply(CombatAction.quick_melee(1, seq, _eye, dir, _eye, server.now))
	return server.apply(CombatAction.fire(1, seq, _eye, dir, _eye, server.now))


func _take(server: CombatServer, weapon: StringName) -> void:
	if weapon != &"quick_melee":
		server.apply(CombatAction.give_weapon(1, weapon, weapon))


## Where every target stands, as the night sends it: facing the player, in the pose's hit set.
func _place(server: CombatServer, walker: int, feet: Vector3, pose: StringName, steps: int) -> void:
	var set_id := StringName("%s.%s" % [ZombiePose.body_of(ZombieModels.DEFAULT), pose])
	for _i in steps:
		server.apply(
			CombatAction.targets([{"id": walker, "pos": feet, "yaw": 0.0, "pose": set_id}])
		)
		server.apply(CombatAction.tick(WeaponsFixture.STEP))


func _aim_dir(feet: Vector3, height: float) -> Vector3:
	return (feet + Vector3(0.0, height, 0.0) - Vector3(0.0, PIVOT, 0.0)).normalized()


func _one_blow(
	weapon: StringName, round_number: int, reach: float, aim: String, pose: StringName
) -> void:
	var made := _walker_in(round_number)
	var server: CombatServer = made[0]
	var walker: int = made[1]
	_take(server, weapon)
	var feet := Vector3(0.0, 0.0, -reach)
	var dir := _aim_dir(feet, AIMED[aim])
	_place(server, walker, feet, pose, WAIT_STEPS)
	var hurt := WeaponsFixture.of(_swing(server, weapon, 1, dir), &"damage_dealt")
	if hurt.is_empty():
		print("BLOW %s r%d %s %.1f %s MISS" % [weapon, round_number, pose, reach, aim])
		return
	var h := hurt[0]
	print(
		(
			"BLOW %s r%d %s %.1f %s zone=%s damage=%.0f left=%.0f"
			% [weapon, round_number, pose, reach, aim, h["zone"], h["damage"], h["health"]]
		)
	)


func _hits_to_kill(weapon: StringName, round_number: int) -> void:
	var made := _walker_in(round_number)
	var server: CombatServer = made[0]
	var walker: int = made[1]
	_take(server, weapon)
	var feet := Vector3(0.0, 0.0, -1.1)
	var dir := _aim_dir(feet, AIMED["chest"])
	for blows in range(1, 14):
		_place(server, walker, feet, ZombiePose.MOVE, WAIT_STEPS)
		var events := _swing(server, weapon, blows, dir)
		if not WeaponsFixture.of(events, &"target_killed").is_empty():
			print("HITS %s r%d %d" % [weapon, round_number, blows])
			return
	print("HITS %s r%d never" % [weapon, round_number])

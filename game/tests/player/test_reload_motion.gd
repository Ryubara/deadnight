# Every firearm's reload reads as a reload (#683, after #383's tilt): its `ReloadMotion` lifts and
# turns the weapon, the left hand goes to the belt for ammunition and back to the weapon, the
# weapon's part (drum, barrels, cylinder, lever) opens and closes, and the pose ends on the hold the
# aim weight gives, whatever that is. Stepped by hand with fixed ticks.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const START := Vector3(0.0, 0.05, 10.0)
const GUNS: Array[StringName] = [
	&"pistol",
	&"smg",
	&"rifle",
	&"shotgun",
	&"flare_gun",
	&"ppsh",
	&"mp5",
	&"m4a1",
	&"m249",
	&"fifty_cal",
	&"pump_870",
]
## The weapon turns at least this far from its hold (degrees) and its grip moves at least this far
## (metres): enough to come out from behind the head of the shoulder camera's view.
const MIN_TURN_DEG := 30.0
const MIN_MOVE := 0.1
## The most the barrel may turn in one tick at 60 a second: the revolver's flick to throw its
## empties out turns 17.4 at its fastest; a pop (a pose switched in one tick) is several times this.
const MAX_TICK_TURN_DEG := 20.0
## How far the grip may be from where it started once the reload is over: the aim loop's breathing
## sway alone moves it up to 3.5 cm between two moments.
const SWAY := 0.05
## The left hand is at the belt when it is this far from the weapon's grip, and on the weapon when
## it is this near.
const LEFT_AWAY := 0.35
const LEFT_ON := 0.3

var _runner: GdUnitSceneRunner
var _player: Player
var _rig: ThirdPersonCamera
var _animation: PlayerAnimation


func before_test() -> void:
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	# The suite ticks the player by hand (PlayerHandStep), not at the physics clock's pace.
	_player.set_physics_process(false)
	_rig = _player.camera_rig
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_rig.set_process(false)
	_animation.set_process(false)
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_player.teleport(START)
	# The physics server learns of the room's static bodies on its first step: take that one by
	# the clock, then tick by hand.
	await get_tree().physics_frame
	await _ticks(1)


func after_test() -> void:
	Input.action_release("aim")
	Input.action_release("sprint")


func _ticks(count: int) -> void:
	for i in count:
		PlayerHandStep.tick(_player)
		_rig.step(TICK, 1.0)
		_animation._process(TICK)
		_animation.advance(TICK)
	await get_tree().process_frame


func _seconds(seconds: float) -> void:
	await _ticks(roundi(seconds / TICK))


func _equip(weapon_id: StringName) -> void:
	_animation.equip(weapon_id)
	await _ticks(60)


## The weapon's place and barrel without the recoil kick.
func _weapon() -> Transform3D:
	var hands := _animation.hands()
	var kick := hands.recoil
	hands.recoil = 0.0
	var target := hands.weapon_target()
	hands.recoil = kick
	return target


## Reloads for `seconds` and samples the weapon, the left hand, the part and the ammunition every
## tick for `seconds` and a little after.
func _sample_reload(seconds: float) -> Dictionary:
	var start := _weapon()
	var last := -start.basis.x
	var out := {
		"turn": 0.0,
		"move": 0.0,
		"tick_turn": 0.0,
		"left_far": 0.0,
		"left_near": 1000.0,
		"part": 0.0,
		"ammo": false,
		"at_end": 0.0,
		"weight_at_end": 0.0,
	}
	_animation.reload(seconds)
	var ticks := roundi(seconds / TICK)
	for i in ticks + roundi(0.3 / TICK):
		await _ticks(1)
		var now := _weapon()
		var barrel := -now.basis.x
		out["turn"] = maxf(out["turn"], rad_to_deg(barrel.angle_to(-start.basis.x)))
		out["move"] = maxf(out["move"], now.origin.distance_to(start.origin))
		out["tick_turn"] = maxf(out["tick_turn"], rad_to_deg(barrel.angle_to(last)))
		last = barrel
		var pose := _animation.reload_pose()
		if pose.left > 0.99:
			var left := _animation.hands().solved_left().origin.distance_to(now.origin)
			out["left_far"] = maxf(out["left_far"], left)
			out["left_near"] = minf(out["left_near"], left)
		out["part"] = maxf(out["part"], pose.part)
		var ammo := _animation.reload_ammo()
		out["ammo"] = out["ammo"] or (ammo != null and ammo.visible)
		if i == ticks - 1:
			out["at_end"] = rad_to_deg(barrel.angle_to(-start.basis.x))
	out["after"] = rad_to_deg((-_weapon().basis.x).angle_to(-start.basis.x))
	out["origin_after"] = _weapon().origin.distance_to(start.origin)
	return out


func _check_reload(weapon_id: StringName, aiming: bool) -> void:
	await _equip(weapon_id)
	if aiming:
		_runner.simulate_action_press("aim")
		await _seconds(1.0)
	var seconds: float = WeaponCatalog.get_def(weapon_id).reload_time
	var tag := "%s%s" % [weapon_id, " aiming" if aiming else ""]
	var weight_before := _rig.aim_amount()
	var run := await _sample_reload(seconds)
	print("RELOAD %s %s" % [tag, run])
	assert_float(run["turn"]).override_failure_message(tag + ": no turn").is_greater(MIN_TURN_DEG)
	assert_float(run["move"]).override_failure_message(tag + ": no move").is_greater(MIN_MOVE)
	assert_float(run["tick_turn"]).override_failure_message(tag + ": a jump").is_less(
		MAX_TICK_TURN_DEG
	)
	assert_float(run["left_far"]).override_failure_message(tag + ": no belt").is_greater(LEFT_AWAY)
	assert_float(run["left_near"]).override_failure_message(tag + ": not at the weapon").is_less(
		LEFT_ON
	)
	assert_float(run["part"]).override_failure_message(tag + ": part shut").is_greater(0.95)
	assert_bool(run["ammo"]).override_failure_message(tag + ": no ammunition").is_true()
	# Back on the hold by the end of the reload time, and exactly there a moment later.
	assert_float(run["at_end"]).override_failure_message(tag + ": not back").is_less(3.0)
	assert_float(run["after"]).override_failure_message(tag + ": not on the hold").is_less(0.5)
	assert_float(run["origin_after"]).override_failure_message(tag + ": moved").is_less(SWAY)
	assert_float(_animation.reload_weight()).is_equal_approx(0.0, 0.001)
	var part := _animation.reload_part()
	assert_object(part).override_failure_message(tag + ": no part").is_not_null()
	assert_bool(part.visible).override_failure_message(tag + ": part left off").is_true()
	(
		assert_bool(_animation.reload_ammo().visible)
		. override_failure_message(tag + ": ammo")
		. is_false()
	)
	# The motion never touches the aim weight.
	assert_float(_rig.aim_amount()).override_failure_message(tag + ": weight").is_equal_approx(
		weight_before, 0.001
	)


func test_every_gun_reloads_with_its_motion_and_is_back_on_its_hold() -> void:
	for weapon_id in GUNS:
		await _check_reload(weapon_id, false)
		await _seconds(0.3)


func test_a_reload_while_aiming_returns_to_the_aim() -> void:
	for weapon_id: StringName in [&"pistol", &"shotgun"]:
		await _check_reload(weapon_id, true)
		_runner.simulate_action_release("aim")
		await _seconds(1.5)


func test_putting_the_weapon_away_ends_the_reload() -> void:
	await _equip(&"shotgun")
	_animation.reload(2.4)
	await _seconds(0.6)
	assert_float(_animation.reload_weight()).is_greater(0.9)
	assert_float(_animation.reload_pose().part).is_greater(0.9)
	_animation.equip(&"pistol")
	await _seconds(0.5)
	assert_float(_animation.reload_weight()).is_equal_approx(0.0, 0.001)
	assert_object(_animation.hands().reload).is_null()


func test_a_gun_not_reloading_holds_still() -> void:
	await _equip(&"rifle")
	await _seconds(0.5)
	assert_float(_animation.reload_weight()).is_equal(0.0)
	assert_object(_animation.hands().reload).is_null()
	assert_bool(_animation.reload_ammo().visible).is_false()


func test_a_reload_keeps_the_arms_from_the_sprint_carry() -> void:
	# The reload needs both hands: a sprint started during it does not take the arms.
	await _equip(&"smg")
	_animation.reload(1.9)
	_runner.simulate_action_press("sprint")
	_runner.simulate_action_press("move_forward")
	await _seconds(0.8)
	assert_float(_animation.sprint_carry()).is_less(0.01)
	assert_float(_animation.hands().weight).is_greater(0.99)
	_runner.simulate_action_release("move_forward")


func test_every_motion_starts_and_ends_on_the_hold_and_names_its_parts() -> void:
	for weapon_id in GUNS:
		var motion := ReloadMotion.for_weapon(weapon_id)
		assert_object(motion).override_failure_message(String(weapon_id)).is_not_null()
		var keys := motion.keys
		assert_float(keys[0].at).is_equal(0.0)
		assert_float(keys[-1].at).is_equal(1.0)
		for key: ReloadKey in [keys[0], keys[-1]]:
			assert_vector(key.weapon_offset).is_equal(Vector3.ZERO)
			assert_vector(key.weapon_turn).is_equal(Vector3.ZERO)
			assert_float(key.left).is_equal(0.0)
			assert_float(key.part).is_equal(0.0)
			assert_bool(key.ammo).is_false()
		for i in range(1, keys.size()):
			assert_float(keys[i].at).override_failure_message(String(weapon_id)).is_greater(
				keys[i - 1].at
			)
		for event: StringName in motion.events:
			for share in motion.event_shares(event):
				assert_float(share).is_between(0.01, 0.95)
		# The part is a node of the gun's model, the ammunition a model of its own.
		var hold := WeaponHoldMap.hold_for(weapon_id)
		var model := (load(hold.scene) as PackedScene).instantiate()
		(
			assert_object(model.find_child(String(motion.part_node), true, false))
			. override_failure_message("%s: no %s" % [weapon_id, motion.part_node])
			. is_not_null()
		)
		model.free()
		assert_bool(ResourceLoader.exists(motion.ammo_scene)).is_true()


# --- The pump: one cycle a round (#793) ---


func test_the_pump_motion_is_a_loop_of_one_cycle_a_round_over_its_magazine() -> void:
	var motion := ReloadMotion.for_weapon(&"pump_870")
	var def := WeaponCatalog.get_def(&"pump_870")
	assert_bool(motion.is_by_round()).is_true()
	assert_int(motion.loop_rounds).is_equal(def.magazine_size)
	assert_float(motion.loop_from).is_greater(0.0)
	assert_float(motion.loop_to).is_less(1.0)
	# A shell goes in, and the belt is reached for, once in each cycle; the pump is racked once.
	assert_int(motion.event_shares(&"shell_in").size()).is_equal(def.magazine_size)
	assert_int(motion.event_shares(&"pouch").size()).is_equal(def.magazine_size)
	assert_int(motion.event_shares(&"pump").size()).is_equal(1)


func test_a_reload_of_fewer_rounds_plays_the_lead_in_that_many_cycles_and_the_lead_out() -> void:
	var motion := ReloadMotion.for_weapon(&"pump_870")
	for rounds in range(1, motion.loop_rounds + 1):
		assert_float(motion.playhead(0.0, rounds)).is_equal(0.0)
		assert_float(motion.playhead(1.0, rounds)).is_equal_approx(1.0, 0.0001)
		var last := -1.0
		for i in 101:
			var at := motion.playhead(float(i) / 100.0, rounds)
			assert_float(at).is_greater_equal(last)
			last = at
		assert_int(motion.event_shares_for(&"shell_in", rounds).size()).is_equal(rounds)
		assert_int(motion.event_shares_for(&"pouch", rounds).size()).is_equal(rounds)
		assert_int(motion.event_shares_for(&"pump", rounds).size()).is_equal(1)
		for event: StringName in motion.events:
			for share in motion.event_shares_for(event, rounds):
				assert_float(share).is_between(0.01, 0.99)
	# The whole reload is the identity, and a magazine gun's motion ignores the count.
	assert_float(motion.playhead(0.37, motion.loop_rounds)).is_equal(0.37)
	assert_float(ReloadMotion.for_weapon(&"smg").playhead(0.37, 3)).is_equal(0.37)


func test_the_pump_reload_of_two_rounds_shows_two_shells_going_in() -> void:
	await _equip(&"pump_870")
	var def := WeaponCatalog.get_def(&"pump_870")
	var seconds := def.round_seconds() * 2.0
	_animation.reload(seconds, 2)
	var shown := 0
	var last := false
	for i in roundi(seconds / TICK) + 20:
		await _ticks(1)
		var ammo := _animation.reload_ammo()
		var now := ammo != null and ammo.visible
		if last and not now:
			shown += 1
		last = now
	# The shell is in the hand twice (taken from the belt, put in), and the reload ends clean.
	assert_int(shown).is_equal(2)
	assert_float(_animation.reload_weight()).is_equal_approx(0.0, 0.001)


func test_a_shot_that_ends_the_pump_reload_lets_the_arms_back_to_the_hold() -> void:
	await _equip(&"pump_870")
	_animation.reload(2.8, 6)
	await _seconds(0.8)
	assert_float(_animation.reload_weight()).is_greater(0.9)
	_animation.cancel_reload()
	await _seconds(0.5)
	assert_float(_animation.reload_weight()).is_equal_approx(0.0, 0.001)
	assert_object(_animation.hands().reload).is_null()

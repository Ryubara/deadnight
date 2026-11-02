# A grenade thrown in the night by a person's own input (#351): the throw key goes in as a real key
# event, the human controller turns it into the night's command, the server cooks and throws, the
# count drops, the grenade flies, goes off and hurts a zombie, and the player's own view draws it.
# Nothing here calls the grenade code directly: the whole path is the one a player's finger takes.
# A night run by hand: a tick is 1/60 s and nothing waits on the clock.
extends GdUnitTestSuite

const TICKS_PER_SECOND := 60
const SETTLE := 30
## Time for the first zombie to finish rising before the throw.
const EMERGE_TICKS := 150
const COOK_TICKS := 20
## From the button coming up to the grenade leaving the hand (0.375 s of the clip) and a little.
const WIND_TICKS := 30
const FLIGHT_LIMIT := 600
## The break before round one: long enough to throw in, short enough to wait out.
const INTRO_SECONDS := 1.0
## An underarm toss goes off within this many metres of the thrower; a zombie this far from the
## blast's centre is inside the blast but outside its core.
const CLOSE_BLAST := 9.0
const EDGE_OFFSET := 4.0

var _night: Night
var _hud: Hud
var _controller: HumanController
var _heard: Array[Dictionary] = []


func before_test() -> void:
	_heard = []
	# A fresh one each test: it remembers which buttons were down for the press edges.
	_controller = HumanController.new()
	_hud = (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	add_child(_hud)
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = INTRO_SECONDS
	_night = await NightFixture.start(self, Night.Mode.MANUAL, tuning, 7, _hud)
	_night.state.event_received.connect(_hear)
	NightFixture.run(_night, SETTLE)


func after_test() -> void:
	# A night left standing keeps flying its grenades into the next test, and its player's body
	# holds the next night's player up where the spawn is: free it before the next one is built.
	_night.state.event_received.disconnect(_hear)
	_night.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_key(KEY_G, false)
	_key(KEY_H, false)


func _hear(event: Dictionary) -> void:
	_heard.append(event)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


## `ticks` ticks of the night, each sending what the human controller reads from the input now.
func _play(ticks: int) -> void:
	var animation := _night.player().get_node("AnimationTree") as PlayerAnimation
	for _i in ticks:
		NightFixture.run(_night, 1, _controller.command(_night.player(), 1))
		# The Soldier follows frames, which a hand-run night has none of: step him by the tick.
		animation._process(Night.STEP)
		animation.advance(Night.STEP)


## The `blast_hit` that reached zombie `zombie_id`, or empty.
func _hit_on(zombie_id: int) -> Dictionary:
	for event in _heard:
		if event["type"] == &"blast_hit" and event["target_id"] == zombie_id:
			return event
	return {}


func _count(type: StringName) -> int:
	return _heard.filter(func(event: Dictionary) -> bool: return event["type"] == type).size()


func _first(type: StringName) -> Dictionary:
	for event in _heard:
		if event["type"] == type:
			return event
	return {}


## Round one is on and its first zombie has risen.
func _into_the_round() -> int:
	for _i in FLIGHT_LIMIT:
		if not _night.server.sim.zombies.is_empty():
			break
		NightFixture.run(_night, 1)
	assert_bool(_night.server.sim.zombies.is_empty()).is_false()
	NightFixture.run(_night, EMERGE_TICKS)
	return _night.server.sim.zombies.keys()[0]


## Where a grenade thrown as the event says goes off, found by stepping a copy of it through the
## same world the server uses (the same stepping code, the same physics space).
func _blast_point(thrown: Dictionary) -> Vector3:
	var cast := WorldCast.new(_night.get_world_3d().direct_space_state)
	var def := GrenadesFixture.def()
	var copy := GrenadeState.new(
		0, 1, def, thrown["position"], thrown["velocity"], thrown["fuse_left"]
	)
	for _i in FLIGHT_LIMIT:
		copy.step(Night.STEP, cast.callable())
		if copy.is_spent():
			break
	return copy.position


func test_pressing_the_throw_key_cooks_a_grenade_and_spends_one() -> void:
	_into_the_round()
	var before := _night.server.rules.grenades_of(1)
	assert_int(before).is_greater(0)
	_key(KEY_G, true)
	_play(COOK_TICKS)
	assert_int(_count(&"cook_started")).is_equal(1)
	assert_int(_night.server.rules.grenades_of(1)).is_equal(before - 1)
	var counted := {}
	for event in _heard:
		if event["type"] == &"grenade_count_changed" and event["reason"] == &"thrown":
			counted = event
	assert_int(counted.get("count", -1)).is_equal(before - 1)
	assert_str(String(counted.get("reason", &""))).is_equal("thrown")


func test_letting_go_throws_it_and_it_flies() -> void:
	_into_the_round()
	_key(KEY_G, true)
	_play(COOK_TICKS)
	_key(KEY_G, false)
	_play(WIND_TICKS)
	assert_int(_count(&"grenade_thrown")).is_equal(1)
	assert_int(_night.server.grenades.grenades_in_flight()).is_equal(1)


func test_the_underarm_key_tosses_a_grenade_too() -> void:
	_into_the_round()
	_key(KEY_H, true)
	_play(COOK_TICKS)
	_key(KEY_H, false)
	_play(WIND_TICKS)
	assert_bool(_first(&"grenade_thrown").get("underarm", false)).is_true()


func test_the_grenade_goes_off_and_kills_a_zombie_beside_it() -> void:
	var zombie_id := _into_the_round()
	var body: ZombieBody = _night.server.sim.zombies[zombie_id]
	_key(KEY_G, true)
	_play(COOK_TICKS)
	_key(KEY_G, false)
	_play(WIND_TICKS)
	var thrown := _first(&"grenade_thrown")
	assert_bool(thrown.is_empty()).is_false()
	if thrown.is_empty():
		return
	var spot := _blast_point(thrown) + Vector3(1.0, -0.1, 0.0)
	# The dead walk; this one waits where the grenade will go off.
	for _i in FLIGHT_LIMIT:
		if _count(&"grenade_exploded") > 0:
			break
		body.position = spot
		body.velocity = Vector3.ZERO
		_play(1)
	assert_int(_count(&"grenade_exploded")).is_equal(1)
	assert_int(_count(&"blast_hit")).is_greater(0)
	assert_bool(_night.server.rules.has_zombie(zombie_id)).is_false()


func test_a_toss_goes_off_close_and_the_blast_throws_and_stuns_a_zombie_at_its_edge() -> void:
	var zombie_id := _into_the_round()
	var body: ZombieBody = _night.server.sim.zombies[zombie_id]
	_key(KEY_H, true)
	_play(COOK_TICKS)
	_key(KEY_H, false)
	_play(WIND_TICKS)
	var thrown := _first(&"grenade_thrown")
	assert_bool(thrown.is_empty()).is_false()
	if thrown.is_empty():
		return
	var blast := _blast_point(thrown)
	var from := _night.player().global_position
	assert_float(Vector2(blast.x - from.x, blast.z - from.z).length()).is_less(CLOSE_BLAST)
	var spot := blast + Vector3(EDGE_OFFSET, -0.1, 0.0)
	for _i in FLIGHT_LIMIT:
		if _count(&"grenade_exploded") > 0:
			break
		body.position = spot
		body.velocity = Vector3.ZERO
		_play(1)
	var hit := _hit_on(zombie_id)
	assert_bool(hit.is_empty()).is_false()
	# The stun falls off with the distance from the blast: shorter than the core's, never none.
	assert_float(hit.get("stun", 0.0)).is_between(0.1, _night.server.grenades.def.stun_seconds)
	# Thrown away from the blast, along the ground's direction.
	var away: Vector3 = hit.get("impulse", Vector3.ZERO)
	assert_float(away.x).is_greater(0.0)


func test_the_view_draws_the_grenade_while_it_flies() -> void:
	_into_the_round()
	_key(KEY_G, true)
	_play(COOK_TICKS)
	_key(KEY_G, false)
	_play(WIND_TICKS)
	assert_int(_night.view.grenades_in_flight()).is_equal(1)
	assert_int(_night.view.find_children("*", "GrenadeView", true, false).size()).is_equal(1)


func test_the_hud_counts_the_grenades_down() -> void:
	_into_the_round()
	var before := _night.server.rules.grenades_of(1)
	assert_str(_hud.health.grenade_text).is_equal("GRENADES x%d" % before)
	_key(KEY_G, true)
	_play(COOK_TICKS)
	assert_str(_hud.health.grenade_text).is_equal("GRENADES x%d" % (before - 1))


func test_a_grenade_held_until_it_goes_off_hurts_the_thrower_once() -> void:
	_into_the_round()
	var health := _night.server.health_of(1)
	_key(KEY_G, true)
	var fuse := _night.server.grenades.def.fuse
	_play(roundi(fuse * TICKS_PER_SECOND) + 20)
	assert_bool(_first(&"grenade_exploded").get("in_hand", false)).is_true()
	assert_float(_night.server.health_of(1)).is_less(health)
	# The key is still down: it does not pull another pin until it is let go.
	assert_int(_count(&"cook_started")).is_equal(1)
	_key(KEY_G, false)
	_play(WIND_TICKS)
	_key(KEY_G, true)
	_play(COOK_TICKS)
	assert_int(_count(&"cook_started")).is_equal(2)


func test_with_none_left_the_key_throws_nothing_and_says_so_once() -> void:
	_into_the_round()
	var carried := _night.server.rules.grenades_of(1)
	for _i in carried:
		_key(KEY_G, true)
		_play(COOK_TICKS)
		_key(KEY_G, false)
		_play(WIND_TICKS)
	assert_int(_count(&"grenade_thrown")).is_equal(carried)
	assert_int(_night.server.rules.grenades_of(1)).is_equal(0)
	_key(KEY_G, true)
	_play(COOK_TICKS * 3)
	assert_int(_count(&"cook_started")).is_equal(carried)
	assert_int(_count(&"cook_rejected")).is_equal(1)
	assert_str(String(_first(&"cook_rejected")["reason"])).is_equal("no_grenades")


func test_between_rounds_the_key_does_nothing() -> void:
	# The night is still in its break: no round, no throw, and the count is not spent.
	var before := _night.server.rules.grenades_of(1)
	_key(KEY_G, true)
	_play(COOK_TICKS)
	assert_int(_count(&"cook_started")).is_equal(0)
	assert_int(_night.server.rules.grenades_of(1)).is_equal(before)


func test_the_soldier_plays_the_pin_and_the_throw() -> void:
	_into_the_round()
	var animation := _night.player().get_node("AnimationTree") as PlayerAnimation
	_key(KEY_G, true)
	_play(3)
	assert_str(String(animation.action_clip)).is_equal("Grenade_Cook")
	_play(COOK_TICKS)
	_key(KEY_G, false)
	_play(3)
	assert_str(String(animation.action_clip)).is_equal("Grenade_Throw")
	_play(WIND_TICKS)
	_key(KEY_H, true)
	_play(COOK_TICKS)
	_key(KEY_H, false)
	_play(3)
	assert_str(String(animation.action_clip)).is_equal("Grenade_Toss")


## The tick (counted from the start of the play) at which `event` is first heard, or -1.
func _tick_of(type: StringName) -> int:
	for index in _heard.size():
		if _heard[index]["type"] == type:
			return index
	return -1


func test_the_grenade_leaves_the_hand_as_the_throw_clip_lets_go() -> void:
	_into_the_round()
	var animation := _night.player().get_node("AnimationTree") as PlayerAnimation
	var released: Array[float] = []
	var thrown_at: Array[float] = []
	var clock := [0.0]
	animation.clip_event.connect(
		func(_clip: StringName, event: StringName) -> void:
			if event == &"release":
				released.append(clock[0])
	)
	_night.state.event_received.connect(
		func(event: Dictionary) -> void:
			if event["type"] == &"grenade_thrown":
				thrown_at.append(clock[0])
	)
	_key(KEY_G, true)
	_play(COOK_TICKS)
	_key(KEY_G, false)
	for _i in WIND_TICKS * 2:
		_play(1)
		clock[0] += 1.0 / TICKS_PER_SECOND
	assert_array(thrown_at).has_size(1)
	assert_array(released).has_size(1)
	assert_float(released[0]).is_equal_approx(thrown_at[0], 0.07)
	# Not at the button: the throw takes the clip's time to reach its release frame.
	assert_float(thrown_at[0]).is_greater(0.3)


func test_the_swing_is_announced_when_the_button_comes_up() -> void:
	_into_the_round()
	_key(KEY_G, true)
	_play(COOK_TICKS)
	_key(KEY_G, false)
	_play(2)
	assert_int(_count(&"throw_started")).is_equal(1)
	assert_int(_count(&"grenade_thrown")).is_equal(0)
	assert_bool(_first(&"throw_started")["underarm"]).is_false()
	_play(WIND_TICKS)
	assert_int(_count(&"grenade_thrown")).is_equal(1)
	assert_int(_tick_of(&"throw_started")).is_less(_tick_of(&"grenade_thrown"))


func test_a_long_cook_holds_the_cook_pose_until_the_button_comes_up() -> void:
	_into_the_round()
	var animation := _night.player().get_node("AnimationTree") as PlayerAnimation
	_key(KEY_G, true)
	_play(TICKS_PER_SECOND / 2)
	var held_at := _upper_arm_angle(animation)
	_play(TICKS_PER_SECOND * 2)
	assert_str(String(animation.action_clip)).is_equal("Grenade_Cook")
	assert_bool(animation.get("parameters/action/active")).is_true()
	assert_float(_upper_arm_angle(animation)).is_equal_approx(held_at, 0.01)
	_key(KEY_G, false)
	_play(2)
	assert_str(String(animation.action_clip)).is_equal("Grenade_Throw")


func test_the_grenade_is_in_the_hand_from_the_pin_to_the_release() -> void:
	_into_the_round()
	var animation := _night.player().get_node("AnimationTree") as PlayerAnimation
	var grenade := animation.weapon_mount().get_node("Grenade") as Node3D
	assert_bool(grenade.visible).is_false()
	_key(KEY_G, true)
	_play(COOK_TICKS)
	assert_bool(grenade.visible).is_true()
	_key(KEY_G, false)
	_play(WIND_TICKS)
	assert_int(_count(&"grenade_thrown")).is_equal(1)
	assert_bool(grenade.visible).is_false()


func test_a_grenade_that_goes_off_in_the_hand_leaves_the_hand_empty_and_the_gun_back() -> void:
	_into_the_round()
	var animation := _night.player().get_node("AnimationTree") as PlayerAnimation
	var grenade := animation.weapon_mount().get_node("Grenade") as Node3D
	_key(KEY_G, true)
	_play(roundi(_night.server.grenades.def.fuse * TICKS_PER_SECOND) + 20)
	assert_bool(_first(&"grenade_exploded").get("in_hand", false)).is_true()
	assert_bool(grenade.visible).is_false()
	assert_str(String(animation.action_clip)).is_equal("")


## How far the right upper arm is turned from straight, from the skeleton as it stands now.
func _upper_arm_angle(animation: PlayerAnimation) -> float:
	var skeleton := animation.weapon_mount().get_parent() as Skeleton3D
	var bone := skeleton.find_bone("UpperArm.R")
	return skeleton.get_bone_pose_rotation(bone).get_angle()

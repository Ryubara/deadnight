# The Soldier's perk drink (#912, docs/design/animation.md, "Drink"): `Drink_Perk` plays over
# the arms at the pace of the rules' drink, the gun goes away and comes back, the perk's bottle
# shows in its colour, loses its cap, reaches the mouth, is thrown away and lands; a down drops
# it. Stepped by hand, a fixed tick at a time.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const TICK := 1.0 / 60.0
const SECONDS := 2.5
## The mouth in the Head bone's frame (skeleton units), as `tools/blender/drink_clip.py` prints it
## (`DRINK mouth in the Head bone's frame`): the point the lip is put on while drinking.
const MOUTH := Vector3(0.0009, 0.4192, -0.1478)

var _runner: GdUnitSceneRunner
var _player: Player
var _animation: PlayerAnimation
var _skeleton: Skeleton3D
var _events: Array[StringName] = []


func before_test() -> void:
	_runner = scene_runner(TEST_ROOM)
	_player = _runner.find_child("Player") as Player
	_player.capture_mouse = false
	_player.camera_rig.set_process(false)
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_animation.set_process(false)
	_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_skeleton = _player.find_child("Skeleton3D", true, false) as Skeleton3D
	_events.clear()
	_animation.clip_event.connect(
		func(clip: StringName, event: StringName) -> void:
			if clip == DrinkLayer.CLIP:
				_events.append(event)
	)
	_step(10)


func _step(ticks: int) -> void:
	for _i in ticks:
		_animation._process(TICK)
		_animation.advance(TICK)


## Steps until the clip has passed `event` (one tick at a time; fails after the drink's length).
func _until(event: StringName) -> void:
	for _i in roundi(SECONDS * 60.0) + 10:
		if _events.has(event):
			return
		_step(1)
	fail("no %s" % event)


func _bone(bone: String) -> Vector3:
	return (
		(_skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(bone)))
		. origin
	)


## The bottle's lip in the world: the hand bone as the skeleton poses it now, the bottle's place on
## it, the hold's `muzzle` on the model (the mount's own transform is updated only when it draws).
func _lip() -> Vector3:
	var hold := load(PerkBottle.HOLD) as WeaponHold
	var hand := (
		_skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone("Index1.R"))
	)
	return hand * _animation.bottle().transform * hold.muzzle


func test_the_clip_is_in_the_library_and_lasts_the_drink() -> void:
	var player := _player.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_bool(player.has_animation(DrinkLayer.CLIP)).is_true()
	assert_float(player.get_animation(DrinkLayer.CLIP).length).is_equal_approx(SECONDS, 0.01)
	assert_bool(_animation.is_drinking()).is_false()
	assert_bool(_animation.bottle().visible).is_false()


func test_the_drink_puts_the_gun_away_shows_the_bottle_and_brings_the_gun_back() -> void:
	assert_bool(_animation.weapon().visible).is_true()
	_animation.drink(&"tonic_double_shot", SECONDS)
	assert_bool(_animation.is_drinking()).is_true()
	_until(&"bottle_visible")
	assert_bool(_animation.weapon().visible).is_false()
	assert_bool(_animation.bottle().visible).is_true()
	assert_bool(_animation.bottle().capped()).is_true()
	_until(&"cap_off")
	assert_bool(_animation.bottle().capped()).is_false()
	_until(&"discard")
	assert_bool(_animation.bottle().visible).is_false()
	assert_int(_animation.bottle().loose()).is_greater_equal(2)  # the cap and the bottle
	_until(&"weapon_visible")
	assert_bool(_animation.weapon().visible).is_true()
	_until(&"done")
	assert_bool(_animation.is_drinking()).is_false()
	_step(40)
	assert_float(_animation.drink_layer().blend).is_equal(0.0)


func test_the_clip_keeps_the_pace_of_the_rules_drink() -> void:
	# Played over 3 s instead of 2.5, the clip ends with the drink, not before it.
	_animation.drink(&"tonic_quick_load", 3.0)
	_step(int(3.0 * 60.0) - 3)
	assert_bool(_animation.is_drinking()).is_true()
	_step(4)
	assert_bool(_animation.is_drinking()).is_false()
	assert_array(_events).contains([&"done"])


func test_each_perk_has_its_machines_colours() -> void:
	for look: Dictionary in PerkMachine.LOOKS.values():
		_animation.drink(look["item"], SECONDS)
		assert_object(_animation.bottle().drink_colour()).is_equal(look["drink"])
		assert_object(_animation.bottle().label_colour()).is_equal(look["body"])
		_animation.stop_drink()
	_animation.drink(&"tonic_hearty", SECONDS)
	assert_object(_animation.bottle().drink_colour()).is_equal(SodaFountain.TONIC)


func test_the_lip_reaches_the_mouth_while_drinking() -> void:
	# The clip was solved in Blender with the lip on the mouth, which rides the Head bone; here the
	# lip is measured as the game draws it, over the locomotion's hips, in the Head bone's frame.
	_animation.drink(&"tonic_double_shot", SECONDS)
	for moment: StringName in [&"drink", &"gulp"]:
		_until(moment)
		_step(1)
		var head := _skeleton.get_bone_global_pose(_skeleton.find_bone("Head"))
		var lip := head.affine_inverse() * (_skeleton.global_transform.affine_inverse() * _lip())
		var off := lip.distance_to(MOUTH)
		(
			assert_float(off)
			. override_failure_message("lip %s, %.3f from the mouth at %s" % [lip, off, moment])
			. is_less(0.05)
		)


func test_going_down_drops_the_bottle_and_ends_the_drink() -> void:
	_animation.drink(&"tonic_reload_shock", SECONDS)
	_until(&"cap_off")
	_animation.set_downed(true)
	assert_bool(_animation.is_drinking()).is_false()
	assert_bool(_animation.bottle().visible).is_false()
	assert_int(_animation.bottle().loose()).is_greater_equal(2)
	# Down, a new drink does not start.
	_animation.drink(&"tonic_reload_shock", SECONDS)
	assert_bool(_animation.is_drinking()).is_false()


func test_the_thrown_bottle_lands_beside_the_drinker_and_goes() -> void:
	_animation.drink(&"tonic_swift_rescue", SECONDS)
	_until(&"discard")
	_step(90)
	var feet := _player.global_position
	var lying := 0
	for child in _player.get_parent().get_children():
		var node := child as Node3D
		if (
			node != null
			and node.top_level
			and node.visible
			and node.find_child("Label", true, false)
		):
			lying += 1
			assert_float(node.global_position.y - feet.y).is_between(0.0, 0.15)
			var away := Vector2(node.global_position.x - feet.x, node.global_position.z - feet.z)
			assert_float(away.length()).is_between(0.3, 3.0)
	assert_int(lying).is_equal(1)
	_step(int(PerkBottle.LIE_SECONDS * 60.0))
	assert_int(_animation.bottle().loose()).is_equal(0)


func test_the_hand_closes_on_the_bottle_while_it_shows() -> void:
	_animation.drink(&"tonic_third_holster", SECONDS)
	_until(&"bottle_visible")
	_step(30)
	assert_object(_animation.fingers().grip).is_same(_animation.bottle().grip)

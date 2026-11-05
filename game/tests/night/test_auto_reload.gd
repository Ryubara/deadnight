extends GdUnitTestSuite
## A gun that runs dry reloads by itself, for every player on every device (#1278). The reproduction
## was a phone aiming with auto-fire: the trigger lets go at an empty magazine (`wants_fire` needs a
## round), and the server reloaded only when a trigger was pulled at an empty gun, so nothing ever
## reloaded it. Each row presses real input events (the keyboard and mouse, a pad that is not device
## 0, a finger on the touch layer's Aim) through `HumanController` into a night, and reads the
## server's own weapon state. A night is stepped by hand, a tick is 1/60 s.

const PAD := 3
const TICK := 1.0 / 60.0
## Ticks the longest reload of the tests takes, with a margin.
const RELOAD_TICKS := 240
const PISTOL := &"pistol"
const SHOTGUN := &"pump_870"
const PLAYER := 1
## A health no magazine takes off the first zombie.
const TOUGH := 5000.0

var _night: Night
var _was_touch := false
var _held: Array[InputEvent] = []
var _heard: Array[Dictionary] = []


func before_test() -> void:
	await RouterFixture.clear(get_tree())
	_was_touch = UIInputMode.touch
	UIInputMode.touch = false
	_held = []
	_heard = []


func after_test() -> void:
	for event in _held.duplicate():
		_send(event, false)
	_held = []
	for action in [&"fire", &"aim", &"reload", &"swap_weapon"]:
		Input.action_release(action)
	UIInputMode.touch = _was_touch
	if _night != null:
		_night.queue_free()
		_night = null
		await get_tree().physics_frame


## A human night with the pistol in hand and the shotgun carried too, the break over, a zombie
## on the lot.
func _begin(touch := false) -> void:
	var tuning := RulesFixture.full_hands()
	# The dead outlast a magazine, so a trigger is never let go for lack of a target.
	tuning.rounds.health_base = TOUGH
	_night = await NightFixture.start(self, Night.Mode.HUMAN, tuning)
	_night.ticks_per_frame = 0
	_night.touch_active = func() -> bool: return touch
	_night.state.event_received.connect(func(event: Dictionary) -> void: _heard.append(event))
	_night.server.combat.apply(CombatAction.give_weapon(PLAYER, SHOTGUN, &"crowbar"))
	_night.server.combat.apply(CombatAction.equip(PLAYER, PISTOL))
	NightFixture.first_zombie(_night)


func _state(weapon: StringName = PISTOL) -> WeaponState:
	return _night.server.combat.state_of(PLAYER, weapon)


func _count(type: StringName) -> int:
	return _heard.filter(func(event: Dictionary) -> bool: return event["type"] == type).size()


## The input events the map binds to `action` on a keyboard and mouse, or on a gamepad.
func _bound(action: StringName, pad: bool) -> Array[InputEvent]:
	var found: Array[InputEvent] = []
	for event in InputMap.action_get_events(action):
		var is_pad := event is InputEventJoypadButton or event is InputEventJoypadMotion
		if is_pad == pad and (is_pad or event is InputEventKey or event is InputEventMouseButton):
			var copy := event.duplicate() as InputEvent
			if pad:
				copy.device = PAD
			found.append(copy)
	return found


func _send(event: InputEvent, pressed: bool) -> void:
	var copy := event.duplicate() as InputEvent
	if copy is InputEventKey:
		(copy as InputEventKey).pressed = pressed
	elif copy is InputEventMouseButton:
		(copy as InputEventMouseButton).pressed = pressed
	elif copy is InputEventJoypadButton:
		(copy as InputEventJoypadButton).pressed = pressed
	elif copy is InputEventJoypadMotion and not pressed:
		(copy as InputEventJoypadMotion).axis_value = 0.0
	if pressed:
		_held.append(event)
	else:
		_held.erase(event)
	Input.parse_input_event(copy)
	Input.flush_buffered_events()


## Keeps a zombie on the crosshair.
func _hold_a_target() -> void:
	var view := _night.player().camera_rig.aim_transform()
	for zombie: ZombieBody in _night.server.sim.zombies.values():
		zombie.position = view.origin + (-view.basis.z) * 6.0 - Vector3.UP * 1.2
		zombie.velocity = Vector3.ZERO
		return


## Steps the night `ticks` ticks, a frame between so the camera and the input settle.
func _play(ticks: int) -> void:
	for _i in ticks:
		await get_tree().process_frame
		_hold_a_target()
		_night.tick()


## Plays until `done` says so, at most `limit` ticks; the ticks it took.
func _play_until(done: Callable, limit: int) -> int:
	for tick in limit:
		if done.call():
			return tick
		await _play(1)
	return limit


# --- The case reported: aiming with auto-fire on a phone ---


## A finger on the touch layer's Aim button, a zombie on the crosshair, the trigger never touched:
## the gun fires itself dry and must reload itself.
func test_aiming_with_auto_fire_reloads_at_an_empty_magazine() -> void:
	await _begin(true)
	UIInputMode.touch = true
	var fixture := TouchFixture.make(self, TouchFixture.PHONE)
	await get_tree().process_frame
	await fixture.touch(0, fixture.at(&"aim"))
	# The finger stays down: the first reload is the whole of what this row reads.
	await _play_until(func() -> bool: return _count(&"reload_finished") > 0, 900)
	var shots := _count(&"shot_fired")
	var started := _count(&"reload_started")
	var finished := _heard.filter(
		func(e: Dictionary) -> bool: return e["type"] == &"reload_finished"
	)
	await fixture.lift(0)
	fixture.free_all()
	(
		assert_int(shots)
		. override_failure_message(
			"the finger on Aim fired %d shots before a reload, a magazine is 10" % shots
		)
		. is_equal(10)
	)
	(
		assert_int(started)
		. override_failure_message("the pistol ran dry under auto-fire and never reloaded")
		. is_equal(1)
	)
	assert_int(finished.size()).is_equal(1)
	if finished.size() == 1:
		assert_int(int(finished[0]["ammo"])).is_equal(10)
		assert_int(int(finished[0]["reserve"])).is_equal(30)


# --- Every device: the trigger lets go at the last round ---


func test_a_trigger_let_go_at_the_last_round_reloads_on_the_keyboard_and_mouse() -> void:
	await _let_go_after_the_last_round(false)


func test_a_trigger_let_go_at_the_last_round_reloads_on_a_gamepad() -> void:
	await _let_go_after_the_last_round(true)


func _let_go_after_the_last_round(pad: bool) -> void:
	await _begin()
	_state().ammo = 1
	var fire := _bound(&"fire", pad)[0]
	_send(fire, true)
	await _play_until(func() -> bool: return _count(&"shot_fired") > 0, 60)
	_send(fire, false)
	assert_int(_state().ammo).is_equal(0)
	await _play(RELOAD_TICKS)
	assert_int(_count(&"reload_started")).is_equal(1)
	assert_int(_count(&"reload_finished")).is_equal(1)
	assert_int(_state().ammo).is_equal(10)
	assert_int(_state().reserve).is_equal(30)


func test_a_trigger_held_through_a_whole_magazine_reloads_on_every_device() -> void:
	for pad in [false, true]:
		await _begin()
		var fire := _bound(&"fire", pad)[0]
		_send(fire, true)
		await _play_until(func() -> bool: return _count(&"reload_finished") > 0, 600)
		_send(fire, false)
		(
			assert_int(_count(&"shot_fired"))
			. override_failure_message("pad %s: a whole magazine is ten shots" % pad)
			. is_greater_equal(10)
		)
		assert_int(_count(&"reload_started")).is_greater_equal(1)
		_night.queue_free()
		await get_tree().physics_frame
		_heard = []


# --- The rounds go in at the end, and a swap drops the reload ---


func test_the_rounds_go_in_only_when_the_reload_has_finished() -> void:
	await _begin()
	_state().ammo = 0
	await _play(2)
	assert_int(_count(&"reload_started")).is_equal(1)
	# A person mashing Reload meanwhile gets refusals, never rounds.
	var reload_key := _bound(&"reload", false)[0]
	for _i in 30:
		_send(reload_key, true)
		await _play(1)
		_send(reload_key, false)
		await _play(1)
		assert_int(_state().ammo).is_equal(0)
	await _play(RELOAD_TICKS)
	assert_int(_state().ammo).is_equal(10)
	assert_int(_state().reserve).is_equal(30)
	assert_int(_count(&"reload_finished")).is_equal(1)


func test_a_swap_in_the_middle_of_a_reload_adds_nothing() -> void:
	await _begin()
	_state().ammo = 0
	await _play(30)
	assert_bool(_state().is_reloading()).is_true()
	await _swap_key()
	assert_bool(_state().is_reloading()).is_false()
	await _play(RELOAD_TICKS)
	assert_int(_state(PISTOL).ammo).is_equal(0)
	assert_int(_state(PISTOL).reserve).is_equal(40)
	assert_int(_count(&"reload_finished")).is_equal(0)


func test_coming_back_to_an_empty_gun_reloads_it() -> void:
	await _begin()
	_state().ammo = 0
	await _play(30)
	await _swap_key()
	await _play(RELOAD_TICKS)
	assert_int(_state(PISTOL).ammo).is_equal(0)
	await _swap_key()
	await _play(RELOAD_TICKS)
	assert_int(_state(PISTOL).ammo).is_equal(10)
	assert_int(_state(PISTOL).reserve).is_equal(30)
	assert_int(_count(&"reload_finished")).is_equal(1)


func test_a_reload_by_the_round_keeps_only_the_rounds_that_finished() -> void:
	await _begin()
	_night.server.combat.apply(CombatAction.equip(PLAYER, SHOTGUN))
	_state(SHOTGUN).ammo = 0
	await _play_until(func() -> bool: return _state(SHOTGUN).ammo >= 2, 600)
	assert_int(_state(SHOTGUN).ammo).is_equal(2)
	await _swap_key()
	await _play(RELOAD_TICKS)
	assert_int(_state(SHOTGUN).ammo).is_equal(2)
	assert_int(_state(SHOTGUN).reserve).is_equal(40)
	assert_int(_count(&"reload_finished")).is_equal(0)


# --- Nothing to reload with, nothing to reload ---


func test_an_empty_reserve_does_not_reload_or_complain() -> void:
	await _begin()
	_state().ammo = 0
	_state().reserve = 0
	await _play(RELOAD_TICKS)
	assert_int(_count(&"reload_started")).is_equal(0)
	assert_int(_count(&"reload_rejected")).is_equal(0)
	assert_int(_state().ammo).is_equal(0)


func test_a_blade_in_hand_is_left_alone() -> void:
	await _begin()
	_night.server.combat.apply(CombatAction.give_weapon(PLAYER, &"crowbar", SHOTGUN))
	_night.server.combat.apply(CombatAction.equip(PLAYER, &"crowbar"))
	await _play(RELOAD_TICKS)
	assert_int(_count(&"reload_started")).is_equal(0)
	assert_int(_count(&"reload_rejected")).is_equal(0)


## A bot decides its own reloads (`BotArsenal` swaps instead when the dead are close and another
## gun is loaded), so the server's rule leaves a bot's seat alone.
func test_a_bot_s_empty_gun_is_left_to_the_bot() -> void:
	await _begin()
	_night.server.rules.players[PLAYER].bot = true
	_state().ammo = 0
	await _play(RELOAD_TICKS)
	assert_int(_count(&"reload_started")).is_equal(0)
	assert_int(_state().ammo).is_equal(0)


## The swap key, pressed and let go as a person would.
func _swap_key() -> void:
	var key := _bound(&"swap_weapon", false)[0]
	_send(key, true)
	await _play(1)
	_send(key, false)
	await _play(1)

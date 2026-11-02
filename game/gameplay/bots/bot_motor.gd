class_name BotMotor
extends RefCounted
## The hands of a bot: every tick it turns the brain's intent into a `NightCommand`: the view, the
## trigger and the stick (the way to walk was found by `BotLegs`). The aim is a model, not a dice
## roll:
##
## - the view (`yaw`, `pitch`) is a critically damped spring toward where the target is, with a
##   hard cap on how fast it may turn (`BotProfile.max_aim_speed`, any window), and the shot's
##   `dir` is derived from the view, so the shot always goes where the bot looks;
## - the point it turns to carries seeded, filtered tracking noise that grows with distance, the
##   target's angular speed and the bot's own speed and shrinks the longer it stays on target;
## - the trigger is pulled when the view is inside the weapon's hit cone, not before, with a
##   small seeded pause after each shot and a pause on switching to the next zombie;
## - the bot aims at the chest, and at the head with the profile's head-aim rate when the target
##   is slow and near; at the headliner's lit lens (its weak spot) at the profile's rate while the
##   boss faces it;
## - a grenade is thrown by turning to the view the brain chose, pulling the pin when the view is
##   there, letting go a moment after and holding the view while the arm swings.
##
## All randomness is the bot's own seeded stream; time is the step it is given.

## Metres of a zombie's width the cone must cover, and the cone's limits in degrees.
const HIT_RADIUS := 0.3
const CONE_MIN := 1.0
const CONE_MAX := 6.0
## Seconds over which tracking noise stays correlated, and the least it shrinks to on target.
const NOISE_MEMORY := 0.25
const FOCUS_FLOOR := 0.6
const FOCUS_SECONDS := 1.0
## A head is aimed at only when the target moves slower than this (m/s) and is nearer than this (m).
const HEAD_SPEED := 3.0
const HEAD_RANGE := 12.0
## Limits of the pitch the view turns to (radians), and a melee swing's reach (metres).
const PITCH_LIMIT := 1.2
const MELEE_RANGE := 1.9
## The weak spot of the headliner in a walker's units (as `Hitbox.WEAK_ZONE`): up and ahead of its
## feet, and the least a boss must face the bot (dot product) for the lens to be seen.
const WEAK_SPOT := Vector3(0.0, 1.16, 0.29)
const WEAK_FACING := 0.35
## A grenade throw: degrees the view may be off the throw's, ticks the pin is held, seconds the view
## is held after the button comes up (the arm's swing), and the longest the turn may take.
const THROW_AIM_DEGREES := 3.0
const THROW_COOK_TICKS := 2
const THROW_SWING_SECONDS := 0.5
const THROW_TURN_SECONDS := 1.5
## The widest the view may be off a target for a panic shot (degrees).
const PANIC_DEGREES := 25.0
## Shots in a burst of an automatic weapon.
const BURST_MIN := 3
const BURST_MAX := 5
## The barrel's place from the feet, on the body's heading (as `NightTuning.muzzle_offset`).
const MUZZLE := Vector3(0.3, 1.45, -0.4)

## Where the view is.
var yaw := 0.0
var pitch := 0.0
## The target the motor is on, and the degrees between the view and it at the last tick.
var target_id := -1
var error_degrees := INF
## Shots the motor has asked for since it began, and grenades it has thrown.
var triggers := 0
var throws := 0

var _profile: BotProfile
var _rng: RandomNumberGenerator
var _yaw_speed := 0.0
var _pitch_speed := 0.0
var _noise := Vector2.ZERO
var _started := false
var _retarget_left := 0.0
var _pause_left := 0.0
var _burst_left := 0
var _focus := 0.0
var _head := false
var _weak := false
var _panicky := false
var _throw_phase := 0
var _throw_ticks := 0
var _throw_left := 0.0
var _throw_style: StringName = &""
var _throw_view := Vector2.ZERO
var _shots_seen := 0
var _last_position := Vector3.INF
var _last_bearing := 0.0
var _weapon_id: StringName = &""
var _weapon_def: WeaponDef


func _init(profile: BotProfile, rng: RandomNumberGenerator) -> void:
	_profile = profile
	_rng = rng


## Looks along `p_yaw` from now on, as if the bot had been turned there (a test, a spawn).
func face(p_yaw: float) -> void:
	yaw = p_yaw
	_started = true


## The command for this tick. The intent's one-shot edges (reload, swap, use) are used up.
func command(
	delta: float, me: Dictionary, intent: BotIntent, beliefs: BotBeliefs, shots: int
) -> NightCommand:
	var out := NightCommand.new()
	var here: Vector3 = me.get("pos", Vector3.ZERO)
	if not _started:
		_started = true
		yaw = me.get("facing", 0.0)
	if _last_position == Vector3.INF:
		_last_position = here
	var own_speed := Vector2(here.x - _last_position.x, here.z - _last_position.z).length() / delta
	_last_position = here
	var weapon := _weapon_of(me)
	_count_shots(shots, weapon != null and weapon.automatic)
	_tick_timers(delta)
	var eye := here + Vector3(0.0, BotLevel.EYE_HEIGHT, 0.0)
	var contact := _target(intent, beliefs)
	var throwing := _throwing(intent, delta)
	var wanted := _throw_view if throwing else _wanted_view(delta, eye, contact, intent, own_speed)
	_turn(delta, wanted)
	out.origin = eye
	out.look_along(yaw, pitch)
	out.muzzle = here + Basis(Vector3.UP, yaw) * MUZZLE
	if me.get("downed", false):
		_end_throw()
		return out
	_walk(out, intent)
	if throwing:
		_throw(out)
	else:
		out.fire = _trigger(me, eye, contact, intent.melee_ok)
	out.reload = intent.reload and not me.get("reloading", false)
	out.swap = intent.swap
	out.use = intent.use
	out.use_held = intent.use_held
	intent.reload = false
	intent.swap = false
	intent.use = false
	return out


# --- Who ---


## The contact the intent names, if it may be shot at; note a change of target.
func _target(intent: BotIntent, beliefs: BotBeliefs) -> Dictionary:
	var contact := beliefs.contact(intent.target_id)
	if contact.is_empty() or not beliefs.is_believed(contact) or not contact["visible"]:
		_leave_target()
		return {}
	if intent.target_id != target_id:
		if target_id >= 0:
			_retarget_left = _rng.randf_range(_profile.retarget_min, _profile.retarget_max)
		target_id = intent.target_id
		_head = _rng.randf() < _profile.head_rate
		if ZombieModels.is_boss(contact.get("look", ZombieModels.DEFAULT)):
			_weak = _rng.randf() < _profile.weak_spot_rate
		_focus = 0.0
		_noise = Vector2.ZERO
	return contact


func _leave_target() -> void:
	if target_id >= 0:
		# The next one costs the flick; losing the target for good is the brain's business.
		_retarget_left = maxf(
			_retarget_left, _rng.randf_range(_profile.retarget_min, _profile.retarget_max)
		)
	target_id = -1
	error_degrees = INF
	_focus = 0.0


# --- Where to look ---


## The yaw and pitch the view is turning to: the target (noise included), a place to glance at,
## the way it walks, or where it already looks.
func _wanted_view(
	delta: float, eye: Vector3, contact: Dictionary, intent: BotIntent, own_speed: float
) -> Vector2:
	if not contact.is_empty():
		var point := _aim_point(contact, eye)
		var to := point - eye
		var distance := Vector2(to.x, to.z).length()
		var bearing := atan2(-to.x, -to.z)
		var truth := Vector2(bearing, asin(clampf(to.normalized().y, -1.0, 1.0)))
		var sweep := absf(angle_difference(_last_bearing, bearing)) / delta
		_last_bearing = bearing
		_step_noise(delta, distance, sweep, own_speed)
		error_degrees = _view_error_degrees(truth)
		var near_enough := error_degrees <= _cone_degrees(distance) * 2.0
		_focus = (
			minf(_focus + delta, FOCUS_SECONDS) if near_enough else maxf(_focus - 2.0 * delta, 0.0)
		)
		return truth + _noise
	if not is_nan(intent.look_yaw):
		return Vector2(intent.look_yaw, 0.0)
	if intent.wish.length() > 0.01:
		return Vector2(atan2(-intent.wish.x, -intent.wish.z), 0.0)
	return Vector2(yaw, pitch)


func _aim_point(contact: Dictionary, eye: Vector3) -> Vector3:
	var look: StringName = contact.get("look", ZombieModels.DEFAULT)
	var scale := ZombieModels.aim_scale(look)
	var at: Vector3 = contact["position"]
	if _weak and ZombieModels.is_boss(look):
		var lens := weak_spot(contact, eye)
		if lens != Vector3.INF:
			return lens
	var apart := Vector2(at.x - eye.x, at.z - eye.z).length()
	var speed := Vector2(contact["velocity"].x, contact["velocity"].z).length()
	var head := _head and speed < HEAD_SPEED and apart < HEAD_RANGE
	return at + Vector3(0.0, (BotLevel.HEAD_HEIGHT if head else BotLevel.CHEST_HEIGHT) * scale, 0.0)


## Where the boss's lens is, or `Vector3.INF` when the boss does not face `eye` enough for the bot
## to see it (the lamp is on its belly).
static func weak_spot(contact: Dictionary, eye: Vector3) -> Vector3:
	var yaw_of: float = contact.get("yaw", 0.0)
	var forward := Vector3(sin(yaw_of), 0.0, cos(yaw_of))
	var at: Vector3 = contact["position"]
	var to_eye := Vector3(eye.x - at.x, 0.0, eye.z - at.z)
	if to_eye.length() < 0.01 or forward.dot(to_eye.normalized()) < WEAK_FACING:
		return Vector3.INF
	var scale := ZombieModels.aim_scale(contact.get("look", ZombieModels.DEFAULT))
	return at + (forward * WEAK_SPOT.z + Vector3.UP * WEAK_SPOT.y) * scale


## Filtered tracking noise, in radians: yaw at full size, pitch at half.
func _step_noise(delta: float, distance: float, sweep: float, own_speed: float) -> void:
	var sigma := _profile.track_error * clampf(distance / 15.0, 0.3, 2.0)
	sigma *= 1.0 + own_speed / 3.0
	sigma *= 1.0 + rad_to_deg(sweep) / 180.0
	sigma *= lerpf(1.0, FOCUS_FLOOR, clampf(_focus / FOCUS_SECONDS, 0.0, 1.0))
	var keep := exp(-delta / NOISE_MEMORY)
	var fresh := sqrt(1.0 - keep * keep) * deg_to_rad(sigma)
	_noise.x = _noise.x * keep + fresh * _rng.randfn()
	_noise.y = _noise.y * keep + fresh * 0.5 * _rng.randfn()


# --- The turn ---


## One step of the spring, then the cap: the view never turns faster than the profile allows.
func _turn(delta: float, wanted: Vector2) -> void:
	var omega := _profile.aim_stiffness
	var yaw_gap := angle_difference(yaw, wanted.x)
	var pitch_gap := clampf(wanted.y, -PITCH_LIMIT, PITCH_LIMIT) - pitch
	_yaw_speed += (omega * omega * yaw_gap - 2.0 * omega * _yaw_speed) * delta
	_pitch_speed += (omega * omega * pitch_gap - 2.0 * omega * _pitch_speed) * delta
	var cap := deg_to_rad(_profile.max_aim_speed)
	var speed := Vector2(_yaw_speed, _pitch_speed)
	if speed.length() > cap:
		speed = speed.normalized() * cap
		_yaw_speed = speed.x
		_pitch_speed = speed.y
	yaw = wrapf(yaw + _yaw_speed * delta, -PI, PI)
	pitch = clampf(pitch + _pitch_speed * delta, -PITCH_LIMIT, PITCH_LIMIT)


func _view_error_degrees(truth: Vector2) -> float:
	var view := Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.FORWARD
	var goal := Basis.from_euler(Vector3(truth.y, truth.x, 0.0)) * Vector3.FORWARD
	return rad_to_deg(view.angle_to(goal))


# --- Legs and trigger ---


## The stick: the wish direction seen from the view (the body walks its own way while the view
## is elsewhere, as a person's does).
func _walk(out: NightCommand, intent: BotIntent) -> void:
	out.motion.jump = intent.jump
	if intent.wish.length() <= 0.01:
		return
	var heading := atan2(-intent.wish.x, -intent.wish.z)
	var apart := yaw - heading
	out.motion.move = Vector2(sin(apart), -cos(apart)) * clampf(intent.pace, 0.0, 1.0)
	out.motion.sprint = intent.sprint


## Whether to hold the trigger: on a target, view inside the hit cone, nothing in the way of the
## gun, and the pauses of the last shot and the last switch over.
func _trigger(me: Dictionary, eye: Vector3, contact: Dictionary, melee_ok: bool = true) -> bool:
	if contact.is_empty() or me.get("reloading", false):
		return false
	var weapon := _weapon_of(me)
	if weapon == null:
		return false
	var distance := Vector2(contact["position"].x - eye.x, contact["position"].z - eye.z).length()
	if weapon.is_melee():
		return melee_ok and distance < MELEE_RANGE
	if int(me.get("ammo", 0)) <= 0 or _retarget_left > 0.0 or _pause_left > 0.0:
		return false
	var limit := PANIC_DEGREES if _panicky else _cone_degrees(distance) * _profile.fire_slop
	if error_degrees > limit:
		return false
	triggers += 1
	return true


# --- Grenades ---


## Whether the view belongs to a throw this tick: one was ordered and is not over (the turn, the
## pin, the arm's swing). The order is taken when it comes and kept: the brain thinks several
## times while the view turns, and each fresh intent would otherwise forget it. The brain stops it
## by setting `throw_abort` while the view is still turning; a turn that takes too long is given up.
func _throwing(intent: BotIntent, delta: float) -> bool:
	match _throw_phase:
		0:
			if intent.throw_style == &"":
				return false
			_throw_phase = 1
			_throw_left = THROW_TURN_SECONDS
			_throw_style = intent.throw_style
			_throw_view = Vector2(intent.throw_yaw, intent.throw_pitch)
			intent.throw_style = &""
		1:
			_throw_left -= delta
			if intent.throw_abort or _throw_left <= 0.0:
				_throw_phase = 0
				return false
		3:
			_throw_left -= delta
			if _throw_left <= 0.0:
				_throw_phase = 0
				return false
	return true


## The throw buttons: held for `THROW_COOK_TICKS` ticks once the view is on the throw's, then let go
## with the view kept still while the arm swings.
func _throw(out: NightCommand) -> void:
	if _throw_phase == 1 and _view_error_degrees(_throw_view) <= THROW_AIM_DEGREES:
		_throw_phase = 2
		_throw_ticks = 0
	if _throw_phase != 2:
		return
	out.motion.throw_under = _throw_style == &"under"
	out.motion.throw_over = _throw_style != &"under"
	_throw_ticks += 1
	if _throw_ticks >= THROW_COOK_TICKS:
		_throw_phase = 3
		_throw_left = THROW_SWING_SECONDS
		throws += 1


func _end_throw() -> void:
	_throw_phase = 0


## The weapon in hand (looked up once per change), or null.
func _weapon_of(me: Dictionary) -> WeaponDef:
	var id: StringName = me.get("weapon", &"")
	if id == &"":
		return null
	if id != _weapon_id:
		_weapon_id = id
		_weapon_def = WeaponCatalog.get_def(id)
	return _weapon_def


## Half the angle the weapon's hit covers at this distance.
static func _cone_degrees(distance: float) -> float:
	return clampf(rad_to_deg(atan2(HIT_RADIUS, maxf(distance, 0.1))), CONE_MIN, CONE_MAX)


# --- Cadence ---


## A shot went off: a short pause before the next, and (an automatic weapon) a longer one after a
## burst of three to five.
func _count_shots(shots: int, automatic: bool) -> void:
	if shots <= _shots_seen:
		_shots_seen = shots
		return
	for _i in shots - _shots_seen:
		_pause_left = _rng.randf() * _profile.fire_jitter
		_panicky = _profile.panic_rate > 0.0 and _rng.randf() < _profile.panic_rate
		if not automatic:
			continue
		if _burst_left <= 0:
			_burst_left = _rng.randi_range(BURST_MIN, BURST_MAX)
		_burst_left -= 1
		if _burst_left <= 0:
			_pause_left += _profile.fire_jitter * 2.0
	_shots_seen = shots


func _tick_timers(delta: float) -> void:
	_retarget_left = maxf(_retarget_left - delta, 0.0)
	_pause_left = maxf(_pause_left - delta, 0.0)

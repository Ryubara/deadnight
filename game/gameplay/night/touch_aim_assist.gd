class_name TouchAimAssist
extends RefCounted
## The touch player's aim help in a night (#286): it feeds `AimAssist` with the zombies the client
## knows and the view the player has, nudges the view, tells the touch layer how much to slow the
## look drag, and says when the trigger should pull itself. It reads only the client's picture of
## the night (`ClientState`), so it runs the same on a local night and on a game server.
##
## It is for touch alone: nothing happens unless the touch layer is up and a finger, not a mouse
## or a pad, was the last input (`UIInputMode.touch`). The assist is the toggle
## `controls/touch_aim_assist` (on is `ON_STRENGTH`); the auto-fire choice is
## `controls/touch_auto_fire` (on by default, the maintainer's decision in #470: while aiming, the
## weapon fires as if Fire were held with the crosshair on a zombie; off, the touch layer makes Aim
## a toggle and the player shoots by hand).

## When the trigger pulls itself with the crosshair on a zombie: never, or while the player aims.
enum AutoFire { OFF, WHILE_AIMING }

const SETTINGS_PATH := ^"/root/Settings"
const ACTION_AIM := &"aim"
const ACTION_FIRE := &"fire"
const MIN_AMMO := 1
## The strength of the assist when the setting is on: the far right of the slider it replaced.
const ON_STRENGTH := 1.0

var tuning := AimAssistTuning.shipped()
## () -> bool, whether the touch layer is up. Without one the assist is off.
var touch_active := Callable()
## 0 (off) or `ON_STRENGTH`; read from the settings. A test may set any value from 0 to 1.
var strength := ON_STRENGTH
var auto_fire: int = AutoFire.WHILE_AIMING

var _tree: SceneTree
var _state: ClientState
var _sight: Callable
var _friction := 1.0
var _on_target := false
var _targets: Array[Dictionary] = []
var _after := Vector2.ZERO
var _has_after := false
var _defs: Dictionary[StringName, WeaponDef] = {}


func _init(tree: SceneTree, state: ClientState, sight: Callable = Callable()) -> void:
	_tree = tree
	_state = state
	_sight = sight
	var service := tree.root.get_node_or_null(SETTINGS_PATH) if tree != null else null
	if service != null and service.has_signal(&"changed"):
		service.connect(&"changed", _on_setting_changed)
	_read_settings()


## True when the help is on right now: touch layer up, a finger the last input, strength above 0.
func is_on() -> bool:
	return strength > 0.0 and is_touch()


## The factor the touch layer puts on a look drag (1 when there is no help).
func friction() -> float:
	return _friction if is_on() else 1.0


## The crosshair is on a zombie as of the last `prepare`.
func is_on_target() -> bool:
	return _on_target


## Once per command, before the controls are read: finds the zombie nearest the crosshair, nudges
## the view toward it while the player aims or fires, and remembers the friction and whether the
## crosshair is on a zombie.
func prepare(player: Player, delta: float) -> void:
	_friction = 1.0
	_on_target = false
	if not is_touch() or _state == null:
		_has_after = false
		return
	_gather_targets()
	if _targets.is_empty():
		_has_after = false
		return
	var rig := player.camera_rig
	var view := rig.aim_transform()
	var eye := view.origin
	var dir := -view.basis.z
	var own_speed := 0.0
	if _has_after and delta > 0.0:
		var turned := Vector2(angle_difference(_after.x, rig.yaw), rig.pitch - _after.y)
		own_speed = turned.length() / delta
	if strength > 0.0:
		var found := AimAssist.pick(eye, dir, _targets, strength, tuning, _sight)
		_friction = AimAssist.friction(found, strength, tuning)
		var helping := Input.is_action_pressed(ACTION_AIM) or Input.is_action_pressed(ACTION_FIRE)
		if helping and not found.is_empty():
			var step := AimAssist.pull(eye, dir, found, strength, own_speed, delta, tuning)
			rig.nudge(step.x, step.y)
	_after = Vector2(rig.yaw, rig.pitch)
	_has_after = true
	if auto_fire != AutoFire.OFF:
		_on_target = AimAssist.on_target(eye, dir, _targets, _fire_reach(), _sight)


## Whether the trigger should be pulled for the player this tick: auto-fire is on, the player aims,
## the crosshair is on a zombie in reach, and the gun can shoot.
func wants_fire() -> bool:
	if auto_fire == AutoFire.OFF or not _on_target or not is_touch():
		return false
	if not Input.is_action_pressed(ACTION_AIM):
		return false
	var me := _state.me()
	if me.get("downed", false) or me.get("reloading", false):
		return false
	var def := _def(me.get("weapon", &""))
	return def != null and (def.is_melee() or int(me.get("ammo", 0)) >= MIN_AMMO)


## The touch layer is up and a finger was the last input.
func is_touch() -> bool:
	return UIInputMode.touch and touch_active.is_valid() and bool(touch_active.call())


## The farthest a zombie may be for the trigger to pull itself: the gun's reach, and no more than
## the tuning allows.
func _fire_reach() -> float:
	var def := _def(_state.me().get("weapon", &""))
	if def == null:
		return 0.0
	var reach := def.melee_range if def.is_melee() else def.max_range
	return minf(reach, tuning.auto_fire_reach)


func _def(weapon: StringName) -> WeaponDef:
	if weapon == &"":
		return null
	if not _defs.has(weapon):
		_defs[weapon] = WeaponCatalog.get_def(weapon)
	return _defs[weapon]


## The living zombies of the last frame, as `AimAssist` wants them.
func _gather_targets() -> void:
	_targets.clear()
	for zombie in _state.zombies:
		if int(zombie.get("mode", 0)) == ZombieBody.Mode.DYING:
			continue
		var look: StringName = zombie.get("look", ZombieModels.DEFAULT)
		var mode: int = zombie.get("mode", ZombieBody.Mode.CHASE)
		var yaw: float = zombie.get("yaw", 0.0)
		var target := {
			"position": zombie["position"],
			"yaw": yaw,
			"scale": ZombieModels.height_of(look),
			"aim_scale": ZombieModels.aim_scale(look),
			"pose": ZombiePose.hit_set(look, mode, false, 0.0, zombie.get("climbing", false)),
		}
		_targets.append(target)


func _read_settings() -> void:
	var service := _tree.root.get_node_or_null(SETTINGS_PATH) if _tree != null else null
	if service == null or not service.has_method(&"get_value"):
		return
	var level: Variant = service.call(&"get_value", &"controls/touch_aim_assist")
	if level is bool:
		strength = ON_STRENGTH if level else 0.0
	var mode: Variant = service.call(&"get_value", &"controls/touch_auto_fire")
	if mode is int:
		# A saved 2 ("always", gone with #470) counts as on.
		auto_fire = AutoFire.WHILE_AIMING if mode >= 1 else AutoFire.OFF


func _on_setting_changed(_key: StringName, _value: Variant) -> void:
	_read_settings()

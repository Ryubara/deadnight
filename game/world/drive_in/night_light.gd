class_name NightLight
extends Node
## The night closing in: the lot's ambient light, moon, sky and fog follow the round. The rules say
## how light the night is (`RoundTuning.ambient_for_round`, 0.60 in round 1 falling to 0.15); this
## reads it from the events the client hears, so a client of any kind does the same and the server
## draws nothing. Round 1 is the look the generator wrote (`docs/research/night-environment.md`);
## each later round scales the scene's own numbers toward the `darkest_*` fractions of
## `LightTuning` (`light_tuning_default.tres`; the player's shadow side and the dead at 25 m still
## read at the shipped ones), so the lamps' pools, which are lights and quads of their own, hold
## while the field around them sinks. The change begins when the break announces the next round
## and eases in over `ease_seconds`, so nothing pops. Compatibility only: an `Environment` energy,
## a fog density and one light energy.

## The eased light level now, in the rules' units (`ambient_for_round`: 1 is day).
var level: float
## The round the level is heading for, 0 until one is heard.
var round_target := 0

var _rounds: RoundTuning
var _environment: Environment
var _moon: DirectionalLight3D
var _base_ambient: float
var _base_moon: float
var _base_fog_density: float
var _from: float
var _to: float
var _elapsed := LightTuning.current().ease_seconds


## Follows `lighting` (the lot's `Lighting` node) by the round `state` hears.
func _init(lighting: Node3D, rounds: RoundTuning, state: ClientState = null) -> void:
	name = "NightLight"
	_rounds = rounds
	var world := lighting.get_node("WorldEnvironment") as WorldEnvironment
	# A scene's resources are shared by every copy of it: this night darkens its own.
	_environment = world.environment.duplicate() as Environment
	world.environment = _environment
	_moon = lighting.get_node("Moon") as DirectionalLight3D
	_base_ambient = _environment.ambient_light_energy
	_base_moon = _moon.light_energy
	_base_fog_density = _environment.fog_density
	level = rounds.ambient_start
	_from = level
	_to = level
	_apply()
	if state != null:
		state.event_received.connect(on_event)


## The round the events name, and nothing else of the night.
func on_event(event: Dictionary) -> void:
	match event["type"]:
		&"break_started":
			_head_for(event["next_round"])
		&"round_started":
			_head_for(event["round"])
		&"frame":
			# A client that joins late has heard no round yet: it starts there, with no ease.
			if round_target == 0:
				_head_for(event["round"], true)


## Moves the level on by `delta` seconds.
func advance(delta: float) -> void:
	_elapsed = minf(_elapsed + delta, LightTuning.current().ease_seconds)
	level = lerpf(_from, _to, smoothstep(0.0, 1.0, _elapsed / LightTuning.current().ease_seconds))
	_apply()


## 0 in round 1 (the scene as built) to 1 at the darkest round, from the level now.
func darkness() -> float:
	var span := _rounds.ambient_start - _rounds.ambient_min
	if span <= 0.0:
		return 0.0
	return clampf((_rounds.ambient_start - level) / span, 0.0, 1.0)


func _process(delta: float) -> void:
	advance(delta)


func _head_for(round_number: int, snap: bool = false) -> void:
	if round_number < 1 or round_number == round_target:
		return
	var first := round_target == 0
	round_target = round_number
	_from = level
	_to = _rounds.ambient_for_round(round_number)
	_elapsed = LightTuning.current().ease_seconds if (snap or first) else 0.0
	advance(0.0)


func _apply() -> void:
	var dark := darkness()
	var tuning := LightTuning.current()
	_environment.ambient_light_energy = _base_ambient * lerpf(1.0, tuning.darkest_ambient, dark)
	_moon.light_energy = _base_moon * lerpf(1.0, tuning.darkest_moon, dark)
	var sky := lerpf(1.0, tuning.darkest_sky, dark)
	_environment.background_energy_multiplier = sky
	_environment.fog_light_energy = sky
	_environment.fog_density = _base_fog_density * lerpf(1.0, tuning.darkest_fog_density, dark)

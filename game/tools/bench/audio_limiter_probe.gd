extends Node
## Does a limiter on the Master bus act where the sounds are played (#718)? Fires the tommy gun
## without a break through the audio service in four phases of `BURST` seconds each: with nothing
## on the buses; with a hard limiter on Master (ceiling `CEILING_DB`, lower than the gun's own
## peak); with the limiter taken off again; and with Master turned down `TURN_DOWN_DB` (the
## control: bus volume works in every build). A browser run (`tools/web_smoke/limiter_web.py`)
## plays sounds as samples; the limiter's phase tells whether the effect is heard there. Prints
## `PHASE <name> <seconds>` as each starts (seconds as the sum of the frames' deltas, which is
## the movie's own time under Movie Maker).

const BURST := 2.0
const GAP := 1.5
const CEILING_DB := -9.0
const TURN_DOWN_DB := -9.0
const SOUND := &"shot_smg"

var _phases: Array[StringName] = [&"plain", &"limiter", &"plain_again", &"master_down"]
var _t := 0.0
var _phase := -1
var _next_shot := 0.0
var _interval := 0.075


func _ready() -> void:
	Audio.seed_random(718)
	var listener := Camera3D.new()
	add_child(listener)
	listener.make_current()
	Audio.listener = listener
	_interval = WeaponCatalog.get_def(&"smg").fire_interval


func _process(delta: float) -> void:
	_t += delta
	var slot := BURST + GAP
	var index := int(_t / slot)
	var local := _t - index * slot
	if index >= _phases.size():
		print("END")
		get_tree().quit()
		return
	if index != _phase:
		_phase = index
		_next_shot = 0.0
		_enter(_phases[index])
	# One shot a frame at most: a slow frame (a browser loading) must not play a pile of them at once.
	if local < BURST and _next_shot <= local:
		Audio.play(SOUND, null, 0.0)
		_next_shot = maxf(_next_shot + _interval, local)


func _enter(phase: StringName) -> void:
	var master := AudioServer.get_bus_index(&"Master")
	match phase:
		&"limiter":
			var limiter := AudioEffectHardLimiter.new()
			limiter.ceiling_db = CEILING_DB
			AudioServer.add_bus_effect(master, limiter)
		&"plain_again":
			AudioServer.remove_bus_effect(master, 0)
		&"master_down":
			AudioServer.set_bus_volume_db(master, TURN_DOWN_DB)
	print("PHASE %s %.3f" % [phase, _t])

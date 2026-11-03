class_name RecutLayer
extends Node
## What an upgraded weapon adds to its shot: a short futuristic layer (a sweep, a ring and a sub
## pulse, `tools/audio/energy_recipes.py`) that plays over the report of **any** re-cut weapon, so
## every weapon of the roster sounds upgraded without a recipe each (#791, the numbers in
## `docs/research/gun-audio.md#the-energy-weapons-and-the-re-cut-layer-791`). Made only from what
## the server sent, like `WeaponSounds`: a `shot_fired` event plays the layer when the shooter's
## frame says the weapon has been re-cut (`arms`: weapon id to `[ammo, reserve, tier]`, tier above
## 0 after the bench). A melee swing and a flare's launch are shots too. Nothing here is a bus
## effect: the web build plays samples, so the layer is a sound of its own on its own voice.
##
## A weapon whose re-cut has an element (#785: explosive rounds, shock, fire) adds that element's
## accent over the shared layer: the two play together (`ELEMENT_LAYERS`, `WEAPON_ELEMENTS`). The
## wonder weapons have no element.

## The layer of every re-cut weapon but the wonder weapons.
const DEFAULT_LAYER := &"recut_layer"
## The layer of the wonder weapons, whose shots are already full of sweeps and glass in the
## bright band where the shared layer would be lost: the same idea an octave and a half lower.
## They have no element.
const WONDER_LAYER := &"recut_deep"
const WONDER_WEAPONS: Array[StringName] = [&"ray_gun", &"freeze_gun"]
## The accent of each element: the explosive rounds' is a dull crump and scattered debris, the
## shock's an arc, the fire's an ember whoosh with spitting sparks.
const ELEMENT_LAYERS := {
	&"explosive": &"recut_blast",
	&"shock": &"recut_shock",
	&"fire": &"recut_fire",
}
## The elements the weapons' re-cuts carry (weapon id to element), as the roster's design has them:
## the revolver's explosive rounds, the dual pistols' shock arc, the pump 870's burning and the
## flare gun's burning ground. A weapon not in the catalogue yet does no harm here.
const WEAPON_ELEMENTS := {
	&"pistol": &"explosive",
	&"dual_pistols": &"shock",
	&"pump_870": &"fire",
	&"flare_gun": &"fire",
}
## The layer's level wanders by up to this much from play to play. How often it can play is the
## sound's own cooldown (an automatic weapon at twelve shots a second plays a layer every other
## shot: a layer is a ring, not a rattle).
const LEVEL_JITTER_DB := 0.5

## `Callable(id: StringName, at: Variant, extra_db: float)`; the audio service unless a test
## listens instead.
var play := Callable()
## Weapon id to element, for a weapon that has one; the shipped table by default.
var elements: Dictionary = WEAPON_ELEMENTS.duplicate()

var _state: ClientState
var _rng := RandomNumberGenerator.new()


## The sounds a re-cut `weapon_id` plays over its shot: the shared layer (the wonder weapons'
## own), and its element's accent when it has one.
static func layers_for(
	weapon_id: StringName, table: Dictionary = WEAPON_ELEMENTS
) -> Array[StringName]:
	var layers: Array[StringName] = [WONDER_LAYER if weapon_id in WONDER_WEAPONS else DEFAULT_LAYER]
	var accent: StringName = ELEMENT_LAYERS.get(table.get(weapon_id, &""), &"")
	if accent != &"":
		layers.append(accent)
	return layers


func setup(state: ClientState, seed_value := 791) -> void:
	_state = state
	_rng.seed = seed_value
	state.event_received.connect(_on_event)


## Whether `player_id`'s `weapon_id` has been re-cut, as the latest frame says.
func is_recut(player_id: int, weapon_id: StringName) -> bool:
	var player: Dictionary = _state.frame.get("players", {}).get(player_id, {})
	var arms: Dictionary = player.get("arms", {})
	var held: Variant = arms.get(weapon_id)
	return held is Array and held.size() > 2 and int(held[2]) > 0


func _on_event(event: Dictionary) -> void:
	if event["type"] != &"shot_fired":
		return
	var weapon_id: StringName = event["weapon_id"]
	var shooter_id: int = event["shooter_id"]
	if not is_recut(shooter_id, weapon_id):
		return
	# Like the guns: the shooter's own layer is in their hands (flat), a stranger's comes from the
	# muzzle.
	var heard_at: Variant = null if shooter_id == _state.player_id else event["muzzle"]
	for sound in layers_for(weapon_id, elements):
		var extra_db := _rng.randf_range(-LEVEL_JITTER_DB, LEVEL_JITTER_DB)
		if play.is_valid():
			play.call(sound, heard_at, extra_db)
		else:
			Audio.play(sound, heard_at, extra_db)

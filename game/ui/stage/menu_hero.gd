class_name MenuHero
extends Node3D
## The player's soldier on the menu's stage: the saved look and the showcase weapon at the low
## ready. Built with the same assembler the wardrobe and the night use, and the weapon is put in the
## hands by `HeldWeapon`, the one builder of the night's `PlayerAnimation` too: the weapon's own
## hold, its solved grip, the arms' pose and the fingers on it. The menu has no hand placement of
## its own, so what it shows is how the night holds the weapon (Deadnight #621).

## Metres per unit of the model: the same scale as the player's body.
const MODEL_SCALE := 0.8
## The body's clip under a carried gun: the arms are the hand pose's.
const FALLBACK_CLIP := &"Idle"

## Where the carried gun points, as the night's aim does: the pitch the view gives it (radians
## below the level) and a turn across the body. The hold's own rise and stance come on top of it.
const LOW_READY_PITCH := 0.04
const LOW_READY_TURN := 0.0
## The weapon shown when the saved one has no model.
const DEFAULT_WEAPON := &"rifle"

## The look on the soldier now.
var look: CharacterLook
var model: Node3D
var weapon: Node3D
var weapon_id := &""

var _player: AnimationPlayer
## The weapon in the hands and the nodes that pose them (`HeldWeapon`: the night's builder).
var _held: HeldWeapon


## The weapons that can be shown: those the night puts in a hand today (`WeaponHoldMap.hold_for`:
## the weapon's own model), so a weapon gets onto the list by getting its model, not by a change
## here.
static func available() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in WeaponCatalog.IDS:
		if WeaponHoldMap.hold_for(id) != null:
			out.append(id)
	return out


## The saved showcase weapon, or the default when it is gone or has no model.
static func saved_weapon() -> StringName:
	var id := StringName(Settings.get_value(SettingsService.SHOWCASE_WEAPON))
	return id if id in available() else DEFAULT_WEAPON


## Dresses the soldier in `look` (the armband of `seat`) holding the weapon `id`.
func show_look(worn: CharacterLook, id: StringName, seat := 0) -> void:
	look = worn
	if model != null:
		remove_child(model)
		model.queue_free()
	model = CharacterAssembler.assemble(worn, seat)
	model.scale = Vector3.ONE * MODEL_SCALE
	add_child(model)
	_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	hold(id)


## Puts the weapon `id` in the hands and the matching ready pose on the body.
func hold(id: StringName) -> void:
	weapon_id = id
	if _held != null:
		_held.release()
		_held = null
	weapon = null
	var weapon_class := WeaponHoldMap.class_of(id)
	var hold_data := WeaponHoldMap.hold_for(id)
	# A gun is carried by the game's own hand pose over the idle; a melee weapon keeps the arm of
	# its aim clip, as in the night.
	var carried := hold_data != null and hold_data.shouldered
	var clip := FALLBACK_CLIP if carried else StringName("Aim_%s" % weapon_class)
	if not _player.has_animation(clip):
		clip = FALLBACK_CLIP
	_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_player.play(clip)
	if hold_data == null:
		return
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	_held = HeldWeapon.new(skeleton)
	weapon = _held.hold_weapon(weapon_class, hold_data)
	_held.close_hands()
	_held.hands.active = carried
	_held.hands.aim_pitch = LOW_READY_PITCH


## Steps the idle by `delta` seconds.
func advance(delta: float) -> void:
	if _player != null:
		_player.advance(delta)
	if _held != null:
		# The hand pose aims in the world: forward is the soldier's own front (+Z), plus the turn.
		_held.hands.aim_yaw = global_rotation.y + PI + LOW_READY_TURN

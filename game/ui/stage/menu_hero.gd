class_name MenuHero
extends Node3D
## The player's soldier on the menu's stage: the saved look and the showcase weapon, in the class's
## ready pose (the `Aim_<Class>` clip, which already holds the weapon in the hands). Built with the
## same assembler and weapon mount the wardrobe and the night use, so what the menu shows is what
## the night will.

## Metres per unit of the model: the same scale as the player's body.
const MODEL_SCALE := 0.8
## The pose clip of a weapon class when it has none of its own.
const FALLBACK_CLIP := &"Idle"

## How far the carried gun is lowered (radians below the level) and turned across the body.
const LOW_READY_PITCH := 0.04
const LOW_READY_TURN := 0.0
## The weapon shown when the saved one has no model.
const DEFAULT_WEAPON := &"rifle"

var model: Node3D
var weapon: Node3D
var weapon_id := &""

var _player: AnimationPlayer
var _mount: BoneAttachment3D
var _hands: WeaponHandsIK


## The weapons that can be shown: those whose class has a model in the hand today, so a weapon
## gets onto the list by getting its model, not by a change here.
static func available() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in WeaponCatalog.IDS:
		if PlayerAnimation.hold_of(WeaponHoldMap.class_of(id)) != null:
			out.append(id)
	return out


## The saved showcase weapon, or the default when it is gone or has no model.
static func saved_weapon() -> StringName:
	var id := StringName(Settings.get_value(SettingsService.SHOWCASE_WEAPON))
	return id if id in available() else DEFAULT_WEAPON


## Dresses the soldier in `look` (the armband of `seat`) holding the weapon `id`.
func show_look(look: CharacterLook, id: StringName, seat := 0) -> void:
	if model != null:
		remove_child(model)
		model.queue_free()
	model = CharacterAssembler.assemble(look, seat)
	model.scale = Vector3.ONE * MODEL_SCALE
	add_child(model)
	_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	hold(id)


## Puts the weapon `id` in the hands and the matching ready pose on the body.
func hold(id: StringName) -> void:
	weapon_id = id
	if _mount != null:
		_mount.queue_free()
		_mount = null
	weapon = null
	if _hands != null:
		_hands.queue_free()
		_hands = null
	var weapon_class := WeaponHoldMap.class_of(id)
	var hold_data := PlayerAnimation.hold_of(weapon_class)
	# A gun is carried at the low ready by the game's own hand pose (`WeaponHandsIK`) over the idle;
	# a melee weapon keeps the arm of its aim clip.
	var carried := hold_data != null and hold_data.shouldered
	var clip := FALLBACK_CLIP if carried else StringName("Aim_%s" % weapon_class)
	if not _player.has_animation(clip):
		clip = FALLBACK_CLIP
	_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_player.play(clip)
	if hold_data == null:
		return
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	_mount = BoneAttachment3D.new()
	_mount.name = "WeaponMount"
	_mount.bone_name = PlayerAnimation.HAND_BONE
	skeleton.add_child(_mount)
	weapon = (load(hold_data.scene) as PackedScene).instantiate() as Node3D
	var grip := PlayerAnimation.HOLD_MELEE if weapon_class == &"Melee" else PlayerAnimation.HOLD_GUN
	weapon.transform = grip.scaled_local(Vector3.ONE * hold_data.model_scale)
	_mount.add_child(weapon)
	if carried:
		_hands = WeaponHandsIK.new()
		_hands.name = "WeaponHandsIK"
		_hands.hold = hold_data
		_hands.hand_hold = PlayerAnimation.HOLD_GUN
		_hands.aim_pitch = LOW_READY_PITCH
		skeleton.add_child(_hands)


## Steps the idle by `delta` seconds.
func advance(delta: float) -> void:
	if _player != null:
		_player.advance(delta)
	if _hands != null:
		# The hand pose aims in the world: forward is the soldier's own front (+Z), plus the turn.
		_hands.aim_yaw = global_rotation.y + PI + LOW_READY_TURN

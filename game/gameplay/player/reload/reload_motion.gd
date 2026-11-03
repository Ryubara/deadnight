class_name ReloadMotion
extends Resource
## How one firearm reloads, so it reads from the shoulder camera and on another player's screen
## (#683): the weapon comes down and turns to show its working side, the left hand goes to the
## part, to the belt for ammunition and back, the part (a drum, the barrels, a cylinder, a lever)
## moves, and the steps the sounds play on. One file per weapon, `reload/<weapon id>.tres`,
## stretched over the weapon's own reload time; `WeaponHandsIK` poses the arms on the weapon's
## solved grip from it and `PlayerAnimation` moves the part and the ammunition
## (docs/design/animation.md, Reloading).

const DIR := "res://gameplay/player/reload/"

static var _cache: Dictionary = {}

## The reload's kind, for the docs and the tests: magazine, break_open, lever, revolver.
@export var mechanism: StringName = &""
## The weapon's moving part: a node of its model (made in Blender at its pivot:
## tools/blender/build_weapons.py, `NODES`), or empty for none.
@export var part_node: StringName = &""
## The part's turn when fully open: degrees about `part_axis` (the model's own axes, through the
## part's pivot), and its slide in the model's units.
@export var part_axis := Vector3.FORWARD
@export_range(-180.0, 180.0, 0.5, "suffix:deg") var part_turn := 0.0
@export var part_slide := Vector3.ZERO
## What the left hand brings from the belt (a glb beside the weapon's), and where it sits on the
## left hand's bone (metres and degrees in the bone's space, at the Soldier's size).
@export_file("*.glb") var ammo_scene := ""
@export var ammo_offset := Vector3.ZERO
@export var ammo_turn := Vector3.ZERO
## How many times the gun's size the ammunition is drawn: the kit's hands are two to three times a
## person's (docs/design/weapon-hold.md), and a shell at the gun's size vanishes in the fist.
@export_range(0.5, 3.0, 0.05) var ammo_size := 1.5
## The ammunition is the part itself (the drum): the hand takes the part where it is.
@export var ammo_is_part := false
## A reload that loads one round at a time (`WeaponDef.reload_by_round`, #793): the timeline below
## is a full reload of `loop_rounds` rounds, and from `loop_from` to `loop_to` it is that many
## identical cycles, one per round. A reload of fewer rounds plays the lead-in, that many cycles
## and the lead-out (`playhead`); `loop_rounds` 0 is an ordinary reload.
@export_range(0, 12) var loop_rounds := 0
@export_range(0.0, 1.0, 0.005) var loop_from := 0.0
@export_range(0.0, 1.0, 0.005) var loop_to := 0.0
## The poses, in order of `at`; the first should be at 0 and the last at 1, both the hold's own.
@export var keys: Array[ReloadKey] = []
## The steps that sound: event name to the shares of the reload it happens at
## (`WeaponSounds.RELOAD` gives each event its sound).
@export var events: Dictionary[StringName, PackedFloat32Array] = {}


## The motion of a weapon id, or null for a weapon that does not reload.
static func for_weapon(weapon_id: StringName) -> ReloadMotion:
	if _cache.has(weapon_id):
		return _cache[weapon_id]
	var path := DIR + String(weapon_id) + ".tres"
	var motion: ReloadMotion = load(path) as ReloadMotion if ResourceLoader.exists(path) else null
	_cache[weapon_id] = motion
	return motion


## The shares of the reload at which `event` happens (empty for none).
func event_shares(event: StringName) -> PackedFloat32Array:
	return events.get(event, PackedFloat32Array())


## Whether the reload is a loop of one cycle a round (`loop_rounds`).
func is_by_round() -> bool:
	return loop_rounds > 0 and loop_to > loop_from


## The share of the full timeline that a reload of `rounds` rounds is at `share` of its own time:
## the lead-in, the first `rounds` cycles, then the lead-out after the cycles that were cut.
func playhead(share: float, rounds: int) -> float:
	if not is_by_round() or rounds <= 0 or rounds >= loop_rounds:
		return share
	var cut := _cycle() * float(loop_rounds - rounds)
	var total := 1.0 - cut
	var at := share * total
	return at if at <= loop_to - cut else at + cut


## The shares of a reload of `rounds` rounds at which `event` happens: the full timeline's, with
## the events of the cut cycles gone and the rest squeezed into the shorter reload.
func event_shares_for(event: StringName, rounds: int) -> PackedFloat32Array:
	var shares := event_shares(event)
	if not is_by_round() or rounds <= 0 or rounds >= loop_rounds:
		return shares
	var cut := _cycle() * float(loop_rounds - rounds)
	var kept := PackedFloat32Array()
	for share in shares:
		if share <= loop_to - cut:
			kept.append(share / (1.0 - cut))
		elif share >= loop_to:
			kept.append((share - cut) / (1.0 - cut))
	return kept


func _cycle() -> float:
	return (loop_to - loop_from) / float(loop_rounds)


## The pose at `share` of the reload (0 to 1), written into `out`.
func sample(share: float, out: ReloadPose) -> void:
	out.motion = self
	if keys.is_empty():
		out.clear()
		return
	share = clampf(share, 0.0, 1.0)
	var i := 0
	while i < keys.size() - 2 and share >= keys[i + 1].at:
		i += 1
	var a := keys[i]
	var b := keys[mini(i + 1, keys.size() - 1)]
	var span := b.at - a.at
	var t := 1.0 if span <= 0.0 else smoothstep(0.0, 1.0, (share - a.at) / span)
	if share < a.at:
		t = 0.0
	out.weapon_offset = a.weapon_offset.lerp(b.weapon_offset, t)
	out.weapon_turn = a.weapon_turn.lerp(b.weapon_turn, t)
	out.chest_lean = lerpf(a.chest_lean, b.chest_lean, t)
	out.chest_turn = lerpf(a.chest_turn, b.chest_turn, t)
	out.part = lerpf(a.part, b.part, t)
	out.part_shown = a.part_shown if t < 1.0 else b.part_shown
	out.ammo = a.ammo if t < 1.0 else b.ammo
	out.left = lerpf(a.left, b.left, t)
	# The hand travels between two points it holds; from or to the hold's own it stays on the
	# point and the weight carries it.
	if a.left > 0.0 and b.left > 0.0:
		out.left_from = a
		out.left_to = b
		out.left_mix = t
	elif b.left > 0.0:
		out.left_from = b
		out.left_to = b
		out.left_mix = 0.0
	elif a.left > 0.0:
		out.left_from = a
		out.left_to = a
		out.left_mix = 0.0
	else:
		out.left_from = null
		out.left_to = null
		out.left_mix = 0.0


## The part's transform under its rest (the model's units) at `amount` open.
func part_transform(rest: Transform3D, amount: float) -> Transform3D:
	var turn := Basis(part_axis.normalized(), deg_to_rad(part_turn * amount))
	return Transform3D(rest.basis * turn, rest.origin + part_slide * amount)


## Where a point given on the part (the model's units, the part closed) is with the part `amount`
## open, `rest` being the part's place in the model.
func point_on_part(point: Vector3, rest: Transform3D, amount: float) -> Vector3:
	return part_transform(rest, amount) * (rest.affine_inverse() * point)

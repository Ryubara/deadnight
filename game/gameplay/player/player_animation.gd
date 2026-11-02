# gdlint: disable=max-public-methods
class_name PlayerAnimation
extends AnimationTree
## Drives the Soldier's clips (docs/design/animation.md is the spec) from the player's movement.
##
## The tree is built here, in code, so the clip names live in one place:
##   body:  locomotion (Idle / Walk / Run blended by speed; the Run end plays at ground speed /
##          run_clip_speed so the feet do not slide; while aiming, Walk_Shoot / Walk_Back /
##          Strafe_Left / Strafe_Right blended by the direction of travel, from their own file),
##          and jump -> fall -> land -> locomotion.
##   upper: the class's Aim_<Class> loop, or while sprinting on the ground its Sprint_<Class>
##          carry (its own file, played at the Run clip's time so the swing lands on the
##          footfalls), with a OneShot on top (Fire, Reload, Swing, Equip, Unequip), laid over the
##          body by a Blend2 filtered to the upper bones.
##   repair: Repair_Board looping over the upper layer while the player puts boards back at a
##          breach (its own file, added to the library here), timed by the rules' events.
##   downed: kneeling at a revive, or down, over all of that (DownedPose, #504).
##   full:  a full-body OneShot over both (HitReact, Death).
## Loops, the upper bones and the event frames come from clips.json, written by the build script.

signal clip_event(clip: StringName, event: StringName)

const SPEC := "res://assets/characters/soldier/clips.json"
## Kit clips the spec does not list but the jump uses as a loop.
const KIT_LOOPS := ["Jump_Idle"]
const HAND_BONE := "Index1.R"
## The weapon scene's transform under a BoneAttachment3D on HAND_BONE, measured on the built
## Soldier (docs/design/animation.md, "Weapons in the hand").
const HOLD_GUN := Transform3D(
	Basis(
		Vector3(-0.062527, -0.997926, -0.015303),
		Vector3(0.118606, -0.022655, 0.992683),
		Vector3(-0.990971, 0.060254, 0.119776)
	),
	Vector3(-0.039563, 0.197228, -0.070351)
)
const HOLD_MELEE := Transform3D(
	Basis(
		Vector3(-0.438017, -0.897818, 0.045446),
		Vector3(-0.898861, 0.436628, -0.037496),
		Vector3(0.013822, -0.057274, -0.998263)
	),
	Vector3(-0.004282, 0.175673, -0.062554)
)
## The hold of each class that shows a weapon (Pistol has no model yet: the hand stays empty):
## the model, its size and where it rests (holds/*.tres, docs/design/weapon-hold.md).
const HOLDS_DIR := "res://gameplay/player/holds/"
## The node every firearm model carries at the tip of its barrel, `-Z` out of the barrel.
const MUZZLE_NODE := "Muzzle"
const HOLD_CLASSES: Array[StringName] = [&"Rifle", &"Shotgun", &"Melee"]
## How fast the arms go to and from the shouldered pose (per second, exponential).
const SHOULDER_RATE := 14.0
## Recoil of a shot dies away at this rate (per second, exponential).
const RECOIL_RATE := 16.0
## How fast the tilt of a reload follows its curve, per second: a cancelled reload (a swap) lets the
## weapon back up in a few frames instead of jumping.
const RELOAD_FOLLOW := 30.0
## The claw hammer the repair puts in the right hand in place of the weapon, on the same mount.
## Its hold file sizes it (a tool, larger than the size rule: docs/design/weapon-hold.md); the
## grip is the melee one tipped 20 degrees in the hammer's swing plane (about its Z), so the face
## meets the board square on the blow (docs/design/animation.md, Repair).
const HAMMER_HOLD := "res://gameplay/player/holds/hammer.tres"
const HOLD_HAMMER := Transform3D(
	Basis(
		Vector3(-0.719030, -0.694337, 0.029881),
		Vector3(-0.694842, 0.717368, -0.050778),
		Vector3(0.013822, -0.057274, -0.998263)
	),
	Vector3(-0.004282, 0.175673, -0.062554)
)
## The node the hammer model carries at the centre of its striking face, -Z out of the face
## (docs/design/style.md, "Attachment points").
const HAMMER_FACE := "Face"
const CLASSES: Array[StringName] = [&"Rifle", &"Shotgun", &"Pistol", &"Melee"]
const DEFAULT_CLASS := &"Rifle"
## Where Walk sits on the move blend (0 = Idle, 1 = Run).
const WALK_POINT := 0.45
## The repair clip, built into its own file (docs/design/animation.md, Repair) and added to the
## Soldier's library when the tree is built.
const REPAIR_GLB := "res://assets/characters/soldier/repair/soldier_repair.glb"
const REPAIR_SPEC := "res://assets/characters/soldier/repair/clips.json"
const REPAIR_CLIP := &"Repair_Board"
## The event the board lands on: the blow that knocks a board home. Each `board_repaired` of this
## player puts the clip `REPAIR_KNOCK` seconds before it, and the loop emits it once per board.
const REPAIR_SET_EVENT := "board_set"
## A board put back slides in and knocks home this long after its `board_repaired` (the
## barricade's mend): the fist comes down on it then, not at the event (#245).
const REPAIR_KNOCK := Barricade.MEND_SECONDS
## How many repair intervals the clip keeps going after the last board went up: a held `use`
## mends the next one an interval later, so it only stops once one is missed.
const REPAIR_HOLD := 1.5
## How fast the repair layer fades in and out (per second, exponential).
const REPAIR_BLEND_RATE := 18.0
const REPAIR_SEEK_PARAMETER := &"parameters/repair_seek/seek_request"
const REPAIR_SCALE_PARAMETER := &"parameters/repair_scale/scale"
const REPAIR_BLEND_PARAMETER := &"parameters/repair/blend_amount"
## Moving while aiming (#74): one gait turned four ways, built into its own file
## (docs/design/animation.md, Moving while aiming) and added to the Soldier's library. Each clip's
## direction of travel in the blend space: x to the Soldier's right, y ahead.
const AIM_MOVE_GLB := "res://assets/characters/soldier/aim_move/soldier_aim_move.glb"
const AIM_MOVE_SPEC := "res://assets/characters/soldier/aim_move/clips.json"
const AIM_MOVES := {
	&"Walk_Shoot": Vector2(0.0, 1.0),
	&"Walk_Back": Vector2(0.0, -1.0),
	&"Strafe_Left": Vector2(-1.0, 0.0),
	&"Strafe_Right": Vector2(1.0, 0.0),
}
## The aim gait is fully in by this share of its clips' ground speed (Idle blends in below it).
const AIM_MOVE_FULL := 0.4
## How slow or fast the aim gait is played to fit the ground (outside it the feet slide).
const AIM_RATE_MIN := 0.5
const AIM_RATE_MAX := 1.6
const AIM_MOVE_PARAMETER := &"parameters/body/locomotion/aim_move/blend_position"
const AIM_RATE_PARAMETER := &"parameters/body/locomotion/aim_rate/scale"
const AIM_BLEND_PARAMETER := &"parameters/body/locomotion/aim_blend/blend_amount"
## The sprint carry (#459): an upper-body loop per class on the kit Run's 17 frames, built into its
## own file (docs/design/animation.md, Sprint carry) and added to the Soldier's library. It is
## seeked to the Run clip's place every frame, so the two never drift apart (names: SprintCarry).
const SPRINT_GLB := "res://assets/characters/soldier/sprint/soldier_sprint.glb"
const SPRINT_SPEC := "res://assets/characters/soldier/sprint/clips.json"
const CARRY_BLEND_PARAMETER := &"parameters/carry/blend_amount"
const CARRY_SEEK_PARAMETER := &"parameters/carry_seek/seek_request"
const RUN_POSITION_PARAMETER := &"parameters/body/locomotion/move/run/current_position"
const RUN_DELTA_PARAMETER := &"parameters/body/locomotion/move/run/current_delta"

## The grenade's clips, a file of their own on the same rig (`docs/design/animation.md`, Grenade):
## the pin and the cooking hold, the overarm throw and the underarm toss. Upper body, so the legs
## keep running under them.
const GRENADE_GLB := "res://assets/characters/soldier/grenade/soldier_grenade.glb"
const GRENADE_SPEC := "res://assets/characters/soldier/grenade/clips.json"
const GRENADE_COOK := &"Grenade_Cook"
const GRENADE_THROW := &"Grenade_Throw"
const GRENADE_TOSS := &"Grenade_Toss"
const GRENADE_CLIPS: Array[StringName] = [GRENADE_COOK, GRENADE_THROW, GRENADE_TOSS]
## The cook clip's first event: the gun goes down, the grenade is in the hand.
const GRENADE_TAKEN_EVENT := "grenade_visible"
## The throw clips' last event: the arm is back, the gun comes up again.
const GRENADE_DONE_EVENT := "done"
## The throw clips' release frame: the grenade leaves the hand.
const GRENADE_RELEASE_EVENT := "release"
## How long the cook clip holds its last frame while the button is down (more than any fuse).
const GRENADE_COOK_HOLD := 30.0
## The grenade in the hand: its hold file (model, size: docs/design/weapon-hold.md) and grip file.
const GRENADE_HOLD := "res://gameplay/player/holds/grenade.tres"
const GRENADE_GRIP := "grenade"
## How fast the fingers go to and from a grip (per second, exponential).
const GRIP_RATE := 20.0

const STATE_LOCOMOTION := &"locomotion"
const STATE_JUMP := &"jump"
const STATE_FALL := &"fall"
const STATE_LAND := &"land"
## Crouched: the kit's Duck clip held at its lowest pose, with some of the Walk laid over it while
## the body moves (the kit has no crouch walk).
const STATE_CROUCH := &"crouch"
const CROUCH_MIX_PARAMETER := &"parameters/body/crouch/mix/blend_amount"
const CROUCH_RATE_PARAMETER := &"parameters/body/crouch/walk_rate/scale"
## Seconds of the Duck clip looped around its lowest pose to hold it.
const DUCK_HOLD := 0.1
## The slowest the Walk steps under the Duck pose, as a share of its own pace.
const CROUCH_WALK_RATE_MIN := 0.5
const MOVE_PARAMETER := &"parameters/body/locomotion/move/blend_position"
const RUN_SPEED_PARAMETER := &"parameters/body/locomotion/run_speed/scale"

var weapon_class: StringName = DEFAULT_CLASS
## The clip the upper OneShot is playing, or &"" when none.
var action_clip: StringName = &""

var _player: Player
var _tuning: PlayerTuning
var _spec: Dictionary = {}
var _playback: AnimationNodeStateMachinePlayback
var _aim_node: AnimationNodeAnimation
var _action_node: AnimationNodeAnimation
var _full_node: AnimationNodeAnimation
var _mount: BoneAttachment3D
var _weapon: Node3D
var _hammer: Node3D
var _grenade: Node3D
var _hold: WeaponHold
var _hands: WeaponHandsIK
## The fingers on what the hands hold (`HandGrip` of the weapon, the hammer or the grenade).
var _fingers: HandGripPose
var _weapon_grip: HandGrip
var _hammer_grip: HandGrip
var _grenade_grip: HandGrip
## How far the right hand's fingers are on the held item's grip (0: the clip's fist).
var _grip_blend := 0.0
var _shoulder_blend := 0.0
var _recoil := 0.0
## Seconds of the reload left (0: not reloading), its length, and how far the weapon is tilted down
## for it now, 0 to 1 (`WeaponHandsIK.reload_dip`).
var _reload_left := 0.0
var _reload_length := 1.0
var _reload_dip := 0.0
var _action_time := 0.0
var _move_blend := 0.0
var _was_on_floor := true
## Seconds into the Duck clip where the body is lowest: the pose a crouch holds.
var _duck_bottom := 0.0
## Seconds of repair left before the clip lets go (0: not repairing).
var _repair_left := 0.0
## Where the repair clip is, in its own seconds.
var _repair_time := 0.0
var _repair_scale := 1.0
var _repair_blend := 0.0
## The aim gait's weight over the free locomotion (0 free, 1 aiming), and its clips' ground speed.
## It is also the weapon's pose weight: the aim button or a shot from the hip raises it, and the
## camera does not follow it (the view zooms for the aim button only, #464).
var _aim_blend := 0.0
var _aim_spring := DampedSpring.new()
var _aim_move_speed := 2.6
var _aim_move := Vector2.ZERO
## Boards put back whose blow has not landed yet: each is one `board_set` the loop still owes.
var _boards_due := 0
var _carry_node: AnimationNodeAnimation
## The sprint carry's weight and the place of its clip (the Run clip's, while the feet are on the
## ground); the tree gets the weight through a smoothstep.
var _carry := SprintCarry.new()
var _carry_on := false
## The downed and revive layers (#504), and where the kneel loop is for its `press` events.
var _down := DownedPose.new()
var _revive_time := 0.0


func _ready() -> void:
	_player = get_parent() as Player
	_tuning = _player.tuning
	_spec = JSON.parse_string(FileAccess.get_file_as_string(SPEC))
	var model := _player.get_node("Model")
	var anim_player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var library := anim_player.get_animation_library(&"")
	SoldierClipFile.add(library, _spec, REPAIR_GLB, REPAIR_SPEC, [REPAIR_CLIP])
	SoldierClipFile.add(library, _spec, GRENADE_GLB, GRENADE_SPEC, GRENADE_CLIPS)
	var aim_moves := SoldierClipFile.add(
		library, _spec, AIM_MOVE_GLB, AIM_MOVE_SPEC, AIM_MOVES.keys()
	)
	_aim_move_speed = aim_moves["clips"]["Walk_Shoot"]["ground_speed"]
	SoldierClipFile.add(library, _spec, SPRINT_GLB, SPRINT_SPEC, SprintCarry.CLIPS)
	var revive_specs := DownedPose.add_clips(anim_player)
	_spec["clips"].merge(revive_specs)
	if revive_specs.has(String(DownedPose.CRAWL_CLIP)):
		_down.crawl_speed = revive_specs[String(DownedPose.CRAWL_CLIP)]["ground_speed"]
	_loop_clips(anim_player)
	_duck_bottom = SoldierClipFile.lowest_second(anim_player.get_animation(&"Duck"))
	_mount = BoneAttachment3D.new()
	_mount.name = "WeaponMount"
	_mount.bone_name = HAND_BONE
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	skeleton.add_child(_mount)
	var hammer_hold := load(HAMMER_HOLD) as WeaponHold
	_hammer = (load(hammer_hold.scene) as PackedScene).instantiate() as Node3D
	_hammer.name = "Hammer"
	_hammer_grip = HandGrip.for_scene(hammer_hold.scene)
	_hammer.transform = _grip_hold(_hammer_grip, HOLD_HAMMER).scaled_local(
		Vector3.ONE * hammer_hold.model_scale
	)
	_hammer.visible = false
	_mount.add_child(_hammer)
	_build_grenade()
	_hands = WeaponHandsIK.new()
	_hands.name = "WeaponHandsIK"
	_hands.hand_hold = HOLD_GUN
	_hands.influence = 0.0
	skeleton.add_child(_hands)
	# After the arms' IK: the fingers close on what the hand holds, the palm turns as one.
	_fingers = HandGripPose.new()
	_fingers.name = "HandGripPose"
	skeleton.add_child(_fingers)
	self.anim_player = get_path_to(anim_player)
	tree_root = _build_tree(SoldierClipFile.skeleton_track_path(anim_player))
	set(&"parameters/split/blend_amount", 1.0)
	active = true
	_playback = get(&"parameters/body/playback") as AnimationNodeStateMachinePlayback
	_set_class(DEFAULT_CLASS, hold_of(DEFAULT_CLASS))
	_player.jumped.connect(_on_jumped)
	_player.landed.connect(_on_landed)


func _process(delta: float) -> void:
	var on_floor := _player.state.on_floor
	if _was_on_floor and not on_floor and _player.state.velocity.y <= 0.0:
		_playback.travel(STATE_FALL)
	_was_on_floor = on_floor
	_follow_stance(on_floor)

	var speed := _player.ground_speed()
	var follow := 1.0 - exp(-_tuning.blend_rate * delta)
	_move_blend = lerpf(_move_blend, clampf(speed / _tuning.run_blend_speed, 0.0, 1.0), follow)
	set(MOVE_PARAMETER, _move_blend)
	# Only the Run end of the blend follows ground speed; Idle and Walk play at their own pace.
	var run_scale := maxf(speed / _tuning.run_clip_speed, 0.4)
	var run_part := clampf((_move_blend - WALK_POINT) / (0.95 - WALK_POINT), 0.0, 1.0)
	set(RUN_SPEED_PARAMETER, lerpf(1.0, run_scale, run_part))
	_advance_crouch()
	_advance_aim_move(follow, delta)
	_advance_events(delta)
	_advance_repair(delta)
	_advance_downed(speed, delta)
	_advance_carry(delta, on_floor)
	_advance_reload(delta)
	_advance_shoulder(delta)
	_advance_grip(delta)


## The tilt for the reload: down over the first `reload_dip_in` of it, held, up over the last
## `reload_dip_out`, each a smoothstep.
func _advance_reload(delta: float) -> void:
	var target := 0.0
	if _reload_left > 0.0:
		_reload_left = maxf(_reload_left - delta, 0.0)
		var done := 1.0 - _reload_left / _reload_length
		target = smoothstep(0.0, _tuning.reload_dip_in, done)
		target *= 1.0 - smoothstep(1.0 - _tuning.reload_dip_out, 1.0, done)
	_reload_dip = lerpf(_reload_dip, target, 1.0 - exp(-RELOAD_FOLLOW * delta))
	if _reload_left <= 0.0 and _reload_dip < 0.001:
		_reload_dip = 0.0
	_hands.reload_dip = _reload_dip
	_hands.reload_tilt_deg = _tuning.reload_tilt_degrees


## Into the crouch state when the body crouches on the ground, back to the locomotion when it
## stands (a fall leaves it by its own transition, a landing returns to the locomotion).
func _follow_stance(on_floor: bool) -> void:
	var current := _playback.get_current_node()
	if _player.state.crouching and on_floor and current == STATE_LOCOMOTION:
		_playback.travel(STATE_CROUCH)
	elif not _player.state.crouching and current == STATE_CROUCH:
		_playback.travel(STATE_LOCOMOTION)


## How much Walk shows under the held Duck pose, and how fast it steps, for the speed now.
func _advance_crouch() -> void:
	var share := clampf(_player.ground_speed() / _tuning.crouch_speed, 0.0, 1.0)
	set(CROUCH_MIX_PARAMETER, share * _tuning.crouch_walk_blend)
	set(CROUCH_RATE_PARAMETER, maxf(share, CROUCH_WALK_RATE_MIN))


## The aim gait for the player's velocity in the frame of its facing: where it sits in the 2D
## blend (x to the right, y ahead; its length is how far it has left the Idle in the middle), and
## how fast it plays so the feet keep up (ground speed over the clips' own).
static func aim_move_for(velocity: Vector3, facing: float, clip_speed: float) -> Dictionary:
	var ahead := Vector3(-sin(facing), 0.0, -cos(facing))
	var right := Vector3(cos(facing), 0.0, -sin(facing))
	var local := Vector2(velocity.dot(right), velocity.dot(ahead))
	var share := local.length() / clip_speed
	if share < 0.001:
		return {"position": Vector2.ZERO, "rate": 1.0}
	var weight := clampf(share / AIM_MOVE_FULL, 0.0, 1.0)
	var rate := lerpf(1.0, clampf(share, AIM_RATE_MIN, AIM_RATE_MAX), weight)
	return {"position": local.normalized() * weight, "rate": rate}


## Whether the arms should carry the weapon with the stride: sprinting on the ground at speed with
## nothing else for the arms to do (no aim and no shot held, no action clip, no repair, not down
## and not kneeling at a revive). In the air the carry only holds what it had: it never starts
## there, and anything that interrupts it on the ground interrupts it in the air too.
func sprint_carry_wanted(on_floor: bool) -> bool:
	var state := _player.state
	return (
		state.sprinting
		and (on_floor or _carry_on)
		and _player.ground_speed() >= _tuning.sprint_carry_min_speed
		and not state.holds_aim(_tuning.hip_fire_hold)
		and action_clip == &""
		and not is_repairing()
		and not _down.downed
		and not _down.reviving
	)


## The sprint carry's weight now, 0 to 1 (linear in time; the tree eases it), for tests.
func sprint_carry() -> float:
	return _carry.weight


## Where the sprint carry's clip is, in its own seconds, for tests.
func sprint_carry_time() -> float:
	return _carry.time


## Where the Run clip is in the locomotion, in its own seconds (the carry follows it).
func run_time() -> float:
	return get(RUN_POSITION_PARAMETER)


## The aim gait's place in its blend space now, for tests.
func aim_move() -> Vector2:
	return _aim_move


## The aim gait's weight over the free locomotion now (0 free, 1 aiming), for tests.
func aim_weight() -> float:
	return _aim_blend


## Name of the body state machine's current state, for tests and debugging.
func current_state() -> StringName:
	return _playback.get_current_node()


## The BoneAttachment3D that carries the weapon, for tests and debugging.
func weapon_mount() -> BoneAttachment3D:
	return _mount


## The weapon model in the hand, or null (Pistol has none yet).
func weapon() -> Node3D:
	return _weapon


## The repair hammer on the hand mount, shown only while the repair holds the arms.
func hammer() -> Node3D:
	return _hammer


## The muzzle point of the weapon in the hand (its `-Z` points down the barrel), or null when the
## class shows no weapon. The muzzle flash hangs on it. It is the `Muzzle` node the weapon's own
## model carries (the convention: docs/design/weapon-hold.md), or, for a model that has none yet,
## one placed at the hold's `muzzle` point.
func muzzle_point() -> Node3D:
	if _weapon == null:
		return null
	return _weapon.find_child(MUZZLE_NODE, true, false) as Node3D


## Switches to a weapon: a class (`&"Rifle"`) or a weapon of the catalogue (`&"pistol"`).
## Equip_<Class> plays and the weapon appears on its weapon_visible frame; the upper body then
## holds Aim_<Class>. A catalogue weapon brings its own hold and model (`WeaponHoldMap.hold_for`),
## so no two share a model; a class brings the class's hold (`hold_of`).
func equip(weapon: StringName) -> void:
	if weapon in CLASSES:
		_set_class(weapon, hold_of(weapon))
	elif weapon in WeaponCatalog.IDS:
		_set_class(WeaponHoldMap.class_of(weapon), WeaponHoldMap.hold_for(weapon))
	else:
		push_error("PlayerAnimation: no weapon or class %s" % weapon)
		return
	cancel_reload()
	_weapon_visible(false)
	play_action(&"Equip")


## The weapon is reloading for `seconds` (the server's `reload_started`): it tilts down, eased, and
## is back up when they are over, whatever the aim weight is (the tilt is added to the pose the
## aim weight gives, so a reload while aiming returns to the aim).
func reload(seconds: float) -> void:
	_reload_length = maxf(seconds, 0.01)
	_reload_left = _reload_length


## The reload stops (a swap abandons it, the server cancels it too).
func cancel_reload() -> void:
	_reload_left = 0.0


## How far the weapon is tilted down for the reload now, 0 to 1, for tests.
func reload_dip() -> float:
	return _reload_dip


## Plays `<action>_<Class>` (Fire, Reload, Swing, Equip, Unequip) on the upper body. Returns
## false when the class has no such clip.
func play_action(action: StringName) -> bool:
	var played := _play_clip(StringName("%s_%s" % [action, weapon_class]))
	# An attack or a reload that cuts the Equip clip short must not leave the weapon hidden: its
	# `weapon_visible` frame would never come.
	if played and action != &"Equip" and action != &"Unequip":
		_weapon_visible(true)
	return played


## The Soldier's side of a grenade, by the server's events. `&"cook"` (`cook_started`): the pin is
## out, the cook clip plays and the gun goes down. `&"throw"` (`throw_started`, the button came up):
## the throw clip, or for the short underarm toss the toss clip (`underarm` is the event's own
## flag); the grenade leaves the hand at the clip's release frame, which is where the server lets
## go of it. `&"gone"` (it went off in the hand, or the player was downed): the hand is empty and
## the gun comes back.
func grenade(stage: StringName, underarm: bool = false) -> void:
	match stage:
		&"cook":
			_play_clip(GRENADE_COOK)
		&"throw":
			_play_clip(GRENADE_TOSS if underarm else GRENADE_THROW)
		&"gone":
			_grenade.visible = false
			if action_clip == GRENADE_COOK:
				action_clip = &""
				set(&"parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
			_weapon_visible(true)


## Plays a clip of the spec on the upper body, in place of whatever action it was playing. Returns
## false when the spec has no such clip.
func _play_clip(clip: StringName) -> bool:
	if not _spec["clips"].has(String(clip)):
		return false
	_action_node.animation = clip
	# The cook pose is kept for as long as the button stays down: the node's timeline runs past
	# the clip, which holds its last frame.
	_action_node.use_custom_timeline = clip == GRENADE_COOK
	if clip == GRENADE_COOK:
		_action_node.timeline_length = GRENADE_COOK_HOLD
		_action_node.stretch_time_scale = false
		_action_node.loop_mode = Animation.LOOP_NONE
	action_clip = clip
	_action_time = 0.0
	set(&"parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_emit_events(clip, -1.0, 0.0)
	return true


## Plays a full-body clip over everything (HitReact, Death).
func play_full_body(clip: StringName) -> void:
	_full_node.animation = clip
	set(&"parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## A board this player put back has just gone up (the rules' `board_repaired`, which come one
## `interval` apart while `use` is held): the repair loop plays, or keeps playing, at the pace of
## one loop per interval, from `REPAIR_KNOCK` seconds before the blow, so the fist comes down as
## the board knocks home (on the first board too: it rises and lands). The weapon is put away
## and the hammer is in the hand meanwhile. Driven by the events alone: nothing here reads the
## clock.
func board_repaired(interval: float) -> void:
	interval = maxf(interval, 0.05)
	_repair_scale = _clip_seconds(REPAIR_CLIP) / interval
	_repair_left = interval * REPAIR_HOLD
	_repair_time = repair_lead(interval)
	_boards_due += 1
	set(REPAIR_SCALE_PARAMETER, _repair_scale)
	set(REPAIR_SEEK_PARAMETER, _repair_time)
	_hands_on_repair(true)


## Where a board's `board_repaired` puts the repair clip, in its own seconds: the blow less the
## knock's delay at the pace of `interval` (never before the clip's start).
func repair_lead(interval: float) -> float:
	var scale := _clip_seconds(REPAIR_CLIP) / maxf(interval, 0.05)
	return maxf(_event_seconds(REPAIR_CLIP, REPAIR_SET_EVENT) - REPAIR_KNOCK * scale, 0.0)


## Whether the repair loop holds the arms.
func is_repairing() -> bool:
	return _repair_left > 0.0


## Lets go of the repair at once (the player went down, or walked off).
func stop_repair() -> void:
	if _repair_left > 0.0:
		_repair_left = 0.0
		_boards_due = 0
		_hands_on_repair(false)


## The repair layer's weight now (0: the weapon arms, 1: the repair arms), for tests.
func repair_weight() -> float:
	return _repair_blend


## Where the repair clip is, in its own seconds, for tests.
func repair_time() -> float:
	return _repair_time


## Down (`player_downed`) or up again (`player_revived`): the body eases into the downed pose or out
## of it (DownedPose). Going down drops a repair, a reload and a revive, and puts the weapon away.
func set_downed(downed: bool) -> void:
	if downed == _down.downed:
		return
	_down.downed = downed
	if downed:
		stop_repair()
		cancel_reload()
		_down.reviving = false
	_weapon_visible(not downed)


## Holding the revive on a teammate (`revive_started` naming this player the reviver) or not
## (`revive_interrupted`, `player_revived`): kneels and presses while held. Never while down.
func set_reviving(reviving: bool) -> void:
	reviving = reviving and not _down.downed
	if reviving == _down.reviving:
		return
	_down.reviving = reviving
	if reviving:
		stop_repair()
		cancel_reload()
		_revive_time = 0.0
	_weapon_visible(not reviving)


func is_downed() -> bool:
	return _down.downed


func is_reviving() -> bool:
	return _down.reviving


## The layers' weights now (0 to 1), and whether the optional crawl is in, for tests.
func downed_weight() -> float:
	return _down.downed_blend


func kneel_weight() -> float:
	return _down.kneel_blend


func crawl_weight() -> float:
	return _down.crawl_blend


func has_crawl() -> bool:
	return _down.has_crawl()


## Event names and frames of a clip, from clips.json: {event: frame or [frames]}.
func clip_events(clip: StringName) -> Dictionary:
	var entry: Dictionary = _spec["clips"].get(String(clip), {})
	return entry.get("events", {})


## The grenade in the hand, on the same mount as the weapons: the model of `GRENADE_HOLD` at the
## hold's size, in the grip solved for it (the fist closed on something short).
func _build_grenade() -> void:
	var hold := load(GRENADE_HOLD) as WeaponHold
	_grenade = (load(hold.scene) as PackedScene).instantiate() as Node3D
	_grenade.name = "Grenade"
	_grenade_grip = HandGrip.for_name(GRENADE_GRIP)
	var held := _grip_hold(_grenade_grip, Transform3D(Basis(), HOLD_MELEE.origin))
	_grenade.transform = held.scaled_local(Vector3.ONE * hold.model_scale)
	_grenade.visible = false
	_mount.add_child(_grenade)


## The hold data of a weapon class, or null when the class shows no weapon.
static func hold_of(new_class: StringName) -> WeaponHold:
	if new_class not in HOLD_CLASSES:
		return null
	return load(HOLDS_DIR + String(new_class).to_lower() + ".tres") as WeaponHold


## The hold data of the weapon in the hand, or null.
func weapon_hold() -> WeaponHold:
	return _hold


## The arm pose that puts the weapon at the shoulder, for tests and debugging.
func hands() -> WeaponHandsIK:
	return _hands


## How far the arms are on the shouldered pose, 0 to 1.
func shoulder_blend() -> float:
	return _shoulder_blend


func _set_class(new_class: StringName, hold: WeaponHold) -> void:
	weapon_class = new_class
	_aim_node.animation = StringName("Aim_%s" % new_class)
	_carry_node.animation = SprintCarry.clip_for(new_class, hold)
	if _weapon != null:
		_weapon.free()
		_weapon = null
	_hold = hold
	_hands.hold = _hold
	_weapon_grip = null
	_hands.grip = null
	if _hold != null:
		_weapon = (load(_hold.scene) as PackedScene).instantiate() as Node3D
		_weapon.name = "Weapon"
		_weapon_grip = HandGrip.for_scene(_hold.scene)
		_hands.grip = _weapon_grip
		var grip := _grip_hold(_weapon_grip, HOLD_MELEE if new_class == &"Melee" else HOLD_GUN)
		_weapon.transform = grip.scaled_local(Vector3.ONE * _hold.model_scale)
		# The arms' IK works the hand out from the weapon's pose through the same grip.
		_hands.hand_hold = grip
		_weapon.visible = not is_repairing()
		if _weapon.find_child(MUZZLE_NODE, true, false) == null:
			_weapon.add_child(_make_muzzle(_hold))
		_mount.add_child(_weapon)


## The model's place under the hand bone: its grip's (solved from its sockets), or `fallback` (the
## kit's hold) for a model with no grip file yet.
static func _grip_hold(grip: HandGrip, fallback: Transform3D) -> Transform3D:
	return grip.hold if grip != null else fallback


## The grip of the weapon in the hand, or null.
func weapon_grip() -> HandGrip:
	return _weapon_grip


## The finger pose on the skeleton, for tests.
func fingers() -> HandGripPose:
	return _fingers


## The fingers close on what the right hand shows: the hammer while repairing, the grenade while it
## is in the hand, else the weapon; the left hand's fingers follow the arms' IK, which puts that
## hand on the weapon's `Support`.
func _advance_grip(delta: float) -> void:
	var grip: HandGrip = null
	if _hammer.visible:
		grip = _hammer_grip
	elif _grenade.visible:
		grip = _grenade_grip
	elif _weapon != null and _weapon.visible:
		grip = _weapon_grip
	if grip != null:
		_fingers.grip = grip
	var target := 1.0 if grip != null else 0.0
	_grip_blend = lerpf(_grip_blend, target, 1.0 - exp(-GRIP_RATE * delta))
	if absf(_grip_blend - target) < 0.001:
		_grip_blend = target
	_fingers.right_weight = _grip_blend
	var left := grip == _weapon_grip and grip != null and grip.has_left
	# The left hand is on the weapon by the arms' IK (the shouldered pose) or by the sprint carry,
	# whose two-handed clips put it on the grip's `left_hand` (#527).
	var on := _shoulder_blend if _hands.active else 0.0
	_fingers.left_weight = maxf(on, smoothstep(0.0, 1.0, _carry.weight)) if left else 0.0


## The muzzle point of a hold: at its `muzzle` (the model's units), turned so `-Z` runs out of the
## barrel (the model's `-X`).
func _make_muzzle(hold: WeaponHold) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = MUZZLE_NODE
	marker.transform = Transform3D(Basis.looking_at(Vector3.LEFT, Vector3.UP), hold.muzzle)
	return marker


## Eases the arms onto the shouldered pose while the weapon is up and the clip does not use the
## hands (Reload, Equip, Unequip, Swing and the repair do), and gives the pose the camera's aim.
func _advance_shoulder(delta: float) -> void:
	var up := _hold != null and _hold.shouldered and _weapon != null and _weapon.visible
	var hands_free := (
		(action_clip == &"" or String(action_clip).begins_with("Fire_"))
		and not is_repairing()
		and not _down.downed
		and not _down.reviving
	)
	var rig := _player.camera_rig
	# The pose weight (the aim button or a recent shot from the hip, eased) turns the weapon from the
	# body's heading to the view and the barrel in to the crosshair's ray: no single-frame jump.
	var weight := _aim_blend
	_hands.aim_yaw = lerp_angle(_player.rotation.y, rig.yaw, weight)
	_hands.aim_pitch = rig.pitch
	_hands.converge = weight
	_hands.hip_converge = WeaponHandsIK.hip_share(angle_difference(_player.rotation.y, rig.yaw))
	var view := rig.aim_transform()
	_hands.converge_on = view.origin - view.basis.z * WeaponHandsIK.CONVERGE_DISTANCE
	if String(action_clip).begins_with("Fire_") and _action_time < delta * 1.5:
		_recoil = 1.0
	_recoil *= exp(-RECOIL_RATE * delta)
	_hands.recoil = _recoil
	var target := 1.0 if up and hands_free else 0.0
	_shoulder_blend = lerpf(_shoulder_blend, target, 1.0 - exp(-SHOULDER_RATE * delta))
	if absf(_shoulder_blend - target) < 0.001:
		_shoulder_blend = target
	# The sprint carry holds the arms itself: the shouldered pose gives way to it as it comes in.
	_hands.influence = _shoulder_blend * (1.0 - _carry.weight)
	# Off, not only at influence 0: at 0 the modifier still overrode the arms in the drawn pose,
	# so the clips that move them (the repair, Reload, Swing, the carry) never showed in a running
	# game.
	_hands.active = _hands.influence > 0.0


## While repairing the hammer is in the hand and the weapon put away; a clip's weapon_visible
## event (an Equip) does not bring the weapon back over the hammer. Down or kneeling at a revive,
## the hands hold nothing.
func _weapon_visible(shown: bool) -> void:
	if _weapon != null:
		_weapon.visible = shown and not is_repairing() and not _down.downed and not _down.reviving


func _hands_on_repair(repairing: bool) -> void:
	_hammer.visible = repairing
	_weapon_visible(not repairing)


func _advance_events(delta: float) -> void:
	if action_clip == &"":
		return
	var before := _action_time
	_action_time += delta
	var clip := action_clip
	_emit_events(clip, before, _action_time)
	if _action_time >= _clip_seconds(clip) and action_clip == clip and clip != GRENADE_COOK:
		action_clip = &""
	elif clip == GRENADE_COOK and _action_time >= GRENADE_COOK_HOLD:
		action_clip = &""


## Follows the aim: while the aim is held (the button, or a shot just fired from the hip) the legs
## take the aim gait for the direction of travel (the body keeps facing the view, so moving sideways
## or back is a strafe or a backpedal). The weight eases at the aim's speed, from the same answer
## the body's turn reads (`PlayerMotionState.holds_aim`); the camera does not read it.
func _advance_aim_move(follow: float, delta: float) -> void:
	var held := _player.state.holds_aim(_tuning.hip_fire_hold)
	_aim_spring.step(1.0 if held else 0.0, _tuning.aim_frequency, delta)
	_aim_blend = clampf(_aim_spring.value, 0.0, 1.0)
	set(AIM_BLEND_PARAMETER, _aim_blend)
	var gait := aim_move_for(_player.state.velocity, _player.state.facing, _aim_move_speed)
	_aim_move = _aim_move.lerp(gait["position"], follow)
	set(AIM_MOVE_PARAMETER, _aim_move)
	set(AIM_RATE_PARAMETER, gait["rate"])


## The sprint carry: its weight toward what the body is doing (in over `sprint_carry_in`, out over
## `sprint_carry_out`, linearly) and its clip locked to the Run clip's place. The Run's place is
## read off the tree after its last step, plus that step: the place the Run reaches in the step to
## come, so the two land on the same frame. In the air the clip holds still (the Run is not played
## there either); after a landing it catches up with the restarted Run instead of jumping.
func _advance_carry(delta: float, on_floor: bool) -> void:
	_carry_on = sprint_carry_wanted(on_floor)
	var span := _tuning.sprint_carry_in if _carry_on else _tuning.sprint_carry_out
	_carry.advance_weight(delta, _carry_on, span)
	set(CARRY_BLEND_PARAMETER, smoothstep(0.0, 1.0, _carry.weight))
	if on_floor and current_state() == STATE_LOCOMOTION:
		var length := _clip_seconds(_carry_node.animation)
		_carry.follow_run(
			delta, run_time(), get(RUN_DELTA_PARAMETER), length, 1.0 / float(_spec["fps"])
		)
	set(CARRY_SEEK_PARAMETER, _carry.time)


## Moves the repair loop on by `delta` seconds: its events (`board_set` only for a board that is
## due: one per `board_repaired`, never the loop's own) and the fade in or out of its layer.
func _advance_repair(delta: float) -> void:
	if _repair_left > 0.0:
		var length := _clip_seconds(REPAIR_CLIP)
		var before := _repair_time
		_repair_time += delta * _repair_scale
		_advance_repair_events(before, minf(_repair_time, length))
		if _repair_time > length:
			_repair_time -= length
			_advance_repair_events(-1.0, _repair_time)
		if _repair_left > delta:
			_repair_left -= delta
		else:
			stop_repair()
	var target := 1.0 if _repair_left > 0.0 else 0.0
	_repair_blend = lerpf(_repair_blend, target, 1.0 - exp(-REPAIR_BLEND_RATE * delta))
	if absf(_repair_blend - target) < 0.001:
		_repair_blend = target
	set(REPAIR_BLEND_PARAMETER, _repair_blend)


## The downed and kneel layers, and the kneel loop's `press` events while the revive is held.
func _advance_downed(speed: float, delta: float) -> void:
	_down.advance(self, speed, delta)
	if _down.reviving:
		var length := _clip_seconds(DownedPose.REVIVE_CLIP)
		var before := _revive_time
		_revive_time += delta
		_emit_events(DownedPose.REVIVE_CLIP, before, minf(_revive_time, length))
		if _revive_time > length:
			_revive_time -= length
			_emit_events(DownedPose.REVIVE_CLIP, -1.0, _revive_time)


func _advance_repair_events(from: float, to: float) -> void:
	_emit_events(REPAIR_CLIP, from, to, REPAIR_SET_EVENT)
	var set_at := _event_seconds(REPAIR_CLIP, REPAIR_SET_EVENT)
	if _boards_due > 0 and set_at > from and set_at <= to:
		_boards_due -= 1
		clip_event.emit(REPAIR_CLIP, StringName(REPAIR_SET_EVENT))


func _event_frames(clip: StringName, event: String) -> Array:
	var frames: Variant = clip_events(clip).get(event, [])
	return frames if frames is Array else [frames]


func _event_seconds(clip: StringName, event: String) -> float:
	return float(_event_frames(clip, event)[0]) / float(_spec["fps"])


## How long an action holds the upper body: the clip's length, but never before its last event.
## clips.json rounds `seconds` (0.333 for 8 frames at 24 fps), so a frame step landing between
## the rounded length and the last event (8/24) would end the clip and skip that event for good.
func _clip_seconds(clip: StringName) -> float:
	var seconds: float = _spec["clips"][String(clip)]["seconds"]
	var fps: float = _spec["fps"]
	var events := clip_events(clip)
	for event: String in events:
		var frames: Array = events[event] if events[event] is Array else [events[event]]
		for frame: float in frames:
			seconds = maxf(seconds, frame / fps)
	return seconds


## Emits every event of `clip` whose time lies in (from, to], except the one named `skip`.
func _emit_events(clip: StringName, from: float, to: float, skip: String = "") -> void:
	var fps: float = _spec["fps"]
	var events := clip_events(clip)
	for event: String in events:
		if event == skip:
			continue
		var frames: Array = events[event] if events[event] is Array else [events[event]]
		for frame: float in frames:
			var at := frame / fps
			if at > from and at <= to:
				if event == "weapon_visible":
					_weapon_visible(true)
				elif event == "weapon_hidden":
					_weapon_visible(false)
				elif event == GRENADE_TAKEN_EVENT:
					_weapon_visible(false)
					_grenade.visible = true
				elif event == GRENADE_RELEASE_EVENT:
					_grenade.visible = false
				elif event == GRENADE_DONE_EVENT:
					_weapon_visible(true)
				clip_event.emit(clip, StringName(event))


func _on_jumped() -> void:
	_playback.travel(STATE_JUMP)


func _on_landed(_impact_speed: float) -> void:
	_playback.travel(STATE_LAND)


func _loop_clips(anim_player: AnimationPlayer) -> void:
	var clips: Dictionary = _spec["clips"]
	for clip: String in clips:
		if clips[clip]["loop"]:
			anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	for clip: String in KIT_LOOPS:
		anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


func _clip(clip_name: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip_name
	return node


func _build_tree(skeleton_path: String) -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	tree.add_node(&"body", PlayerBodyTree.build(_duck_bottom))
	_aim_node = _clip(&"Aim_Rifle")
	_carry_node = _clip(&"Sprint_Rifle")
	_action_node = _clip(&"Fire_Rifle")
	_full_node = _clip(&"HitReact")
	tree.add_node(&"aim", _aim_node)
	tree.add_node(&"carry_clip", _carry_node)
	tree.add_node(&"carry_seek", AnimationNodeTimeSeek.new())
	tree.add_node(&"carry", AnimationNodeBlend2.new())
	tree.add_node(&"action_clip", _action_node)
	var action := AnimationNodeOneShot.new()
	action.fadein_time = 0.05
	action.fadeout_time = 0.12
	tree.add_node(&"action", action)
	tree.add_node(&"repair_clip", _clip(REPAIR_CLIP))
	tree.add_node(&"repair_seek", AnimationNodeTimeSeek.new())
	tree.add_node(&"repair_scale", AnimationNodeTimeScale.new())
	tree.add_node(&"repair", AnimationNodeBlend2.new())
	var split := AnimationNodeBlend2.new()
	split.filter_enabled = true
	for bone: String in _spec["upper_bones"]:
		split.set_filter_path(NodePath("%s:%s" % [skeleton_path, bone]), true)
	tree.add_node(&"split", split)
	tree.add_node(&"full_clip", _full_node)
	var full := AnimationNodeOneShot.new()
	full.fadein_time = 0.05
	full.fadeout_time = 0.15
	tree.add_node(&"full", full)
	tree.connect_node(&"carry_seek", 0, &"carry_clip")
	tree.connect_node(&"carry", 0, &"aim")
	tree.connect_node(&"carry", 1, &"carry_seek")
	tree.connect_node(&"action", 0, &"carry")
	tree.connect_node(&"action", 1, &"action_clip")
	tree.connect_node(&"split", 0, &"body")
	tree.connect_node(&"repair_seek", 0, &"repair_clip")
	tree.connect_node(&"repair_scale", 0, &"repair_seek")
	tree.connect_node(&"repair", 0, &"action")
	tree.connect_node(&"repair", 1, &"repair_scale")
	tree.connect_node(&"split", 1, &"repair")
	tree.connect_node(&"full", 0, _down.add_nodes(tree, &"split"))
	tree.connect_node(&"full", 1, &"full_clip")
	tree.connect_node(&"output", 0, &"full")
	return tree

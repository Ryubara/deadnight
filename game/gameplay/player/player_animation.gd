class_name PlayerAnimation
extends AnimationTree
## Drives the Soldier's clips (docs/design/animation.md is the spec) from the player's movement.
##
## The tree is built here, in code, so the clip names live in one place:
##   body:  locomotion (Idle / Walk / Run blended by speed; the Run end plays at ground speed /
##          run_clip_speed so the feet do not slide), and jump -> fall -> land -> locomotion.
##   upper: the class's Aim_<Class> loop with a OneShot on top (Fire, Reload, Swing, Equip,
##          Unequip), laid over the body by a Blend2 filtered to the upper bones.
##   repair: Repair_Board looping over the upper layer while the player puts boards back at a
##          breach (its own file, added to the library here), timed by the rules' events.
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
## The weapon each class shows (Pistol has no model yet: the hand stays empty).
const WEAPON_SCENES := {
	&"Rifle": "res://assets/weapons/lever_rifle/lever_rifle.glb",
	&"Shotgun": "res://assets/weapons/double_shotgun/double_shotgun.glb",
	&"Melee": "res://assets/weapons/baseball_bat/baseball_bat.glb",
}
const CLASSES: Array[StringName] = [&"Rifle", &"Shotgun", &"Pistol", &"Melee"]
const DEFAULT_CLASS := &"Rifle"
## Where Walk sits on the move blend (0 = Idle, 1 = Run).
const WALK_POINT := 0.45
## The repair clip, built into its own file (docs/design/animation.md, Repair) and added to the
## Soldier's library when the tree is built.
const REPAIR_GLB := "res://assets/characters/soldier/repair/soldier_repair.glb"
const REPAIR_SPEC := "res://assets/characters/soldier/repair/clips.json"
const REPAIR_CLIP := &"Repair_Board"
## The event the board lands on: each `board_repaired` of this player seeks the clip here.
const REPAIR_SET_EVENT := "board_set"
## How many repair intervals the clip keeps going after the last board went up: a held `use`
## mends the next one an interval later, so it only stops once one is missed.
const REPAIR_HOLD := 1.5
## How fast the repair layer fades in and out (per second, exponential).
const REPAIR_BLEND_RATE := 18.0
const REPAIR_SEEK_PARAMETER := &"parameters/repair_seek/seek_request"
const REPAIR_SCALE_PARAMETER := &"parameters/repair_scale/scale"
const REPAIR_BLEND_PARAMETER := &"parameters/repair/blend_amount"

const STATE_LOCOMOTION := &"locomotion"
const STATE_JUMP := &"jump"
const STATE_FALL := &"fall"
const STATE_LAND := &"land"
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
var _action_time := 0.0
var _move_blend := 0.0
var _was_on_floor := true
## Seconds of repair left before the clip lets go (0: not repairing).
var _repair_left := 0.0
## Where the repair clip is, in its own seconds.
var _repair_time := 0.0
var _repair_scale := 1.0
var _repair_blend := 0.0


func _ready() -> void:
	_player = get_parent() as Player
	_tuning = _player.tuning
	_spec = JSON.parse_string(FileAccess.get_file_as_string(SPEC))
	var model := _player.get_node("Model")
	var anim_player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_add_repair_clip(anim_player)
	_loop_clips(anim_player)
	_mount = BoneAttachment3D.new()
	_mount.name = "WeaponMount"
	_mount.bone_name = HAND_BONE
	model.find_child("Skeleton3D", true, false).add_child(_mount)
	self.anim_player = get_path_to(anim_player)
	tree_root = _build_tree(_skeleton_track_path(anim_player))
	set(&"parameters/split/blend_amount", 1.0)
	active = true
	_playback = get(&"parameters/body/playback") as AnimationNodeStateMachinePlayback
	_set_class(DEFAULT_CLASS)
	_player.jumped.connect(_on_jumped)
	_player.landed.connect(_on_landed)


func _process(delta: float) -> void:
	var on_floor := _player.state.on_floor
	if _was_on_floor and not on_floor and _player.state.velocity.y <= 0.0:
		_playback.travel(STATE_FALL)
	_was_on_floor = on_floor

	var speed := _player.ground_speed()
	var follow := 1.0 - exp(-_tuning.blend_rate * delta)
	_move_blend = lerpf(_move_blend, clampf(speed / _tuning.run_blend_speed, 0.0, 1.0), follow)
	set(MOVE_PARAMETER, _move_blend)
	# Only the Run end of the blend follows ground speed; Idle and Walk play at their own pace.
	var run_scale := maxf(speed / _tuning.run_clip_speed, 0.4)
	var run_part := clampf((_move_blend - WALK_POINT) / (0.95 - WALK_POINT), 0.0, 1.0)
	set(RUN_SPEED_PARAMETER, lerpf(1.0, run_scale, run_part))
	_advance_events(delta)
	_advance_repair(delta)


## Name of the body state machine's current state, for tests and debugging.
func current_state() -> StringName:
	return _playback.get_current_node()


## The BoneAttachment3D that carries the weapon, for tests and debugging.
func weapon_mount() -> BoneAttachment3D:
	return _mount


## The weapon model in the hand, or null (Pistol has none yet).
func weapon() -> Node3D:
	return _weapon


## Switches to a weapon class: Equip_<Class> plays and the weapon appears on its weapon_visible
## frame; the upper body then holds Aim_<Class>.
func equip(new_class: StringName) -> void:
	if new_class not in CLASSES:
		push_error("PlayerAnimation: no weapon class %s" % new_class)
		return
	_set_class(new_class)
	_weapon_visible(false)
	play_action(&"Equip")


## Plays `<action>_<Class>` (Fire, Reload, Swing, Equip, Unequip) on the upper body. Returns
## false when the class has no such clip.
func play_action(action: StringName) -> bool:
	var clip := StringName("%s_%s" % [action, weapon_class])
	if not _spec["clips"].has(String(clip)):
		return false
	_action_node.animation = clip
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
## `interval` apart while `use` is held): the repair loop plays, or keeps playing, from the frame
## the board lands on, at the pace of one loop per interval. The weapon is put away meanwhile.
## Driven by the events alone: nothing here reads the clock.
func board_repaired(interval: float) -> void:
	interval = maxf(interval, 0.05)
	_repair_scale = _clip_seconds(REPAIR_CLIP) / interval
	_repair_left = interval * REPAIR_HOLD
	_repair_time = _event_seconds(REPAIR_CLIP, REPAIR_SET_EVENT)
	set(REPAIR_SCALE_PARAMETER, _repair_scale)
	set(REPAIR_SEEK_PARAMETER, _repair_time)
	_weapon_visible(false)
	_emit_events(REPAIR_CLIP, _repair_time - 0.001, _repair_time)


## Whether the repair loop holds the arms.
func is_repairing() -> bool:
	return _repair_left > 0.0


## Lets go of the repair at once (the player went down, or walked off).
func stop_repair() -> void:
	if _repair_left > 0.0:
		_repair_left = 0.0
		_weapon_visible(true)


## The repair layer's weight now (0: the weapon arms, 1: the repair arms), for tests.
func repair_weight() -> float:
	return _repair_blend


## Where the repair clip is, in its own seconds, for tests.
func repair_time() -> float:
	return _repair_time


## Event names and frames of a clip, from clips.json: {event: frame or [frames]}.
func clip_events(clip: StringName) -> Dictionary:
	var entry: Dictionary = _spec["clips"].get(String(clip), {})
	return entry.get("events", {})


func _set_class(new_class: StringName) -> void:
	weapon_class = new_class
	_aim_node.animation = StringName("Aim_%s" % new_class)
	if _weapon != null:
		_weapon.free()
		_weapon = null
	if WEAPON_SCENES.has(new_class):
		_weapon = (load(WEAPON_SCENES[new_class]) as PackedScene).instantiate() as Node3D
		_weapon.name = "Weapon"
		_weapon.transform = HOLD_MELEE if new_class == &"Melee" else HOLD_GUN
		_mount.add_child(_weapon)


func _weapon_visible(shown: bool) -> void:
	if _weapon != null:
		_weapon.visible = shown


func _advance_events(delta: float) -> void:
	if action_clip == &"":
		return
	var before := _action_time
	_action_time += delta
	var clip := action_clip
	_emit_events(clip, before, _action_time)
	if _action_time >= _clip_seconds(clip) and action_clip == clip:
		action_clip = &""


## Moves the repair loop on by `delta` seconds: its events (but the board_set frame: that one is
## the rules' event, sent by `board_repaired`) and the fade in or out of its layer.
func _advance_repair(delta: float) -> void:
	if _repair_left > 0.0:
		var length := _clip_seconds(REPAIR_CLIP)
		var before := _repair_time
		_repair_time += delta * _repair_scale
		var set_at := _event_seconds(REPAIR_CLIP, REPAIR_SET_EVENT)
		_emit_events(REPAIR_CLIP, before, minf(_repair_time, length), set_at)
		if _repair_time > length:
			_repair_time -= length
			_emit_events(REPAIR_CLIP, -1.0, _repair_time, set_at)
		if _repair_left > delta:
			_repair_left -= delta
		else:
			stop_repair()
	var target := 1.0 if _repair_left > 0.0 else 0.0
	_repair_blend = lerpf(_repair_blend, target, 1.0 - exp(-REPAIR_BLEND_RATE * delta))
	if absf(_repair_blend - target) < 0.001:
		_repair_blend = target
	set(REPAIR_BLEND_PARAMETER, _repair_blend)


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


## Emits every event of `clip` whose time lies in (from, to], except those at `skip_at` seconds.
func _emit_events(clip: StringName, from: float, to: float, skip_at: float = -1.0) -> void:
	var fps: float = _spec["fps"]
	var events := clip_events(clip)
	for event: String in events:
		var frames: Array = events[event] if events[event] is Array else [events[event]]
		for frame: float in frames:
			var at := frame / fps
			if at > from and at <= to and not is_equal_approx(at, skip_at):
				if event == "weapon_visible":
					_weapon_visible(true)
				elif event == "weapon_hidden":
					_weapon_visible(false)
				clip_event.emit(clip, StringName(event))


func _on_jumped() -> void:
	_playback.travel(STATE_JUMP)


func _on_landed(_impact_speed: float) -> void:
	_playback.travel(STATE_LAND)


## Adds Repair_Board to the Soldier's own library (same rig, same track paths: the grenade
## clips' recipe) and its entry to the clip spec, so its loop and events read like any other.
func _add_repair_clip(anim_player: AnimationPlayer) -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REPAIR_SPEC))
	_spec["clips"][String(REPAIR_CLIP)] = spec["clips"][String(REPAIR_CLIP)]
	var library := anim_player.get_animation_library(&"")
	if library.has_animation(REPAIR_CLIP):
		return
	# Not kept in a static: a static Animation outlives the scene tree and is reported leaked at exit.
	var holder := (load(REPAIR_GLB) as PackedScene).instantiate()
	var source := holder.find_child("AnimationPlayer", true, false) as AnimationPlayer
	library.add_animation(REPAIR_CLIP, source.get_animation(REPAIR_CLIP))
	holder.free()


func _loop_clips(anim_player: AnimationPlayer) -> void:
	var clips: Dictionary = _spec["clips"]
	for clip: String in clips:
		if clips[clip]["loop"]:
			anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	for clip: String in KIT_LOOPS:
		anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


## The node path the clips' bone tracks use for the skeleton (read from the file, not assumed).
func _skeleton_track_path(anim_player: AnimationPlayer) -> String:
	var idle := anim_player.get_animation(&"Idle")
	for track in idle.get_track_count():
		var path := String(idle.track_get_path(track))
		if path.contains(":"):
			return path.get_slice(":", 0)
	return "CharacterArmature/Skeleton3D"


func _clip(clip_name: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip_name
	return node


func _build_tree(skeleton_path: String) -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	tree.add_node(&"body", _build_body())
	_aim_node = _clip(&"Aim_Rifle")
	_action_node = _clip(&"Fire_Rifle")
	_full_node = _clip(&"HitReact")
	tree.add_node(&"aim", _aim_node)
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
	tree.connect_node(&"action", 0, &"aim")
	tree.connect_node(&"action", 1, &"action_clip")
	tree.connect_node(&"split", 0, &"body")
	tree.connect_node(&"repair_seek", 0, &"repair_clip")
	tree.connect_node(&"repair_scale", 0, &"repair_seek")
	tree.connect_node(&"repair", 0, &"action")
	tree.connect_node(&"repair", 1, &"repair_scale")
	tree.connect_node(&"split", 1, &"repair")
	tree.connect_node(&"full", 0, &"split")
	tree.connect_node(&"full", 1, &"full_clip")
	tree.connect_node(&"output", 0, &"full")
	return tree


func _build_body() -> AnimationNodeStateMachine:
	var machine := AnimationNodeStateMachine.new()
	machine.add_node(STATE_LOCOMOTION, _build_locomotion(), Vector2(200, 100))
	machine.add_node(STATE_JUMP, _clip(&"Jump"), Vector2(400, 0))
	machine.add_node(STATE_FALL, _clip(&"Jump_Idle"), Vector2(600, 100))
	machine.add_node(STATE_LAND, _clip(&"Jump_Land"), Vector2(400, 200))
	machine.add_transition(&"Start", STATE_LOCOMOTION, _transition(0.0, false))
	machine.add_transition(STATE_LOCOMOTION, STATE_JUMP, _transition(0.08, false))
	machine.add_transition(STATE_LOCOMOTION, STATE_FALL, _transition(0.15, false))
	machine.add_transition(STATE_JUMP, STATE_FALL, _transition(0.1, true))
	machine.add_transition(STATE_JUMP, STATE_LAND, _transition(0.05, false))
	machine.add_transition(STATE_FALL, STATE_LAND, _transition(0.05, false))
	machine.add_transition(STATE_LAND, STATE_LOCOMOTION, _transition(0.15, true))
	machine.add_transition(STATE_LAND, STATE_JUMP, _transition(0.08, false))
	return machine


func _transition(fade: float, at_end: bool) -> AnimationNodeStateMachineTransition:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = fade
	if at_end:
		transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	return transition


func _build_locomotion() -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	var move := AnimationNodeBlendSpace1D.new()
	move.min_space = 0.0
	move.max_space = 1.0
	move.sync = true  # Walk and Run differ in length: keep their steps in phase
	move.add_blend_point(_clip(&"Idle"), 0.0, -1, &"idle")
	move.add_blend_point(_clip(&"Walk"), WALK_POINT, -1, &"walk")
	move.add_blend_point(_clip(&"Run"), 1.0, -1, &"run")
	tree.add_node(&"move", move)
	tree.add_node(&"run_speed", AnimationNodeTimeScale.new())
	tree.connect_node(&"run_speed", 0, &"move")
	tree.connect_node(&"output", 0, &"run_speed")
	return tree

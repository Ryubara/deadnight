class_name PlayerAnimation
extends AnimationTree
## Drives the Soldier's clips (bare names, docs/design/animation.md) from the player's movement.
##
## The tree is built here, in code, so the clip names live in one place:
##   locomotion: Idle <-> Run blended by speed, and the same pair in an aiming pose (Idle_Shoot held
##               on its first frame, Run_Gun), blended by how far the aim has eased in.
##   jump -> fall -> land -> locomotion for leaving the ground and coming back.
## The Run clips play at a time scale of ground speed / run_clip_speed so the feet do not slide.

const LOOPED := ["Idle", "Run", "Run_Gun", "Jump_Idle", "Idle_Shoot"]
## The Soldier's file carries no weapon: one is attached to the hand bone with the measured gun hold
## (docs/design/animation.md, "Weapons in the hand").
const WEAPON_SCENE := preload("res://assets/weapons/lever_rifle/lever_rifle.glb")
const HAND_BONE := "Index1.R"
const HOLD_GUN := Transform3D(
	Basis(
		Vector3(-0.062527, -0.997926, -0.015303),
		Vector3(0.118606, -0.022655, 0.992683),
		Vector3(-0.990971, 0.060254, 0.119776)
	),
	Vector3(-0.039563, 0.197228, -0.070351)
)

const STATE_LOCOMOTION := &"locomotion"
const STATE_JUMP := &"jump"
const STATE_FALL := &"fall"
const STATE_LAND := &"land"

var _player: Player
var _tuning: PlayerTuning
var _playback: AnimationNodeStateMachinePlayback
var _move_blend := 0.0
var _aim_blend := 0.0
var _was_on_floor := true


func _ready() -> void:
	_player = get_parent() as Player
	_tuning = _player.tuning
	var model := _player.get_node("Model")
	var anim_player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_loop_clips(anim_player)
	_attach_weapon(model)
	self.anim_player = get_path_to(anim_player)
	tree_root = _build_tree()
	active = true
	_playback = get(&"parameters/playback") as AnimationNodeStateMachinePlayback
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
	_aim_blend = lerpf(_aim_blend, _player.camera_rig.aim_amount(), follow)
	var scale_factor := maxf(speed / _tuning.run_clip_speed, 0.4)
	set(&"parameters/locomotion/hip_move/blend_amount", _move_blend)
	set(&"parameters/locomotion/aim_move/blend_amount", _move_blend)
	set(&"parameters/locomotion/aim_mix/blend_amount", _aim_blend)
	set(&"parameters/locomotion/run_speed/scale", scale_factor)
	set(&"parameters/locomotion/aim_run_speed/scale", scale_factor)


## Name of the state machine's current state, for tests and debugging.
func current_state() -> StringName:
	return _playback.get_current_node()


func _on_jumped() -> void:
	_playback.travel(STATE_JUMP)


func _on_landed(_impact_speed: float) -> void:
	_playback.travel(STATE_LAND)


func _loop_clips(anim_player: AnimationPlayer) -> void:
	for clip: String in LOOPED:
		anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


## The BoneAttachment3D that carries the weapon, for tests and debugging.
func weapon_mount() -> BoneAttachment3D:
	return _player.get_node("Model").find_child("WeaponMount", true, false) as BoneAttachment3D


func _attach_weapon(model: Node) -> void:
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var mount := BoneAttachment3D.new()
	mount.name = "WeaponMount"
	mount.bone_name = HAND_BONE
	skeleton.add_child(mount)
	var weapon := WEAPON_SCENE.instantiate() as Node3D
	weapon.name = "Weapon"
	weapon.transform = HOLD_GUN
	mount.add_child(weapon)


func _clip(clip_name: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = StringName(clip_name)
	return node


func _build_tree() -> AnimationNodeStateMachine:
	var machine := AnimationNodeStateMachine.new()
	machine.add_node(STATE_LOCOMOTION, _build_locomotion(), Vector2(200, 100))
	machine.add_node(STATE_JUMP, _clip("Jump"), Vector2(400, 0))
	machine.add_node(STATE_FALL, _clip("Jump_Idle"), Vector2(600, 100))
	machine.add_node(STATE_LAND, _clip("Jump_Land"), Vector2(400, 200))
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
	tree.add_node(&"idle", _clip("Idle"))
	tree.add_node(&"run", _clip("Run"))
	tree.add_node(&"run_speed", AnimationNodeTimeScale.new())
	tree.add_node(&"hip_move", AnimationNodeBlend2.new())
	tree.add_node(&"aim_idle", _clip("Idle_Shoot"))
	tree.add_node(&"aim_idle_hold", AnimationNodeTimeScale.new())
	tree.add_node(&"aim_run", _clip("Run_Gun"))
	tree.add_node(&"aim_run_speed", AnimationNodeTimeScale.new())
	tree.add_node(&"aim_move", AnimationNodeBlend2.new())
	tree.add_node(&"aim_mix", AnimationNodeBlend2.new())
	tree.connect_node(&"run_speed", 0, &"run")
	tree.connect_node(&"hip_move", 0, &"idle")
	tree.connect_node(&"hip_move", 1, &"run_speed")
	tree.connect_node(&"aim_idle_hold", 0, &"aim_idle")
	tree.connect_node(&"aim_run_speed", 0, &"aim_run")
	tree.connect_node(&"aim_move", 0, &"aim_idle_hold")
	tree.connect_node(&"aim_move", 1, &"aim_run_speed")
	tree.connect_node(&"aim_mix", 0, &"hip_move")
	tree.connect_node(&"aim_mix", 1, &"aim_move")
	tree.connect_node(&"output", 0, &"aim_mix")
	return tree

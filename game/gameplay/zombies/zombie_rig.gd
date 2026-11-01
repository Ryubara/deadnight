class_name ZombieRig
extends RefCounted
## The animation side of a zombie model: one shared AnimationLibrary built from the model's own
## clips (the rig-sharing recipe, kit docs godot/rig-sharing.md), added to each model's player, and
## one AnimationTree per zombie with the same state machine. A body with the same bone names
## (a zombie variant, another character) plays the same library unchanged.

const LIBRARY := &"zombie"
## Clips the library carries, and which of them loop.
const CLIPS: Array[StringName] = [&"Idle", &"Walk", &"Run", &"Punch", &"HitReact", &"Death"]
const LOOPING: Array[StringName] = [&"Idle", &"Walk", &"Run"]
## Planar speed (m/s) at which the move state plays each clip.
const IDLE_AT := 0.0
const WALK_AT := 1.0
const RUN_AT := 3.0
const MAX_SPEED := 4.5

const STATE_MOVE := &"move"
const STATE_ATTACK := &"attack"
const STATE_STAGGER := &"stagger"
const STATE_DIE := &"die"
const BLEND_PARAMETER := &"parameters/move/blend_position"
const PLAYBACK_PARAMETER := &"parameters/playback"

## The one library every zombie shares. Built from the first model, then reused.
static var _library: AnimationLibrary


## Adds the shared library to `model`'s AnimationPlayer and builds its tree; returns the tree
## (inactive callbacks are left to the caller: the throttle advances it by hand).
static func attach(model: Node) -> AnimationTree:
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _library == null:
		_library = _build_library(player)
	player.add_animation_library(LIBRARY, _library)
	var tree := AnimationTree.new()
	tree.tree_root = _build_state_machine()
	model.add_child(tree)  # a sibling of the player: the clips' track paths resolve against ".."
	tree.anim_player = tree.get_path_to(player)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	return tree


static func _build_library(player: AnimationPlayer) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	for clip in CLIPS:
		var animation := player.get_animation(clip).duplicate(true) as Animation
		animation.loop_mode = Animation.LOOP_LINEAR if clip in LOOPING else Animation.LOOP_NONE
		library.add_animation(clip, animation)
	return library


static func _build_state_machine() -> AnimationNodeStateMachine:
	var machine := AnimationNodeStateMachine.new()
	var move := AnimationNodeBlendSpace1D.new()
	move.min_space = IDLE_AT
	move.max_space = MAX_SPEED
	move.sync = true  # walk and run have different lengths: keep their steps in phase
	move.add_blend_point(_clip_node(&"Idle"), IDLE_AT, -1, &"idle")
	move.add_blend_point(_clip_node(&"Walk"), WALK_AT, -1, &"walk")
	move.add_blend_point(_clip_node(&"Run"), RUN_AT, -1, &"run")
	machine.add_node(STATE_MOVE, move)
	machine.add_node(STATE_ATTACK, _clip_node(&"Punch"))
	machine.add_node(STATE_STAGGER, _clip_node(&"HitReact"))
	machine.add_node(STATE_DIE, _clip_node(&"Death"))
	return machine


static func _clip_node(clip: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = StringName("%s/%s" % [LIBRARY, clip])
	return node

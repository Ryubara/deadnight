class_name ZombieRig
extends RefCounted
## The animation side of a zombie model: one shared AnimationLibrary built from the model's own
## clips (the rig-sharing recipe, kit docs godot/rig-sharing.md), added to each model's player, and
## one AnimationTree per zombie with the same state machine. A body with the same bone names
## (a zombie variant, another character) plays the same library unchanged. The headliner has five
## clips of its own (`Boss_*`, in its file only) and its own machine over them (`attach_boss`).

const LIBRARY := &"zombie"
## Clips the library carries, and which of them loop.
const CLIPS: Array[StringName] = [
	&"Idle", &"Walk", &"Run", &"Crawl", &"Punch", &"HitReact", &"Death"
]
const LOOPING: Array[StringName] = [&"Idle", &"Walk", &"Run", &"Crawl"]
## Planar speed (m/s) at which the move state plays each clip.
const IDLE_AT := 0.0
const WALK_AT := 1.0
const RUN_AT := 3.0
const MAX_SPEED := 4.5

## The boss's clips, in a library of their own (`BOSS_LIBRARY`), and which of them loop.
const BOSS_LIBRARY := &"boss"
const BOSS_CLIPS: Array[StringName] = [
	&"Idle", &"Boss_Walk", &"Boss_Attack", &"Boss_Roar", &"Boss_Stagger", &"Boss_Death"
]
const BOSS_LOOPING: Array[StringName] = [&"Idle", &"Boss_Walk"]
## Seconds into `Boss_Attack` at which the blow lands (frame 32 at 24 fps, `clips.json` beside the
## model): the clip is played faster or slower so that this is the type's telegraph.
const BOSS_HIT_SECONDS := 32.0 / 24.0
## Planar speed (m/s) at which the boss's move state is fully walking.
const BOSS_WALK_AT := 0.6

## Clips authored for Deadnight on the same rig, in a file of their own
## (`tools/blender/build_zombie_clips.py`): added to both libraries.
const EXTRA_CLIPS_FILE := "res://assets/characters/zombies/clips/zombie_clips.glb"
## Pulling a board off the fence: reach, grab, strain, yank. It loops while a zombie stands at its
## boards; `TEAR_YANK_SECONDS` is the moment the board leaves the hands (frame 22 of 29 at 24 fps,
## `clips.json` beside the file), which the view puts on the rules' tear moment.
const TEAR_CLIP := &"Tear_Boards"
const TEAR_YANK_SECONDS := 22.0 / 24.0
const TEAR_SECONDS := 29.0 / 24.0

const STATE_MOVE := &"move"
const STATE_ROAR := &"roar"
const STATE_CRAWL := &"crawl"
const STATE_ATTACK := &"attack"
const STATE_STAGGER := &"stagger"
const STATE_DIE := &"die"
const STATE_TEAR := &"tear"
## The tear state is the clip behind a seek and a time scale: their parameters.
const TEAR_SEEK_PARAMETER := &"parameters/tear/seek/seek_request"
const TEAR_SCALE_PARAMETER := &"parameters/tear/scale/scale"
const BLEND_PARAMETER := &"parameters/move/blend_position"
const PLAYBACK_PARAMETER := &"parameters/playback"
## The attack state of the boss is a clip behind a time scale: this is the scale's parameter.
const BOSS_ATTACK_SCALE_PARAMETER := &"parameters/attack/scale/scale"

## The one library every zombie shares. Built from the first model, then reused.
static var _library: AnimationLibrary
static var _boss_library: AnimationLibrary
## The files the warm-up loaded, held so they stay in the resource cache until `release`.
static var _warm: Array[Resource] = []


## Loads the walker's model and the extra clips' file and builds the shared library now, at the
## night's start, instead of when the first zombie appears (#245: the first spawns cost a frame of
## 31 ms in the barricades capture). Does nothing when the library is built already.
static func warm_up() -> void:
	if _library != null:
		return
	var scene := ZombieModels.scene(ZombieModels.DEFAULT)
	_warm.append(scene)
	_warm.append(load(EXTRA_CLIPS_FILE))
	var model := scene.instantiate()
	_library = _build_library(model.find_child("AnimationPlayer", true, false) as AnimationPlayer)
	model.free()


## Adds the shared library to `model`'s AnimationPlayer and builds its tree; returns the tree
## (inactive callbacks are left to the caller: the throttle advances it by hand).
static func attach(model: Node) -> AnimationTree:
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _library == null:
		_library = _build_library(player)
	player.add_animation_library(LIBRARY, _library)
	return _tree(model, player, _build_state_machine())


## The same for the headliner: its five clips and its own machine (`STATE_MOVE` walks or stands,
## `STATE_ROAR` is its entrance, the others as for any zombie).
static func attach_boss(model: Node) -> AnimationTree:
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _boss_library == null:
		_boss_library = _build_library(player, BOSS_CLIPS, BOSS_LOOPING)
	player.add_animation_library(BOSS_LIBRARY, _boss_library)
	return _tree(model, player, _build_boss_machine())


static func _tree(
	model: Node, player: AnimationPlayer, machine: AnimationNodeStateMachine
) -> AnimationTree:
	var tree := AnimationTree.new()
	tree.tree_root = machine
	model.add_child(tree)  # a sibling of the player: the clips' track paths resolve against ".."
	tree.anim_player = tree.get_path_to(player)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	return tree


## Lets go of the shared library (a static holds its clips, which Godot reports as leaked at exit).
static func release() -> void:
	_library = null
	_boss_library = null
	_warm.clear()


static func _build_library(
	player: AnimationPlayer, clips: Array[StringName] = CLIPS, looping: Array[StringName] = LOOPING
) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	for clip in clips:
		var animation := player.get_animation(clip).duplicate(true) as Animation
		animation.loop_mode = Animation.LOOP_LINEAR if clip in looping else Animation.LOOP_NONE
		library.add_animation(clip, animation)
	var tear := _extra_clip(TEAR_CLIP)
	tear.loop_mode = Animation.LOOP_LINEAR
	library.add_animation(TEAR_CLIP, tear)
	return library


## A clip from the extra clips' file (the same rig and track paths as every zombie model).
static func _extra_clip(clip: StringName) -> Animation:
	# The warm-up holds the file, so this does not read it from disk again.
	var scene := (load(EXTRA_CLIPS_FILE) as PackedScene).instantiate()
	var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var animation := player.get_animation(clip).duplicate(true) as Animation
	scene.free()
	return animation


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
	machine.add_node(STATE_CRAWL, _clip_node(&"Crawl"))
	machine.add_node(STATE_ATTACK, _clip_node(&"Punch"))
	machine.add_node(STATE_STAGGER, _clip_node(&"HitReact"))
	machine.add_node(STATE_DIE, _clip_node(&"Death"))
	machine.add_node(STATE_TEAR, _tear_node(LIBRARY))
	return machine


static func _build_boss_machine() -> AnimationNodeStateMachine:
	var machine := AnimationNodeStateMachine.new()
	var move := AnimationNodeBlendSpace1D.new()
	move.min_space = IDLE_AT
	move.max_space = BOSS_WALK_AT
	move.add_blend_point(_clip_node(&"Idle", BOSS_LIBRARY), IDLE_AT, -1, &"idle")
	move.add_blend_point(_clip_node(&"Boss_Walk", BOSS_LIBRARY), BOSS_WALK_AT, -1, &"walk")
	machine.add_node(STATE_MOVE, move)
	machine.add_node(STATE_ROAR, _clip_node(&"Boss_Roar", BOSS_LIBRARY))
	machine.add_node(STATE_ATTACK, _scaled_clip(&"Boss_Attack"))
	machine.add_node(STATE_STAGGER, _clip_node(&"Boss_Stagger", BOSS_LIBRARY))
	machine.add_node(STATE_DIE, _clip_node(&"Boss_Death", BOSS_LIBRARY))
	machine.add_node(STATE_TEAR, _tear_node(BOSS_LIBRARY))
	return machine


## The tear clip behind a seek (to put the yank on a tear) and a time scale (to fit a type's pace).
static func _tear_node(library: StringName) -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	tree.add_node(&"clip", _clip_node(TEAR_CLIP, library))
	tree.add_node(&"seek", AnimationNodeTimeSeek.new())
	tree.add_node(&"scale", AnimationNodeTimeScale.new())
	tree.connect_node(&"seek", 0, &"clip")
	tree.connect_node(&"scale", 0, &"seek")
	tree.connect_node(&"output", 0, &"scale")
	return tree


## A clip behind a time scale (the scale is `BOSS_ATTACK_SCALE_PARAMETER`).
static func _scaled_clip(clip: StringName) -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	tree.add_node(&"clip", _clip_node(clip, BOSS_LIBRARY))
	tree.add_node(&"scale", AnimationNodeTimeScale.new())
	tree.connect_node(&"scale", 0, &"clip")
	tree.connect_node(&"output", 0, &"scale")
	return tree


static func _clip_node(clip: StringName, library: StringName = LIBRARY) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = StringName("%s/%s" % [library, clip])
	return node

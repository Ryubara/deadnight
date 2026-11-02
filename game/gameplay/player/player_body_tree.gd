class_name PlayerBodyTree
extends RefCounted
## The body layer of `PlayerAnimation`'s tree: a state machine of the locomotion (Idle, Walk and
## Run by speed, the four aim moves around Idle), the jump, fall and landing, and the crouch. The
## state names, blend points and the Duck hold are `PlayerAnimation`'s constants.


## The body's state machine; `duck_bottom` is the second of Duck where the body is lowest.
static func build(duck_bottom: float) -> AnimationNodeStateMachine:
	var locomotion := PlayerAnimation.STATE_LOCOMOTION
	var jump := PlayerAnimation.STATE_JUMP
	var fall := PlayerAnimation.STATE_FALL
	var land := PlayerAnimation.STATE_LAND
	var crouch := PlayerAnimation.STATE_CROUCH
	var machine := AnimationNodeStateMachine.new()
	machine.add_node(locomotion, _locomotion(), Vector2(200, 100))
	machine.add_node(jump, _clip(&"Jump"), Vector2(400, 0))
	machine.add_node(fall, _clip(&"Jump_Idle"), Vector2(600, 100))
	machine.add_node(land, _clip(&"Jump_Land"), Vector2(400, 200))
	machine.add_node(crouch, _crouch(duck_bottom), Vector2(200, 250))
	machine.add_transition(&"Start", locomotion, _transition(0.0, false))
	machine.add_transition(locomotion, jump, _transition(0.08, false))
	machine.add_transition(locomotion, fall, _transition(0.15, false))
	machine.add_transition(jump, fall, _transition(0.1, true))
	machine.add_transition(jump, land, _transition(0.05, false))
	machine.add_transition(fall, land, _transition(0.05, false))
	machine.add_transition(land, locomotion, _transition(0.15, true))
	machine.add_transition(land, jump, _transition(0.08, false))
	machine.add_transition(locomotion, crouch, _transition(0.15, false))
	machine.add_transition(crouch, locomotion, _transition(0.15, false))
	machine.add_transition(crouch, fall, _transition(0.15, false))
	return machine


static func _transition(fade: float, at_end: bool) -> AnimationNodeStateMachineTransition:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = fade
	if at_end:
		transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	return transition


## The held Duck pose (a short loop around its lowest second) with the Walk laid over by `mix`.
static func _crouch(duck_bottom: float) -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	var duck := _clip(&"Duck")
	duck.use_custom_timeline = true
	duck.start_offset = maxf(duck_bottom - PlayerAnimation.DUCK_HOLD * 0.5, 0.0)
	duck.timeline_length = PlayerAnimation.DUCK_HOLD
	duck.loop_mode = Animation.LOOP_LINEAR
	duck.stretch_time_scale = false
	tree.add_node(&"duck", duck)
	tree.add_node(&"walk", _clip(&"Walk"))
	tree.add_node(&"walk_rate", AnimationNodeTimeScale.new())
	tree.connect_node(&"walk_rate", 0, &"walk")
	tree.add_node(&"mix", AnimationNodeBlend2.new())
	tree.connect_node(&"mix", 0, &"duck")
	tree.connect_node(&"mix", 1, &"walk_rate")
	tree.connect_node(&"output", 0, &"mix")
	return tree


static func _locomotion() -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	var move := AnimationNodeBlendSpace1D.new()
	move.min_space = 0.0
	move.max_space = 1.0
	move.sync = true  # Walk and Run differ in length: keep their steps in phase
	move.add_blend_point(_clip(&"Idle"), 0.0, -1, &"idle")
	move.add_blend_point(_clip(&"Walk"), PlayerAnimation.WALK_POINT, -1, &"walk")
	move.add_blend_point(_clip(&"Run"), 1.0, -1, &"run")
	tree.add_node(&"move", move)
	tree.add_node(&"run_speed", AnimationNodeTimeScale.new())
	tree.connect_node(&"run_speed", 0, &"move")
	# Aiming: the four directions around Idle; the clips share their length and step together,
	# so a diagonal is two of them in phase.
	var aim_move := AnimationNodeBlendSpace2D.new()
	aim_move.sync = true
	aim_move.add_blend_point(_clip(&"Idle"), Vector2.ZERO, -1, &"idle")
	var moves := PlayerAnimation.AIM_MOVES
	for clip: StringName in moves:
		aim_move.add_blend_point(
			_clip(clip), moves[clip], -1, StringName(String(clip).to_snake_case())
		)
	tree.add_node(&"aim_move", aim_move)
	tree.add_node(&"aim_rate", AnimationNodeTimeScale.new())
	tree.connect_node(&"aim_rate", 0, &"aim_move")
	tree.add_node(&"aim_blend", AnimationNodeBlend2.new())
	tree.connect_node(&"aim_blend", 0, &"run_speed")
	tree.connect_node(&"aim_blend", 1, &"aim_rate")
	tree.connect_node(&"output", 0, &"aim_blend")
	return tree


static func _clip(clip_name: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip_name
	return node

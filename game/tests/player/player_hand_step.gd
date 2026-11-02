class_name PlayerHandStep
extends RefCounted
## One physics tick of a `Player`, taken by hand and now.
##
## A suite that steps the game by hand must not also wait a real physics frame for each tick: that
## ties it to the clock (60 ticks a second, 1,200 ticks = 20 s) and the CI job to the sum of every
## such wait. The suite switches the player's own `_physics_process` off once
## (`player.set_physics_process(false)`) and calls `tick` instead, back to back; the tick is the
## same code the engine would call (the submitted command, or the sampled controls), so it plays the
## same. Waiting a frame is for what only a frame does (the skeleton's modifiers, the layout), once
## per measurement and not once per tick (docs/research/ci-time.md).


## What the engine does at the start of a physics frame: the input it has buffered reaches the
## Input singleton, then the player takes its tick with the submitted command or the controls.
static func tick(player: Player) -> void:
	Input.flush_buffered_events()
	player._physics_process(player.get_physics_process_delta_time())

class_name NightFixture
extends RefCounted
## Helpers for the night suites: a night built and started, ticks run by hand.

const STEP := Night.STEP


## A night in `mode`, added to `parent`, ready to play. `rules_tuning` replaces the shipped table.
static func start(
	parent: Node, mode: Night.Mode, rules_tuning: RulesTuning = null, seed_value: int = 7
) -> Night:
	var night := Night.new()
	parent.add_child(night)
	await night.start(mode, seed_value, rules_tuning)
	return night


## Runs `count` ticks of a night driven by hand, sending `command` before each one.
static func run(night: Night, count: int, command: NightCommand = null) -> void:
	for _i in count:
		if command != null:
			night.link.send(command.to_dict())
		night.tick()


## A command that looks at `target` from the player and holds the trigger.
static func shoot_at(night: Night, target: Vector3) -> NightCommand:
	var command := NightCommand.new()
	var eye := night.state.position() + Vector3(0.0, Autopilot.EYE, 0.0)
	command.origin = eye
	command.dir = (target + Vector3(0.0, Autopilot.CHEST, 0.0) - eye).normalized()
	command.fire = true
	return command


## Ends the break and runs until the first zombie is on the lot; returns its id.
static func first_zombie(night: Night) -> int:
	night.server.rules.apply(RulesAction.skip_break())
	for _i in 600:
		night.tick()
		if not night.server.sim.zombies.is_empty():
			return night.server.sim.zombies.keys()[0]
	return -1

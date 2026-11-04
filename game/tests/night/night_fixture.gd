class_name NightFixture
extends RefCounted
## Helpers for the night suites: a night built and started, ticks run by hand.

const STEP := Night.STEP


## A night in `mode`, added to `parent`, ready to play. `rules_tuning` replaces the shipped table;
## `hud`, when given, hears the night from its first event; `night_tuning` replaces the shipped
## night numbers.
static func start(
	parent: Node,
	mode: Night.Mode,
	rules_tuning: RulesTuning = null,
	seed_value: int = 7,
	hud: Hud = null,
	night_tuning: NightTuning = null
) -> Night:
	var night := Night.new()
	night.hud = hud
	night.night_tuning = night_tuning
	parent.add_child(night)
	await night.start(mode, seed_value, rules_tuning)
	return night


## A night with `players` seated (ids 1 to `players`) and a bot host to put bots on, with no client
## of its own (`SeatedNight`). Add the bots with `seat`, run it with `tick` and `run`.
static func seat(
	parent: Node,
	players: int,
	rules_tuning: RulesTuning = null,
	seed_value: int = 7,
	shopping: bool = false,
	scene: PackedScene = null,
	indexed: bool = true
) -> SeatedNight:
	return await SeatedNight.start(
		parent, players, rules_tuning, seed_value, shopping, scene, indexed
	)


## Runs `count` ticks of a night driven by hand, sending `command` before each one.
static func run(night: Night, count: int, command: NightCommand = null) -> void:
	for _i in count:
		if command != null:
			night.link.send(command.to_dict())
		night.tick()


## Waits until the navigation bake a bought door started has landed: freeing a night under a bake
## on its worker thread can crash the engine at exit.
static func settle_bake(night: Night, frames: int = 1800) -> void:
	for _i in frames:
		if not night.world.navigation.is_busy():
			return
		await night.get_tree().physics_frame


## A command that looks at `target` from the player and holds the trigger.
static func shoot_at(night: Night, target: Vector3) -> NightCommand:
	var command := NightCommand.new()
	var eye := night.state.position() + Vector3(0.0, Autopilot.EYE, 0.0)
	command.origin = eye
	command.aim_along(target + Vector3(0.0, Autopilot.CHEST, 0.0) - eye)
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


## The shipped table with round 1 a round of only `type_id`, so a night shows one type at once.
static func only_tuning(type_id: StringName) -> RulesTuning:
	var tuning := RulesFixture.tuning()
	var special := SpecialRound.new()
	special.id = StringName("only_%s" % type_id)
	special.title = "Only %s" % type_id
	special.kind = SpecialRound.Kind.ONLY
	special.only_type = type_id
	special.count_fraction = 1.0
	special.spawn_rate = 2.0
	_make_round_one_special(tuning, special)
	return tuning


## The shipped table with round 1 the shipped boss night (a headliner among escorts).
static func boss_tuning() -> RulesTuning:
	return special_tuning(&"double_feature")


## The shipped table with round 1 the shipped special round `special_id` (`double_feature`,
## `stampede`, `crawl_space`), with the id and rules the game has for it.
static func special_tuning(special_id: StringName) -> RulesTuning:
	var tuning := RulesFixture.tuning()
	for special in tuning.specials.rounds:
		if special.id == special_id:
			_make_round_one_special(tuning, special)
	return tuning


static func _make_round_one_special(tuning: RulesTuning, special: SpecialRound) -> void:
	var rounds: Array[SpecialRound] = [special]
	tuning.specials.rounds = rounds
	tuning.specials.first_round = 1
	tuning.specials.every = 1


## Ends the break and runs until a zombie of `type_id` is on the lot; returns its id (-1 if none).
static func first_of_type(night: Night, type_id: StringName, max_ticks: int = 3000) -> int:
	night.server.rules.apply(RulesAction.skip_break())
	for _i in max_ticks:
		night.tick()
		for zombie_id: int in night.server.sim.zombies:
			var body: ZombieBody = night.server.sim.zombies[zombie_id]
			if body.profile.type == type_id:
				return zombie_id
	return -1

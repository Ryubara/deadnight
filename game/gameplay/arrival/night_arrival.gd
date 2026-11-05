class_name NightArrival
extends RefCounted
## The arrival by helicopter as a `Night` runs it (#1057): when the show is due, how it begins (the
## server is told, the body is hidden, the controls are the show's), what a command made meanwhile
## is
## (nothing), and how it ends (the body is back, the server is told, the black comes away). The show
## itself is `ArrivalCutscene`; the shield the server keeps meanwhile is `ArrivalPlay`.

## Whether a drop was shown in this run of the game: `ArrivalTuning.Repeat.FIRST_PER_SESSION`.
static var shown := false


## Forgets that a show was seen (a test starts a session again).
static func reset() -> void:
	shown = false


## Whether the show is due: asked for, a person's night, in the tuning, and not yet seen this
## session
## when the tuning says once a session.
static func due(night: Night) -> bool:
	if not night.arrival or night.mode != Night.Mode.HUMAN or night.rules_tuning == null:
		return false
	if night.arrival_show != null or night.player() == null:
		return false
	var tuning := night.rules_tuning.arrival
	if not tuning.enabled:
		return false
	return tuning.repeat == ArrivalTuning.Repeat.ALWAYS or not shown


## The night's opening (the first break, before any round) or a night already going.
static func is_fresh(night: Night) -> bool:
	if not night.remote:
		return true
	return night.state.phase() == GameRules.Phase.BREAK and night.state.round_number() == 0


## Builds the show over the player's body, tells the server it began and takes the body, the mouse
## look and the HUD out of the player's hands.
static func begin(night: Night) -> void:
	var body := night.player()
	shown = true
	var seat := (
		night.looks.seats.get(night.state.player_id, maxi(night.state.player_id - 1, 0)) as int
	)
	var show := ArrivalCutscene.new()
	show.name = "ArrivalCutscene"
	night.add_child(show)
	night.arrival_show = show
	show.begin(
		night.rules_tuning.arrival,
		is_fresh(night),
		body.global_position,
		body.state.facing,
		night.worn_look(),
		seat,
		body.camera_rig.camera(),
		hides(night)
	)
	body.set_arriving(true)
	body.look_locked = true
	show.finished.connect(func(_skipped: bool) -> void: finish(night, body))
	night.link.send(
		{"type": NightServer.ARRIVAL, "player_id": night.state.player_id, "begin": true}
	)
	night.arrival_started.emit()


## The nodes of the lot over the landing spot, hidden while the show looks down at it: a roof.
static func hides(night: Night) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for path in ArrivalCutscene.ROOF_NODES:
		var roof := night.world.greybox.get_node_or_null(path) as Node3D
		if roof != null:
			found.append(roof)
	return found


## The show is over, at black: the player's body is back and theirs, the server is told, and the
## night comes back from the black.
static func finish(night: Night, body: Player) -> void:
	if is_instance_valid(body):
		body.set_arriving(false)
		body.look_locked = false
	if night.link != null:
		night.link.send(
			{"type": NightServer.ARRIVAL, "player_id": night.state.player_id, "begin": false}
		)
	night.arrival_show.spawn_in()
	night.arrival_ended.emit()


## What the night does with a command made while the show plays: nothing at all.
static func quiet(command: NightCommand) -> void:
	command.motion.move = Vector2.ZERO
	command.motion.sprint = false
	command.motion.crouch = false
	command.motion.aim = false
	command.motion.fire = false
	command.motion.jump = false
	command.motion.melee = false
	command.motion.swap_shoulder = false
	command.motion.throw_over = false
	command.motion.throw_under = false
	command.fire = false
	command.reload = false
	command.use = false
	command.use_held = false
	command.swap = false
	command.slot = WeaponSlots.NONE

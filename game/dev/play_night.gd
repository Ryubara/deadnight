class_name PlayNight
extends Node
## A developer's way into the game: run this scene (F6 in the editor) and a solo night starts at
## once, with no menu. Select the `PlayNight` node and set the options in the inspector first.
## Not part of the shipped game (the menu's Play goes to `ui/screens/night_screen.tscn`).
##
## It builds what the night screen builds (the night on the lot, the HUD over it) and starts it
## the way a person's night starts, then applies what the options ask for. The tuning is a copy,
## so a changed option never edits a `.tres`.

@export_group("Night")
## The round to start in. 1 is a normal night: the first break, then round 1. Higher rounds start
## at once, with that round's zombie count, health and speed (`RoundTuning`).
@export_range(1, 60) var start_round := 1
## The night's dice. The same seed gives the same night when played the same way.
@export var seed_value := Night.SEED
## The bot plays instead of you, seen over its shoulder (watch a tuning change play out).
@export var autopilot := false
## Skip the break before the first round. Off waits the intro break out as the game does.
@export var skip_intro := true
## Draw and load everything once behind a loading screen first, as the game does. Off starts at
## once but the first shots and zombies may hitch. A headless run never warms up.
@export var warm_up := true

@export_group("Rules")
## The tuning table the night plays with. Point it at another `.tres` of `RulesTuning` to try a
## variant; the default is the shipped `default_tuning.tres`. Null uses the shipped one.
@export var rules_tuning: RulesTuning = preload("res://gameplay/rules/default_tuning.tres")
## Points to start with. -1 keeps the tuning's own (`EconomyTuning.start_points`).
@export var starting_points := -1

@export_group("Cheats")
## Health is topped up every tick: the dead cannot down you.
@export var god_mode := false
## Every carried gun is refilled every tick: no reloading, no running dry.
@export var infinite_ammo := false

var night: Night

var hud: Hud
var _result: Label


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = (load(Hud.SCENE) as PackedScene).instantiate()
	layer.add_child(hud)
	night = Night.new()
	night.hud = hud
	night.warm_up = warm_up and NightScreen.warm_up_enabled
	night.shoulder_camera = autopilot
	add_child(night)
	if night.warm_up:
		var loading := LoadingOverlay.new()
		layer.add_child(loading)
		night.loading.connect(loading.show_progress)
		night.ready_to_play.connect(loading.finish)
	night.night_over.connect(_on_night_over)
	var mode := Night.Mode.AUTOPILOT if autopilot else Night.Mode.HUMAN
	await night.start(mode, seed_value, _tuning())
	_skip_ahead()
	night.ticked.connect(_on_tick)


## A private copy of the chosen table with the options applied.
func _tuning() -> RulesTuning:
	var source := rules_tuning
	if source == null:
		source = load(GameRules.DEFAULT_TUNING_PATH)
	var tuning := source.duplicate(true) as RulesTuning
	if starting_points >= 0:
		tuning.economy.start_points = starting_points
	return tuning


## Starts the round asked for: the rules count up from the round before it. The server forgets
## events it caused between two ticks, so they go straight to the client, which is what feeds the
## HUD.
func _skip_ahead() -> void:
	night.server.rules.round_number = start_round - 1
	if skip_intro or start_round > 1:
		night.state.apply_events(night.server.rules.apply(RulesAction.skip_break()))


func _on_tick() -> void:
	var rules := night.server.rules
	var player := rules.players.get(Night.PLAYER_ID) as PlayerState
	if god_mode and player != null and not player.downed:
		player.health = player.max_health
	if infinite_ammo:
		for weapon_id: StringName in night.server.combat.carried(Night.PLAYER_ID):
			var weapon := night.server.combat.state_of(Night.PLAYER_ID, weapon_id)
			if weapon.uses_ammo():
				weapon.ammo = weapon.def.magazine_size
				weapon.reserve = weapon.def.reserve_max


func _on_night_over(round_reached: int) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_result = Label.new()
	_result.text = "You did not make it: round %d. Run the scene again." % round_reached
	_result.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hud.add_child(_result)

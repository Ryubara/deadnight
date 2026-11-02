extends Node
## The zombies of a night over time, from the rules alone (no window needed): a player who kills
## every zombie `--life` seconds (default 7) after it stands. Prints `CSV,<t>,<round>,<alive>,
## <queued>` every half second, for as many rounds as `--rounds` (default 5). Arguments after `--`:
## `--count`, `--max-alive`, `--break` (the match settings), `--seed`. Not part
## of the game.

const STEP := 1.0 / 30.0
const EVERY := 0.5


func _ready() -> void:
	var args := _parse_args()
	var settings := MatchSettings.new()
	settings.count_multiplier = float(args.get("count", 1.0))
	settings.max_alive = int(args.get("max-alive", 0))
	settings.break_seconds = float(args.get("break", 0.0))
	var life := float(args.get("life", 7.0))
	var rounds := int(args.get("rounds", 5))
	var rules := GameRules.new(null, int(args.get("seed", 1)), settings.clamped())
	rules.apply(RulesAction.add_player(1))
	rules.apply(RulesAction.start())
	var born := {}
	var t := 0.0
	var next_print := 0.0
	while rules.round_number < rounds or rules.phase == GameRules.Phase.ACTIVE:
		for event in rules.apply(RulesAction.tick(STEP)):
			if event["type"] == &"zombie_spawn_requested":
				born[event["zombie_id"]] = t
		t += STEP
		for zombie_id in rules.zombie_ids():
			if t - born.get(zombie_id, t) >= life:
				rules.apply(RulesAction.hit(1, zombie_id, RulesAction.ZONE_BODY, 99999.0))
		if t >= next_print:
			next_print += EVERY
			var queued: int = rules.to_dict()["spawn_left"]
			print("CSV,%.1f,%d,%d,%d" % [t, rules.round_number, rules.zombie_ids().size(), queued])
		if t > 1800.0:
			break
	get_tree().quit()


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed

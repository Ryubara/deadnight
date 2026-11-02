class_name RulesSnapshot
extends RefCounted
## `GameRules`' snapshot in and out: `take` reads every field a night is made of, `restore`
## checks a dictionary and puts it back. They reach into the rules' own fields (the leading
## underscore marks what a caller outside the rules leaves alone) because a snapshot is the one
## thing that must hold all of them; the layout is `GameRules.SNAPSHOT_KEYS` and its version.


## Everything, as plain Variant data (see `GameRules.to_dict`).
static func take(rules: GameRules) -> Dictionary:
	var player_data := {}
	for player_id in rules.players:
		player_data[player_id] = rules.players[player_id].to_dict()
	var zombie_data := {}
	for zombie_id in rules._zombies:
		zombie_data[zombie_id] = rules._zombies[zombie_id].to_dict()
	return {
		"version": GameRules.SNAPSHOT_VERSION,
		"tuning_id": rules.tuning.fingerprint(),
		"seed": rules.rng_seed,
		"phase": rules.phase,
		"round": rules.round_number,
		"break_left": rules._break_left,
		"plan": rules._plan.duplicate(),
		# How many are still to spawn: derived from the plan, for readers that only count (the HUD).
		"spawn_left": rules._plan.size(),
		"special_id": String(rules._special.id) if rules._special != null else "",
		"round_total": rules._round_total,
		"spawn_timer": rules._spawn_timer,
		"round_players": rules._round_players,
		"next_zombie_id": rules._next_zombie_id,
		"zombies": zombie_data,
		"players": player_data,
		"doors_open": rules.doors_open.duplicate(),
		"generator": rules.generator.to_dict(),
		"barricades": rules.barricades.to_dict(),
		"crane": rules.crane.to_dict(),
		"match_settings": rules.settings.to_dict(),
		"round_elapsed": rules._round_elapsed,
		"spawn_rng_state": rules._spawn_rng.state,
		"shop_rng_state": rules._shop_rng.state,
		"cripple_rng_state": rules._cripple_rng.state,
		"crane_rng_state": rules._crane_rng.state,
	}


## Replaces `rules`' state with a snapshot (see `GameRules.from_dict`). Returns `&""` when it
## worked, else why it did not, with the night left untouched.
static func restore(rules: GameRules, data: Dictionary) -> StringName:
	# The version first: an older layout has other keys and would otherwise look damaged.
	if not data.has("version") or typeof(data["version"]) != TYPE_INT:
		return GameRules.RESTORE_MALFORMED
	if data["version"] != GameRules.SNAPSHOT_VERSION:
		return GameRules.RESTORE_BAD_VERSION
	if not SnapshotCheck.fits(data, GameRules.SNAPSHOT_KEYS):
		return GameRules.RESTORE_MALFORMED
	if data["tuning_id"] != rules.tuning.fingerprint():
		return GameRules.RESTORE_WRONG_TUNING
	if not SnapshotCheck.insides_fit(data, rules.tuning):
		return GameRules.RESTORE_MALFORMED
	rules.rng_seed = data["seed"]
	rules.phase = data["phase"]
	rules.round_number = data["round"]
	rules._break_left = data["break_left"]
	rules._plan.assign(data["plan"])
	rules._special = rules.tuning.specials.by_id(StringName(data["special_id"]))
	rules._round_total = data["round_total"]
	rules._spawn_timer = data["spawn_timer"]
	rules._round_players = data["round_players"]
	rules._round_elapsed = data["round_elapsed"]
	rules.settings = MatchSettings.from_dict(data["match_settings"])
	rules._next_zombie_id = data["next_zombie_id"]
	rules._zombies.clear()
	for zombie_id in data["zombies"]:
		rules._zombies[zombie_id] = ZombieState.from_dict(data["zombies"][zombie_id])
	rules.players.clear()
	for player_id in data["players"]:
		rules.players[player_id] = PlayerState.from_dict(data["players"][player_id])
	rules.doors_open.assign(data["doors_open"])
	rules.generator.restore(data["generator"])
	rules.barricades.restore(data["barricades"])
	rules.crane.restore(data["crane"])
	rules._fuel_announced = floori(rules.generator.fuel)
	rules._spawn_rng.seed = rules.rng_seed ^ GameRules.SPAWN_STREAM
	rules._spawn_rng.state = data["spawn_rng_state"]
	rules._shop_rng.seed = rules.rng_seed ^ GameRules.SHOP_STREAM
	rules._shop_rng.state = data["shop_rng_state"]
	rules._cripple_rng.seed = rules.rng_seed ^ GameRules.CRIPPLE_STREAM
	rules._cripple_rng.state = data["cripple_rng_state"]
	rules._crane_rng.seed = rules.rng_seed ^ GameRules.CRANE_STREAM
	rules._crane_rng.state = data["crane_rng_state"]
	return &""

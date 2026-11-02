extends Node
## The boss-night parity run of the bots plan (phase 3): four hosted bots of one profile play the
## first boss night (round 5, Double Feature) in the real server, night after night, and the share
## that pass it is printed, to be set beside the balance simulator's prediction for the same skill.
## A local or nightly measurement, not a test: a night is a minute or two of wall time. Not part of
## the game.
##
## `godot --headless --path game res://tests/captures/bots_boss_night.tscn -- --profile=regular
## --nights=30 --seed=1 --loadout=weapon_rifle,weapon_shotgun`
## Arguments after `--`: `--profile=rookie|regular|veteran`, `--nights=N`, `--seed=S` (the first
## seed; night n uses S + n), `--loadout=` the shop items each bot is given, in order, `--seconds=N`
## (the longest a night is played), `--topoff=0.5` (the share of a weapon's reserve limit each bot
## carries, the simulator's `ammo_topoff`: 0.5 for the weak level, 1 for the others) and
## `--set=boss_keep=2,retreat_margin=1` (profile fields to change). Prints one `NIGHT {json}` per
## night and `PARITY {json}` at the end.

var _args := {}


func _ready() -> void:
	_args = _parse_args()
	var title := String(_args.get("profile", "regular"))
	var nights := int(_args.get("nights", 20))
	var first_seed := int(_args.get("seed", 1))
	var seconds := int(_args.get("seconds", BossNight.DEFAULT_SECONDS))
	var loadout: Array[StringName] = []
	for item in String(_args.get("loadout", "")).split(",", false):
		loadout.append(StringName(item))
	var makers := {
		"rookie": BotProfile.rookie, "regular": BotProfile.regular, "veteran": BotProfile.veteran
	}
	var base: Callable = makers.get(title, BotProfile.regular)
	var overrides := _overrides()
	var maker := func() -> BotProfile:
		var profile: BotProfile = base.call()
		for field in overrides:
			profile.set(field, overrides[field])
		return profile
	var passed := 0
	var total_seconds := 0.0
	for n in nights:
		var outcome := await BossNight.play(
			self, maker, first_seed + n, loadout, seconds, float(_args.get("topoff", 1.0))
		)
		passed += 1 if outcome["passed"] else 0
		total_seconds += outcome["seconds"]
		print(
			"NIGHT ", JSON.stringify({"profile": title, "seed": first_seed + n, "outcome": outcome})
		)
	print(
		"PARITY ",
		(
			JSON
			. stringify(
				{
					"profile": title,
					"nights": nights,
					"passed": passed,
					"share": float(passed) / float(maxi(nights, 1)),
					"mean_seconds": total_seconds / float(maxi(nights, 1)),
					"loadout": _args.get("loadout", ""),
				}
			)
		)
	)
	get_tree().quit()


## `--set=field=value,field=value`: numbers set on every profile before a night (a sweep).
func _overrides() -> Dictionary:
	var found := {}
	for pair in String(_args.get("set", "")).split(",", false):
		var parts := pair.split("=")
		if parts.size() == 2:
			found[parts[0]] = float(parts[1])
	return found


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var parts := arg.substr(2).split("=", true, 1)
			parsed[parts[0]] = parts[1]
	return parsed

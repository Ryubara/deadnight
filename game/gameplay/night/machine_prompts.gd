class_name MachinePrompts
extends RefCounted
## The words on the prompt card at the lot's machines: what `MachineOffers` found, put on the
## HUD's card (`HudState.set_prompt`). The numbers a re-cut or a perk gives come from the rules'
## tuning, so the card never says what the machine will not do.

const RECUT_NAME := "Re-cut bench"
## The bench's answer for a weapon that was re-cut already: the rule, not just the fact (#909).
const RECUT_DONE := "ALREADY RE-CUT. A WEAPON CAN BE RE-CUT ONCE"
const TONIC_NAME := "Tonic"


## Puts `prompt` on the card when it is a machine's and returns true; false for any other kind.
static func show(
	state: HudState,
	prompt: Dictionary,
	weapon_names: Dictionary,
	spec: UpgradeTuning,
	perks: PerkTuning = null
) -> bool:
	match prompt.get("kind", &""):
		&"recut":
			var weapon: String = weapon_names.get(prompt["weapon"], str(prompt["weapon"]))
			_put(
				state,
				&"buy_recut",
				"Re-cut: %s" % weapon,
				prompt["price"],
				_gain(spec, StringName(prompt["weapon"]))
			)
		&"recut_done":
			_put(state, &"recut_info", RECUT_NAME, 0, RECUT_DONE)
		&"recut_none":
			_put(state, &"recut_info", RECUT_NAME, 0, "NOTHING TO RE-CUT IN YOUR HAND")
		&"tonic":
			var detail := blurb(prompt["effect"], prompt["bonus"], perks)
			_put(state, &"buy_tonic", _name(prompt), prompt["price"], detail)
		&"tonic_owned":
			_put(state, &"tonic_info", _name(prompt), 0, "YOU HAVE HAD YOURS")
		&"tonic_full":
			var limit := "YOU CARRY %d TONICS, THE MOST" % int(prompt["limit"])
			_put(state, &"tonic_info", _name(prompt), 0, limit)
		_:
			return false
	return true


static func _name(prompt: Dictionary) -> String:
	var named: String = prompt.get("name", "")
	return named if named != "" else TONIC_NAME


## What a perk does, in one plain line on the card. The numbers are the tuning's.
static func blurb(effect: int, bonus: float, perks: PerkTuning) -> String:
	var spec := perks if perks != null else PerkTuning.new()
	match effect:
		ShopItem.Effect.HEALTH:
			return "+%d MOST HEALTH" % roundi(bonus)
		ShopItem.Effect.FIRE_RATE:
			return "FIRES %d%% FASTER" % roundi((spec.fire_rate_multiplier - 1.0) * 100.0)
		ShopItem.Effect.RELOAD_SPEED:
			return "RELOADS %d%% FASTER" % roundi((1.0 / spec.reload_time_scale - 1.0) * 100.0)
		ShopItem.Effect.EXTRA_WEAPON:
			return (
				"CARRY %d WEAPONS INSTEAD OF %d"
				% [WeaponCatalog.CARRY_LIMIT + spec.extra_weapons, WeaponCatalog.CARRY_LIMIT]
			)
		ShopItem.Effect.REVIVE:
			return (
				"REVIVE TEAMMATES %d%% FASTER. GETS YOU UP ALONE, %d TIMES A NIGHT"
				% [roundi((1.0 / spec.revive_time_scale - 1.0) * 100.0), spec.self_revive_uses]
			)
		ShopItem.Effect.SHOCK:
			return "RELOADING SHOCKS THE DEAD WITHIN %s M" % String.num(spec.shock_radius, 1)
	return ""


## What a re-cut does to this weapon, in the card's words: "DAMAGE x1.75, ROUNDS x1.5".
static func _gain(spec: UpgradeTuning, weapon: StringName) -> String:
	var cut := spec.profile_of(WeaponCatalog.catalog_id(weapon))
	if cut == null:
		return ""
	return cut.card_line(WeaponCatalog.get_def(WeaponCatalog.catalog_id(weapon)))


static func _put(
	state: HudState, kind: StringName, label: String, cost: int, detail: String
) -> void:
	var now := state.prompt
	if (
		now.get("kind") != kind
		or now.get("label") != label
		or now.get("cost") != cost
		or now.get("detail") != detail
	):
		state.set_prompt(kind, label, cost, detail)

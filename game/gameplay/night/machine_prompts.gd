class_name MachinePrompts
extends RefCounted
## The words on the prompt card at the lot's two machines: what `MachineOffers` found, put on the
## HUD's card (`HudState.set_prompt`). The numbers a re-cut gives come from the rules' tuning, so
## the card never says what the weapon will not do.

const RECUT_NAME := "Re-cut bench"
const TONIC_NAME := "Hearty tonic"


## Puts `prompt` on the card when it is a machine's and returns true; false for any other kind.
static func show(
	state: HudState, prompt: Dictionary, weapon_names: Dictionary, spec: UpgradeTuning
) -> bool:
	match prompt.get("kind", &""):
		&"recut":
			var weapon: String = weapon_names.get(prompt["weapon"], str(prompt["weapon"]))
			_put(state, &"buy_recut", "Re-cut: %s" % weapon, prompt["price"], _gain(spec))
		&"recut_done":
			_put(state, &"recut_info", RECUT_NAME, 0, "THIS WEAPON IS ALREADY RE-CUT")
		&"recut_none":
			_put(state, &"recut_info", RECUT_NAME, 0, "NOTHING TO RE-CUT IN YOUR HAND")
		&"tonic":
			var detail := "+%d MOST HEALTH" % roundi(prompt["bonus"])
			_put(state, &"buy_tonic", TONIC_NAME, prompt["price"], detail)
		&"tonic_owned":
			_put(state, &"tonic_info", TONIC_NAME, 0, "YOU HAVE HAD YOURS")
		_:
			return false
	return true


## What a re-cut does, in the card's words: "DAMAGE x1.75, ROUNDS x1.5".
static func _gain(spec: UpgradeTuning) -> String:
	return (
		"DAMAGE x%s, ROUNDS x%s"
		% [String.num(spec.damage_multiplier, 2), String.num(spec.magazine_multiplier, 2)]
	)


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

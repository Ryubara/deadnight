class_name NightReadout
extends RefCounted
## The plain-text readout of a night, built from a `ClientState`. It stands in until the HUD (#89)
## binds to the same events; it is also what the captures print on the frame.


static func text_for(state: ClientState) -> String:
	var me := state.me()
	var weapon: StringName = me.get("weapon", &"")
	var lines: Array[String] = []
	lines.append(_headline(state))
	lines.append(
		(
			"points %d     health %d     %s %d / %d%s"
			% [
				state.points(),
				roundi(me.get("health", 0.0)),
				weapon,
				me.get("ammo", 0),
				me.get("reserve", 0),
				"  reloading" if me.get("reloading", false) else ""
			]
		)
	)
	lines.append(
		(
			"zombies left %d     fuel %d     doors open %d"
			% [
				state.frame.get("remaining", 0),
				roundi(state.frame.get("fuel", 0.0)),
				state.frame.get("doors", []).size()
			]
		)
	)
	var prompt: Dictionary = me.get("prompt", {})
	match prompt.get("kind", &""):
		&"door":
			lines.append("[E] open the way: %d points" % prompt["price"])
		&"repair":
			lines.append("[E] put a board back")
	return "\n".join(lines)


static func _headline(state: ClientState) -> String:
	match state.phase():
		GameRules.Phase.BREAK:
			if state.round_number() == 0:
				return "The first round is coming"
			return "Round %d done. Next one soon." % state.round_number()
		GameRules.Phase.OVER:
			return "NIGHT OVER at round %d" % state.round_reached
		GameRules.Phase.ACTIVE:
			return "ROUND %d" % state.round_number()
	return "Get ready"

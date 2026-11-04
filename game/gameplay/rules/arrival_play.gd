class_name ArrivalPlay
extends RefCounted
## The shield of a player's arrival (#1057): a person's client plays a helicopter drop on its own
## screen and says so (`arrival` with `begin`), and until it says it landed (or `cap_seconds` run
## out) the player cannot be hurt, the dead do not turn to them and they take no part in the night,
## so no one walks up to a body nobody sees. A moment after the landing (`grace_seconds`) a blow
## still does nothing. Static functions that take the rules, like `PerkPlay`; nothing here waits for
## the client: the night goes on whatever it does.
##
## Events: `player_dropping` (player_id): the drop began; `player_landed` (player_id): it ended, by
## the client's word or the cap.


## The client of `player` began its drop. Refused (the answer to the sender) for a seat that has had
## its drop, a bot, a player who is down and outside a break or a round.
static func begin(rules: GameRules, player_id: int) -> void:
	var player := rules.players.get(player_id) as PlayerState
	var refusal := &""
	if player == null:
		refusal = &"unknown_player"
	elif not rules.tuning.arrival.enabled:
		refusal = &"arrival_off"
	elif rules.phase != GameRules.Phase.BREAK and rules.phase != GameRules.Phase.ACTIVE:
		refusal = &"wrong_phase"
	elif player.bot:
		refusal = &"bot"
	elif player.dropped:
		refusal = &"already_dropped"
	elif player.downed:
		refusal = &"player_downed"
	if refusal != &"":
		rules._reject(refusal, RulesAction.ARRIVAL)
		return
	player.dropped = true
	player.drop_left = rules.tuning.arrival.cap_seconds
	rules._emit(&"player_dropping", {"player_id": player_id})


## The client of `player` says it landed (it faded out, or the player skipped).
static func land(rules: GameRules, player_id: int) -> void:
	var player := rules.players.get(player_id) as PlayerState
	if player == null:
		rules._reject(&"unknown_player", RulesAction.ARRIVAL)
	elif not player.is_dropping():
		rules._reject(&"not_dropping", RulesAction.ARRIVAL)
	else:
		_land(rules, player)


## One step: the cap runs down on the ones still in the helicopter, the grace on the ones landed.
static func tick(rules: GameRules, delta: float) -> void:
	for player: PlayerState in rules.players.values():
		if player.drop_left > 0.0:
			player.drop_left -= delta
			if player.drop_left <= 0.0:
				_land(rules, player)
		elif player.grace_left > 0.0:
			player.grace_left = maxf(player.grace_left - delta, 0.0)


static func _land(rules: GameRules, player: PlayerState) -> void:
	player.drop_left = 0.0
	player.grace_left = rules.tuning.arrival.grace_seconds
	rules._emit(&"player_landed", {"player_id": player.id})

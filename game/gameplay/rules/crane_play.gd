class_name CranePlay
extends RefCounted
## The prize crane's play, as the rules run it: the steps of a play on `GameRules.crane` (a
## `CraneState`), in static functions that take the rules so no reference cycle is made.
##
## A play runs in stages: SPIN (the claw digs, prizes cycle), then GRAB (the prize floats, only the
## buyer may take it) or, when the play breaks the crane down, LEAVING (the dud shows, the price
## comes back, the crane hops to another spot). Whether it breaks is decided at the purchase. The
## tuning is `CraneTuning`. Events (fields besides `type`):
##
##   crane_spin_started: player_id (the buyer), spot, seconds, plays (at this spot, this one
##     included); right after the purchase's points_changed and purchase_made
##   crane_prize_ready: player_id, spot, weapon (a shop id such as weapon_rifle), seconds (the
##     window in which only that player can take it)
##   crane_prize_taken: player_id, spot, weapon
##   crane_prize_lost: player_id, spot, weapon, reason (expired, or left when the buyer went)
##   crane_take_denied: player_id, reason (not_buyer, nothing_to_take, downed, already_owned)
##   crane_breakdown: player_id, spot, refund, seconds (until the crane is gone); the dud shows,
##     the price comes back as a points_changed (reason refund)
##   crane_moved: from_spot, to_spot


## Takes the play: the stage, and the rolls for the breakdown. The weapon is drawn when the spin
## ends, from what the buyer then lacks.
static func start(rules: GameRules, player: PlayerState, price: int) -> Dictionary:
	var crane := rules.crane
	var cfg := rules.tuning.crane
	# A crane with nowhere else to go (every other spot is behind a closed door) cannot leave.
	var roll := rules._crane_rng.randf()
	crane.breaks = not open_spots(rules).is_empty() and roll < cfg.leave_chance(crane.plays)
	crane.plays += 1
	crane.stage = CraneState.Stage.SPIN
	crane.buyer_id = player.id
	crane.price = price
	crane.weapon = &""
	crane.left = cfg.spin_seconds
	return {"crane_spot": crane.spot}


static func tick(rules: GameRules, delta: float) -> void:
	var crane := rules.crane
	if crane.stage == CraneState.Stage.READY:
		return
	crane.left -= delta
	if crane.left > 0.0:
		return
	match crane.stage:
		CraneState.Stage.SPIN:
			_spin_ended(rules)
		CraneState.Stage.GRAB:
			_prize_lost(rules, &"expired")
		CraneState.Stage.LEAVING:
			_move(rules)


static func _spin_ended(rules: GameRules) -> void:
	var crane := rules.crane
	var cfg := rules.tuning.crane
	var buyer := rules.players.get(crane.buyer_id) as PlayerState
	if crane.breaks:
		var refund := _refund(rules, buyer, roundi(crane.price * cfg.refund_fraction))
		crane.stage = CraneState.Stage.LEAVING
		crane.left = cfg.breakdown_seconds
		(
			rules
			. _emit(
				&"crane_breakdown",
				{
					"player_id": crane.buyer_id,
					"spot": crane.spot,
					"refund": refund,
					"seconds": cfg.breakdown_seconds,
				}
			)
		)
		return
	var item := rules.tuning.economy.item(&"crane_play")
	if item.pool_without(buyer.weapons).is_empty():
		# The buyer got every prize some other way during the spin: the play is paid back.
		_refund(rules, buyer, crane.price)
		_prize_lost(rules, &"none_left")
		return
	crane.weapon = item.roll(buyer.weapons, rules._crane_rng)
	crane.stage = CraneState.Stage.GRAB
	crane.left = cfg.grab_seconds
	(
		rules
		. _emit(
			&"crane_prize_ready",
			{
				"player_id": crane.buyer_id,
				"spot": crane.spot,
				"weapon": crane.weapon,
				"seconds": cfg.grab_seconds,
			}
		)
	)


## Gives `amount` back to the buyer (a refund is not earnings). Returns what was paid.
static func _refund(rules: GameRules, buyer: PlayerState, amount: int) -> int:
	if amount <= 0:
		return 0
	buyer.points += amount
	buyer.points_spent -= amount
	rules._emit(
		&"points_changed",
		{"player_id": buyer.id, "total": buyer.points, "delta": amount, "reason": &"refund"}
	)
	return amount


static func take(rules: GameRules, player_id: int) -> void:
	var crane := rules.crane
	var player := rules.players.get(player_id) as PlayerState
	if player == null:
		rules._reject(&"unknown_player", RulesAction.CRANE_TAKE)
		return
	var denied := &""
	if crane.stage != CraneState.Stage.GRAB:
		denied = &"nothing_to_take"
	elif player_id != crane.buyer_id:
		denied = &"not_buyer"
	elif player.downed:
		denied = &"downed"
	elif player.weapons.has(crane.weapon):
		denied = &"already_owned"
	if denied != &"":
		rules._emit(&"crane_take_denied", {"player_id": player_id, "reason": denied})
		return
	player.weapons.append(crane.weapon)
	rules._emit(
		&"crane_prize_taken", {"player_id": player_id, "spot": crane.spot, "weapon": crane.weapon}
	)
	crane.stage = CraneState.Stage.READY
	crane.buyer_id = -1
	crane.weapon = &""


## The prize was not taken in time, or its buyer left. Nothing is refunded; the crane is free again.
static func _prize_lost(rules: GameRules, reason: StringName) -> void:
	var crane := rules.crane
	rules._emit(
		&"crane_prize_lost",
		{"player_id": crane.buyer_id, "spot": crane.spot, "weapon": crane.weapon, "reason": reason}
	)
	crane.stage = CraneState.Stage.READY
	crane.buyer_id = -1
	crane.weapon = &""


## A buyer who leaves mid-play frees the crane (a breakdown in progress carries on without them).
static func buyer_left(rules: GameRules, player_id: int) -> void:
	var crane := rules.crane
	if crane.buyer_id != player_id:
		return
	if crane.stage == CraneState.Stage.GRAB:
		_prize_lost(rules, &"left")
	elif crane.stage == CraneState.Stage.SPIN:
		crane.stage = CraneState.Stage.READY
		crane.buyer_id = -1


## The spots other than this one that the crane may move to: those whose door is open.
static func open_spots(rules: GameRules) -> Array[int]:
	var crane := rules.crane
	var open: Array[int] = []
	var doors := rules.tuning.crane.spot_doors
	for index in doors.size():
		if index != crane.spot and (doors[index] == &"" or rules.doors_open.has(doors[index])):
			open.append(index)
	return open


## The broken-down crane goes to another open spot, drawn from them; its count of plays starts over.
static func _move(rules: GameRules) -> void:
	var crane := rules.crane
	var from := crane.spot
	var open := open_spots(rules)
	if not open.is_empty():
		crane.spot = open[rules._crane_rng.randi() % open.size()]
	crane.plays = 0
	crane.stage = CraneState.Stage.READY
	crane.buyer_id = -1
	rules._emit(&"crane_moved", {"from_spot": from, "to_spot": crane.spot})

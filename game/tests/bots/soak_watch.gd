class_name SoakWatch
extends RefCounted
## What the nightly bot soak measures about a night (bots plan, phase 7), read from outside the
## bots:
## the server's truth (positions, events) and the bots' own telemetry. `SeatedNight.on_event` feeds
## `hear`, `tick` runs once after every `SeatedNight.tick`, `report` is plain data for one night and
## `verdict` holds a report to the gates of
## `docs/research/bots.md#phase-7-validation-at-scale-and-tuning`.
## Nothing here decides anything for a bot.

## The gates, seconds and metres unless said.
const GATE_STUCK_EPISODE := 10.0
## The share of walking time stuck is judged over a cell, not a bot (one five-second episode in a
## four-minute walk is 2%): `tools/bots/soak_report.py` holds the cell to this.
const GATE_STUCK_SHARE := 0.01
const GATE_IDLE_THREAT := 5.0
const GATE_ROAM_IDLE := 8.0
const GATE_FAR_METRES := 25.0
const GATE_FAR_SECONDS := 20.0
const GATE_HOLD_METRES := 3.0
const GATE_HOLD_SHARE := 0.92
const GATE_FOLLOW_METRES := 12.0
const GATE_FOLLOW_SHARE := 0.95
## A zombie within this many metres of a bot, in its sight, counts as a threat it must not idle
## beside
## (the distance inside which a bot does no errand).
const THREAT_METRES := 12.0
## A body slower than this (m/s) stands.
const STANDING := 0.05
## Metres nearer a zombie must come, while a bot waits, for the wait not to count as idle.
const APPROACH_METRES := 1.0
## Seconds within which the same item refused again counts as a loop.
const LOOP_WINDOW := 30.0
## What a bot is doing when it is on an errand (its `note` starts with one of these), which the
## far-from-the-person gate leaves out.
const ERRAND_NOTES: Array[String] = ["buy", "fuel", "breaker", "boards", "crane"]
## Notes of a bot that stands the stance of the Hold order.
const STANCE_NOTES: Array[String] = ["hold_order", "fight", "throw"]
## Notes of a bot with nothing to do.
const IDLE_NOTES: Array[String] = ["", "hold", "roam"]

const STEP := Night.STEP
## The categories points are counted in.
const CATEGORIES := {
	ShopItem.Kind.DOOR: "door",
	ShopItem.Kind.WEAPON: "weapon",
	ShopItem.Kind.CRANE: "crane",
	ShopItem.Kind.TONIC: "tonic",
	ShopItem.Kind.FUEL: "fuel",
	ShopItem.Kind.GRENADES: "grenades",
	ShopItem.Kind.AMMO: "ammo",
	ShopItem.Kind.UPGRADE: "upgrade",
}

var night: SeatedNight
## Seats played by a stand-in for a person.
var people: Array[int] = []
var order: StringName = BotOrders.ROAM
var hold_spot := Vector3.INF

var ticks := 0
var _seat: Dictionary = {}
var _shot_now: Dictionary = {}
var _hit_now: Dictionary = {}
## The seats that fired in the step just run.
var _fired: Dictionary = {}
## By seat: the signature of the last command sent, and the ticks it has been the same.
var _signature: Dictionary = {}
var _same_for: Dictionary = {}
var _kills_total := 0
var _last_refusal: Dictionary = {}
var _loops := 0
var _denials := 0
var _spread_sum := 0.0
var _spread_n := 0
var _doors: Array[StringName] = []
var _round_marks: Dictionary = {}
## By round: the damage the bots took, the downs, and what the bots carried when it began, so a
## night is read round by round against the simulator's own (`damage`, `died_in`).
var _round_damage: Dictionary = {}
var _round_downs: Dictionary = {}
## By round, then zombie type: [blows that landed, their damage].
var _round_blows: Dictionary = {}
var _round_kit: Dictionary = {}


func _init(p_night: SeatedNight, p_people: Array[int], p_order: StringName) -> void:
	night = p_night
	people = p_people
	order = p_order


func _tally(id: int) -> Dictionary:
	if not _seat.has(id):
		_seat[id] = {
			"up": 0,
			"down": 0,
			"idle_threat_run": 0,
			"idle_threat_longest": 0,
			"idle_samples": [],
			"idle_threat_ref": INF,
			"roam_samples": [],
			"idle_roam_run": 0,
			"idle_roam_longest": 0,
			"far_run": 0,
			"far_longest": 0,
			"far_notes": {},
			"near12": 0,
			"near12_of": 0,
			"stance": 0,
			"stance_held": 0,
			"shots": 0,
			"shot_hits": 0,
			"pellet_hits": 0,
			"heads": 0,
			"weak": 0,
			"kills": 0,
			"downs": 0,
			"deaths": 0,
			"damage_taken": 0.0,
			"spent": {},
			"revived_others": 0,
		}
	return _seat[id]


## One event of the server (the night calls this for every event of every step).
func hear(event: Dictionary) -> void:
	match event["type"]:
		&"shot_fired":
			var id: int = event["shooter_id"]
			_tally(id)["shots"] += 1
			_shot_now[id] = true
		&"quick_melee":
			# A blow with the free hand is something done, not a shot to count.
			_shot_now[event["shooter_id"]] = true
		&"zombie_damaged":
			var id: int = event["player_id"]
			var zone: StringName = event["zone"]
			if id > 0 and zone != RulesAction.ZONE_BLAST:
				var tally := _tally(id)
				tally["pellet_hits"] += 1
				_hit_now[id] = true
				if zone == RulesAction.ZONE_HEAD:
					tally["heads"] += 1
				elif zone == RulesAction.ZONE_WEAK:
					tally["weak"] += 1
		&"zombie_removed":
			if event["cause"] == &"killed":
				_kills_total += 1
				var killer: int = event["killer_id"]
				if killer > 0:
					_tally(killer)["kills"] += 1
		&"player_downed":
			_tally(event["player_id"])["downs"] += 1
			var down_round: int = night.server.rules.round_number
			_round_downs[down_round] = int(_round_downs.get(down_round, 0)) + 1
		&"player_damaged":
			var blow_round: int = night.server.rules.round_number
			var by_type: Dictionary = _round_blows.get(blow_round, {})
			var landed: Array = by_type.get(String(event["zombie_type"]), [0, 0.0])
			landed[0] += 1
			landed[1] += float(event["damage"])
			by_type[String(event["zombie_type"])] = landed
			_round_blows[blow_round] = by_type
		&"player_died":
			_tally(event["player_id"])["deaths"] += 1
		&"player_hurt":
			_tally(event["player_id"])["damage_taken"] += float(event["damage"])
			var hurt_round: int = night.server.rules.round_number
			_round_damage[hurt_round] = (
				float(_round_damage.get(hurt_round, 0.0)) + float(event["damage"])
			)
		&"player_revived":
			var reviver := int(event.get("reviver_id", 0))
			if reviver > 0:
				_tally(reviver)["revived_others"] += 1
		&"purchase_made":
			var item := night.server.rules.tuning.economy.item(event["item_id"])
			var category: String = CATEGORIES.get(item.kind, "other")
			var spent: Dictionary = _tally(event["player_id"])["spent"]
			spent[category] = int(spent.get(category, 0)) + int(event["price"])
		&"purchase_denied":
			_denials += 1
			var key := "%s:%s" % [event["player_id"], event["item_id"]]
			var at := float(night.server.tick_count) / 60.0
			if _last_refusal.has(key) and at - _last_refusal[key] < LOOP_WINDOW - 1.0:
				_loops += 1
			_last_refusal[key] = at
		&"door_opened":
			_doors.append(event["door_id"])
		&"round_started":
			_round_marks[event["round"]] = float(night.server.tick_count) / 60.0
			_round_kit[event["round"]] = _kit()


## An action a bot sent (`SeatedNight.on_action`): the same command as the one before, or not.
func act(action: Dictionary, id: int) -> void:
	if action.get("type") != NightServer.COMMAND:
		return
	var signature := BotTelemetry.signature(action)
	if _signature.get(id, "") == signature:
		_same_for[id] = int(_same_for.get(id, 0)) + 1
	else:
		_same_for[id] = 0
	_signature[id] = signature


## After a tick: the bots' state this tick, read against the server's truth.
func tick() -> void:
	ticks += 1
	for id in _shot_now:
		if _hit_now.has(id):
			_tally(id)["shot_hits"] += 1
	_fired = _shot_now.duplicate()
	_shot_now.clear()
	_hit_now.clear()
	if hold_spot == Vector3.INF and order == BotOrders.HOLD:
		var held: Dictionary = night.frame.get(BotOrders.FRAME_KEY, {})
		var team: Dictionary = held.get("team", {})
		if not team.is_empty():
			hold_spot = team["at"]
	var humans := _humans_up()
	var places: Array[Vector3] = []
	for bot in night.host.bots:
		var id := bot.state.player_id
		if people.has(id):
			continue
		var tally := _tally(id)
		var body := night.server.body_of(id)
		var me: Dictionary = night.frame["players"].get(id, {})
		if body == null or me.is_empty() or me.get("downed", false) or me.get("dead", false):
			tally["down"] += 1
			tally["idle_threat_run"] = 0
			tally["idle_roam_run"] = 0
			tally["far_run"] = 0
			continue
		tally["up"] += 1
		var here := body.global_position
		places.append(here)
		var note: String = bot.intent.note
		var standing := Vector2(body.velocity.x, body.velocity.z).length() < STANDING
		_watch_idle(tally, bot, here, note, standing, me)
		_watch_people(tally, here, note, humans)
		if hold_spot != Vector3.INF and STANCE_NOTES.has(note):
			tally["stance"] += 1
			var off := Vector2(here.x - hold_spot.x, here.z - hold_spot.z)
			tally["stance_held"] += 1 if off.length() <= GATE_HOLD_METRES else 0
	for i in places.size():
		for j in range(i + 1, places.size()):
			_spread_sum += Vector2(places[i].x - places[j].x, places[i].z - places[j].z).length()
			_spread_n += 1


## What the bots carry now: the guns each holds (sorted, joined) and the points of all of them.
func _kit() -> Dictionary:
	var guns: Array[String] = []
	var points := 0
	for bot in night.host.bots:
		var id := bot.state.player_id
		if people.has(id):
			continue
		points += night.server.rules.points_of(id)
		var arms: Dictionary = night.frame.get("players", {}).get(id, {}).get("arms", {})
		var names: Array[String] = []
		for weapon: StringName in arms:
			names.append(String(weapon))
		names.sort()
		guns.append("+".join(names))
	guns.sort()
	return {"guns": guns, "points": points}


func _humans_up() -> Array[Vector3]:
	var found: Array[Vector3] = []
	for id in people:
		var me: Dictionary = night.frame["players"].get(id, {})
		var body := night.server.body_of(id)
		if body != null and not me.is_empty() and not me.get("downed", false):
			found.append(body.global_position)
	return found


## Standing with a zombie in sight (the 5 s gate) and standing with nothing to do (Roam's 8 s).
func _watch_idle(
	tally: Dictionary, bot: BotClient, here: Vector3, note: String, standing: bool, me: Dictionary
) -> void:
	var threat := false
	var nearest: Dictionary = {}
	for contact in bot.perception.beliefs.targets(here):
		var apart := Vector2(contact["position"].x - here.x, contact["position"].z - here.z)
		if apart.length() <= THREAT_METRES:
			threat = true
			nearest = {
				"id": contact["id"], "m": snappedf(apart.length(), 0.1), "mode": contact["mode"]
			}
			break
	# Standing on the same command (no button, no turn of the view past a bucket) is the plan's
	# idle; a
	# trigger or a held use (a revive, a board) is something done even though the command repeats.
	var doing := _fired.has(bot.state.player_id) or bot.intent.use or bot.intent.use_held
	var unchanged := int(_same_for.get(bot.state.player_id, 0)) > 0
	var idle_threat := threat and standing and unchanged and not doing
	# A zombie that is coming (a metre nearer than when the wait began) is a wait for the blow, not
	# a bot that ignores it: the dry bot and the one with a crowbar meet the dead where they stand.
	var gap: float = nearest.get("m", INF)
	if idle_threat and int(tally["idle_threat_run"]) == 0:
		tally["idle_threat_ref"] = gap
	elif idle_threat and gap <= float(tally["idle_threat_ref"]) - APPROACH_METRES:
		idle_threat = false
	tally["idle_threat_run"] = int(tally["idle_threat_run"]) + 1 if idle_threat else 0
	if (
		tally["idle_threat_run"] == int(GATE_IDLE_THREAT * 60.0)
		and tally["idle_samples"].size() < 3
	):
		(
			tally["idle_samples"]
			. append(
				{
					"tick": ticks,
					"note": note,
					"at": [snappedf(here.x, 0.1), snappedf(here.z, 0.1)],
					"target": nearest,
					"weapon": str(me.get("weapon", "")),
					"ammo": me.get("ammo", -1),
					"reserve": me.get("reserve", -1),
					"goal": bot.intent.goal.snappedf(0.1),
					"target_id": bot.intent.target_id,
					"zombie": _zombie_card(bot.intent.target_id),
				}
			)
		)
	tally["idle_threat_longest"] = maxi(tally["idle_threat_longest"], tally["idle_threat_run"])
	var idle_roam := standing and IDLE_NOTES.has(note)
	tally["idle_roam_run"] = int(tally["idle_roam_run"]) + 1 if idle_roam else 0
	if tally["idle_roam_run"] == int(GATE_ROAM_IDLE * 60.0) and tally["roam_samples"].size() < 3:
		(
			tally["roam_samples"]
			. append(
				{
					"tick": ticks,
					"note": note,
					"at": [snappedf(here.x, 0.1), snappedf(here.z, 0.1)],
					"goal": bot.intent.goal.snappedf(0.1),
					"path": str(bot.legs.path.last_status),
					"stuck": bot.legs.stuck.stuck,
					"round": night.server.rules.round_number,
					"phase": night.server.rules.phase,
				}
			)
		)
	tally["idle_roam_longest"] = maxi(tally["idle_roam_longest"], tally["idle_roam_run"])


## The distance to the nearest person on their feet: the 25 m gate (a run of ticks beyond it,
## outside
## an errand) and the share within 12 m (Follow's).
func _watch_people(tally: Dictionary, here: Vector3, note: String, humans: Array[Vector3]) -> void:
	if humans.is_empty():
		tally["far_run"] = 0
		return
	var nearest := INF
	for person in humans:
		nearest = minf(nearest, Vector2(person.x - here.x, person.z - here.z).length())
	tally["near12_of"] += 1
	tally["near12"] += 1 if nearest <= GATE_FOLLOW_METRES else 0
	var errand := false
	for prefix in ERRAND_NOTES:
		errand = errand or note.begins_with(prefix)
	if nearest > GATE_FOLLOW_METRES:
		var far_notes: Dictionary = tally["far_notes"]
		var key := note.get_slice(" ", 0)
		far_notes[key] = int(far_notes.get(key, 0)) + 1
	if nearest > GATE_FAR_METRES and not errand:
		tally["far_run"] += 1
		tally["far_longest"] = maxi(tally["far_longest"], tally["far_run"])
	else:
		tally["far_run"] = 0


## The stuck episodes of a bot that lasted over five seconds, for the report.
func _long_episodes(bot: BotClient) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for episode in bot.legs.episodes:
		if float(episode.get("seconds", 0.0)) > 5.0:
			(
				found
				. append(
					{
						"position": str(episode.get("position", "")),
						"goal": str(episode.get("goal", "")),
						"note": str(episode.get("note", "")),
						"seconds": snappedf(float(episode.get("seconds", 0.0)), 0.1),
						"depth": int(episode.get("depth", 0)),
						"at": episode.get("at", 0.0),
					}
				)
			)
	return found


## How the night stands: the dead left by type, and what each bot holds. Read when it is lost.
func _end_state() -> Dictionary:
	var left: Dictionary = {}
	var cards: Array[Dictionary] = []
	for zombie: ZombieBody in night.server.sim.zombies.values():
		if zombie.mode != ZombieBody.Mode.DYING:
			var key := String(zombie.profile.type)
			left[key] = int(left.get(key, 0)) + 1
			if cards.size() < 6:
				cards.append(_zombie_card(zombie.id))
	var bots: Array[Dictionary] = []
	for bot in night.host.bots:
		if people.has(bot.state.player_id):
			continue
		var me: Dictionary = night.frame["players"].get(bot.state.player_id, {})
		(
			bots
			. append(
				{
					"seat": bot.state.player_id,
					"downed": me.get("downed", false),
					"dead": me.get("dead", false),
					"weapon": str(me.get("weapon", "")),
					"arms": me.get("arms", {}).duplicate(),
					"points": night.server.rules.points_of(bot.state.player_id),
				}
			)
		)
	return {"left": left, "cards": cards, "bots": bots}


## What the server holds of a zombie: where it is and what it is doing (the soak's word on a bot
## that stood by one).
func _zombie_card(zombie_id: int) -> Dictionary:
	var zombie: ZombieBody = night.server.sim.zombies.get(zombie_id)
	if zombie == null:
		return {}
	return {
		"at":
		[
			snappedf(zombie.position.x, 0.1),
			snappedf(zombie.position.y, 0.1),
			snappedf(zombie.position.z, 0.1)
		],
		"mode": zombie.mode,
		"gate": String(zombie.gate_id),
		"tearing": zombie.tearing,
		"type": String(zombie.profile.type),
	}


## Plain data for the night so far: one object for the run and one for each bot.
func report() -> Dictionary:
	var bots: Array[Dictionary] = []
	var rules := night.server.rules
	for bot in night.host.bots:
		var id := bot.state.player_id
		if people.has(id):
			continue
		var tally := _tally(id)
		var gauges := bot.telemetry.gauges
		var walking := float(gauges.get(&"walking_seconds", 0.0))
		var stuck := float(gauges.get(&"stuck_seconds", 0.0))
		var player: PlayerState = rules.players.get(id)
		(
			bots
			. append(
				{
					"seat": id,
					"profile": bot.profile.title,
					"up_seconds": snappedf(float(tally["up"]) / 60.0, 0.1),
					"down_seconds": snappedf(float(tally["down"]) / 60.0, 0.1),
					"walking_seconds": snappedf(walking, 0.1),
					"stuck_seconds": snappedf(stuck, 0.1),
					"stuck_share": snappedf(stuck / maxf(walking, 1.0), 0.0001),
					"longest_stuck": snappedf(float(gauges.get(&"longest_stuck", 0.0)), 0.1),
					"bot_stuck_reports": bot.telemetry.counters.get(&"bot_stuck", 0),
					"brain_disabled": bot.telemetry.has_event(BotClient.BRAIN_DISABLED),
					"idle_threat_longest":
					snappedf(float(tally["idle_threat_longest"]) / 60.0, 0.1),
					"idle_samples": tally["idle_samples"],
					"roam_samples": tally["roam_samples"],
					"stuck_episodes": _long_episodes(bot),
					"idle_roam_longest": snappedf(float(tally["idle_roam_longest"]) / 60.0, 0.1),
					"far_longest": snappedf(float(tally["far_longest"]) / 60.0, 0.1),
					"far_notes": tally["far_notes"],
					"near12_share":
					snappedf(float(tally["near12"]) / maxf(float(tally["near12_of"]), 1.0), 0.0001),
					"stance_share":
					snappedf(
						float(tally["stance_held"]) / maxf(float(tally["stance"]), 1.0), 0.0001
					),
					"stance_seconds": snappedf(float(tally["stance"]) / 60.0, 0.1),
					"shots": tally["shots"],
					"shot_hits": tally["shot_hits"],
					"pellet_hits": tally["pellet_hits"],
					"heads": tally["heads"],
					"weak_hits": tally["weak"],
					"kills": tally["kills"],
					"downs": tally["downs"],
					"deaths": tally["deaths"],
					"damage_taken": snappedf(tally["damage_taken"], 0.1),
					"revive_attempts": int(bot.telemetry.counters.get(&"revive_attempts", 0)),
					"revive_successes": int(bot.telemetry.counters.get(&"revive_successes", 0)),
					"revived_others": tally["revived_others"],
					"buys": int(bot.telemetry.counters.get(&"buys", 0)),
					"rejected_buys": int(bot.telemetry.counters.get(&"rejected_buys", 0)),
					"spent": tally["spent"],
					"points_earned": player.points_earned if player != null else 0,
					"points_spent": player.points_spent if player != null else 0,
					"think_us_p50": bot.telemetry.think_us(0.5),
					"think_us_p99": bot.telemetry.think_us(0.99),
					"path_queries": int(gauges.get(&"path_queries", 0.0)),
				}
			)
		)
	return {
		"round": rules.round_number,
		"over": rules.phase == GameRules.Phase.OVER,
		"game_seconds": snappedf(float(ticks) / 60.0, 0.1),
		"kills_total": _kills_total,
		"doors": _doors.size(),
		"denials": _denials,
		"denial_loops": _loops,
		"spread": snappedf(_spread_sum / maxf(float(_spread_n), 1.0), 0.1),
		"round_marks": _round_marks,
		"round_damage": _round_damage,
		"round_downs": _round_downs,
		"round_blows": _round_blows,
		"round_kit": _round_kit,
		"end": _end_state(),
		"bots": bots,
	}


## The gates a night's report breaks, in words (empty: it held them). `people` is whether a person
## stand-in played. The Follow gates apply under that order only, the Hold gate under Hold.
static func verdict(
	night_report: Dictionary, order_id: StringName, with_person: bool
) -> Array[String]:
	var broken: Array[String] = []
	if int(night_report.get("errors", 0)) > 0:
		broken.append("engine errors: %d" % int(night_report["errors"]))
	if night_report.get("reason", "") == "stalled_round":
		broken.append("a round that would not end (round %d)" % int(night_report["round"]))
	if int(night_report.get("denial_loops", 0)) > 0:
		broken.append("rejected-buy loops: %d" % int(night_report["denial_loops"]))
	for bot: Dictionary in night_report.get("bots", []):
		var label := "seat %d (%s)" % [bot["seat"], bot["profile"]]
		if float(bot["longest_stuck"]) > GATE_STUCK_EPISODE:
			broken.append("%s stuck for %.1f s at once" % [label, bot["longest_stuck"]])
		if float(bot["idle_threat_longest"]) > GATE_IDLE_THREAT:
			broken.append(
				"%s idle %.1f s with a zombie in view" % [label, bot["idle_threat_longest"]]
			)
		if bool(bot["brain_disabled"]):
			broken.append("%s lost its brain" % label)
		if order_id == BotOrders.ROAM and float(bot["idle_roam_longest"]) > GATE_ROAM_IDLE:
			broken.append("%s idle %.1f s under Roam" % [label, bot["idle_roam_longest"]])
		if with_person and order_id == BotOrders.FOLLOW:
			if float(bot["far_longest"]) > GATE_FAR_SECONDS:
				broken.append("%s %.1f s beyond 25 m of the person" % [label, bot["far_longest"]])
		if (
			order_id == BotOrders.HOLD
			and float(bot["stance_seconds"]) >= 30.0
			and float(bot["stance_share"]) < GATE_HOLD_SHARE
		):
			broken.append(
				"%s held the spot %.0f%% of the time" % [label, 100.0 * bot["stance_share"]]
			)
	return broken

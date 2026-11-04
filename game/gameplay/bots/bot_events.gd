class_name BotEvents
extends RefCounted
## What a bot may hear of the night: an allow-list of the events a person's feed and HUD already
## show. Anything not listed is dropped before the bot's `ClientState` sees it, so a new event
## that carries server-side detail is private to the bot until someone adds it here.
## (`docs/research/bots.md#perception-what-a-bot-is-allowed-to-know`.)

## Heard by every bot: the night as the screen shows it.
const PUBLIC: Array[StringName] = [
	&"frame",
	&"phase_changed",
	&"break_started",
	&"special_round_announced",
	&"special_round_cleared",
	&"round_started",
	&"round_ended",
	&"game_over",
	&"door_opened",
	&"board_torn",
	&"board_repaired",
	&"circuit_changed",
	&"fuel_changed",
	&"fuel_low",
	&"fuel_empty",
	&"fuel_restored",
	&"player_added",
	&"player_removed",
	&"player_downed",
	&"player_revived",
	&"revive_started",
	&"revive_stopped",
	&"ping_placed",
	&"ping_cleared",
	&"zombie_removed",
	&"grenade_thrown",
	&"grenade_bounced",
	&"grenade_exploded",
]
## Heard only when they are about the bot itself (a purchase, its own gun, the blow it took).
const OWN: Array[StringName] = [
	&"points_changed",
	&"purchase_made",
	&"purchase_denied",
	&"drink_started",
	&"drink_finished",
	&"drink_spilled",
	&"player_hurt",
	&"player_healed",
	&"shot_fired",
	&"fire_rejected",
	&"reload_started",
	&"reload_round",
	&"reload_interrupted",
	&"reload_finished",
	&"reload_rejected",
	&"weapon_equipped",
	&"ammo_added",
	&"weapon_upgraded",
	&"grenade_count_changed",
	&"lure_started",
]
## Event types that start with these are public too (the prize crane's whole play).
const PUBLIC_PREFIXES: Array[String] = ["crane_"]
## The fields that name whose event it is, in the order they are looked for.
const OWNER_FIELDS: Array[StringName] = [&"player_id", &"shooter_id", &"thrower_id"]


## The events of `events` the bot `player_id` may hear, in order.
static func filter(events: Array, player_id: int) -> Array[Dictionary]:
	var heard: Array[Dictionary] = []
	for event: Dictionary in events:
		if allows(event, player_id):
			heard.append(event)
	return heard


static func allows(event: Dictionary, player_id: int) -> bool:
	var type: StringName = event.get("type", &"")
	if PUBLIC.has(type):
		return true
	for prefix in PUBLIC_PREFIXES:
		if String(type).begins_with(prefix):
			return true
	return OWN.has(type) and owner_of(event) == player_id


## Whose event it is: the player it is about, or -1 when it names none.
static func owner_of(event: Dictionary) -> int:
	for field in OWNER_FIELDS:
		if event.has(field):
			return int(event[field])
	return -1

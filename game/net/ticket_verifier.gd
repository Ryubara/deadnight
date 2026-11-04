class_name TicketVerifier
extends RefCounted
## Checks the ticket the platform backend gives a player for a night (`spikes/backend/src/
## tokens.ts`, docs/research/platform-backend.md, "The game-server ticket"): an HS256 token whose
## payload says which player (`sub`, `name`), which night (`matchId`) and which game server
## (`serverId`) it is for, and, when the host chose them, the rules of the night (`settings`, the
## game's `MatchSettings` as `to_dict` writes it).
##
## A ticket is good once: the `jti` of every one admitted is remembered until it would have expired
## anyway. Time is the caller's (`now`, seconds since 1970), so a test moves it by hand.

## `{"alg":"HS256","typ":"JWT"}` as the backend writes it, base64url.
const HEADER := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
## Why a ticket was refused, as text a log or a test can match.
const BAD := "bad ticket"
const WRONG_SERVER := "ticket is for another server"
const USED := "ticket already used"
const BAD_SETTINGS := "ticket carries rules this server does not take"
## Followed by the keys: the host chose a setting this build of the game server has not heard of.
const UNKNOWN_SETTING := "ticket carries a setting this server does not know"
## What the ticket's `icon` claim starts with: `level_07`, the file name of the ladder's icon.
const ICON_PREFIX := "level_"

var _secret: PackedByteArray
var _server_id: String
## jti -> exp, for the tickets already used.
var _used: Dictionary[String, int] = {}


func _init(secret: String, server_id: String) -> void:
	_secret = secret.to_utf8_buffer()
	_server_id = server_id


## `{"ok": true, "user": sub, "name", "match": matchId, "settings", "level", "icon"}` for a ticket
## this server may admit (and spends it), or `{"ok": false, "reason"}`. `settings` is the
## `MatchSettings` the host chose, or null when the ticket has none (the usual rules). Rules this
## server cannot take (a value out of its bounds: the backend and the game disagree) refuse the
## ticket, loudly, instead of starting a night with other rules than the host asked for.
func admit(ticket: String, now: int) -> Dictionary:
	var claims := claims_of(ticket, now)
	if claims.is_empty():
		return {"ok": false, "reason": BAD}
	if claims.get("serverId", "") != _server_id:
		return {"ok": false, "reason": WRONG_SERVER}
	var jti: Variant = claims.get("jti")
	if (
		typeof(jti) != TYPE_STRING
		or (jti as String).is_empty()
		or typeof(claims.get("matchId")) != TYPE_STRING
	):
		return {"ok": false, "reason": BAD}
	var settings: MatchSettings = null
	if claims.has("settings"):
		var why := _settings_problem(claims["settings"])
		if why != "":
			return {"ok": false, "reason": why}
		settings = MatchSettings.from_json(claims["settings"])
	for known: String in _used.keys():
		if _used[known] <= now:
			_used.erase(known)
	if _used.has(jti):
		return {"ok": false, "reason": USED}
	_used[jti] = int(claims["exp"])
	var shown := level_claims(claims)
	return {
		"ok": true,
		"user": claims["sub"],
		"name": str(claims.get("name", "")),
		"match": claims["matchId"],
		"settings": settings,
		"level": shown["level"],
		"icon": shown["icon"],
	}


## The level and icon a ticket's claims give the seat, both whole numbers from 1 to the top level,
## or both 0 when the ticket has none (a ticket from before the backend kept profiles, a claim out
## of range): the seat then shows no level. The backend signs them from the account's stored
## profile; the client's own word never reaches here. The icon is the claim `level_NN` (the file of
## the ladder's icon, `LevelIcons`) read as the number NN, and follows the level when it is missing
## or wrong.
static func level_claims(claims: Dictionary) -> Dictionary:
	var held: Variant = claims.get("level")
	if typeof(held) != TYPE_FLOAT and typeof(held) != TYPE_INT:
		return {"level": 0, "icon": 0}
	var level := int(held)
	if float(held) != float(level) or level < 1 or level > LevelCurve.MAX_LEVEL:
		return {"level": 0, "icon": 0}
	var icon := level
	var named := str(claims.get("icon", ""))
	if named.begins_with(ICON_PREFIX) and named.substr(ICON_PREFIX.length()).is_valid_int():
		var number := named.substr(ICON_PREFIX.length()).to_int()
		if number >= 1 and number <= LevelCurve.MAX_LEVEL:
			icon = number
	return {"level": level, "icon": icon}


## Why the `settings` claim of a ticket is refused ("" when the game takes it). A key this build
## does not know is a setting the host chose that the night would not have: refused by name, never
## started without it (Deadnight #944).
func _settings_problem(held: Variant) -> String:
	if typeof(held) == TYPE_DICTIONARY:
		var unknown := MatchSettings.unknown_keys(held)
		if not unknown.is_empty():
			return "%s: %s" % [UNKNOWN_SETTING, ", ".join(unknown)]
	return "" if MatchSettings.from_json(held) != null else BAD_SETTINGS


## The payload of a correctly signed, unexpired ticket, or `{}`: the header is the one the backend
## writes, the signature matches (compared in constant time), `kind` is "ticket", `exp` and `iat`
## are numbers and `exp` is in the future.
func claims_of(ticket: String, now: int) -> Dictionary:
	var parts := ticket.split(".")
	if parts.size() != 3 or parts[0] != HEADER or not _signed(parts):
		return {}
	var parsed: Variant = JSON.parse_string(_decode(parts[1]).get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var claims: Dictionary = parsed
	var sound: bool = (
		claims.get("kind") == "ticket"
		and typeof(claims.get("sub")) == TYPE_STRING
		and typeof(claims.get("iat")) == TYPE_FLOAT
		and typeof(claims.get("exp")) == TYPE_FLOAT
	)
	return claims if sound and int(claims["exp"]) > now else {}


## Whether the signature (the third part) is the HMAC of the first two, compared in constant time.
func _signed(parts: PackedStringArray) -> bool:
	var crypto := Crypto.new()
	var expected := crypto.hmac_digest(
		HashingContext.HASH_SHA256, _secret, (parts[0] + "." + parts[1]).to_utf8_buffer()
	)
	var given := _decode(parts[2])
	return given.size() == expected.size() and crypto.constant_time_compare(given, expected)


## Base64url without padding to bytes (empty when it is not base64).
static func _decode(text: String) -> PackedByteArray:
	var standard := text.replace("-", "+").replace("_", "/")
	while standard.length() % 4 != 0:
		standard += "="
	return Marshalls.base64_to_raw(standard)

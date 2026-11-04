class_name TicketVerifier
extends RefCounted
## Checks the ticket the platform backend gives a player for a night (`spikes/backend/src/
## tokens.ts`, docs/research/platform-backend.md, "The game-server ticket"): an HS256 token whose
## payload says which player (`sub`, `name`), which night (`matchId`) and which game server
## (`serverId`) it is for, and, when the host chose them, the rules of the night (`settings`, the
## game's `MatchSettings` as `to_dict` writes it).
##
## The ticket also says the level of the lobby's host (`hostLevel`, signed by the backend from the
## host's account): the host's level decides which maps the night may be on, so a map the host's
## level does not open falls back to the default (`MatchSettings.fit_host`), whoever holds the
## ticket and whatever a client sent.
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
## `host_level` of a ticket that does not say (a backend from before levels, or an account with no
## progress): level 1, so a ticket that holds no claim never opens a map that needs a level.
const NO_LEVEL := 1
## Followed by the keys: the host chose a setting this build of the game server has not heard of.
const UNKNOWN_SETTING := "ticket carries a setting this server does not know"

var _secret: PackedByteArray
var _server_id: String
## jti -> exp, for the tickets already used.
var _used: Dictionary[String, int] = {}


func _init(secret: String, server_id: String) -> void:
	_secret = secret.to_utf8_buffer()
	_server_id = server_id


## `{"ok": true, "user", "name", "match", "settings", "host_level", "map_refused"}` for a ticket
## this server may admit (and spends it), or `{"ok": false, "reason"}`. `settings` is the
## `MatchSettings` the host chose, or null when the ticket has none (the usual rules). Rules this
## server cannot take (a value out of its bounds: the backend and the game disagree) refuse the
## ticket, loudly, instead of starting a night with other rules than the host asked for.
## `host_level` is the claim (`NO_LEVEL`, level 1, when absent); `map_refused` names the map the
## host asked for and the level did not open ("" when the map stands), which the server logs.
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
	var host_level := _host_level(claims.get("hostLevel"))
	var settings: MatchSettings = null
	var map_refused := ""
	if claims.has("settings"):
		var why := _settings_problem(claims["settings"])
		if why != "":
			return {"ok": false, "reason": why}
		settings = MatchSettings.from_json(claims["settings"])
		if not MapRegistry.is_open(settings.map, host_level):
			map_refused = settings.map
			settings = settings.fit_host(host_level)
	for known: String in _used.keys():
		if _used[known] <= now:
			_used.erase(known)
	if _used.has(jti):
		return {"ok": false, "reason": USED}
	_used[jti] = int(claims["exp"])
	return {
		"ok": true,
		"user": claims["sub"],
		"name": str(claims.get("name", "")),
		"match": claims["matchId"],
		"settings": settings,
		"host_level": host_level,
		"map_refused": map_refused,
	}


## The level a ticket's `hostLevel` claim holds: `NO_LEVEL` (level 1) when there is no claim; a
## whole number from 1 up is that level (beyond the ladder, the top one); anything else that is
## claimed is level 1 too, so a missing or damaged claim never opens a map.
static func _host_level(claim: Variant) -> int:
	if claim == null:
		return NO_LEVEL
	if typeof(claim) not in [TYPE_INT, TYPE_FLOAT]:
		return 1
	var number := float(claim)
	if not is_finite(number) or number < 1.0 or not is_equal_approx(number, roundf(number)):
		return 1
	return mini(int(number), LevelCurve.MAX_LEVEL)


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

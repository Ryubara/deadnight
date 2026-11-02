class_name TicketVerifier
extends RefCounted
## Checks the ticket the platform backend gives a player for a night (`spikes/backend/src/
## tokens.ts`, docs/research/platform-backend.md, "The game-server ticket"): an HS256 token whose
## payload says which player (`sub`, `name`), which night (`matchId`) and which game server
## (`serverId`) it is for.
##
## A ticket is good once: the `jti` of every one admitted is remembered until it would have expired
## anyway. Time is the caller's (`now`, seconds since 1970), so a test moves it by hand.

## `{"alg":"HS256","typ":"JWT"}` as the backend writes it, base64url.
const HEADER := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
## Why a ticket was refused, as text a log or a test can match.
const BAD := "bad ticket"
const WRONG_SERVER := "ticket is for another server"
const USED := "ticket already used"

var _secret: PackedByteArray
var _server_id: String
## jti -> exp, for the tickets already used.
var _used: Dictionary[String, int] = {}


func _init(secret: String, server_id: String) -> void:
	_secret = secret.to_utf8_buffer()
	_server_id = server_id


## `{"ok": true, "user": sub, "name", "match": matchId}` for a ticket this server may admit (and
## spends it), or `{"ok": false, "reason"}`.
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
	}


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
	var sound := (
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

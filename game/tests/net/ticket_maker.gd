class_name TicketMaker
extends RefCounted
## Signs tickets the way the backend does (`spikes/backend/src/tokens.ts`), for tests of a game
## server that checks them: HS256, `kind` "ticket", a `jti` that is new each time.

static var _count := 0


## A ticket for `user` in `match_id` on `server_id`, good for `seconds` from now; `settings` (a
## `MatchSettings.to_dict`) are the rules the host chose, none when empty; `host_level` is the
## lobby host's level the backend signs in (none when null, a backend from before levels); `extra`
## are more claims (`level`, `icon`, `xp` as the backend signs them from the account's profile).
static func make(
	secret: String,
	server_id: String,
	match_id: String,
	user: String,
	user_name: String = "Tester",
	seconds: int = 60,
	settings: Dictionary = {},
	host_level: Variant = null,
	extra: Dictionary = {}
) -> String:
	_count += 1
	var now := int(Time.get_unix_time_from_system())
	var claims := {
		"sub": user,
		"kind": "ticket",
		"iat": now,
		"exp": now + seconds,
		"matchId": match_id,
		"name": user_name,
		"serverId": server_id,
		"jti": "t%d-%d" % [_count, randi()],
	}
	if not settings.is_empty():
		claims["settings"] = settings
	if host_level != null:
		claims["hostLevel"] = host_level
	claims.merge(extra, true)
	var head := TicketVerifier.HEADER
	var body := _encode(JSON.stringify(claims).to_utf8_buffer())
	var signature := Crypto.new().hmac_digest(
		HashingContext.HASH_SHA256, secret.to_utf8_buffer(), (head + "." + body).to_utf8_buffer()
	)
	return "%s.%s.%s" % [head, body, _encode(signature)]


static func _encode(bytes: PackedByteArray) -> String:
	return (
		Marshalls
		. raw_to_base64(bytes)
		. replace("+", "-")
		. replace("/", "_")
		. trim_suffix("=")
		. trim_suffix("=")
	)

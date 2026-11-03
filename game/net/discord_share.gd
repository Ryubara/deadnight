class_name DiscordShare
extends RefCounted
## What Discord answered to "Share in Discord" (Deadnight #627), in words.
##
## The bridge (`deploy/web/discord-share.js`) sends the Embedded App SDK's `shareLink` and keeps the
## real answer: `shareJson()` is one line of JSON with a `verdict`:
## - `asking`: sent a moment ago, Discord has not refused it;
## - `open`: no answer after a second and no refusal: a window may be up (Discord answers when the
##   window is closed, so a command still pending is the only sign of an open one);
## - `shared`: the window answered success;
## - `closed`: the window answered success=false after a while: it was open and was closed;
## - `refused`: an error, or success=false at once: Discord opened nothing;
## - `unreadable`: the SDK could not read the client's answer.
## `auth` is how the Activity's `authenticate` went (`none`, `pending`, `ok`, `unread`, `failed`):
## Discord refuses a command with error 4006 until that is done (the cause of #627).
## The hint to pick who to send it to is shown for `open` only. `says` is the sentence for the
## player; `line` is the probe line with Discord's own numbers and error, so a report shows it.

const HINT := "Pick who to send it to in Discord's window."
const READ_JS := """(function () {
  var d = window.deadnightDiscord;
  return d && d.shareJson ? d.shareJson() : '';
})()"""

## For a test: called with the JS to run on the page instead of `JavaScriptBridge.eval`.
static var eval_js := Callable()


## Asks the page to open Discord's share window. Returns false off the web.
static func ask(message: String, code: String) -> bool:
	if not _can_eval():
		return false
	_eval("window.deadnightDiscord.share(%s, %s)" % [JSON.stringify(message), JSON.stringify(code)])
	return true


## The bridge's state (empty off the web, or before anything was asked).
static func read() -> Dictionary:
	if not _can_eval():
		return {}
	var parsed: Variant = JSON.parse_string(str(_eval(READ_JS)))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func settled(state: Dictionary) -> bool:
	var verdict := str(state.get("verdict", "idle"))
	if verdict in ["idle", "asking", "open"]:
		return verdict == "idle"
	return str(state.get("invite", "")) != "asking"


## The sentence the lobby shows under the Share button.
static func says(state: Dictionary, code: String) -> String:
	var invite := str(state.get("invite", ""))
	match str(state.get("verdict", "idle")):
		"asking":
			return "Asking Discord..."
		"open":
			return HINT
		"shared":
			if state.get("didSendMessage", false):
				return "Sent through Discord."
			return "Discord copied the link. Paste it to your friends."
		"closed":
			return (
				"Discord's window was closed without sending. Press Share in Discord to try again,"
				+ " or Copy the code."
			)
		"unreadable":
			return (
				"Discord's window may have opened, but its answer could not be read. If nothing"
				+ " opened, press Copy the code and send it yourself."
			)
		"refused":
			var out := "Discord did not open its share window. Press Copy the code and send it yourself."
			if _not_signed_in(state):
				out = (
					"Discord did not open its share window: this Activity is not signed in with"
					+ " Discord yet. Press Copy the code and send it yourself."
				)
			if invite == "opened":
				out = (
					"Discord did not open its share window, but its invite window opened: invite"
					+ " your friends there, then send them the code %s (Copy the code)." % code
				)
			return out
	return ""


## Discord refused with 4006 ("Not authenticated or invalid scope") and the sign-in with Discord had
## not completed (a guest, or `authenticate` failed): the refusal is the missing sign-in.
static func _not_signed_in(state: Dictionary) -> bool:
	return (
		str(state.get("code", "")) == "4006" and str(state.get("auth", "ok")) in ["none", "failed"]
	)


## The probe line: what Discord answered, as it answered it.
static func line(state: Dictionary) -> String:
	var verdict := str(state.get("verdict", "idle"))
	if verdict == "idle":
		return ""
	var parts: Array[String] = ["share: %s after %d ms" % [verdict, int(state.get("ms", 0))]]
	if state.get("success") != null:
		parts.append(
			(
				"answer success=%s copied=%s sent=%s"
				% [state.get("success"), state.get("didCopyLink"), state.get("didSendMessage")]
			)
		)
	if str(state.get("kind", "")) != "":
		var code := str(state.get("code", ""))
		parts.append(
			(
				"error %s%s: %s"
				% [state.get("kind"), (" " + code) if code != "" else "", state.get("detail", "")]
			)
		)
	elif str(state.get("detail", "")) != "":
		parts.append(str(state.get("detail")))
	if str(state.get("raw", "")) != "":
		parts.append("Discord's frame: %s" % state.get("raw"))
	if str(state.get("auth", "")) != "":
		var auth_why := str(state.get("authDetail", ""))
		parts.append(
			"sign-in: %s%s" % [state.get("auth"), (" (" + auth_why + ")") if auth_why != "" else ""]
		)
	var invite := str(state.get("invite", ""))
	if invite != "":
		var why := str(state.get("inviteDetail", ""))
		parts.append("invite window: %s%s" % [invite, (" (" + why + ")") if why != "" else ""])
	return "; ".join(parts)


static func _can_eval() -> bool:
	return eval_js.is_valid() or OS.has_feature("web")


static func _eval(js: String) -> Variant:
	return eval_js.call(js) if eval_js.is_valid() else JavaScriptBridge.eval(js)

class_name GamepadProbe
extends RefCounted
## Whether the page may read a gamepad. A Discord Activity is an iframe, and the browser lets an
## iframe read gamepads only when the page around it allows the `gamepad` feature (an `allow`
## attribute that Discord writes, not us). When it does not, `navigator.getGamepads()` throws and
## Godot's web runtime swallows the error: no pad is ever seen, and nothing says why. The head
## include of the export defines `window.deadnightGamepad()`, a JSON line of what the page sees
## (`iframe`, `focus`: whether the page has the keyboard focus, `policy`: the feature policy's
## answer or null, `pads`: the pads listed, `error`: the exception's name); this reads it and
## says it in words.

## What a player reads when Discord keeps the page from the controller.
const BLOCKED := (
	"Controller: Discord does not let this window read a gamepad."
	+ " Use the keyboard and mouse, or play in a browser tab."
)
const READY := "Controller: connected."
const WAITING := "Controller: allowed. Press a button on it to wake it."
const UNFOCUSED := "Controller: allowed. Click in the game first, then press a button on it."
## The window was clicked and still does not hold the focus: Discord keeps it, and a browser lists
## no pad to a window without it.
const NO_FOCUS := (
	"Controller: allowed, but Discord keeps the keyboard focus away from the game even after a"
	+ " click, so no controller is listed. Play in a browser tab, or send this line to the makers."
)
## The short line shown on every screen while a frame has no focus (`hint`).
const HINT := "Click the game once to use a controller"
const UNKNOWN := ""


## The page's own report as a dictionary (empty off the web or when the page has no probe).
static func read() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var raw: Variant = JavaScriptBridge.eval(
		"window.deadnightGamepad ? window.deadnightGamepad() : ''"
	)
	var parsed: Variant = JSON.parse_string(str(raw))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## The sentence for a report: blocked, connected, or allowed and waiting for a button press (a page
## that does not have the focus is told to click first, or, once it was clicked, that Discord holds
## the focus; a browser lists no pad to a window without it); empty when there is no report.
static func note(report: Dictionary) -> String:
	if report.is_empty():
		return UNKNOWN
	if report.has("error") or report.get("policy") == false:
		return BLOCKED
	if int(report.get("pads", 0)) > 0:
		return READY
	if report.get("focus") == false:
		return NO_FOCUS if int(report.get("clicks", 0)) > 0 else UNFOCUSED
	return WAITING


## The short hint for every screen: a game inside a frame (a Discord Activity) that does not hold
## the focus gets no controller from the browser until it is clicked once (the maintainer's pad
## worked after one click, #479). Empty in a tab, on the desktop, and once the frame has the focus.
static func hint(report: Dictionary) -> String:
	if report.get("iframe") == true and report.get("focus") == false:
		return HINT
	return ""


## What the page saw, as one short line for whoever reads the screen: whether the window has the
## focus, how many clicks reached it, how often it gained and lost the focus, how many controller
## events came, whether it is shown. Empty when there is no report.
static func detail(report: Dictionary) -> String:
	if report.is_empty():
		return ""
	var focus := "?" if report.get("focus") == null else ("yes" if report["focus"] else "no")
	return (
		"focus %s, clicks %d, focus changes %d/%d, controller events %d, %s"
		% [
			focus,
			int(report.get("clicks", 0)),
			int(report.get("focus_events", 0)),
			int(report.get("blur_events", 0)),
			int(report.get("pad_events", 0)),
			str(report.get("visible", "?")),
		]
	)

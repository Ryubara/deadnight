class_name ChallengeHudLink
extends RefCounted
## Joins a night's challenges to its HUD: each advance the session counts goes to the HUD as a
## `challenge_advanced` event (the HUD reads events and nothing else), the card's sound cue plays,
## and the player's setting decides which prompts show. The night holds it for as long as it plays.

var _hud: Hud
var _settings: SettingsService


## `settings` is the player's (the `Settings` autoload); a test passes its own.
func _init(session: ChallengeSession, hud: Hud, settings: SettingsService = null) -> void:
	_hud = hud
	_settings = settings if settings != null else Settings
	session.advanced.connect(_on_advanced)
	hud.challenge.cue.connect(_on_cue)
	_apply_setting()
	_settings.changed.connect(_on_setting)


func _on_advanced(advance: Dictionary) -> void:
	if advance.get("completed", false):
		# The lane or the prompt shows it now: the menu must not show it again (`ProgressSeen`).
		ProgressSeen.note_challenge(
			int(advance.get("family", 0)), StringName(advance.get("id", &""))
		)
	var event := advance.duplicate()
	event["type"] = HudChallenge.EVENT
	_hud.state.apply_event(event)


func _on_cue(finished: bool) -> void:
	Audio.play(&"challenge_done" if finished else &"challenge_tick")


func _on_setting(key: StringName, _value: Variant) -> void:
	if key == SettingsService.CHALLENGE_PROMPTS:
		_apply_setting()


func _apply_setting() -> void:
	_hud.challenge.mode = (
		int(_settings.get_value(SettingsService.CHALLENGE_PROMPTS)) as HudChallenge.Mode
	)

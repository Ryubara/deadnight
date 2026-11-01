class_name LookStore
extends RefCounted
## Saves and loads the player's own look through the settings service (`user://settings.cfg`
## today; the platform profile later, behind these same two calls).


## The saved look, or the first preset when nothing is saved (a text that cannot be read gives the
## first option of every slot). Options this player has not unlocked are put back, so a
## hand-edited file cannot wear a locked item.
static func load_look(unlocks: LookUnlocks = null) -> CharacterLook:
	var text: String = Settings.get_value(SettingsService.CHARACTER_LOOK)
	var look := CharacterLook.from_json(text) if text != "" else CharacterLook.default_look()
	return look.without_locked(unlocks if unlocks != null else LookUnlocks.new())


static func save_look(look: CharacterLook) -> void:
	Settings.set_value(SettingsService.CHARACTER_LOOK, look.to_json())
	Settings.save()

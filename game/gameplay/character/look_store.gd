class_name LookStore
extends RefCounted
## Saves and loads the player's own look through the settings service (`user://settings.cfg`
## today; the platform profile later, behind these same two calls).


## The saved look, or the first preset when nothing is saved (a text that cannot be read gives the
## first option of every slot). Options this player has not unlocked (the account's level, from the
## profile file, unless `unlocks` is given) are put back, so a hand-edited file or a look saved at
## a higher level cannot wear a locked item.
static func load_look(unlocks: LookUnlocks = null) -> CharacterLook:
	var text: String = Settings.get_value(SettingsService.CHARACTER_LOOK)
	var look := CharacterLook.from_json(text) if text != "" else CharacterLook.default_look()
	return look.without_locked(unlocks if unlocks != null else LookUnlocks.saved())


## Writes the look to the file now.
static func save_look(look: CharacterLook) -> void:
	set_look(look)
	Settings.save()


## Makes `look` the saved one in memory and leaves the file write to the caller, so a screen that
## holds several choices can write them all once (`LoadoutPanel.commit`).
static func set_look(look: CharacterLook) -> void:
	Settings.set_value(SettingsService.CHARACTER_LOOK, look.to_json())

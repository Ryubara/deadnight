class_name MenuContext
extends RefCounted
## What the menu's panels share: the account facts they show, the challenge board they read, the
## stage they turn, and the one signal they use to ask the main menu to go somewhere. A panel
## never pushes a screen itself; the main menu decides what each action opens.

## A panel asks for a route or an effect: `solo`, `together`, `browser`, `settings`,
## `credits` or `quit`.
signal action(id: StringName)
## Emitted just before `action`: the panel on show writes what it holds before the route leaves.
signal leaving

## The player's name (or anything else the plate shows) changed: the plate shows it again.
signal profile_changed

var profile := MenuProfile.new()
## A `ChallengeBoard` (or anything with the same reads: `dailies()`, `orders()`, `milestones()`,
## `refresh_text()`, `swap_order(slot)`, `refresh()` and the `changed` signal).
var board: Object
var stage: MenuStageView
## The window is a phone's: panels are narrower and show less.
var compact := false


func request(id: StringName) -> void:
	leaving.emit()
	action.emit(id)

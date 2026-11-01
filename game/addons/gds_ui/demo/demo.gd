extends Control
## The interactive demo: the menu in the router. Use the mouse, the keyboard or a gamepad.

const MENU := "res://addons/gds_ui/demo/demo_menu.tscn"


func _ready() -> void:
	await get_tree().process_frame
	UIRouter.reset(MENU, UITransition.Kind.FADE)

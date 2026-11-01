extends Control
## The game's root: starts the UI on the main menu. The film overlay lives beside it on a layer
## above the router, so grain and vignette cover every screen and every transition.

const MENU := "res://ui/screens/main_menu.tscn"


func _ready() -> void:
	add_child(WebProbe.new())
	await get_tree().process_frame
	UIRouter.reset(MENU, UITransition.Kind.FADE)

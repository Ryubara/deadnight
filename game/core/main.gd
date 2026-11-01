extends Control
## The game's root: starts the UI on the main menu. The film overlay lives beside it on a layer
## above the router, so grain and vignette cover every screen and every transition.

const MENU := "res://ui/screens/main_menu.tscn"


func _ready() -> void:
	add_child(WebProbe.new())
	# Above the router, below the film: "turn your phone" when a touch device is held upright.
	var prompt_layer := CanvasLayer.new()
	prompt_layer.layer = TouchRotatePrompt.LAYER
	prompt_layer.add_child(TouchRotatePrompt.new())
	add_child(prompt_layer)
	await get_tree().process_frame
	if KillBench.requested():
		add_child(KillBench.new())
		return
	UIRouter.reset(MENU, UITransition.Kind.FADE)

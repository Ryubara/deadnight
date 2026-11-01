@tool
extends EditorPlugin
## Registers the screen router autoload while the plugin is enabled.

const AUTOLOAD_NAME := "UIRouter"
const ROUTER_PATH := "res://addons/gds_ui/router/ui_router.gd"


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, ROUTER_PATH)


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)

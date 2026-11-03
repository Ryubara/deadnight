extends Node
## The ammunition card and the wall's prompt card with each gun name (#857), one name every `HOLD`
## frames. `-- --set=old` shows the real designations the guns would carry without the decision,
## `-- --set=new` the chosen names, so the longest ("Double-Feature Gun") is seen to fit. Not part
## of the game. Run with Movie Maker: `godot --path game
## res://tests/captures/weapon_names_sheet.tscn --fixed-fps 10 --write-movie out.png
## --quit-after 75 -- --set=new`.

const OLD: Array[String] = ["MP5", "PPSh", "M4A1", "M249", "Pump 870", "Ray gun", "Freeze gun"]
const NEW: Array[String] = [
	"Usher SMG",
	"Reel Gun",
	"Matinee Carbine",
	"Double-Feature Gun",
	"Popper",
	"Moonbeam Pistol",
	"Snow-Cone Gun",
]
const HOLD := 10
const PRICES: Array[int] = [1300, 750, 1600, 1500, 900, 2000, 1800]

var _hud: Hud
var _names := NEW
var _frame := 0


func _ready() -> void:
	if "--set=old" in OS.get_cmdline_user_args():
		_names = OLD
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = (load(Hud.SCENE) as PackedScene).instantiate()
	layer.add_child(_hud)
	_hud.state.set_health(100.0, 100.0)
	_show(0)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame % HOLD == 0 and _frame / HOLD < _names.size():
		_show(_frame / HOLD)


func _show(index: int) -> void:
	_hud.state.set_ammo(30, 120, _names[index])
	_hud.state.set_equipment("Revolver", 1)
	_hud.state.set_prompt(&"buy_weapon", _names[index], PRICES[index])
	print("frame %d: %s" % [_frame, _names[index]])

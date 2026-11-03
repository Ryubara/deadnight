extends Node
## The ammunition card and the equipment slot with each chosen gun name (#857), one name every
## `HOLD` frames, so the longest ("Double-Feature Gun") is seen to fit. Not part of the game.
## Run with Movie Maker: `godot --path game res://tests/captures/weapon_names_sheet.tscn
## --fixed-fps 10 --write-movie out.png --quit-after 80`.

const NAMES: Array[String] = [
	"Usher SMG",
	"Reel Gun",
	"Matinee Carbine",
	"Double-Feature Gun",
	"Popper",
	"Moonbeam Pistol",
	"Snow-Cone Gun",
]
const HOLD := 10

var _hud: Hud
var _frame := 0


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = (load(Hud.SCENE) as PackedScene).instantiate()
	layer.add_child(_hud)
	_hud.state.set_health(100.0, 100.0)
	_show(0)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame % HOLD == 0 and _frame / HOLD < NAMES.size():
		_show(_frame / HOLD)


func _show(index: int) -> void:
	_hud.state.set_ammo(30, 120, NAMES[index])
	_hud.state.set_equipment("Revolver", 1)
	print("frame %d: %s" % [_frame, NAMES[index]])

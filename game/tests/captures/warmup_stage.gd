extends Node
## Shows what the night's warm-up draws, without the loading screen over it: the lot from above lit
## and dark, then the stage in each light condition. For captures (a frame is a shot). Not part of
## the game.

var _night: Night


func _ready() -> void:
	_night = Night.new()
	_night.warm_up = true
	add_child(_night)
	_night.loading.connect(
		func(fraction: float, text: String) -> void: print("loading %.2f %s" % [fraction, text])
	)
	var began := Time.get_ticks_msec()
	await _night.start(Night.Mode.AUTOPILOT)
	print("warm-up done in %d ms, %d shots" % [Time.get_ticks_msec() - began, _night.warmup.shots])
	print("lot bounds: ", _night.warmup.lot_bounds)
	print("recorded: %d draw strings" % _night.warmup.ledger.seen.size())
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()

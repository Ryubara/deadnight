class_name MachineView
extends RefCounted
## Plays the lot's machines when the server says a purchase was made: the re-cut bench on
## `weapon_upgraded` (with the weapon that was re-cut), the soda fountain on the purchase of its
## tonic. The machines draw and step themselves (`RecutMachine`, `SodaFountain`); this only starts
## them, from events every client hears, so everyone sees the bench go.

## The shop item the fountain pours.
const TONIC_ITEM := &"tonic_hearty"

var _root: Node


## `root` is any node in the night's tree: the machines are found in its groups when needed.
func setup(state: ClientState, root: Node) -> void:
	_root = root
	state.event_received.connect(_on_event)


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"weapon_upgraded":
			for machine in _root.get_tree().get_nodes_in_group(RecutMachine.GROUP):
				(machine as RecutMachine).play(event["weapon_id"])
		&"purchase_made":
			if event["item_id"] == TONIC_ITEM:
				for fountain in _root.get_tree().get_nodes_in_group(SodaFountain.GROUP):
					(fountain as SodaFountain).play()

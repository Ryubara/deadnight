class_name HostAway
extends RefCounted
## A seat held for a player whose socket dropped.
var token: PackedByteArray
## When the seat is given up (the host's clock, seconds).
var until: float
## The backend's user id of the player (`""` without a ticket).
var user: String


func _init(p_token: PackedByteArray, p_until: float, p_user: String = "") -> void:
	token = p_token
	until = p_until
	user = p_user

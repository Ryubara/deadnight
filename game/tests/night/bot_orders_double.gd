class_name NightWithBotOrdersDouble
extends Node
## A stand-in for a `Night` that has `bot_orders` (#641): it records what the wheel's link gives it.
## `BotOrderLink.for_night` only needs a node with a `bot_orders` that has `issue`.

var bot_orders := Recorder.new()


class Recorder:
	extends RefCounted
	var heard: Array = []

	func issue(order: StringName, issuer_id: int, at: Vector3, bot_id := 0) -> Dictionary:
		heard.append({&"order": order, &"issuer": issuer_id, &"at": at, &"bot": bot_id})
		return {&"type": &"order", &"order": order, &"at": at, &"bot_id": bot_id}

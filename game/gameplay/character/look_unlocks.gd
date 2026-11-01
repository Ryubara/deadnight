class_name LookUnlocks
extends RefCounted
## What this player may wear. Progression (docs/design/progression.md) is cosmetics only and is
## not built yet, so this holds the facts the gates ask about at their starting values; the
## platform backend fills them in later. A gate is a dictionary: empty means free, otherwise
## `billing` (an account level), `stubs` (a price, bought once) or `order` (a named goal).

## Account level. A gate `{"billing": n}` opens at level n.
var billing_level := 1
## Options bought or earned by other means, keyed by `key`.
var owned := {}


## The key under which an option is recorded as owned.
static func key(slot: StringName, id: StringName) -> String:
	return "%s/%s" % [slot, id]


func is_unlocked(slot: StringName, id: StringName, gate: Dictionary) -> bool:
	if gate.is_empty() or owned.has(key(slot, id)):
		return true
	return gate.has("billing") and billing_level >= int(gate["billing"])


func grant(slot: StringName, id: StringName) -> void:
	owned[key(slot, id)] = true


## Words for a locked option: how to get it.
static func describe(gate: Dictionary) -> String:
	if gate.has("billing"):
		return "Reach Billing level %d" % int(gate["billing"])
	if gate.has("stubs"):
		return "%d stubs at the prize counter" % int(gate["stubs"])
	if gate.has("order"):
		return "Finish the order: %s" % gate["order"]
	return ""

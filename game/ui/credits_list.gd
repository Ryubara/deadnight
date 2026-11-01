class_name CreditsList
extends Resource
## What the Credits screen shows. One entry per line: `# Heading` starts a section, anything
## else is a line of that section (`Name - what they did`).

@export var lines := PackedStringArray()


## The lines as sections: [{"heading": String, "names": PackedStringArray}].
func sections() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw in lines:
		var line := raw.strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("# "):
			out.append({"heading": line.substr(2), "names": PackedStringArray()})
		else:
			if out.is_empty():
				out.append({"heading": "", "names": PackedStringArray()})
			# A packed array is a value: append to a copy, then store it back.
			var names: PackedStringArray = out.back()["names"]
			names.append(line)
			out.back()["names"] = names
	return out

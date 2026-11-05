class_name LoadoutPanel
extends MenuPanel
## The Loadout tab: the wardrobe's grid (the customize screen, embedded) beside a showcase
## weapon row, with the soldier on the stage showing every change at once. The showcase weapon is
## cosmetic: it is what the menu's soldier holds, and a night starts with the starter program
## whatever is chosen.
##
## Every choice on the tab (the wardrobe's parts and colours, the showcase weapon) is held in
## memory while the tab is open: the wardrobe keeps the working look, `_weapon` the weapon, and the
## stage shows both. Nothing is written per click. `commit` writes them once, when the player
## leaves: another tab, a screen the menu opens, or closing the menu (`MenuShell`).

const CUSTOMIZE := "res://ui/screens/customize_screen.tscn"
## The width the Plate button keeps on the mastery line, desktop and phone.
const PLATE_BUTTON_WIDTH := 300.0
const PLATE_BUTTON_WIDTH_COMPACT := 110.0

var wardrobe: CustomizeScreen

var _weapon_selector: UIOptionSelector
var _weapon_row: UIRow
var _plate_button: UIButton
var _mastery_label: Label
var _weapons: Array[StringName] = []
## The showcase weapon chosen on the tab, saved or not yet.
var _weapon: StringName = MenuHero.DEFAULT_WEAPON


func _ready() -> void:
	_weapon = MenuHero.saved_weapon()
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override(&"separation", 6 if context.compact else 14)
	add_child(column)
	# A phone leaves 372 units: the heading goes (the tab bar says where you are).
	if not context.compact:
		column.add_child(MenuLook.heading("Loadout", "Dress the soldier"))
	var weapon_box := _build_weapon_row()
	if not context.compact:
		column.add_child(weapon_box)
	wardrobe = (load(CUSTOMIZE) as PackedScene).instantiate() as CustomizeScreen
	wardrobe.params = {
		"embedded": true,
		"compact": context.compact,
		"unlocks": LookUnlocks.at_level(context.profile.level()),
	}
	wardrobe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wardrobe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(wardrobe)
	# A phone has 372 units for the tab: the weapon row scrolls with the pickers.
	if context.compact:
		wardrobe.prepend_row(weapon_box)
	# The weapon row lines up with the wardrobe's rows, and is as narrow as they are.
	_weapon_row.set_widths(wardrobe.row_widths.x, wardrobe.row_widths.y)
	wardrobe.look_changed.connect(_on_look_changed)
	wardrobe.rows_stacked.connect(_weapon_row.set_stacked)
	if context.compact:
		_fit_for_fingers()
	refresh()


func width(compact: bool) -> float:
	# The pickers' rows are about 800 units wide: a label column, a 440 selector, the padding.
	return 860.0 if compact else 900.0


func first_focus() -> Control:
	return _weapon_selector


## The button that opens the plate's calling cards and emblems.
func plate_button() -> UIButton:
	return _plate_button


## What the plate button says: the card and emblem the player wears.
func plate_text() -> String:
	return _plate_button.text


## The weapons the row offers: those whose class has a model.
func weapons() -> Array[StringName]:
	return _weapons


func selector() -> UIOptionSelector:
	return _weapon_selector


## The line under the weapon: its mastery level.
func mastery_text() -> String:
	return _mastery_label.text


## Shows the choices held now (the saved ones when the tab was just opened).
func refresh() -> void:
	if _weapon_selector == null:
		return
	_weapon_selector.select(maxi(_weapons.find(_weapon), 0), false)
	_show_mastery(_weapon)


## The level changed (the account's profile was read, a night ended): the wardrobe's locks follow.
func set_unlocks(unlocks: LookUnlocks) -> void:
	if wardrobe != null:
		wardrobe.set_unlocks(unlocks)


## The tab is shown again: what was committed on leaving is what is saved, so start from it.
func on_show() -> void:
	_weapon = MenuHero.saved_weapon()
	_show_plate()
	super.on_show()


func on_hide() -> void:
	commit()


## Whether a choice on the tab is not saved yet.
func is_dirty() -> bool:
	return _weapon != MenuHero.saved_weapon() or (wardrobe != null and wardrobe.is_dirty())


## Writes every choice held on the tab with one write of the file, and nothing when none changed.
func commit() -> void:
	if not is_dirty():
		return
	if wardrobe != null and wardrobe.is_dirty():
		wardrobe.commit()
	Settings.set_value(SettingsService.SHOWCASE_WEAPON, String(_weapon))
	Settings.save()


func _build_weapon_row() -> Control:
	var row := UIRow.new()
	_weapon_row = row
	# On a phone the title column is the wardrobe's 150 units: the short word fits it.
	row.title = "Weapon" if context.compact else "Showcase weapon"
	row.hint = (
		""
		if context.compact
		else ("The soldier holds it here. A night starts with the starter program.")
	)
	_weapon_selector = UIOptionSelector.new()
	var names := PackedStringArray()
	_weapons = MenuHero.available()
	for id in _weapons:
		var def := WeaponCatalog.get_def(id)
		names.append(def.display_name if def != null and def.display_name != "" else String(id))
	_weapon_selector.options = names
	_weapon_selector.selected_changed.connect(_on_weapon_selected)
	row.set_control(_weapon_selector)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	box.add_child(row)
	var line := HBoxContainer.new()
	box.add_child(line)
	_mastery_label = MenuLook.label("", MenuLook.SIZE_CAPTION, MenuLook.MUTED, &"wide")
	_mastery_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(_mastery_label)
	# The plate's button shares the mastery line, so the tab is no taller than it was.
	_plate_button = UIButton.new()
	_plate_button.name = "PlateButton"
	_plate_button.variant = UIButton.Variant.GHOST
	_plate_button.pressed.connect(func() -> void: context.request(&"cards"))
	line.add_child(_plate_button)
	_show_plate()
	return box


## The button's words: the card, the emblem and the frame worn, or what to do when there are none.
func _show_plate() -> void:
	if _plate_button == null:
		return
	var read: Variant = ProfileSave.read(MenuProfile.profile_path)["profile"]
	var catalog := PlateCatalog.shipped()
	var worn := {"card": &"", "emblem": &"", "frame": &""}
	if read != null:
		var profile := read as Profile
		worn = catalog.worn(profile.equipped, profile.level(), profile.done)
	var words: Array[String] = []
	for kind in PlateCatalog.KINDS:
		if worn[kind] != &"":
			words.append(catalog.title(kind, worn[kind]))
	_plate_button.text = (
		"Plate: " + " + ".join(words) if not words.is_empty() else "Plate: cards, emblems, frames"
	)
	# A phone's tab has 372 units: the button says only what it opens.
	if context.compact:
		_plate_button.text = "Plate"
	_plate_button.clip_text = true
	_plate_button.custom_minimum_size.x = (
		PLATE_BUTTON_WIDTH_COMPACT if context.compact else PLATE_BUTTON_WIDTH
	)


## On a phone every picker is at least a tap target high and no text is under the type floor.
func _fit_for_fingers() -> void:
	for node in find_children("*", "Label", true, false):
		var label := node as Label
		var size := label.get_theme_font_size(&"font_size")
		label.add_theme_font_size_override(&"font_size", maxi(size, MenuLook.SIZE_CAPTION))
	for node in wardrobe.find_children("*", "", true, false):
		if node is UIOptionSelector or node is UIButton:
			var control := node as Control
			control.custom_minimum_size.y = maxf(control.custom_minimum_size.y, MenuLook.TAP_TARGET)
	_weapon_selector.custom_minimum_size.y = maxf(
		_weapon_selector.custom_minimum_size.y, MenuLook.TAP_TARGET
	)
	_plate_button.custom_minimum_size.y = maxf(
		_plate_button.custom_minimum_size.y, MenuLook.TAP_TARGET
	)


func _on_weapon_selected(index: int) -> void:
	if index < 0 or index >= _weapons.size():
		return
	_weapon = _weapons[index]
	_show_mastery(_weapon)
	if context.stage != null:
		context.stage.preview_look(wardrobe.look, _weapon)


func _show_mastery(weapon: StringName) -> void:
	var profile := context.profile
	_mastery_label.text = (
		"Mastery %d of 10 - %d%% to the next"
		% [profile.mastery_level(weapon), roundi(profile.mastery_fraction(weapon) * 100.0)]
	)


func _on_look_changed(look: CharacterLook) -> void:
	if context.stage != null:
		context.stage.preview_look(look, _weapon)

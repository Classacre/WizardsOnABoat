class_name SeaHUD
extends CanvasLayer

signal host_requested(world_name: String, seed_value: int, wizard_name: String)
signal join_requested(address: String, wizard_name: String)
signal action(action_name: String, data: Dictionary)
signal spell_selected(recipe: Array, spell_name: String)
signal staff_selected(staff_id: String)
signal modal_changed(open: bool)

const INK := Color("102f3c")
const CREAM := Color("f6e8c8")
const GOLD := Color("e9ba65")
var root: Control
var main_menu: PanelContainer
var modal: PanelContainer
var modal_body: VBoxContainer
var title_label: Label
var status: Label
var location_label: Label
var stats: Label
var prompt: Label
var objective: Label
var notice: Label
var spell_label: Label
var crosshair: Label
var breath_bar: ProgressBar
var mana_bar: ProgressBar
var underwater_tint: ColorRect
var gameplay: Control
var current_panel := ""
var notice_timer := 0.0
var _snapshot: Dictionary = {}
var _player_id := ""
var _craft: Array = []
var _craft_label: Label

func _ready() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	theme.default_font_size = 20
	theme.set_color("font_color","Label",CREAM)
	theme.set_color("font_color","Button",CREAM)
	theme.set_color("font_hover_color","Button",GOLD)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035,0.12,0.16,0.95)
	panel_style.border_color = Color("ad985e")
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(7)
	panel_style.content_margin_left = 26
	panel_style.content_margin_right = 26
	panel_style.content_margin_top = 22
	panel_style.content_margin_bottom = 22
	theme.set_stylebox("panel","PanelContainer",panel_style)
	var button_style := StyleBoxFlat.new()
	button_style.bg_color = Color("245363")
	button_style.set_corner_radius_all(4)
	button_style.content_margin_top = 11
	button_style.content_margin_bottom = 11
	button_style.content_margin_left = 16
	button_style.content_margin_right = 16
	theme.set_stylebox("normal","Button",button_style)
	var hover := button_style.duplicate()
	hover.bg_color = Color("326f79")
	theme.set_stylebox("hover","Button",hover)
	theme.set_stylebox("pressed","Button",button_style)
	root.theme = theme
	_build_gameplay()
	_build_menu()
	modal = PanelContainer.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	modal.position = Vector2(425,120)
	modal.size = Vector2(686,760)
	modal.visible = false
	root.add_child(modal)
	modal_body = VBoxContainer.new()
	modal_body.add_theme_constant_override("separation",12)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size=Vector2(634,690)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	modal.add_child(scroll)
	modal_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(modal_body)
	notice = _label("",22)
	root.add_child(notice)
	notice.position = Vector2(300,185)
	notice.size = Vector2(936,90)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _label(text: String, font_size := 20) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_shadow_color",Color(0.02,0.06,0.08,0.75))
	label.add_theme_constant_override("shadow_offset_x",1)
	label.add_theme_constant_override("shadow_offset_y",2)
	return label

func _button(text: String, callback: Callable, parent: Node) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _build_menu() -> void:
	main_menu = PanelContainer.new()
	root.add_child(main_menu)
	main_menu.position = Vector2(72,190)
	main_menu.size = Vector2(440,660)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",14)
	main_menu.add_child(box)
	box.add_child(_label("THE GREAT SEA",18))
	box.add_child(_label("WIZARDS\nON A BOAT",46))
	box.add_child(_label("A shared sea of spells & strange islands",18))
	box.add_child(HSeparator.new())
	var name_input := LineEdit.new()
	name_input.placeholder_text = "Your wizard name"
	name_input.text = "Wayfarer"
	box.add_child(name_input)
	var world_input := LineEdit.new()
	world_input.text = "Hearthharbour"
	world_input.placeholder_text = "World name / save slot"
	box.add_child(world_input)
	var seed_input := LineEdit.new()
	seed_input.text = "7319"
	seed_input.placeholder_text = "World seed"
	box.add_child(seed_input)
	_button("SET SAIL  ·  Host / continue world",func():host_requested.emit(world_input.text,seed_input.text.to_int(),name_input.text),box)
	var address := LineEdit.new()
	address.text = "127.0.0.1"
	address.placeholder_text = "Host IP address"
	box.add_child(address)
	_button("JOIN A WORLD",func():join_requested.emit(address.text,name_input.text),box)
	status = _label("18 wizards · 6 ships · 4 per crew\nProgress belongs to each world.",16)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	_button("Quit",func():get_tree().quit(),box)

func _build_gameplay() -> void:
	gameplay = Control.new()
	gameplay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gameplay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(gameplay)
	gameplay.visible = false
	underwater_tint = ColorRect.new()
	underwater_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	underwater_tint.color = Color(0.02,0.35,0.48,0.15)
	underwater_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gameplay.add_child(underwater_tint)
	underwater_tint.visible = false
	location_label = _label("HEARTHHARBOUR",23)
	location_label.position = Vector2(44,34)
	gameplay.add_child(location_label)
	objective = _label("Find the apprentice's wind cache at the old ruin.",18)
	objective.position = Vector2(44,72)
	gameplay.add_child(objective)
	stats = _label("",20)
	stats.position = Vector2(44,904)
	gameplay.add_child(stats)
	mana_bar = ProgressBar.new()
	mana_bar.position = Vector2(44,948)
	mana_bar.size = Vector2(240,8)
	mana_bar.show_percentage = false
	gameplay.add_child(mana_bar)
	breath_bar = ProgressBar.new()
	breath_bar.position = Vector2(640,850)
	breath_bar.size = Vector2(256,14)
	breath_bar.max_value = 30
	breath_bar.show_percentage = false
	gameplay.add_child(breath_bar)
	crosshair = _label("·",32)
	crosshair.position = Vector2(759,491)
	gameplay.add_child(crosshair)
	prompt = _label("",22)
	prompt.position = Vector2(400,726)
	prompt.size = Vector2(736,55)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gameplay.add_child(prompt)
	spell_label = _label("EMPTY SPELLBOOK",20)
	spell_label.position = Vector2(1090,904)
	gameplay.add_child(spell_label)
	var controls := _label("WASD Move   Space Jump / swim up   Ctrl Dive   E Interact\nB Spellbook   I Satchel   C Crew   H Hearthstone   Esc Menu",16)
	controls.position = Vector2(780,950)
	gameplay.add_child(controls)

func entered_world() -> void:
	main_menu.hide()
	gameplay.show()
	close_panel()

func show_notice(message: String) -> void:
	notice.text = message
	notice_timer = 5.0
	if status:
		status.text = message

func _process(delta: float) -> void:
	notice_timer -= delta
	if notice_timer <= 0:
		notice.text = ""

func update_player(snapshot: Dictionary, player_id: String, wizard: Node, area: String, hint: String) -> void:
	_snapshot = snapshot
	_player_id = player_id
	var data: Dictionary = snapshot.get("players",{}).get(player_id,{})
	if data.is_empty():
		return
	location_label.text = area.to_upper()+ ("  ·  PROTECTED HARBOUR" if data.get("safe_zone",false) else "")
	stats.text = "♥  %d    ✦  %d    ◈  %d gold" % [data.get("health",100),wizard.mana,data.get("inventory",{}).get("gold",0)]
	mana_bar.value = wizard.mana
	breath_bar.visible = wizard.head_underwater
	breath_bar.value = wizard.breath
	underwater_tint.visible = wizard.head_underwater
	prompt.text = hint
	if not data.get("alive",true):
		prompt.text = "Lost at sea.  Press E to return."
	objective.text = "Find the apprentice's wind cache at the old ruin.  ◇" if data.get("learned",[]).is_empty() else "Explore ruins for glyphs. Aim Gale at your sail to catch the wind."

func close_panel() -> void:
	modal.hide()
	current_panel = ""
	modal_changed.emit(false)

func _open(title: String) -> void:
	for child in modal_body.get_children():
		child.queue_free()
		modal_body.remove_child(child)
	modal_body.add_child(_label(title,32))
	_button("Close  [Esc]",close_panel,modal_body)
	modal.show()
	modal_changed.emit(true)

func open_book() -> void:
	current_panel = "book"
	_open("YOUR SPELLBOOK")
	var data: Dictionary = _snapshot.get("players",{}).get(_player_id,{})
	var spells: Dictionary = data.get("spells",{})
	for spell_name in spells:
		var recipe: Array = spells[spell_name]
		_button(spell_name+"  ·  "+" → ".join(recipe),func():spell_selected.emit(recipe,spell_name);close_panel(),modal_body)
	modal_body.add_child(_label("Write a spell: form → effects → modifiers",18))
	_craft = []
	_craft_label = _label("Choose a form first",20)
	modal_body.add_child(_craft_label)
	var glyphs := GridContainer.new()
	glyphs.columns = 3
	modal_body.add_child(glyphs)
	for glyph in data.get("learned",[]):
		_button(str(glyph).capitalize(),func():
			if _craft.size()<6:
				_craft.append(glyph)
				_craft_label.text=" → ".join(_craft)
		,glyphs)
	var spell_name_input := LineEdit.new()
	spell_name_input.placeholder_text = "Name your spell"
	spell_name_input.text = "Wayfarer's spell"
	modal_body.add_child(spell_name_input)
	_button("Inscribe spell",func():action.emit("save_spell",{"name":spell_name_input.text,"recipe":_craft.duplicate()}),modal_body)
	_button("Clear glyph sequence",func():_craft.clear();_craft_label.text="Choose a form first",modal_body)
	var help := _label("Glyphs are found in dungeons and on bosses.\nModifiers affect the preceding effect. The shop sells equipment, never glyphs.",17)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_body.add_child(help)

func open_shop() -> void:
	current_panel = "shop"
	_open("MARA'S CHANDLERY")
	modal_body.add_child(_label("Compasses, provisions and curious equipment",18))
	for id in GameCatalog.SHOP:
		var item: Dictionary = GameCatalog.SHOP[id]
		_button("%s    %d gold" % [item.name,item.buy],func():action.emit("buy",{"item":id}),modal_body)
	_button("Sell gathered materials",func():action.emit("sell",{"item":"all_materials"}),modal_body)

func open_inventory() -> void:
	current_panel = "inventory"
	_open("YOUR SATCHEL")
	var data: Dictionary = _snapshot.get("players",{}).get(_player_id,{})
	for id in data.get("inventory",{}):
		modal_body.add_child(_label("%s  × %d" % [str(id).replace("_"," ").capitalize(),data.inventory[id]],20))
	modal_body.add_child(_label("Equipment: "+", ".join(data.get("equipment",[])),17))
	var owned:Array=data.get("inventory",{}).keys()+data.get("equipment",[])
	for id in owned:
		if not _snapshot.get("items",{}).has(id): continue
		var staff:Dictionary=_snapshot.items[id]
		modal_body.add_child(_label("Staff: "+str(staff.get("affix","")),18))
		if not staff.get("recipe",[]).is_empty():
			_button("Wield inscribed staff",func():staff_selected.emit(id),modal_body)
		for spell_name in data.get("spells",{}):
			_button("Teach staff: "+str(spell_name),func():action.emit("teach_staff",{"staff_id":id,"spell_name":spell_name}),modal_body)
	_button("Drink healing potion",func():action.emit("interact",{"kind":"potion"}),modal_body)
	_button("Use bound hearthstone",func():action.emit("hearthstone",{});close_panel(),modal_body)
	_button("Read biome compass",func():action.emit("interact",{"kind":"compass"}),modal_body)

func open_crews() -> void:
	current_panel = "crews"
	_open("CREWS OF THE GREAT SEA")
	modal_body.add_child(_label("Four berths per crew. One ship per crew.",18))
	for id in _snapshot.get("crews",{}):
		var crew: Dictionary = _snapshot.crews[id]
		_button("%s   %d / 4 wizards" % [crew.name,crew.members.size()],func():action.emit("join_crew",{"crew_id":id}),modal_body)
	_button("Found a new crew",func():action.emit("create_crew",{"name":"The Wayfarers"}),modal_body)

func open_pause() -> void:
	current_panel = "pause"
	_open("THE SEA KEEPS MOVING")
	modal_body.add_child(_label("WASD  Move / steer at helm\nSpace  Jump / swim upwards\nCtrl  Dive\nE  Interact / release helm\nLeft mouse  Cast selected spell\n1 / 2  Select first / second spell\nB  Spellbook     I  Satchel     C  Crews\nH  Hearthstone     Q  Healing potion",22))
	_button("Save & leave world",func():action.emit("leave",{}),modal_body)

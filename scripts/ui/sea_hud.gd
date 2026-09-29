class_name SeaHUD
extends CanvasLayer

signal host_requested(world_name: String, seed_value: int, wizard_name: String)
signal join_requested(address: String, wizard_name: String)
signal action(action_name: String, data: Dictionary)
signal spell_selected(recipe: Array, spell_name: String)
signal staff_selected(staff_id: String)
signal modal_changed(open: bool)
signal dev_requested
signal dev_action(action_name: String, data: Dictionary)

const INK := Color("102f3c")
const CREAM := Color("f6e8c8")
const GOLD := Color("e9ba65")
var root: Control
var main_menu: PanelContainer
var main_menu_scroll: ScrollContainer
var modal: PanelContainer
var modal_body: VBoxContainer
var modal_scroll: ScrollContainer
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
var _glyph_grid: GridContainer
var _controls_label: Label
var _dev_fly_speed := 24.0
var _world_input: LineEdit
var _seed_input: LineEdit

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
	modal.visible = false
	root.add_child(modal)
	var modal_column := VBoxContainer.new()
	modal_column.add_theme_constant_override("separation",8)
	modal.add_child(modal_column)
	title_label = _label("",30)
	modal_column.add_child(title_label)
	_button("Close  [Esc]",close_panel,modal_column)
	modal_column.add_child(HSeparator.new())
	modal_scroll = ScrollContainer.new()
	modal_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal_column.add_child(modal_scroll)
	modal_body = VBoxContainer.new()
	modal_body.add_theme_constant_override("separation",12)
	modal_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	modal_scroll.add_child(modal_body)
	notice = _label("",22)
	root.add_child(notice)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	get_viewport().size_changed.connect(_layout_ui)
	_layout_ui.call_deferred()

func _label(text: String, font_size := 20) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_shadow_color",Color(0.02,0.06,0.08,0.75))
	label.add_theme_constant_override("shadow_offset_x",1)
	label.add_theme_constant_override("shadow_offset_y",2)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _button(text: String, callback: Callable, parent: Node) -> Button:
	var button := Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _build_menu() -> void:
	main_menu = PanelContainer.new()
	root.add_child(main_menu)
	main_menu_scroll = ScrollContainer.new()
	main_menu_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_menu_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_menu.add_child(main_menu_scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",14)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_menu_scroll.add_child(box)
	box.add_child(_label("THE GREAT SEA",18))
	box.add_child(_label("WIZARDS\nON A BOAT",46))
	box.add_child(_label("A shared sea of spells & strange islands",18))
	box.add_child(HSeparator.new())
	var name_input := LineEdit.new()
	name_input.placeholder_text = "Your wizard name"
	name_input.text = "Wayfarer"
	box.add_child(name_input)
	box.add_child(_label("WORLD NAME · SAVE SLOT",16))
	_world_input = LineEdit.new()
	_world_input.text = "Hearthharbour"
	_world_input.placeholder_text = "Name this world"
	box.add_child(_world_input)
	box.add_child(_label("WORLD SEED · SIGNED INTEGER",16))
	_seed_input = LineEdit.new()
	_seed_input.text = "7319"
	_seed_input.placeholder_text = "For example: 7319"
	box.add_child(_seed_input)
	_button("Randomize seed",func():_seed_input.text = str(randi_range(0,2147483647)),box)
	box.add_child(_label("New worlds use generator v2. Share the seed and generator version to recreate terrain. The name identifies a save slot; use a new name for a different seed.",16))
	_button("SET SAIL  ·  Host / continue world",func():_request_host(name_input.text),box)
	var active_session := get_tree().root.get_node_or_null("Session")
	if active_session != null and active_session.save_enabled:
		_add_saved_world_picker(box,active_session.saved_worlds())
	var address := LineEdit.new()
	address.text = "127.0.0.1"
	address.placeholder_text = "Host IP address"
	box.add_child(address)
	_button("JOIN A WORLD",func():join_requested.emit(address.text,name_input.text),box)
	status = _label("18 wizards · 6 ships · 4 per crew\nProgress belongs to each world.",16)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	_button("Quit",func():get_tree().quit(),box)

func _parse_seed(text_value: String) -> Dictionary:
	var entered := text_value.strip_edges()
	if not entered.is_valid_int():
		return {"ok":false,"error":"Enter a whole-number world seed."}
	var value := entered.to_int()
	if value < -2147483648 or value > 2147483647:
		return {"ok":false,"error":"World seed must be between -2147483648 and 2147483647."}
	return {"ok":true,"seed":value}

func _request_host(wizard_name: String) -> void:
	var world_name := _world_input.text.strip_edges()
	if world_name.is_empty() or world_name.length() > 64:
		show_notice("Enter a world name of 1–64 characters.")
		return
	var parsed := _parse_seed(_seed_input.text)
	if not parsed.ok:
		show_notice(str(parsed.error))
		return
	host_requested.emit(world_name,int(parsed.seed),wizard_name)

func _add_saved_world_picker(box: VBoxContainer, saves: Array[Dictionary]) -> void:
	if saves.is_empty():
		return
	box.add_child(HSeparator.new())
	box.add_child(_label("SAVED WORLDS · SELECT TO FILL NAME AND SEED",16))
	for record in saves:
		var world_name := str(record.get("name",""))
		var seed := int(record.get("seed",0))
		var generation := int(record.get("generator_version",1))
		_button("Continue %s · seed %d · v%d" % [world_name,seed,generation],func():
			_world_input.text = world_name
			_seed_input.text = str(seed)
			status.text = "Selected saved world. Set sail to continue it."
		,box)

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
	_controls_label = _label("WASD Move · Space Jump · Ctrl Dive · E Interact\nB Spellbook · I Satchel · C Crew · F3 Dev · Esc Menu",16)
	gameplay.add_child(_controls_label)

func _center_panel(panel: PanelContainer, viewport_size: Vector2, desired_size: Vector2) -> void:
	var margin := 12.0 if viewport_size.x < 700.0 else 24.0
	var width := minf(desired_size.x,maxf(40.0,viewport_size.x-margin*2.0))
	var height := minf(desired_size.y,maxf(40.0,viewport_size.y-margin*2.0))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -width*0.5
	panel.offset_top = -height*0.5
	panel.offset_right = width*0.5
	panel.offset_bottom = height*0.5

func _layout_ui() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	_center_panel(main_menu,viewport_size,Vector2(520,740))
	_center_panel(modal,viewport_size,Vector2(720,760))
	if is_instance_valid(_glyph_grid):
		_glyph_grid.columns = 1 if viewport_size.x < 420.0 else 2 if viewport_size.x < 700.0 else 3
	var margin := 16.0 if viewport_size.x < 700.0 else 36.0
	var width := maxf(40.0,viewport_size.x-margin*2.0)
	notice.position = Vector2(margin,maxf(12.0,viewport_size.y*0.12))
	notice.size = Vector2(width,minf(90.0,viewport_size.y*0.18))
	location_label.position = Vector2(margin,20)
	location_label.size = Vector2(width,36)
	objective.position = Vector2(margin,56)
	objective.size = Vector2(width,48)
	var compact := viewport_size.x < 800.0 or viewport_size.y < 560.0
	stats.position = Vector2(margin,maxf(0.0,viewport_size.y-78.0))
	stats.size = Vector2(width*0.52,48)
	stats.add_theme_font_size_override("font_size",16 if compact else 20)
	mana_bar.position = Vector2(margin,maxf(0.0,viewport_size.y-29.0))
	mana_bar.size = Vector2(minf(240.0,width*0.48),8)
	breath_bar.position = Vector2((viewport_size.x-minf(256.0,width))*0.5,maxf(0.0,viewport_size.y-112.0))
	breath_bar.size = Vector2(minf(256.0,width),14)
	crosshair.position = viewport_size*0.5-Vector2(12,24)
	crosshair.size = Vector2(24,48)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.position = Vector2(margin,maxf(92.0,viewport_size.y-(130.0 if compact else 165.0)))
	prompt.size = Vector2(width,52)
	prompt.add_theme_font_size_override("font_size",17 if compact else 22)
	spell_label.position = Vector2(viewport_size.x-(width*0.48)-margin,maxf(0.0,viewport_size.y-90.0))
	spell_label.size = Vector2(width*0.48,50)
	spell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	spell_label.add_theme_font_size_override("font_size",16 if compact else 20)
	_controls_label.visible = not compact and viewport_size.x >= 1100.0
	_controls_label.position = Vector2(viewport_size.x-minf(650.0,width*0.55)-margin,maxf(0.0,viewport_size.y-58.0))
	_controls_label.size = Vector2(minf(650.0,width*0.55),54)
	_controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

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
	_glyph_grid = null
	title_label.text = title
	modal_scroll.scroll_vertical = 0
	_layout_ui()
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
	_glyph_grid = GridContainer.new()
	_glyph_grid.columns = 1 if get_viewport().get_visible_rect().size.x < 420.0 else 2 if get_viewport().get_visible_rect().size.x < 700.0 else 3
	modal_body.add_child(_glyph_grid)
	for glyph in data.get("learned",[]):
		_button(str(glyph).capitalize(),func():
			if _craft.size()<6:
				_craft.append(glyph)
				_craft_label.text=" → ".join(_craft)
		,_glyph_grid)
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
	_add_active_seed_controls()
	modal_body.add_child(_label("WASD  Move / steer at helm\nSpace  Jump / swim upwards\nCtrl  Dive\nE  Interact / release helm\nLeft mouse  Cast selected spell\n1 / 2  Select first / second spell\nB  Spellbook     I  Satchel     C  Crews\nH  Hearthstone     Q  Healing potion\nF3  Developer tools",22))
	_button("Developer tools  [F3]",func():dev_requested.emit(),modal_body)
	_button("Save & leave world",func():action.emit("leave",{}),modal_body)

func _emit_dev_target(action_name: String, id: String, close_after: bool) -> void:
	dev_action.emit(action_name,{"id":id})
	if close_after:
		close_panel()

func _filter_dev_buttons(buttons: Array[Button], query: String) -> void:
	var search := query.strip_edges().to_lower()
	for button in buttons:
		button.visible = search.is_empty() or str(button.get_meta("search","")).contains(search)

func _add_active_seed_controls() -> void:
	if not _snapshot.has("seed"):
		return
	var seed := int(_snapshot.seed)
	var generation := int(_snapshot.get("generator_version",1))
	modal_body.add_child(_label("ACTIVE WORLD SEED · %d · GENERATOR v%d" % [seed,generation],18))
	_button("Copy seed",func():
		DisplayServer.clipboard_set(str(seed))
		show_notice("World seed %d copied." % seed)
	,modal_body)

func open_dev(entries: Array, spawn_catalog: Array, fly_enabled: bool, is_host: bool) -> void:
	current_panel = "dev"
	_open("DEVELOPER MAP")
	_add_active_seed_controls()
	modal_body.add_child(_label("HOST CONTROLS · Teleport, fly, and inspect creatures around the Great Sea." if is_host else "CLIENT · Host controls are unavailable while connected as a client.",17))
	var fly_toggle := CheckButton.new()
	fly_toggle.text = "Fly mode"
	fly_toggle.button_pressed = fly_enabled
	fly_toggle.disabled = not is_host
	fly_toggle.toggled.connect(func(enabled: bool): dev_action.emit("fly_toggle",{"enabled":enabled}))
	modal_body.add_child(fly_toggle)
	var speed_label := _label("Fly speed: %d m/s" % int(_dev_fly_speed),18)
	modal_body.add_child(speed_label)
	var speed_slider := HSlider.new()
	speed_slider.min_value = 5.0
	speed_slider.max_value = 120.0
	speed_slider.step = 5.0
	speed_slider.value = _dev_fly_speed
	speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_slider.mouse_filter = Control.MOUSE_FILTER_STOP if is_host else Control.MOUSE_FILTER_IGNORE
	speed_slider.focus_mode = Control.FOCUS_ALL if is_host else Control.FOCUS_NONE
	speed_slider.modulate.a = 1.0 if is_host else 0.5
	speed_slider.value_changed.connect(func(value: float):
		_dev_fly_speed = value
		speed_label.text = "Fly speed: %d m/s" % int(value)
		dev_action.emit("fly_speed",{"speed":value})
	)
	modal_body.add_child(speed_slider)
	modal_body.add_child(HSeparator.new())
	var search := LineEdit.new()
	search.placeholder_text = "Search..."
	modal_body.add_child(search)
	modal_body.add_child(_label("TELEPORT TO",20))
	var destinations := VBoxContainer.new()
	destinations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_body.add_child(destinations)
	var destination_buttons: Array[Button] = []
	for entry in entries:
		if not entry is Dictionary:
			continue
		var id := str(entry.get("id",""))
		if id.is_empty():
			continue
		var label_text := str(entry.get("label",id))
		var button := _button(label_text,_emit_dev_target.bind("teleport",id,true),destinations)
		button.disabled = not is_host
		button.set_meta("search",(label_text+" "+id).to_lower())
		destination_buttons.append(button)
	if destination_buttons.is_empty():
		destinations.add_child(_label("No destinations available.",17))
	modal_body.add_child(HSeparator.new())
	modal_body.add_child(_label("SPAWN AN ENTITY",20))
	var spawns := VBoxContainer.new()
	spawns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_body.add_child(spawns)
	var spawn_buttons: Array[Button] = []
	if is_host:
		for entry in spawn_catalog:
			if not entry is Dictionary:
				continue
			var id := str(entry.get("id",""))
			if id.is_empty():
				continue
			var label_text := str(entry.get("label",id))
			var button := _button("Spawn  ·  "+label_text,_emit_dev_target.bind("spawn",id,false),spawns)
			button.set_meta("search",(label_text+" "+id).to_lower())
			spawn_buttons.append(button)
		if spawn_buttons.is_empty():
			spawns.add_child(_label("No spawnable entities available.",17))
	else:
		spawns.add_child(_label("Only the host can spawn entities.",17))
	search.text_changed.connect(func(query: String):
		_filter_dev_buttons(destination_buttons,query)
		_filter_dev_buttons(spawn_buttons,query)
	)

extends SceneTree
## Headless layout/signal checks for the responsive HUD and developer menu.

const HUD = preload("res://scripts/ui/sea_hud.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _fits(control: Control, viewport_size: Vector2) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= -1.0 and rect.position.y >= -1.0 and rect.end.x <= viewport_size.x + 1.0 and rect.end.y <= viewport_size.y + 1.0

func _centered(control: Control, viewport_size: Vector2) -> bool:
	var rect := control.get_global_rect()
	return (rect.position + rect.size * 0.5).distance_to(viewport_size * 0.5) <= 1.0

func _find_button(node: Node, caption: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text.contains(caption):
			return child
		var found := _find_button(child,caption)
		if found != null:
			return found
	return null

func _find_line_edit(node: Node) -> LineEdit:
	for child in node.get_children():
		if child is LineEdit:
			return child
		var found := _find_line_edit(child)
		if found != null:
			return found
	return null

func _run() -> void:
	root.get_node("Session").save_enabled = false
	var hud = HUD.new()
	root.add_child(hud)
	await process_frame
	for viewport_size in [Vector2i(320,240),Vector2i(640,360),Vector2i(1280,854),Vector2i(2560,720)]:
		root.size = viewport_size
		await process_frame
		await process_frame
		_check(_fits(hud.main_menu,Vector2(viewport_size)),"Main menu leaves %s viewport" % viewport_size)
		_check(_centered(hud.main_menu,Vector2(viewport_size)),"Main menu is off center at %s" % viewport_size)
		for panel_name in ["pause","book","shop","inventory","crews"]:
			hud.call("open_"+panel_name)
			await process_frame
			_check(_fits(hud.modal,Vector2(viewport_size)),"%s panel leaves %s viewport" % [panel_name,viewport_size])
			_check(_centered(hud.modal,Vector2(viewport_size)),"%s panel is off center at %s" % [panel_name,viewport_size])
			hud.close_panel()
		var entries: Array = []
		var spawns: Array = []
		for index in 40:
			entries.append({"id":"place_%d"%index,"label":"Island destination %d"%index})
			spawns.append({"id":"entity_%d"%index,"label":"Creature entity %d"%index})
		hud.open_dev(entries,spawns,false,true)
		await process_frame
		_check(_fits(hud.modal,Vector2(viewport_size)),"Developer panel leaves %s viewport" % viewport_size)
		_check(_centered(hud.modal,Vector2(viewport_size)),"Developer panel is off center at %s" % viewport_size)
		_check(hud.modal_scroll.get_v_scroll_bar().max_value > hud.modal_scroll.size.y,"Developer content is not scrollable at %s" % viewport_size)
		hud.close_panel()
	# Exercise the viewport signal with an already open panel; there is no manual layout call.
	root.size = Vector2i(1280,854)
	await process_frame
	hud.open_pause()
	root.size = Vector2i(640,360)
	await process_frame
	await process_frame
	_check(_fits(hud.modal,Vector2(640,360)),"Open panel leaves the viewport after resize")
	_check(_centered(hud.modal,Vector2(640,360)),"Open panel is off center after resize")
	hud.close_panel()
	var events: Array = []
	hud.dev_action.connect(func(action_name: String,data: Dictionary): events.append({"action":action_name,"data":data}))
	hud.open_dev([{"id":"rootwatch","label":"Rootwatch"}],[{"id":"kettleback","label":"Kettleback"}],false,true)
	var destination := _find_button(hud.modal_body,"Rootwatch")
	var spawn := _find_button(hud.modal_body,"Kettleback")
	var search := _find_line_edit(hud.modal_body)
	_check(destination != null and spawn != null and search != null,"Developer controls are missing")
	if destination != null and spawn != null and search != null:
		search.text = "kettle"
		search.text_changed.emit(search.text)
		_check(not destination.visible and spawn.visible,"Developer search did not filter destinations")
		search.text = "root"
		search.text_changed.emit(search.text)
		_check(destination.visible and not spawn.visible,"Developer search did not filter spawn entries")
		search.text = ""
		search.text_changed.emit(search.text)
		spawn.pressed.emit()
		_check(events.size() == 1 and events[0].action == "spawn" and events[0].data.id == "kettleback","Spawn button payload is wrong")
		destination.pressed.emit()
	_check(events.size() == 2 and events[1].action == "teleport" and events[1].data.id == "rootwatch","Teleport button payload is wrong")
	_check(not hud.modal.visible,"Teleport did not close the panel")
	hud.open_dev([{"id":"rootwatch","label":"Rootwatch"}],[{"id":"kettleback","label":"Kettleback"}],false,false)
	destination = _find_button(hud.modal_body,"Rootwatch")
	spawn = _find_button(hud.modal_body,"Kettleback")
	var fly := _find_button(hud.modal_body,"Fly mode")
	_check(destination != null and destination.disabled,"Client teleport is enabled")
	_check(spawn == null,"Client spawn entry is shown")
	_check(fly != null and fly.disabled,"Client fly toggle is enabled")
	hud.close_panel()
	var dev_open_requests := [0]
	hud.dev_requested.connect(func(): dev_open_requests[0] += 1)
	hud.open_pause()
	var dev_menu_button := _find_button(hud.modal_body,"Developer tools")
	_check(dev_menu_button != null,"Pause developer button is missing")
	if dev_menu_button != null:
		dev_menu_button.pressed.emit()
	_check(dev_open_requests[0] == 1,"Pause developer button did not request the menu")
	print("UI_LAYOUT_TEST_FAILURES=",failures.size())
	hud.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

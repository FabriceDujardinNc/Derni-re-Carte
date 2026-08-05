extends Control
## Lobby — salle d'attente avant la partie, habillée avec UiKit.
## L'hôte voit son IP + le mot de passe à partager, la liste des joueurs se
## met à jour en direct, et il lance quand tout le monde est là (les sièges
## restants sont remplis par des bots).

var _players_box: VBoxContainer
var _start_button: Button
var _info_label: Label
var _panel: PanelContainer

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.play_menu_music()  # l'ambiance de bar continue dans le salon.
	_build_ui()
	Net.lobby_updated.connect(_refresh_players)
	Net.join_failed.connect(_on_join_failed)
	_refresh_players()
	_animate_entrance()
	# Mode test automatisé : l'hôte lance dès qu'un client a rejoint.
	if Net.is_server and "autostart" in OS.get_cmdline_user_args():
		Net.lobby_updated.connect(func() -> void:
			if Net.peers.size() >= 2:
				Net.start_match_as_host(GameConfig.player_count))

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.make_theme()
	UiKit.add_background(self)

	var card_layer := Control.new()
	card_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(card_layer)
	UiKit.spawn_floating_cards(card_layer, 8)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)

	var title := Label.new()
	title.text = "🎴 Salle d'attente"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.72))
	column.add_child(title)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiKit.panel_style())
	_panel.custom_minimum_size = Vector2(500, 0)
	column.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)

	_info_label = Label.new()
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.modulate = Color(1, 1, 1, 0.75)
	if Net.is_server:
		_info_label.text = "À partager avec tes amis :\nIP : %s   ·   Mot de passe : %s\n(sur le même PC : 127.0.0.1)" % [
			Net.best_local_ip(),
			Net.password if not Net.password.is_empty() else "(aucun)"]
	else:
		_info_label.text = "Connecté ! En attente du lancement par l'hôte…"
	box.add_child(_info_label)

	box.add_child(HSeparator.new())

	var players_title := Label.new()
	players_title.text = "Joueurs connectés :"
	players_title.modulate = Color(1, 1, 1, 0.8)
	box.add_child(players_title)

	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 6)
	box.add_child(_players_box)

	if Net.is_server:
		_start_button = Button.new()
		_start_button.custom_minimum_size = Vector2(0, 52)
		UiKit.style_button(_start_button, UiKit.ACCENT, 22)
		_start_button.pressed.connect(func() -> void:
			Net.start_match_as_host(GameConfig.player_count))
		box.add_child(_start_button)

	var back := Button.new()
	back.text = "Quitter le salon"
	back.flat = true
	back.modulate = Color(1, 1, 1, 0.55)
	UiKit.hover_pop(back)
	back.pressed.connect(func() -> void:
		Net.leave()
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	column.add_child(back)

func _animate_entrance() -> void:
	await get_tree().process_frame
	UiKit.pop_in(_panel)

func _refresh_players() -> void:
	for child in _players_box.get_children():
		child.queue_free()
	var peer_ids := Net.peers.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		var entry: Dictionary = Net.peers[peer_id]
		var label := Label.new()
		var suffix := "  (hôte)" if int(peer_id) == 1 else ""
		label.text = "⬤ %s%s" % [entry["name"], suffix]
		label.add_theme_color_override("font_color",
			GameConfig.PLAYER_COLORS[int(entry["color"]) % GameConfig.PLAYER_COLORS.size()])
		_players_box.add_child(label)
	if _start_button != null:
		var humans := Net.peers.size()
		var bots := maxi(GameConfig.player_count - humans, 0)
		_start_button.text = "🎴  LANCER  (%d joueur%s + %d bot%s)" % [
			humans, "s" if humans > 1 else "", bots, "s" if bots > 1 else ""]

func _on_join_failed(reason: String) -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
	push_warning("Connexion refusée : " + reason)

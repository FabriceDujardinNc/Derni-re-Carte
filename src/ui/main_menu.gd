extends Control
## Menu principal — nom, nombre de joueurs, couleur, solo ou multijoueur.
## Habillé avec UiKit : panneau central animé, titre qui respire, cartes
## flottantes en fond, boutons qui réagissent au survol.

var _name_edit: LineEdit
var _count_slider: HSlider
var _count_label: Label
var _color_buttons: Array[Button] = []
var _selected_color := 0
var _ip_edit: LineEdit
var _password_edit: LineEdit
var _error_label: Label
var _mode_buttons := {}  ## "ffa" / "chains" -> Button
var _selected_mode := "ffa"
var _difficulty_buttons := {}
var _selected_difficulty := "moyen"
var _hat_buttons: Array[Button] = []
var _balance_label: Label
var _title: Label
var _panel: PanelContainer
var _joining := false

func _ready() -> void:
	Net.leave()  # retour au menu = on coupe toute session réseau en cours.
	var args := OS.get_cmdline_user_args()
	# Tests automatisés : `-- host mdp=x autostart` / `-- join ip=x mdp=x`.
	var arg_password := ""
	var arg_ip := "127.0.0.1"
	for arg in args:
		if arg.begins_with("mdp="):
			arg_password = arg.get_slice("=", 1)
		elif arg.begins_with("ip="):
			arg_ip = arg.get_slice("=", 1)
	if "host" in args:
		Net.host_game(Net.DEFAULT_PORT, arg_password, GameConfig.player_name, 0)
		get_tree().change_scene_to_file.call_deferred("res://scenes/lobby.tscn")
		return
	if "join" in args:
		Net.join_game(arg_ip, Net.DEFAULT_PORT, arg_password, "Invité", 1)
		Net.joined_lobby.connect(func() -> void:
			get_tree().change_scene_to_file("res://scenes/lobby.tscn"), CONNECT_ONE_SHOT)
		return
	# Les tests headless solo (autoplay/turbo) sautent le menu et lancent direct.
	if "autoplay" in args or "turbo" in args:
		_start_game()
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_selected_color = GameConfig.color_index
	_build_ui()
	_animate_entrance()
	Audio.play_menu_music()
	Net.joined_lobby.connect(_on_joined_lobby)
	Net.join_failed.connect(_on_net_join_failed)

# ---------------------------------------------------------------- Construction

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.make_theme()
	UiKit.add_background(self)

	# Couche d'ambiance : dos de cartes qui dérivent lentement.
	var card_layer := Control.new()
	card_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(card_layer)
	UiKit.spawn_floating_cards(card_layer, 10)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)

	# --- Titre ---
	_title = Label.new()
	_title.text = Lang.t("🎴 Dernière Carte")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 54)
	_title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.72))
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_title.add_theme_constant_override("shadow_offset_x", 3)
	_title.add_theme_constant_override("shadow_offset_y", 4)
	column.add_child(_title)

	var subtitle := Label.new()
	subtitle.text = Lang.t("Que le meilleur menteur gagne.")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(1, 1, 1, 0.5)
	column.add_child(subtitle)

	# --- Panneau central ---
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiKit.panel_style())
	_panel.custom_minimum_size = Vector2(520, 0)
	column.add_child(_panel)

	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 12)
	_panel.add_child(form)

	# Nom + nombre de joueurs sur la même logique de section.
	form.add_child(_section_label(Lang.t("👤  Ton nom")))
	_name_edit = LineEdit.new()
	_name_edit.text = GameConfig.player_name
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(0, 40)
	form.add_child(_name_edit)

	_count_label = _section_label(Lang.t("🪑  Joueurs à table : %d") % GameConfig.player_count)
	form.add_child(_count_label)
	_count_slider = HSlider.new()
	_count_slider.min_value = 2
	_count_slider.max_value = 8
	_count_slider.step = 1
	_count_slider.value = GameConfig.player_count
	_count_slider.custom_minimum_size = Vector2(0, 26)
	_count_slider.value_changed.connect(func(value: float) -> void:
		_count_label.text = Lang.t("🪑  Joueurs à table : %d") % int(value))
	form.add_child(_count_slider)

	form.add_child(_section_label(Lang.t("🎨  Ta couleur")))
	var color_row := HBoxContainer.new()
	color_row.alignment = BoxContainer.ALIGNMENT_CENTER
	color_row.add_theme_constant_override("separation", 6)
	form.add_child(color_row)
	for i in GameConfig.PLAYER_COLORS.size():
		var button := Button.new()
		button.text = "⬤"
		button.flat = true
		button.custom_minimum_size = Vector2(46, 46)
		button.add_theme_font_size_override("font_size", 30)
		button.add_theme_color_override("font_color", GameConfig.PLAYER_COLORS[i])
		button.add_theme_color_override("font_hover_color", GameConfig.PLAYER_COLORS[i].lightened(0.35))
		button.add_theme_color_override("font_pressed_color", GameConfig.PLAYER_COLORS[i])
		button.pressed.connect(_on_color_selected.bind(i))
		UiKit.hover_pop(button)
		color_row.add_child(button)
		_color_buttons.append(button)
	_refresh_color_buttons()

	# --- Mode de jeu ---
	form.add_child(_section_label(Lang.t("⚔️  Mode de jeu")))
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 10)
	form.add_child(mode_row)
	var mode_definitions := [
		["ffa", Lang.t("🗡️ Chacun pour soi")],
		["chains", Lang.t("⛓️ Les Enchaînés")],
		["teams", Lang.t("⚔️ Équipes")],
	]
	for definition in mode_definitions:
		var mode_button := Button.new()
		mode_button.text = definition[1]
		mode_button.custom_minimum_size = Vector2(0, 40)
		mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiKit.style_button(mode_button, UiKit.ACCENT_BLUE, 16)
		mode_button.pressed.connect(_on_mode_selected.bind(definition[0]))
		mode_row.add_child(mode_button)
		_mode_buttons[definition[0]] = mode_button
	var mode_hint := Label.new()
	mode_hint.text = Lang.t("Enchaînés : paires secrètes, si ton enchaîné meurt tu meurs · Équipes : Rouge vs Bleu, tir ami autorisé (4 joueurs min).")
	mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_hint.modulate = Color(1, 1, 1, 0.5)
	form.add_child(mode_hint)
	_selected_mode = GameConfig.mode
	_refresh_mode_buttons()

	# --- Boutique de chapeaux (l'audace gagnée en jouant sert ici) ---
	_balance_label = _section_label(Lang.t("🎩  Ton chapeau — réserve : ⭐ %d") % GameConfig.audace_bank)
	form.add_child(_balance_label)
	var hat_grid := GridContainer.new()
	hat_grid.columns = 3
	hat_grid.add_theme_constant_override("h_separation", 6)
	hat_grid.add_theme_constant_override("v_separation", 6)
	form.add_child(hat_grid)
	for i in GameConfig.HATS.size():
		var hat_button := Button.new()
		hat_button.custom_minimum_size = Vector2(0, 34)
		hat_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiKit.style_button(hat_button, UiKit.ACCENT_BLUE, 13)
		hat_button.pressed.connect(_on_hat_pressed.bind(i))
		hat_grid.add_child(hat_button)
		_hat_buttons.append(hat_button)
	_refresh_hat_buttons()

	# --- Difficulté des bots ---
	form.add_child(_section_label(Lang.t("🤖  Difficulté des bots")))
	var difficulty_row := HBoxContainer.new()
	difficulty_row.add_theme_constant_override("separation", 6)
	form.add_child(difficulty_row)
	var difficulty_definitions := [
		["facile", Lang.t("😴 Facile")],
		["moyen", Lang.t("🙂 Moyen")],
		["difficile", Lang.t("😈 Difficile")],
		["nightmare", "💀 Nightmare"],
		["celeste", Lang.t("🌟 Céleste")],
	]
	for definition in difficulty_definitions:
		var difficulty_button := Button.new()
		difficulty_button.text = definition[1]
		difficulty_button.custom_minimum_size = Vector2(0, 36)
		difficulty_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiKit.style_button(difficulty_button, UiKit.ACCENT_BLUE, 13)
		difficulty_button.pressed.connect(_on_difficulty_selected.bind(definition[0]))
		difficulty_row.add_child(difficulty_button)
		_difficulty_buttons[definition[0]] = difficulty_button
	_selected_difficulty = GameConfig.difficulty
	_refresh_difficulty_buttons()

	form.add_child(HSeparator.new())

	# --- Solo ---
	var play := Button.new()
	play.text = Lang.t("▶   JOUER EN SOLO")
	play.custom_minimum_size = Vector2(0, 54)
	UiKit.style_button(play, UiKit.ACCENT, 24)
	play.pressed.connect(_on_play_pressed)
	form.add_child(play)

	form.add_child(HSeparator.new())

	# --- Multijoueur ---
	var multi_title := _section_label(Lang.t("🌐  Multijoueur — héberge, ou rejoins avec IP + mot de passe"))
	form.add_child(multi_title)

	_password_edit = LineEdit.new()
	_password_edit.placeholder_text = Lang.t("Mot de passe de la partie (optionnel)")
	_password_edit.custom_minimum_size = Vector2(0, 38)
	form.add_child(_password_edit)

	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = Lang.t("IP de l'hôte (ex : 192.168.1.10) — pour rejoindre")
	_ip_edit.custom_minimum_size = Vector2(0, 38)
	form.add_child(_ip_edit)

	var multi_row := HBoxContainer.new()
	multi_row.add_theme_constant_override("separation", 12)
	form.add_child(multi_row)
	var host_button := Button.new()
	host_button.text = Lang.t("🏠  Héberger")
	host_button.custom_minimum_size = Vector2(0, 46)
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_button(host_button, UiKit.ACCENT_BLUE, 20)
	host_button.pressed.connect(_on_host_pressed)
	multi_row.add_child(host_button)
	var join_button := Button.new()
	join_button.text = Lang.t("🔗  Rejoindre")
	join_button.custom_minimum_size = Vector2(0, 46)
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_button(join_button, UiKit.ACCENT_BLUE, 20)
	join_button.pressed.connect(_on_join_pressed)
	multi_row.add_child(join_button)

	_error_label = Label.new()
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.add_theme_color_override("font_color", Color(1, 0.4, 0.35))
	form.add_child(_error_label)

	# --- Quitter ---
	var quit := Button.new()
	quit.text = Lang.t("Quitter")
	quit.flat = true
	quit.custom_minimum_size = Vector2(0, 34)
	quit.modulate = Color(1, 1, 1, 0.55)
	UiKit.hover_pop(quit)
	quit.pressed.connect(func() -> void: get_tree().quit())
	column.add_child(quit)

	# Numéro de version : pour vérifier d'un coup d'œil que tout le monde
	# a la même release avant une partie.
	var version_label := Label.new()
	version_label.text = GameConfig.VERSION
	version_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version_label.offset_left = -140
	version_label.offset_top = -34
	version_label.offset_right = -12
	version_label.offset_bottom = -10
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version_label.modulate = Color(1, 1, 1, 0.4)
	add_child(version_label)

	# Bouton drapeau (haut droite) : bascule FR/EN puis reconstruit le menu.
	var lang_button := Button.new()
	lang_button.text = Lang.flag_label()
	lang_button.custom_minimum_size = Vector2(128, 52)
	UiKit.style_button(lang_button, UiKit.ACCENT_BLUE, 26)
	lang_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	lang_button.offset_left = -148
	lang_button.offset_top = 16
	lang_button.offset_right = -20
	lang_button.offset_bottom = 68
	lang_button.pressed.connect(func() -> void:
		Lang.toggle()
		get_tree().reload_current_scene.call_deferred())
	add_child(lang_button)

func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(1, 1, 1, 0.8)
	return label

## Entrée en scène : titre puis panneau, avec un léger décalage.
func _animate_entrance() -> void:
	await get_tree().process_frame
	UiKit.pop_in(_title)
	UiKit.pop_in(_panel, 0.12)
	await get_tree().create_timer(0.6).timeout
	UiKit.breathe(_title)

# ---------------------------------------------------------------- Actions

func _on_mode_selected(mode: String) -> void:
	_selected_mode = mode
	_refresh_mode_buttons()

func _refresh_mode_buttons() -> void:
	for mode in _mode_buttons:
		_mode_buttons[mode].modulate.a = 1.0 if mode == _selected_mode else 0.45

## Clic sur un chapeau : le porter s'il est possédé, sinon l'acheter.
func _on_hat_pressed(hat_id: int) -> void:
	if hat_id in GameConfig.unlocked_hats:
		GameConfig.selected_hat = hat_id
		GameConfig.save_progress()
	elif GameConfig.buy_hat(hat_id):
		GameConfig.selected_hat = hat_id
		GameConfig.save_progress()
		Audio.play("win", -8.0)
	else:
		var price: int = GameConfig.HATS[hat_id]["price"]
		_show_error(Lang.t("Il te faut ⭐ %d pour « %s » (réserve : %d). Joue avec audace !")
			% [price, GameConfig.HATS[hat_id]["name"], GameConfig.audace_bank])
	_refresh_hat_buttons()

func _refresh_hat_buttons() -> void:
	_balance_label.text = Lang.t("🎩  Ton chapeau — réserve : ⭐ %d") % GameConfig.audace_bank
	for i in _hat_buttons.size():
		var hat: Dictionary = GameConfig.HATS[i]
		if i in GameConfig.unlocked_hats:
			_hat_buttons[i].text = hat["name"]
			_hat_buttons[i].modulate.a = 1.0 if i == GameConfig.selected_hat else 0.45
		else:
			_hat_buttons[i].text = "🔒 %s (⭐%d)" % [hat["name"], hat["price"]]
			_hat_buttons[i].modulate.a = 0.6

func _on_difficulty_selected(difficulty: String) -> void:
	_selected_difficulty = difficulty
	_refresh_difficulty_buttons()

func _refresh_difficulty_buttons() -> void:
	for difficulty in _difficulty_buttons:
		_difficulty_buttons[difficulty].modulate.a = 1.0 if difficulty == _selected_difficulty else 0.4

func _on_color_selected(index: int) -> void:
	_selected_color = index
	_refresh_color_buttons()

func _refresh_color_buttons() -> void:
	for i in _color_buttons.size():
		_color_buttons[i].modulate.a = 1.0 if i == _selected_color else 0.35

func _apply_settings() -> void:
	var chosen_name := _name_edit.text.strip_edges()
	GameConfig.player_name = chosen_name if not chosen_name.is_empty() else "Player"
	GameConfig.player_count = int(_count_slider.value)
	GameConfig.color_index = _selected_color
	GameConfig.mode = _selected_mode
	GameConfig.difficulty = _selected_difficulty

func _show_error(message: String) -> void:
	_error_label.add_theme_color_override("font_color", Color(1, 0.4, 0.35))
	_error_label.text = message
	# Petit frémissement : l'erreur se voit sans être agressive.
	var tween := _error_label.create_tween()
	_error_label.pivot_offset = _error_label.size / 2.0
	tween.tween_property(_error_label, "rotation", 0.02, 0.05)
	tween.tween_property(_error_label, "rotation", -0.02, 0.05)
	tween.tween_property(_error_label, "rotation", 0.0, 0.05)

func _on_play_pressed() -> void:
	_apply_settings()
	_start_game()

func _on_host_pressed() -> void:
	_apply_settings()
	var error := Net.host_game(Net.DEFAULT_PORT, _password_edit.text.strip_edges(),
		GameConfig.player_name, GameConfig.color_index)
	if error != OK:
		_show_error(Lang.t("Impossible d'ouvrir le port %d (déjà utilisé ?)") % Net.DEFAULT_PORT)
		return
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_join_pressed() -> void:
	if _joining:
		return
	_apply_settings()
	var ip := _extract_ip(_ip_edit.text)
	if ip.is_empty():
		_show_error(Lang.t("Adresse IP invalide. Exemple : 192.168.1.10 (ou 127.0.0.1 sur le même PC)."))
		return
	var error := Net.join_game(ip, Net.DEFAULT_PORT, _password_edit.text.strip_edges(),
		GameConfig.player_name, GameConfig.color_index)
	if error != OK:
		_show_error(Lang.t("Connexion impossible vers « %s ».") % ip)
		return
	_joining = true
	_error_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	_error_label.text = Lang.t("⏳ Connexion à %s…") % ip
	# Chien de garde : sans réponse de l'hôte, on ne reste pas bloqué en silence.
	await get_tree().create_timer(8.0).timeout
	if _joining and is_inside_tree():
		_joining = false
		Net.leave()
		_show_error(Lang.t("Aucune réponse de %s. Vérifie l'IP, le mot de passe, et que l'hôte a bien cliqué Héberger.") % ip)

func _on_joined_lobby() -> void:
	if _joining:
		_joining = false
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_net_join_failed(reason: String) -> void:
	_joining = false
	_show_error(reason)

## Repêche une IP valide même si l'utilisateur colle du texte autour
## (« IP : 192.168.1.10 » → « 192.168.1.10 »).
func _extract_ip(raw: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}")
	var found := regex.search(raw)
	if found != null and found.get_string(0).is_valid_ip_address():
		return found.get_string(0)
	return ""

func _start_game() -> void:
	# Différé : on peut arriver ici pendant que l'arbre construit encore le menu
	# (autoplay/headless), et changer de scène à cet instant est interdit.
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")

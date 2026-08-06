class_name Hud
extends CanvasLayer
## Hud — interface du joueur local, construite par code pour le prototype.
##
## Règle d'or du game design : les PV des AUTRES ne sont jamais affichés.
## On lit leur état sur leur corps (teinte, tremblements, halètement).
## Le HUD ne montre que : SA vie, SA carte (privée), le tour en cours,
## et un journal des événements publics.

const CATEGORY_COLORS := {
	"positive": Color(0.35, 0.85, 0.4),
	"negative": Color(0.9, 0.3, 0.25),
	"neutral": Color(0.75, 0.75, 0.8),
	"legendary": Color(1.0, 0.8, 0.2),
	"utility": Color(0.45, 0.65, 1.0),
}

var local_player: CharacterBase  ## Assigné par main.gd avant l'ajout à l'arbre.

var _hp_bar: ProgressBar
var _hp_label: Label
var _shield_label: Label
var _turn_label: Label
var _card_panel: PanelContainer
var _card_title: Label
var _card_desc: Label
var _log: RichTextLabel
var _root: Control
var _card_tween: Tween
var _hand_slots: Array[Label] = []
var _hand_selected := 0
var _points_label: Label
var _stoning_label: Label
var _stoning_tween: Tween
var _draw_prompt: Label
var _draw_prompt_tween: Tween
var _countdown_label: Label
var _chat_input: LineEdit
var _last_chat_ms := 0
var _alert_label: Label
var _alert_tween: Tween

func _ready() -> void:
	_build_ui()
	# Événements de partie.
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.card_drawn.connect(_on_card_drawn)
	EventBus.match_ended.connect(_on_match_ended)
	EventBus.log_public.connect(_on_log_public)
	EventBus.log_private.connect(_on_log_private)
	EventBus.fake_event.connect(_on_fake_event)
	EventBus.emote_played.connect(_on_emote_played)
	EventBus.status_applied.connect(_on_status_applied)
	EventBus.card_stored.connect(_on_card_stored)
	EventBus.card_used.connect(_on_card_used)
	EventBus.hand_selected.connect(_on_hand_selected)
	EventBus.stalling_started.connect(_on_stalling_started)
	EventBus.stalling_ended.connect(_on_stalling_ended)
	EventBus.countdown_tick.connect(_on_countdown_tick)
	EventBus.chat_message.connect(_on_chat_message)
	EventBus.chain_echo.connect(_on_chain_echo)
	EventBus.points_changed.connect(func(c, points: int) -> void:
		if c == local_player:
			_points_label.text = "⭐ %d point%s d'audace" % [points, "s" if points > 1 else ""])
	# État du joueur local uniquement.
	local_player.health.hp_changed.connect(_on_hp_changed)
	local_player.health.shield_changed.connect(_on_shield_changed)
	local_player.health.damaged.connect(_on_local_damaged)
	local_player.health.healed.connect(_on_local_healed)

# ---------------------------------------------------------------- Construction

func _build_ui() -> void:
	var root := Control.new()
	_root = root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = GameFonts.ui_font()
	theme.default_font_size = 16
	root.theme = theme
	add_child(root)

	# Indicateur de tour (haut, centré).
	_turn_label = Label.new()
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_turn_label.offset_top = 16
	_turn_label.offset_bottom = 52
	_turn_label.add_theme_font_size_override("font_size", 22)
	root.add_child(_turn_label)

	# Bloc vie (bas gauche).
	var hp_box := VBoxContainer.new()
	hp_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hp_box.offset_left = 20
	hp_box.offset_top = -120
	hp_box.offset_right = 300
	hp_box.offset_bottom = -20
	root.add_child(hp_box)

	_hp_label = Label.new()
	_hp_label.text = "❤️ 100 / 100"
	hp_box.add_child(_hp_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.max_value = 100
	_hp_bar.value = 100
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(260, 22)
	hp_box.add_child(_hp_bar)

	_shield_label = Label.new()
	_shield_label.text = ""
	hp_box.add_child(_shield_label)

	_points_label = Label.new()
	_points_label.text = "⭐ 0 point d'audace"
	_points_label.modulate = Color(1, 0.9, 0.5)
	hp_box.add_child(_points_label)

	# Journal des événements (droite).
	var log_panel := PanelContainer.new()
	log_panel.anchor_left = 1.0
	log_panel.anchor_right = 1.0
	log_panel.anchor_top = 0.0
	log_panel.anchor_bottom = 1.0
	log_panel.offset_left = -380
	log_panel.offset_right = -16
	log_panel.offset_top = 60
	log_panel.offset_bottom = -60
	log_panel.modulate = Color(1, 1, 1, 0.85)
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(log_panel)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.add_child(_log)

	# Panneau de carte piochée (bas, centré) — information PRIVÉE.
	_card_panel = PanelContainer.new()
	_card_panel.anchor_left = 0.5
	_card_panel.anchor_right = 0.5
	_card_panel.anchor_top = 1.0
	_card_panel.anchor_bottom = 1.0
	_card_panel.offset_left = -230
	_card_panel.offset_right = 230
	_card_panel.offset_top = -200
	_card_panel.offset_bottom = -80
	_card_panel.visible = false
	root.add_child(_card_panel)

	var card_margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		card_margin.add_theme_constant_override(side, 12)
	_card_panel.add_child(card_margin)

	var card_box := VBoxContainer.new()
	card_margin.add_child(card_box)

	_card_title = Label.new()
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_title.add_theme_font_size_override("font_size", 24)
	card_box.add_child(_card_title)

	_card_desc = Label.new()
	_card_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_box.add_child(_card_desc)

	# Compte à rebours d'échauffement, plein centre.
	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_countdown_label.offset_left = -300
	_countdown_label.offset_right = 300
	_countdown_label.offset_top = -120
	_countdown_label.offset_bottom = 20
	_countdown_label.add_theme_font_size_override("font_size", 88)
	_countdown_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.25))
	_countdown_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_countdown_label.add_theme_constant_override("shadow_offset_y", 4)
	_countdown_label.visible = false
	root.add_child(_countdown_label)

	# Grand rappel de pioche, au centre : impossible de rater son tour.
	_draw_prompt = Label.new()
	_draw_prompt.text = "🎯 À TOI DE PIOCHER !\nESPACE — ou clique sur la pioche qui brille"
	_draw_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_draw_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_draw_prompt.offset_left = -300
	_draw_prompt.offset_right = 300
	_draw_prompt.offset_top = 60
	_draw_prompt.offset_bottom = 160
	_draw_prompt.add_theme_font_size_override("font_size", 30)
	_draw_prompt.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_draw_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_draw_prompt.add_theme_constant_override("shadow_offset_y", 3)
	_draw_prompt.visible = false
	root.add_child(_draw_prompt)

	# Bannière d'alerte générique (écho de chaîne, etc.).
	_alert_label = Label.new()
	_alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_alert_label.offset_left = -320
	_alert_label.offset_right = 320
	_alert_label.offset_top = -140
	_alert_label.offset_bottom = -100
	_alert_label.add_theme_font_size_override("font_size", 26)
	_alert_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_alert_label.add_theme_constant_override("shadow_offset_y", 3)
	_alert_label.visible = false
	root.add_child(_alert_label)

	# Bannière de lapidation : impossible de la rater.
	_stoning_label = Label.new()
	_stoning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stoning_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_stoning_label.offset_top = 60
	_stoning_label.offset_bottom = 104
	_stoning_label.add_theme_font_size_override("font_size", 30)
	_stoning_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.15))
	_stoning_label.visible = false
	root.add_child(_stoning_label)

	# Main de cartes (au-dessus du panneau de carte piochée).
	var hand_box := HBoxContainer.new()
	hand_box.anchor_left = 0.5
	hand_box.anchor_right = 0.5
	hand_box.anchor_top = 1.0
	hand_box.anchor_bottom = 1.0
	hand_box.offset_left = -230
	hand_box.offset_right = 230
	hand_box.offset_top = -240
	hand_box.offset_bottom = -208
	hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_box.add_theme_constant_override("separation", 14)
	root.add_child(hand_box)

	var hand_title := Label.new()
	hand_title.text = "🎴 Main :"
	hand_box.add_child(hand_title)
	for i in CharacterBase.HAND_SIZE:
		var slot := Label.new()
		slot.text = "—"
		hand_box.add_child(slot)
		_hand_slots.append(slot)

	# Champ de chat texte (T pour ouvrir, Entrée pour envoyer, Échap pour fermer).
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Ton message… (Entrée : envoyer · Échap : annuler)"
	_chat_input.max_length = 90
	_chat_input.anchor_left = 0.5
	_chat_input.anchor_right = 0.5
	_chat_input.anchor_top = 1.0
	_chat_input.anchor_bottom = 1.0
	_chat_input.offset_left = -260
	_chat_input.offset_right = 260
	_chat_input.offset_top = -86
	_chat_input.offset_bottom = -48
	_chat_input.visible = false
	_chat_input.text_submitted.connect(_on_chat_submitted)
	_chat_input.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_close_chat()
			get_viewport().set_input_as_handled())
	root.add_child(_chat_input)

	# Point de visée au centre : nécessaire pour cliquer sur la pioche.
	var crosshair := ColorRect.new()
	crosshair.color = Color(1, 1, 1, 0.4)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -2
	crosshair.offset_top = -2
	crosshair.offset_right = 2
	crosshair.offset_bottom = 2
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)

	# Rappel des contrôles (bas, centré).
	var hint := Label.new()
	hint.text = "ESPACE : piocher · R : révéler · clic droit : utiliser · E : se lever · ZQSD : marcher · V : parler · T : chat · 1-4 : émotes · Échap : pause"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -32
	hint.offset_bottom = -10
	hint.modulate = Color(1, 1, 1, 0.55)
	root.add_child(hint)

# ---------------------------------------------------------------- Événements

func _on_turn_started(character) -> void:
	if character == local_player:
		_turn_label.text = "🎯 À TOI — appuie sur ESPACE pour piocher"
		_turn_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		_show_draw_prompt(true)
	else:
		_turn_label.text = "Au tour de %s…" % character.display_name
		_turn_label.add_theme_color_override("font_color", Color.WHITE)
		_show_draw_prompt(false)

func _show_draw_prompt(shown: bool) -> void:
	_draw_prompt.visible = shown
	if _draw_prompt_tween and _draw_prompt_tween.is_valid():
		_draw_prompt_tween.kill()
	if shown:
		_draw_prompt.modulate.a = 1.0
		_draw_prompt_tween = create_tween().set_loops()
		_draw_prompt_tween.tween_property(_draw_prompt, "modulate:a", 0.45, 0.5)
		_draw_prompt_tween.tween_property(_draw_prompt, "modulate:a", 1.0, 0.5)

func _on_card_drawn(character, card: Dictionary) -> void:
	_add_log("🃏 %s pioche une carte…" % character.display_name, Color(0.8, 0.8, 0.85))
	if character == local_player:
		_show_draw_prompt(false)
		_show_card(card)

func _show_card(card: Dictionary) -> void:
	var category: String = card.get("category", "neutral")
	_card_title.text = "%s %s" % [card.get("emoji", ""), card.get("name", "?")]
	_card_title.add_theme_color_override("font_color", CATEGORY_COLORS.get(category, Color.WHITE))
	_card_desc.text = card.get("description", "")
	_card_panel.visible = true
	# Volontairement AUCUNE trace dans le journal : ta carte n'existe nulle part
	# par écrit tant que tu ne la révèles pas toi-même (touche R = +1 point).
	if _card_tween and _card_tween.is_valid():
		_card_tween.kill()
	_card_tween = create_tween()
	_card_tween.tween_interval(5.0)
	_card_tween.tween_callback(func() -> void: _card_panel.visible = false)

func _on_match_ended(winner) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_turn_label.text = ""
	_stoning_label.visible = false
	_show_draw_prompt(false)
	_build_end_screen(winner)

## Écran de fin : voile sombre en fondu, panneau doré, podium animé, boutons.
func _build_end_screen(winner) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.01, 0.03, 0.0)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(overlay)
	var fade := create_tween()
	fade.tween_property(overlay, "color:a", 0.72, 0.6)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel_style())
	panel.custom_minimum_size = Vector2(540, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	# Mode Enchaînés : la victoire peut être PARTAGÉE par toute la chaîne
	# survivante — tous les vivants de la fin sont vainqueurs.
	var winners: Array = []
	if winner != null:
		winners.append(winner)
		if GameConfig.mode == "chains":
			for character in Net.characters:
				if is_instance_valid(character) and character.is_alive() \
						and not character in winners:
					winners.append(character)

	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	if winners.size() > 1:
		var names: Array[String] = []
		for character in winners:
			names.append(character.display_name)
		title.text = "⛓️🏆 %s remportent la partie ENSEMBLE !" % " & ".join(names)
		if local_player in winners:
			title.text += "\n(et TU en fais partie !)"
	elif winner == local_player:
		title.text = "🏆 TU remportes la Dernière Carte !"
	elif winner != null:
		title.text = "🏆 %s remporte la Dernière Carte !" % winner.display_name
	else:
		title.text = "💀 Personne n'a survécu…"
	box.add_child(title)

	box.add_child(HSeparator.new())

	# Classement : les vainqueurs d'abord, puis les autres par audace décroissante.
	var ranked: Array = []
	for character in Net.characters:
		if is_instance_valid(character) and not character in winners:
			ranked.append(character)
	ranked.sort_custom(func(a, b) -> bool: return a.points > b.points)
	for i in range(winners.size() - 1, -1, -1):
		ranked.push_front(winners[i])
	var medals := ["🥇", "🥈", "🥉"]
	var rows: Array[Control] = []
	for i in ranked.size():
		var character = ranked[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var rank := Label.new()
		rank.text = medals[i] if i < medals.size() else " %d." % (i + 1)
		rank.custom_minimum_size = Vector2(42, 0)
		row.add_child(rank)
		var dot := Label.new()
		dot.text = "⬤"
		dot.add_theme_color_override("font_color", character.color)
		row.add_child(dot)
		var name_label := Label.new()
		name_label.text = character.display_name + ("  (toi)" if character == local_player else "")
		if not character.is_alive():
			name_label.text += "  💀"
			name_label.modulate = Color(1, 1, 1, 0.55)
		if i == 0:
			name_label.add_theme_font_size_override("font_size", 22)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var score := Label.new()
		score.text = "⭐ %d" % character.points
		score.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
		row.add_child(score)
		box.add_child(row)
		rows.append(row)

	box.add_child(HSeparator.new())

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var replay := Button.new()
	replay.text = "🔄  Rejouer  (R)"
	replay.custom_minimum_size = Vector2(0, 46)
	replay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_button(replay, UiKit.ACCENT, 20)
	replay.pressed.connect(func() -> void: get_tree().reload_current_scene())
	buttons.add_child(replay)
	var menu_button := Button.new()
	menu_button.text = "🏠  Menu  (M)"
	menu_button.custom_minimum_size = Vector2(0, 46)
	menu_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_button(menu_button, UiKit.ACCENT_BLUE, 20)
	menu_button.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	buttons.add_child(menu_button)

	# Entrée en scène : le panneau, puis les lignes du podium en cascade.
	await get_tree().process_frame
	UiKit.pop_in(panel)
	for i in rows.size():
		UiKit.pop_in(rows[i], 0.15 + i * 0.08)

func _on_log_public(message: String) -> void:
	_add_log(message, Color(0.92, 0.92, 0.97))

func _on_log_private(character, message: String) -> void:
	if character != local_player:
		return
	_add_log(message, Color(0.65, 0.65, 0.7))
	# Frémissement de chaîne : petit tintement + alerte discrète.
	if message.begins_with("⛓️ Ta chaîne frémit"):
		Audio.play("goupille", -8.0)
		_flash_alert("⛓️ Ta chaîne frémit… il est tout près.", Color(0.8, 0.85, 1.0), 1.6)

func _on_fake_event(message: String) -> void:
	# Le faux indice ressemble à un vrai : personne ne sait qu'il ne s'est RIEN passé.
	_add_log(message, Color(1.0, 0.85, 0.5))

func _on_emote_played(character, emote: String) -> void:
	_add_log("%s réagit : %s" % [character.display_name, emote], Color(0.7, 0.8, 1.0))

func _on_status_applied(character, status_name: String) -> void:
	if character == local_player:
		_add_log("⚠️ Statut subi : %s" % status_name, Color(1.0, 0.6, 0.4))

func _on_card_stored(character, card: Dictionary) -> void:
	if character == local_player:
		_add_log("🎴 %s %s gardée en main (clic droit pour l'utiliser)."
			% [card.get("emoji", ""), card.get("name", "?")], Color(0.6, 0.8, 1.0))
		_refresh_hand()

## Une carte utilisée est une action VISIBLE : elle est révélée à tous.
func _on_card_used(user, card: Dictionary, target) -> void:
	if target != null and target != user:
		_add_log("💥 %s lance %s %s sur %s !" % [user.display_name,
			card.get("emoji", ""), card.get("name", "?"), target.display_name],
			Color(1.0, 0.7, 0.4))
	else:
		_add_log("✨ %s utilise %s %s." % [user.display_name,
			card.get("emoji", ""), card.get("name", "?")], Color(0.6, 0.9, 0.7))
	if user == local_player:
		_refresh_hand()

func _on_hand_selected(character, index: int) -> void:
	if character == local_player:
		_hand_selected = index
		_refresh_hand()

func _refresh_hand() -> void:
	_hand_selected = clampi(_hand_selected, 0, maxi(local_player.hand.size() - 1, 0))
	for i in _hand_slots.size():
		var slot := _hand_slots[i]
		if i < local_player.hand.size():
			var card: Dictionary = local_player.hand[i]
			slot.text = "%s %s" % [card.get("emoji", ""), card.get("name", "?")]
			var selected := i == _hand_selected
			slot.modulate = Color(1, 0.9, 0.4) if selected else Color(1, 1, 1, 0.8)
		else:
			slot.text = "—"
			slot.modulate = Color(1, 1, 1, 0.35)

## Alerte flash au centre de l'écran (disparaît d'elle-même).
func _flash_alert(text: String, color: Color, duration := 2.5) -> void:
	_alert_label.text = text
	_alert_label.add_theme_color_override("font_color", color)
	_alert_label.visible = true
	_alert_label.modulate.a = 1.0
	if _alert_tween and _alert_tween.is_valid():
		_alert_tween.kill()
	_alert_tween = create_tween()
	_alert_tween.tween_interval(duration)
	_alert_tween.tween_property(_alert_label, "modulate:a", 0.0, 0.5)
	_alert_tween.tween_callback(func() -> void: _alert_label.visible = false)

## Mode Enchaînés : TON enchaîné vient d'encaisser — impossible à rater.
func _on_chain_echo(character) -> void:
	if character != local_player:
		return
	_flash_alert("🩸 Ton enchaîné vient d'encaisser ! Qui a été touché à l'instant ?",
		Color(1.0, 0.45, 0.45))
	Audio.play("heart", -2.0)
	var second_beat := create_tween()
	second_beat.tween_interval(0.25)
	second_beat.tween_callback(func() -> void: Audio.play("heart", -4.0))

# ---------------------------------------------------------------- Chat texte

func _unhandled_input(event: InputEvent) -> void:
	if EventBus.chat_open or EventBus.pause_open:
		return
	if event.is_action_pressed("open_chat"):
		_open_chat()
		get_viewport().set_input_as_handled()

func _open_chat() -> void:
	EventBus.chat_open = true
	_chat_input.visible = true
	_chat_input.text = ""
	_chat_input.grab_focus()

func _close_chat() -> void:
	EventBus.chat_open = false
	_chat_input.visible = false
	_chat_input.release_focus()

func _on_chat_submitted(text: String) -> void:
	_close_chat()
	var clean := text.strip_edges()
	if clean.is_empty():
		return
	# Anti-spam : un message par seconde et demie.
	var now := Time.get_ticks_msec()
	if now - _last_chat_ms < 1500:
		return
	_last_chat_ms = now
	if Net.client_mode():
		Net.send_chat(clean)
	local_player.say(clean)

func _on_chat_message(character, text: String) -> void:
	_add_log("💬 %s : %s" % [character.display_name, text], character.color.lightened(0.35))

## Échauffement : gros chiffres au centre, cailloux gratuits, puis GO.
func _on_countdown_tick(n: int) -> void:
	_countdown_label.visible = true
	_countdown_label.pivot_offset = _countdown_label.size / 2.0
	if n > 0:
		_countdown_label.text = str(n)
		_turn_label.text = "🪨 ÉCHAUFFEMENT — défoulez-vous, tout sera pardonné !"
		_turn_label.add_theme_color_override("font_color", Color(1, 0.7, 0.3))
		Audio.play("click", -4.0)
	else:
		_countdown_label.text = "🎴 GO !"
		_turn_label.text = ""
		Audio.play("ding", -2.0)
		var tween := create_tween()
		tween.tween_interval(1.0)
		tween.tween_callback(func() -> void: _countdown_label.visible = false)
	var pop := create_tween()
	_countdown_label.scale = Vector2(1.4, 1.4)
	pop.tween_property(_countdown_label, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_stalling_started(lambin) -> void:
	if lambin == local_player:
		_stoning_label.text = "🪨 TU TE FAIS LAPIDER — PIOCHE !! 🪨"
	else:
		_stoning_label.text = "🪨 LAPIDATION AUTORISÉE sur %s ! (clic gauche) 🪨" % lambin.display_name
	_stoning_label.visible = true
	if _stoning_tween and _stoning_tween.is_valid():
		_stoning_tween.kill()
	_stoning_tween = create_tween().set_loops()
	_stoning_tween.tween_property(_stoning_label, "modulate:a", 0.35, 0.4)
	_stoning_tween.tween_property(_stoning_label, "modulate:a", 1.0, 0.4)

func _on_stalling_ended(_lambin) -> void:
	if _stoning_tween and _stoning_tween.is_valid():
		_stoning_tween.kill()
	_stoning_label.visible = false
	_stoning_label.modulate.a = 1.0

func _on_hp_changed(hp: int, max_hp: int) -> void:
	_hp_bar.value = hp
	_hp_label.text = "❤️ %d / %d" % [hp, max_hp]

func _on_shield_changed(shield: int) -> void:
	_shield_label.text = "🛡️ %d" % shield if shield > 0 else ""

func _on_local_damaged(amount: int, source: String) -> void:
	_add_log("💥 -%d PV (%s)" % [amount, source], Color(1.0, 0.45, 0.4))

func _on_local_healed(amount: int) -> void:
	_add_log("💚 +%d PV" % amount, Color(0.5, 1.0, 0.5))

func _add_log(text: String, color: Color = Color(0.9, 0.9, 0.95)) -> void:
	_log.append_text("[color=#%s]%s[/color]\n" % [color.to_html(false), text])

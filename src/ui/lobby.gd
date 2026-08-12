extends Control
## Lobby — salle d'attente avant la partie, habillée avec UiKit.
## L'hôte voit son IP + le mot de passe à partager, la liste des joueurs se
## met à jour en direct, et il lance quand tout le monde est là (les sièges
## restants sont remplis par des bots).

var _players_box: VBoxContainer
var _start_button: Button
var _info_label: Label
var _panel: PanelContainer
var _firewall_label: Label
var _firewall_checks_left := 15  ## ~1 minute de vérifications, puis on lâche.

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
	title.text = Lang.t("🎴 Salle d'attente")
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
		_info_label.text = Lang.t("À partager avec tes amis :\nIP : %s   ·   Mot de passe : %s\n(sur le même PC : 127.0.0.1)") % [
			Net.best_local_ip(),
			Net.password if not Net.password.is_empty() else Lang.t("(aucun)")]
	else:
		_info_label.text = Lang.t("Connecté ! En attente du lancement par l'hôte…")
	box.add_child(_info_label)

	# Invités SANS le jeu : un lien à ouvrir dans leur navigateur, rien à
	# télécharger. Affiché seulement si le partage web a démarré.
	var share_url := Net.web_share_url() if Net.is_server else ""
	if not share_url.is_empty():
		var share_label := Label.new()
		share_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		share_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		share_label.add_theme_color_override("font_color", Color(0.6, 0.95, 0.7))
		share_label.text = Lang.t("🌐 Sans rien installer — ce lien dans leur navigateur :\n%s") % share_url
		box.add_child(share_label)
		var copy := Button.new()
		copy.text = Lang.t("📋  Copier le lien")
		copy.custom_minimum_size = Vector2(0, 38)
		UiKit.style_button(copy, UiKit.ACCENT_BLUE, 16)
		copy.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(share_url)
			copy.text = Lang.t("✅  Lien copié !"))
		box.add_child(copy)
		# Panne nº 1 en pratique : le pare-feu Windows jette les connexions
		# entrantes sans rien dire (les invités voient « site inaccessible »).
		# Le jeu a déjà demandé l'autorisation ; ici on rend compte de l'état.
		_firewall_label = Label.new()
		_firewall_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_firewall_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(_firewall_label)
		_refresh_firewall_label()

	box.add_child(HSeparator.new())

	var players_title := Label.new()
	players_title.text = Lang.t("Joueurs connectés :")
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
	back.text = Lang.t("Quitter le salon")
	back.flat = true
	back.modulate = Color(1, 1, 1, 0.55)
	UiKit.hover_pop(back)
	back.pressed.connect(func() -> void:
		Net.leave()
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	column.add_child(back)

## Autorisation réseau : « c'est bon », « clique Oui », ou la manœuvre manuelle.
## Tant qu'elle manque, on re-teste : l'hôte voit le feu passer au vert sans
## avoir à comprendre ce qui se passe.
func _refresh_firewall_label() -> void:
	if _firewall_label == null:
		return
	if Net.firewall_ok:
		_firewall_label.text = Lang.t("✅ Réseau autorisé — tes amis peuvent entrer.")
		_firewall_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.7))
		return
	_firewall_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.35))
	if Net.firewall_asked:
		_firewall_label.text = Lang.t("⏳ Windows demande d'autoriser le réseau : clique « Oui ». Sans ça, tes amis verront « site inaccessible ».")
	else:
		_firewall_label.text = Lang.t("⚠️ Réseau non autorisé : lance autoriser-pare-feu.bat (clic droit → Exécuter en tant qu'administrateur), sinon tes amis ne pourront pas entrer.")
	# On re-teste tant que ce n'est pas réglé : l'hôte peut cliquer « Oui »
	# à tout moment. La vérification interroge Windows (~0,2 s), donc on
	# l'espace et on s'arrête au bout d'une minute pour ne pas hacher le salon.
	if _firewall_checks_left <= 0:
		return
	_firewall_checks_left -= 1
	await get_tree().create_timer(4.0).timeout
	if not is_inside_tree():
		return
	Net.refresh_firewall_state()
	_refresh_firewall_label()

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
		var suffix := Lang.t("  (hôte)") if int(peer_id) == 1 else ""
		label.text = "⬤ %s%s" % [entry["name"], suffix]
		label.add_theme_color_override("font_color",
			GameConfig.PLAYER_COLORS[int(entry["color"]) % GameConfig.PLAYER_COLORS.size()])
		_players_box.add_child(label)
	if _start_button != null:
		var humans := Net.peers.size()
		var bots := maxi(GameConfig.player_count - humans, 0)
		_start_button.text = Lang.t("🎴  LANCER  (%d joueur%s + %d bot%s)") % [
			humans, "s" if humans > 1 else "", bots, "s" if bots > 1 else ""]

func _on_join_failed(reason: String) -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
	push_warning(Lang.t("Connexion refusée : ") + reason)

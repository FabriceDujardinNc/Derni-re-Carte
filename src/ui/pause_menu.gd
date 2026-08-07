extends CanvasLayer
## Menu pause (Échap) — options et sorties.
## La partie CONTINUE derrière (jeu social : on ne fige pas les autres) ;
## seules les entrées gameplay du joueur local sont coupées (EventBus.pause_open).

var _root: Control
var _panel: PanelContainer
var _note: Label
var _previous_time_scale := 1.0

func _ready() -> void:
	layer = 10  # au-dessus du HUD.
	_build_ui()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.make_theme()
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiKit.panel_style())
	_panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)

	var title := Label.new()
	title.text = Lang.t("⏸️  Pause")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	box.add_child(title)

	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.modulate = Color(1, 1, 1, 0.6)
	box.add_child(_note)

	box.add_child(HSeparator.new())

	# --- Volume ---
	var volume_label := Label.new()
	volume_label.text = Lang.t("🔊  Volume : %d %%") % int(GameConfig.volume * 100)
	box.add_child(volume_label)
	var volume_slider := HSlider.new()
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 5
	volume_slider.value = GameConfig.volume * 100
	volume_slider.custom_minimum_size = Vector2(0, 26)
	volume_slider.value_changed.connect(func(value: float) -> void:
		GameConfig.volume = value / 100.0
		volume_label.text = Lang.t("🔊  Volume : %d %%") % int(value)
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(GameConfig.volume, 0.0001)))
		AudioServer.set_bus_mute(0, GameConfig.volume <= 0.0))
	box.add_child(volume_slider)

	# --- Sensibilité souris ---
	var sensitivity_label := Label.new()
	sensitivity_label.text = Lang.t("🖱️  Sensibilité souris : ×%.1f") % GameConfig.mouse_sensitivity
	box.add_child(sensitivity_label)
	var sensitivity_slider := HSlider.new()
	sensitivity_slider.min_value = 0.4
	sensitivity_slider.max_value = 2.0
	sensitivity_slider.step = 0.1
	sensitivity_slider.value = GameConfig.mouse_sensitivity
	sensitivity_slider.custom_minimum_size = Vector2(0, 26)
	sensitivity_slider.value_changed.connect(func(value: float) -> void:
		GameConfig.mouse_sensitivity = value
		sensitivity_label.text = Lang.t("🖱️  Sensibilité souris : ×%.1f") % value)
	box.add_child(sensitivity_slider)

	# --- Voix ---
	var mic_check := CheckButton.new()
	mic_check.text = Lang.t("🎤  Micro activé (maintenir V pour parler)")
	mic_check.button_pressed = GameConfig.voice_enabled
	mic_check.toggled.connect(func(pressed: bool) -> void:
		Voice.set_microphone_enabled(pressed))
	box.add_child(mic_check)

	var voice_label := Label.new()
	voice_label.text = Lang.t("🗣️  Volume des voix : %d %%") % int(GameConfig.voice_volume * 100)
	box.add_child(voice_label)
	var voice_slider := HSlider.new()
	voice_slider.min_value = 0
	voice_slider.max_value = 100
	voice_slider.step = 5
	voice_slider.value = GameConfig.voice_volume * 100
	voice_slider.custom_minimum_size = Vector2(0, 26)
	voice_slider.value_changed.connect(func(value: float) -> void:
		GameConfig.voice_volume = value / 100.0
		voice_label.text = Lang.t("🗣️  Volume des voix : %d %%") % int(value))
	box.add_child(voice_slider)

	# --- Plein écran ---
	var fullscreen_check := CheckButton.new()
	fullscreen_check.text = Lang.t("🖥️  Plein écran")
	fullscreen_check.button_pressed = GameConfig.fullscreen
	fullscreen_check.toggled.connect(func(pressed: bool) -> void:
		GameConfig.fullscreen = pressed
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED))
	box.add_child(fullscreen_check)

	box.add_child(HSeparator.new())

	# --- Sorties ---
	var resume := Button.new()
	resume.text = Lang.t("▶   Reprendre")
	resume.custom_minimum_size = Vector2(0, 48)
	UiKit.style_button(resume, UiKit.ACCENT, 20)
	resume.pressed.connect(func() -> void: set_open(false))
	box.add_child(resume)

	var to_menu := Button.new()
	to_menu.text = Lang.t("🏠  Menu principal")
	to_menu.custom_minimum_size = Vector2(0, 42)
	UiKit.style_button(to_menu, UiKit.ACCENT_BLUE, 18)
	to_menu.pressed.connect(func() -> void:
		EventBus.pause_open = false
		Engine.time_scale = _previous_time_scale  # ne jamais fuir en laissant le temps figé.
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	box.add_child(to_menu)

	var quit := Button.new()
	quit.text = Lang.t("Quitter le jeu")
	quit.flat = true
	quit.modulate = Color(1, 1, 1, 0.55)
	UiKit.hover_pop(quit)
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)

func _unhandled_input(event: InputEvent) -> void:
	if EventBus.chat_open:
		return  # Échap ferme le chat (géré par le HUD), pas le menu.
	if event.is_action_pressed("ui_cancel"):
		set_open(not _root.visible)
		get_viewport().set_input_as_handled()

func set_open(open: bool) -> void:
	_root.visible = open
	EventBus.pause_open = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if Net.active:
		# Multijoueur : PAS de vraie pause — la table continue, et toi aussi
		# tu restes vulnérable. Aucune échappatoire par le menu.
		_note.text = Lang.t("⚠️ La partie continue : tu restes vulnérable à la table !")
	elif open:
		# Solo : vraie pause — le temps s'arrête (bots, poisons, minuteurs).
		_note.text = Lang.t("(jeu en pause)")
		_previous_time_scale = Engine.time_scale
		Engine.time_scale = 0.0
	else:
		Engine.time_scale = _previous_time_scale
